import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../core/models.dart';

/// 只向设备已安装的系统语音引擎提交正文，不调用应用的翻译或生成服务。
class NovelSpeech extends ChangeNotifier {
  final _tts = FlutterTts();
  Process? _speechProcess;
  Future<void> _stopEngine() async {
    if (Platform.isLinux) {
      final process = _speechProcess;
      _speechProcess = null;
      process?.kill();
      if (process != null) await process.exitCode;
    } else {
      await _tts.stop();
    }
  }

  Future<int> _speak(
    String text,
    String language,
    double rate,
    int generation,
  ) async {
    if (!Platform.isLinux) return await _tts.speak(text);
    try {
      final process = await Process.start('espeak-ng', [
        '--stdin',
        '-v',
        language.startsWith('zh') ? 'cmn' : 'en',
        '-s',
        (175 * rate / .5).round().clamp(80, 450).toString(),
      ]);
      if (_disposed || generation != _generation) {
        process.kill();
        await process.exitCode;
        return 0;
      }
      _speechProcess = process;
      // 正文只经标准输入交给本机引擎，不写日志、参数或临时文件。
      final drains = Future.wait([
        process.stdout.drain<void>(),
        process.stderr.drain<void>(),
      ]);
      process.stdin.writeln(text);
      await process.stdin.close();
      final code = await process.exitCode;
      await drains;
      if (identical(_speechProcess, process)) _speechProcess = null;
      return code == 0 ? 1 : 0;
    } on ProcessException {
      throw SourceError('CONFIG', '朗读不可用，请检查系统语音引擎与语言包');
    }
  }

  int _generation = 0;
  bool _playing = false;
  bool _disposed = false;
  bool get playing => _playing;
  Future<void> stop() async {
    _generation++;
    _playing = false;
    if (!_disposed) notifyListeners();
    await _stopEngine();
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
    await _stopEngine();
    if (generation != _generation || _disposed) return;
    if (!Platform.isLinux) {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setLanguage(language.startsWith('zh') ? 'zh-CN' : 'en-US');
      await _tts.setSpeechRate(rate);
    }
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
          if (await _speak(chunk, language, rate, generation) != 1 &&
              generation == _generation) {
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
    _stopEngine().catchError((Object _) {});
    super.dispose();
  }
}
