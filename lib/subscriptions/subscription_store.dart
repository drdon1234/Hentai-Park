import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' show Variable;

import '../core/async_tasks.dart';
import '../core/storage.dart';
import '../data/database.dart';
import '../engine/source_identity.dart';
import '../library/library.dart';

class SubscriptionEntry {
  const SubscriptionEntry({
    required this.source,
    required this.target,
    required this.label,
    this.dimension = 'posts',
    this.enabled = true,
    this.notify = true,
  });
  final String source, target, label, dimension;
  final bool enabled, notify;
  String get identity => safeFileName(jsonEncode([source, dimension, target]));
  Map<String, Object> toJson() => {
    'source': source,
    'target': target,
    'label': label,
    'dimension': dimension,
    'enabled': enabled,
    'notify': notify,
  };
}

/// 旧 JSON 只导入一次并保留原文件，不再双写旧格式。
class SubscriptionStore extends ChangeNotifier {
  // 公开 database 参数允许测试隔离数据库，不暴露私有字段命名。
  // ignore: prefer_initializing_formals
  SubscriptionStore({AppDatabase? database}) : _database = database;
  static final instance = SubscriptionStore();
  final AppDatabase? _database;
  AppDatabase get database => _database ?? Library.instance.db;
  final _writes = SerialExecutor();
  List<SubscriptionEntry> _items = [];
  bool loaded = false;
  List<SubscriptionEntry> get items => List.unmodifiable(_items);
  Future<void> reload() => _writes.run(() async {
    loaded = false;
    await _load();
  });
  Future<void> load() => _writes.run(_load);

  static List<SubscriptionEntry> parse(Object? data) {
    if (data is! Map ||
        data['items'] is! List ||
        (data['items'] as List).length > 10000) {
      throw const FormatException('订阅记录格式无效');
    }
    final unique = <String, SubscriptionEntry>{};
    for (final value in data['items']) {
      if (value is! Map ||
          !isSourceKey(value['source']) ||
          value['target'] is! String ||
          (value['target'] as String).trim().isEmpty ||
          (value['target'] as String).length > 2048 ||
          (value['target'] as String).contains('\u0000') ||
          (value['label'] != null &&
              (value['label'] is! String ||
                  (value['label'] as String).length > 512)) ||
          (value['dimension'] != null &&
              (value['dimension'] is! String ||
                  !RegExp(r'^[a-z][a-z0-9_]{0,31}$')
                      .hasMatch(value['dimension']))) ||
          (value['enabled'] != null && value['enabled'] is! bool) ||
          (value['notify'] != null && value['notify'] is! bool)) {
        throw const FormatException('订阅记录格式无效');
      }
      final e = SubscriptionEntry(
        source: value['source'],
        target: (value['target'] as String).trim(),
        label: value['label'] ?? value['target'],
        dimension: value['dimension'] ?? 'posts',
        enabled: value['enabled'] != false,
        notify: value['notify'] != false,
      );
      unique[e.identity] = e;
    }
    return unique.values.toList();
  }

  Map<String, dynamic> exportJson() => {
    'items': _items.map((e) => e.toJson()).toList(),
  };
  Map<String, dynamic> prepareMerge(Object data) {
    final next = {for (final e in _items) e.identity: e};
    for (final e in parse(data)) {
      next.putIfAbsent(e.identity, () => e);
    }
    return {'items': next.values.map((e) => e.toJson()).toList()};
  }

  Future<void> _load() async {
    if (loaded) return;
    final marker = await database
        .customSelect(
          "SELECT value FROM subscription_meta WHERE name='json_import'",
        )
        .get();
    if (marker.isEmpty) {
      final file = AppPaths.dataFile('subscriptions.json');
      final legacy = await file.exists()
          ? parse(jsonDecode(await file.readAsString()))
          : <SubscriptionEntry>[];
      if (legacy.isNotEmpty) {
        final snapshot = AppPaths.dataFile('subscriptions.json.pre-migration');
        if (!await snapshot.exists()) await file.copy(snapshot.path);
      }
      await database.transaction(() async {
        for (final entry in legacy) {
          await insert(entry, keepExisting: true);
        }
        await database.customStatement(
          "INSERT OR IGNORE INTO subscription_meta(name,value) VALUES('json_import','complete')",
        );
      });
    }
    final rows = await database
        .customSelect(
          'SELECT * FROM subscriptions ORDER BY created_at,identity',
        )
        .get();
    _items = [
      for (final row in rows)
        SubscriptionEntry(
          source: row.read<String>('source'),
          target: row.read<String>('target'),
          label: row.read<String>('label'),
          dimension: row.read<String>('dimension'),
          enabled: row.read<int>('enabled') == 1,
          notify: row.read<int>('notify') == 1,
        ),
    ];
    loaded = true;
    notifyListeners();
  }

  Future<void> insert(SubscriptionEntry e, {bool keepExisting = false}) async {
    await database.customStatement(
      'INSERT ${keepExisting ? 'OR IGNORE ' : ''}INTO subscriptions(identity,source,dimension,target,label,enabled,notify,created_at) VALUES(?,?,?,?,?,?,?,?)'
      '${keepExisting ? '' : ' ON CONFLICT(identity) DO UPDATE SET label=excluded.label,enabled=excluded.enabled,notify=excluded.notify'}',
      [
        e.identity,
        e.source,
        e.dimension,
        e.target,
        e.label,
        e.enabled ? 1 : 0,
        e.notify ? 1 : 0,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
    await database.customStatement(
      'INSERT OR IGNORE INTO subscription_checks(identity) VALUES(?)',
      [e.identity],
    );
    if (!keepExisting) {
      await database.customStatement(
        "UPDATE subscription_checks SET lease_owner='',lease_until=0 WHERE identity=?",
        [e.identity],
      );
    }
  }

  /// 恢复事务中的新增目标建立新基线，已存在目标保持名称与状态。
  Future<void> merge(Object data) async {
    for (final e in parse(data)) {
      await insert(e, keepExisting: true);
    }
  }

  Future<void> add({
    required String source,
    required String target,
    required String label,
    String dimension = 'posts',
    bool enabled = true,
    bool notify = true,
  }) {
    final e = parse({
      'items': [
        {
          'source': source,
          'target': target,
          'label': label.trim().isEmpty ? target : label.trim(),
          'dimension': dimension,
          'enabled': enabled,
          'notify': notify,
        },
      ],
    }).single;
    return _writes.run(() async {
      if (!loaded) throw StateError('订阅记录尚未读取');
      await database.transaction(() => insert(e));
      loaded = false;
      await _load();
    });
  }

  Future<void> remove(
    String source,
    String target, {
    String dimension = 'posts',
  }) => _writes.run(() async {
    if (!loaded) throw StateError('订阅记录尚未读取');
    await database.transaction(() async {
      final identity = SubscriptionEntry(
        source: source,
        target: target,
        label: '',
        dimension: dimension,
      ).identity;
      await database.customStatement(
        'DELETE FROM subscriptions WHERE identity=?',
        [identity],
      );
    });
    loaded = false;
    await _load();
  });

  /// 同目标仅改备注；纠正目标时原子替换并为新目标建立独立基线。
  Future<void> edit(
    SubscriptionEntry original, {
    required String target,
    required String label,
  }) => _writes.run(() async {
    if (!loaded) throw StateError('订阅记录尚未读取');
    await database.transaction(() async {
      final current = await database
          .customSelect(
            'SELECT * FROM subscriptions WHERE identity=?',
            variables: [Variable(original.identity)],
          )
          .getSingleOrNull();
      if (current == null) throw const FormatException('订阅已移除，请刷新列表');
      final next = parse({
        'items': [
          {
            ...original.toJson(),
            'target': target,
            'label': label.trim().isEmpty ? target.trim() : label.trim(),
            'enabled': current.read<int>('enabled') == 1,
            'notify': current.read<int>('notify') == 1,
          },
        ],
      }).single;
      if (next.identity == original.identity) {
        await database.customStatement(
          'UPDATE subscriptions SET label=? WHERE identity=?',
          [next.label, original.identity],
        );
      } else {
        final duplicate = await database
            .customSelect(
              'SELECT identity FROM subscriptions WHERE identity=?',
              variables: [Variable(next.identity)],
            )
            .getSingleOrNull();
        if (duplicate != null) {
          throw const FormatException('该订阅目标已存在');
        }
        await database.customStatement(
          'DELETE FROM subscriptions WHERE identity=?',
          [original.identity],
        );
        await insert(next);
        await database.customStatement(
          'UPDATE subscriptions SET created_at=? WHERE identity=?',
          [current.read<int>('created_at'), next.identity],
        );
      }
    });
    loaded = false;
    await _load();
  });
}
