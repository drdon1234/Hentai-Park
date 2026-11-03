import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'diagnostic_entry.dart';
import 'diagnostics.dart';
import 'models.dart';
import 'storage.dart';

/// The diagnostics log of this run. Entries are sanitized by [Diagnostics]
/// when recorded, so the in-app view and the export show the same facts.
class AppLog {
  static const _limit = 2000;
  static final _entries = <DiagnosticEntry>[];
  static bool debugEnabled = false;
  static bool startupDebugNotice = false;
  static bool _persistent = false;
  static bool _initialized = false;
  static final _pending = <String>[];
  static Timer? _flushTimer;
  static Future<void> _writing = Future.value();
  static File get _file =>
      File(p.join(AppPaths.data.path, 'logs', 'runtime.log'));
  static bool get persistent => _persistent;
  static final _preferences = JsonStore('log_preferences.json');
  static bool debugNextLaunch = false;
  static Future<void> _savePreferences() async {
    _preferences.save({
      'persistent': _persistent,
      'debugNextLaunch': debugNextLaunch,
    });
    await _preferences.flush();
  }

  static Future<void> setDebugNextLaunch(bool value) async {
    debugNextLaunch = value;
    await _savePreferences();
  }

  static int _sequence = 0;
  static int nextRequestId() => ++_sequence;

  static Future<void> initialize() async {
    if (_initialized) return;
    Object? preferences;
    try {
      preferences = await _preferences.load();
    } catch (error) {
      _logStorageError(error);
    }
    _persistent = preferences is Map && preferences['persistent'] == true;
    final debug = preferences is Map && preferences['debugNextLaunch'] == true;
    debugEnabled = debug;
    startupDebugNotice = debug;
    debugNextLaunch = false;
    try {
      if (debug) await _savePreferences();
      if (!_persistent) await _clearFiles();
    } catch (error) {
      _logStorageError(error);
    }
    _initialized = true;
    record({'event': 'session', 'outcome': 'started'});
    await flush();
  }

  static void _logStorageError(Object error) =>
      AppLog.error(error, event: 'log_storage');

  static void debug(Map fields) {
    if (debugEnabled) record({...fields, 'level': 'debug'});
  }

  static void setDebug(bool value) {
    debugEnabled = value;
    record({'event': 'debug_mode', 'outcome': value ? 'started' : 'complete'});
  }

  /// 切换串行化到同一写队列；关闭立即抛弃历史文件并从当前会话重新记录。
  static Future<void> setPersistent(bool value) async {
    await flush();
    _persistent = value;
    final change = _writing.then((_) async {
      if (!value) {
        await _clearFiles();
        _entries.clear();
      }
    });
    _writing = change.catchError((Object _) {});
    await change;
    await _savePreferences();
    record({
      'event': 'log_retention',
      'outcome': value ? 'started' : 'complete',
    });
    await flush();
  }

  static Future<void> _clearFiles() async {
    for (var i = 0; i < 20; i++) {
      final file = i == 0 ? _file : File('${_file.path}.$i');
      if (await file.exists()) await file.delete();
    }
  }

  /// 每个记录均已净化；批量异步落盘，避免网络/分段事件同步阻塞界面。
  static Future<void> flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (!_initialized || _pending.isEmpty) return _writing;
    final batch = _pending.toList();
    _pending.clear();
    final persistent = _persistent;
    final writing = _writing.then((_) async {
      final file = _file;
      await file.parent.create(recursive: true);
      final limit = persistent ? 5 * 1024 * 1024 : 1024 * 1024;
      final count = persistent ? 20 : 2;
      var size = await file.exists() ? await file.length() : 0;
      for (final line in batch) {
        final bytes = utf8.encode('$line\n');
        if (size + bytes.length > limit) {
          final oldest = File('${file.path}.${count - 1}');
          if (await oldest.exists()) await oldest.delete();
          for (var i = count - 2; i >= 0; i--) {
            final from = i == 0 ? file : File('${file.path}.$i');
            if (await from.exists()) await from.rename('${file.path}.${i + 1}');
          }
          size = 0;
        }
        await file.writeAsBytes(bytes, mode: FileMode.append);
        size += bytes.length;
      }
    });
    // 日志存储失败不得递归写日志或中断业务；下一批仍可继续写入。
    _writing = writing.catchError((Object _) {});
    return _writing;
  }

  static Future<List<DiagnosticEntry>> retained({int? limit = 2000}) async {
    await flush();
    final result = <DiagnosticEntry>[];
    for (var i = 19; i >= 0; i--) {
      final file = i == 0 ? _file : File('${_file.path}.$i');
      try {
        if (!await file.exists()) continue;
        await for (final line
            in file
                .openRead()
                .transform(utf8.decoder)
                .transform(const LineSplitter())) {
          try {
            final entry = DiagnosticEntry.fromJson(jsonDecode(line));
            if (entry != null) result.add(entry);
          } on FormatException {
            /* 忽略意外退出留下的不完整记录。 */
          }
          if (limit != null && result.length > limit + 500) {
            result.removeRange(0, result.length - limit);
          }
        }
      } catch (_) {
        /* 单个日志不可读不阻断其他文件。 */
      }
    }
    if (limit != null && result.length > limit) {
      result.removeRange(0, result.length - limit);
    }
    return result;
  }

  static DiagnosticEntry record(
    Map fields, {
    PluginCopy? copy,
    List<String> frames = const [],
  }) {
    final clean = Diagnostics.fields({
      'level': 'normal',
      ...fields,
    }, copy: copy);
    final text = Diagnostics.format(clean);
    final cleanFrames = Diagnostics.stack(
      StackTrace.fromString(frames.join('\n')),
    );
    final now = DateTime.now();
    _entries.add(
      DiagnosticEntry(
        time: now,
        fields: clean,
        copy: copy,
        frames: cleanFrames,
      ),
    );
    if (_entries.length > _limit) {
      _entries.removeRange(0, _entries.length - _limit);
    }
    _pending.add(jsonEncode(_entries.last.toJson()));
    if (!_initialized && _pending.length > 2000) _pending.removeAt(0);
    if (_initialized && _pending.length >= 512) unawaited(flush());
    if (_initialized) {
      _flushTimer ??= Timer(
        const Duration(milliseconds: 250),
        () => unawaited(flush()),
      );
    }
    if (kDebugMode) debugPrint(text);
    return _entries.last;
  }

  /// Records a failure; cancellations are expected and skipped.
  static void error(
    Object error, {
    String event = 'error',
    String? site,
    String? action,
    StackTrace? stack,
    int? requestId,
    int? elapsedMs,
  }) {
    if (error is SourceError && error.code == 'CANCELLED') return;
    record(
      {
        'event': event,
        'site': ?site,
        'action': ?action,
        'requestId': ?requestId,
        'elapsedMs': ?elapsedMs,
        ...Diagnostics.error(error),
      },
      copy: error is SourceError ? error.copy : null,
      frames: Diagnostics.stack(stack),
    );
  }

  /// Sources that appear in this run's log.
  static Set<String> get sites => {
    for (final entry in _entries) ?entry.fields['site'],
  };

  static List<DiagnosticEntry> get entries => List.unmodifiable(_entries);

  static List<String> get lines => linesFor(LogMode.full);

  static List<String> linesFor(LogMode mode) => [
    for (final entry in _entries.reversed) ...entry.lines(mode),
  ];
}
