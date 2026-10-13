import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../subscriptions/schema.dart';

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

  /// The site lists no chapters for this work (a single gallery), so library updates can skip it.
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
  IntColumn get categoryId =>
      integer().references(Categories, #id, onDelete: KeyAction.cascade)();

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
  IntColumn get progressUpdatedAt => integer().nullable()();

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

class RestoreCheckpoints extends Table {
  IntColumn get id => integer()();
  TextColumn get token => text()();
  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Works,
    Categories,
    WorkCategories,
    Chapters,
    History,
    DownloadTasks,
    RestoreCheckpoints,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  factory AppDatabase.file(File file) =>
      AppDatabase(NativeDatabase.createInBackground(file));
  factory AppDatabase.memory() => AppDatabase(NativeDatabase.memory());

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await createSubscriptionTables(this);
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_works_favorite ON works (favorite)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_chapters_fetch ON chapters (date_fetch)',
      );
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.addColumn(works, works.oneShot);
      if (from < 3) {
        await m.addColumn(chapters, chapters.position);
        await m.addColumn(chapters, chapters.duration);
        await m.addColumn(chapters, chapters.positionUpdatedAt);
      }
      if (from < 4) await m.addColumn(chapters, chapters.progressUpdatedAt);
      if (from < 5) await m.createTable(restoreCheckpoints);
      if (from < 6) await createSubscriptionTables(this);
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
