import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/settings.dart';
import '../engine/network_client.dart';
import 'models.dart';
import 'store.dart';

class TavernApiException implements Exception {
  const TavernApiException(this.code, [this.status]);
  final String code;
  final int? status;
}

/// 独立于站点插件和 Cookie 的模型请求；取消立即关闭连接。
class TavernGeneration {
  HttpClient? _client;
  HttpClientRequest? _request;
  bool _cancelled = false;
  String finishReason = '';
  int? totalTokens;

  void cancel() {
    _cancelled = true;
    _request?.abort();
    _client?.close(force: true);
  }

  Stream<String> send({
    required TavernApiConfig config,
    required String apiKey,
    required List<Map<String, String>> messages,
  }) async* {
    final base = TavernApiSettings.validateBaseUrl(config.baseUrl);
    final path = base.path.replaceFirst(RegExp(r'/+$'), '');
    final target = base.replace(path: '$path/chat/completions');
    if (base.scheme == 'http' && apiKey.isNotEmpty) {
      throw const TavernApiException('insecure_key');
    }
    final client = _client = createHttpClient(
      proxy: AppSettings.instance.proxy,
    );
    try {
      if (_cancelled) throw const TavernApiException('cancelled');
      final request = _request = await client
          .postUrl(target)
          .timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      if (apiKey.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      }
      request.write(
        jsonEncode({
          'model': config.model,
          'messages': messages,
          'stream': true,
          'temperature': config.temperature,
          'max_tokens': config.maxTokens,
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw TavernApiException('http', response.statusCode);
      }
      var finished = false;
      var sawContent = false;
      final event = StringBuffer();
      String? parseEvent() {
        final data = event.toString();
        event.clear();
        if (data.isEmpty) return null;
        if (data == '[DONE]') {
          finished = true;
          return null;
        }
        final value = jsonDecode(data);
        if (value is! Map || value['error'] != null) {
          throw const TavernApiException('response');
        }
        final choices = value['choices'];
        if (value['usage'] is Map && value['usage']['total_tokens'] is int) {
          totalTokens = value['usage']['total_tokens'] as int;
        }
        if (choices is! List || choices.isEmpty) return null;
        final choice = choices.first;
        if (choice is! Map) throw const TavernApiException('response');
        if (choice['finish_reason'] is String) {
          finishReason = choice['finish_reason'] as String;
        }
        final delta = choice['delta'];
        if (delta is! Map || delta['content'] == null) return null;
        if (delta['content'] is! String) {
          throw const TavernApiException('response');
        }
        return delta['content'] as String;
      }

      await for (final line
          in response
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .timeout(const Duration(seconds: 90))) {
        if (_cancelled) throw const TavernApiException('cancelled');
        if (line.length > 1024 * 1024) {
          throw const TavernApiException('response');
        }
        if (line.isEmpty) {
          final delta = parseEvent();
          if (delta != null && delta.isNotEmpty) {
            sawContent = true;
            yield delta;
          }
          if (finished) break;
        } else if (line.startsWith('data:')) {
          if (event.isNotEmpty) event.write('\n');
          event.write(line.substring(5).trimLeft());
          if (event.length > 1024 * 1024) {
            throw const TavernApiException('response');
          }
        }
      }
      if (!finished && event.isNotEmpty) {
        final delta = parseEvent();
        if (delta != null && delta.isNotEmpty) {
          sawContent = true;
          yield delta;
        }
      }
      if (finished && !sawContent && finishReason == 'length') {
        throw const TavernApiException('length');
      }
      if (!finished || !sawContent) {
        throw const TavernApiException('incomplete');
      }
      if (finishReason.isNotEmpty &&
          !{'stop', 'length'}.contains(finishReason)) {
        throw const TavernApiException('response');
      }
    } on TavernApiException {
      rethrow;
    } catch (_) {
      throw TavernApiException(_cancelled ? 'cancelled' : 'network');
    } finally {
      client.close(force: true);
      _request = null;
      _client = null;
    }
  }
}

class TavernPrompt {
  const TavernPrompt({
    required this.messages,
    required this.matchedEntries,
    required this.trimmedHistory,
  });
  final List<Map<String, String>> messages;
  final int matchedEntries;
  final bool trimmedHistory;
}

TavernPrompt buildTavernPrompt(
  TavernSession session,
  List<TavernResource> books, {
  TavernApiConfig config = const TavernApiConfig(),
  bool continuation = false,
}) {
  final card = TavernResource(kind: 'character', raw: session.card);
  String replace(String text) => text
      .replaceAll('{{char}}', card.name)
      .replaceAll('{{user}}', session.userName);
  const fallback =
      'Write the next reply as the fictional character. Respect the user persona and story context.';
  final instructions = replace(
    card.text('system_prompt').trim().isEmpty
        ? fallback
        : card.text('system_prompt').replaceAll('{{original}}', fallback),
  );
  final post = replace(
    card.text('post_history_instructions').replaceAll('{{original}}', ''),
  );
  final role =
      [
            ('Character', card.name),
            ('Description', card.text('description')),
            ('Personality', card.text('personality')),
            ('Scenario', card.text('scenario')),
            ('Example dialogue', card.text('mes_example')),
            ('User name', session.userName),
            ('User persona', session.persona),
          ]
          .where((f) => f.$2.trim().isNotEmpty)
          .map((f) => '${f.$1}: ${replace(f.$2)}')
          .join('\n\n');
  final history = session.messages.map((m) => m['content'] ?? '').toList();
  final entries = <TavernLoreEntry>[];
  for (final book in [card, ...books]) {
    final settings = book.bookSettings;
    int number(String key, int fallback) =>
        settings[key] is num ? (settings[key] as num).toInt() : fallback;
    entries.addAll(
      matchTavernLore(
        book.entries,
        history,
        scanDepth: number('scan_depth', 4),
        tokenBudget: number(
          'token_budget',
          2048,
        ).clamp(0, config.contextTokens ~/ 2),
        recursive: settings['recursive_scanning'] == true,
      ),
    );
  }
  String world(bool before) => entries
      .where((e) => e.beforeCharacter == before)
      .map((e) => replace(e.content))
      .join('\n\n');
  final system = [
    instructions,
    world(true),
    role,
    world(false),
  ].where((s) => s.isNotEmpty).join('\n\n');
  final tail = <Map<String, String>>[
    if (post.isNotEmpty) {'role': 'system', 'content': post},
    if (continuation)
      {
        'role': 'user',
        'content': 'Continue the last character reply exactly from where it stopped. Do not repeat the existing text.',
      },
  ];
  final budget = config.contextTokens - config.maxTokens - 256;
  var used =
      estimateTavernTokens(system) +
      tail.fold<int>(0, (n, m) => n + estimateTavernTokens(m['content']!));
  if (used >= budget) throw const TavernApiException('context_too_large');
  final selected = <Map<String, String>>[];
  for (final message in session.messages.reversed) {
    final content = message['content'] ?? '';
    final cost = estimateTavernTokens(content);
    if (used + cost > budget) break;
    selected.add({'role': message['role']!, 'content': content});
    used += cost;
  }
  if (selected.isEmpty || (!continuation && selected.first['role'] != 'user')) {
    throw const TavernApiException('context_too_large');
  }
  return TavernPrompt(
    messages: [
      {'role': 'system', 'content': system},
      ...selected.reversed,
      ...tail,
    ],
    matchedEntries: entries.length,
    trimmedHistory: selected.length < session.messages.length,
  );
}
