using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using Park.Core.Configuration;

namespace Park.Core.Localization;

public static partial class L
{
    private static readonly Lock Sync = new();
    private static Dictionary<string, Dictionary<string, string>> _catalog = new(StringComparer.Ordinal);
    private static HashSet<string> _knownBaseKeys = new(StringComparer.Ordinal);
    private static string _currentLocale = "zh-Hans";
    private static bool _loaded;

    public static event Action? LocaleChanged;

    public static string CurrentLocale
    {
        get { lock (Sync) return _currentLocale; }
    }

    public static bool IsRtl => string.Equals(CurrentLocale, "ar", StringComparison.OrdinalIgnoreCase);

    public static void Initialize(string? preferredLocale = null)
    {
        var loaded = new Dictionary<string, Dictionary<string, string>>(StringComparer.Ordinal);
        var assetsRoot = AppPaths.AssetsRoot;

        foreach (var spec in PublicContract.Languages)
        {
            var merged = new Dictionary<string, string>(StringComparer.Ordinal);
            MergeJsonFile(merged, Path.Combine(assetsRoot, "i18n", $"{spec.Id}.json"));
            MergeJsonFile(merged, Path.Combine(assetsRoot, "windows-locales", $"{spec.Id}.json"));
            loaded[spec.Id] = merged;
        }

        lock (Sync)
        {
            _catalog = loaded;
            _knownBaseKeys = loaded.TryGetValue("zh-Hans", out var zh)
                ? new HashSet<string>(zh.Keys, StringComparer.Ordinal)
                : new HashSet<string>(StringComparer.Ordinal);
            _loaded = true;
            _currentLocale = ResolveSupportedLocale(preferredLocale);
        }
    }

    public static void SetLocale(string? localeId)
    {
        var resolved = ResolveSupportedLocale(localeId);
        bool changed;
        lock (Sync)
        {
            if (!_loaded) Initialize(resolved);
            changed = !string.Equals(_currentLocale, resolved, StringComparison.Ordinal);
            _currentLocale = resolved;
        }
        if (changed) LocaleChanged?.Invoke();
    }

    public static string ResolveSupportedLocale(string? requested)
    {
        if (!string.IsNullOrWhiteSpace(requested))
        {
            foreach (var lang in PublicContract.Languages)
            {
                if (string.Equals(lang.Id, requested, StringComparison.OrdinalIgnoreCase))
                    return lang.Id;
            }
        }

        var ui = CultureInfo.CurrentUICulture;
        if (ui.Name.StartsWith("zh", StringComparison.OrdinalIgnoreCase))
        {
            return ui.Name.Contains("Hant", StringComparison.OrdinalIgnoreCase) ||
                   ui.Name.EndsWith("-TW", StringComparison.OrdinalIgnoreCase) ||
                   ui.Name.EndsWith("-HK", StringComparison.OrdinalIgnoreCase) ||
                   ui.Name.EndsWith("-MO", StringComparison.OrdinalIgnoreCase)
                ? "zh-Hant"
                : "zh-Hans";
        }

        foreach (var lang in PublicContract.Languages)
        {
            if (string.Equals(lang.Id, ui.TwoLetterISOLanguageName, StringComparison.OrdinalIgnoreCase))
                return lang.Id;
        }

        return "en";
    }

    public static bool HasMessage(string template)
    {
        lock (Sync)
        {
            if (!_loaded) Initialize();
            return _knownBaseKeys.Contains(template);
        }
    }

    public static string Tr(string key, IReadOnlyDictionary<string, object?>? args = null)
    {
        string template;
        lock (Sync)
        {
            if (!_loaded) Initialize();
            template = _catalog.TryGetValue(_currentLocale, out var dict) && dict.TryGetValue(key, out var translated)
                ? translated
                : key;
        }
        return FormatPlaceholders(template, args);
    }

    /// <summary>
    /// Lookup chain per SOURCE_API.md:
    /// Plugin i18n[current] -> Plugin i18n['en'] (except zh-Hans) -> App catalog -> Raw text.
    /// </summary>
    public static string TranslatePlugin(
        IReadOnlyDictionary<string, IReadOnlyDictionary<string, string>>? pluginI18n,
        string rawKey,
        IReadOnlyDictionary<string, string>? args = null)
    {
        if (string.IsNullOrEmpty(rawKey)) return string.Empty;
        var locale = CurrentLocale;
        string? resolved = null;

        if (pluginI18n is not null)
        {
            if (pluginI18n.TryGetValue(locale, out var currentDict) && currentDict.TryGetValue(rawKey, out var hit) && !string.IsNullOrEmpty(hit))
            {
                resolved = hit;
            }
            else if (!string.Equals(locale, "zh-Hans", StringComparison.Ordinal) &&
                     pluginI18n.TryGetValue("en", out var enDict) &&
                     enDict.TryGetValue(rawKey, out var enHit) &&
                     !string.IsNullOrEmpty(enHit))
            {
                resolved = enHit;
            }
        }

        if (resolved is null)
        {
            lock (Sync)
            {
                if (!_loaded) Initialize();
                if (_catalog.TryGetValue(locale, out var appDict) && appDict.TryGetValue(rawKey, out var appHit))
                {
                    resolved = appHit;
                }
            }
        }

        resolved ??= rawKey;
        if (args is null || args.Count == 0) return resolved;

        return PlaceholderRegex().Replace(resolved, match =>
        {
            var token = match.Groups[1].Value;
            return args.TryGetValue(token, out var val) ? val ?? string.Empty : match.Value;
        });
    }

    public static string FormatPlaceholders(string template, IReadOnlyDictionary<string, object?>? args)
    {
        if (args is null || args.Count == 0) return template;
        return PlaceholderRegex().Replace(template, match =>
        {
            var token = match.Groups[1].Value;
            return args.TryGetValue(token, out var val) ? Convert.ToString(val, CultureInfo.InvariantCulture) ?? string.Empty : match.Value;
        });
    }

    public static string FormatBytes(long bytes) => bytes switch
    {
        >= 1L << 30 => $"{bytes / (double)(1L << 30):F2} GB",
        >= 1L << 20 => $"{bytes / (double)(1L << 20):F1} MB",
        >= 1L << 10 => $"{bytes / (double)(1L << 10):F0} KB",
        _ => $"{bytes} B",
    };

    public static string FormatCount(long? count)
    {
        if (count is null) return string.Empty;
        var n = count.Value;
        var locale = CurrentLocale;
        if (locale.StartsWith("zh", StringComparison.Ordinal) || locale is "ja" or "ko")
        {
            if (n >= 100_000_000)
                return Tr("{value0}亿", new Dictionary<string, object?> { ["value0"] = (n / 100_000_000.0).ToString("F1", CultureInfo.InvariantCulture) });
            if (n >= 10_000)
                return Tr("{value0}万", new Dictionary<string, object?> { ["value0"] = (n / 10_000.0).ToString(n >= 100_000 ? "F0" : "F1", CultureInfo.InvariantCulture) });
        }
        if (n >= 1_000_000) return $"{n / 1_000_000.0:F1}M";
        if (n >= 1_000) return $"{n / 1_000.0:F1}k";
        return n.ToString(CultureInfo.InvariantCulture);
    }

    public static string DomainDisplayName(string category) => category switch
    {
        "feed" => Tr("吃瓜"),
        "gallery" => Tr("三次元美图"),
        "illustration" => Tr("二次元美图"),
        "doujin" => Tr("本子"),
        "anime" => Tr("里番"),
        "jav" => "JAV",
        "adult" => Tr("成人视频"),
        "shortvideo" => Tr("短视频"),
        "aiDrama" => Tr("AI短剧"),
        "recording" => Tr("录播"),
        "live" => Tr("直播"),
        "asmr" => Tr("音声"),
        "novel" => Tr("小说"),
        "tavern" => Tr("酒馆"),
        "onlineGame" => Tr("在线游戏"),
        "game" => Tr("游戏资源"),
        "other" => Tr("创作社区"),
        _ => category,
    };

    private static void MergeJsonFile(Dictionary<string, string> target, string path)
    {
        if (!File.Exists(path)) return;
        using var stream = File.OpenRead(path);
        using var doc = JsonDocument.Parse(stream);
        if (doc.RootElement.ValueKind != JsonValueKind.Object) return;
        foreach (var prop in doc.RootElement.EnumerateObject())
        {
            if (prop.Value.ValueKind == JsonValueKind.String)
            {
                var value = prop.Value.GetString();
                if (!string.IsNullOrEmpty(value))
                {
                    target[prop.Name] = value;
                }
            }
        }
    }

    [GeneratedRegex(@"\{(\w+)\}")]
    private static partial Regex PlaceholderRegex();
}
