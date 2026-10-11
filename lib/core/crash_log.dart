import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'storage.dart';

/// Persists uncaught errors to `logs/crash.log` (rotated at 256 KB) so users can export them.
class CrashLog {
  static const _limit = 256 * 1024;

  static File get file => File(p.join(AppPaths.data.path, 'logs', 'crash.log'));

  static void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      record(details.exception, details.stack, context: details.context?.toString());
      previous?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack);
      return false; // keep the default handling (logging) as well
    };
  }

  static void record(Object error, StackTrace? stack, {String? context}) {
    final entry = StringBuffer()
      ..writeln('==== ${DateTime.now().toIso8601String()}${context != null ? ' · $context' : ''}')
      ..writeln(error)
      ..writeln(stack ?? '');
    unawaited(_append(entry.toString()));
  }

  static Future<void> _append(String text) async {
    try {
      final f = file;
      await f.parent.create(recursive: true);
      if (await f.exists() && await f.length() > _limit) {
        await f.rename('${f.path}.1');
      }
      await f.writeAsString(text, mode: FileMode.append, flush: true);
    } catch (_) {
      // Logging must never throw.
    }
  }

  /// Everything useful for a bug report: platform, recent crashes and the given runtime logs.
  static Future<String> report(List<String> runtimeLogs) async {
    final b = StringBuffer()
      ..writeln('HentaiPark 诊断日志')
      ..writeln('时间：${DateTime.now().toIso8601String()}')
      ..writeln('系统：${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
      ..writeln('Dart：${Platform.version.split(' ').first}')
      ..writeln();
    for (final f in [File('${file.path}.1'), file]) {
      if (await f.exists()) b.writeln(await f.readAsString());
    }
    b
      ..writeln('==== 运行日志')
      ..writeAll(runtimeLogs, '\n');
    return b.toString();
  }

  static Future<void> clear() async {
    for (final f in [File('${file.path}.1'), file]) {
      if (await f.exists()) await f.delete();
    }
  }
}
