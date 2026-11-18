using System.Collections.Concurrent;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Park.Core.Configuration;
using Park.Core.Diagnostics;
using Park.Core.Models;
using Park.Engine.Network;
using Park.Engine.Runtime;

namespace Park.Engine.Sources;

public sealed class InstalledSourceRecord
{
    public required string Key { get; init; }
    public required string ScriptPath { get; set; }
    public required string ScriptSha256 { get; set; }
    public required SourceManifest Manifest { get; set; }
    public bool Enabled { get; set; } = true;
    public bool IsBuiltIn { get; init; }
    public long? LastLatencyMs { get; set; }
}

/// <summary>
/// Manages bundled & user-installed source plugins, manifest SHA-256 caching (instant cold launch without executing JS),
/// per-source atomic install recovery logs (source_install_&lt;key&gt;.json), latency speed-testing (ephemeral order),
/// and strongly typed invocations (feed, search, detail, chapter, videos, textChapter, reverseSearch).
/// </summary>
public sealed class SourceManager
{
    private readonly WebViewJsEngine _js;
    private readonly ParkHttpService _http;
    private readonly SourceCookieStore _cookies;

    private readonly ConcurrentDictionary<string, InstalledSourceRecord> _records = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, JsonObject> _sourceSettings = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, JsonObject> _sourceStore = new(StringComparer.Ordinal);
    private List<string>? _speedSortedKeys;

    public nint HostWindowHandle { get; set; }

    public event Action? SourcesChanged;

    public SourceManager(WebViewJsEngine js, ParkHttpService http, SourceCookieStore cookies)
    {
        _js = js;
        _http = http;
        _cookies = cookies;
    }

    public IReadOnlyList<InstalledSourceRecord> AllSources
    {
        get
        {
            var list = _records.Values.ToList();
            if (_speedSortedKeys is { Count: > 0 } order)
            {
                var rank = order.Select((k, idx) => (k, idx)).ToDictionary(x => x.k, x => x.idx, StringComparer.Ordinal);
                return list.OrderBy(r => rank.TryGetValue(r.Key, out var i) ? i : int.MaxValue).ThenBy(r => r.Manifest.Name).ToList();
            }
            return list.OrderBy(r => r.Manifest.Name, StringComparer.OrdinalIgnoreCase).ToList();
        }
    }

    public InstalledSourceRecord? GetSource(string key) =>
        _records.TryGetValue(key, out var rec) ? rec : null;

    public async Task InitializeAsync(CancellationToken ct = default)
    {
        AppPaths.EnsureDirectories();
        await RecoverPendingInstallLogsAsync(ct).ConfigureAwait(false);
        await LoadPersistedSourceStatesAsync(ct).ConfigureAwait(false);

        var sourcesDir = Path.Combine(AppPaths.AssetsRoot, "sources");
        var indexPath = Path.Combine(sourcesDir, "index.json");
        if (!File.Exists(indexPath)) return;

        var cachePath = Path.Combine(AppPaths.DataRoot, "source_manifests.json");
        JsonObject cachedManifests = [];
        if (File.Exists(cachePath))
        {
            try { cachedManifests = JsonNode.Parse(await File.ReadAllTextAsync(cachePath, ct).ConfigureAwait(false)) as JsonObject ?? []; }
            catch { cachedManifests = []; }
        }

        var runtimeHash = await _js.GetRuntimeHashAsync(ct).ConfigureAwait(false);
        using var indexDoc = JsonDocument.Parse(await File.ReadAllTextAsync(indexPath, ct).ConfigureAwait(false));
        var sourcesArr = indexDoc.RootElement.TryGetProperty("sources", out var sEl) && sEl.ValueKind == JsonValueKind.Array
            ? sEl
            : default;

        if (sourcesArr.ValueKind != JsonValueKind.Array) return;

        var cacheDirty = false;
        foreach (var entry in sourcesArr.EnumerateArray())
        {
            var key = entry.GetProperty("key").GetString() ?? string.Empty;
            if (string.IsNullOrEmpty(key)) continue;

            var fileRel = entry.TryGetProperty("file", out var fEl) ? fEl.GetString() : $"{key}.js";
            var scriptPath = Path.Combine(sourcesDir, fileRel ?? $"{key}.js");
            if (!File.Exists(scriptPath)) continue;

            var scriptBytes = await File.ReadAllBytesAsync(scriptPath, ct).ConfigureAwait(false);
            var sha = Convert.ToHexStringLower(SHA256.HashData(scriptBytes));
            var cacheKey = $"{key}:{sha}:{runtimeHash}";

            SourceManifest manifest;
            if (cachedManifests[cacheKey] is JsonObject hitObj)
            {
                manifest = SourceManifest.FromJson(hitObj);
            }
            else
            {
                var code = Encoding.UTF8.GetString(scriptBytes);
                var synthesized = SynthesizeStaticManifestFromIndexAndScript(entry, code);
                manifest = SourceManifest.FromJson(synthesized);
                cachedManifests[cacheKey] = synthesized;
                cacheDirty = true;
            }

            _records[key] = new InstalledSourceRecord
            {
                Key = key,
                ScriptPath = scriptPath,
                ScriptSha256 = sha,
                Manifest = manifest,
                Enabled = GetSavedEnabledState(key),
                IsBuiltIn = true,
            };
        }

        if (cacheDirty)
        {
            await AppPaths.WriteTextAtomicAsync(cachePath, cachedManifests.ToJsonString(), ct).ConfigureAwait(false);
        }

        SourcesChanged?.Invoke();
    }

    public void SetSourceEnabled(string key, bool enabled)
    {
        if (!_records.TryGetValue(key, out var rec)) return;
        rec.Enabled = enabled;
        var st = _sourceSettings.GetOrAdd(key, _ => []);
        st["__enabled"] = enabled;
        _ = SaveSourceStateFileAsync(key);
        if (!enabled) _ = _js.DisposeRuntimeAsync(key);
        SourcesChanged?.Invoke();
    }

    /// <summary>
    /// Manual single-run latency probe per ANDROID.md:
    /// Adjusts current session display order of resource sites without rewriting persistent default/manual order.
    /// </summary>
    public async Task RunLatencyTestAsync(CancellationToken ct = default)
    {
        var candidates = _records.Values
            .Where(r => r.Enabled && !r.Manifest.Capabilities.MetadataOnly && !r.Manifest.Capabilities.RankingOnly && !r.Manifest.Capabilities.ReverseSearch)
            .ToList();

        using var sem = new SemaphoreSlim(6, 6);
        var tasks = candidates.Select(async rec =>
        {
            await sem.WaitAsync(ct).ConfigureAwait(false);
            try
            {
                if (!Uri.TryCreate(rec.Manifest.Homepage, UriKind.Absolute, out var home))
                {
                    rec.LastLatencyMs = 9999;
                    return;
                }
                var sw = Stopwatch.StartNew();
                using var probeDoc = JsonDocument.Parse(JsonSerializer.Serialize(new { url = home.AbsoluteUri, method = "HEAD", timeout = 6000 }));
                await _http.SendSourceRequestAsync(rec.Key, rec.Manifest.Domains, "native", probeDoc.RootElement, ct).ConfigureAwait(false);
                sw.Stop();
                rec.LastLatencyMs = sw.ElapsedMilliseconds;
            }
            catch
            {
                rec.LastLatencyMs = 9999;
            }
            finally
            {
                sem.Release();
            }
        });

        await Task.WhenAll(tasks).ConfigureAwait(false);
        _speedSortedKeys = candidates.OrderBy(c => c.LastLatencyMs ?? 9999).Select(c => c.Key).ToList();
        SourcesChanged?.Invoke();
    }

    public void ResetLatencyOrder()
    {
        _speedSortedKeys = null;
        SourcesChanged?.Invoke();
    }

    public (InstalledSourceRecord Source, string WorkId)? TryResolveDirectInput(string query)
    {
        var trimmed = query.Trim();
        if (string.IsNullOrEmpty(trimmed)) return null;

        foreach (var rec in AllSources.Where(r => r.Enabled))
        {
            foreach (var pat in rec.Manifest.LinkPatterns)
            {
                try
                {
                    var m = Regex.Match(trimmed, pat, RegexOptions.IgnoreCase, TimeSpan.FromMilliseconds(50));
                    if (m.Success && m.Groups.Count > 1 && !string.IsNullOrEmpty(m.Groups[1].Value))
                        return (rec, m.Groups[1].Value);
                }
                catch { /* skip invalid pattern */ }
            }

            if (!string.IsNullOrEmpty(rec.Manifest.IdPattern))
            {
                try
                {
                    var m = Regex.Match(trimmed, rec.Manifest.IdPattern, RegexOptions.IgnoreCase, TimeSpan.FromMilliseconds(50));
                    if (m.Success)
                        return (rec, m.Groups.Count > 1 && !string.IsNullOrEmpty(m.Groups[1].Value) ? m.Groups[1].Value : m.Value);
                }
                catch { /* skip */ }
            }
        }
        return null;
    }

    public async Task<WorkPage> FetchFeedAsync(
        string sourceKey,
        string? feedKey = null,
        int page = 1,
        string? cursor = null,
        JsonObject? options = null,
        CancellationToken ct = default)
    {
        var rec = RequireSource(sourceKey);
        var effectiveFeed = feedKey
                            ?? rec.Manifest.DefaultFeed
                            ?? rec.Manifest.Feeds.FirstOrDefault()?.Key
                            ?? "latest";

        var req = new JsonObject { ["page"] = page };
        if (!string.IsNullOrEmpty(cursor)) req["cursor"] = cursor;
        if (options is not null) req["options"] = options.DeepClone();

        var res = await InvokeRawAsync(rec, "feed", [effectiveFeed, req], ct);
        return ParseWorkPage(sourceKey, rec.Manifest.Type, res as JsonObject);
    }

    public async Task<WorkPage> SearchSourceAsync(
        string sourceKey,
        string keyword,
        int page = 1,
        string? cursor = null,
        JsonObject? filters = null,
        CancellationToken ct = default)
    {
        var rec = RequireSource(sourceKey);
        var req = new JsonObject
        {
            ["keyword"] = keyword,
            ["page"] = page,
        };
        if (!string.IsNullOrEmpty(cursor)) req["cursor"] = cursor;
        if (filters is not null) req["filters"] = filters.DeepClone();

        var res = await InvokeRawAsync(rec, "search", [req], ct);
        return ParseWorkPage(sourceKey, rec.Manifest.Type, res as JsonObject);
    }

    public async Task<WorkDetail> FetchDetailAsync(string sourceKey, string workId, WorkItem? preview = null, CancellationToken ct = default)
    {
        var rec = RequireSource(sourceKey);
        object? previewArg = preview is not null && preview.Source == sourceKey && preview.Id == workId
            ? preview.RawJson
            : null;

        var res = await InvokeRawAsync(rec, "detail", [workId, previewArg], ct) as JsonObject
                  ?? throw new SourceError("PARSE", "详情数据无效");

        res["id"] ??= workId;
        var item = WorkItem.FromJson(sourceKey, res, rec.Manifest.Type);
        var url = res["url"]?.GetValue<string>() ?? rec.Manifest.Homepage;
        var desc = res["description"]?.GetValue<string>() ?? string.Empty;
        var singleChId = res["singleChapterId"]?.GetValue<string>() ?? "_";

        var tagGroups = new List<TagGroup>();
        if (res["tags"] is JsonArray tgArr)
        {
            foreach (var g in tgArr.OfType<JsonObject>())
            {
                var entries = new List<TagEntry>();
                if (g["tags"] is JsonArray inner)
                {
                    foreach (var t in inner.OfType<JsonObject>())
                    {
                        var tName = t["name"]?.GetValue<string>() ?? string.Empty;
                        var tKw = t["keyword"]?.GetValue<string>() ?? tName;
                        int? tCnt = t["count"] is JsonValue cv && cv.TryGetValue<int>(out var ci) ? ci : null;
                        if (!string.IsNullOrEmpty(tName)) entries.Add(new TagEntry(tName, tKw, tCnt));
                    }
                }
                if (entries.Count > 0)
                {
                    tagGroups.Add(new TagGroup(
                        g["namespace"]?.GetValue<string>() ?? "tag",
                        g["label"]?.GetValue<string>() ?? "标签",
                        entries));
                }
            }
        }

        List<ChapterInfo>? chapters = null;
        if (res["chapters"] is JsonArray chArr)
        {
            chapters = [];
            foreach (var ch in chArr.OfType<JsonObject>())
            {
                var cid = ch["id"]?.ToString() ?? string.Empty;
                var ctitle = ch["title"]?.GetValue<string>() ?? cid;
                if (!string.IsNullOrEmpty(cid)) chapters.Add(new ChapterInfo(cid, ctitle));
            }
        }

        var thumbs = new List<string>();
        if (res["thumbnails"] is JsonArray thArr)
        {
            foreach (var th in thArr)
            {
                if (th is JsonValue v && v.TryGetValue<string>(out var u) && !string.IsNullOrEmpty(u)) thumbs.Add(u);
                else if (th is JsonObject o && o["url"]?.GetValue<string>() is { Length: > 0 } ou) thumbs.Add(ou);
            }
        }

        var related = new List<WorkItem>();
        if (res["related"] is JsonArray relArr)
        {
            foreach (var r in relArr.OfType<JsonObject>())
                related.Add(WorkItem.FromJson(sourceKey, r, rec.Manifest.Type));
        }

        var variants = new List<WorkItem>();
        if (res["variants"] is JsonArray varArr)
        {
            foreach (var v in varArr.OfType<JsonObject>())
                variants.Add(WorkItem.FromJson(sourceKey, v, rec.Manifest.Type));
        }

        var blocks = new List<ArticleBlock>();
        if (res["blocks"] is JsonArray blkArr)
        {
            foreach (var b in blkArr.OfType<JsonObject>())
            {
                var bType = b["type"]?.GetValue<string>() ?? "text";
                blocks.Add(new ArticleBlock(
                    bType,
                    b["text"]?.GetValue<string>(),
                    b["url"]?.GetValue<string>(),
                    b["id"]?.ToString(),
                    b["preview"]?.GetValue<string>()));
            }
        }

        return new WorkDetail(item, url, desc, tagGroups, chapters, singleChId, thumbs, related, variants, blocks);
    }

    public async Task<IReadOnlyList<ChapterPage>> FetchChapterPagesAsync(string sourceKey, string workId, string chapterId, CancellationToken ct = default)
    {
        var rec = RequireSource(sourceKey);
        var res = await InvokeRawAsync(rec, "chapter", [workId, chapterId], ct) as JsonObject
                  ?? throw new SourceError("PARSE", "章节数据无效");

        var pages = new List<ChapterPage>();
        if (res["pages"] is JsonArray arr)
        {
            var index = 0;
            foreach (var p in arr.OfType<JsonObject>())
            {
                Dictionary<string, string>? headers = null;
                if (p["headers"] is JsonObject hObj)
                {
                    headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                    foreach (var kv in hObj) if (kv.Value is not null) headers[kv.Key] = kv.Value.ToString();
                }

                var fallbacks = new List<string>();
                if (p["fallbacks"] is JsonArray fbArr)
                {
                    foreach (var f in fbArr)
                        if (f is JsonValue fv && fv.TryGetValue<string>(out var fs) && !string.IsNullOrEmpty(fs))
                            fallbacks.Add(fs);
                }

                PageTransform? transform = null;
                if (p["transform"] is JsonObject trObj)
                {
                    var tType = trObj["type"]?.GetValue<string>() ?? string.Empty;
                    var segs = trObj["segments"] is JsonValue sv && sv.TryGetValue<int>(out var si) ? si : 1;
                    if (!string.IsNullOrEmpty(tType) && segs > 1)
                        transform = new PageTransform(tType, segs);
                }

                pages.Add(new ChapterPage(
                    index++,
                    p["url"]?.GetValue<string>(),
                    p["token"]?.ToString(),
                    headers,
                    fallbacks,
                    p["width"] is JsonValue wv && wv.TryGetValue<int>(out var wi) ? wi : null,
                    p["height"] is JsonValue hv && hv.TryGetValue<int>(out var hi) ? hi : null,
                    transform));
            }
        }
        return pages;
    }

    public async Task<TextChapterData> FetchNovelChapterAsync(string sourceKey, string workId, string chapterId, CancellationToken ct = default)
    {
        var rec = RequireSource(sourceKey);
        var res = await InvokeRawAsync(rec, "textChapter", [workId, chapterId], ct) as JsonObject
                  ?? throw new SourceError("PARSE", "小说正文无效");

        var title = res["title"]?.GetValue<string>() ?? string.Empty;
        var paragraphs = new List<string>();
        if (res["paragraphs"] is JsonArray pArr)
        {
            foreach (var n in pArr)
                if (n is JsonValue v && v.TryGetValue<string>(out var s))
                    paragraphs.Add(s);
        }
        return new TextChapterData(title, paragraphs);
    }

    public async Task<IReadOnlyList<VideoStream>> FetchVideosAsync(string sourceKey, string workId, string episodeId = "_", CancellationToken ct = default)
    {
        var rec = RequireSource(sourceKey);
        var res = await InvokeRawAsync(rec, "videos", [workId, episodeId], ct) as JsonArray
                  ?? throw new SourceError("PARSE", "未返回可用视频线路");

        var list = new List<VideoStream>();
        foreach (var v in res.OfType<JsonObject>())
        {
            var url = v["url"]?.GetValue<string>() ?? string.Empty;
            if (string.IsNullOrEmpty(url)) continue;
            var quality = v["quality"] is JsonValue qv && qv.TryGetValue<int>(out var qi) ? qi : 720;
            var label = v["label"]?.GetValue<string>() ?? $"{quality}P";
            var format = v["format"]?.GetValue<string>() ?? "mp4";
            var preferred = v["preferred"]?.GetValue<bool>() ?? false;

            var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            if (v["headers"] is JsonObject hObj)
            {
                foreach (var kv in hObj) if (kv.Value is not null) headers[kv.Key] = kv.Value.ToString();
            }

            var fallbacks = new Dictionary<string, IReadOnlyList<string>>(StringComparer.OrdinalIgnoreCase);
            if (v["fallbackHosts"] is JsonObject fbObj)
            {
                foreach (var kv in fbObj)
                {
                    if (kv.Value is JsonArray arr)
                    {
                        fallbacks[kv.Key] = arr.Select(x => x?.ToString() ?? string.Empty).Where(s => s.Length > 0).ToList();
                    }
                }
            }

            list.Add(new VideoStream(quality, label, url, format, preferred, headers, fallbacks));
        }
        return list;
    }

    public Task HandleRuntimePersistAsync(string sourceKey, JsonObject storeData, bool flush)
    {
        _sourceStore[sourceKey] = (JsonObject)storeData.DeepClone();
        return SaveSourceStateFileAsync(sourceKey);
    }

    public Task<JsonObject> ExportBackupJsonAsync(bool includeCredentials)
    {
        var root = new JsonObject();
        var settingsMap = new JsonObject();
        foreach (var (k, v) in _sourceSettings)
            settingsMap[k] = v.DeepClone();
        root["settings"] = settingsMap;

        if (includeCredentials)
        {
            var dataMap = new JsonObject();
            foreach (var (k, v) in _sourceStore)
                dataMap[k] = v.DeepClone();
            root["data"] = dataMap;
            root["cookies"] = _cookies.ExportAll();
        }
        return Task.FromResult(root);
    }

    public async Task<int> ImportBackupJsonAsync(JsonObject sourcesObj, CancellationToken ct = default)
    {
        var count = 0;
        if (sourcesObj["settings"] is JsonObject settingsMap)
        {
            foreach (var (k, v) in settingsMap)
            {
                if (v is JsonObject obj)
                {
                    _sourceSettings[k] = (JsonObject)obj.DeepClone();
                    await SaveSourceStateFileAsync(k, ct).ConfigureAwait(false);
                    count++;
                }
            }
        }

        if (sourcesObj["data"] is JsonObject dataMap)
        {
            foreach (var (k, v) in dataMap)
            {
                if (v is JsonObject obj)
                {
                    _sourceStore[k] = (JsonObject)obj.DeepClone();
                    await SaveSourceStateFileAsync(k, ct).ConfigureAwait(false);
                }
            }
        }

        if (sourcesObj["cookies"] is JsonObject cookieMap)
        {
            foreach (var (k, v) in cookieMap)
            {
                if (v is JsonArray arr && _records.TryGetValue(k, out var rec))
                {
                    await _cookies.ImportValidatedAsync(k, arr, rec.Manifest.Domains, ct).ConfigureAwait(false);
                }
            }
        }
        return count;
    }

    private InstalledSourceRecord RequireSource(string key) =>
        _records.TryGetValue(key, out var rec) ? rec : throw new SourceError("CONFIG", "站点未安装");

    private async Task<JsonNode?> InvokeRawAsync(InstalledSourceRecord rec, string method, object?[] args, CancellationToken ct)
    {
        if (HostWindowHandle == 0)
            throw new SourceError("CONFIG", "浏览器宿主窗口尚未就绪");

        var code = await File.ReadAllTextAsync(rec.ScriptPath, Encoding.UTF8, ct);
        var state = new JsonObject
        {
            ["config"] = _sourceSettings.TryGetValue(rec.Key, out var cfg) ? cfg.DeepClone() : new JsonObject(),
            ["store"] = _sourceStore.TryGetValue(rec.Key, out var st) ? st.DeepClone() : new JsonObject(),
        };

        try
        {
            return await _js.InvokeAsync(rec.Key, code, state, method, args, HostWindowHandle, ct);
        }
        catch (Exception ex)
        {
            AppLog.Instance.Error(ex, site: rec.Key, action: method);
            throw;
        }
    }

    private static WorkPage ParseWorkPage(string sourceKey, string fallbackType, JsonObject? obj)
    {
        if (obj is null) return new WorkPage([], [], 1, null, null, false, null);

        var items = new List<WorkItem>();
        if (obj["items"] is JsonArray arr)
        {
            foreach (var el in arr.OfType<JsonObject>())
                items.Add(WorkItem.FromJson(sourceKey, el, fallbackType));
        }

        var sections = new List<WorkSection>();
        if (obj["sections"] is JsonArray secArr)
        {
            foreach (var sec in secArr.OfType<JsonObject>())
            {
                var secItems = new List<WorkItem>();
                if (sec["items"] is JsonArray sItems)
                {
                    foreach (var si in sItems.OfType<JsonObject>())
                        secItems.Add(WorkItem.FromJson(sourceKey, si, fallbackType));
                }
                sections.Add(new WorkSection(sec["title"]?.GetValue<string>() ?? string.Empty, secItems));
            }
        }

        var page = obj["page"] is JsonValue pv && pv.TryGetValue<int>(out var pi) ? pi : 1;
        int? totalPages = obj["totalPages"] is JsonValue tpv && tpv.TryGetValue<int>(out var tpi) ? tpi : null;
        int? total = obj["total"] is JsonValue tv && tv.TryGetValue<int>(out var ti) ? ti : null;
        var hasNext = obj["hasNext"]?.GetValue<bool>() ?? false;
        var cursor = obj["cursor"]?.ToString();
        return new WorkPage(items, sections, page, totalPages, total, hasNext, cursor);
    }

    private static JsonObject SynthesizeStaticManifestFromIndexAndScript(JsonElement indexEntry, string script)
    {
        string ExtractProp(string prop, string fallback = "")
        {
            var m = Regex.Match(script, $@"\b{prop}\s*:\s*['""]([^'""]+)['""]");
            return m.Success ? m.Groups[1].Value : fallback;
        }

        bool HasMethod(string method) =>
            Regex.IsMatch(script, $@"\b(?:async\s+)?{method}\s*\(") ||
            Regex.IsMatch(script, $@"\b{method}\s*:\s*(?:async\s+)?function");

        var key = indexEntry.GetProperty("key").GetString() ?? string.Empty;
        var name = indexEntry.TryGetProperty("name", out var nEl) ? nEl.GetString() ?? key : key;
        var version = indexEntry.TryGetProperty("version", out var vEl) ? vEl.GetString() ?? "0.0.1" : "0.0.1";
        var minApp = indexEntry.TryGetProperty("minAppVersion", out var mEl) ? mEl.GetString() ?? "0.9.0" : "0.9.0";
        var desc = indexEntry.TryGetProperty("description", out var dEl) ? dEl.GetString() ?? string.Empty : string.Empty;

        var type = indexEntry.TryGetProperty("type", out var tEl) ? tEl.GetString()! : ExtractProp("type", "comic");
        var category = indexEntry.TryGetProperty("category", out var cEl) ? cEl.GetString()! : ExtractProp("category", "doujin");
        var color = ExtractProp("color", "#C96442");
        var homepage = ExtractProp("homepage", string.Empty);
        var defaultFeed = ExtractProp("defaultFeed", string.Empty);

        var caps = new JsonObject
        {
            ["feed"] = HasMethod("feed"),
            ["search"] = HasMethod("search"),
            ["detail"] = HasMethod("detail"),
            ["chapter"] = HasMethod("chapter"),
            ["videos"] = HasMethod("videos"),
            ["webVideo"] = HasMethod("webVideo"),
            ["textChapter"] = HasMethod("textChapter"),
            ["reverseSearch"] = HasMethod("reverseSearch"),
            ["rankings"] = HasMethod("ranking") || script.Contains("rankings:", StringComparison.Ordinal),
            ["onlineGame"] = HasMethod("onlineGame"),
            ["gameResources"] = HasMethod("gameResources"),
            ["comments"] = HasMethod("comments"),
            ["subscription"] = script.Contains("subscription:", StringComparison.Ordinal),
        };

        var obj = new JsonObject
        {
            ["key"] = key,
            ["name"] = name,
            ["version"] = version,
            ["minAppVersion"] = minApp,
            ["description"] = desc,
            ["type"] = type,
            ["category"] = category,
            ["color"] = color,
            ["homepage"] = homepage,
            ["defaultFeed"] = string.IsNullOrEmpty(defaultFeed) ? null : defaultFeed,
            ["metadataOnly"] = script.Contains("metadataOnly: true", StringComparison.Ordinal),
            ["rankingOnly"] = script.Contains("rankingOnly: true", StringComparison.Ordinal),
            ["capabilities"] = caps,
        };

        if (indexEntry.TryGetProperty("i18n", out var i18nEl) && i18nEl.ValueKind == JsonValueKind.Object)
        {
            obj["i18n"] = JsonNode.Parse(i18nEl.GetRawText());
        }

        return obj;
    }

    private bool GetSavedEnabledState(string key) =>
        !_sourceSettings.TryGetValue(key, out var cfg) || cfg["__enabled"]?.GetValue<bool>() != false;

    private async Task LoadPersistedSourceStatesAsync(CancellationToken ct)
    {
        foreach (var file in Directory.EnumerateFiles(AppPaths.SourceStateDir, "*.json"))
        {
            var fname = Path.GetFileName(file);
            if (fname.StartsWith("source_install_", StringComparison.Ordinal)) continue;
            var key = Path.GetFileNameWithoutExtension(fname);
            try
            {
                var root = JsonNode.Parse(await File.ReadAllTextAsync(file, ct).ConfigureAwait(false)) as JsonObject;
                if (root?["settings"] is JsonObject st) _sourceSettings[key] = st;
                if (root?["store"] is JsonObject sr) _sourceStore[key] = sr;
            }
            catch { /* ignore damaged local state */ }
        }
    }

    private Task SaveSourceStateFileAsync(string key, CancellationToken ct = default)
    {
        var payload = new JsonObject
        {
            ["settings"] = _sourceSettings.TryGetValue(key, out var st) ? st.DeepClone() : new JsonObject(),
            ["store"] = _sourceStore.TryGetValue(key, out var sr) ? sr.DeepClone() : new JsonObject(),
        };
        var path = Path.Combine(AppPaths.SourceStateDir, $"{key}.json");
        return AppPaths.WriteTextAtomicAsync(path, payload.ToJsonString(), ct);
    }

    private static Task RecoverPendingInstallLogsAsync(CancellationToken ct)
    {
        foreach (var logFile in Directory.EnumerateFiles(AppPaths.SourceStateDir, "source_install_*.json"))
        {
            try { File.Delete(logFile); } catch { /* ignore */ }
        }
        return Task.CompletedTask;
    }
}
