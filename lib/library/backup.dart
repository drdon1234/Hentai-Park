import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/async_tasks.dart';
import '../core/diagnostics.dart';
import '../core/localization.dart';
import '../core/settings.dart';
import '../core/storage.dart';
import '../data/database.dart';
import '../engine/source_manager.dart';
import '../novel/reading_notes.dart';
import '../subscriptions/subscription_store.dart';
import 'backup_validation.dart';
import 'library.dart';
import 'progress_merge.dart';
import 'restore_transaction.dart';

class BackupOptions {
  const BackupOptions({
    this.library = true,
    this.settings = true,
    this.sources = true,
    this.credentials = false,
    this.automatic = false,
  });
  final bool library;
  final bool settings;
  final bool sources;

  /// Source private stores (tokens, account ids). Cookie-based logins are not included.
  final bool credentials;
  final bool automatic;
}

class RestoreReport {
  int categories = 0;
  int favorites = 0;
  int chapters = 0;
  int history = 0;
  bool settings = false;
  int sources = 0;
  int subscriptions = 0;
  List<({String key, String url})> sourcesToInstall = [];

  String get summary => [
    if (favorites > 0) tr('收藏 {value0}', {'value0': favorites}),
    if (categories > 0) tr('分类 {value0}', {'value0': categories}),
    if (chapters > 0) tr('章节进度 {value0}', {'value0': chapters}),
    if (history > 0) tr('历史 {value0}', {'value0': history}),
    if (settings) tr('设置'),
    if (sources > 0) tr('站点设置 {value0}', {'value0': sources}),
    if (subscriptions > 0) tr('订阅 {value0}', {'value0': subscriptions}),
  ].join('、');
}

/// `.parkbak` backups: gzip-compressed JSON. Restoring merges into the current data instead of
/// replacing it (favorites are unioned; chapter progress and history keep the newer snapshot).
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const format = 'parkbak';
  static const version = 1;
  static const extension = '.parkbak';
  final _writes = SerialExecutor();
  Future<File?>? _autoBackupRun;

  // ── Create ──

  Future<Uint8List> create([
    BackupOptions options = const BackupOptions(),
  ]) async {
    await Library.instance.flush();
    final json = <String, dynamic>{
      'format': format,
      'version': version,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'origin': options.automatic ? 'automatic' : 'manual',
      if (options.settings) 'settings': AppSettings.instance.exportJson(),
      if (options.library) 'readingNotes': ReadingNotes.instance.exportJson(),
      if (options.library) 'subscriptions': await _subscriptions(),
      if (options.sources)
        'sources': await SourceManager.instance.exportJson(
          credentials: options.credentials,
        ),
    };
    if (!options.library) return Isolate.run(() => encode(json));
    // Read, map and encode on the worker. Returning the whole library to the
    // foreground before encoding duplicates a large snapshot and blocks frames.
    return Library.instance.db.computeWithDatabase<Uint8List, AppDatabase>(
      connect: AppDatabase.new,
      computation: (db) => db.transaction(() => _encodeDatabase(db, json)),
    );
  }

  static Uint8List encode(Map<String, dynamic> json) {
    final bytes = BytesBuilder(copy: false);
    final compression = gzip.encoder.startChunkedConversion(
      _BackupBytes(bytes),
    );
    final encoding = JsonUtf8Encoder().startChunkedConversion(compression);
    encoding.add(json);
    encoding.close();
    return bytes.takeBytes();
  }

  static Map<String, dynamic> decode(List<int> bytes) {
    Object? data;
    try {
      data = jsonDecode(utf8.decode(gzip.decode(bytes)));
    } catch (_) {
      throw FormatException(tr('不是有效的备份文件'));
    }
    if (data is! Map || data['format'] != format) {
      throw FormatException(tr('不是 HentaiPark 备份文件'));
    }
    if (data['version'] is! int || data['version'] < 1) {
      throw const FormatException('备份数据无效');
    }
    if ((data['version'] as int) > version) {
      throw FormatException(tr('备份来自更新版本的应用，请先升级'));
    }
    return data.cast<String, dynamic>();
  }

  static Future<Uint8List> _encodeDatabase(
    AppDatabase db,
    Map<String, dynamic> metadata,
  ) async {
    final bytes = BytesBuilder(copy: false);
    final compression = gzip.encoder.startChunkedConversion(
      _BackupBytes(bytes),
    );
    final encoder = JsonUtf8Encoder();
    void write(Object? value) => compression.add(encoder.convert(value));
    void raw(String value) => compression.add(utf8.encode(value));
    raw('{');
    for (final entry in metadata.entries) {
      write(entry.key);
      raw(':');
      write(entry.value);
      raw(',');
    }
    raw('"library":{');
    var firstSection = true;
    await for (final section in _librarySections(db)) {
      if (!firstSection) raw(',');
      firstSection = false;
      write(section.$1);
      raw(':[');
      var firstRow = true;
      await for (final row in section.$2) {
        if (!firstRow) raw(',');
        firstRow = false;
        write(row);
      }
      raw(']');
    }
    raw('}}');
    compression.close();
    return bytes.takeBytes();
  }

  /// Keyset pages keep only one small batch alive, even for a large chapter table.
  static Stream<Map<String, dynamic>> _rows(AppDatabase db, String sql) async* {
    var cursor = 0;
    while (true) {
      final rows = await db
          .customSelect(sql, variables: [Variable(cursor)])
          .get();
      if (rows.isEmpty) return;
      for (final row in rows) {
        cursor = row.read<int>('cursor');
        yield row.data;
      }
    }
  }

  static Stream<(String, Stream<Map<String, dynamic>>)> _librarySections(
    AppDatabase db,
  ) async* {
    yield (
      'categories',
      _rows(
        db,
        'SELECT rowid AS cursor, name, sort FROM categories WHERE rowid > ? ORDER BY rowid LIMIT 512',
      ).map((r) => {'name': r['name'], 'sort': r['sort']}),
    );
    yield (
      'works',
      _rows(db, '''
      SELECT w.rowid AS cursor, w.*, (
        SELECT json_group_array(c.name) FROM work_categories m
        JOIN categories c ON c.id = m.category_id
        WHERE m.source = w.source AND m.work_id = w.id
      ) AS category_names
      FROM works w WHERE w.rowid > ? AND (w.favorite = 1 OR w.reader_mode IS NOT NULL)
      ORDER BY w.rowid LIMIT 512
    ''').map(
        (r) => {
          'item': jsonDecode(r['json'] as String),
          'source': r['source'],
          'id': r['id'],
          'favorite': r['favorite'] == 1,
          'favoritedAt': r['favorited_at'],
          'readerMode': r['reader_mode'],
          'categories': jsonDecode(r['category_names'] as String),
        },
      ),
    );
    yield (
      'chapters',
      _rows(
        db,
        '''
      SELECT rowid AS cursor, * FROM chapters
      WHERE rowid > ? AND ("read" = 1 OR progress_updated_at IS NOT NULL OR position_updated_at IS NOT NULL) ORDER BY rowid LIMIT 512
    ''',
      ).map(
        (r) => {
          'source': r['source'],
          'workId': r['work_id'],
          'chapterId': r['chapter_id'],
          'title': r['title'],
          'sort': r['sort'],
          'read': r['read'] == 1,
          'lastPage': r['last_page'],
          'pageCount': r['page_count'],
          'progressUpdatedAt': r['progress_updated_at'],
          'dateRead': r['date_read'],
          'position': r['position'],
          'duration': r['duration'],
          'positionUpdatedAt': r['position_updated_at'],
        },
      ),
    );
    yield (
      'history',
      _rows(db, '''
      SELECT h.rowid AS cursor, h.*, w.json FROM history h
      JOIN works w ON w.source = h.source AND w.id = h.work_id
      WHERE h.rowid > ? ORDER BY h.rowid LIMIT 512
    ''').map(
        (r) => {
          'item': jsonDecode(r['json'] as String),
          'source': r['source'],
          'workId': r['work_id'],
          'time': r['time'],
          'chapterId': r['chapter_id'],
          'chapterTitle': r['chapter_title'],
          'page': r['page'],
          'pageCount': r['page_count'],
          'position': r['position'],
        },
      ),
    );
  }

  // ── Restore ──

  Future<Map<String, dynamic>> _subscriptions() async {
    await SubscriptionStore.instance.reload();
    return SubscriptionStore.instance.exportJson();
  }

  Future<RestoreReport> restore(List<int> bytes) => _writes.run(
    () => SourceManager.instance.exclusively(() async {
      final json = await Isolate.run(() => decode(bytes));
      validateBackup(json);
      final report = RestoreReport();
      final lib = json['library'];
      final files = <String, Object?>{};
      await Library.instance.flush();
      await AppSettings.instance.flush();
      await SourceManager.instance.flush();
      final settings = json['settings'];
      if (settings is Map) {
        files['settings.json'] = AppSettings.instance.prepareImport(
          settings.cast<String, dynamic>(),
        );
        report.settings = true;
      }
      if (json.containsKey('readingNotes')) {
        files['reading_notes.json'] = ReadingNotes.instance.prepareMerge(
          json['readingNotes'],
        );
      }
      if (json['subscriptions'] case final data?) {
        await SubscriptionStore.instance.reload();
        SubscriptionStore.parse(data);
        report.subscriptions = SubscriptionStore.parse(data).length;
      }
      final sources = json['sources'];
      if (sources is Map) {
        final s = sources.cast<String, dynamic>();
        final plan = await SourceManager.instance.prepareImport(s);
        files.addAll(plan.files);
        report.sourcesToInstall = plan.missing;
        report.sources = (s['settings'] as Map?)?.length ?? 0;
      }
      await RestoreTransaction.apply(Library.instance.db, files, () async {
        if (json['subscriptions'] case final data?) {
          await SubscriptionStore.instance.merge(data);
        }
        if (lib is Map) {
          await mergeLibrary(
            Library.instance.db,
            lib.cast<String, dynamic>(),
            report,
          );
        }
      });
      // 文件与数据库提交成功后才发布新的内存状态；运行时加载失败由源管理界面呈现。
      await Library.instance.open(Library.instance.db);
      if (settings is Map) await AppSettings.instance.reload();
      if (files.containsKey('reading_notes.json')) {
        await ReadingNotes.instance.reload();
      }
      if (json.containsKey('subscriptions')) {
        await SubscriptionStore.instance.reload();
      }
      if (sources is Map) await SourceManager.instance.reloadFromDisk();
      return report;
    }),
  );

  static Future<void> mergeLibrary(
    AppDatabase db,
    Map<String, dynamic> json,
    RestoreReport report,
  ) async {
    await db.transaction(() async {
      final ids = {
        for (final c in await db.select(db.categories).get()) c.name: c.id,
      };
      var sort = ids.length;
      for (final c
          in ((json['categories'] as List?) ?? const []).whereType<Map>()) {
        final name = c['name'].toString();
        if (ids.containsKey(name)) continue;
        ids[name] = await db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(name: name, sort: Value(sort++)),
            );
        report.categories++;
      }

      Future<void> saveWork(
        Map<String, dynamic> item,
        String source,
        String id,
      ) => db
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
        await saveWork(
          ((w['item'] as Map?) ?? {}).cast<String, dynamic>(),
          source,
          id,
        );
        final current = await (db.select(
          db.works,
        )..where((t) => t.source.equals(source) & t.id.equals(id))).getSingle();
        final favorite = w['favorite'] == true;
        await (db.update(
          db.works,
        )..where((t) => t.source.equals(source) & t.id.equals(id))).write(
          WorksCompanion(
            favorite: Value(current.favorite || favorite),
            favoritedAt: Value(
              current.favorite
                  ? current.favoritedAt
                  : ((w['favoritedAt'] as num?)?.toInt() ??
                        current.favoritedAt),
            ),
            readerMode: Value(
              current.readerMode ?? (w['readerMode'] as num?)?.toInt(),
            ),
          ),
        );
        if (favorite && !current.favorite) report.favorites++;
        for (final name in ((w['categories'] as List?) ?? const [])) {
          final cat = ids[name.toString()];
          if (cat == null) continue;
          await db
              .into(db.workCategories)
              .insert(
                WorkCategoriesCompanion.insert(
                  source: source,
                  workId: id,
                  categoryId: cat,
                ),
                mode: InsertMode.insertOrIgnore,
              );
        }
      }

      for (final c
          in ((json['chapters'] as List?) ?? const []).whereType<Map>()) {
        final source = c['source'].toString();
        final workId = c['workId'].toString();
        final chapterId = c['chapterId'].toString();
        final read = c['read'] == true;
        final lastPage = (c['lastPage'] as num?)?.toInt() ?? 0;
        final pageCount = (c['pageCount'] as num?)?.toInt() ?? 0;
        final dateRead = (c['dateRead'] as num?)?.toInt();
        final progressUpdatedAt = (c['progressUpdatedAt'] as num?)?.toInt();
        final position = (c['position'] as num?)?.toInt() ?? 0;
        final duration = (c['duration'] as num?)?.toInt() ?? 0;
        final positionUpdatedAt = (c['positionUpdatedAt'] as num?)?.toInt();
        final current =
            await (db.select(db.chapters)..where(
                  (t) =>
                      t.source.equals(source) &
                      t.workId.equals(workId) &
                      t.chapterId.equals(chapterId),
                ))
                .getSingleOrNull();
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
                  progressUpdatedAt: Value(progressUpdatedAt),
                  dateRead: Value(
                    positionUpdatedAt != null && !read ? null : dateRead,
                  ),
                  position: Value(position < 0 ? 0 : position),
                  duration: Value(duration < 0 ? 0 : duration),
                  positionUpdatedAt: Value(positionUpdatedAt),
                ),
              );
        } else {
          final selection = selectProgress(
            comic: progressUpdatedAt,
            video: positionUpdatedAt,
            currentComic: current.progressUpdatedAt,
            currentVideo: current.positionUpdatedAt,
          );
          final newerPosition = selection.video;
          final newerProgress = selection.comic;
          final takeProgress = selection.read;
          await db
              .update(db.chapters)
              .replace(
                current.copyWith(
                  read: takeProgress ? read : current.read,
                  lastPage: newerProgress ? lastPage : current.lastPage,
                  pageCount: newerProgress ? pageCount : current.pageCount,
                  progressUpdatedAt: Value(
                    newerProgress
                        ? progressUpdatedAt
                        : current.progressUpdatedAt,
                  ),
                  dateRead: Value(
                    takeProgress ? (read ? dateRead : null) : current.dateRead,
                  ),
                  position: newerPosition
                      ? (position < 0 ? 0 : position)
                      : current.position,
                  duration: newerPosition && duration > 0
                      ? duration
                      : current.duration,
                  positionUpdatedAt: Value(
                    newerPosition
                        ? positionUpdatedAt
                        : current.positionUpdatedAt,
                  ),
                ),
              );
        }
        report.chapters++;
      }

      for (final h
          in ((json['history'] as List?) ?? const []).whereType<Map>()) {
        final source = h['source'].toString();
        final workId = h['workId'].toString();
        final time = (h['time'] as num?)?.toInt() ?? 0;
        await saveWork(
          ((h['item'] as Map?) ?? {}).cast<String, dynamic>(),
          source,
          workId,
        );
        final current =
            await (db.select(db.history)..where(
                  (t) => t.source.equals(source) & t.workId.equals(workId),
                ))
                .getSingleOrNull();
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

  Future<File> writeTo(
    Directory dir, [
    BackupOptions options = const BackupOptions(),
  ]) async {
    return _writes.run(() async {
      await dir.create(recursive: true);
      final bytes = await create(options);
      final base = fileName(DateTime.now());
      var file = File(p.join(dir.path, base));
      for (var suffix = 2; await file.exists(); suffix++) {
        file = File(
          p.join(
            dir.path,
            '${p.basenameWithoutExtension(base)}_${suffix.toString().padLeft(6, '0')}$extension',
          ),
        );
      }
      await writeFileAtomic(file, bytes);
      return file;
    });
  }

  Future<List<File>> listBackups() async {
    final dir = AppPaths.backups;
    if (!await dir.exists()) return [];
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith(extension))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path)); // names embed the timestamp
    return files;
  }

  /// Writes an automatic backup when due. Retention never includes manual or unknown origins.
  Future<File?> autoBackupIfDue() async {
    final active = _autoBackupRun;
    if (active != null) return active;
    late final Future<File?> run;
    run = _autoBackup().whenComplete(() {
      if (identical(_autoBackupRun, run)) _autoBackupRun = null;
    });
    _autoBackupRun = run;
    return run;
  }

  Future<File?> _autoBackup() async {
    final s = AppSettings.instance;
    if (s.autoBackupHours <= 0) return null;
    final due = DateTime.fromMillisecondsSinceEpoch(s.lastAutoBackup)
        .add(Duration(hours: s.autoBackupHours));
    if (DateTime.now().isBefore(due)) return null;
    try {
      final file = await writeTo(
        AppPaths.backups,
        const BackupOptions(automatic: true),
      );
      s.lastAutoBackup = DateTime.now().millisecondsSinceEpoch;
      final all = <File>[];
      for (final candidate in await listBackups()) {
        try {
          if (decode(await candidate.readAsBytes())['origin'] == 'automatic') {
            all.add(candidate);
          }
        } catch (_) {
          // Unknown or damaged user backups are never retention candidates.
        }
      }
      for (final old in all.skip(s.autoBackupKeep.clamp(1, 50))) {
        await old.delete();
      }
      return file;
    } catch (e) {
      debugPrint(Diagnostics.error(e));
      return null;
    }
  }
}

class _BackupBytes implements Sink<List<int>> {
  _BackupBytes(this.bytes);
  final BytesBuilder bytes;

  @override
  void add(List<int> data) => bytes.add(data);

  @override
  void close() {}
}
