using System.Text.Json;
using System.Text.Json.Nodes;

namespace Park.Core.Configuration;

public enum SettingsDomain
{
    Appearance,
    Reader,
    Novel,
    ShortVideo,
    Video,
    Network,
    Privacy,
    Library,
    Subscriptions,
    Search,
    Filter,
    Maintenance,
}

public enum ReaderPageMode
{
    Vertical = 0,
    LeftToRight = 1,
    RightToLeft = 2,
}

public sealed class AppSettings
{
    public static AppSettings Instance { get; } = new();

    private static readonly IReadOnlyDictionary<SettingsDomain, HashSet<string>> DomainKeys =
        new Dictionary<SettingsDomain, HashSet<string>>
        {
            [SettingsDomain.Appearance] =
            [
                "themeMode", "seedColor", "useSystemAccent", "language", "refreshRate",
                "gridColumns", "albumColumns", "albumCollapsed", "desktopScale",
                "domainOrder", "homeCategories", "homeDimension", "homeMedia",
                "homeSources", "homeExpandedDomains", "homeHiddenSources",
            ],
            [SettingsDomain.Reader] =
            [
                "readerMode", "preloadPages", "keepScreenOn", "volumeKeyPaging",
                "tapToPage", "readerDual", "readerCoverSingle", "readerSplitWide",
                "readerCrop", "readerDim", "readerWarm", "readerGrayscale", "readerInvert",
                "readerTapLayout", "readerTapInvertH", "readerTapInvertV", "readerBackground",
                "readerShowPageNumber", "readerOrientation", "readerAnimate", "readerGap",
            ],
            [SettingsDomain.Novel] =
            [
                "novelAnimate", "novelAutoScroll", "novelBold", "novelBrightness",
                "novelDim", "novelFont", "novelFontSize", "novelIndent", "novelJustify",
                "novelKeepScreenOn", "novelLetterSpacing", "novelLineHeight", "novelMargin",
                "novelMode", "novelTwoColumn", "novelOrientation", "novelParagraphGap",
                "novelShowStatus", "novelSpeechRate", "novelTapToPage", "novelTheme", "novelVolumeKeys",
            ],
            [SettingsDomain.ShortVideo] = ["shortVideoPreloadCount", "shortVideoRetainedCount"],
            [SettingsDomain.Video] = ["danmakuArea", "voiceBackgroundPlayback"],
            [SettingsDomain.Network] =
            [
                "dataSavingMode", "proxy", "imageConcurrency", "cacheLimitMb",
                "downloadConcurrency", "downloadSiteConcurrency", "downloadTaskConcurrency",
                "downloadWifiOnly", "downloadDirectory", "pdfPagesPerFile",
            ],
            [SettingsDomain.Privacy] =
            [
                "blurCovers", "secureScreen", "incognito", "appLock", "appLockAfter",
                "adultConfirmed", "onboarded", "replyWithoutAsking",
            ],
            [SettingsDomain.Library] =
            [
                "askCategoryOnFavorite", "librarySort", "librarySortAsc",
                "libraryDisplay", "historyDisplay", "downloadDisplay",
                "libraryFilterDownloaded", "libraryFilterUnread", "libraryFilterSources",
                "libraryFilterKind", "badgeUnread", "badgeDownloaded", "badgeSource",
                "libraryUpdateHours", "lastLibraryUpdate", "updateOnlyMultiChapter",
                "updateSkipUnread", "updateSkipNotStarted", "autoDownloadNew", "deleteAfterRead",
            ],
            [SettingsDomain.Subscriptions] =
            [
                "subscriptionUpdateHours", "subscriptionNotifications", "subscriptionNotificationPreview",
            ],
            [SettingsDomain.Search] =
            [
                "rememberedFilters", "rankingSelection", "searchHistories", "tagDownloadReminders",
                "tagDownloadIgnoredSources", "aggregateExcluded", "autoTranslateContent",
                "translateEngine", "translateTargets",
            ],
            [SettingsDomain.Filter] =
            [
                "blockedTags", "blockedTagAliases", "blockPresets", "blockedWorks", "blockedAuthors",
            ],
            [SettingsDomain.Maintenance] =
            [
                "logMode", "autoSourceUpdates", "autoAppUpdates", "ignoredAppUpdate",
                "ignoredSourceUpdates", "lastSourceUpdate", "autoBackupHours",
                "autoBackupKeep", "lastAutoBackup", "closeToTray",
            ],
        };

    private readonly Lock _lock = new();
    private JsonObject _values = [];
    private Task _pendingWrite = Task.CompletedTask;

    public const uint DefaultSeedColor = 0xFFC96442;

    public static IReadOnlyList<(uint Argb, string LabelKey)> PresetAccents { get; } =
    [
        (0xFFC96442, "陶土"),
        (0xFFB8862F, "琥珀"),
        (0xFF5F8A62, "青苔"),
        (0xFF4F6FB8, "靛蓝"),
        (0xFF8A5C9E, "梅紫"),
        (0xFFC25878, "樱粉"),
    ];

    public event Action<SettingsDomain, string>? Changed;

    public bool FreshInstall { get; private set; }

    public async Task LoadAsync(CancellationToken ct = default)
    {
        AppPaths.EnsureDirectories();
        var path = AppPaths.SettingsFile;
        if (!File.Exists(path))
        {
            lock (_lock)
            {
                _values = [];
                FreshInstall = true;
            }
            return;
        }

        var raw = await File.ReadAllTextAsync(path, ct).ConfigureAwait(false);
        JsonNode? parsed;
        try
        {
            parsed = JsonNode.Parse(raw);
        }
        catch (JsonException)
        {
            // Preserve damaged original file with unique name per DEVELOPMENT.md
            var backupCorrupt = $"{path}.corrupt.{DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}";
            File.Copy(path, backupCorrupt, overwrite: false);
            throw;
        }

        lock (_lock)
        {
            _values = parsed as JsonObject ?? [];
            FreshInstall = _values.Count == 0;
        }
    }

    public JsonObject? RememberedFilters(string scope)
    {
        lock (_lock)
            return (_values["rememberedFilters"] as JsonObject)?[scope]?.DeepClone() as JsonObject;
    }

    public void RememberFilters(string scope, JsonObject? preset)
    {
        lock (_lock)
        {
            var all = (_values["rememberedFilters"]?.DeepClone() as JsonObject) ?? new JsonObject();
            if (preset is null) all.Remove(scope);
            else all[scope] = preset.DeepClone();
            SetNode("rememberedFilters", all);
        }
    }

    public string ThemeMode
    {
        get => GetString("themeMode", "dark");
        set => Set("themeMode", value);
    }

    public uint SeedColor
    {
        get => (uint)GetInt64("seedColor", DefaultSeedColor);
        set => Set("seedColor", (long)value);
    }

    public bool UseSystemAccent
    {
        get => GetBool("useSystemAccent", false);
        set => Set("useSystemAccent", value);
    }

    public string Language
    {
        get => GetString("language", string.Empty);
        set => Set("language", value);
    }

    public int GridColumns
    {
        get => Math.Clamp(GetInt32("gridColumns", 0), 0, 10);
        set => Set("gridColumns", Math.Clamp(value, 0, 10));
    }

    public string HomeDimension
    {
        get => GetString("homeDimension", "all");
        set => Set("homeDimension", value);
    }

    public string HomeMedia
    {
        get => GetString("homeMedia", "all");
        set => Set("homeMedia", value);
    }

    public ReaderPageMode ReaderMode
    {
        get => (ReaderPageMode)Math.Clamp(GetInt32("readerMode", 0), 0, 2);
        set => Set("readerMode", (int)value);
    }

    public bool ReaderDual
    {
        get => GetBool("readerDual", false);
        set => Set("readerDual", value);
    }

    public bool ReaderCoverSingle
    {
        get => GetBool("readerCoverSingle", true);
        set => Set("readerCoverSingle", value);
    }

    public double ReaderDim
    {
        get => Math.Clamp(GetDouble("readerDim", 0.0), 0.0, 0.75);
        set => Set("readerDim", Math.Clamp(value, 0.0, 0.75));
    }

    public double ReaderWarm
    {
        get => Math.Clamp(GetDouble("readerWarm", 0.0), 0.0, 0.6);
        set => Set("readerWarm", Math.Clamp(value, 0.0, 0.6));
    }

    public int NovelFontSize
    {
        get => Math.Clamp(GetInt32("novelFontSize", 18), 12, 36);
        set => Set("novelFontSize", Math.Clamp(value, 12, 36));
    }

    public string NovelFont
    {
        get => GetString("novelFont", "serif");
        set => Set("novelFont", value);
    }

    public string NovelTheme
    {
        get => GetString("novelTheme", "paper");
        set => Set("novelTheme", value);
    }

    public bool NovelTwoColumn
    {
        get => GetBool("novelTwoColumn", true);
        set => Set("novelTwoColumn", value);
    }

    public string Proxy
    {
        get => GetString("proxy", string.Empty);
        set => Set("proxy", value.Trim());
    }

    public bool DataSavingMode
    {
        get => GetBool("dataSavingMode", false);
        set => Set("dataSavingMode", value);
    }

    public int DownloadSiteConcurrency
    {
        get => Math.Clamp(GetInt32("downloadSiteConcurrency", 3), 1, 8);
        set => Set("downloadSiteConcurrency", Math.Clamp(value, 1, 8));
    }

    public int DownloadTaskConcurrency
    {
        get => Math.Clamp(GetInt32("downloadTaskConcurrency", 1), 1, 8);
        set => Set("downloadTaskConcurrency", Math.Clamp(value, 1, 8));
    }

    public int DownloadConcurrency
    {
        get => Math.Clamp(GetInt32("downloadConcurrency", 3), 1, 8);
        set => Set("downloadConcurrency", Math.Clamp(value, 1, 8));
    }

    public string DownloadDirectory
    {
        get => GetString("downloadDirectory", AppPaths.DefaultDownloadsDir);
        set => Set("downloadDirectory", value);
    }

    public bool BlurCovers
    {
        get => GetBool("blurCovers", false);
        set => Set("blurCovers", value);
    }

    public bool SecureScreen
    {
        get => GetBool("secureScreen", false);
        set => Set("secureScreen", value);
    }

    public bool Incognito
    {
        get => GetBool("incognito", false);
        set => Set("incognito", value);
    }

    public bool AppLock
    {
        get => GetBool("appLock", false);
        set => Set("appLock", value);
    }

    public int AppLockAfter
    {
        get => Math.Clamp(GetInt32("appLockAfter", 60), 0, 86400);
        set => Set("appLockAfter", Math.Clamp(value, 0, 86400));
    }

    public bool AdultConfirmed
    {
        get => GetBool("adultConfirmed", false);
        set => Set("adultConfirmed", value);
    }

    public bool Onboarded
    {
        get => GetBool("onboarded", false);
        set => Set("onboarded", value);
    }

    public bool CloseToTray
    {
        get => GetBool("closeToTray", false);
        set => Set("closeToTray", value);
    }

    public int AutoBackupHours
    {
        get => Math.Clamp(GetInt32("autoBackupHours", 0), 0, 720);
        set => Set("autoBackupHours", Math.Clamp(value, 0, 720));
    }

    public int AutoBackupKeep
    {
        get => Math.Clamp(GetInt32("autoBackupKeep", 5), 1, 50);
        set => Set("autoBackupKeep", Math.Clamp(value, 1, 50));
    }

    public long LastAutoBackup
    {
        get => GetInt64("lastAutoBackup", 0);
        set => Set("lastAutoBackup", value);
    }

    public IReadOnlyList<string> BlockedTags
    {
        get => GetStringList("blockedTags");
        set
        {
            var arr = new JsonArray(value.Where(s => !string.IsNullOrWhiteSpace(s)).Distinct(StringComparer.OrdinalIgnoreCase).Select(s => JsonValue.Create(s)).ToArray());
            SetNode("blockedTags", arr);
        }
    }

    public IReadOnlyList<string> DomainOrder
    {
        get
        {
            var stored = GetStringList("domainOrder");
            if (stored.Count == 0) return PublicContract.DefaultDomainOrder;
            var result = stored.Where(d => PublicContract.Categories.Contains(d)).ToList();
            foreach (var def in PublicContract.DefaultDomainOrder)
            {
                if (!result.Contains(def)) result.Add(def);
            }
            return result;
        }
        set => SetNode("domainOrder", new JsonArray(value.Select(v => JsonValue.Create(v)).ToArray()));
    }

    public JsonObject ExportJson()
    {
        lock (_lock)
        {
            var copy = (JsonObject)_values.DeepClone();
            // Adult confirmation and machine-local download path stay local per DEVELOPMENT.md
            copy.Remove("adultConfirmed");
            copy.Remove("onboarded");
            copy.Remove("downloadDirectory");
            return copy;
        }
    }

    public JsonObject PrepareImport(JsonObject incoming)
    {
        lock (_lock)
        {
            var merged = (JsonObject)_values.DeepClone();
            foreach (var kv in incoming)
            {
                if (kv.Key is "adultConfirmed" or "onboarded" or "downloadDirectory")
                    continue;
                merged[kv.Key] = kv.Value?.DeepClone();
            }
            return merged;
        }
    }

    public async Task FlushAsync(CancellationToken ct = default)
    {
        Task pending;
        JsonObject snapshot;
        lock (_lock)
        {
            pending = _pendingWrite;
            snapshot = (JsonObject)_values.DeepClone();
        }
        await pending.ConfigureAwait(false);
        await AppPaths.WriteTextAtomicAsync(AppPaths.SettingsFile, snapshot.ToJsonString(new JsonSerializerOptions { WriteIndented = true }), ct).ConfigureAwait(false);
    }

    public static SettingsDomain? DomainOf(string key)
    {
        foreach (var (domain, keys) in DomainKeys)
        {
            if (keys.Contains(key)) return domain;
        }
        return null;
    }

    private string GetString(string key, string fallback)
    {
        lock (_lock)
        {
            return _values[key] is JsonValue v && v.TryGetValue<string>(out var s) ? s : fallback;
        }
    }

    private bool GetBool(string key, bool fallback)
    {
        lock (_lock)
        {
            return _values[key] is JsonValue v && v.TryGetValue<bool>(out var b) ? b : fallback;
        }
    }

    private int GetInt32(string key, int fallback)
    {
        lock (_lock)
        {
            return _values[key] is JsonValue v && v.TryGetValue<int>(out var i) ? i : fallback;
        }
    }

    private long GetInt64(string key, long fallback)
    {
        lock (_lock)
        {
            return _values[key] is JsonValue v && v.TryGetValue<long>(out var l) ? l : fallback;
        }
    }

    private double GetDouble(string key, double fallback)
    {
        lock (_lock)
        {
            return _values[key] is JsonValue v && v.TryGetValue<double>(out var d) ? d : fallback;
        }
    }

    private List<string> GetStringList(string key)
    {
        lock (_lock)
        {
            if (_values[key] is not JsonArray arr) return [];
            var res = new List<string>(arr.Count);
            foreach (var item in arr)
            {
                if (item is JsonValue v && v.TryGetValue<string>(out var s) && !string.IsNullOrWhiteSpace(s))
                    res.Add(s);
            }
            return res;
        }
    }

    private void Set<T>(string key, T value) => SetNode(key, JsonValue.Create(value));

    private void SetNode(string key, JsonNode? node)
    {
        SettingsDomain domain;
        JsonObject snapshot;
        lock (_lock)
        {
            if (JsonNode.DeepEquals(_values[key], node)) return;
            _values[key] = node;
            domain = DomainOf(key) ?? SettingsDomain.Maintenance;
            snapshot = (JsonObject)_values.DeepClone();
            _pendingWrite = _pendingWrite.ContinueWith(async _ =>
            {
                try
                {
                    await AppPaths.WriteTextAtomicAsync(
                        AppPaths.SettingsFile,
                        snapshot.ToJsonString(new JsonSerializerOptions { WriteIndented = true })).ConfigureAwait(false);
                }
                catch
                {
                    // Retained in memory; explicit FlushAsync surfaces failures.
                }
            }).Unwrap();
        }
        Changed?.Invoke(domain, key);
    }
}
