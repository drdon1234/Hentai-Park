import 'package:drift/drift.dart';

/// 检查点、更新事件与通知队列必须在同一事务中保存。
Future<void> createSubscriptionTables(GeneratedDatabase db) async {
  for (final sql in [
    '''CREATE TABLE IF NOT EXISTS subscriptions (
      identity TEXT PRIMARY KEY, source TEXT NOT NULL, dimension TEXT NOT NULL,
      target TEXT NOT NULL, label TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1,
      notify INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL,
      UNIQUE(source,dimension,target))''',
    '''CREATE TABLE IF NOT EXISTS subscription_checks (
      identity TEXT PRIMARY KEY REFERENCES subscriptions(identity) ON DELETE CASCADE,
      baseline INTEGER NOT NULL DEFAULT 0, last_success INTEGER NOT NULL DEFAULT 0,
      next_due INTEGER NOT NULL DEFAULT 0, failures INTEGER NOT NULL DEFAULT 0,
      error_code TEXT NOT NULL DEFAULT '', progress TEXT NOT NULL DEFAULT '{}',
      context_hash TEXT NOT NULL DEFAULT '',
      seen_count INTEGER NOT NULL DEFAULT 0,
      lease_owner TEXT NOT NULL DEFAULT '', lease_until INTEGER NOT NULL DEFAULT 0)''',
    '''CREATE TABLE IF NOT EXISTS subscription_seen (
      identity TEXT NOT NULL REFERENCES subscriptions(identity) ON DELETE CASCADE,
      content_id TEXT NOT NULL, PRIMARY KEY(identity,content_id))''',
    '''CREATE TABLE IF NOT EXISTS subscription_events (
      event_key TEXT PRIMARY KEY, source TEXT NOT NULL, content_id TEXT NOT NULL,
      identity TEXT NOT NULL,
      title TEXT NOT NULL, route TEXT NOT NULL, created_at INTEGER NOT NULL,
      unread INTEGER NOT NULL DEFAULT 1, notify INTEGER NOT NULL DEFAULT 1,
      notification_id INTEGER NOT NULL, delivered INTEGER NOT NULL DEFAULT 0,
      attempts INTEGER NOT NULL DEFAULT 0, next_attempt INTEGER NOT NULL DEFAULT 0)''',
    'CREATE INDEX IF NOT EXISTS idx_subscription_events_pending ON subscription_events(delivered,next_attempt)',
    '''CREATE TABLE IF NOT EXISTS subscription_event_targets (
      event_key TEXT NOT NULL REFERENCES subscription_events(event_key) ON DELETE CASCADE,
      identity TEXT NOT NULL REFERENCES subscriptions(identity) ON DELETE CASCADE,
      PRIMARY KEY(event_key,identity))''',
    'CREATE TABLE IF NOT EXISTS subscription_meta (name TEXT PRIMARY KEY,value TEXT NOT NULL)',
  ]) {
    await db.customStatement(sql);
  }
}
