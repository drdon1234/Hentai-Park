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

  /// Translates [text] into every language in [targets]; returns code → translation.
  /// Languages that fail are left out; throws only when all of them fail.
  Future<KeywordTranslation> translateAll(
    String text,
    Iterable<String> targets, {
    String engine = 'google',
  }) async {
    final codes = targets.toList();
    if (engine != 'google') throw ArgumentError.value(engine, 'engine');
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
}
