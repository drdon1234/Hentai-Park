import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:uuid/uuid.dart';

import '../core/models.dart';
import '../data/database.dart';
import 'models.dart';
import 'store.dart';

/// 酒馆资源包含原始文件；API 密钥与服务配置不进入备份。
Future<Map<String, dynamic>> exportTavernBackup(AppDatabase db) =>
    db.transaction(() async {
      final resources = await db
          .customSelect('SELECT * FROM tavern_resources')
          .get();
      final edits = await db
          .customSelect('SELECT * FROM tavern_edits ORDER BY saved_at DESC')
          .get();
      final sessions = await db
          .customSelect('SELECT data_json FROM tavern_sessions')
          .get();
      return {
        'resources': [
          for (final row in resources)
            {
              'item': jsonDecode(row.read<String>('item_json')),
              'kind': row.read<String>('kind'),
              'format': row.read<String>('format'),
              'original': base64Encode(row.read<Uint8List>('original')),
              'savedAt': row.read<int>('saved_at'),
            },
        ],
        'edits': [
          for (final row in edits)
            {
              'revision': row.read<String>('revision'),
              'uid': row.read<String>('uid'),
              'savedAt': row.read<int>('saved_at'),
              'content': jsonDecode(row.read<String>('content')),
            },
        ],
        'sessions': [
          for (final row in sessions) jsonDecode(row.read<String>('data_json')),
        ],
      };
    });

void validateTavernBackup(Object data) {
  if (data is! Map ||
      data['resources'] is! List ||
      data['sessions'] is! List ||
      (data['resources'] as List).length > 10000 ||
      (data['sessions'] as List).length > 10000) {
    throw const FormatException('备份数据无效');
  }
  final ids = <String>{};
  final kinds = <String, String>{};
  for (final value in data['resources'] as List) {
    if (value is! Map ||
        value['item'] is! Map ||
        value['kind'] is! String ||
        value['format'] is! String ||
        value['original'] is! String ||
        (value['original'] as String).length > 16 * 1024 * 1024 ||
        value['savedAt'] is! int ||
        (value['savedAt'] as int) < 0) {
      throw const FormatException('备份数据无效');
    }
    final item = WorkItem.fromStored(
      Map<String, dynamic>.from(value['item'] as Map),
    );
    if (item.source.isEmpty || item.id.isEmpty || !ids.add(item.uid)) {
      throw const FormatException('备份数据无效');
    }
    kinds[item.uid] = value['kind'] as String;
    try {
      TavernResource.parse(
        value['kind'] as String,
        value['format'] as String,
        base64Decode(value['original'] as String),
      );
    } catch (_) {
      throw const FormatException('备份数据无效');
    }
  }
  final edits = data['edits'] ?? [];
  if (edits is! List || edits.length > 80000) {
    throw const FormatException('备份数据无效');
  }
  for (final edit in edits) {
    if (edit is! Map ||
        !kinds.containsKey(edit['uid']) ||
        edit['savedAt'] is! int ||
        edit['revision'] is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(edit['revision'] as String) ||
        edit['content'] is! Map) {
      throw const FormatException('备份数据无效');
    }
    TavernResource.parse(
      kinds[edit['uid']]!,
      'json',
      Uint8List.fromList(utf8.encode(jsonEncode(edit['content']))),
    );
  }
  final sessionIds = <String>{};
  for (final value in data['sessions'] as List) {
    if (value is! Map) throw const FormatException('备份数据无效');
    final session = TavernSession.fromJson(value);
    if (session.id.isEmpty ||
        !sessionIds.add(session.id) ||
        kinds[session.resourceUid] != 'character' ||
        session.books.any((id) => kinds[id] != 'lorebook')) {
      throw const FormatException('备份数据无效');
    }
    try {
      TavernResource.parse(
        'character',
        'json',
        Uint8List.fromList(utf8.encode(jsonEncode(session.card))),
      );
    } catch (_) {
      throw const FormatException('备份数据无效');
    }
  }
}

/// 冲突时保留当前和备份的两份资源，并将备份会话指向对应副本。
Future<void> mergeTavernBackup(AppDatabase db, Object data) async {
  validateTavernBackup(data);
  final backup = data as Map;
  final remap = <String, String>{};
  for (final value in backup['resources'] as List) {
    final row = value as Map;
    var item = WorkItem.fromStored(
      Map<String, dynamic>.from(row['item'] as Map),
    );
    final oldUid = item.uid;
    final bytes = base64Decode(row['original'] as String);
    final resource = TavernResource.parse(
      row['kind'] as String,
      row['format'] as String,
      bytes,
    );
    final existing = await db
        .customSelect(
          'SELECT card_json,format,original FROM tavern_resources WHERE uid=?',
          variables: [Variable.withString(oldUid)],
        )
        .get();
    if (existing.isNotEmpty &&
        (existing.single.read<String>('card_json') !=
                jsonEncode(resource.raw) ||
            existing.single.read<String>('format') != row['format'] ||
            !listEquals(existing.single.read<Uint8List>('original'), bytes))) {
      item = WorkItem({
        ...item.toJson(),
        'id': 'local-${const Uuid().v4()}',
        'mediaKind': 'tavern',
      }, item.source);
    }
    remap[oldUid] = item.uid;
    await db.customStatement(
      '''INSERT OR IGNORE INTO tavern_resources
      (uid,item_json,kind,format,card_json,original,saved_at) VALUES(?,?,?,?,?,?,?)''',
      [
        item.uid,
        jsonEncode(item.toJson()),
        resource.kind,
        row['format'],
        jsonEncode(resource.raw),
        bytes,
        row['savedAt'],
      ],
    );
  }
  for (final edit in backup['edits'] as List? ?? const []) {
    await db.customStatement(
      'INSERT OR IGNORE INTO tavern_edits(revision,uid,saved_at,content) VALUES(?,?,?,?)',
      [
        remap[edit['uid']] == edit['uid']
            ? edit['revision']
            : const Uuid().v4().replaceAll('-', ''),
        remap[edit['uid']],
        edit['savedAt'],
        jsonEncode(edit['content']),
      ],
    );
  }
  final sessions = <String, Map<String, dynamic>>{};
  final ids = <String, String>{};
  final existingRows = await db
      .customSelect('SELECT id,data_json FROM tavern_sessions')
      .get();
  final existing = {
    for (final row in existingRows)
      row.read<String>('id'): row.read<String>('data_json'),
  };
  for (final value in backup['sessions'] as List) {
    final raw = Map<String, dynamic>.from(value as Map);
    final session = TavernSession.fromJson(raw);
    raw['resourceUid'] = remap[session.resourceUid];
    raw['books'] = [for (final book in session.books) remap[book]!];
    sessions[session.id] = raw;
    ids[session.id] = session.id;
  }
  // 若父分支因冲突需要新标识，同时重映射所有引用该分支的会话。
  final children = <String, List<String>>{};
  for (final entry in sessions.entries) {
    final parent = entry.value['parentId'];
    if (parent is String) (children[parent] ??= []).add(entry.key);
  }
  final pending = sessions.keys.toList();
  while (pending.isNotEmpty) {
    final id = pending.removeLast(), raw = sessions[id]!;
    if (ids[id] != id || !existing.containsKey(id)) continue;
    final parent = raw['parentId'];
    final compare = {
      ...raw,
      if (ids.containsKey(parent)) 'parentId': ids[parent],
    };
    if (existing[id] != jsonEncode(compare)) {
      ids[id] = const Uuid().v4();
      pending.addAll(children[id] ?? []);
    }
  }
  for (final entry in sessions.entries) {
    final raw = entry.value, parent = raw['parentId'];
    raw['id'] = ids[entry.key];
    if (ids.containsKey(parent)) raw['parentId'] = ids[parent];
    await db.customStatement(
      'INSERT OR IGNORE INTO tavern_sessions(id,resource_uid,data_json,updated_at) VALUES(?,?,?,?)',
      [raw['id'], raw['resourceUid'], jsonEncode(raw), raw['updatedAt']],
    );
  }
}
