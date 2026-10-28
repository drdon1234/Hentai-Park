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
    await _tts.awaitSpeakCompletion(true);
    await _tts.setLanguage(language.startsWith('zh') ? 'zh-CN' : 'en-US');
    await _tts.setSpeechRate(rate);
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
