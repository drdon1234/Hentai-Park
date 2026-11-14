import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/localization.dart';
import '../core/settings.dart';
import 'client.dart';
import 'models.dart';
import 'store.dart';
import 'worldbook_terms.dart';

/// 页面只呈现状态；生成、取消和保存共用一条有序的会话事务链。
class TavernConversation extends ChangeNotifier {
  TavernConversation(TavernSession original, {bool persist = true})
    : session = TavernSession.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map,
      ),
      ephemeral = !persist || AppSettings.instance.incognito {
    _privacy = AppSettings.instance.watch({'incognito'});
    _privacy.addListener(_privacyChanged);
  }

  final TavernSession session;
  bool ephemeral;
  bool busy = false;
  bool unsaved = false;
  bool trimmed = false;
  bool unsupportedLore = false;
  int matched = 0;
  int? totalTokens;
  String draft = '';
  TavernApiException? failure;
  TavernGeneration? _generation;
  bool _disposed = false;
  late final Listenable _privacy;
  void _privacyChanged() {
    ephemeral = ephemeral || AppSettings.instance.incognito;
    if (ephemeral) unsaved = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> save() async {
    // 一旦进入无痕，本页所有后续变更均不补写到原会话。
    ephemeral = ephemeral || AppSettings.instance.incognito;
    if (!ephemeral) {
      try {
        await TavernStore.instance.putSession(session);
      } catch (_) {
        unsaved = true;
        _notify();
        rethrow;
      }
    }
    unsaved = false;
    _notify();
  }

  Future<void> edit(int index, String text) async {
    if (busy || text.trim().isEmpty) return;
    session.messages[index] = {
      ...session.messages[index],
      'role': session.messages[index]['role']!,
      'content': text,
    };
    session.alternatives.remove('$index');
    await save();
  }

  Future<void> truncate(int index) async {
    if (busy) return;
    session.messages.removeRange(index, session.messages.length);
    session.alternatives.removeWhere(
      (key, _) => (int.tryParse(key) ?? index) >= index,
    );
    await save();
  }

  void cancel() => _generation?.cancel();

  Future<void> nextAlternative(int index) async {
    if (busy) return;
    final options = session.alternatives['$index'];
    if (options == null || options.isEmpty) return;
    options.add(Map.of(session.messages[index]));
    session.messages[index] = options.removeAt(0);
    await save();
  }

  Future<TavernSession> branch(int index) async {
    final data = session.toJson();
    data['id'] = const Uuid().v4();
    final copy = TavernSession.fromJson(jsonDecode(jsonEncode(data)) as Map);
    copy.messages.removeRange(index + 1, copy.messages.length);
    copy.alternatives.removeWhere(
      (key, _) => (int.tryParse(key) ?? index + 1) > index,
    );
    if (!ephemeral) await TavernStore.instance.putSession(copy);
    return copy;
  }

  Future<void> generate({
    String? text,
    bool regenerate = false,
    bool continuation = false,
  }) async {
    if (busy || unsaved) return;
    busy = true;
    failure = null;
    draft = '';
    trimmed = false;
    _notify();
    final generation = _generation = TavernGeneration();
    Map<String, String>? previous;
    var started = false;
    try {
      await TavernApiSettings.instance.load();
      final config = TavernApiSettings.instance.config;
      if (!config.configured) throw const TavernApiException('configuration');
      if (text != null && text.trim().isNotEmpty) {
        session.messages.add({
          'role': 'user',
          'content': text.trim(),
          'name': session.userName,
        });
        await save();
      }
      if (regenerate || continuation) {
        if (session.messages.isEmpty ||
            session.messages.last['role'] != 'assistant') {
          return;
        }
        previous = Map.of(session.messages.last);
      }
      final promptSession = TavernSession.fromJson(
        jsonDecode(jsonEncode(session.toJson())) as Map,
      );
      if (regenerate) promptSession.messages.removeLast();
      final books = <TavernResource>[];
      for (final uid in promptSession.books) {
        final saved = await TavernStore.instance.get(uid);
        if (saved == null) throw const TavernApiException('book_missing');
        books.add(saved.resource);
      }
      unsupportedLore = [
        TavernResource(kind: 'character', raw: session.card),
        ...books,
      ].any((r) => r.hasUnsupportedLore);
      await WorldbookTerms.instance.ensureLoaded(
        AppLocalizations.localeKey(AppLocalizations.instance.locale),
      );
      final prompt = await buildTranslatedTavernPrompt(
        promptSession,
        books,
        config: config,
        continuation: continuation,
      );
      matched = prompt.matchedEntries;
      trimmed = prompt.trimmedHistory;
      final key = await TavernApiSettings.instance.apiKey();
      started = true;
      await for (final delta in generation.send(
        config: config,
        apiKey: key,
        messages: prompt.messages,
      )) {
        draft += delta;
        _notify();
      }
    } catch (error) {
      failure = error is TavernApiException
          ? error
          : const TavernApiException('network');
    } finally {
      totalTokens = generation.totalTokens;
      if (started && draft.isNotEmpty) {
        // 重生成失败保留旧回复；新消息和续写保留已经收到的文本。
        if (!regenerate || failure == null) {
          final prefix = continuation && previous != null
              ? previous['content'] ?? ''
              : '';
          final message = <String, String>{
            'role': 'assistant',
            'name': TavernResource(kind: 'character', raw: session.card).name,
            'content': '$prefix$draft',
            'status':
                failure?.code ??
                (generation.finishReason == 'length' ? 'length' : 'complete'),
          };
          if (previous != null) session.messages.removeLast();
          if (regenerate && previous != null) {
            session.alternatives
                .putIfAbsent('${session.messages.length}', () => [])
                .add(previous);
          }
          session.messages.add(message);
          try {
            await save();
          } catch (_) {
            /* 页面保留未保存内容并阻止静默退出。 */
          }
        }
      }
      draft = '';
      busy = false;
      _generation = null;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _privacy.removeListener(_privacyChanged);
    cancel();
    super.dispose();
  }
}
