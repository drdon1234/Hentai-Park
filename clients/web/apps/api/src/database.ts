import { DatabaseSync } from 'node:sqlite';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { workCollectionResourceKey, subscriptionResourceKey, downloadTaskId } from '@hentai-park/domain-model';

export const MIGRATION_VERSION = 14;
export const schemaSql = `
CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS works (source TEXT NOT NULL, work_id TEXT NOT NULL, title TEXT NOT NULL, cover TEXT, media_kind TEXT NOT NULL, category TEXT NOT NULL, source_category TEXT, summary TEXT, source_url TEXT NOT NULL, capability_json TEXT NOT NULL, source_version TEXT, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1, PRIMARY KEY(source, work_id));
CREATE TABLE IF NOT EXISTS chapters (source TEXT NOT NULL, work_id TEXT NOT NULL, chapter_id TEXT NOT NULL, title TEXT NOT NULL, sort REAL NOT NULL, read_state TEXT NOT NULL DEFAULT 'unread', page_progress INTEGER, video_position REAL, duration REAL, progress_updated_at TEXT, version INTEGER NOT NULL DEFAULT 1, PRIMARY KEY(source, work_id, chapter_id), FOREIGN KEY(source, work_id) REFERENCES works(source, work_id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS history (source TEXT NOT NULL, work_id TEXT NOT NULL, chapter_id TEXT, chapter_title TEXT, page INTEGER, page_count INTEGER, position REAL, updated_at TEXT NOT NULL, PRIMARY KEY(source, work_id, chapter_id));
CREATE TABLE IF NOT EXISTS categories (id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1);
CREATE TABLE IF NOT EXISTS work_collections (source TEXT NOT NULL, work_id TEXT NOT NULL, favorite INTEGER NOT NULL DEFAULT 0, favorited_at TEXT, category_ids_json TEXT NOT NULL DEFAULT '[]', updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1, resource_key TEXT NOT NULL UNIQUE, PRIMARY KEY(source, work_id), FOREIGN KEY(source, work_id) REFERENCES works(source, work_id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS source_registry (source TEXT PRIMARY KEY, manifest_json TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1, updated_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS source_settings (source TEXT PRIMARY KEY, settings_json TEXT NOT NULL, updated_at TEXT NOT NULL, FOREIGN KEY(source) REFERENCES source_registry(source) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS source_accounts (source TEXT PRIMARY KEY, account_json TEXT NOT NULL, updated_at TEXT NOT NULL, FOREIGN KEY(source) REFERENCES source_registry(source) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS app_settings (key TEXT PRIMARY KEY, value_json TEXT NOT NULL, updated_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS download_tasks (task_id TEXT PRIMARY KEY, source TEXT NOT NULL, work_id TEXT NOT NULL, chapter_id TEXT NOT NULL, variant TEXT NOT NULL, resource_key TEXT NOT NULL UNIQUE, idempotency_key TEXT NOT NULL UNIQUE, status TEXT NOT NULL, completed_count INTEGER NOT NULL DEFAULT 0, total_count INTEGER NOT NULL DEFAULT 0, bytes INTEGER NOT NULL DEFAULT 0, speed REAL, failure_code TEXT, retry_count INTEGER NOT NULL DEFAULT 0, recoverable INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1, UNIQUE(source, work_id, chapter_id, variant));
CREATE TABLE IF NOT EXISTS download_files (id INTEGER PRIMARY KEY AUTOINCREMENT, task_id TEXT NOT NULL, resource_key TEXT NOT NULL UNIQUE, path TEXT, status TEXT NOT NULL DEFAULT 'pending', bytes INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, FOREIGN KEY(task_id) REFERENCES download_tasks(task_id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS deletion_intents (intent_id TEXT PRIMARY KEY, resource_key TEXT NOT NULL UNIQUE, task_id TEXT, status TEXT NOT NULL DEFAULT 'pending', requested_at TEXT NOT NULL, completed_at TEXT, FOREIGN KEY(task_id) REFERENCES download_tasks(task_id) ON DELETE SET NULL);
CREATE TABLE IF NOT EXISTS task_leases (task_id TEXT PRIMARY KEY, lease_owner TEXT NOT NULL, lease_expires_at TEXT NOT NULL, heartbeat_at TEXT NOT NULL, cancellation_requested INTEGER NOT NULL DEFAULT 0, recovered_at TEXT, lease_generation INTEGER NOT NULL, FOREIGN KEY(task_id) REFERENCES download_tasks(task_id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS restore_checkpoints (task_id TEXT PRIMARY KEY, checkpoint_json TEXT NOT NULL, recoverable INTEGER NOT NULL DEFAULT 1, updated_at TEXT NOT NULL, FOREIGN KEY(task_id) REFERENCES download_tasks(task_id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS subscriptions (subscription_id TEXT PRIMARY KEY, source TEXT NOT NULL, dimension TEXT NOT NULL, target TEXT NOT NULL, resource_key TEXT NOT NULL UNIQUE, enabled INTEGER NOT NULL DEFAULT 1, notify INTEGER NOT NULL DEFAULT 1, baseline TEXT, last_success TEXT, next_due TEXT, failures INTEGER NOT NULL DEFAULT 0, context_hash TEXT, updated_at TEXT NOT NULL, version INTEGER NOT NULL DEFAULT 1, UNIQUE(source, dimension, target));
CREATE TABLE IF NOT EXISTS subscription_checks (id INTEGER PRIMARY KEY AUTOINCREMENT, subscription_id TEXT NOT NULL, checked_at TEXT NOT NULL, success INTEGER NOT NULL, error_code TEXT, FOREIGN KEY(subscription_id) REFERENCES subscriptions(subscription_id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS subscription_seen (subscription_id TEXT NOT NULL, content_id TEXT NOT NULL, observed_at TEXT NOT NULL, content_version TEXT, PRIMARY KEY(subscription_id, content_id), FOREIGN KEY(subscription_id) REFERENCES subscriptions(subscription_id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS subscription_events (event_id TEXT PRIMARY KEY, subscription_id TEXT NOT NULL, content_id TEXT NOT NULL, observed_at TEXT NOT NULL, content_version TEXT, payload_json TEXT, FOREIGN KEY(subscription_id) REFERENCES subscriptions(subscription_id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS domain_events (event_id TEXT PRIMARY KEY, sequence INTEGER NOT NULL UNIQUE, event_type TEXT NOT NULL, aggregate_type TEXT NOT NULL, aggregate_id TEXT NOT NULL, aggregate_version INTEGER NOT NULL, event_version INTEGER NOT NULL, created_at TEXT NOT NULL, payload_json TEXT NOT NULL, UNIQUE(aggregate_type, aggregate_id, event_version));
CREATE TABLE IF NOT EXISTS event_outbox (event_id TEXT PRIMARY KEY, published_at TEXT, attempts INTEGER NOT NULL DEFAULT 0, FOREIGN KEY(event_id) REFERENCES domain_events(event_id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS event_deliveries (event_id TEXT NOT NULL, consumer_id TEXT NOT NULL, delivered_at TEXT NOT NULL, processed_at TEXT, PRIMARY KEY(event_id, consumer_id), FOREIGN KEY(event_id) REFERENCES domain_events(event_id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS event_read_states (event_id TEXT NOT NULL, viewer_id TEXT NOT NULL, tab_id TEXT NOT NULL, read_at TEXT NOT NULL, PRIMARY KEY(event_id, viewer_id, tab_id), FOREIGN KEY(event_id) REFERENCES domain_events(event_id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS idempotency_records (request_key TEXT PRIMARY KEY, operation TEXT NOT NULL, response_status INTEGER NOT NULL, response_json TEXT NOT NULL, created_at TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS idx_download_tasks_status ON download_tasks(status);
CREATE INDEX IF NOT EXISTS idx_domain_events_sequence ON domain_events(sequence);
`;

export class AppDatabase {
  readonly db: DatabaseSync;
  readonly path: string;
  constructor(path = process.env.WEB_DB_PATH ?? './data/web.sqlite') {
    this.path = path;
    if (path !== ':memory:') mkdirSync(dirname(path), { recursive: true });
    this.db = new DatabaseSync(path);
    try {
      this.db.exec('PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000; PRAGMA foreign_keys=ON; PRAGMA synchronous=NORMAL;');
      this.migrate();
    } catch(error) { this.db.close(); throw error; }
  }
  migrate() {
    const current = Number((this.db.prepare('PRAGMA user_version').get() as { user_version?: number }).user_version ?? 0);
    if (current > MIGRATION_VERSION) throw new Error(`Unsupported database version ${current}`);
    let version = current;
    this.db.exec('BEGIN IMMEDIATE');
    try {
      this.db.exec(schemaSql);
      const row = this.db.prepare('SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1').get() as { version?: number } | undefined;
      if (!row) this.db.prepare('INSERT INTO schema_migrations(version, applied_at) VALUES(?, ?)').run(1, new Date().toISOString());
      if (current < 2) {
        this.db.exec(`ALTER TABLE history RENAME TO history_legacy;
          CREATE TABLE history (source TEXT NOT NULL, work_id TEXT NOT NULL, chapter_id TEXT, chapter_title TEXT, page INTEGER, page_count INTEGER, position REAL, updated_at TEXT NOT NULL, scope_key TEXT NOT NULL UNIQUE, FOREIGN KEY(source, work_id) REFERENCES works(source, work_id) ON DELETE CASCADE);
          INSERT INTO history(source,work_id,chapter_id,chapter_title,page,page_count,position,updated_at,scope_key) SELECT source,work_id,chapter_id,chapter_title,page,page_count,position,updated_at,source||':'||work_id||':'||COALESCE(chapter_id,'__work__') FROM history_legacy;
          DROP TABLE history_legacy;
          ALTER TABLE idempotency_records RENAME TO idempotency_records_legacy;
          CREATE TABLE idempotency_records (operation TEXT NOT NULL, request_key TEXT NOT NULL, request_fingerprint TEXT NOT NULL, response_status INTEGER NOT NULL, response_json TEXT NOT NULL, created_at TEXT NOT NULL, PRIMARY KEY(operation, request_key));
          INSERT INTO idempotency_records(operation,request_key,request_fingerprint,response_status,response_json,created_at) SELECT operation,request_key,request_key,response_status,response_json,created_at FROM idempotency_records_legacy;
          DROP TABLE idempotency_records_legacy;`);
        this.db.prepare('INSERT OR REPLACE INTO schema_migrations(version, applied_at) VALUES(?, ?)').run(2, new Date().toISOString());
        version = 2;
      }
      if (version < 3) {
        const hasResourceKey = this.db.prepare('PRAGMA table_info(download_tasks)').all().some((column) => (column as { name?: string }).name === 'resource_key');
        if (!hasResourceKey) this.db.exec('ALTER TABLE download_tasks ADD COLUMN resource_key TEXT');
        this.db.exec("UPDATE download_tasks SET resource_key=source||':'||work_id||':'||chapter_id||':'||variant WHERE resource_key IS NULL; CREATE UNIQUE INDEX IF NOT EXISTS idx_download_tasks_resource_key ON download_tasks(resource_key);");
        this.db.prepare('INSERT OR REPLACE INTO schema_migrations(version, applied_at) VALUES(?, ?)').run(3, new Date().toISOString());
        version = 3;
      }
      if (version < 4) {
        this.db.exec('DROP TABLE IF EXISTS media_tokens');
        this.db.prepare('INSERT OR REPLACE INTO schema_migrations(version, applied_at) VALUES(?, ?)').run(4, new Date().toISOString());
        version = 4;
      }
      if (version < 5) {
        this.db.exec("ALTER TABLE works ADD COLUMN metadata_json TEXT NOT NULL DEFAULT '{}'");
        this.db.prepare('INSERT OR REPLACE INTO schema_migrations(version, applied_at) VALUES(?, ?)').run(5, new Date().toISOString());
      }
      if (version < 6) {
        for (const row of this.db.prepare('SELECT source,work_id FROM work_collections').all()) this.db.prepare('UPDATE work_collections SET resource_key=? WHERE source=? AND work_id=?').run(workCollectionResourceKey({source:String(row.source),id:String(row.work_id)}),row.source,row.work_id);
        for (const row of this.db.prepare('SELECT subscription_id,source,dimension,target FROM subscriptions').all()) this.db.prepare('UPDATE subscriptions SET resource_key=? WHERE subscription_id=?').run(subscriptionResourceKey(String(row.source),String(row.dimension),String(row.target)),row.subscription_id);
        for (const row of this.db.prepare('SELECT task_id,source,work_id,chapter_id,variant,resource_key FROM download_tasks').all()) {
          const key=downloadTaskId({source:String(row.source),workId:String(row.work_id),chapterId:String(row.chapter_id),variant:String(row.variant)}); const old=String(row.resource_key);
          this.db.prepare('UPDATE download_tasks SET resource_key=? WHERE task_id=?').run(key,row.task_id);
          this.db.prepare('UPDATE deletion_intents SET resource_key=? WHERE task_id=?').run(key,row.task_id);
          for (const file of this.db.prepare('SELECT id,resource_key FROM download_files WHERE task_id=?').all(row.task_id)) if(String(file.resource_key).startsWith(old)) this.db.prepare('UPDATE download_files SET resource_key=? WHERE id=?').run(key+String(file.resource_key).slice(old.length),file.id);
          const checkpoint=this.db.prepare('SELECT checkpoint_json FROM restore_checkpoints WHERE task_id=?').get(row.task_id);
          if(checkpoint){const value=JSON.parse(String(checkpoint.checkpoint_json));if(value.hashes && typeof value.hashes==='object')value.hashes=Object.fromEntries(Object.entries(value.hashes).map(([name,hash])=>[name.startsWith(old)?key+name.slice(old.length):name,hash]));this.db.prepare('UPDATE restore_checkpoints SET checkpoint_json=? WHERE task_id=?').run(JSON.stringify(value),row.task_id);}
        }
        for (const row of this.db.prepare('SELECT rowid,source,work_id,chapter_id FROM history').all()) this.db.prepare('UPDATE history SET scope_key=? WHERE rowid=?').run(JSON.stringify([row.source,row.work_id,row.chapter_id??null]),row.rowid);
        this.db.prepare('INSERT OR REPLACE INTO schema_migrations(version, applied_at) VALUES(?, ?)').run(6, new Date().toISOString());
      }
      if (version < 7) {
        this.db.exec('ALTER TABLE subscriptions ADD COLUMN deleted_at TEXT');
        this.db.prepare('INSERT OR REPLACE INTO schema_migrations(version, applied_at) VALUES(?, ?)').run(7,new Date().toISOString());
      }
      if(version<8){this.db.exec('ALTER TABLE chapters ADD COLUMN node_type TEXT');this.db.prepare('INSERT OR REPLACE INTO schema_migrations(version,applied_at) VALUES(?,?)').run(8,new Date().toISOString());}
      if(version<9){this.db.exec("ALTER TABLE chapters ADD COLUMN node_metadata_json TEXT NOT NULL DEFAULT '{}'");this.db.prepare('INSERT OR REPLACE INTO schema_migrations(version,applied_at) VALUES(?,?)').run(9,new Date().toISOString());}
      if(version<10){this.db.exec(`
        ALTER TABLE download_files ADD COLUMN metadata_json TEXT NOT NULL DEFAULT '{}';
        ALTER TABLE categories ADD COLUMN sort REAL NOT NULL DEFAULT 0;
        ALTER TABLE works ADD COLUMN content_updated_at TEXT;
        ALTER TABLE chapters ADD COLUMN text_offset INTEGER;
        CREATE TABLE novel_notes(id TEXT PRIMARY KEY,source TEXT NOT NULL,work_id TEXT NOT NULL,chapter_id TEXT NOT NULL,offset INTEGER NOT NULL,end_offset INTEGER NOT NULL,quote TEXT NOT NULL,note TEXT NOT NULL,bookmark INTEGER NOT NULL,updated_at TEXT NOT NULL,version INTEGER NOT NULL DEFAULT 1,FOREIGN KEY(source,work_id,chapter_id) REFERENCES chapters(source,work_id,chapter_id) ON DELETE CASCADE);
        CREATE TABLE tavern_assets(asset_id TEXT PRIMARY KEY,source TEXT NOT NULL,work_id TEXT NOT NULL,kind TEXT NOT NULL,format TEXT NOT NULL,data_json TEXT NOT NULL,updated_at TEXT NOT NULL,version INTEGER NOT NULL DEFAULT 1,UNIQUE(source,work_id));
        CREATE TABLE tavern_conversations(conversation_id TEXT PRIMARY KEY,asset_id TEXT NOT NULL REFERENCES tavern_assets(asset_id),messages_json TEXT NOT NULL,updated_at TEXT NOT NULL,version INTEGER NOT NULL DEFAULT 1);
        CREATE TABLE tag_translation_packs(source TEXT NOT NULL,locale TEXT NOT NULL,version TEXT NOT NULL,payload_json TEXT NOT NULL,updated_at TEXT NOT NULL,PRIMARY KEY(source,locale));
        CREATE TABLE subscription_scan_state(subscription_id TEXT PRIMARY KEY REFERENCES subscriptions(subscription_id) ON DELETE CASCADE,state_json TEXT NOT NULL);
        CREATE TABLE subscription_event_targets(event_id TEXT NOT NULL REFERENCES subscription_events(event_id) ON DELETE CASCADE,subscription_id TEXT NOT NULL REFERENCES subscriptions(subscription_id) ON DELETE CASCADE,PRIMARY KEY(event_id,subscription_id));
        CREATE TABLE persistent_read_states(event_id TEXT PRIMARY KEY REFERENCES domain_events(event_id) ON DELETE CASCADE,read_at TEXT NOT NULL);
        ALTER TABLE subscription_events ADD COLUMN content_key TEXT;
        CREATE UNIQUE INDEX idx_subscription_event_content ON subscription_events(content_key) WHERE content_key IS NOT NULL;
        INSERT INTO persistent_read_states SELECT event_id,MIN(read_at) FROM event_read_states GROUP BY event_id;
        DROP TABLE event_read_states;
        ALTER TABLE persistent_read_states RENAME TO event_read_states;
        INSERT OR IGNORE INTO subscription_event_targets SELECT event_id,subscription_id FROM subscription_events;
      `);this.db.prepare('INSERT OR REPLACE INTO schema_migrations(version,applied_at) VALUES(?,?)').run(10,new Date().toISOString());}
      if(version<11){this.db.exec(`ALTER TABLE download_tasks ADD COLUMN recording_json TEXT;
        CREATE TABLE reverse_search_history(id TEXT PRIMARY KEY,source TEXT NOT NULL,created_at TEXT NOT NULL,results_json TEXT NOT NULL);
      `);this.db.prepare('INSERT OR REPLACE INTO schema_migrations(version,applied_at) VALUES(?,?)').run(11,new Date().toISOString());}
      if(version<12){this.db.exec('ALTER TABLE reverse_search_history ADD COLUMN image_base64 TEXT;ALTER TABLE reverse_search_history ADD COLUMN mime_type TEXT;');this.db.prepare('INSERT OR REPLACE INTO schema_migrations(version,applied_at) VALUES(?,?)').run(12,new Date().toISOString());}
      if(version<13){this.db.exec("ALTER TABLE tavern_conversations ADD COLUMN settings_json TEXT NOT NULL DEFAULT '{}'");this.db.prepare('INSERT OR REPLACE INTO schema_migrations(version,applied_at) VALUES(?,?)').run(13,new Date().toISOString());}
      if(version<14){this.db.exec(`
        CREATE TABLE tavern_connections(connection_id TEXT PRIMARY KEY,endpoint TEXT NOT NULL,model TEXT NOT NULL,temperature REAL NOT NULL DEFAULT 0.8,max_tokens INTEGER NOT NULL DEFAULT 1024,context_tokens INTEGER NOT NULL DEFAULT 32768,secret_cipher TEXT NOT NULL DEFAULT '',key_endpoint TEXT NOT NULL DEFAULT '',updated_at TEXT NOT NULL,version INTEGER NOT NULL DEFAULT 1);
        CREATE TABLE worldbook_term_packs(locale TEXT PRIMARY KEY,pack_version TEXT NOT NULL,payload_json TEXT NOT NULL,updated_at TEXT NOT NULL,version INTEGER NOT NULL DEFAULT 1);
      `);this.db.prepare('INSERT OR REPLACE INTO schema_migrations(version,applied_at) VALUES(?,?)').run(14,new Date().toISOString());}
      this.db.exec(`PRAGMA user_version=${MIGRATION_VERSION}; COMMIT`);
    } catch (error) { this.db.exec('ROLLBACK'); throw error; }
  }
  close() { this.db.close(); }
  recoverPending() {
    return {
      tasks: this.db.prepare("SELECT * FROM download_tasks WHERE status IN ('queued','running','paused','failed','cancelling')").all(),
      deletionIntents: this.db.prepare("SELECT * FROM deletion_intents WHERE status='pending'").all()
    };
  }
}
