import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import '../core/app_log.dart';
import '../core/async_tasks.dart';
import '../core/localization.dart';
import '../core/models.dart';

/// 正在执行的下载共用一个前台服务；不包含标题、站点或账号信息。
class BackgroundDownloads {
  BackgroundDownloads({Future<void> Function(int count)? update})
    : _update = update ?? _updateNative;

  static final instance = BackgroundDownloads();
  static const _channel = MethodChannel('hentai_park/downloads');
  final Future<void> Function(int count) _update;
  final _updates = SerialExecutor();
  final _tokens = <Object, CancelToken>{};
  final _recordings = <Object>{};
  bool _listening = false;
  bool _interrupted = false;

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
    if (!_listening && Platform.isAndroid) {
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
      if (_interrupted && _tokens.isNotEmpty) {
        throw SourceError('BACKGROUND', '后台下载已被系统停止，请返回应用后重试');
      }
      if (_tokens.isEmpty) _interrupted = false;
      _tokens[id] = token;
      if (recording) _recordings.add(id);
      try {
        await _update(_tokens.length);
      } catch (_) {
        _tokens.remove(id);
        _recordings.remove(id);
        throw SourceError('BACKGROUND', '无法启动后台下载，请返回应用后重试');
      }
    });
    return DownloadLease._(this, id, token);
  }

  /// Android 的服务超时或被停止时，停止所有持有租约的网络工作。
  void interrupt() {
    _interrupted = true;
    for (final token in _tokens.values.toList()) {
      token.cancel(SourceError('BACKGROUND', '后台下载已被系统停止，请返回应用后重试'));
    }
  }

  static SourceError? interruption(Object error) {
    if (error is DioException && error.error is SourceError) {
      error = error.error as SourceError;
    }
    return error is SourceError && error.code == 'BACKGROUND' ? error : null;
  }

  Future<void> _release(Object id) => _updates.run(() async {
    if (_tokens.remove(id) == null) return;
    _recordings.remove(id);
    try {
      await _update(_interrupted ? 0 : _tokens.length);
    } catch (error) {
      // 清理错误不覆盖原任务的下载或校验错误。
      AppLog.error(error, event: 'background_download');
    }
  });

  static Future<void> _updateNative(int count) async {
    if (!Platform.isAndroid) return;
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

  Future<void> release() => _release ??= _owner._release(_id);
}
