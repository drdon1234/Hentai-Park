import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'app_log.dart';
import 'async_tasks.dart';
import 'diagnostics.dart';
import 'models.dart';
import 'storage.dart';

/// Persists uncaught errors to `logs/crash.log` (rotated at 256 KB) so users can export them.
class CrashLog {
  static const _limit = 256 * 1024;
  static final _writes = SerialExecutor();

  static File get file => File(p.join(AppPaths.data.path, 'logs', 'crash.log'));

  static void install() {
    FlutterError.onError = (details) {
      record(details.exception, details.stack, library: details.library);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack);
      return true;
    };
  }

  static void record(Object error, StackTrace? stack, {String? library}) {
    final fields = {
      'event': 'crash',
      ...Diagnostics.error(error),
      'library': ?library,
    };
    final copy = error is SourceError ? error.copy : null;
    final clean = Diagnostics.fields(fields, copy: copy);
    final frames = Diagnostics.stack(stack);
    AppLog.record(clean, copy: copy, frames: frames);
    final entry = jsonEncode({
      'time': DateTime.now().toIso8601String(),
      'fields': clean,
      'frames': frames,
    });
    unawaited(_writes.run(() => _append('$entry\n')));
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

  /// Uncaught errors of earlier runs, sanitized again when read back.
  static Future<List<String>> _earlier() async {
    final lines = <String>[];
    for (final f in [File('${file.path}.1'), file]) {
      try {
        if (!await f.exists()) continue;
        for (final line in await f.readAsLines()) {
          final Object? value;
          try {
            value = jsonDecode(line);
          } on FormatException {
            continue;
          }
          if (value is! Map || value['fields'] is! Map) continue;
          final time = DateTime.tryParse('${value['time']}');
          if (time == null) continue;
          lines.add(
            '${time.toIso8601String().substring(0, 19)} '
            '${Diagnostics.format(Diagnostics.fields(value['fields'] as Map))}',
          );
          final frames = value['frames'];
          if (frames is List) {
            lines.addAll(
              Diagnostics.stack(StackTrace.fromString(frames.join('\n')))
                  .map((frame) => '  $frame'),
            );
          }
        }
      } catch (_) {
        // An unreadable log must not block the report.
      }
    }
    return lines;
  }

  /// Everything useful for a bug report: platform, recent crashes and this run's log.
  static Future<String> report({List<String> context = const []}) async {
    final earlier = await _earlier();
    final b = StringBuffer()
      ..writeln('HentaiPark 诊断日志')
      ..writeln('时间：${DateTime.now().toIso8601String()}')
      ..writeln(
        '系统：${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      )
      ..writeln('Dart：${Platform.version.split(' ').first}');
    context.forEach(b.writeln);
    b
      ..writeln()
      ..writeln('==== 未捕获错误（含此前运行）')
      ..writeAll(earlier.isEmpty ? ['无'] : earlier, '\n')
      ..writeln()
      ..writeln()
      ..writeln('==== 本次运行')
      ..writeAll(AppLog.lines.isEmpty ? ['无'] : AppLog.lines, '\n')
      ..writeln();
    return b.toString();
  }
}
