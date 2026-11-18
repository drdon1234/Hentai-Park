using System.Text.Json;
using System.Text.Json.Nodes;

namespace Park.Core.Models;

public sealed class SourceError : Exception
{
    public string Code { get; }
    public string RawMessage { get; }
    public IReadOnlyDictionary<string, string> Params { get; }
    public int? Status { get; }
    public string? Url { get; }
    public IReadOnlyDictionary<string, string> Diagnostics { get; }

    public SourceError(
        string code,
        string rawMessage,
        IReadOnlyDictionary<string, string>? parameters = null,
        int? status = null,
        string? url = null,
        IReadOnlyDictionary<string, string>? diagnostics = null)
        : base(rawMessage)
    {
        Code = string.IsNullOrWhiteSpace(code) ? "UNKNOWN" : code;
        RawMessage = rawMessage;
        Params = parameters ?? new Dictionary<string, string>();
        Status = status;
        Url = url;
        Diagnostics = diagnostics ?? new Dictionary<string, string>();
    }

    public static SourceError FromJson(JsonElement element)
    {
        if (element.ValueKind != JsonValueKind.Object)
            return new SourceError("PARSE", "站点返回了无效结果");

        var code = element.TryGetProperty("code", out var c) && c.ValueKind == JsonValueKind.String ? c.GetString()! : "PARSE";
        var msg = element.TryGetProperty("message", out var m) && m.ValueKind == JsonValueKind.String ? m.GetString()! : code;
        int? status = element.TryGetProperty("status", out var s) && s.TryGetInt32(out var sv) ? sv : null;
        var url = element.TryGetProperty("url", out var u) && u.ValueKind == JsonValueKind.String ? u.GetString() : null;

        var prms = new Dictionary<string, string>(StringComparer.Ordinal);
        if (element.TryGetProperty("params", out var p) && p.ValueKind == JsonValueKind.Object)
        {
            foreach (var item in p.EnumerateObject())
                prms[item.Name] = item.Value.ToString();
        }

        var diags = new Dictionary<string, string>(StringComparer.Ordinal);
        if (element.TryGetProperty("diagnostics", out var d) && d.ValueKind == JsonValueKind.Object)
        {
            foreach (var item in d.EnumerateObject())
            {
                if (item.Value.ValueKind == JsonValueKind.String)
                    diags[item.Name] = item.Value.GetString()!;
            }
        }

        return new SourceError(code, msg, prms, status, url, diags);
    }
}

public sealed record WorkIdentity(string Source, string Id)
{
    public string Uid => $"{Source}:{Id}";
}

public sealed record FeedChoice(string Value, string Label, string? Color = null);

public sealed record FilterOptionDef(
    string Key,
    string Label,
    string Type,
    string DefaultValue,
    IReadOnlyList<FeedChoice> Values,
    bool Dynamic = false,
    IReadOnlyList<string>? DependsOn = null,
    double Step = 1,
    double? Minimum = null,
    double? Maximum = null);

public sealed record FeedDefinition(
    string Key,
    string Label,
    IReadOnlyList<FilterOptionDef> Options);

public sealed record SourceCapabilities(
    bool Feed = false,
    bool Search = false,
    bool Detail = false,
    bool Chapter = false,
    bool Videos = false,
    bool WebVideo = false,
    bool TextChapter = false,
    bool ReverseSearch = false,
    bool Rankings = false,
    bool Subscription = false,
    bool SubscriptionUpdates = false,
    bool Album = false,
    bool OnlineGame = false,
    bool GameResources = false,
    bool Comments = false,
    bool PreviewContent = false,
    bool PostShortVideos = false,
    bool MetadataOnly = false,
    bool RankingOnly = false);

public sealed record ImageDecryptSpec(string Type, string Key, string Iv);

public sealed record SourceManifest(
    string Key,
    string Name,
    string Version,
    string MinAppVersion,
    string Type,
    string Category,
    string Color,
    string Description,
    string Homepage,
    IReadOnlyList<string> Domains,
    IReadOnlyList<string> LinkPatterns,
    string? IdPattern,
    string? DefaultFeed,
    string? AnonymousDefaultFeed,
    string? BrowseLayout,
    string NetworkMode,
    bool VpnHint,
    IReadOnlyDictionary<string, string> ImageHeaders,
    ImageDecryptSpec? ImageDecrypt,
    IReadOnlyList<FeedDefinition> Feeds,
    IReadOnlyList<FilterOptionDef> SearchFilters,
    IReadOnlyList<FilterOptionDef> Settings,
    SourceCapabilities Capabilities,
    IReadOnlyDictionary<string, IReadOnlyDictionary<string, string>> I18n,
    JsonObject RawManifest)
{
    public static SourceManifest FromJson(JsonObject obj)
    {
        var key = obj["key"]?.GetValue<string>() ?? string.Empty;
        var name = obj["name"]?.GetValue<string>() ?? key;
        var version = obj["version"]?.GetValue<string>() ?? "0.0.1";
        var minAppVersion = obj["minAppVersion"]?.GetValue<string>() ?? "0.9.0";
        var type = obj["type"]?.GetValue<string>() ?? "comic";
        var category = obj["category"]?.GetValue<string>() ?? "other";
        var color = obj["color"]?.GetValue<string>() ?? "#C96442";
        var desc = obj["description"]?.GetValue<string>() ?? string.Empty;
        var homepage = obj["homepage"]?.GetValue<string>() ?? string.Empty;

        var domains = ReadStringList(obj["domains"]);
        if (domains.Count == 0 && Uri.TryCreate(homepage, UriKind.Absolute, out var homeUri) && !string.IsNullOrEmpty(homeUri.Host))
        {
            domains = [homeUri.Host];
        }

        var linkPatterns = ReadStringList(obj["linkPatterns"]);
        var idPattern = obj["idPattern"]?.GetValue<string>();
        var defaultFeed = obj["defaultFeed"]?.GetValue<string>();
        var anonFeed = obj["anonymousDefaultFeed"]?.GetValue<string>();
        var browseLayout = obj["browseLayout"]?.GetValue<string>();

        var netObj = obj["network"] as JsonObject;
        var netMode = netObj?["mode"]?.GetValue<string>() ?? "auto";
        var vpnHint = netObj?["vpnHint"]?.GetValue<bool>() ?? false;

        var imgHeaders = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (obj["imageHeaders"] is JsonObject ih)
        {
            foreach (var kv in ih)
            {
                if (kv.Value is not null) imgHeaders[kv.Key] = kv.Value.ToString();
            }
        }

        ImageDecryptSpec? decrypt = null;
        if (obj["imageDecrypt"] is JsonObject decObj)
        {
            var dt = decObj["type"]?.GetValue<string>() ?? string.Empty;
            var dk = decObj["key"]?.GetValue<string>() ?? string.Empty;
            var div = decObj["iv"]?.GetValue<string>() ?? string.Empty;
            if (!string.IsNullOrEmpty(dt) && !string.IsNullOrEmpty(dk))
                decrypt = new ImageDecryptSpec(dt, dk, div);
        }

        var feeds = new List<FeedDefinition>();
        if (obj["feeds"] is JsonArray feedsArr)
        {
            foreach (var node in feedsArr.OfType<JsonObject>())
            {
                feeds.Add(new FeedDefinition(
                    node["key"]?.GetValue<string>() ?? string.Empty,
                    node["label"]?.GetValue<string>() ?? string.Empty,
                    ReadFilterOptions(node["options"] as JsonArray)));
            }
        }

        var searchFilters = ReadFilterOptions(obj["searchFilters"] as JsonArray);
        var settings = ReadFilterOptions(obj["settings"] as JsonArray);

        var capObj = obj["capabilities"] as JsonObject;
        bool Cap(string prop) => capObj?[prop]?.GetValue<bool>() ?? false;
        var caps = new SourceCapabilities(
            Feed: Cap("feed") || feeds.Count > 0,
            Search: Cap("search"),
            Detail: Cap("detail"),
            Chapter: Cap("chapter"),
            Videos: Cap("videos"),
            WebVideo: Cap("webVideo"),
            TextChapter: Cap("textChapter"),
            ReverseSearch: Cap("reverseSearch"),
            Rankings: Cap("rankings"),
            Subscription: Cap("subscription"),
            SubscriptionUpdates: Cap("subscriptionUpdates"),
            Album: Cap("album"),
            OnlineGame: Cap("onlineGame"),
            GameResources: Cap("gameResources"),
            Comments: Cap("comments"),
            PreviewContent: Cap("previewContent") || (obj["previewContent"]?.GetValue<bool>() ?? false),
            PostShortVideos: Cap("postShortVideos") || (obj["postShortVideos"]?.GetValue<bool>() ?? false),
            MetadataOnly: obj["metadataOnly"]?.GetValue<bool>() ?? false,
            RankingOnly: obj["rankingOnly"]?.GetValue<bool>() ?? false);

        var i18n = new Dictionary<string, IReadOnlyDictionary<string, string>>(StringComparer.Ordinal);
        if (obj["i18n"] is JsonObject i18nObj)
        {
            foreach (var langEntry in i18nObj)
            {
                if (langEntry.Value is JsonObject table)
                {
                    var map = new Dictionary<string, string>(StringComparer.Ordinal);
                    foreach (var pair in table)
                    {
                        if (pair.Value is JsonValue v && v.TryGetValue<string>(out var str))
                            map[pair.Key] = str;
                    }
                    i18n[langEntry.Key] = map;
                }
            }
        }

        return new SourceManifest(
            key, name, version, minAppVersion, type, category, color, desc, homepage,
            domains, linkPatterns, idPattern, defaultFeed, anonFeed, browseLayout,
            netMode, vpnHint, imgHeaders, decrypt, feeds, searchFilters, settings, caps, i18n,
            (JsonObject)obj.DeepClone());
    }

    private static List<string> ReadStringList(JsonNode? node)
    {
        if (node is not JsonArray arr) return [];
        var list = new List<string>(arr.Count);
        foreach (var item in arr)
        {
            if (item is JsonValue v && v.TryGetValue<string>(out var s) && !string.IsNullOrWhiteSpace(s))
                list.Add(s);
        }
        return list;
    }

    private static List<FilterOptionDef> ReadFilterOptions(JsonArray? arr)
    {
        if (arr is null) return [];
        var result = new List<FilterOptionDef>();
        foreach (var item in arr.OfType<JsonObject>())
        {
            var choices = new List<FeedChoice>();
            var valuesArr = (item["values"] ?? item["options"]) as JsonArray;
            if (valuesArr is not null)
            {
                foreach (var c in valuesArr.OfType<JsonObject>())
                {
                    choices.Add(new FeedChoice(
                        c["value"]?.ToString() ?? string.Empty,
                        c["label"]?.GetValue<string>() ?? string.Empty,
                        c["color"]?.GetValue<string>()));
                }
            }
            result.Add(new FilterOptionDef(
                item["key"]?.GetValue<string>() ?? string.Empty,
                item["label"]?.GetValue<string>() ?? string.Empty,
                item["type"]?.GetValue<string>() ?? "select",
                item["default"]?.ToString() ?? string.Empty,
                choices,
                item["dynamic"]?.GetValue<bool>() ?? false,
                ReadStringList(item["dependsOn"]), item["step"]?.GetValue<double>() ?? 1,
                item["min"]?.GetValue<double>(), item["max"]?.GetValue<double>()));
        }
        return result;
    }
}

public sealed record WorkItem(
    string Source,
    string Id,
    string Title,
    string Subtitle,
    string Cover,
    bool CoverBlurred,
    double? CoverAspect,
    int? Pages,
    double? Rating,
    long? Likes,
    long? Views,
    string Language,
    string Category,
    string Badge,
    string? BadgeColor,
    string Duration,
    string Uploaded,
    string MediaKind,
    string? WorkCode,
    IReadOnlyList<string> Tags,
    IReadOnlyList<string> Authors,
    string? Uploader,
    JsonObject RawJson)
{
    public string Uid => $"{Source}:{Id}";

    public static WorkItem FromJson(string sourceKey, JsonObject obj, string fallbackMediaKind = "comic")
    {
        var id = obj["id"]?.ToString() ?? string.Empty;
        var title = obj["title"]?.GetValue<string>() ?? string.Empty;
        var subtitle = obj["subtitle"]?.GetValue<string>() ?? string.Empty;
        var cover = obj["cover"]?.GetValue<string>() ?? string.Empty;
        var blurred = obj["coverBlurred"]?.GetValue<bool>() ?? false;
        double? aspect = obj["coverAspect"] is JsonValue av && av.TryGetValue<double>(out var ad) && double.IsFinite(ad) && ad > 0 ? ad : null;
        int? pages = obj["pages"] is JsonValue pv && pv.TryGetValue<int>(out var pi) ? pi : null;
        double? rating = obj["rating"] is JsonValue rv && rv.TryGetValue<double>(out var rd) ? rd : null;
        long? likes = obj["likes"] is JsonValue lv && lv.TryGetValue<long>(out var ll) ? ll : null;
        long? views = obj["views"] is JsonValue vv && vv.TryGetValue<long>(out var vl) ? vl : null;
        var language = obj["language"]?.GetValue<string>() ?? string.Empty;
        var category = obj["category"]?.GetValue<string>() ?? string.Empty;
        var badge = obj["badge"]?.GetValue<string>() ?? string.Empty;
        var badgeColor = obj["badgeColor"]?.GetValue<string>();
        var duration = obj["duration"]?.ToString() ?? string.Empty;
        var uploaded = obj["uploaded"]?.GetValue<string>() ?? string.Empty;
        var mediaKind = obj["mediaKind"]?.GetValue<string>() ?? fallbackMediaKind;
        var workCode = obj["workCode"]?.GetValue<string>();
        var uploader = obj["uploader"]?.GetValue<string>();

        var tags = new List<string>();
        if (obj["tags"] is JsonArray tArr)
        {
            foreach (var t in tArr)
            {
                if (t is JsonValue tv && tv.TryGetValue<string>(out var ts) && !string.IsNullOrWhiteSpace(ts))
                    tags.Add(ts);
                else if (t is JsonObject to && to["name"]?.GetValue<string>() is { Length: > 0 } tn)
                    tags.Add(tn);
            }
        }

        var authors = new List<string>();
        if (obj["authors"] is JsonArray aArr)
        {
            foreach (var a in aArr)
            {
                if (a is JsonValue av2 && av2.TryGetValue<string>(out var as2) && !string.IsNullOrWhiteSpace(as2))
                    authors.Add(as2);
            }
        }

        var clone = (JsonObject)obj.DeepClone();
        clone["source"] = sourceKey;
        clone["id"] = id;
        return new WorkItem(
            sourceKey, id, title, subtitle, cover, blurred, aspect, pages, rating, likes, views,
            language, category, badge, badgeColor, duration, uploaded, mediaKind, workCode,
            tags, authors, uploader, clone);
    }
}

public sealed record WorkSection(string Title, IReadOnlyList<WorkItem> Items);

public sealed record WorkPage(
    IReadOnlyList<WorkItem> Items,
    IReadOnlyList<WorkSection> Sections,
    int Page,
    int? TotalPages,
    int? Total,
    bool HasNext,
    string? Cursor);

public sealed record TagEntry(string Name, string Keyword, int? Count = null);
public sealed record TagGroup(string Namespace, string Label, IReadOnlyList<TagEntry> Tags);
public sealed record ChapterInfo(string Id, string Title);

public sealed record ArticleBlock(string Type, string? Text = null, string? Url = null, string? VideoId = null, string? Preview = null);

public sealed record WorkDetail(
    WorkItem Item,
    string Url,
    string Description,
    IReadOnlyList<TagGroup> TagGroups,
    IReadOnlyList<ChapterInfo>? Chapters,
    string SingleChapterId,
    IReadOnlyList<string> Thumbnails,
    IReadOnlyList<WorkItem> Related,
    IReadOnlyList<WorkItem> Variants,
    IReadOnlyList<ArticleBlock> Blocks)
{
    public IReadOnlyList<ChapterInfo> EffectiveChapters =>
        Chapters is { Count: > 0 }
            ? Chapters
            : [new ChapterInfo(string.IsNullOrEmpty(SingleChapterId) ? "_" : SingleChapterId, Item.Title)];
}

public sealed record PageTransform(string Type, int Segments);

public sealed record ChapterPage(
    int Index,
    string? Url,
    string? Token,
    IReadOnlyDictionary<string, string>? Headers,
    IReadOnlyList<string> Fallbacks,
    int? Width,
    int? Height,
    PageTransform? Transform);

public sealed record VideoStream(
    int Quality,
    string Label,
    string Url,
    string Format,
    bool Preferred,
    IReadOnlyDictionary<string, string> Headers,
    IReadOnlyDictionary<string, IReadOnlyList<string>> FallbackHosts);

public sealed record TextChapterData(string Title, IReadOnlyList<string> Paragraphs)
{
    public string FullText => string.Join("\n\n", Paragraphs);
}

public sealed record ReverseSearchMatch(
    string SourceKey,
    string SourceName,
    string Title,
    string? Keyword,
    string? Description,
    string? Url,
    double? Similarity,
    bool Uncertain,
    string? PreviewImage);
