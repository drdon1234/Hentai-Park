import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/settings.dart';
import '../core/storage.dart';
import '../data/database.dart';
import '../engine/source_manager.dart';
import 'library.dart';
import '../core/localization.dart';

class BackupOptions {
  const BackupOptions({this.library = true, this.settings = true, this.sources = true, this.credentials = false});
  final bool library;
  final bool settings;
  final bool sources;

  /// Source private stores (tokens, account ids). Cookie-based logins are not included.
  final bool credentials;
}

class RestoreReport {
  int categories = 0;
  int favorites = 0;
  int chapters = 0;
  int history = 0;
  bool settings = false;
  int sources = 0;
  List<({String key, String url})> sourcesToInstall = [];

  String get summary => [
    if (favorites > 0) tr('收藏 {value0}', {'value0': favorites}),
    if (categories > 0) tr('分类 {value0}', {'value0': categories}),
    if (chapters > 0) tr('章节进度 {value0}', {'value0': chapters}),
    if (history > 0) tr('历史 {value0}', {'value0': history}),
    if (settings) tr('设置'),
    if (sources > 0) tr('源设置 {value0}', {'value0': sources}),
  ].join('、');
}

/// `.parkbak` backups: gzip-compressed JSON. Restoring merges into the current data instead of
/// replacing it (favorites are unioned, read marks OR-ed, progress and history keep the newer value).
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const format = 'parkbak';
  static const version = 1;
  static const extension = '.parkbak';

  // ── Create ──

  Future<Uint8List> create([BackupOptions options = const BackupOptions()]) async {
    await Library.instance.flush();
    final json = <String, dynamic>{
      'format': format,
      'version': version,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      if (options.library) 'library': await exportLibrary(Library.instance.db),
      if (options.settings) 'settings': AppSettings.instance.exportJson(),
      if (options.sources) 'sources': SourceManager.instance.exportJson(credentials: options.credentials),
    };
    return encode(json);
  }

  static Uint8List encode(Map<String, dynamic> json) => Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(json))));

  static Map<String, dynamic> decode(List<int> bytes) {
    Object? data;
    try {
      data = jsonDecode(utf8.decode(gzip.decode(bytes)));
    } catch (_) {
      throw FormatException(tr('不是有效的备份文件'));
    }
    if (data is! Map || data['format'] != format) throw FormatException(tr('不是 HentaiPark 备份文件'));
    if ((data['version'] as num? ?? 0) > version) throw FormatException(tr('备份来自更新版本的应用，请先升级'));
    return data.cast<String, dynamic>();
  }

  static Future<Map<String, dynamic>> exportLibrary(AppDatabase db) async {
    final categories = await db.select(db.categories).get();
    final names = {for (final c in categories) c.id: c.name};
    final memberships = <String, List<String>>{};
    for (final m in await db.select(db.workCategories).get()) {
      final n = names[m.categoryId];
      if (n != null) memberships.putIfAbsent('${m.source}:${m.workId}', () => []).add(n);
    }
    final works = await (db.select(db.works)..where((w) => w.favorite.equals(true) | w.readerMode.isNotNull())).get();
    final chapters = await (db.select(db.chapters)..where((c) => c.read.equals(true) | c.lastPage.isBiggerThanValue(0))).get();
    final history = await db.select(db.history).join([innerJoin(db.works, db.works.source.equalsExp(db.history.source) & db.works.id.equalsExp(db.history.workId))]).get();
    return {
      'categories': [
        for (final c in categories) {'name': c.name, 'sort': c.sort},
      ],
      'works': [
        for (final w in works)
          {
            'item': jsonDecode(w.json),
            'source': w.source,
            'id': w.id,
            'favorite': w.favorite,
            'favoritedAt': w.favoritedAt,
            'readerMode': w.readerMode,
            'categories': memberships['${w.source}:${w.id}'] ?? const [],
          },
      ],
      'chapters': [
        for (final c in chapters)
          {
            'source': c.source,
            'workId': c.workId,
            'chapterId': c.chapterId,
            'title': c.title,
            'sort': c.sort,
            'read': c.read,
            'lastPage': c.lastPage,
            'pageCount': c.pageCount,
            'dateRead': c.dateRead,
          },
      ],
      'history': [
        for (final r in history)
          () {
            final h = r.readTable(db.history);
            final w = r.readTable(db.works);
            return {
              'item': jsonDecode(w.json),
              'source': h.source,
              'workId': h.workId,
              'time': h.time,
              'chapterId': h.chapterId,
              'chapterTitle': h.chapterTitle,
              'page': h.page,
              'pageCount': h.pageCount,
              'position': h.position,
            };
          }(),
      ],
    };
  }

  // ── Restore ──

  Future<RestoreReport> restore(List<int> bytes) async {
    final json = decode(bytes);
    final report = RestoreReport();
    final lib = json['library'];
    if (lib is Map) {
      await Library.instance.flush();
      await mergeLibrary(Library.instance.db, lib.cast<String, dynamic>(), report);
      await Library.instance.open(Library.instance.db);
    }
    final settings = json['settings'];
    if (settings is Map) {
      AppSettings.instance.importJson(settings.cast<String, dynamic>());
      report.settings = true;
    }
    final sources = json['sources'];
    if (sources is Map) {
      final s = sources.cast<String, dynamic>();
      report.sourcesToInstall = await SourceManager.instance.importJson(s);
      report.sources = (s['settings'] as Map?)?.length ?? 0;
    }
    return report;
  }

  static Future<void> mergeLibrary(AppDatabase db, Map<String, dynamic> json, RestoreReport report) async {
    await db.transaction(() async {
      final ids = {for (final c in await db.select(db.categories).get()) c.name: c.id};
      var sort = ids.length;
      for (final c in ((json['categories'] as List?) ?? const []).whereType<Map>()) {
        final name = c['name'].toString();
        if (ids.containsKey(name)) continue;
        ids[name] = await db.into(db.categories).insert(CategoriesCompanion.insert(name: name, sort: Value(sort++)));
        report.categories++;
      }

      Future<void> saveWork(Map<String, dynamic> item, String source, String id) => db
          .into(db.works)
          .insert(
            WorksCompanion.insert(
              source: source,
              id: id,
              title: Value((item['title'] ?? '').toString()),
              cover: Value((item['cover'] ?? '').toString()),
              json: Value(jsonEncode({...item, 'source': source, 'id': id})),
            ),
            mode: InsertMode.insertOrIgnore,
          );

      for (final w in ((json['works'] as List?) ?? const []).whereType<Map>()) {
        final source = w['source'].toString();
        final id = w['id'].toString();
        await saveWork(((w['item'] as Map?) ?? {}).cast<String, dynamic>(), source, id);
        final current = await (db.select(db.works)..where((t) => t.source.equals(source) & t.id.equals(id))).getSingle();
        final favorite = w['favorite'] == true;
        await (db.update(db.works)..where((t) => t.source.equals(source) & t.id.equals(id))).write(
          WorksCompanion(
            favorite: Value(current.favorite || favorite),
            favoritedAt: Value(current.favorite ? current.favoritedAt : ((w['favoritedAt'] as num?)?.toInt() ?? current.favoritedAt)),
            readerMode: Value(current.readerMode ?? (w['readerMode'] as num?)?.toInt()),
          ),
        );
        if (favorite && !current.favorite) report.favorites++;
        for (final name in ((w['categories'] as List?) ?? const [])) {
          final cat = ids[name.toString()];
          if (cat == null) continue;
          await db.into(db.workCategories).insert(WorkCategoriesCompanion.insert(source: source, workId: id, categoryId: cat), mode: InsertMode.insertOrIgnore);
        }
      }

      for (final c in ((json['chapters'] as List?) ?? const []).whereType<Map>()) {
        final source = c['source'].toString();
        final workId = c['workId'].toString();
        final chapterId = c['chapterId'].toString();
        final read = c['read'] == true;
        final lastPage = (c['lastPage'] as num?)?.toInt() ?? 0;
        final pageCount = (c['pageCount'] as num?)?.toInt() ?? 0;
        final dateRead = (c['dateRead'] as num?)?.toInt();
        final current = await (db.select(
          db.chapters,
        )..where((t) => t.source.equals(source) & t.workId.equals(workId) & t.chapterId.equals(chapterId))).getSingleOrNull();
        if (current == null) {
          await db
              .into(db.chapters)
              .insert(
                ChaptersCompanion.insert(
                  source: source,
                  workId: workId,
                  chapterId: chapterId,
                  title: Value((c['title'] ?? '').toString()),
                  sort: Value((c['sort'] as num?)?.toInt() ?? 0),
                  read: Value(read),
                  lastPage: Value(lastPage),
                  pageCount: Value(pageCount),
                  dateRead: Value(dateRead),
                ),
              );
        } else {
          await db
              .update(db.chapters)
              .replace(
                current.copyWith(
                  read: current.read || read,
                  lastPage: current.lastPage > lastPage ? current.lastPage : lastPage,
                  pageCount: current.pageCount > pageCount ? current.pageCount : pageCount,
                  dateRead: Value(current.dateRead ?? dateRead),
                ),
              );
        }
        report.chapters++;
      }

      for (final h in ((json['history'] as List?) ?? const []).whereType<Map>()) {
        final source = h['source'].toString();
        final workId = h['workId'].toString();
        final time = (h['time'] as num?)?.toInt() ?? 0;
        await saveWork(((h['item'] as Map?) ?? {}).cast<String, dynamic>(), source, workId);
        final current = await (db.select(db.history)..where((t) => t.source.equals(source) & t.workId.equals(workId))).getSingleOrNull();
        if (current != null && current.time >= time) continue;
        await db
            .into(db.history)
            .insertOnConflictUpdate(
              HistoryCompanion.insert(
                source: source,
                workId: workId,
                time: time,
                chapterId: Value(h['chapterId'] as String?),
                chapterTitle: Value(h['chapterTitle'] as String?),
                page: Value((h['page'] as num?)?.toInt() ?? 0),
                pageCount: Value((h['pageCount'] as num?)?.toInt() ?? 0),
                position: Value((h['position'] as num?)?.toInt()),
              ),
            );
        report.history++;
      }
    });
  }

  // ── Files & automatic backups ──

  static String fileName(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'hentaipark_${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}$extension';
  }

  Future<File> writeTo(Directory dir, [BackupOptions options = const BackupOptions()]) async {
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, fileName(DateTime.now())));
    await file.writeAsBytes(await create(options), flush: true);
    return file;
  }

  Future<List<File>> listBackups() async {
    final dir = AppPaths.backups;
    if (!await dir.exists()) return [];
    final files = await dir.list().where((e) => e is File && e.path.endsWith(extension)).cast<File>().toList();
    files.sort((a, b) => b.path.compareTo(a.path)); // names embed the timestamp
    return files;
  }

  /// Writes an automatic backup when the configured interval has passed, then prunes old ones.
  Future<File?> autoBackupIfDue() async {
    final s = AppSettings.instance;
    if (s.autoBackupHours <= 0) return null;
    final due = DateTime.fromMillisecondsSinceEpoch(s.lastAutoBackup).add(Duration(hours: s.autoBackupHours));
    if (DateTime.now().isBefore(due)) return null;
    try {
      final file = await writeTo(AppPaths.backups);
      s.lastAutoBackup = DateTime.now().millisecondsSinceEpoch;
      final all = await listBackups();
      for (final old in all.skip(s.autoBackupKeep.clamp(1, 50))) {
        await old.delete();
      }
      return file;
    } catch (e) {
      debugPrint('auto backup failed: $e');
      return null;
    }
  }
}
