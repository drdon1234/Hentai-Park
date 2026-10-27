import '../core/models.dart';
import '../engine/source_manager.dart';
import 'downloads.dart';
import 'library.dart';

/// Where "continue" on a stored work leads.
sealed class PlaybackTarget {
  const PlaybackTarget();
}

/// The work's own page: games, short videos, external sources, or nothing stored to resume.
class OpenWorkPage extends PlaybackTarget {
  const OpenWorkPage();
}

/// The player. [work] is null when nothing is stored locally and the detail must be fetched.
class PlayVideo extends PlaybackTarget {
  const PlayVideo(this.work, this.episodeId, {this.downloadedOnly = false});
  final WorkDetail? work;
  final String? episodeId;
  final bool downloadedOnly;
}

/// The comic or novel reader at [chapter] and [startPage].
class ReadChapter extends PlaybackTarget {
  const ReadChapter(
    this.work, {
    this.chapter,
    this.startPage = 0,
    this.downloadedOnly = false,
  });
  final WorkDetail work;
  final Chapter? chapter;
  final int startPage;
  final bool downloadedOnly;
}

/// Builds what to open from the stored chapter list, history and downloads, without a request.
abstract final class PlaybackResolver {
  static Future<PlaybackTarget> resolve(
    WorkItem item,
    String? chapterId, {
    int? page,
    bool downloadedOnly = false,
  }) async {
    final lib = Library.instance;
    final chapters =
        lib.chaptersCached(item.uid) ?? await lib.loadChapters(item.uid);
    final task = DownloadManager.instance.task(item.uid);
    final allowIncomplete =
        !downloadedOnly &&
        task != null &&
        !task.isVideo &&
        !task.isNovel &&
        item.source != localSource;
    // 下载记录本身就是本地目录，不能依赖插件、首页或另外一份章节缓存。
    if (task != null &&
        (downloadedOnly ||
            allowIncomplete ||
            chapterId == null ||
            task.completed.contains(chapterKeyOf(chapterId)))) {
      final available = task.chapters
          .where(
            (chapter) =>
                (allowIncomplete || task.completed.contains(chapter.id)) &&
                !(task.deletingChapters?.contains(chapter.id) ?? false) &&
                task.deletingChapters?.isEmpty != true,
          )
          .toList();
      if (available.isNotEmpty) {
        final requested = chapterId ?? lib.historyOf(item.uid)?.chapterId;
        final selected =
            available
                .where((c) => c.id == chapterKeyOf(requested))
                .firstOrNull ??
            available.first;
        final work = WorkDetail({
          ...task.item.json,
          'mediaKind': task.media.name,
          'chaptersComplete': false,
          'chapters': [
            for (final c in available) {'id': c.id, 'title': c.title},
          ],
        }, item.source);
        if (task.isVideo) {
          return PlayVideo(work, selected.id, downloadedOnly: true);
        }
        final state = lib.chapterState(item.uid, selected.id);
        final history = lib.historyOf(item.uid);
        final start = selected.id == chapterKeyOf(requested) && page != null
            ? page
            : state != null
            ? (state.read ? 0 : state.lastPage)
            : history?.chapterId == selected.id
            ? history!.page
            : 0;
        return ReadChapter(
          work,
          chapter: selected,
          startPage: start,
          downloadedOnly: !allowIncomplete,
        );
      }
    }
    if (downloadedOnly) return const OpenWorkPage();
    final sources = SourceManager.instance;
    final manifest = sources.manifest(item.source);
    final kind = sources.kindOf(item);
    if (manifest?.category == SourceCategory.shortvideo ||
        kind == MediaKind.game ||
        manifest?.opensExternally == true) {
      return const OpenWorkPage();
    }
    if (kind == MediaKind.video ||
        task?.isVideo == true ||
        lib.historyOf(item.uid)?.position != null) {
      final episodes = [
        for (final chapter in chapters)
          Chapter(chapter.chapterId, chapter.title),
      ];
      final known = episodes.map((episode) => episode.id).toSet();
      for (final episode in task?.chapters ?? const <Chapter>[]) {
        if (known.add(episode.id)) episodes.add(episode);
      }
      if (episodes.isNotEmpty) {
        return PlayVideo(
          WorkDetail({
            ...item.json,
            'chaptersComplete': false,
            'chapters': [
              for (final episode in episodes)
                {'id': episode.id, 'title': episode.title},
            ],
          }, item.source),
          chapterId,
        );
      }
      return PlayVideo(
        DownloadManager.instance.offlineDetail(item.source, item.id),
        chapterId,
      );
    }
    if (chapters.isEmpty) return const OpenWorkPage();
    final key = chapterKeyOf(chapterId);
    final state =
        chapters.where((c) => c.chapterId == key).firstOrNull ?? chapters.first;
    final start = page ?? (state.read ? 0 : state.lastPage);
    if (chapters.length == 1) {
      final only = chapters.first.chapterId;
      return ReadChapter(
        WorkDetail({
          ...item.json,
          'id': item.id,
          'singleChapterId': only == '_' ? null : only,
        }, item.source),
        startPage: start,
      );
    }
    return ReadChapter(
      WorkDetail({
        ...item.json,
        'id': item.id,
        'chapters': [
          for (final c in chapters) {'id': c.chapterId, 'title': c.title},
        ],
      }, item.source),
      chapter: Chapter(state.chapterId, state.title),
      startPage: start,
    );
  }
}
