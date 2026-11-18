using Park.Core.Models;

namespace Park.Library;

public readonly record struct ProgressSelection(bool Comic, bool Video, bool Read);

public static class ProgressMerge
{
    /// <summary>
    /// Exact port of lib/library/progress_merge.dart:
    /// Comic page and video position independently take newer timestamps;
    /// read state follows whichever action happened most recently (never logical-OR overwriting newer unread).
    /// </summary>
    public static ProgressSelection Select(
        long? incomingComic,
        long? incomingVideo,
        long? currentComic,
        long? currentVideo) => new(
        Comic: incomingComic is not null && incomingComic.Value > (currentComic ?? -1),
        Video: incomingVideo is not null && incomingVideo.Value > (currentVideo ?? -1),
        Read: Math.Max(incomingComic ?? -1, incomingVideo ?? -1) > Math.Max(currentComic ?? -1, currentVideo ?? -1));
}

public sealed record ChapterProgressSnapshot(
    string Source,
    string WorkId,
    string ChapterId,
    string Title,
    int Sort,
    bool Read,
    int LastPage,
    int PageCount,
    long? DateRead,
    long? ProgressUpdatedAt,
    int Position,
    int Duration,
    long? PositionUpdatedAt);

public sealed record HistoryEntry(
    WorkItem Item,
    long Time,
    string? ChapterId,
    string? ChapterTitle,
    int Page,
    int PageCount,
    int? Position);

public sealed record ContinueTarget(string ChapterId, string ChapterTitle, int Page, int PositionSeconds);

public static class PlaybackResolver
{
    public static ContinueTarget Resolve(
        WorkDetail detail,
        HistoryEntry? history,
        IReadOnlyDictionary<string, ChapterProgressSnapshot> chapters)
    {
        var list = detail.EffectiveChapters;
        if (history?.ChapterId is { Length: > 0 } histId)
        {
            var hit = list.FirstOrDefault(c => c.Id == histId);
            if (hit is not null)
            {
                chapters.TryGetValue(hit.Id, out var chSnap);
                return new ContinueTarget(
                    hit.Id,
                    hit.Title,
                    chSnap?.LastPage ?? history.Page,
                    chSnap?.Position ?? history.Position ?? 0);
            }
        }

        // First unread chapter, or last chapter if all read
        foreach (var ch in list)
        {
            if (!chapters.TryGetValue(ch.Id, out var snap) || !snap.Read)
            {
                return new ContinueTarget(ch.Id, ch.Title, snap?.LastPage ?? 0, snap?.Position ?? 0);
            }
        }

        var first = list[0];
        chapters.TryGetValue(first.Id, out var firstSnap);
        return new ContinueTarget(first.Id, first.Title, firstSnap?.LastPage ?? 0, firstSnap?.Position ?? 0);
    }
}
