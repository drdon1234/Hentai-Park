import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../core/storage.dart';
import '../data/database.dart';
import 'subscription_store.dart';

class UpdateItem {
  const UpdateItem({
    required this.id,
    required this.title,
    this.workId = '',
    this.chapterId = '',
    this.kind = 'work',
  });
  final String id, title, workId, chapterId, kind;
  Map<String, String> toJson() => {
    'id': id,
    'title': title,
    'workId': workId,
    'chapterId': chapterId,
    'kind': kind,
  };
  factory UpdateItem.parse(Map value) {
    for (final key in ['id', 'title', 'workId', 'chapterId', 'kind']) {
      if (value[key] != null &&
          (value[key] is! String || (value[key] as String).length > 4096)) {
        throw const FormatException('订阅更新结果无效');
      }
    }
    if (value['id'] is! String ||
        (value['id'] as String).isEmpty ||
        !{'work', 'post', 'chapter'}.contains(value['kind'] ?? 'work')) {
      throw const FormatException('订阅更新结果无效');
    }
    return UpdateItem(
      id: value['id'],
      title: value['title'] ?? '',
      workId: value['workId'] ?? '',
      chapterId: value['chapterId'] ?? '',
      kind: value['kind'] ?? 'work',
    );
  }
}

class UpdateState {
  const UpdateState({
    this.baseline = false,
    this.cursor,
    this.pending = const [],
    this.error = '',
    this.lastSuccess = 0,
  });
  final bool baseline;
  final String? cursor;
  final List<UpdateItem> pending;
  final String error;
  final int lastSuccess;
}

class SubscriptionEvent {
  SubscriptionEvent(QueryRow row)
    : key = row.read<String>('event_key'),
      source = row.read<String>('source'),
      contentId = row.read<String>('content_id'),
      identity = row.read<String>('identity'),
      title = row.read<String>('title'),
      route = UpdateItem.parse(jsonDecode(row.read<String>('route')) as Map),
      unread = row.read<int>('unread') == 1,
      notificationId = row.read<int>('notification_id'),
      createdAt = row.read<int>('created_at');
  final String key, source, contentId, identity, title;
  final UpdateItem route;
  final bool unread;
  final int notificationId, createdAt;
}

class UpdateStore {
  UpdateStore(this.db);
  final AppDatabase db;
  Future<UpdateState> state(SubscriptionEntry entry) async {
    final row = await db
        .customSelect(
          'SELECT * FROM subscription_checks WHERE identity=?',
          variables: [Variable(entry.identity)],
        )
        .getSingleOrNull();
    if (row == null) return const UpdateState();
    final progress = jsonDecode(row.read<String>('progress')) as Map;
    return UpdateState(
      baseline: row.read<int>('baseline') == 1,
      cursor: progress['cursor'] as String?,
      pending: (progress['items'] as List? ?? [])
          .whereType<Map>()
          .map(UpdateItem.parse)
          .toList(),
      error: row.read<String>('error_code'),
      lastSuccess: row.read<int>('last_success'),
    );
  }

  Future<String?> acquire(
    SubscriptionEntry entry, {
    required int now,
    bool force = false,
  }) => db.transaction(() async {
    final token = const Uuid().v4();
    final changed = await db.customUpdate(
      '''UPDATE subscription_checks SET lease_owner=?,lease_until=?
      WHERE identity=? AND lease_until<=? AND (? OR next_due<=?)
      AND EXISTS(SELECT 1 FROM subscriptions WHERE identity=? AND enabled=1)''',
      variables: [
        Variable(token),
        Variable(now + 300000),
        Variable(entry.identity),
        Variable(now),
        Variable(force ? 1 : 0),
        Variable(now),
        Variable(entry.identity),
      ],
    );
    return changed == 1 ? token : null;
  });

  Future<Set<String>> seen(SubscriptionEntry e) async => {
    for (final row
        in await db
            .customSelect(
              'SELECT content_id FROM subscription_seen WHERE identity=?',
              variables: [Variable(e.identity)],
            )
            .get())
      row.read<String>('content_id'),
  };

  Future<void> ensureContext(
    SubscriptionEntry entry,
    String lease,
    String fingerprint,
  ) => db.transaction(() async {
    final row = await db
        .customSelect(
          'SELECT context_hash,baseline FROM subscription_checks WHERE identity=? AND lease_owner=?',
          variables: [Variable(entry.identity), Variable(lease)],
        )
        .getSingleOrNull();
    if (row == null || row.read<String>('context_hash') == fingerprint) return;
    // 源版本或账号发生变化，重新建立基线；已读记录与旧事件仍完整保存。
    await db.customStatement(
      "UPDATE subscription_checks SET context_hash=?,baseline=0,progress='{}' WHERE identity=? AND lease_owner=?",
      [fingerprint, entry.identity, lease],
    );
  });

  Future<void> commit(
    SubscriptionEntry entry,
    String lease,
    List<UpdateItem> items, {
    required int now,
    required bool complete,
    String? cursor,
    int intervalHours = 6,
  }) => db.transaction(() async {
    final owner = await db
        .customSelect(
          '''SELECT c.baseline,c.seen_count,s.notify FROM subscription_checks c JOIN subscriptions s USING(identity)
      WHERE c.identity=? AND c.lease_owner=? AND c.lease_until>=? AND s.enabled=1''',
          variables: [Variable(entry.identity), Variable(lease), Variable(now)],
        )
        .getSingleOrNull();
    if (owner == null) return;
    final current = await state(entry);
    final merged = {
      for (final item in [...current.pending, ...items]) item.id: item,
    };
    if (merged.length > 20000) throw const FormatException('订阅检查结果过大');
    if (!complete) {
      if (cursor == null ||
          cursor.isEmpty ||
          cursor.length > 4096 ||
          merged.length > 20000) {
        throw const FormatException('订阅检查分页无效');
      }
      await db.customStatement(
        'UPDATE subscription_checks SET progress=?,next_due=?,lease_owner=?,lease_until=0 WHERE identity=?',
        [
          jsonEncode({
            'cursor': cursor,
            'items': merged.values.map((e) => e.toJson()).toList(),
          }),
          now + 60000,
          '',
          entry.identity,
        ],
      );
      return;
    }
    final previous = await seen(entry);
    final baseline =
        owner.read<int>('baseline') == 1 &&
        previous.length == owner.read<int>('seen_count');
    for (final item in merged.values) {
      if (previous.contains(item.id)) continue;
      await db.customStatement(
        'INSERT OR IGNORE INTO subscription_seen(identity,content_id) VALUES(?,?)',
        [entry.identity, item.id],
      );
      if (!baseline) continue;
      final key = safeFileName(jsonEncode([entry.source, item.kind, item.id]));
      final notificationId =
          (int.parse(key.substring(0, 7), radix: 16) + 20000) & 0x7fffffff;
      await db.customStatement(
        '''INSERT OR IGNORE INTO subscription_events
        (event_key,source,content_id,identity,title,route,created_at,notification_id,notify) VALUES(?,?,?,?,?,?,?,?,?)''',
        [
          key,
          entry.source,
          item.id,
          entry.identity,
          item.title,
          jsonEncode(item.toJson()),
          now,
          notificationId,
          owner.read<int>('notify'),
        ],
      );
      await db.customStatement(
        'INSERT OR IGNORE INTO subscription_event_targets(event_key,identity) VALUES(?,?)',
        [key, entry.identity],
      );
      if (owner.read<int>('notify') == 1) {
        await db.customStatement(
          'UPDATE subscription_events SET notify=1 WHERE event_key=?',
          [key],
        );
      }
    }
    await db.customStatement(
      "UPDATE subscription_checks SET baseline=1,seen_count=(SELECT COUNT(*) FROM subscription_seen WHERE identity=?),last_success=?,next_due=?,failures=0,error_code='',progress='{}',lease_owner='',lease_until=0 WHERE identity=?",
      [entry.identity, now, now + intervalHours * 3600000, entry.identity],
    );
  });

  Future<void> fail(
    SubscriptionEntry entry,
    String lease, {
    required int now,
    required String code,
  }) => db.transaction(() async {
    const safe = {
      'NETWORK',
      'HTTP',
      'PARSE',
      'LOGIN_REQUIRED',
      'BLOCKED',
      'CLOUDFLARE',
      'CONFIG',
      'UNSUPPORTED',
      'CANCELLED',
      'NOT_FOUND',
    };
    final row = await db
        .customSelect(
          'SELECT failures FROM subscription_checks WHERE identity=? AND lease_owner=?',
          variables: [Variable(entry.identity), Variable(lease)],
        )
        .getSingleOrNull();
    if (row == null) return;
    final failures = row.read<int>('failures') + 1;
    final delay = (60000 * (1 << failures.clamp(0, 8))).clamp(60000, 86400000);
    await db.customStatement(
      'UPDATE subscription_checks SET failures=?,error_code=?,next_due=?,lease_owner=?,lease_until=0 WHERE identity=? AND lease_owner=?',
      [
        failures,
        safe.contains(code) ? code : 'NETWORK',
        now + delay,
        '',
        entry.identity,
        lease,
      ],
    );
  });

  Future<List<SubscriptionEvent>> events({
    bool pending = false,
    int now = 0,
  }) async =>
      (await db
              .customSelect(
                'SELECT * FROM subscription_events ${pending ? 'WHERE delivered=0 AND notify=1 AND next_attempt<=? AND EXISTS(SELECT 1 FROM subscription_event_targets t JOIN subscriptions s USING(identity) WHERE t.event_key=subscription_events.event_key AND s.enabled=1 AND s.notify=1)' : ''} ORDER BY created_at DESC,event_key LIMIT 500',
                variables: pending ? [Variable(now)] : [],
              )
              .get())
          .map(SubscriptionEvent.new)
          .toList();
  Future<void> markRead(String key) => db.customStatement(
    'UPDATE subscription_events SET unread=0 WHERE event_key=?',
    [key],
  );
  Future<void> delivered(String key) => db.customStatement(
    'UPDATE subscription_events SET delivered=1 WHERE event_key=?',
    [key],
  );
  Future<void> retryDelivery(String key, int now) => db.customStatement(
    'UPDATE subscription_events SET attempts=attempts+1,next_attempt=? WHERE event_key=?',
    [now + 300000, key],
  );
}
