import 'dart:convert';

import '../engine/http_service.dart';
import 'models.dart';

/// Translated search terms together with the language detected for the input.
class KeywordTranslation {
  const KeywordTranslation(this.translations, {this.sourceLanguage});
  final Map<String, String> translations;
  final String? sourceLanguage;
}

String? normalizeSearchLanguage(String? code) => switch (code?.toLowerCase()) {
  'zh' || 'zh-cn' || 'zh-hans' => 'zh-CN',
  'zh-tw' || 'zh-hant' || 'zh-hk' => 'zh-TW',
  null || '' => null,
  _ => code!.toLowerCase().split('-').first,
};

/// Free web translation endpoints (no API key) used to search the same keyword in several languages.
class Translator {
  Translator._();
  static final Translator instance = Translator._();

  String? _msToken;
  DateTime _msTokenTime = DateTime(2000);

  static const _msCodes = {'zh-CN': 'zh-Hans', 'zh-TW': 'zh-Hant'};

  /// Translates [text] into every language in [targets]; returns code → translation.
  /// Languages that fail are left out; throws only when all of them fail.
  Future<KeywordTranslation> translateAll(
    String text,
    Iterable<String> targets, {
    String engine = 'google',
  }) async {
    final codes = targets.toList();
    if (engine == 'microsoft') return _microsoft(text, codes);
    final out = <String, String>{};
    final detected = <String, String>{};
    Object? lastError;
    await Future.wait(
      codes.map((code) async {
        try {
          final t = await _google(text, code);
          if (t.text.isNotEmpty) out[code] = t.text;
          if (t.sourceLanguage != null) detected[code] = t.sourceLanguage!;
        } catch (e) {
          lastError = e;
        }
      }),
    );
    if (out.isEmpty && lastError != null) throw lastError!;
    return KeywordTranslation(
      {
        for (final c in codes)
          if (out[c] != null) c: out[c]!,
      },
      sourceLanguage: codes
          .map((c) => detected[c])
          .whereType<String>()
          .firstOrNull,
    );
  }

  Future<({String text, String? sourceLanguage})> _google(
    String text,
    String target,
  ) async {
    final uri = Uri.https('translate.googleapis.com', '/translate_a/single', {
      'client': 'gtx',
      'sl': 'auto',
      'tl': target,
      'dt': 't',
      'q': text,
    });
    final res = await HttpService.instance.send(
      method: 'GET',
      url: uri.toString(),
      timeout: const Duration(seconds: 12),
      detectCloudflare: false,
    );
    if (!res.ok) {
      throw SourceError(
        'NETWORK',
        '谷歌翻译请求失败（HTTP {status}）',
        params: {'status': res.status},
        status: res.status,
      );
    }
    final data = jsonDecode(res.text);
    final parts = (data is List && data.isNotEmpty && data[0] is List)
        ? data[0] as List
        : const [];
    return (
      text: parts
          .map((p) => p is List && p.isNotEmpty ? '${p[0] ?? ''}' : '')
          .join()
          .trim(),
      sourceLanguage: normalizeSearchLanguage(
        data is List && data.length > 2 && data[2] is String
            ? data[2] as String
            : null,
      ),
    );
  }

  Future<KeywordTranslation> _microsoft(String text, List<String> codes) async {
    if (_msToken == null ||
        DateTime.now().difference(_msTokenTime) > const Duration(minutes: 8)) {
      final auth = await HttpService.instance.send(
        method: 'GET',
        url: 'https://edge.microsoft.com/translate/auth',
        timeout: const Duration(seconds: 12),
        detectCloudflare: false,
      );
      if (!auth.ok) {
        throw SourceError(
          'NETWORK',
          '微软翻译授权失败（HTTP {status}）',
          params: {'status': auth.status},
          status: auth.status,
        );
      }
      _msToken = auth.text.trim();
      _msTokenTime = DateTime.now();
    }
    final to = codes.map((c) => 'to=${_msCodes[c] ?? c}').join('&');
    final res = await HttpService.instance.send(
      method: 'POST',
      url:
          'https://api-edge.cognitive.microsofttranslator.com/translate?api-version=3.0&$to',
      headers: {
        'Authorization': 'Bearer $_msToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode([
        {'Text': text},
      ]),
      timeout: const Duration(seconds: 12),
      detectCloudflare: false,
    );
    if (!res.ok) {
      _msToken = null;
      throw SourceError(
        'NETWORK',
        '微软翻译请求失败（HTTP {status}）',
        params: {'status': res.status},
        status: res.status,
      );
    }
    final data = jsonDecode(res.text);
    final list = (data is List && data.isNotEmpty && data[0] is Map)
        ? (data[0]['translations'] as List? ?? const [])
        : const [];
    final byMs = {
      for (final t in list.whereType<Map>())
        '${t['to']}': '${t['text'] ?? ''}'.trim(),
    };
    final detected = data is List && data.isNotEmpty && data[0] is Map
        ? data[0]['detectedLanguage']
        : null;
    return KeywordTranslation(
      {
        for (final c in codes)
          if ((byMs[_msCodes[c] ?? c] ?? '').isNotEmpty)
            c: byMs[_msCodes[c] ?? c]!,
      },
      sourceLanguage: normalizeSearchLanguage(
        detected is Map ? detected['language']?.toString() : null,
      ),
    );
  }
}
