import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../core/localization.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../core/storage.dart';
import '../data/database.dart';
import '../library/library.dart';
import 'models.dart';

class SavedTavernResource {
  SavedTavernResource({
    required this.item,
    required this.resource,
    required this.format,
    required this.bytes,
  });
  final WorkItem item;
  final TavernResource resource;
  final String format;
  final Uint8List bytes;
}

class TavernSession {
  TavernSession({
    required this.id,
    required this.resourceUid,
    required this.title,
    required this.card,
    required this.messages,
    required this.books,
    required this.updatedAt,
    this.userName = 'User',
    this.persona = '',
    this.memory = '',
    this.notes = '',
    this.tags = '',
    this.speaker = '',
    Map<String, Map<String, dynamic>>? cast,
    this.inputDraft = '',
    this.parentId,
    this.pendingReply,
    Map<String, List<Map<String, String>>>? alternatives,
  }) : cast = cast ?? {},
       alternatives = alternatives ?? {};
  final String id;
  static const workSource = 'tavern-session';
  WorkItem get work => WorkItem({
    'id': id,
    'title': title,
    'contentDomain': 'tavern',
    'mediaKind': 'tavern',
  }, workSource);

  final String resourceUid;
  String title;
  final Map<String, dynamic> card;
  final List<Map<String, String>> messages;
  final List<String> books;
  int updatedAt;
  String userName;
  String persona;
  String memory;
  String notes;
  String tags;
  String speaker;
  final Map<String, Map<String, dynamic>> cast;
  Map<String, dynamic> get speakingCard => cast[speaker] ?? card;
  String inputDraft;
  String? parentId;
  Map<String, String>? pendingReply;
  final Map<String, List<Map<String, String>>> alternatives;

  Map<String, dynamic> toJson() => {
    'id': id,
    'resourceUid': resourceUid,
    'title': title,
    'card': card,
    'messages': messages,
    'books': books,
    'updatedAt': updatedAt,
    'userName': userName,
    'persona': persona,
    if (notes.isNotEmpty) 'notes': notes,
    if (tags.isNotEmpty) 'tags': tags,
    if (memory.isNotEmpty) 'memory': memory,
    if (cast.isNotEmpty) 'cast': cast,
    if (speaker.isNotEmpty) 'speaker': speaker,
    'inputDraft': inputDraft,
    if (parentId != null) 'parentId': parentId,
    if (pendingReply != null) 'pendingReply': pendingReply,
    'alternatives': alternatives,
  };

  factory TavernSession.fromJson(Map value) {
    if (value['id'] is! String ||
        value['resourceUid'] is! String ||
        value['title'] is! String ||
        value['card'] is! Map ||
        value['messages'] is! List ||
        value['books'] is! List ||
        value['updatedAt'] is! int) {
      throw const FormatException('酒馆会话格式无效');
    }
    final messages = <Map<String, String>>[];
    for (final message in value['messages'] as List) {
      if (message is! Map ||
          !{'user', 'assistant'}.contains(message['role']) ||
          message['content'] is! String) {
        throw const FormatException('酒馆会话格式无效');
      }
      messages.add({
        'role': message['role'] as String,
        'content': message['content'] as String,
        if (message['name'] is String) 'name': message['name'] as String,
        if (message['status'] is String) 'status': message['status'] as String,
      });
    }
    if ((value['books'] as List).any((book) => book is! String)) {
      throw const FormatException('酒馆会话格式无效');
    }
    if (value['alternatives'] case final Map alternatives) {
      for (final entry in alternatives.entries) {
        final index = int.tryParse(entry.key.toString());
        if (index == null ||
            index < 0 ||
            index >= messages.length ||
            entry.value is! List) {
          throw const FormatException('酒馆会话格式无效');
        }
        for (final message in entry.value as List) {
          if (message is! Map ||
              message['role'] != 'assistant' ||
              message['content'] is! String ||
              message.values.any((value) => value is! String)) {
            throw const FormatException('酒馆会话格式无效');
          }
        }
      }
    } else if (value['alternatives'] != null) {
      throw const FormatException('酒馆会话格式无效');
    }
    final cast = <String, Map<String, dynamic>>{};
    final members = value['cast'];
    if (members != null) {
      if (members is! Map || members.length > 20) {
        throw const FormatException('酒馆会话格式无效');
      }
      for (final entry in members.entries) {
        if (entry.key is! String || entry.value is! Map) {
          throw const FormatException('酒馆会话格式无效');
        }
        cast[entry.key as String] = Map<String, dynamic>.from(
          entry.value as Map,
        );
      }
    }
    return TavernSession(
      id: value['id'] as String,
      resourceUid: value['resourceUid'] as String,
      title: value['title'] as String,
      card: Map<String, dynamic>.from(value['card'] as Map),
      messages: messages,
      books: (value['books'] as List).cast<String>().toList(),
      updatedAt: value['updatedAt'] as int,
      userName: value['userName'] is String
          ? value['userName'] as String
          : 'User',
      cast: cast,
      speaker: value['speaker'] as String? ?? '',
      notes: value['notes'] is String ? value['notes'] as String : '',
      tags: value['tags'] is String ? value['tags'] as String : '',
      memory: value['memory'] is String ? value['memory'] as String : '',
      persona: value['persona'] is String ? value['persona'] as String : '',
      inputDraft: value['inputDraft'] is String
          ? value['inputDraft'] as String
          : '',
      parentId: value['parentId'] is String
          ? value['parentId'] as String
          : null,
      pendingReply:
          value['pendingReply'] is Map &&
              (value['pendingReply'] as Map).values.every((v) => v is String)
          ? Map<String, String>.from(value['pendingReply'] as Map)
          : null,
      alternatives: value['alternatives'] is Map
          ? {
              for (final entry in (value['alternatives'] as Map).entries)
                entry.key.toString(): [
                  for (final message in entry.value as List)
                    Map<String, String>.from(message as Map),
                ],
            }
          : {},
    );
  }
}

/// 保存资源及聊天使用 SQLite 事务，原始 PNG/JSON 与结构化数据一起保留。
class TavernStore extends ChangeNotifier {
  TavernStore._();
  static final TavernStore instance = TavernStore._();
  AppDatabase get _db => Library.instance.db;
  Future<(Map<String, dynamic>, Uint8List?)?> readDraft(String id) async {
    final row = await _db
        .customSelect(
          'SELECT content,portrait FROM tavern_drafts WHERE id=?',
          variables: [Variable.withString(id)],
        )
        .getSingleOrNull();
    return row == null
        ? null
        : (
            jsonDecode(row.read<String>('content')) as Map<String, dynamic>,
            row.readNullable<Uint8List>('portrait'),
          );
  }

  Future<void> writeDraft(
    String id,
    String content,
    Uint8List? portrait,
  ) => _db.customStatement(
    'INSERT OR REPLACE INTO tavern_drafts(id,content,portrait) VALUES(?,?,?)',
    [id, content, portrait],
  );

  Future<void> clearDraft(String id) =>
      _db.customStatement('DELETE FROM tavern_drafts WHERE id=?', [id]);

  void restored() => notifyListeners();

  Future<void> save(
    WorkItem item,
    TavernResource resource,
    String format,
    Uint8List bytes,
  ) async {
    if (bytes.isEmpty || bytes.length > 12 * 1024 * 1024) {
      throw const FormatException('酒馆资源格式无效');
    }
    await _db.customStatement(
      '''INSERT INTO tavern_resources(uid,item_json,kind,format,card_json,original,saved_at)
      VALUES(?,?,?,?,?,?,?) ON CONFLICT(uid) DO UPDATE SET item_json=excluded.item_json,
      kind=excluded.kind,format=excluded.format,card_json=excluded.card_json,
      original=excluded.original,saved_at=excluded.saved_at''',
      [
        item.uid,
        jsonEncode(item.toJson()),
        resource.kind,
        format,
        jsonEncode(resource.raw),
        bytes,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
    notifyListeners();
  }

  /// 保留卡片容器与扩展数据，重新解析成功后才写入书库。
  Future<void> updateResource(
    SavedTavernResource saved,
    TavernResource resource, {
    String? title,
    String? draftId,
  }) async {
    final item = title == null || title.trim().isEmpty
        ? saved.item
        : WorkItem({
            ...saved.item.json,
            'title': title.trim(),
            if (resource.data['tags'] is List) 'tags': resource.data['tags'],
          }, saved.item.source);
    final bytes = saved.format == 'png'
        ? writeTavernPng(saved.bytes, resource.raw)
        : Uint8List.fromList(utf8.encode(jsonEncode(resource.raw)));
    final parsed = TavernResource.parse(resource.kind, saved.format, bytes);
    await _db.transaction(() async {
      await save(item, parsed, saved.format, bytes);
      if (draftId != null) await clearDraft(draftId);
    });
  }

  Future<SavedTavernResource?> get(String uid) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM tavern_resources WHERE uid=?',
          variables: [Variable.withString(uid)],
        )
        .get();
    if (rows.isEmpty) return null;
    final row = rows.single;
    final item = jsonDecode(row.read<String>('item_json'));
    final card = jsonDecode(row.read<String>('card_json'));
    if (item is! Map || card is! Map) throw const FormatException('酒馆资源格式无效');
    return SavedTavernResource(
      item: WorkItem.fromStored(Map<String, dynamic>.from(item)),
      resource: TavernResource(
        kind: row.read<String>('kind'),
        raw: Map<String, dynamic>.from(card),
      ),
      format: row.read<String>('format'),
      bytes: row.read<Uint8List>('original'),
    );
  }

  Future<List<(int, Map<String, dynamic>)>> revisions(String uid) async {
    final rows = await _db
        .customSelect(
          'SELECT saved_at,content FROM tavern_edits WHERE uid=? ORDER BY saved_at DESC,rowid DESC LIMIT 8',
          variables: [Variable.withString(uid)],
        )
        .get();
    return [
      for (final row in rows)
        (
          row.read<int>('saved_at'),
          jsonDecode(row.read<String>('content')) as Map<String, dynamic>,
        ),
    ];
  }

  Future<void> pinResource(String uid, bool pinned) async {
    await _db.customStatement(
      "UPDATE tavern_resources SET item_json=json_set(item_json,'\$.tavernPinned',?) WHERE uid=?",
      [pinned ? 1 : 0, uid],
    );
    notifyListeners();
  }

  Future<List<WorkItem>> resources({String? kind}) async {
    const columns =
        r"SELECT item_json, CASE WHEN json_type(card_json,'$.data.tags')='array' THEN json_extract(card_json,'$.data.tags') WHEN json_type(card_json,'$.tags')='array' THEN json_extract(card_json,'$.tags') END AS card_tags FROM tavern_resources";
    final rows = await _db
        .customSelect(
          kind == null
              ? '$columns ORDER BY saved_at DESC'
              : '$columns WHERE kind=? ORDER BY saved_at DESC',
          variables: kind == null ? const [] : [Variable.withString(kind)],
        )
        .get();
    return rows.map((row) {
      final item = WorkItem.fromStored(
        Map<String, dynamic>.from(
          jsonDecode(row.read<String>('item_json')) as Map,
        ),
      );
      final rawTags = row.data['card_tags'];
      if (rawTags is! String || !rawTags.startsWith('[')) return item;
      final tags = jsonDecode(rawTags);
      if (tags is! List) return item;
      return WorkItem({
        ...item.json,
        'tags': {...item.tags, ...tags.whereType<String>()}.toList(),
      }, item.source);
    }).toList();
  }

  Future<void> removeResource(String uid) async {
    await _db.transaction(() async {
      final references = await _db
          .customSelect(
            'SELECT id FROM tavern_sessions WHERE resource_uid=? LIMIT 1',
            variables: [Variable.withString(uid)],
          )
          .get();
      if (references.isNotEmpty ||
          (await sessions()).any((session) => session.books.contains(uid))) {
        throw StateError('请先删除使用此资源的会话');
      }
      await _db.customStatement('DELETE FROM tavern_resources WHERE uid=?', [
        uid,
      ]);
    });
    notifyListeners();
  }

  Future<TavernSession> createSession(
    SavedTavernResource saved,
    int greeting, {
    bool persist = true,
  }) async {
    if (saved.resource.kind != 'character') {
      throw const FormatException('酒馆资源格式无效');
    }
    final greetings = saved.resource.greetings;
    final now = DateTime.now().millisecondsSinceEpoch;
    final session = TavernSession(
      id: const Uuid().v4(),
      resourceUid: saved.item.uid,
      title: saved.item.title.isEmpty ? saved.resource.name : saved.item.title,
      card: Map<String, dynamic>.from(saved.resource.raw),
      messages: [
        if (greeting >= 0 && greeting < greetings.length)
          {
            'role': 'assistant',
            'name': saved.resource.name,
            'content': greetings[greeting]
                .replaceAll('{{char}}', saved.resource.name)
                .replaceAll('{{user}}', 'User'),
          },
      ],
      books: [],
      updatedAt: now,
    );
    if (persist) await putSession(session);
    return session;
  }

  Future<void> putSession(
    TavernSession session, {
    bool existingOnly = false,
  }) async {
    if (AppSettings.instance.incognito) return;
    session.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction(() async {
      for (final uid in session.books) {
        final book = await _db
            .customSelect(
              'SELECT uid FROM tavern_resources WHERE uid=? AND kind=?',
              variables: [
                Variable.withString(uid),
                Variable.withString('lorebook'),
              ],
            )
            .get();
        if (book.isEmpty) throw StateError('关联的世界书已不存在');
      }
      if (existingOnly) {
        final changed = await _db.customUpdate(
          'UPDATE tavern_sessions SET data_json=?,updated_at=? WHERE id=?',
          variables: [
            Variable.withString(jsonEncode(session.toJson())),
            Variable.withInt(session.updatedAt),
            Variable.withString(session.id),
          ],
        );
        if (changed == 0) throw StateError('会话已删除');
        return;
      }
      await _db.customStatement(
        '''INSERT INTO tavern_sessions(id,resource_uid,data_json,updated_at) VALUES(?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET data_json=excluded.data_json,updated_at=excluded.updated_at''',
        [
          session.id,
          session.resourceUid,
          jsonEncode(session.toJson()),
          session.updatedAt,
        ],
      );
    });
    Library.instance.recordVisit(session.work);
    notifyListeners();
  }

  Future<TavernSession?> session(String id) async {
    final row = await _db
        .customSelect(
          'SELECT data_json FROM tavern_sessions WHERE id=?',
          variables: [Variable.withString(id)],
        )
        .getSingleOrNull();
    return row == null
        ? null
        : TavernSession.fromJson(
            jsonDecode(row.read<String>('data_json')) as Map,
          );
  }

  Future<List<TavernSession>> sessions({String? uid}) async {
    final rows = await _db
        .customSelect(
          uid == null
              ? 'SELECT data_json FROM tavern_sessions ORDER BY updated_at DESC'
              : 'SELECT data_json FROM tavern_sessions WHERE resource_uid=? ORDER BY updated_at DESC',
          variables: uid == null ? const [] : [Variable.withString(uid)],
        )
        .get();
    return [
      for (final row in rows)
        TavernSession.fromJson(
          jsonDecode(row.read<String>('data_json')) as Map,
        ),
    ];
  }

  Future<void> removeSession(String id) async {
    await Library.instance.flush();
    await _db.transaction(() async {
      await _db.customStatement('DELETE FROM tavern_sessions WHERE id=?', [id]);
      await _db.customStatement(
        'DELETE FROM history WHERE source=? AND work_id=?',
        [TavernSession.workSource, id],
      );
    });
    Library.instance.removeHistory('${TavernSession.workSource}:$id');
    notifyListeners();
  }
}

class TavernApiConfig {
  const TavernApiConfig({
    this.baseUrl = '',
    this.model = '',
    this.temperature = 0.7,
    this.maxTokens = 4096,
    this.secretRef = '',
    this.contextTokens = 65536,
    this.systemPrompt,
  });
  final String baseUrl;
  final String model;
  final double temperature;
  final int maxTokens;
  final String secretRef;
  final int contextTokens;
  final String? systemPrompt;
  String get effectiveSystemPrompt => systemPrompt ?? tr('生成的所有内容请使用简体中文回复。');
  bool get configured => baseUrl.isNotEmpty && model.isNotEmpty;
  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'model': model,
    'temperature': temperature,
    'maxTokens': maxTokens,
    'secretRef': secretRef,
    'contextTokens': contextTokens,
    if (systemPrompt != null) 'systemPrompt': systemPrompt,
  };
  factory TavernApiConfig.fromJson(Map value) => TavernApiConfig(
    baseUrl: value['baseUrl'] is String ? value['baseUrl'] as String : '',
    model: value['model'] is String ? value['model'] as String : '',
    temperature: (value['temperature'] as num?)?.toDouble() ?? 0.7,
    maxTokens: (value['maxTokens'] as num?)?.toInt() ?? 4096,
    secretRef: value['secretRef'] is String ? value['secretRef'] as String : '',
    contextTokens: (value['contextTokens'] as num?)?.toInt() ?? 65536,
    systemPrompt: value['systemPrompt'] is String
        ? value['systemPrompt'] as String
        : null,
  );
}

class TavernApiSettings extends ChangeNotifier {
  TavernApiSettings._();
  static final TavernApiSettings instance = TavernApiSettings._();
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
  );
  final _store = JsonStore('tavern_api.json');
  TavernApiConfig config = const TavernApiConfig();
  Future<void>? _loading;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final value = await _store.load();
      if (value is Map) config = TavernApiConfig.fromJson(value);
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }

  static Uri validateBaseUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    final local =
        uri != null &&
        {'localhost', '127.0.0.1', '::1'}.contains(uri.host.toLowerCase());
    if (value.length > 2048 ||
        uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !(uri.scheme == 'https' || (uri.scheme == 'http' && local))) {
      throw const FormatException('接口地址无效');
    }
    return uri;
  }

  Future<String> apiKey() async {
    await load();
    if (config.secretRef.isEmpty) return '';
    return await _secure.read(key: config.secretRef) ?? '';
  }

  Future<void> save({
    required String baseUrl,
    required String model,
    required double temperature,
    required int maxTokens,
    String? newKey,
    bool clearKey = false,
    String? systemPrompt,
    int contextTokens = 65536,
  }) async {
    await load();
    final uri = validateBaseUrl(baseUrl);
    if ((systemPrompt?.length ?? 0) > 32000 ||
        model.trim().isEmpty ||
        model.length > 200 ||
        (newKey != null &&
            (newKey.length > 4096 ||
                RegExp(r'[\x00-\x1f\x7f]').hasMatch(newKey))) ||
        !temperature.isFinite ||
        temperature < 0 ||
        temperature > 2 ||
        maxTokens < 1 ||
        maxTokens > 32768) {
      throw const FormatException('模型配置无效');
    }
    if (contextTokens < maxTokens + 256 || contextTokens > 2000000) {
      throw const FormatException('模型配置无效');
    }
    final old = config;
    var ref = clearKey ? '' : old.secretRef;
    final normalizedBase = uri.toString().replaceFirst(RegExp(r'/+$'), '');
    if (old.baseUrl.isNotEmpty && old.baseUrl != normalizedBase) {
      ref = '';
    }
    if (uri.scheme == 'http' &&
        (ref.isNotEmpty || (newKey?.trim().isNotEmpty ?? false))) {
      throw const FormatException('HTTP 本机服务不能携带 API Key');
    }
    if (newKey != null && newKey.trim().isNotEmpty) {
      ref = 'tavern_api_${const Uuid().v4()}';
      await _secure.write(key: ref, value: newKey.trim());
    }
    final next = TavernApiConfig(
      baseUrl: normalizedBase,
      model: model.trim(),
      temperature: temperature,
      maxTokens: maxTokens,
      secretRef: ref,
      contextTokens: contextTokens,
      systemPrompt: systemPrompt,
    );
    try {
      _store.save(next.toJson());
      await _store.flush();
      config = next;
    } catch (_) {
      _store.save(old.toJson());
      if (ref.isNotEmpty && ref != old.secretRef) {
        try {
          await _secure.delete(key: ref);
        } catch (_) {
          // 不覆盖配置保存失败的原始错误。
        }
      }
      rethrow;
    }
    if (old.secretRef.isNotEmpty && old.secretRef != ref) {
      try {
        await _secure.delete(key: old.secretRef);
      } catch (_) {
        /* 不影响已保存的新配置。 */
      }
    }
    notifyListeners();
  }
}
