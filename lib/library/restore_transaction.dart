import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../core/storage.dart';
import '../data/database.dart';
import '../engine/cookie_store.dart';
import '../engine/source_identity.dart';

/// 只暂存本次受影响的 JSON 文件。数据库中的提交标记决定重启时回滚还是完成。
class RestoreTransaction {
  static File get _journal => AppPaths.dataFile('backup_restore.json');
  static bool _allowed(String name) =>
      {
        'settings.json',
        'reading_notes.json',
        'subscriptions.json',
        'sources.json',
      }.contains(name) ||
      (name.startsWith('source_state_') &&
          name.endsWith('.json') &&
          isSourceKey(name.substring(13, name.length - 5)));

  static Future<void> recover(AppDatabase db) async {
    if (!await _journal.exists()) return;
    final data = jsonDecode(await _journal.readAsString());
    if (data is! Map ||
        data['token'] is! String ||
        data['before'] is! Map ||
        data['after'] is! Map) {
      throw const FormatException('恢复记录无效');
    }
    final before = data['before'] as Map, after = data['after'] as Map;
    if ((data['token'] as String).isEmpty ||
        before.length != after.length ||
        before.keys.any((key) => !after.containsKey(key))) {
      throw const FormatException('恢复记录无效');
    }
    // 先验证全部路径与字节，损坏的恢复日志不得导致任意部分删除。
    Map<String, List<int>?> decodeFiles(Map files) {
      final decoded = <String, List<int>?>{};
      for (final e in files.entries) {
        if (e.key is! String ||
            !_allowed(e.key) ||
            (e.value != null && e.value is! String)) {
          throw const FormatException('恢复记录无效');
        }
        decoded[e.key] = e.value == null ? null : base64Decode(e.value);
      }
      return decoded;
    }

    final oldFiles = decodeFiles(before), newFiles = decodeFiles(after);
    final cookies = _decodeCookies(data['cookies']);
    final marker = await (db.select(
      db.restoreCheckpoints,
    )..where((t) => t.id.equals(1))).getSingleOrNull();
    final decoded = marker?.token == data['token'] ? newFiles : oldFiles;
    for (final entry in cookies.entries) {
      await CookieStore.instance.restorePartition(
        entry.key,
        marker?.token == data['token'] ? entry.value.after : entry.value.before,
        domains: entry.value.domains,
        browserSnapshot: marker?.token == data['token']
            ? entry.value.before
            : entry.value.after,
      );
    }
    for (final e in decoded.entries) {
      final file = AppPaths.dataFile(e.key);
      if (e.value == null) {
        if (await file.exists()) await file.delete();
      } else {
        await writeFileAtomic(file, e.value!);
      }
    }
    await _journal.delete();
  }

  static Future<void> apply(
    AppDatabase db,
    Map<String, Object?> files,
    Future<void> Function() updateDatabase, {
    Map<String, ({Map<String, String> snapshot, List<String> domains})>
        cookies =
        const {},
  }) async {
    await recover(db);
    for (final entry in cookies.entries) {
      if (!isSourceKey(entry.key)) throw const FormatException('备份数据无效');
      CookieStore.validateSnapshot(
        entry.value.snapshot,
        domains: entry.value.domains,
      );
    }
    final before = <String, String?>{}, after = <String, String>{};
    for (final e in files.entries) {
      if (!_allowed(e.key)) throw const FormatException('恢复记录无效');
      final file = AppPaths.dataFile(e.key);
      before[e.key] = await file.exists()
          ? base64Encode(await file.readAsBytes())
          : null;
      after[e.key] = base64Encode(utf8.encode(jsonEncode(e.value)));
    }
    final token = const Uuid().v4();
    final cookieJournal = <String, Object?>{
      for (final entry in cookies.entries)
        entry.key: {
          'before': await CookieStore.instance.snapshotPartition(entry.key),
          'after': entry.value.snapshot,
          'domains': entry.value.domains,
        },
    };
    await writeFileAtomic(
      _journal,
      utf8.encode(
        jsonEncode({
          'token': token,
          'before': before,
          'after': after,
          'cookies': cookieJournal,
        }),
      ),
    );
    try {
      await db.transaction(() async {
        for (final entry in cookies.entries) {
          await CookieStore.instance.restorePartition(
            entry.key,
            entry.value.snapshot,
            domains: entry.value.domains,
            browserSnapshot: const {},
          );
        }
        for (final e in after.entries) {
          await writeFileAtomic(
            AppPaths.dataFile(e.key),
            base64Decode(e.value),
          );
        }
        await updateDatabase();
        await db
            .into(db.restoreCheckpoints)
            .insertOnConflictUpdate(
              RestoreCheckpointsCompanion.insert(
                id: const Value(1),
                token: token,
              ),
            );
      });
    } catch (_) {
      await recover(db);
      rethrow;
    }
    // 提交成功时 JSON 已就位；不要为了清理日志再次写文件，制造提交后的假失败。
    // 删除失败只留下可在下次启动补齐的日志，不撤销已完成的恢复。
    try {
      await _journal.delete();
    } on FileSystemException {
      // 下次启动或恢复前处理。
    }
  }

  static Map<
    String,
    ({
      Map<String, String> before,
      Map<String, String> after,
      List<String> domains,
    })
  >
  _decodeCookies(Object? value) {
    if (value == null) return {};
    if (value is! Map) throw const FormatException('恢复记录无效');
    return value.map((key, raw) {
      if (!isSourceKey(key) ||
          raw is! Map ||
          raw['domains'] is! List ||
          (raw['domains'] as List).any((domain) => domain is! String)) {
        throw const FormatException('恢复记录无效');
      }
      // 回滚快照可能包含站点更新前的域名，仅还原原生分区；浏览器仍受当前权限约束。
      CookieStore.validateSnapshot(raw['before']);
      CookieStore.validateSnapshot(raw['after']);
      return MapEntry(key as String, (
        before: (raw['before'] as Map).cast<String, String>(),
        after: (raw['after'] as Map).cast<String, String>(),
        domains: (raw['domains'] as List).cast<String>(),
      ));
    });
  }
}
