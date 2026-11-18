using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.Sqlite;
using Park.Core.Configuration;
using Park.Core.Lifecycle;
using Park.Core.Localization;

namespace Park.Library;

public sealed record BackupOptions(
    bool IncludeLibrary = true,
    bool IncludeSettings = true,
    bool IncludeSources = true,
    bool IncludeCredentials = false,
    bool Automatic = false);

public sealed class RestoreReport
{
    public int Categories { get; set; }
    public int Favorites { get; set; }
    public int Chapters { get; set; }
    public int History { get; set; }
    public bool Settings { get; set; }
    public int Sources { get; set; }
    public int Subscriptions { get; set; }

    public string Summary
    {
        get
        {
            var parts = new List<string>();
            if (Favorites > 0) parts.Add(L.Tr("收藏 {value0}", new Dictionary<string, object?> { ["value0"] = Favorites }));
            if (Categories > 0) parts.Add(L.Tr("分类 {value0}", new Dictionary<string, object?> { ["value0"] = Categories }));
            if (Chapters > 0) parts.Add(L.Tr("章节进度 {value0}", new Dictionary<string, object?> { ["value0"] = Chapters }));
            if (History > 0) parts.Add(L.Tr("历史 {value0}", new Dictionary<string, object?> { ["value0"] = History }));
            if (Settings) parts.Add(L.Tr("设置"));
            if (Sources > 0) parts.Add(L.Tr("站点设置 {value0}", new Dictionary<string, object?> { ["value0"] = Sources }));
            if (Subscriptions > 0) parts.Add(L.Tr("订阅 {value0}", new Dictionary<string, object?> { ["value0"] = Subscriptions }));
            return parts.Count > 0 ? string.Join(L.Tr("、"), parts) : "0";
        }
    }
}

/// <summary>
/// 100% compatible with Android lib/library/backup.dart (.parkbak format = "parkbak", version = 1).
/// Streaming GZip UTF-8 JSON export (512-row keyset cursor batches) and non-destructive merge restore.
/// </summary>
public sealed class BackupService
{
    public const string Format = "parkbak";
    public const int Version = 1;
    public const string Extension = ".parkbak";

    private readonly LibraryStore _library;
    private readonly SerialExecutor _writes = new();
    private bool _suspended;

    public BackupService(LibraryStore library)
    {
        _library = library;
    }

    public async Task RecoverPendingCheckpointsAsync(CancellationToken ct = default)
    {
        // Clean up already-committed restore_checkpoints marker on launch per DEVELOPMENT.md
        await _library.Database.WriteTransactionAsync(async (conn, tx) =>
        {
            await ParkDatabase.ExecuteNonQueryAsync(conn, "DELETE FROM restore_checkpoints;", ct, tx).ConfigureAwait(false);
        }, ct).ConfigureAwait(false);
    }

    public async Task SuspendAsync()
    {
        _suspended = true;
        await _writes.Settled.ConfigureAwait(false);
    }

    public void Resume() => _suspended = false;

    public Task<byte[]> CreateBytesAsync(
        BackupOptions? options = null,
        Func<bool, Task<JsonObject>>? exportSources = null,
        CancellationToken ct = default)
    {
        if (_suspended) throw new InvalidOperationException("Backup service is suspended.");
        var opts = options ?? new BackupOptions();
        return _writes.RunAsync(() => CreateBytesInternalAsync(opts, exportSources, ct));
    }

    public async Task<string> WriteToDirectoryAsync(
        string directory,
        BackupOptions? options = null,
        Func<bool, Task<JsonObject>>? exportSources = null,
        CancellationToken ct = default)
    {
        if (_suspended) throw new InvalidOperationException("Backup service is suspended.");
        var opts = options ?? new BackupOptions();
        return await _writes.RunAsync(async () =>
        {
            Directory.CreateDirectory(directory);
            var bytes = await CreateBytesInternalAsync(opts, exportSources, ct).ConfigureAwait(false);
            var baseName = BuildFileName(DateTime.Now);
            var path = Path.Combine(directory, baseName);
            for (var suffix = 2; File.Exists(path); suffix++)
            {
                var stem = Path.GetFileNameWithoutExtension(baseName);
                path = Path.Combine(directory, $"{stem}_{suffix:D6}{Extension}");
            }
            await AppPaths.WriteFileAtomicAsync(path, bytes, ct).ConfigureAwait(false);
            return path;
        }).ConfigureAwait(false);
    }

    public static string BuildFileName(DateTime localTime) =>
        $"hentaipark_{localTime:yyyyMMdd_HHmmss}{Extension}";

    public static JsonObject DecodeAndValidate(ReadOnlySpan<byte> compressedBytes)
    {
        JsonNode? node;
        try
        {
            using var ms = new MemoryStream(compressedBytes.ToArray());
            using var gz = new GZipStream(ms, CompressionMode.Decompress);
            node = JsonNode.Parse(gz);
        }
        catch (Exception ex)
        {
            throw new FormatException(L.Tr("不是有效的备份文件"), ex);
        }

        if (node is not JsonObject obj || obj["format"]?.GetValue<string>() != Format)
            throw new FormatException(L.Tr("不是 HentaiPark 备份文件"));

        if (obj["version"] is not JsonValue verVal || !verVal.TryGetValue<int>(out var ver) || ver < 1)
            throw new FormatException("备份数据无效");

        if (ver > Version)
            throw new FormatException(L.Tr("备份来自更新版本的应用，请先升级"));

        return obj;
    }

    public Task<RestoreReport> RestoreAsync(
        byte[] bytes,
        Func<JsonObject, Task<int>>? importSources = null,
        CancellationToken ct = default)
    {
        if (_suspended) throw new InvalidOperationException("Backup service is suspended.");
        return _writes.RunAsync(() => RestoreInternalAsync(bytes, importSources, ct));
    }

    private async Task<byte[]> CreateBytesInternalAsync(
        BackupOptions options,
        Func<bool, Task<JsonObject>>? exportSources,
        CancellationToken ct)
    {
        await _library.FlushAsync(ct).ConfigureAwait(false);
        await AppSettings.Instance.FlushAsync(ct).ConfigureAwait(false);

        using var ms = new MemoryStream();
        await using (var gz = new GZipStream(ms, CompressionLevel.Optimal, leaveOpen: true))
        await using (var writer = new Utf8JsonWriter(gz))
        {
            writer.WriteStartObject();
            writer.WriteString("format", Format);
            writer.WriteNumber("version", Version);
            writer.WriteNumber("createdAt", DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
            writer.WriteString("origin", options.Automatic ? "automatic" : "manual");

            if (options.IncludeSettings)
            {
                writer.WritePropertyName("settings");
                AppSettings.Instance.ExportJson().WriteTo(writer);
            }

            if (options.IncludeSources && exportSources is not null)
            {
                var srcJson = await exportSources(options.IncludeCredentials).ConfigureAwait(false);
                writer.WritePropertyName("sources");
                srcJson.WriteTo(writer);
            }

            if (options.IncludeLibrary)
            {
                await _library.Database.ReadAsync(async conn =>
                {
                    // Subscriptions
                    writer.WritePropertyName("subscriptions");
                    await WriteSubscriptionsAsync(conn, writer, ct).ConfigureAwait(false);

                    // Library sections streamed in 512-row keyset batches
                    writer.WritePropertyName("library");
                    writer.WriteStartObject();
                    await WriteCategoriesBatchAsync(conn, writer, ct).ConfigureAwait(false);
                    await WriteWorksBatchAsync(conn, writer, ct).ConfigureAwait(false);
                    await WriteChaptersBatchAsync(conn, writer, ct).ConfigureAwait(false);
                    await WriteHistoryBatchAsync(conn, writer, ct).ConfigureAwait(false);
                    writer.WriteEndObject();
                    return true;
                }, ct).ConfigureAwait(false);
            }

            writer.WriteEndObject();
            await writer.FlushAsync(ct).ConfigureAwait(false);
        }
        return ms.ToArray();
    }

    private async Task<RestoreReport> RestoreInternalAsync(
        byte[] bytes,
        Func<JsonObject, Task<int>>? importSources,
        CancellationToken ct)
    {
        var json = DecodeAndValidate(bytes);
        var report = new RestoreReport();

        await _library.FlushAsync(ct).ConfigureAwait(false);
        await AppSettings.Instance.FlushAsync(ct).ConfigureAwait(false);

        var token = Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(16));

        // Phase 1: Stage settings file if present
        if (json["settings"] is JsonObject settingsObj)
        {
            var mergedSettings = AppSettings.Instance.PrepareImport(settingsObj);
            await AppPaths.WriteTextAtomicAsync(
                AppPaths.SettingsFile,
                mergedSettings.ToJsonString(new JsonSerializerOptions { WriteIndented = true }),
                ct).ConfigureAwait(false);
            await AppSettings.Instance.LoadAsync(ct).ConfigureAwait(false);
            report.Settings = true;
        }

        if (json["sources"] is JsonObject sourcesObj && importSources is not null)
        {
            report.Sources = await importSources(sourcesObj).ConfigureAwait(false);
        }

        // Phase 2: Atomic SQLite merge with restore_checkpoints marker
        await _library.Database.WriteTransactionAsync(async (conn, tx) =>
        {
            await using (var cp = conn.CreateCommand())
            {
                cp.Transaction = tx;
                cp.CommandText = "INSERT OR REPLACE INTO restore_checkpoints (id, token) VALUES (1, $token);";
                cp.Parameters.AddWithValue("$token", token);
                await cp.ExecuteNonQueryAsync(ct).ConfigureAwait(false);
            }

            if (json["subscriptions"] is JsonObject subsObj)
            {
                report.Subscriptions = await MergeSubscriptionsAsync(conn, tx, subsObj, ct).ConfigureAwait(false);
            }

            if (json["library"] is JsonObject libObj)
            {
                await MergeLibraryTablesAsync(conn, tx, libObj, report, ct).ConfigureAwait(false);
            }

            await ParkDatabase.ExecuteNonQueryAsync(conn, "DELETE FROM restore_checkpoints WHERE id = 1;", ct, tx).ConfigureAwait(false);
        }, ct).ConfigureAwait(false);

        return report;
    }

    private static async Task WriteSubscriptionsAsync(SqliteConnection conn, Utf8JsonWriter writer, CancellationToken ct)
    {
        writer.WriteStartObject();
        writer.WritePropertyName("targets");
        writer.WriteStartArray();

        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT identity, source, dimension, target, label, enabled, notify, created_at FROM subscriptions ORDER BY created_at ASC;";
        await using var r = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
        while (await r.ReadAsync(ct).ConfigureAwait(false))
        {
            writer.WriteStartObject();
            writer.WriteString("identity", r.GetString(0));
            writer.WriteString("source", r.GetString(1));
            writer.WriteString("dimension", r.GetString(2));
            writer.WriteString("target", r.GetString(3));
            writer.WriteString("label", r.GetString(4));
            writer.WriteBoolean("enabled", r.GetInt32(5) == 1);
            writer.WriteBoolean("notify", r.GetInt32(6) == 1);
            writer.WriteNumber("createdAt", r.GetInt64(7));
            writer.WriteEndObject();
        }

        writer.WriteEndArray();
        writer.WriteEndObject();
    }

    private static async Task<int> MergeSubscriptionsAsync(SqliteConnection conn, SqliteTransaction tx, JsonObject subsObj, CancellationToken ct)
    {
        var count = 0;
        if (subsObj["targets"] is not JsonArray arr) return 0;
        foreach (var node in arr.OfType<JsonObject>())
        {
            var source = node["source"]?.GetValue<string>() ?? string.Empty;
            var dimension = node["dimension"]?.GetValue<string>() ?? "posts";
            var target = node["target"]?.GetValue<string>() ?? string.Empty;
            if (string.IsNullOrEmpty(source) || string.IsNullOrEmpty(target)) continue;

            var identity = node["identity"]?.GetValue<string>() ?? $"{source}:{dimension}:{target}";
            var label = node["label"]?.GetValue<string>() ?? target;
            var enabled = node["enabled"]?.GetValue<bool>() ?? true;
            var notify = node["notify"]?.GetValue<bool>() ?? true;
            var createdAt = node["createdAt"]?.GetValue<long>() ?? DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();

            await using var cmd = conn.CreateCommand();
            cmd.Transaction = tx;
            cmd.CommandText = """
                INSERT OR IGNORE INTO subscriptions (identity, source, dimension, target, label, enabled, notify, created_at)
                VALUES ($id, $src, $dim, $tgt, $lbl, $en, $not, $ca);
                """;
            cmd.Parameters.AddWithValue("$id", identity);
            cmd.Parameters.AddWithValue("$src", source);
            cmd.Parameters.AddWithValue("$dim", dimension);
            cmd.Parameters.AddWithValue("$tgt", target);
            cmd.Parameters.AddWithValue("$lbl", label);
            cmd.Parameters.AddWithValue("$en", enabled ? 1 : 0);
            cmd.Parameters.AddWithValue("$not", notify ? 1 : 0);
            cmd.Parameters.AddWithValue("$ca", createdAt);
            var inserted = await cmd.ExecuteNonQueryAsync(ct).ConfigureAwait(false);
            if (inserted > 0) count++;
        }
        return count;
    }

    private static async Task WriteCategoriesBatchAsync(SqliteConnection conn, Utf8JsonWriter writer, CancellationToken ct)
    {
        writer.WritePropertyName("categories");
        writer.WriteStartArray();
        long cursor = 0;
        while (true)
        {
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT rowid, name, sort FROM categories WHERE rowid > $cur ORDER BY rowid LIMIT 512;";
            cmd.Parameters.AddWithValue("$cur", cursor);
            var rows = 0;
            await using var r = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
            while (await r.ReadAsync(ct).ConfigureAwait(false))
            {
                rows++;
                cursor = r.GetInt64(0);
                writer.WriteStartObject();
                writer.WriteString("name", r.GetString(1));
                writer.WriteNumber("sort", r.GetInt32(2));
                writer.WriteEndObject();
            }
            if (rows == 0) break;
        }
        writer.WriteEndArray();
    }

    private static async Task WriteWorksBatchAsync(SqliteConnection conn, Utf8JsonWriter writer, CancellationToken ct)
    {
        writer.WritePropertyName("works");
        writer.WriteStartArray();
        long cursor = 0;
        while (true)
        {
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = """
                SELECT w.rowid, w.source, w.id, w.json, w.favorite, w.favorited_at, w.reader_mode,
                       (SELECT json_group_array(c.name) FROM work_categories m
                        JOIN categories c ON c.id = m.category_id
                        WHERE m.source = w.source AND m.work_id = w.id)
                FROM works w
                WHERE w.rowid > $cur AND (
                    w.favorite = 1 OR w.reader_mode IS NOT NULL OR EXISTS (
                        SELECT 1 FROM work_categories m WHERE m.source = w.source AND m.work_id = w.id
                    )
                )
                ORDER BY w.rowid LIMIT 512;
                """;
            cmd.Parameters.AddWithValue("$cur", cursor);
            var rows = 0;
            await using var r = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
            while (await r.ReadAsync(ct).ConfigureAwait(false))
            {
                rows++;
                cursor = r.GetInt64(0);
                writer.WriteStartObject();
                writer.WritePropertyName("item");
                using (var itemDoc = JsonDocument.Parse(r.GetString(3)))
                    itemDoc.RootElement.WriteTo(writer);
                writer.WriteString("source", r.GetString(1));
                writer.WriteString("id", r.GetString(2));
                writer.WriteBoolean("favorite", r.GetInt32(4) == 1);
                if (!r.IsDBNull(5)) writer.WriteNumber("favoritedAt", r.GetInt64(5));
                else writer.WriteNull("favoritedAt");
                if (!r.IsDBNull(6)) writer.WriteNumber("readerMode", r.GetInt32(6));
                else writer.WriteNull("readerMode");
                writer.WritePropertyName("categories");
                using (var catDoc = JsonDocument.Parse(r.IsDBNull(7) ? "[]" : r.GetString(7)))
                    catDoc.RootElement.WriteTo(writer);
                writer.WriteEndObject();
            }
            if (rows == 0) break;
        }
        writer.WriteEndArray();
    }

    private static async Task WriteChaptersBatchAsync(SqliteConnection conn, Utf8JsonWriter writer, CancellationToken ct)
    {
        writer.WritePropertyName("chapters");
        writer.WriteStartArray();
        long cursor = 0;
        while (true)
        {
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = """
                SELECT rowid, source, work_id, chapter_id, title, sort, "read", last_page, page_count,
                       progress_updated_at, date_read, position, duration, position_updated_at
                FROM chapters
                WHERE rowid > $cur AND ("read" = 1 OR progress_updated_at IS NOT NULL OR position_updated_at IS NOT NULL)
                ORDER BY rowid LIMIT 512;
                """;
            cmd.Parameters.AddWithValue("$cur", cursor);
            var rows = 0;
            await using var r = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
            while (await r.ReadAsync(ct).ConfigureAwait(false))
            {
                rows++;
                cursor = r.GetInt64(0);
                writer.WriteStartObject();
                writer.WriteString("source", r.GetString(1));
                writer.WriteString("workId", r.GetString(2));
                writer.WriteString("chapterId", r.GetString(3));
                writer.WriteString("title", r.GetString(4));
                writer.WriteNumber("sort", r.GetInt32(5));
                writer.WriteBoolean("read", r.GetInt32(6) == 1);
                writer.WriteNumber("lastPage", r.GetInt32(7));
                writer.WriteNumber("pageCount", r.GetInt32(8));
                if (!r.IsDBNull(9)) writer.WriteNumber("progressUpdatedAt", r.GetInt64(9)); else writer.WriteNull("progressUpdatedAt");
                if (!r.IsDBNull(10)) writer.WriteNumber("dateRead", r.GetInt64(10)); else writer.WriteNull("dateRead");
                writer.WriteNumber("position", r.GetInt32(11));
                writer.WriteNumber("duration", r.GetInt32(12));
                if (!r.IsDBNull(13)) writer.WriteNumber("positionUpdatedAt", r.GetInt64(13)); else writer.WriteNull("positionUpdatedAt");
                writer.WriteEndObject();
            }
            if (rows == 0) break;
        }
        writer.WriteEndArray();
    }

    private static async Task WriteHistoryBatchAsync(SqliteConnection conn, Utf8JsonWriter writer, CancellationToken ct)
    {
        writer.WritePropertyName("history");
        writer.WriteStartArray();
        long cursor = 0;
        while (true)
        {
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = """
                SELECT h.rowid, h.source, h.work_id, h.time, h.chapter_id, h.chapter_title, h.page, h.page_count, h.position, w.json
                FROM history h
                JOIN works w ON w.source = h.source AND w.id = h.work_id
                WHERE h.rowid > $cur ORDER BY h.rowid LIMIT 512;
                """;
            cmd.Parameters.AddWithValue("$cur", cursor);
            var rows = 0;
            await using var r = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
            while (await r.ReadAsync(ct).ConfigureAwait(false))
            {
                rows++;
                cursor = r.GetInt64(0);
                writer.WriteStartObject();
                writer.WritePropertyName("item");
                using (var doc = JsonDocument.Parse(r.GetString(9)))
                    doc.RootElement.WriteTo(writer);
                writer.WriteString("source", r.GetString(1));
                writer.WriteString("workId", r.GetString(2));
                writer.WriteNumber("time", r.GetInt64(3));
                if (!r.IsDBNull(4)) writer.WriteString("chapterId", r.GetString(4)); else writer.WriteNull("chapterId");
                if (!r.IsDBNull(5)) writer.WriteString("chapterTitle", r.GetString(5)); else writer.WriteNull("chapterTitle");
                writer.WriteNumber("page", r.GetInt32(6));
                writer.WriteNumber("pageCount", r.GetInt32(7));
                if (!r.IsDBNull(8)) writer.WriteNumber("position", r.GetInt32(8)); else writer.WriteNull("position");
                writer.WriteEndObject();
            }
            if (rows == 0) break;
        }
        writer.WriteEndArray();
    }

    private static async Task MergeLibraryTablesAsync(
        SqliteConnection conn,
        SqliteTransaction tx,
        JsonObject lib,
        RestoreReport report,
        CancellationToken ct)
    {
        // 1. Categories
        var catIds = new Dictionary<string, long>(StringComparer.Ordinal);
        await using (var existingCats = conn.CreateCommand())
        {
            existingCats.Transaction = tx;
            existingCats.CommandText = "SELECT id, name FROM categories;";
            await using var r = await existingCats.ExecuteReaderAsync(ct).ConfigureAwait(false);
            while (await r.ReadAsync(ct).ConfigureAwait(false))
                catIds[r.GetString(1)] = r.GetInt64(0);
        }

        var nextSort = catIds.Count;
        if (lib["categories"] is JsonArray catArr)
        {
            foreach (var c in catArr.OfType<JsonObject>())
            {
                var name = c["name"]?.GetValue<string>() ?? string.Empty;
                if (string.IsNullOrEmpty(name) || catIds.ContainsKey(name)) continue;

                await using var ins = conn.CreateCommand();
                ins.Transaction = tx;
                ins.CommandText = "INSERT INTO categories (name, sort) VALUES ($n, $s); SELECT last_insert_rowid();";
                ins.Parameters.AddWithValue("$n", name);
                ins.Parameters.AddWithValue("$s", nextSort++);
                var newId = Convert.ToInt64(await ins.ExecuteScalarAsync(ct).ConfigureAwait(false));
                catIds[name] = newId;
                report.Categories++;
            }
        }

        // Helper to insert/ignore work snapshot
        async Task EnsureWorkAsync(JsonObject? itemObj, string src, string id)
        {
            var mergedItem = itemObj is not null ? (JsonObject)itemObj.DeepClone() : new JsonObject();
            mergedItem["source"] = src;
            mergedItem["id"] = id;
            await using var wIns = conn.CreateCommand();
            wIns.Transaction = tx;
            wIns.CommandText = """
                INSERT OR IGNORE INTO works (source, id, title, cover, json)
                VALUES ($s, $i, $t, $c, $j);
                """;
            wIns.Parameters.AddWithValue("$s", src);
            wIns.Parameters.AddWithValue("$i", id);
            wIns.Parameters.AddWithValue("$t", mergedItem["title"]?.ToString() ?? string.Empty);
            wIns.Parameters.AddWithValue("$c", mergedItem["cover"]?.ToString() ?? string.Empty);
            wIns.Parameters.AddWithValue("$j", mergedItem.ToJsonString());
            await wIns.ExecuteNonQueryAsync(ct).ConfigureAwait(false);
        }

        // 2. Works (union favorites & categories)
        if (lib["works"] is JsonArray worksArr)
        {
            foreach (var w in worksArr.OfType<JsonObject>())
            {
                var src = w["source"]?.ToString() ?? string.Empty;
                var id = w["id"]?.ToString() ?? string.Empty;
                if (string.IsNullOrEmpty(src) || string.IsNullOrEmpty(id)) continue;

                await EnsureWorkAsync(w["item"] as JsonObject, src, id).ConfigureAwait(false);

                bool curFav = false;
                long? curFavAt = null;
                int? curReaderMode = null;
                await using (var sel = conn.CreateCommand())
                {
                    sel.Transaction = tx;
                    sel.CommandText = "SELECT favorite, favorited_at, reader_mode FROM works WHERE source = $s AND id = $i;";
                    sel.Parameters.AddWithValue("$s", src);
                    sel.Parameters.AddWithValue("$i", id);
                    await using var r = await sel.ExecuteReaderAsync(ct).ConfigureAwait(false);
                    if (await r.ReadAsync(ct).ConfigureAwait(false))
                    {
                        curFav = r.GetInt32(0) == 1;
                        curFavAt = r.IsDBNull(1) ? null : r.GetInt64(1);
                        curReaderMode = r.IsDBNull(2) ? null : r.GetInt32(2);
                    }
                }

                var incomingFav = w["favorite"]?.GetValue<bool>() ?? false;
                var incomingFavAt = w["favoritedAt"] is JsonValue fv && fv.TryGetValue<long>(out var fl) ? (long?)fl : null;
                var incomingMode = w["readerMode"] is JsonValue mv && mv.TryGetValue<int>(out var mi) ? (int?)mi : null;

                await using (var upd = conn.CreateCommand())
                {
                    upd.Transaction = tx;
                    upd.CommandText = "UPDATE works SET favorite = $f, favorited_at = $fa, reader_mode = $rm WHERE source = $s AND id = $i;";
                    upd.Parameters.AddWithValue("$f", (curFav || incomingFav) ? 1 : 0);
                    var mergedFavAt = curFav ? curFavAt : (incomingFavAt ?? curFavAt);
                    upd.Parameters.AddWithValue("$fa", mergedFavAt is { } fa ? fa : DBNull.Value);
                    var mergedMode = curReaderMode ?? incomingMode;
                    upd.Parameters.AddWithValue("$rm", mergedMode is { } rm ? rm : DBNull.Value);
                    upd.Parameters.AddWithValue("$s", src);
                    upd.Parameters.AddWithValue("$i", id);
                    await upd.ExecuteNonQueryAsync(ct).ConfigureAwait(false);
                }

                if (incomingFav && !curFav) report.Favorites++;

                if (w["categories"] is JsonArray wcArr)
                {
                    foreach (var cn in wcArr)
                    {
                        var cName = cn?.ToString() ?? string.Empty;
                        if (!catIds.TryGetValue(cName, out var cid)) continue;
                        await using var wcIns = conn.CreateCommand();
                        wcIns.Transaction = tx;
                        wcIns.CommandText = "INSERT OR IGNORE INTO work_categories (source, work_id, category_id) VALUES ($s, $w, $c);";
                        wcIns.Parameters.AddWithValue("$s", src);
                        wcIns.Parameters.AddWithValue("$w", id);
                        wcIns.Parameters.AddWithValue("$c", cid);
                        await wcIns.ExecuteNonQueryAsync(ct).ConfigureAwait(false);
                    }
                }
            }
        }

        // 3. Chapters (ProgressMerge newer-wins per comic/video/read timestamp)
        if (lib["chapters"] is JsonArray chArr)
        {
            foreach (var c in chArr.OfType<JsonObject>())
            {
                var src = c["source"]?.ToString() ?? string.Empty;
                var wid = c["workId"]?.ToString() ?? string.Empty;
                var cid = c["chapterId"]?.ToString() ?? string.Empty;
                if (string.IsNullOrEmpty(src) || string.IsNullOrEmpty(wid) || string.IsNullOrEmpty(cid)) continue;

                var inRead = c["read"]?.GetValue<bool>() ?? false;
                var inLastPage = c["lastPage"] is JsonValue lpv && lpv.TryGetValue<int>(out var lpi) ? lpi : 0;
                var inPageCount = c["pageCount"] is JsonValue pcv && pcv.TryGetValue<int>(out var pci) ? pci : 0;
                var inDateRead = c["dateRead"] is JsonValue drv && drv.TryGetValue<long>(out var drl) ? (long?)drl : null;
                var inProgAt = c["progressUpdatedAt"] is JsonValue pav && pav.TryGetValue<long>(out var pal) ? (long?)pal : null;
                var inPos = Math.Max(0, c["position"] is JsonValue posv && posv.TryGetValue<int>(out var posi) ? posi : 0);
                var inDur = Math.Max(0, c["duration"] is JsonValue durv && durv.TryGetValue<int>(out var duri) ? duri : 0);
                var inPosAt = c["positionUpdatedAt"] is JsonValue psav && psav.TryGetValue<long>(out var psal) ? (long?)psal : null;

                bool exists = false;
                bool curRead = false;
                int curLp = 0, curPc = 0, curPos = 0, curDur = 0;
                long? curDr = null, curProgAt = null, curPosAt = null;

                await using (var sel = conn.CreateCommand())
                {
                    sel.Transaction = tx;
                    sel.CommandText = """
                        SELECT "read", last_page, page_count, date_read, progress_updated_at, position, duration, position_updated_at
                        FROM chapters WHERE source = $s AND work_id = $w AND chapter_id = $c;
                        """;
                    sel.Parameters.AddWithValue("$s", src);
                    sel.Parameters.AddWithValue("$w", wid);
                    sel.Parameters.AddWithValue("$c", cid);
                    await using var r = await sel.ExecuteReaderAsync(ct).ConfigureAwait(false);
                    if (await r.ReadAsync(ct).ConfigureAwait(false))
                    {
                        exists = true;
                        curRead = r.GetInt32(0) == 1;
                        curLp = r.GetInt32(1);
                        curPc = r.GetInt32(2);
                        curDr = r.IsDBNull(3) ? null : r.GetInt64(3);
                        curProgAt = r.IsDBNull(4) ? null : r.GetInt64(4);
                        curPos = r.GetInt32(5);
                        curDur = r.GetInt32(6);
                        curPosAt = r.IsDBNull(7) ? null : r.GetInt64(7);
                    }
                }

                if (!exists)
                {
                    await using var ins = conn.CreateCommand();
                    ins.Transaction = tx;
                    ins.CommandText = """
                        INSERT INTO chapters (source, work_id, chapter_id, title, sort, "read", last_page, page_count, progress_updated_at, date_read, position, duration, position_updated_at)
                        VALUES ($s, $w, $c, $t, $sort, $r, $lp, $pc, $pa, $dr, $pos, $dur, $posa);
                        """;
                    ins.Parameters.AddWithValue("$s", src);
                    ins.Parameters.AddWithValue("$w", wid);
                    ins.Parameters.AddWithValue("$c", cid);
                    ins.Parameters.AddWithValue("$t", c["title"]?.ToString() ?? string.Empty);
                    ins.Parameters.AddWithValue("$sort", c["sort"] is JsonValue sv && sv.TryGetValue<int>(out var si) ? si : 0);
                    ins.Parameters.AddWithValue("$r", inRead ? 1 : 0);
                    ins.Parameters.AddWithValue("$lp", inLastPage);
                    ins.Parameters.AddWithValue("$pc", inPageCount);
                    ins.Parameters.AddWithValue("$pa", inProgAt is { } pa ? pa : DBNull.Value);
                    var effectiveDr = inPosAt is not null && !inRead ? null : inDateRead;
                    ins.Parameters.AddWithValue("$dr", effectiveDr is { } dr ? dr : DBNull.Value);
                    ins.Parameters.AddWithValue("$pos", inPos);
                    ins.Parameters.AddWithValue("$dur", inDur);
                    ins.Parameters.AddWithValue("$posa", inPosAt is { } posa ? posa : DBNull.Value);
                    await ins.ExecuteNonQueryAsync(ct).ConfigureAwait(false);
                }
                else
                {
                    var sel = ProgressMerge.Select(inProgAt, inPosAt, curProgAt, curPosAt);
                    var mergedRead = sel.Read ? inRead : curRead;
                    var mergedLp = sel.Comic ? inLastPage : curLp;
                    var mergedPc = sel.Comic ? inPageCount : curPc;
                    var mergedPa = sel.Comic ? inProgAt : curProgAt;
                    var mergedDr = sel.Read ? (inRead ? inDateRead : null) : curDr;
                    var mergedPos = sel.Video ? inPos : curPos;
                    var mergedDur = sel.Video && inDur > 0 ? inDur : curDur;
                    var mergedPosAt = sel.Video ? inPosAt : curPosAt;

                    await using var upd = conn.CreateCommand();
                    upd.Transaction = tx;
                    upd.CommandText = """
                        UPDATE chapters SET
                            "read" = $r, last_page = $lp, page_count = $pc, progress_updated_at = $pa,
                            date_read = $dr, position = $pos, duration = $dur, position_updated_at = $posa
                        WHERE source = $s AND work_id = $w AND chapter_id = $c;
                        """;
                    upd.Parameters.AddWithValue("$r", mergedRead ? 1 : 0);
                    upd.Parameters.AddWithValue("$lp", mergedLp);
                    upd.Parameters.AddWithValue("$pc", mergedPc);
                    upd.Parameters.AddWithValue("$pa", mergedPa is { } pa ? pa : DBNull.Value);
                    upd.Parameters.AddWithValue("$dr", mergedDr is { } dr ? dr : DBNull.Value);
                    upd.Parameters.AddWithValue("$pos", mergedPos);
                    upd.Parameters.AddWithValue("$dur", mergedDur);
                    upd.Parameters.AddWithValue("$posa", mergedPosAt is { } posa ? posa : DBNull.Value);
                    upd.Parameters.AddWithValue("$s", src);
                    upd.Parameters.AddWithValue("$w", wid);
                    upd.Parameters.AddWithValue("$c", cid);
                    await upd.ExecuteNonQueryAsync(ct).ConfigureAwait(false);
                }
                report.Chapters++;
            }
        }

        // 4. History (newer time wins)
        if (lib["history"] is JsonArray histArr)
        {
            foreach (var h in histArr.OfType<JsonObject>())
            {
                var src = h["source"]?.ToString() ?? string.Empty;
                var wid = h["workId"]?.ToString() ?? string.Empty;
                if (string.IsNullOrEmpty(src) || string.IsNullOrEmpty(wid)) continue;
                var time = h["time"] is JsonValue tv && tv.TryGetValue<long>(out var tl) ? tl : 0L;

                await EnsureWorkAsync(h["item"] as JsonObject, src, wid).ConfigureAwait(false);

                long? existingTime = null;
                await using (var sel = conn.CreateCommand())
                {
                    sel.Transaction = tx;
                    sel.CommandText = "SELECT time FROM history WHERE source = $s AND work_id = $w;";
                    sel.Parameters.AddWithValue("$s", src);
                    sel.Parameters.AddWithValue("$w", wid);
                    var val = await sel.ExecuteScalarAsync(ct).ConfigureAwait(false);
                    if (val is not null && val != DBNull.Value) existingTime = Convert.ToInt64(val);
                }

                if (existingTime is not null && existingTime.Value >= time) continue;

                await using var up = conn.CreateCommand();
                up.Transaction = tx;
                up.CommandText = """
                    INSERT INTO history (source, work_id, time, chapter_id, chapter_title, page, page_count, position)
                    VALUES ($s, $w, $t, $cid, $ct, $p, $pc, $pos)
                    ON CONFLICT(source, work_id) DO UPDATE SET
                        time = excluded.time, chapter_id = excluded.chapter_id, chapter_title = excluded.chapter_title,
                        page = excluded.page, page_count = excluded.page_count, position = excluded.position;
                    """;
                up.Parameters.AddWithValue("$s", src);
                up.Parameters.AddWithValue("$w", wid);
                up.Parameters.AddWithValue("$t", time);
                up.Parameters.AddWithValue("$cid", h["chapterId"]?.GetValue<string>() is { } cid ? cid : DBNull.Value);
                up.Parameters.AddWithValue("$ct", h["chapterTitle"]?.GetValue<string>() is { } ctStr ? ctStr : DBNull.Value);
                up.Parameters.AddWithValue("$p", h["page"] is JsonValue pv && pv.TryGetValue<int>(out var pi) ? pi : 0);
                up.Parameters.AddWithValue("$pc", h["pageCount"] is JsonValue pcv && pcv.TryGetValue<int>(out var pci) ? pci : 0);
                up.Parameters.AddWithValue("$pos", h["position"] is JsonValue posv && posv.TryGetValue<int>(out var posi) ? posi : DBNull.Value);
                await up.ExecuteNonQueryAsync(ct).ConfigureAwait(false);
                report.History++;
            }
        }
    }
}
