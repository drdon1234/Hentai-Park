import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'app_log.dart';
import 'diagnostic_entry.dart';
import 'diagnostics.dart';
import 'models.dart';
import 'storage.dart';

/// Fatal errors are flushed synchronously: the event loop may never run again.
class CrashLog {
  static const _limit = 256 * 1024;
  static final _pending = <DiagnosticEntry>[];

  static File get file => File(p.join(AppPaths.data.path, 'logs', 'crash.log'));

  static void install() {
    FlutterError.onError = (details) {
      record(details.exception, details.stack, library: details.library);
      if (kDebugMode) FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack);
      return true;
    };
  }

  /// Drain errors captured before the application directories were available.
  static void initialize() {
    // Historical files are disposable diagnostics, not user assets. Rewrite
    // them through the same whitelist before any new crash is appended.
    for (final f in [File('${file.path}.1'), file]) {
      try {
        if (!f.existsSync()) continue;
        final clean = <String>[];
        for (final line in f.readAsLinesSync()) {
          try {
            final entry = DiagnosticEntry.fromJson(jsonDecode(line));
            if (entry != null) clean.add(jsonEncode(entry.toJson()));
          } on FormatException {
            // Ignore incomplete records.
          }
        }
        f.writeAsStringSync(
          clean.isEmpty ? '' : '${clean.join('\n')}\n',
          flush: true,
        );
      } catch (_) {
        // Unreadable storage must not prevent startup or error reporting.
      }
    }
    for (final entry in _pending.toList()) {
      if (_append(entry)) _pending.remove(entry);
    }
  }

  static void record(Object error, StackTrace? stack, {String? library}) {
    final entry = AppLog.record(
      {'event': 'crash', ...Diagnostics.error(error), 'library': ?library},
      copy: error is SourceError ? error.copy : null,
      frames: Diagnostics.stack(stack),
    );
    if (!_append(entry)) {
      _pending.add(entry);
      if (_pending.length > 50) _pending.removeAt(0);
    }
  }

  static bool _append(DiagnosticEntry entry) {
    try {
      final f = file;
      final text = '${jsonEncode(entry.toJson())}\n';
      f.parent.createSync(recursive: true);
      if (f.existsSync() &&
          f.lengthSync() + utf8.encode(text).length > _limit) {
        final rotated = File('${f.path}.1');
        if (rotated.existsSync()) rotated.deleteSync();
        f.renameSync(rotated.path);
      }
      f.writeAsStringSync(text, mode: FileMode.append, flush: true);
      return true;
    } catch (_) {
      // Logging must never throw, including before AppPaths.init succeeds.
      return false;
    }
  }

  static Future<List<DiagnosticEntry>> _earlier() async {
    final entries = <DiagnosticEntry>[];
    for (final f in [File('${file.path}.1'), file]) {
      try {
        if (!await f.exists()) continue;
        for (final line in await f.readAsLines()) {
          try {
            final entry = DiagnosticEntry.fromJson(jsonDecode(line));
            if (entry != null) entries.add(entry);
          } on FormatException {
            // A partial final line must not hide the remaining history.
          }
        }
      } catch (_) {
        // An unreadable log must not block the report.
      }
    }
    return entries;
  }

  /// One timeline for the UI and export; each stack stays with its event.
  static Future<String> report({
    List<String> context = const [],
    LogMode mode = LogMode.full,
    List<DiagnosticEntry> nativeEntries = const [],
    bool export = false,
  }) async {
    initialize();
    final runtime = await AppLog.retained(limit: export ? null : 2000);
    final timeline = <String, DiagnosticEntry>{
      for (final entry in [...runtime, ...AppLog.entries])
        entry.identity: entry,
    };
    final current = timeline.values.toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    if (!export && current.length > 2000) {
      current.removeRange(2000, current.length);
    }
    final entries = <String, DiagnosticEntry>{
      for (final entry in [...await _earlier(), ...nativeEntries])
        if (!timeline.containsKey(entry.identity)) entry.identity: entry,
    };
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final history = <String, DiagnosticEntry>{};
    var omitted = 0;
    for (final entry in entries.values) {
      if (!entry.actionable || entry.time.isBefore(cutoff)) {
        omitted++;
        continue;
      }
      final signature = jsonEncode({
        'fields': entry.fields,
        'frames': entry.frames,
      });
      final previous = history[signature];
      if (previous == null) {
        history[signature] = DiagnosticEntry(
          time: entry.time,
          fields: entry.fields,
          frames: entry.frames,
          count: entry.count,
        );
      } else {
        previous.count += entry.count;
        if (entry.time.isAfter(previous.time)) previous.time = entry.time;
      }
    }
    final earlier = history.values.toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    if (earlier.length > 30) omitted += earlier.length - 30;
    final b = StringBuffer()
      ..writeln('HentaiPark 诊断日志')
      ..writeln('时间：${DateTime.now().toIso8601String()}')
      ..writeln('模式：${mode == LogMode.full ? '完整' : '脱敏'}')
      ..writeln(
        mode == LogMode.full
            ? '系统：${Platform.operatingSystem} ${Platform.operatingSystemVersion}'
            : '系统：${Platform.operatingSystem}',
      )
      ..writeln('Dart：${Platform.version.split(' ').first}');
    context.forEach(b.writeln);
    b
      ..writeln()
      ..writeln('==== 运行时间线（新到旧）')
      ..writeAll(
        current.isEmpty ? ['无'] : current.expand((entry) => entry.lines(mode)),
        '\n',
      )
      ..writeln()
      ..writeln()
      ..writeln('==== 历史异常（最近 7 天，最多 30 组，相同异常合并）')
      ..writeAll(
        earlier.isEmpty
            ? ['无']
            : earlier.take(30).expand((entry) => entry.lines(mode)),
        '\n',
      )
      ..writeln()
      ..writeln('已过滤或超出保留范围的历史记录：$omitted')
      ..writeln();
    return b.toString();
  }
}
