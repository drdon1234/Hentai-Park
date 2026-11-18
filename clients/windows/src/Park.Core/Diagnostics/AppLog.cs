using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Park.Core.Configuration;
using Park.Core.Localization;
using Park.Core.Models;

namespace Park.Core.Diagnostics;

/// <summary>
/// Strict whitelist diagnostics sanitizer aligned with lib/core/diagnostics.dart.
/// Never records credentials, cookies, tokens, work titles, local paths, signed URLs, or arbitrary exception strings.
/// </summary>
public static partial class DiagnosticsSanitizer
{
    public static readonly IReadOnlySet<string> AllowedCodes = new HashSet<string>(StringComparer.Ordinal)
    {
        "NETWORK", "TIMEOUT", "AUTH", "PARSE", "CONFIG", "UNSUPPORTED", "HTTP",
        "CANCELLED", "UNKNOWN", "CLOUDFLARE", "CONFIRM_REQUIRED", "LOGIN_REQUIRED",
        "NOT_FOUND", "BLOCKED",
    };

    public static readonly IReadOnlySet<string> AllowedReasons = new HashSet<string>(StringComparer.Ordinal)
    {
        "TLS_CERTIFICATE", "TLS_HANDSHAKE_TERMINATED", "TLS_HANDSHAKE", "DNS",
        "PRIVATE_ADDRESS", "CONNECTION", "FIREWALL_BLOCKED", "CONNECT_TIMEOUT",
        "RECEIVE_TIMEOUT", "SEND_TIMEOUT", "RESPONSE_STREAM", "UPSTREAM_EMPTY",
        "NO_VIDEO", "EMPTY_RESULT", "CONTENT_FILTERED", "SEARCH_ONLY", "NETWORK",
        "CANCELLED", "UNKNOWN", "NATIVE_CRASH", "LOW_MEMORY", "EXIT_SELF",
        "USER_REQUESTED", "INITIALIZATION_FAILURE", "OTHER",
    };

    private static readonly IReadOnlySet<string> AllowedMethods = new HashSet<string>(StringComparer.Ordinal)
    {
        "GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS",
    };

    private static readonly IReadOnlySet<string> AllowedStages = new HashSet<string>(StringComparer.Ordinal)
    {
        "open", "navigation", "page", "credentials", "verify", "complete", "close",
    };

    private static readonly IReadOnlySet<string> AllowedOutcomes = new HashSet<string>(StringComparer.Ordinal)
    {
        "started", "complete", "waiting", "hit", "miss", "ready", "missing",
        "blocked", "challenge", "success", "failure", "cancelled",
    };

    private static readonly string[] NumericKeys =
    [
        "requestId", "elapsedMs", "attempt", "bytes", "items", "generation",
    ];

    public static Dictionary<string, string> FromError(Exception error)
    {
        if (error is not SourceError se)
        {
            return new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["type"] = NonIdentRegex().Replace(error.GetType().Name, string.Empty),
            };
        }

        var map = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["code"] = se.Code,
            ["message"] = se.RawMessage,
        };
        if (se.Status is { } st) map["status"] = st.ToString();
        foreach (var (k, v) in se.Diagnostics) map[k] = v;
        return map;
    }

    public static Dictionary<string, string> Sanitize(
        IReadOnlyDictionary<string, object?> input,
        Func<string, bool>? pluginHasMessage = null,
        bool redacted = false)
    {
        string? Str(string key) => input.TryGetValue(key, out var v) && v is not null ? Convert.ToString(v) : null;

        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        var ev = Str("event");
        result["event"] = ev is not null && EventRegex().IsMatch(ev) ? ev : "source";

        var level = Str("level");
        if (level is "normal" or "debug") result["level"] = level;

        foreach (var numKey in NumericKeys)
        {
            if (long.TryParse(Str(numKey), out var n) && n is >= 0 and <= 9007199254740991L)
                result[numKey] = n.ToString();
        }

        var method = Str("method");
        if (method is not null && AllowedMethods.Contains(method)) result["method"] = method;

        var site = Str("site");
        if (site is not null && NameRegex().IsMatch(site)) result["site"] = site;

        var action = Str("action");
        if (action is not null && NameRegex().IsMatch(action)) result["action"] = action;

        var stage = Str("stage");
        if (stage is not null && AllowedStages.Contains(stage)) result["stage"] = stage;

        var outcome = Str("outcome");
        if (outcome is not null && AllowedOutcomes.Contains(outcome)) result["outcome"] = outcome;

        var code = Str("code");
        if (code is not null && AllowedCodes.Contains(code)) result["code"] = code;

        if (int.TryParse(Str("status"), out var status) && status is >= 100 and <= 599)
            result["status"] = status.ToString();

        var reason = Str("reason");
        if (reason is not null && AllowedReasons.Contains(reason)) result["reason"] = reason;

        var transport = Str("transport");
        if (transport is "native" or "browser") result["transport"] = transport;

        if (!redacted)
        {
            var host = Str("host");
            if (host is not null && host.Length <= 253 && HostRegex().IsMatch(host))
                result["host"] = host;
        }

        var type = Str("type");
        if (type is not null)
        {
            var cleanedType = NonIdentRegex().Replace(type, string.Empty);
            if (cleanedType.Length is > 0 and <= 64) result["type"] = cleanedType;
        }

        var msg = Str("message");
        if (msg is not null && msg.Length <= 200 && (L.HasMessage(msg) || (pluginHasMessage?.Invoke(msg) ?? false)))
        {
            result["message"] = msg;
        }

        return result;
    }

    [GeneratedRegex(@"^[a-z][a-z_]{0,31}$")]
    private static partial Regex EventRegex();

    [GeneratedRegex(@"^[A-Za-z][A-Za-z0-9_.-]{0,63}$")]
    private static partial Regex NameRegex();

    [GeneratedRegex(@"^(?:[a-zA-Z0-9-]+\.)*[a-zA-Z0-9-]+$")]
    private static partial Regex HostRegex();

    [GeneratedRegex(@"[^A-Za-z0-9_]")]
    private static partial Regex NonIdentRegex();
}

public sealed record DiagnosticRecord(long TimestampMs, IReadOnlyDictionary<string, string> Fields)
{
    public string FormattedLine
    {
        get
        {
            var ts = DateTimeOffset.FromUnixTimeMilliseconds(TimestampMs).ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss.fff");
            var pairs = Fields.Select(kv => kv.Key == "message"
                ? $"message={JsonSerializer.Serialize(kv.Value)}"
                : $"{kv.Key}={kv.Value}");
            return $"[{ts}] {string.Join(' ', pairs)}";
        }
    }
}

public sealed class AppLog
{
    public static AppLog Instance { get; } = new();

    private readonly Lock _lock = new();
    private readonly LinkedList<DiagnosticRecord> _recent = new();
    private const int MaxMemoryEntries = 2000;

    public bool DebugEnabled { get; private set; }
    public bool PersistentMode { get; set; }
    public bool StartupDebugNotice { get; set; }

    public event Action? Updated;

    public async Task InitializeAsync()
    {
        AppPaths.EnsureDirectories();
        var prefPath = AppPaths.LogPreferencesFile;
        if (File.Exists(prefPath))
        {
            try
            {
                var doc = JsonDocument.Parse(await File.ReadAllTextAsync(prefPath).ConfigureAwait(false));
                var root = doc.RootElement;
                PersistentMode = root.TryGetProperty("persistent", out var p) && p.ValueKind == JsonValueKind.True;
                if (root.TryGetProperty("debugNextLaunch", out var next) && next.ValueKind == JsonValueKind.True)
                {
                    DebugEnabled = true;
                    StartupDebugNotice = true;
                    await SavePreferencesAsync(debugNextLaunch: false).ConfigureAwait(false);
                }
            }
            catch
            {
                // Log preference errors must never block app startup per DEVELOPMENT.md
            }
        }
    }

    public void EnableDebugThisSession(bool enabled) => DebugEnabled = enabled;

    public Task ScheduleDebugNextLaunchAsync(bool scheduled) => SavePreferencesAsync(debugNextLaunch: scheduled);

    private Task SavePreferencesAsync(bool debugNextLaunch)
    {
        var json = JsonSerializer.Serialize(new { persistent = PersistentMode, debugNextLaunch });
        return AppPaths.WriteTextAtomicAsync(AppPaths.LogPreferencesFile, json);
    }

    public void Record(IReadOnlyDictionary<string, object?> raw, Func<string, bool>? pluginCopy = null)
    {
        var sanitized = DiagnosticsSanitizer.Sanitize(raw, pluginCopy);
        if (sanitized.TryGetValue("level", out var lvl) && lvl == "debug" && !DebugEnabled)
            return;

        var entry = new DiagnosticRecord(DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(), sanitized);
        lock (_lock)
        {
            _recent.AddFirst(entry);
            while (_recent.Count > MaxMemoryEntries)
                _recent.RemoveLast();
        }
        _ = AppendDiskLineAsync(entry);
        Updated?.Invoke();
    }

    public void Error(Exception ex, string eventName = "source", string? site = null, string? action = null)
    {
        var baseFields = DiagnosticsSanitizer.FromError(ex);
        var payload = new Dictionary<string, object?>(StringComparer.Ordinal)
        {
            ["event"] = eventName,
        };
        if (site is not null) payload["site"] = site;
        if (action is not null) payload["action"] = action;
        foreach (var (k, v) in baseFields) payload[k] = v;
        Record(payload);
    }

    public void RecordCrashSync(Exception ex)
    {
        try
        {
            AppPaths.EnsureDirectories();
            var crashPath = Path.Combine(AppPaths.LogsDir, "crash.log");
            if (File.Exists(crashPath) && new FileInfo(crashPath).Length >= 256 * 1024)
            {
                File.Move(crashPath, $"{crashPath}.1", overwrite: true);
            }
            var sanitized = DiagnosticsSanitizer.Sanitize(new Dictionary<string, object?>
            {
                ["event"] = "crash",
                ["reason"] = "NATIVE_CRASH",
                ["type"] = ex.GetType().Name,
            });
            var line = JsonSerializer.Serialize(new
            {
                ts = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                fields = sanitized,
            }) + "\n";
            File.AppendAllText(crashPath, line, Encoding.UTF8);
        }
        catch
        {
            // Never throw inside crash hook
        }
    }

    public IReadOnlyList<DiagnosticRecord> Snapshot(bool redacted = false)
    {
        List<DiagnosticRecord> copy;
        lock (_lock)
        {
            copy = [.. _recent];
        }
        if (!redacted) return copy;

        return copy.Select(r =>
        {
            var dict = new Dictionary<string, string>(r.Fields, StringComparer.Ordinal);
            dict.Remove("host");
            return new DiagnosticRecord(r.TimestampMs, dict);
        }).ToList();
    }

    public string ExportReport(bool redacted, bool hasProxy, IReadOnlyDictionary<string, string> pluginVersions)
    {
        var sb = new StringBuilder();
        sb.AppendLine($"HentaiPark Windows v{PublicContract.AppVersion}+{PublicContract.BuildNumber}");
        sb.AppendLine($"ProxyConfigured: {hasProxy}");
        if (!redacted)
        {
            sb.AppendLine($"OS: Windows {Environment.OSVersion.Version}");
        }
        if (pluginVersions.Count > 0)
        {
            sb.AppendLine("Plugins: " + string.Join(", ", pluginVersions.Select(kv => $"{kv.Key}@{kv.Value}")));
        }
        sb.AppendLine("--- Events ---");
        foreach (var entry in Snapshot(redacted))
        {
            sb.AppendLine(entry.FormattedLine);
        }
        return sb.ToString();
    }

    private async Task AppendDiskLineAsync(DiagnosticRecord entry)
    {
        try
        {
            var logPath = Path.Combine(AppPaths.LogsDir, "runtime.jsonl");
            var maxBytes = PersistentMode ? 5 * 1024 * 1024 : 1024 * 1024;
            if (File.Exists(logPath) && new FileInfo(logPath).Length >= maxBytes)
            {
                File.Move(logPath, $"{logPath}.1", overwrite: true);
            }
            var jsonLine = JsonSerializer.Serialize(new { ts = entry.TimestampMs, fields = entry.Fields }) + "\n";
            await File.AppendAllTextAsync(logPath, jsonLine, Encoding.UTF8).ConfigureAwait(false);
        }
        catch
        {
            // Storage failure never interrupts app operations
        }
    }
}
