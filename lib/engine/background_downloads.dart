import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/app_log.dart';
import '../core/async_tasks.dart';
import '../core/localization.dart';
import '../core/models.dart';
import 'request_lifecycle.dart';

/// 下载共用 Android 前台服务或 iOS 有限后台时间；不发送作品或账号信息。
class BackgroundDownloads extends ChangeNotifier with WidgetsBindingObserver {
  BackgroundDownloads({
    Future<void> Function(int count)? update,
    Future<void> Function(double? value)? progress,
  }) : _update = update ?? _updateNative,
       _progress = progress ?? _progressNative;

  static final instance = BackgroundDownloads();
  static const _channel = MethodChannel('hentai_park/downloads');
  final Future<void> Function(int count) _update;
  final Future<void> Function(double? value) _progress;
  final _progressValues = <Object, double>{};
  Timer? _progressTimer;
  final _updates = SerialExecutor();
  final _tokens = <Object, CancelToken>{};
  final _recordings = <Object>{};
  bool _listening = false;
  bool _observing = false;
  bool _interrupted = false;
  VoidCallback? _executionLease;

  bool get interrupted => _interrupted;

  void _ensureLifecycleObserved() {
    if (_observing) return;
    try {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    } catch (_) {}
  }

  void _syncExecutionLease() {
    if (_tokens.isNotEmpty && !_interrupted) {
      try {
        _executionLease ??= RequestLifecycle.instance
            .acquireBackgroundExecution();
      } catch (_) {}
    } else {
      _executionLease?.call();
      _executionLease = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _interrupted) {
      _interrupted = false;
      _syncExecutionLease();
      notifyListeners();
    }
  }

  Future<T> run<T>(
    Future<T> Function(CancelToken token) action, {
    CancelToken? cancelToken,
  }) async {
    final lease = await acquire(cancelToken: cancelToken);
    try {
      lease.check();
      return await action(lease.token);
    } finally {
      await lease.release();
    }
  }

  Future<DownloadLease> acquire({
    CancelToken? cancelToken,
    bool recording = false,
  }) async {
    _ensureLifecycleObserved();
    if (!_listening && (Platform.isAndroid || Platform.isIOS)) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'interrupted') interrupt();
        if (call.method == 'taskRemoved') {
          for (final id in _recordings.toList()) {
            _tokens[id]?.cancel();
          }
        }
      });
    }
    final token = cancelToken ?? CancelToken();
    if (token.cancelError case final error?) throw error;
    final id = Object();
    await _updates.run(() async {
      if (token.cancelError case final error?) throw error;
      if (_interrupted) {
        final foreground =
            !_observing ||
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
        if (!foreground) {
          throw SourceError('BACKGROUND', '后台下载已被系统停止，请返回应用后重试');
        }
        _interrupted = false;
      }
      _tokens[id] = token;
      if (recording) _recordings.add(id);
      _syncExecutionLease();
      try {
        await _update(_tokens.length);
        _scheduleProgress();
      } catch (_) {
        _tokens.remove(id);
        _recordings.remove(id);
        _syncExecutionLease();
        throw SourceError('BACKGROUND', '无法启动后台下载，请返回应用后重试');
      }
    });
    return DownloadLease._(this, id, token);
  }

  /// 原生后台执行到期或被停止时，停止所有持有租约的网络工作。
  void interrupt() {
    _interrupted = true;
    _syncExecutionLease();
    for (final token in _tokens.values.toList()) {
      token.cancel(SourceError('BACKGROUND', '后台下载已被系统停止，请返回应用后重试'));
    }
    notifyListeners();
  }

  static SourceError? interruption(Object error) {
    if (error is DioException && error.error is SourceError) {
      error = error.error as SourceError;
    }
    return error is SourceError && error.code == 'BACKGROUND' ? error : null;
  }

  Future<void> _release(Object id) => _updates.run(() async {
    if (_tokens.remove(id) == null) return;
    _progressValues.remove(id);
    _scheduleProgress();
    _recordings.remove(id);
    _syncExecutionLease();
    try {
      await _update(_interrupted ? 0 : _tokens.length);
    } catch (error) {
      // 清理错误不覆盖原任务的下载或校验错误。
      AppLog.error(error, event: 'background_download');
    }
  });

  void _report(Object id, int done, int total) {
    if (!_tokens.containsKey(id)) return;
    if (total > 0) {
      _progressValues[id] = (done / total).clamp(0, 1);
    } else {
      _progressValues.remove(id);
    }
    _scheduleProgress();
  }

  void _scheduleProgress() {
    _progressTimer ??= Timer(const Duration(milliseconds: 250), () {
      _progressTimer = null;
      unawaited(
        _updates.run(() async {
          // 不同任务的字节、页数不能相加；按各任务的实际完成比例汇总。
          final value =
              _progressValues.isEmpty ||
                  _progressValues.length != _tokens.length
              ? null
              : _progressValues.values.reduce((a, b) => a + b) / _tokens.length;
          try {
            await _progress(value);
          } catch (error) {
            AppLog.error(error, event: 'background_download');
          }
        }),
      );
    });
  }

  static Future<void> _progressNative(double? value) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await _channel.invokeMethod<void>('progress', {'value': value});
  }

  static Future<void> _updateNative(int count) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await _channel.invokeMethod<void>('update', {
      'count': count,
      'title': tr('下载、录制与翻译'),
      'text': tr('任务进行中，切到后台后继续'),
    });
  }
}

class DownloadLease {
  DownloadLease._(this._owner, this._id, this.token);
  final BackgroundDownloads _owner;
  final Object _id;
  final CancelToken token;
  Future<void>? _release;

  void check() {
    if (token.cancelError case final error?) throw error;
  }

  void reportProgress(int done, int total) => _owner._report(_id, done, total);

  Future<void> release() => _release ??= _owner._release(_id);
}
