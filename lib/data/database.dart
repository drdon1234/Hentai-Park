import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'database.g.dart';

/// Every work the app has a reason to remember (favorite, history, downloaded, chapters known).
/// `json` is the latest [WorkItem] snapshot; the other columns are what queries filter and sort on.
@DataClassName('WorkRow')
class Works extends Table {
  TextColumn get source => text()();
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get cover => text().withDefault(const Constant(''))();
  TextColumn get json => text().withDefault(const Constant('{}'))();
  BoolColumn get favorite => boolean().withDefault(const Constant(false))();
  IntColumn get favoritedAt => integer().nullable()();
  IntColumn get lastUpdateCheck => integer().nullable()();
  IntColumn get readerMode => integer().nullable()();

  /// The site lists no chapters for this work (a single gallery), so library updates can skip it. Added in v2.
  BoolColumn get oneShot => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {source, id};
}

@DataClassName('CategoryRow')
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
  IntColumn get sort => integer().withDefault(const Constant(0))();
}

@DataClassName('WorkCategoryRow')
class WorkCategories extends Table {
  TextColumn get source => text()();
  TextColumn get workId => text()();
  IntColumn get categoryId => integer().references(Categories, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {source, workId, categoryId};
}

/// Chapters of a work as last seen on the site, with per-chapter reading state.
/// One-shot works use a single pseudo chapter ('_' or the source's `singleChapterId`).
@DataClassName('ChapterRow')
class Chapters extends Table {
  TextColumn get source => text()();
  TextColumn get workId => text()();
  TextColumn get chapterId => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  IntColumn get sort => integer().withDefault(const Constant(0))();
  BoolColumn get read => boolean().withDefault(const Constant(false))();
  IntColumn get lastPage => integer().withDefault(const Constant(0))();
  IntColumn get pageCount => integer().withDefault(const Constant(0))();
  IntColumn get dateFetch => integer().withDefault(const Constant(0))();
  IntColumn get dateRead => integer().nullable()();

  /// Video playback state for this chapter. Values are media seconds; the timestamp
  /// below is the wall-clock time at which the position was written.
  IntColumn get position => integer().withDefault(const Constant(0))();
  IntColumn get duration => integer().withDefault(const Constant(0))();
  IntColumn get positionUpdatedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {source, workId, chapterId};
}

/// Latest reading / watching position per work ("continue reading").
@DataClassName('HistoryRow')
class History extends Table {
  TextColumn get source => text()();
  TextColumn get workId => text()();
  IntColumn get time => integer()();
  TextColumn get chapterId => text().nullable()();
  TextColumn get chapterTitle => text().nullable()();
  IntColumn get page => integer().withDefault(const Constant(0))();
  IntColumn get pageCount => integer().withDefault(const Constant(0))();
  IntColumn get position => integer().nullable()();

  @override
  Set<Column> get primaryKey => {source, workId};
}

@DataClassName('DownloadRow')
class DownloadTasks extends Table {
  TextColumn get uid => text()();
  TextColumn get source => text()();
  TextColumn get json => text()();
  TextColumn get dir => text()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {uid};
}

@DriftDatabase(tables: [Works, Categories, WorkCategories, Chapters, History, DownloadTasks])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  factory AppDatabase.file(File file) => AppDatabase(NativeDatabase.createInBackground(file));
  factory AppDatabase.memory() => AppDatabase(NativeDatabase.memory());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement('CREATE INDEX IF NOT EXISTS idx_works_favorite ON works (favorite)');
      await customStatement('CREATE INDEX IF NOT EXISTS idx_chapters_fetch ON chapters (date_fetch)');
    },
    // Future schema changes go here, keyed on `from`; each step must be idempotent.
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.addColumn(works, works.oneShot);
      if (from < 3) {
        await m.addColumn(chapters, chapters.position);
        await m.addColumn(chapters, chapters.duration);
        await m.addColumn(chapters, chapters.positionUpdatedAt);
        await normalizeVideoRecords();
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Copies the legacy work-level video position into its chapter row once.
  /// Explicit per-episode progress always wins over the old history snapshot.
  Future<void> normalizeVideoRecords() async {
    // Match WorkDetail.videoEpisodes: a source's singleChapterId is the stable
    // identity when the legacy history did not record an episode.
    await customStatement(r'''
      UPDATE history SET chapter_id = COALESCE((
        SELECT NULLIF(CAST(json_extract(w.json, '$.singleChapterId') AS TEXT), '')
        FROM works w WHERE w.source = history.source AND w.id = history.work_id
          AND json_valid(w.json)
      ), '_')
      WHERE position IS NOT NULL AND (chapter_id IS NULL OR chapter_id = '')
    ''');
    await customStatement('''
      INSERT INTO chapters (source, work_id, chapter_id, title, position, position_updated_at)
      SELECT h.source, h.work_id, COALESCE(NULLIF(h.chapter_id, ''), '_'),
             COALESCE(h.chapter_title, ''), MAX(h.position, 0), h.time
      FROM history h LEFT JOIN chapters c
        ON c.source = h.source AND c.work_id = h.work_id
        AND c.chapter_id = COALESCE(NULLIF(h.chapter_id, ''), '_')
      WHERE h.position IS NOT NULL
        AND c.position_updated_at IS NULL
      ON CONFLICT(source, work_id, chapter_id) DO UPDATE SET
        position = excluded.position, position_updated_at = excluded.position_updated_at
      WHERE chapters.position_updated_at IS NULL
    ''');
  }

  Future<bool> get isEmpty async {
    final works = await (select(this.works)..limit(1)).get();
    final tasks = await (select(downloadTasks)..limit(1)).get();
    return works.isEmpty && tasks.isEmpty;
  }
}
