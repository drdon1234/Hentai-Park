import 'dart:convert';

import '../engine/http_service.dart';
import 'models.dart';

/// Target languages for multi-language search, keyed by Google language code.
const translateLanguages = <String, String>{
  'zh-CN': '简体中文',
  'zh-TW': '繁体中文',
  'ja': '日语',
  'ko': '韩语',
  'en': '英语',
  'es': '西班牙语',
  'ru': '俄语',
  'ar': '阿拉伯语',
};

const translateEngines = <String, String>{
  'google': '谷歌翻译',
  'microsoft': '微软翻译',
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
  Future<Map<String, String>> translateAll(String text, Iterable<String> targets, {String engine = 'google'}) async {
    final codes = targets.toList();
    if (engine == 'microsoft') return _microsoft(text, codes);
    final out = <String, String>{};
    Object? lastError;
    await Future.wait(
      codes.map((code) async {
        try {
          final t = await _google(text, code);
          if (t.isNotEmpty) out[code] = t;
        } catch (e) {
          lastError = e;
        }
      }),
    );
    if (out.isEmpty && lastError != null) throw lastError!;
    return {for (final c in codes) if (out[c] != null) c: out[c]!};
  }

  Future<String> _google(String text, String target) async {
    final uri = Uri.https('translate.googleapis.com', '/translate_a/single', {'client': 'gtx', 'sl': 'auto', 'tl': target, 'dt': 't', 'q': text});
    final res = await HttpService.instance.send(method: 'GET', url: uri.toString(), timeout: const Duration(seconds: 12), detectCloudflare: false);
    if (!res.ok) throw SourceError('NETWORK', '谷歌翻译请求失败（HTTP ${res.status}）', status: res.status);
    final data = jsonDecode(res.text);
    final parts = (data is List && data.isNotEmpty && data[0] is List) ? data[0] as List : const [];
    return parts.map((p) => p is List && p.isNotEmpty ? '${p[0] ?? ''}' : '').join().trim();
  }

  Future<Map<String, String>> _microsoft(String text, List<String> codes) async {
    if (_msToken == null || DateTime.now().difference(_msTokenTime) > const Duration(minutes: 8)) {
      final auth = await HttpService.instance.send(method: 'GET', url: 'https://edge.microsoft.com/translate/auth', timeout: const Duration(seconds: 12), detectCloudflare: false);
      if (!auth.ok) throw SourceError('NETWORK', '微软翻译授权失败（HTTP ${auth.status}）', status: auth.status);
      _msToken = auth.text.trim();
      _msTokenTime = DateTime.now();
    }
    final to = codes.map((c) => 'to=${_msCodes[c] ?? c}').join('&');
    final res = await HttpService.instance.send(
      method: 'POST',
      url: 'https://api-edge.cognitive.microsofttranslator.com/translate?api-version=3.0&$to',
      headers: {'Authorization': 'Bearer $_msToken', 'Content-Type': 'application/json'},
      body: jsonEncode([
        {'Text': text},
      ]),
      timeout: const Duration(seconds: 12),
      detectCloudflare: false,
    );
    if (!res.ok) {
      _msToken = null;
      throw SourceError('NETWORK', '微软翻译请求失败（HTTP ${res.status}）', status: res.status);
    }
    final data = jsonDecode(res.text);
    final list = (data is List && data.isNotEmpty && data[0] is Map) ? (data[0]['translations'] as List? ?? const []) : const [];
    final byMs = {for (final t in list.whereType<Map>()) '${t['to']}': '${t['text'] ?? ''}'.trim()};
    return {
      for (final c in codes)
        if ((byMs[_msCodes[c] ?? c] ?? '').isNotEmpty) c: byMs[_msCodes[c] ?? c]!,
    };
  }
}
