import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/settings.dart';
import '../engine/network_client.dart';
import 'models.dart';
import 'store.dart';
import 'worldbook_terms.dart';

class TavernApiException implements Exception {
  const TavernApiException(this.code, [this.status]);
  final String code;
  final int? status;
}

/// Retrieves model identifiers from OpenAI-compatible and Anthropic APIs.
class TavernModelCatalog {
  Future<List<String>> fetch({
    required String baseUrl,
    required String apiKey,
  }) async {
    final base = TavernApiSettings.validateBaseUrl(baseUrl);
    if (base.scheme == 'http' && apiKey.isNotEmpty) {
      throw const TavernApiException('insecure_key');
    }
    final anthropic = _isAnthropic(base);
    final paths = _modelPaths(base.path);
    final client = createHttpClient(proxy: AppSettings.instance.proxy);
    try {
      Object? lastError;
      for (final path in paths) {
        try {
          final request = await client
              .getUrl(base.replace(path: path, query: '', fragment: ''))
              .timeout(const Duration(seconds: 20));
          request.followRedirects = false;
          request.headers.set(HttpHeaders.acceptHeader, 'application/json');
          if (apiKey.isNotEmpty) {
            if (anthropic) {
              request.headers.set('x-api-key', apiKey);
              request.headers.set('anthropic-version', '2023-06-01');
            } else {
              request.headers.set(
                HttpHeaders.authorizationHeader,
                'Bearer $apiKey',
              );
            }
          }
          final response = await request.close().timeout(
            const Duration(seconds: 20),
          );
          if (response.statusCode < 200 || response.statusCode >= 300) {
            await response.drain<void>();
            lastError = TavernApiException('http', response.statusCode);
            continue;
          }
          final bytes = <int>[];
          await for (final chunk in response.timeout(
            const Duration(seconds: 20),
          )) {
            if (bytes.length + chunk.length > 2 * 1024 * 1024) {
              throw const TavernApiException('response');
            }
            bytes.addAll(chunk);
          }
          final value = jsonDecode(utf8.decode(bytes));
          final data = value is Map ? value['data'] : null;
          if (data is! List) throw const TavernApiException('response');
          final models = <String>[];
          for (final item in data) {
            if (item is Map) {
              final id = item['id'] ?? item['name'];
              if (id is String && id.trim().isNotEmpty) models.add(id.trim());
            }
          }
          return models.toSet().toList()..sort();
        } on TavernApiException catch (error) {
          lastError = error;
        } on FormatException catch (error) {
          lastError = error;
        } catch (error) {
          lastError = error;
        }
      }
      if (lastError is TavernApiException) throw lastError;
      throw const TavernApiException('network');
    } finally {
      client.close(force: true);
    }
  }

  static bool _isAnthropic(Uri base) {
    final host = base.host.toLowerCase();
    return host == 'api.anthropic.com' ||
        host.endsWith('.anthropic.com') ||
        base.path.toLowerCase().contains('anthropic');
  }

  static List<String> _modelPaths(String path) {
    final normalized = path.replaceFirst(RegExp(r'/+$'), '');
    final withoutV1 = normalized.replaceFirst(
      RegExp(r'/v1$', caseSensitive: false),
      '',
    );
    final candidates = <String>[
      '$normalized/models',
      '${withoutV1.isEmpty ? '' : withoutV1}/models',
    ];
    return candidates
        .map((value) => value.isEmpty ? '/models' : value)
        .toSet()
        .toList(growable: false);
  }
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

List<TavernLoreEntry> _selectTavernLore(
  TavernSession session,
  List<TavernResource> books,
  TavernApiConfig config,
) {
  final card = TavernResource(kind: 'character', raw: session.speakingCard);
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
  return entries;
}

Future<Map<TavernLoreEntry, String>> translateTavernLore(
  Iterable<TavernLoreEntry> entries,
) async {
  final result = <TavernLoreEntry, String>{};
  final pending = entries.toList();
  var next = 0;
  Future<void> worker() async {
    while (next < pending.length) {
      final entry = pending[next++];
      final translated = await WorldbookTerms.instance.translateText(
        entry.content,
      );
      if (translated != null && translated.trim().isNotEmpty) {
        result[entry] = translated;
      }
    }
  }

  final workers = pending.length < 2 ? pending.length : 2;
  await Future.wait(List.generate(workers, (_) => worker()));
  return result;
}

TavernPrompt buildTavernPrompt(
  TavernSession session,
  List<TavernResource> books, {
  TavernApiConfig config = const TavernApiConfig(),
  bool continuation = false,
}) {
  final entries = _selectTavernLore(session, books, config);
  return _buildTavernPrompt(
    session,
    books,
    config: config,
    continuation: continuation,
    entries: entries,
  );
}

Future<TavernPrompt> buildTranslatedTavernPrompt(
  TavernSession session,
  List<TavernResource> books, {
  TavernApiConfig config = const TavernApiConfig(),
  bool continuation = false,
}) async {
  final entries = _selectTavernLore(session, books, config);
  final translated = await translateTavernLore(entries);
  return _buildTavernPrompt(
    session,
    books,
    config: config,
    continuation: continuation,
    entries: entries,
    translated: translated,
  );
}

TavernPrompt _buildTavernPrompt(
  TavernSession session,
  List<TavernResource> books, {
  required TavernApiConfig config,
  required bool continuation,
  required List<TavernLoreEntry> entries,
  Map<TavernLoreEntry, String> translated = const {},
}) {
  final card = TavernResource(kind: 'character', raw: session.speakingCard);
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
            ('Story memory', session.memory),
            if (session.cast.isNotEmpty)
              (
                'Other characters',
                [
                  for (final raw in [session.card, ...session.cast.values])
                    if (!identical(raw, session.speakingCard))
                      TavernResource(kind: 'character', raw: raw),
                ].map((r) => '${r.name}: ${r.text('description')}').join('\n'),
              ),
          ]
          .where((f) => f.$2.trim().isNotEmpty)
          .map((f) => '${f.$1}: ${replace(f.$2)}')
          .join('\n\n');
  String world(bool before) => entries
      .where((e) => e.beforeCharacter == before)
      .map((e) => replace(translated[e] ?? e.content))
      .join('\n\n');
  final system = [
    instructions,
    world(true),
    role,
    world(false),
    config.effectiveSystemPrompt.trim(),
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
    final body = message['content'] ?? '';
    final content = session.cast.isNotEmpty && message['name'] != null
        ? '${message['name']}: $body'
        : body;
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
