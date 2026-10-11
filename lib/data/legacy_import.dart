import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/storage.dart';
import 'database.dart';

/// One-time import of the JSON files written before the SQLite database existed
/// (favorites.json, history.json, downloads.json). Runs in one transaction; on success the
/// files are renamed to `*.migrated` so a rollback to an older build still finds them.
class LegacyImport {
  static const legacyDefaultFolder = '默认收藏';

  /// Returns true when something was imported.
  static Future<bool> run(AppDatabase db, {required Directory dataDir, required Directory downloadsDir}) async {
    final files = {for (final n in ['favorites.json', 'history.json', 'downloads.json']) n: File(p.join(dataDir.path, n))};
    final present = {
      for (final e in files.entries)
        if (await e.value.exists()) e.key: e.value,
    };
    if (present.isEmpty || !await db.isEmpty) return false;
    Object? read(String name) {
      final f = present[name];
      if (f == null) return null;
      try {
        return jsonDecode(f.readAsStringSync());
      } catch (e) {
        debugPrint('legacy $name unreadable: $e');
        return null;
      }
    }

    final favorites = read('favorites.json');
    final history = read('history.json');
    final downloads = read('downloads.json');
    await db.transaction(() async {
      if (favorites is Map) await _favorites(db, favorites);
      if (history is List) await _history(db, history);
      if (downloads is List) await _downloads(db, downloads, downloadsDir);
    });
    for (final f in present.values) {
      try {
        await f.rename('${f.path}.migrated');
      } catch (e) {
        debugPrint('rename ${f.path}: $e');
      }
    }
    return true;
  }

  static Future<void> _saveWork(AppDatabase db, Map<String, dynamic> item) async {
    final source = item['source'].toString();
    final id = item['id'].toString();
    await db
        .into(db.works)
        .insert(
          WorksCompanion.insert(
            source: source,
            id: id,
            title: Value((item['title'] ?? '').toString()),
            cover: Value((item['cover'] ?? '').toString()),
            json: Value(jsonEncode(item)),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  static Future<void> _favorites(AppDatabase db, Map data) async {
    final folders = ((data['folders'] as List?) ?? const []).map((e) => e.toString()).toList();
    final ids = <String, int>{};
    var sort = 0;
    for (final f in folders) {
      if (f == legacyDefaultFolder || ids.containsKey(f)) continue;
      ids[f] = await db.into(db.categories).insert(CategoriesCompanion.insert(name: f, sort: Value(sort++)));
    }
    for (final e in ((data['items'] as List?) ?? const []).whereType<Map>()) {
      final item = (e['item'] as Map?)?.cast<String, dynamic>();
      if (item == null || item['source'] == null || item['id'] == null) continue;
      await _saveWork(db, item);
      final source = item['source'].toString();
      final id = item['id'].toString();
      await (db.update(db.works)..where((w) => w.source.equals(source) & w.id.equals(id))).write(
        WorksCompanion(favorite: const Value(true), favoritedAt: Value((e['added'] as num?)?.toInt() ?? 0)),
      );
      final folder = (e['folder'] ?? legacyDefaultFolder).toString();
      final cat = ids[folder];
      if (cat != null) {
        await db.into(db.workCategories).insert(WorkCategoriesCompanion.insert(source: source, workId: id, categoryId: cat), mode: InsertMode.insertOrIgnore);
      }
    }
  }

  static Future<void> _history(AppDatabase db, List data) async {
    for (final e in data.whereType<Map>()) {
      final item = (e['item'] as Map?)?.cast<String, dynamic>();
      if (item == null || item['source'] == null || item['id'] == null) continue;
      await _saveWork(db, item);
      final source = item['source'].toString();
      final id = item['id'].toString();
      final time = (e['time'] as num?)?.toInt() ?? 0;
      final page = (e['page'] as num?)?.toInt() ?? 0;
      final pageCount = (e['pageCount'] as num?)?.toInt() ?? 0;
      final chapterId = e['chapterId'] as String?;
      await db
          .into(db.history)
          .insertOnConflictUpdate(
            HistoryCompanion.insert(
              source: source,
              workId: id,
              time: time,
              chapterId: Value(chapterId),
              chapterTitle: Value(e['chapterTitle'] as String?),
              page: Value(page),
              pageCount: Value(pageCount),
              position: Value((e['position'] as num?)?.toInt()),
            ),
          );
      if (pageCount > 0) {
        final finished = page >= pageCount - 1;
        await db
            .into(db.chapters)
            .insert(
              ChaptersCompanion.insert(
                source: source,
                workId: id,
                chapterId: (chapterId == null || chapterId.isEmpty) ? '_' : chapterId,
                title: Value((e['chapterTitle'] ?? '').toString()),
                lastPage: Value(page),
                pageCount: Value(pageCount),
                read: Value(finished),
                dateRead: Value(finished ? time : null),
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
    }
  }

  static Future<void> _downloads(AppDatabase db, List data, Directory downloadsDir) async {
    // The old list was in insertion order; keep it by spacing creation times.
    final base = DateTime.now().millisecondsSinceEpoch - data.length;
    for (var i = 0; i < data.length; i++) {
      final e = data[i];
      if (e is! Map) continue;
      final item = (e['item'] as Map?)?.cast<String, dynamic>();
      if (item == null || item['source'] == null || item['id'] == null) continue;
      final source = item['source'].toString();
      final id = item['id'].toString();
      await db
          .into(db.downloadTasks)
          .insert(
            DownloadTasksCompanion.insert(
              uid: '$source:$id',
              source: source,
              json: jsonEncode(e),
              dir: p.join(downloadsDir.path, source, safeFileName(id)),
              createdAt: base + i,
            ),
            mode: InsertMode.insertOrReplace,
          );
    }
  }
}
