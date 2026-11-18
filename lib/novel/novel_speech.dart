import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 只向设备已安装的系统语音引擎提交正文，不调用应用的翻译或生成服务。
class NovelSpeech extends ChangeNotifier {
  final _tts = FlutterTts();
  int _generation = 0;
  bool _playing = false;
  bool _disposed = false;
  bool get playing => _playing;
  Future<void> stop() async {
    _generation++;
    _playing = false;
    if (!_disposed) notifyListeners();
    await _tts.stop();
  }

  static String normalizeLanguage(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'en';
    final lower = trimmed.toLowerCase().replaceAll('_', '-');
    if (lower == 'zh' ||
        lower == 'zh-hans' ||
        lower == 'zh-cn' ||
        lower == 'zh-sg' ||
        lower.contains('简体') ||
        lower == '中文' ||
        lower == 'chinese') {
      return 'zh-CN';
    }
    if (lower == 'zh-hant' ||
        lower == 'zh-tw' ||
        lower == 'zh-hk' ||
        lower.contains('繁體') ||
        lower.contains('繁体')) {
      return 'zh-TW';
    }
    if (lower == 'ja' ||
        lower.startsWith('ja-') ||
        lower == 'japanese' ||
        lower.contains('日')) {
      return 'ja-JP';
    }
    if (lower == 'ko' ||
        lower.startsWith('ko-') ||
        lower == 'korean' ||
        lower.contains('韩') ||
        lower.contains('韓') ||
        lower.contains('한국')) {
      return 'ko-KR';
    }
    if (lower == 'en' ||
        lower.startsWith('en-') ||
        lower == 'english' ||
        lower.contains('英')) {
      return 'en-US';
    }
    if (lower == 'es' || lower.startsWith('es-') || lower == 'spanish') {
      return 'es-ES';
    }
    if (lower == 'ru' || lower.startsWith('ru-') || lower == 'russian') {
      return 'ru-RU';
    }
    if (lower == 'ar' || lower.startsWith('ar-') || lower == 'arabic') {
      return 'ar-SA';
    }
    return trimmed.replaceAll('_', '-');
  }

  /// AppSettings.novelSpeechRate stores 0.2..0.8 (default 0.5).
  /// iOS AVSpeechSynthesizer treats 0.5 as 1.0x normal speed, whereas Android
  /// TextToSpeech treats 1.0 as 1.0x normal speed.
  static double platformSpeechRate(double settingRate) {
    final normalized = settingRate.clamp(0.2, 0.8);
    if (defaultTargetPlatform == TargetPlatform.android) {
      return (normalized * 2.0).clamp(0.4, 1.6);
    }
    return normalized;
  }

  Future<String?> _resolveAvailableLocale(String language) async {
    final normalized = normalizeLanguage(language);
    final candidates = <String>[
      normalized,
      if (normalized.contains('-')) normalized.split('-').first,
    ];
    for (final candidate in candidates) {
      if (await _tts.isLanguageAvailable(candidate) == true) {
        return candidate;
      }
    }
    return null;
  }

  Future<void> read(
    String text, {
    required int offset,
    required String language,
    required double rate,
    required ValueChanged<int> onPosition,
  }) async {
    final generation = ++_generation;
    _playing = false;
    if (!_disposed) notifyListeners();
    await _tts.stop();
    if (generation != _generation || _disposed) return;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          const [
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          ],
          IosTextToSpeechAudioMode.spokenAudio,
        );
      } catch (_) {}
      if (generation != _generation || _disposed) return;
    }
    await _tts.awaitSpeakCompletion(true);
    if (generation != _generation || _disposed) return;
    final locale = await _resolveAvailableLocale(language);
    if (generation != _generation || _disposed) return;
    if (locale == null) {
      throw StateError('TTS language unavailable');
    }
    await _tts.setLanguage(locale);
    if (generation != _generation || _disposed) return;
    await _tts.setSpeechRate(platformSpeechRate(rate));
    if (generation != _generation || _disposed) return;
    _playing = true;
    notifyListeners();
    try {
      var start = offset.clamp(0, text.length);
      while (start < text.length && generation == _generation) {
        var end = text.indexOf('\n\n', start);
        if (end < 0) end = text.length;
        if (end - start > 800) {
          end = start + 800;
          final c = text.codeUnitAt(end - 1);
          if (c >= 0xD800 && c <= 0xDBFF) end--;
        }
        final chunk = text.substring(start, end).trim();
        if (chunk.isNotEmpty) {
          onPosition(start);
          if (generation != _generation || _disposed) return;
          if (await _tts.speak(chunk) != 1 && generation == _generation) {
            throw StateError('TTS unavailable');
          }
        }
        start = end;
        while (start < text.length && text[start] == '\n') {
          start++;
        }
      }
    } finally {
      if (generation == _generation && !_disposed) {
        _playing = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _tts.stop().catchError((Object _) {});
    super.dispose();
  }
}
