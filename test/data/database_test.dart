import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hentai_park/data/database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  test('creates schema and round-trips composite keys', () async {
    expect(await db.isEmpty, isTrue);
    await db.into(db.works).insert(WorksCompanion.insert(source: 'jm', id: '1', title: const Value('A')));
    await db.into(db.works).insertOnConflictUpdate(WorksCompanion.insert(source: 'jm', id: '1', title: const Value('B')));
    final rows = await db.select(db.works).get();
    expect(rows.single.title, 'B');
    expect(rows.single.favorite, isFalse);
    expect(await db.isEmpty, isFalse);
  });

  test('upgrades a v1 database by adding works.one_shot', () async {
    final raw = sqlite3.openInMemory();
    // The v1 works table, as shipped before one_shot existed.
    raw.execute(r"""
      CREATE TABLE works (
        source TEXT NOT NULL, id TEXT NOT NULL, title TEXT NOT NULL DEFAULT '', cover TEXT NOT NULL DEFAULT '',
        json TEXT NOT NULL DEFAULT '{}', favorite INTEGER NOT NULL DEFAULT 0, favorited_at INTEGER,
        last_update_check INTEGER, reader_mode INTEGER, PRIMARY KEY (source, id))
    """);
    raw.execute("INSERT INTO works (source, id, title) VALUES ('jm', '1', 'old')");
    raw.execute('PRAGMA user_version = 1');
    final upgraded = AppDatabase(NativeDatabase.opened(raw));
    final row = await upgraded.select(upgraded.works).getSingle();
    expect(row.title, 'old');
    expect(row.oneShot, isFalse);
    await upgraded.close();
  });

  test('deleting a category cascades to memberships', () async {
    final id = await db.into(db.categories).insert(CategoriesCompanion.insert(name: '连载'));
    await db.into(db.workCategories).insert(WorkCategoriesCompanion.insert(source: 'jm', workId: '1', categoryId: id));
    await (db.delete(db.categories)..where((c) => c.id.equals(id))).go();
    expect(await db.select(db.workCategories).get(), isEmpty);
  });
}
