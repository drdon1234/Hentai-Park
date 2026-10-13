import '../core/models.dart';
import '../core/titles.dart';
import 'library.dart';
import '../core/localization.dart';
import '../engine/source_manager.dart';

class MigrationOptions {
  const MigrationOptions({
    this.categories = true,
    this.readState = true,
    this.removeOld = true,
  });
  final bool categories;
  final bool readState;

  /// true = move (Mihon "migrate"), false = keep the old favorite too ("copy").
  final bool removeOld;
}

/// Moves a favorite to another source's copy of the same work (Mihon's source migration).
class Migrator {
  /// 仅复制无歧义的一对一对应；相同目录长度不代表章节身份相同。
  static Map<String, String> matchChapters(
    List<ChapterState> old,
    List<Chapter> fresh,
  ) {
    final out = <String, String>{};
    if (old.isEmpty || fresh.isEmpty) return out;
    String titleKey(String title) => title.toLowerCase().replaceAll(
      RegExp(r'[\s\p{P}\p{S}]+', unicode: true),
      '',
    );
    final used = <String>{};
    void match(Object? Function(String) keyOf) {
      final oldKeys = <Object, List<ChapterState>>{};
      final newKeys = <Object, List<Chapter>>{};
      for (final chapter in old) {
        final key = keyOf(chapter.title);
        if (key != null && key != '') (oldKeys[key] ??= []).add(chapter);
      }
      for (final chapter in fresh) {
        final key = keyOf(chapter.title);
        if (key != null && key != '') (newKeys[key] ??= []).add(chapter);
      }
      for (final entry in oldKeys.entries) {
        final candidates = newKeys[entry.key];
        if (entry.value.length != 1 || candidates?.length != 1) continue;
        final source = entry.value.single.chapterId;
        final target = chapterKeyOf(candidates!.single.id);
        if (!out.containsKey(source) && used.add(target)) out[source] = target;
      }
    }

    match(titleKey);
    match(parseChapterNumber);
    return out;
  }

  /// 返回是否移除了原收藏；未匹配的进度仍保留在原收藏中。
  static Future<bool> migrate(
    Library lib, {
    required WorkItem from,
    required WorkDetail to,
    MigrationOptions options = const MigrationOptions(),
  }) async {
    final target = to.toItem();
    final categories = options.categories
        ? lib.categoriesOf(from.uid)
        : <int>{};
    final wasFavorite = lib.isFavorite(target.uid);
    if (!wasFavorite) {
      lib.addFavorite(target, categories: categories);
    } else if (options.categories) {
      lib.setCategories(target.uid, {
        ...lib.categoriesOf(target.uid),
        ...categories,
      });
    }
    final kind = MediaKind.fromJson(
      to.json['mediaKind'] ??
          SourceManager.instance.manifest(to.source)?.kind.name,
    );
    final chapters = kind == MediaKind.video
        ? to.videoEpisodes
        : to.chapters ?? [Chapter(chapterKeyOf(to.singleChapterId), tr('全本'))];
    var unmatchedProgress = false;
    await lib.flush();
    if (kind != MediaKind.game) {
      await lib.syncChapters(
        target,
        chapters,
        oneShot: kind == MediaKind.video
            ? !to.hasVideoEpisodes
            : to.chapters == null,
        complete: to.chaptersComplete,
      );
    }
    if (options.readState && kind != MediaKind.game) {
      final old =
          lib.chaptersCached(from.uid) ?? await lib.loadChapters(from.uid);
      final map = matchChapters(old, chapters);
      unmatchedProgress = old.any(
        (chapter) =>
            !map.containsKey(chapter.chapterId) &&
            (chapter.read ||
                chapter.lastPage > 0 ||
                chapter.position > 0 ||
                chapter.progressUpdatedAt != null ||
                chapter.positionUpdatedAt != null),
      );
      await lib.copyProgress(from, target, map);
    }
    await lib.flush();
    final removeOriginal =
        options.removeOld && !unmatchedProgress && from.uid != target.uid;
    if (removeOriginal) lib.removeFavorite(from.uid);
    await lib.flush();
    return removeOriginal;
  }
}
