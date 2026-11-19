import 'package:drift/drift.dart';

Future<void> createTavernTables(GeneratedDatabase db) async {
  await db.customStatement(
    '''CREATE TABLE IF NOT EXISTS tavern_drafts (id TEXT PRIMARY KEY, content TEXT NOT NULL, portrait BLOB)''',
  );
  await db.customStatement('''CREATE TABLE IF NOT EXISTS tavern_resources (
    uid TEXT PRIMARY KEY, item_json TEXT NOT NULL, kind TEXT NOT NULL,
    format TEXT NOT NULL, card_json TEXT NOT NULL, original BLOB NOT NULL,
    saved_at INTEGER NOT NULL)''');
  await db.customStatement('''CREATE TABLE IF NOT EXISTS tavern_edits (
    revision TEXT PRIMARY KEY, uid TEXT NOT NULL REFERENCES tavern_resources(uid) ON DELETE CASCADE,
    saved_at INTEGER NOT NULL, content TEXT NOT NULL)''');
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_tavern_edits ON tavern_edits(uid,saved_at DESC)',
  );
  await db.customStatement('''CREATE TRIGGER IF NOT EXISTS remember_tavern_edit BEFORE UPDATE OF card_json ON tavern_resources
    WHEN OLD.card_json <> NEW.card_json BEGIN
    INSERT INTO tavern_edits VALUES(lower(hex(randomblob(16))),OLD.uid,OLD.saved_at,OLD.card_json);
    END''');
  await db.customStatement('''CREATE TRIGGER IF NOT EXISTS prune_tavern_edits AFTER INSERT ON tavern_edits BEGIN
    DELETE FROM tavern_edits WHERE uid=NEW.uid AND revision NOT IN
      (SELECT revision FROM tavern_edits WHERE uid=NEW.uid ORDER BY saved_at DESC,rowid DESC LIMIT 8);
    END''');
  await db.customStatement('''CREATE TABLE IF NOT EXISTS tavern_sessions (
    id TEXT PRIMARY KEY, resource_uid TEXT NOT NULL REFERENCES tavern_resources(uid) ON DELETE RESTRICT,
    data_json TEXT NOT NULL, updated_at INTEGER NOT NULL)''');
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_tavern_sessions_updated ON tavern_sessions(updated_at)',
  );
}
