import '../core/models.dart';
import '../core/titles.dart';
import 'library.dart';
import '../core/localization.dart';

class MigrationOptions {
  const MigrationOptions({this.categories = true, this.readState = true, this.removeOld = true});
  final bool categories;
  final bool readState;

  /// true = move (Mihon "migrate"), false = keep the old favorite too ("copy").
  final bool removeOld;
}

/// Moves a favorite to another source's copy of the same work (Mihon's source migration).
class Migrator {
  /// Maps old chapter ids to new ones: by parsed chapter number first, then by position when
  /// both lists have the same length.
  static Map<String, String> matchChapters(List<ChapterState> old, List<Chapter> fresh) {
    final out = <String, String>{};
    if (old.isEmpty || fresh.isEmpty) return out;
    if (old.length == 1 && fresh.length == 1) return {old.first.chapterId: chapterKeyOf(fresh.first.id)};
    final byNumber = <double, String>{};
    for (final c in fresh) {
      final n = parseChapterNumber(c.title);
      if (n != null) byNumber.putIfAbsent(n, () => chapterKeyOf(c.id));
    }
    final sortedOld = [...old]..sort((a, b) => a.sort.compareTo(b.sort));
    for (var i = 0; i < sortedOld.length; i++) {
      final o = sortedOld[i];
      final n = parseChapterNumber(o.title);
      final hit = n == null ? null : byNumber[n];
      if (hit != null) {
        out[o.chapterId] = hit;
      } else if (sortedOld.length == fresh.length) {
        out[o.chapterId] = chapterKeyOf(fresh[i].id);
      }
    }
    return out;
  }

  static Future<void> migrate(Library lib, {required WorkItem from, required WorkDetail to, MigrationOptions options = const MigrationOptions()}) async {
    final target = to.toItem();
    final categories = options.categories ? lib.categoriesOf(from.uid) : <int>{};
    final wasFavorite = lib.isFavorite(target.uid);
    if (!wasFavorite) {
      lib.addFavorite(target, categories: categories);
    } else if (options.categories) {
      lib.setCategories(target.uid, {...lib.categoriesOf(target.uid), ...categories});
    }
    final chapters = to.chapters ?? [Chapter(chapterKeyOf(to.singleChapterId), tr('全本'))];
    await lib.syncChapters(target, chapters, oneShot: to.chapters == null);
    if (options.readState) {
      final old = lib.chaptersCached(from.uid) ?? await lib.loadChapters(from.uid);
      final map = matchChapters(old, chapters);
      final read = [for (final o in old) if (o.read && map[o.chapterId] != null) map[o.chapterId]!];
      lib.markRead(target.uid, read, true);
    }
    if (options.removeOld) lib.removeFavorite(from.uid);
    await lib.flush();
  }
}
