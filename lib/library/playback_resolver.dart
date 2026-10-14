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
  const PlayVideo(this.work, this.episodeId);
  final WorkDetail? work;
  final String? episodeId;
}

/// The comic or novel reader at [chapter] and [startPage].
class ReadChapter extends PlaybackTarget {
  const ReadChapter(this.work, {this.chapter, this.startPage = 0});
  final WorkDetail work;
  final Chapter? chapter;
  final int startPage;
}

/// Builds what to open from the stored chapter list, history and downloads, without a request.
abstract final class PlaybackResolver {
  static Future<PlaybackTarget> resolve(
    WorkItem item,
    String? chapterId, {
    int? page,
  }) async {
    final sources = SourceManager.instance;
    final manifest = sources.manifest(item.source);
    final kind = sources.kindOf(item);
    if (manifest?.category == SourceCategory.shortvideo ||
        kind == MediaKind.game ||
        manifest?.opensExternally == true) {
      return const OpenWorkPage();
    }
    final lib = Library.instance;
    final chapters =
        lib.chaptersCached(item.uid) ?? await lib.loadChapters(item.uid);
    final task = DownloadManager.instance.task(item.uid);
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
