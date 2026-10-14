import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'async_tasks.dart';
import 'diagnostics.dart';
import 'storage.dart';

/// Persists uncaught errors to `logs/crash.log` (rotated at 256 KB) so users can export them.
class CrashLog {
  static const _limit = 256 * 1024;
  static final _writes = SerialExecutor();

  static File get file => File(p.join(AppPaths.data.path, 'logs', 'crash.log'));

  static void install() {
    FlutterError.onError = (details) {
      record(
        details.exception,
        details.stack,
        context: details.context?.toString(),
      );
      debugPrint(Diagnostics.error(details.exception));
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack);
      debugPrint(Diagnostics.error(error));
      return true;
    };
  }

  static void record(Object error, StackTrace? stack, {String? context}) {
    final entry = StringBuffer()
      ..writeln('==== ${DateTime.now().toIso8601String()}')
      ..writeln(Diagnostics.error(error))
      ..writeln(Diagnostics.stack(stack));
    unawaited(_writes.run(() => _append(entry.toString())));
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
      ..writeln(
        '系统：${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      )
      ..writeln('Dart：${Platform.version.split(' ').first}')
      ..writeln();
    for (final f in [File('${file.path}.1'), file]) {
      if (await f.exists()) {
        for (final line in (await f.readAsString()).split('\n')) {
          if (line.startsWith('event=')) b.writeln(Diagnostics.message(line));
          if (line.startsWith('#')) {
            b.writeln(Diagnostics.stack(StackTrace.fromString(line)));
          }
        }
      }
    }
    b
      ..writeln('==== 运行日志')
      ..writeAll(
        runtimeLogs.map((line) {
          final start = line.indexOf('event=');
          return Diagnostics.message(start < 0 ? null : line.substring(start));
        }),
        '\n',
      );
    return b.toString();
  }
}
