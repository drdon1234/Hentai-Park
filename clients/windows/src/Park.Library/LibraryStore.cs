using System.Text.Json.Nodes;
using Microsoft.Data.Sqlite;
using Park.Core.Configuration;
using Park.Core.Models;

namespace Park.Library;

public enum LibraryCollection
{
    Favorites,
    Categories,
    History,
    Chapters,
}

public sealed record CategoryEntry(long Id, string Name, int Sort);

public sealed record FavoriteWorkEntry(
    WorkItem Item,
    long? FavoritedAt,
    IReadOnlyList<string> Categories);

public sealed record MigrationResult(bool Completed, bool KeptOriginalFavorite, int MatchedChapters, int UnmatchedWithProgress);

/// <summary>
/// Serialized transactional library store aligned with DEVELOPMENT.md:
/// - Ordered write queue: failed items and subsequent operations stay queued for retry on next write or FlushAsync
/// - Scoped change notifications per work UID and per LibraryCollection
/// - Respects incognito mode for history and reading progress
/// </summary>
public sealed class LibraryStore
{
    private readonly ParkDatabase _db;
    private readonly SemaphoreSlim _queueGate = new(1, 1);
    private readonly Queue<Func<CancellationToken, Task>> _pendingWrites = new();

    public event Action<string>? WorkChanged;
    public event Action<LibraryCollection>? CollectionChanged;

    public ParkDatabase Database => _db;

    public LibraryStore(ParkDatabase db)
    {
        _db = db;
    }

    public async Task FlushAsync(CancellationToken ct = default)
    {
        await _queueGate.WaitAsync(ct).ConfigureAwait(false);
        try
        {
            while (_pendingWrites.Count > 0)
            {
                var next = _pendingWrites.Peek();
                await next(ct).ConfigureAwait(false);
                _pendingWrites.Dequeue();
            }
        }
        finally
        {
            _queueGate.Release();
        }
    }

    private async Task EnqueueWriteAsync(Func<CancellationToken, Task> op, CancellationToken ct = default)
    {
        await _queueGate.WaitAsync(ct).ConfigureAwait(false);
        _pendingWrites.Enqueue(op);
        try
        {
            while (_pendingWrites.Count > 0)
            {
                var next = _pendingWrites.Peek();
                await next(ct).ConfigureAwait(false);
                _pendingWrites.Dequeue();
            }
        }
        finally
        {
            _queueGate.Release();
        }
    }

    public async Task SetFavoriteAsync(WorkItem item, bool favorite, IReadOnlyList<string>? categoryNames = null, CancellationToken ct = default)
    {
        var now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        await EnqueueWriteAsync(async token =>
        {
            await _db.WriteTransactionAsync(async (conn, tx) =>
            {
                await UpsertWorkSnapshotAsync(conn, tx, item, token).ConfigureAwait(false);
                await using var cmd = conn.CreateCommand();
                cmd.Transaction = tx;
                cmd.CommandText = """
                    UPDATE works
                    SET favorite = $fav,
                        favorited_at = CASE WHEN $fav = 1 THEN COALESCE(favorited_at, $now) ELSE NULL END
                    WHERE source = $src AND id = $id;
                    """;
                cmd.Parameters.AddWithValue("$fav", favorite ? 1 : 0);
                cmd.Parameters.AddWithValue("$now", now);
                cmd.Parameters.AddWithValue("$src", item.Source);
                cmd.Parameters.AddWithValue("$id", item.Id);
                await cmd.ExecuteNonQueryAsync(token).ConfigureAwait(false);

                if (categoryNames is not null)
                {
                    await SetWorkCategoriesInternalAsync(conn, tx, item.Source, item.Id, categoryNames, token).ConfigureAwait(false);
                }
            }, token).ConfigureAwait(false);
        }, ct).ConfigureAwait(false);

        WorkChanged?.Invoke(item.Uid);
        CollectionChanged?.Invoke(LibraryCollection.Favorites);
    }

    public async Task<bool> IsFavoriteAsync(string source, string workId, CancellationToken ct = default)
    {
        await FlushAsync(ct).ConfigureAwait(false);
        return await _db.ReadAsync(async conn =>
        {
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT favorite FROM works WHERE source = $src AND id = $id;";
            cmd.Parameters.AddWithValue("$src", source);
            cmd.Parameters.AddWithValue("$id", workId);
            var val = await cmd.ExecuteScalarAsync(ct).ConfigureAwait(false);
            return val is not null && Convert.ToInt32(val) == 1;
        }, ct).ConfigureAwait(false);
    }

    public async Task<IReadOnlyList<FavoriteWorkEntry>> GetFavoritesAsync(
        string? categoryFilter = null,
        string? sourceFilter = null,
        string? searchQuery = null,
        CancellationToken ct = default)
    {
        await FlushAsync(ct).ConfigureAwait(false);
        return await _db.ReadAsync(async conn =>
        {
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = """
                SELECT w.source, w.id, w.json, w.favorited_at,
                       (SELECT json_group_array(c.name)
                        FROM work_categories m JOIN categories c ON c.id = m.category_id
                        WHERE m.source = w.source AND m.work_id = w.id) AS cats
                FROM works w
                WHERE w.favorite = 1
                ORDER BY COALESCE(w.favorited_at, 0) DESC;
                """;
            var results = new List<FavoriteWorkEntry>();
            await using var reader = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
            while (await reader.ReadAsync(ct).ConfigureAwait(false))
            {
                var src = reader.GetString(0);
                if (!string.IsNullOrEmpty(sourceFilter) && !string.Equals(src, sourceFilter, StringComparison.Ordinal))
                    continue;

                var jsonStr = reader.GetString(2);
                var obj = JsonNode.Parse(jsonStr) as JsonObject ?? [];
                var work = WorkItem.FromJson(src, obj);
                long? favAt = reader.IsDBNull(3) ? null : reader.GetInt64(3);

                var cats = new List<string>();
                if (!reader.IsDBNull(4) && JsonNode.Parse(reader.GetString(4)) is JsonArray cArr)
                {
                    foreach (var n in cArr)
                        if (n is JsonValue v && v.TryGetValue<string>(out var cs) && !string.IsNullOrEmpty(cs))
                            cats.Add(cs);
                }

                if (!string.IsNullOrEmpty(categoryFilter) && !cats.Contains(categoryFilter, StringComparer.Ordinal))
                    continue;

                if (!string.IsNullOrWhiteSpace(searchQuery) &&
                    !work.Title.Contains(searchQuery, StringComparison.OrdinalIgnoreCase) &&
                    !work.Subtitle.Contains(searchQuery, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                results.Add(new FavoriteWorkEntry(work, favAt, cats));
            }
            return (IReadOnlyList<FavoriteWorkEntry>)results;
        }, ct).ConfigureAwait(false);
    }

    public async Task<IReadOnlyList<CategoryEntry>> GetCategoriesAsync(CancellationToken ct = default)
    {
        await FlushAsync(ct).ConfigureAwait(false);
        return await _db.ReadAsync(async conn =>
        {
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT id, name, sort FROM categories ORDER BY sort ASC, id ASC;";
            var list = new List<CategoryEntry>();
            await using var r = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
            while (await r.ReadAsync(ct).ConfigureAwait(false))
                list.Add(new CategoryEntry(r.GetInt64(0), r.GetString(1), r.GetInt32(2)));
            return (IReadOnlyList<CategoryEntry>)list;
        }, ct).ConfigureAwait(false);
    }

    public async Task CreateCategoryAsync(string name, CancellationToken ct = default)
    {
        var trimmed = name.Trim();
        if (string.IsNullOrEmpty(trimmed)) return;
        await EnqueueWriteAsync(async token =>
        {
            await _db.WriteTransactionAsync(async (conn, tx) =>
            {
                await using var cmd = conn.CreateCommand();
                cmd.Transaction = tx;
                cmd.CommandText = """
                    INSERT OR IGNORE INTO categories (name, sort)
                    VALUES ($name, COALESCE((SELECT MAX(sort) + 1 FROM categories), 0));
                    """;
                cmd.Parameters.AddWithValue("$name", trimmed);
                await cmd.ExecuteNonQueryAsync(token).ConfigureAwait(false);
            }, token).ConfigureAwait(false);
        }, ct).ConfigureAwait(false);
        CollectionChanged?.Invoke(LibraryCollection.Categories);
    }

    public async Task RecordReadingProgressAsync(
        WorkItem item,
        string chapterId,
        string chapterTitle,
        int lastPage,
        int pageCount,
        bool completed,
        CancellationToken ct = default)
    {
        if (AppSettings.Instance.Incognito) return;
        var now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();

        await EnqueueWriteAsync(async token =>
        {
            await _db.WriteTransactionAsync(async (conn, tx) =>
            {
                await UpsertWorkSnapshotAsync(conn, tx, item, token).ConfigureAwait(false);
                await using var chCmd = conn.CreateCommand();
                chCmd.Transaction = tx;
                chCmd.CommandText = """
                    INSERT INTO chapters (source, work_id, chapter_id, title, "read", last_page, page_count, date_read, progress_updated_at)
                    VALUES ($src, $wid, $cid, $title, $read, $page, $count, $dread, $now)
                    ON CONFLICT(source, work_id, chapter_id) DO UPDATE SET
                        title = CASE WHEN excluded.title <> '' THEN excluded.title ELSE chapters.title END,
                        "read" = excluded."read",
                        last_page = excluded.last_page,
                        page_count = excluded.page_count,
                        date_read = excluded.date_read,
                        progress_updated_at = excluded.progress_updated_at;
                    """;
                chCmd.Parameters.AddWithValue("$src", item.Source);
                chCmd.Parameters.AddWithValue("$wid", item.Id);
                chCmd.Parameters.AddWithValue("$cid", chapterId);
                chCmd.Parameters.AddWithValue("$title", chapterTitle);
                chCmd.Parameters.AddWithValue("$read", completed ? 1 : 0);
                chCmd.Parameters.AddWithValue("$page", Math.Max(0, lastPage));
                chCmd.Parameters.AddWithValue("$count", Math.Max(0, pageCount));
                chCmd.Parameters.AddWithValue("$dread", completed ? (object)now : DBNull.Value);
                chCmd.Parameters.AddWithValue("$now", now);
                await chCmd.ExecuteNonQueryAsync(token).ConfigureAwait(false);

                await UpsertHistoryInternalAsync(conn, tx, item.Source, item.Id, now, chapterId, chapterTitle, lastPage, pageCount, null, token).ConfigureAwait(false);
            }, token).ConfigureAwait(false);
        }, ct).ConfigureAwait(false);

        WorkChanged?.Invoke(item.Uid);
        CollectionChanged?.Invoke(LibraryCollection.Chapters);
        CollectionChanged?.Invoke(LibraryCollection.History);
    }

    public async Task RecordPlaybackPositionAsync(
        WorkItem item,
        string chapterId,
        string chapterTitle,
        int positionSeconds,
        int durationSeconds,
        bool completed,
        CancellationToken ct = default)
    {
        if (AppSettings.Instance.Incognito) return;
        var now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();

        await EnqueueWriteAsync(async token =>
        {
            await _db.WriteTransactionAsync(async (conn, tx) =>
            {
                await UpsertWorkSnapshotAsync(conn, tx, item, token).ConfigureAwait(false);
                await using var chCmd = conn.CreateCommand();
                chCmd.Transaction = tx;
                chCmd.CommandText = """
                    INSERT INTO chapters (source, work_id, chapter_id, title, "read", position, duration, date_read, position_updated_at)
                    VALUES ($src, $wid, $cid, $title, $read, $pos, $dur, $dread, $now)
                    ON CONFLICT(source, work_id, chapter_id) DO UPDATE SET
                        title = CASE WHEN excluded.title <> '' THEN excluded.title ELSE chapters.title END,
                        "read" = excluded."read",
                        position = excluded.position,
                        duration = CASE WHEN excluded.duration > 0 THEN excluded.duration ELSE chapters.duration END,
                        date_read = excluded.date_read,
                        position_updated_at = excluded.position_updated_at;
                    """;
                chCmd.Parameters.AddWithValue("$src", item.Source);
                chCmd.Parameters.AddWithValue("$wid", item.Id);
                chCmd.Parameters.AddWithValue("$cid", chapterId);
                chCmd.Parameters.AddWithValue("$title", chapterTitle);
                chCmd.Parameters.AddWithValue("$read", completed ? 1 : 0);
                chCmd.Parameters.AddWithValue("$pos", Math.Max(0, positionSeconds));
                chCmd.Parameters.AddWithValue("$dur", Math.Max(0, durationSeconds));
                chCmd.Parameters.AddWithValue("$dread", completed ? (object)now : DBNull.Value);
                chCmd.Parameters.AddWithValue("$now", now);
                await chCmd.ExecuteNonQueryAsync(token).ConfigureAwait(false);

                await UpsertHistoryInternalAsync(conn, tx, item.Source, item.Id, now, chapterId, chapterTitle, 0, 0, Math.Max(0, positionSeconds), token).ConfigureAwait(false);
            }, token).ConfigureAwait(false);
        }, ct).ConfigureAwait(false);

        WorkChanged?.Invoke(item.Uid);
        CollectionChanged?.Invoke(LibraryCollection.Chapters);
        CollectionChanged?.Invoke(LibraryCollection.History);
    }

    public async Task<IReadOnlyDictionary<string, ChapterProgressSnapshot>> GetChapterProgressAsync(string source, string workId, CancellationToken ct = default)
    {
        await FlushAsync(ct).ConfigureAwait(false);
        return await _db.ReadAsync(async conn =>
        {
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = """
                SELECT chapter_id, title, sort, "read", last_page, page_count, date_read,
                       progress_updated_at, position, duration, position_updated_at
                FROM chapters
                WHERE source = $src AND work_id = $wid;
                """;
            cmd.Parameters.AddWithValue("$src", source);
            cmd.Parameters.AddWithValue("$wid", workId);
            var map = new Dictionary<string, ChapterProgressSnapshot>(StringComparer.Ordinal);
            await using var r = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
            while (await r.ReadAsync(ct).ConfigureAwait(false))
            {
                var cid = r.GetString(0);
                map[cid] = new ChapterProgressSnapshot(
                    source, workId, cid,
                    r.GetString(1),
                    r.GetInt32(2),
                    r.GetInt32(3) == 1,
                    r.GetInt32(4),
                    r.GetInt32(5),
                    r.IsDBNull(6) ? null : r.GetInt64(6),
                    r.IsDBNull(7) ? null : r.GetInt64(7),
                    r.GetInt32(8),
                    r.GetInt32(9),
                    r.IsDBNull(10) ? null : r.GetInt64(10));
            }
            return (IReadOnlyDictionary<string, ChapterProgressSnapshot>)map;
        }, ct).ConfigureAwait(false);
    }

    public async Task<IReadOnlyList<HistoryEntry>> GetHistoryAsync(int limit = 200, CancellationToken ct = default)
    {
        await FlushAsync(ct).ConfigureAwait(false);
        return await _db.ReadAsync(async conn =>
        {
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = """
                SELECT h.source, h.work_id, h.time, h.chapter_id, h.chapter_title, h.page, h.page_count, h.position, w.json
                FROM history h
                JOIN works w ON w.source = h.source AND w.id = h.work_id
                ORDER BY h.time DESC
                LIMIT $lim;
                """;
            cmd.Parameters.AddWithValue("$lim", limit);
            var list = new List<HistoryEntry>();
            await using var r = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
            while (await r.ReadAsync(ct).ConfigureAwait(false))
            {
                var src = r.GetString(0);
                var obj = JsonNode.Parse(r.GetString(8)) as JsonObject ?? [];
                list.Add(new HistoryEntry(
                    WorkItem.FromJson(src, obj),
                    r.GetInt64(2),
                    r.IsDBNull(3) ? null : r.GetString(3),
                    r.IsDBNull(4) ? null : r.GetString(4),
                    r.GetInt32(5),
                    r.GetInt32(6),
                    r.IsDBNull(7) ? null : r.GetInt32(7)));
            }
            return (IReadOnlyList<HistoryEntry>)list;
        }, ct).ConfigureAwait(false);
    }

    /// <summary>
    /// Unambiguous 1:1 chapter migration per DEVELOPMENT.md:
    /// Retains original favorite whenever any progressed chapter cannot be uniquely matched on target.
    /// </summary>
    public async Task<MigrationResult> MigrateWorkAsync(
        WorkDetail fromDetail,
        WorkDetail toDetail,
        CancellationToken ct = default)
    {
        await FlushAsync(ct).ConfigureAwait(false);
        var fromProgress = await GetChapterProgressAsync(fromDetail.Item.Source, fromDetail.Item.Id, ct).ConfigureAwait(false);
        var toProgress = await GetChapterProgressAsync(toDetail.Item.Source, toDetail.Item.Id, ct).ConfigureAwait(false);

        var toTitleGroups = toDetail.EffectiveChapters
            .GroupBy(c => c.Title.Trim(), StringComparer.OrdinalIgnoreCase)
            .Where(g => !string.IsNullOrEmpty(g.Key) && g.Count() == 1)
            .ToDictionary(g => g.Key, g => g.First(), StringComparer.OrdinalIgnoreCase);

        var fromTitleCounts = fromDetail.EffectiveChapters
            .GroupBy(c => c.Title.Trim(), StringComparer.OrdinalIgnoreCase)
            .ToDictionary(g => g.Key, g => g.Count(), StringComparer.OrdinalIgnoreCase);

        var matched = new List<(ChapterProgressSnapshot Src, ChapterInfo Dst)>();
        var unmatchedWithProgress = 0;

        foreach (var srcCh in fromDetail.EffectiveChapters)
        {
            if (!fromProgress.TryGetValue(srcCh.Id, out var snap)) continue;
            var hasProgress = snap.Read || snap.ProgressUpdatedAt is not null || snap.PositionUpdatedAt is not null;
            if (!hasProgress) continue;

            var titleKey = srcCh.Title.Trim();
            if (!string.IsNullOrEmpty(titleKey) &&
                fromTitleCounts.TryGetValue(titleKey, out var count) && count == 1 &&
                toTitleGroups.TryGetValue(titleKey, out var dstCh))
            {
                matched.Add((snap, dstCh));
            }
            else if (fromDetail.EffectiveChapters.Count == 1 && toDetail.EffectiveChapters.Count == 1)
            {
                matched.Add((snap, toDetail.EffectiveChapters[0]));
            }
            else
            {
                unmatchedWithProgress++;
            }
        }

        var keepOriginal = unmatchedWithProgress > 0;
        await EnqueueWriteAsync(async token =>
        {
            await _db.WriteTransactionAsync(async (conn, tx) =>
            {
                await UpsertWorkSnapshotAsync(conn, tx, toDetail.Item, token).ConfigureAwait(false);

                // Copy favorite & categories
                await using (var copyFav = conn.CreateCommand())
                {
                    copyFav.Transaction = tx;
                    copyFav.CommandText = """
                        UPDATE works SET favorite = 1, favorited_at = COALESCE(favorited_at, $now)
                        WHERE source = $toSrc AND id = $toId;
                        """;
                    copyFav.Parameters.AddWithValue("$now", DateTimeOffset.UtcNow.ToUnixTimeMilliseconds());
                    copyFav.Parameters.AddWithValue("$toSrc", toDetail.Item.Source);
                    copyFav.Parameters.AddWithValue("$toId", toDetail.Item.Id);
                    await copyFav.ExecuteNonQueryAsync(token).ConfigureAwait(false);
                }

                await using (var copyCats = conn.CreateCommand())
                {
                    copyCats.Transaction = tx;
                    copyCats.CommandText = """
                        INSERT OR IGNORE INTO work_categories (source, work_id, category_id)
                        SELECT $toSrc, $toId, category_id FROM work_categories
                        WHERE source = $fromSrc AND work_id = $fromId;
                        """;
                    copyCats.Parameters.AddWithValue("$toSrc", toDetail.Item.Source);
                    copyCats.Parameters.AddWithValue("$toId", toDetail.Item.Id);
                    copyCats.Parameters.AddWithValue("$fromSrc", fromDetail.Item.Source);
                    copyCats.Parameters.AddWithValue("$fromId", fromDetail.Item.Id);
                    await copyCats.ExecuteNonQueryAsync(token).ConfigureAwait(false);
                }

                foreach (var (srcSnap, dstInfo) in matched)
                {
                    toProgress.TryGetValue(dstInfo.Id, out var curDst);
                    var sel = ProgressMerge.Select(
                        srcSnap.ProgressUpdatedAt,
                        srcSnap.PositionUpdatedAt,
                        curDst?.ProgressUpdatedAt,
                        curDst?.PositionUpdatedAt);

                    var read = curDst is null ? srcSnap.Read : (sel.Read ? srcSnap.Read : curDst.Read);
                    var lastPage = curDst is null || sel.Comic ? srcSnap.LastPage : curDst.LastPage;
                    var pageCount = curDst is null || sel.Comic ? srcSnap.PageCount : curDst.PageCount;
                    var progAt = curDst is null || sel.Comic ? srcSnap.ProgressUpdatedAt : curDst.ProgressUpdatedAt;
                    var pos = curDst is null || sel.Video ? srcSnap.Position : curDst.Position;
                    var dur = curDst is null || (sel.Video && srcSnap.Duration > 0) ? srcSnap.Duration : curDst.Duration;
                    var posAt = curDst is null || sel.Video ? srcSnap.PositionUpdatedAt : curDst.PositionUpdatedAt;

                    await using var chUpsert = conn.CreateCommand();
                    chUpsert.Transaction = tx;
                    chUpsert.CommandText = """
                        INSERT INTO chapters (source, work_id, chapter_id, title, "read", last_page, page_count, progress_updated_at, position, duration, position_updated_at)
                        VALUES ($src, $wid, $cid, $title, $read, $lp, $pc, $pat, $pos, $dur, $posat)
                        ON CONFLICT(source, work_id, chapter_id) DO UPDATE SET
                            "read" = excluded."read",
                            last_page = excluded.last_page,
                            page_count = excluded.page_count,
                            progress_updated_at = excluded.progress_updated_at,
                            position = excluded.position,
                            duration = excluded.duration,
                            position_updated_at = excluded.position_updated_at;
                        """;
                    chUpsert.Parameters.AddWithValue("$src", toDetail.Item.Source);
                    chUpsert.Parameters.AddWithValue("$wid", toDetail.Item.Id);
                    chUpsert.Parameters.AddWithValue("$cid", dstInfo.Id);
                    chUpsert.Parameters.AddWithValue("$title", dstInfo.Title);
                    chUpsert.Parameters.AddWithValue("$read", read ? 1 : 0);
                    chUpsert.Parameters.AddWithValue("$lp", lastPage);
                    chUpsert.Parameters.AddWithValue("$pc", pageCount);
                    chUpsert.Parameters.AddWithValue("$pat", progAt is { } pa ? pa : DBNull.Value);
                    chUpsert.Parameters.AddWithValue("$pos", pos);
                    chUpsert.Parameters.AddWithValue("$dur", dur);
                    chUpsert.Parameters.AddWithValue("$posat", posAt is { } psa ? psa : DBNull.Value);
                    await chUpsert.ExecuteNonQueryAsync(token).ConfigureAwait(false);
                }

                if (!keepOriginal)
                {
                    await using var unfavorite = conn.CreateCommand();
                    unfavorite.Transaction = tx;
                    unfavorite.CommandText = "UPDATE works SET favorite = 0, favorited_at = NULL WHERE source = $s AND id = $i;";
                    unfavorite.Parameters.AddWithValue("$s", fromDetail.Item.Source);
                    unfavorite.Parameters.AddWithValue("$i", fromDetail.Item.Id);
                    await unfavorite.ExecuteNonQueryAsync(token).ConfigureAwait(false);
                }
            }, token).ConfigureAwait(false);
        }, ct).ConfigureAwait(false);

        CollectionChanged?.Invoke(LibraryCollection.Favorites);
        CollectionChanged?.Invoke(LibraryCollection.Chapters);
        return new MigrationResult(!keepOriginal, keepOriginal, matched.Count, unmatchedWithProgress);
    }

    internal static async Task UpsertWorkSnapshotAsync(SqliteConnection conn, SqliteTransaction tx, WorkItem item, CancellationToken ct)
    {
        await using var cmd = conn.CreateCommand();
        cmd.Transaction = tx;
        cmd.CommandText = """
            INSERT INTO works (source, id, title, cover, json)
            VALUES ($src, $id, $title, $cover, $json)
            ON CONFLICT(source, id) DO UPDATE SET
                title = CASE WHEN excluded.title <> '' THEN excluded.title ELSE works.title END,
                cover = CASE WHEN excluded.cover <> '' THEN excluded.cover ELSE works.cover END,
                json = excluded.json;
            """;
        cmd.Parameters.AddWithValue("$src", item.Source);
        cmd.Parameters.AddWithValue("$id", item.Id);
        cmd.Parameters.AddWithValue("$title", item.Title);
        cmd.Parameters.AddWithValue("$cover", item.Cover);
        cmd.Parameters.AddWithValue("$json", item.RawJson.ToJsonString());
        await cmd.ExecuteNonQueryAsync(ct).ConfigureAwait(false);
    }

    private static async Task SetWorkCategoriesInternalAsync(
        SqliteConnection conn,
        SqliteTransaction tx,
        string source,
        string workId,
        IReadOnlyList<string> categoryNames,
        CancellationToken ct)
    {
        await using (var del = conn.CreateCommand())
        {
            del.Transaction = tx;
            del.CommandText = "DELETE FROM work_categories WHERE source = $s AND work_id = $w;";
            del.Parameters.AddWithValue("$s", source);
            del.Parameters.AddWithValue("$w", workId);
            await del.ExecuteNonQueryAsync(ct).ConfigureAwait(false);
        }

        foreach (var name in categoryNames.Where(n => !string.IsNullOrWhiteSpace(n)))
        {
            await using var ensure = conn.CreateCommand();
            ensure.Transaction = tx;
            ensure.CommandText = """
                INSERT OR IGNORE INTO categories (name, sort)
                VALUES ($name, COALESCE((SELECT MAX(sort) + 1 FROM categories), 0));
                """;
            ensure.Parameters.AddWithValue("$name", name.Trim());
            await ensure.ExecuteNonQueryAsync(ct).ConfigureAwait(false);

            await using var map = conn.CreateCommand();
            map.Transaction = tx;
            map.CommandText = """
                INSERT OR IGNORE INTO work_categories (source, work_id, category_id)
                SELECT $s, $w, id FROM categories WHERE name = $name;
                """;
            map.Parameters.AddWithValue("$s", source);
            map.Parameters.AddWithValue("$w", workId);
            map.Parameters.AddWithValue("$name", name.Trim());
            await map.ExecuteNonQueryAsync(ct).ConfigureAwait(false);
        }
    }

    private static async Task UpsertHistoryInternalAsync(
        SqliteConnection conn,
        SqliteTransaction tx,
        string source,
        string workId,
        long timeMs,
        string? chapterId,
        string? chapterTitle,
        int page,
        int pageCount,
        int? position,
        CancellationToken ct)
    {
        await using var cmd = conn.CreateCommand();
        cmd.Transaction = tx;
        cmd.CommandText = """
            INSERT INTO history (source, work_id, time, chapter_id, chapter_title, page, page_count, position)
            VALUES ($src, $wid, $time, $cid, $ctitle, $page, $pcount, $pos)
            ON CONFLICT(source, work_id) DO UPDATE SET
                time = excluded.time,
                chapter_id = excluded.chapter_id,
                chapter_title = excluded.chapter_title,
                page = excluded.page,
                page_count = excluded.page_count,
                position = excluded.position;
            """;
        cmd.Parameters.AddWithValue("$src", source);
        cmd.Parameters.AddWithValue("$wid", workId);
        cmd.Parameters.AddWithValue("$time", timeMs);
        cmd.Parameters.AddWithValue("$cid", chapterId is not null ? chapterId : DBNull.Value);
        cmd.Parameters.AddWithValue("$ctitle", chapterTitle is not null ? chapterTitle : DBNull.Value);
        cmd.Parameters.AddWithValue("$page", Math.Max(0, page));
        cmd.Parameters.AddWithValue("$pcount", Math.Max(0, pageCount));
        cmd.Parameters.AddWithValue("$pos", position is { } p ? p : DBNull.Value);
        await cmd.ExecuteNonQueryAsync(ct).ConfigureAwait(false);
    }
}
