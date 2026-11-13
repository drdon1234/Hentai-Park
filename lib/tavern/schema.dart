import 'package:drift/drift.dart';

Future<void> createTavernTables(GeneratedDatabase db) async {
  await db.customStatement('''CREATE TABLE IF NOT EXISTS tavern_resources (
    uid TEXT PRIMARY KEY, item_json TEXT NOT NULL, kind TEXT NOT NULL,
    format TEXT NOT NULL, card_json TEXT NOT NULL, original BLOB NOT NULL,
    saved_at INTEGER NOT NULL)''');
  await db.customStatement('''CREATE TABLE IF NOT EXISTS tavern_sessions (
    id TEXT PRIMARY KEY, resource_uid TEXT NOT NULL REFERENCES tavern_resources(uid) ON DELETE RESTRICT,
    data_json TEXT NOT NULL, updated_at INTEGER NOT NULL)''');
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_tavern_sessions_updated ON tavern_sessions(updated_at)',
  );
}
