import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import '../core/app_log.dart';
import '../core/app_visibility.dart';
import '../core/models.dart';
import 'cancellation.dart';

/// 浏览器运行时在后台可能暂停；超时预算只计算可以执行的前台时间。
class RequestLifecycle extends ChangeNotifier with WidgetsBindingObserver {
  RequestLifecycle() {
    final binding = WidgetsBinding.instance;
    _background = _isBackground(binding.lifecycleState);
    _playbackHidden = !isAppVisible(binding.lifecycleState);
    if (!_background) _clock.start();
    binding.addObserver(this);
  }

  static final instance = RequestLifecycle();
  final _clock = Stopwatch();
  DateTime get foregroundNow =>
      DateTime.fromMicrosecondsSinceEpoch(_clock.elapsedMicroseconds);
  bool _observing = true;
  int _backgroundLeases = 0;
  bool _background = false;
  bool _playbackHidden = false;
  bool _shouldWait(bool playback) => playback ? _playbackHidden : _background;
  int generation = 0;
  bool get background => _background;

  static bool _isBackground(AppLifecycleState? state) =>
      state != null && state != AppLifecycleState.resumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_observing) return;
    AppLog.record({'event': 'lifecycle', 'action': state.name});
    final next = _backgroundLeases == 0 && _isBackground(state);
    final hidden = _backgroundLeases == 0 && !isAppVisible(state);
    if (next == _background && hidden == _playbackHidden) return;
    if (next != _background) {
      _background = next;
      if (next) {
        generation++;
        _clock.stop();
      } else {
        _clock.start();
      }
    }
    _playbackHidden = hidden;
    notifyListeners();
  }

  /// 仅在原生系统持有执行时间时暂时允许后台请求，结束后恢复真实生命周期。
  VoidCallback acquireBackgroundExecution() {
    _backgroundLeases++;
    didChangeAppLifecycleState(
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
    );
    var released = false;
    return () {
      if (released) return;
      released = true;
      _backgroundLeases--;
      didChangeAppLifecycleState(
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
      );
    };
  }

  Future<T> withBackgroundExecution<T>(Future<T> Function() action) async {
    final release = acquireBackgroundExecution();
    try {
      return await action();
    } finally {
      release();
    }
  }

  /// 无界面的订阅引擎没有可恢复的前台，保持原有有界超时与后台执行。
  void useBackgroundWorkerMode() {
    WidgetsBinding.instance.removeObserver(this);
    _observing = false;
    _background = false;
    _playbackHidden = false;
    _clock.start();
    notifyListeners();
  }

  Future<void> waitForForeground(
    CancelToken? token, {
    bool playback = false,
  }) async {
    if (token?.cancelError case final error?) throw error;
    if (!_shouldWait(playback)) return;
    final ready = Completer<void>();
    void changed() {
      if (!_shouldWait(playback) && !ready.isCompleted) ready.complete();
    }

    addListener(changed);
    try {
      await awaitCancelled(ready.future, token);
    } finally {
      removeListener(changed);
    }
  }

  /// 普通请求按聚焦时间退避，播放请求在 Android 窗口可见时继续计时。
  Future<void> retryDelay(
    Duration delay,
    CancelToken? token, {
    bool playback = false,
  }) async {
    await waitForForeground(token, playback: playback);
    final ready = Completer<void>();
    final timer = foregroundTimer(delay, ready.complete, playback: playback);
    try {
      await awaitCancelled(ready.future, token);
      await waitForForeground(token, playback: playback);
    } finally {
      timer.cancel();
    }
  }

  Future<T> timeout<T>(
    Future<T> operation,
    Duration budget, {
    required T Function() onTimeout,
  }) {
    final result = Completer<T>();
    final timer = foregroundTimer(budget, () {
      if (result.isCompleted) return;
      try {
        result.complete(onTimeout());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    operation.then(
      (value) {
        if (!result.isCompleted) result.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      },
    );
    return result.future.whenComplete(() {
      timer.cancel();
    });
  }

  Timer foregroundTimer(
    Duration budget,
    void Function() callback, {
    bool playback = false,
  }) => _ForegroundTimer(this, budget, callback, playback);

  /// 只重放明确只读、且跨过后台切换的连接失败；HTTP/认证/配置失败不重放。
  Future<T> recoverRead<T>(
    Future<T> Function() operation, {
    required bool replayable,
    CancelToken? cancelToken,
  }) async {
    final started = generation;
    final startedInBackground = _background;
    try {
      return await operation();
    } catch (error) {
      final networkFailure =
          error is SourceError &&
              error.code == 'NETWORK' &&
              const {
                'CONNECT_TIMEOUT',
                'RECEIVE_TIMEOUT',
                'CONNECTION',
                'RESPONSE_STREAM',
              }.contains(error.diagnostics['reason']) ||
          error is DioException &&
              const {
                DioExceptionType.connectionTimeout,
                DioExceptionType.receiveTimeout,
                DioExceptionType.connectionError,
              }.contains(error.type);
      if (!replayable ||
          !networkFailure ||
          (!startedInBackground && !_background && generation == started)) {
        rethrow;
      }
      await waitForForeground(cancelToken);
      AppLog.record({'event': 'request_recovery', 'outcome': 'started'});
      if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
      return operation();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// 可取消的一次性前台计时器，完成或取消时立即解除生命周期监听。
class _ForegroundTimer implements Timer {
  _ForegroundTimer(
    this.lifecycle,
    this.remaining,
    this.callback,
    this.playback,
  ) {
    lifecycle.addListener(changed);
    changed();
  }
  final RequestLifecycle lifecycle;
  final bool playback;
  Duration remaining;
  final void Function() callback;
  final watch = Stopwatch();
  Timer? timer;
  bool active = true;
  int ticks = 0;
  void changed() {
    timer?.cancel();
    if (watch.isRunning) {
      watch.stop();
      remaining -= watch.elapsed;
      watch.reset();
    }
    if (!active || lifecycle._shouldWait(playback)) return;
    watch.start();
    timer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      if (!active) return;
      ticks = 1;
      cancel();
      callback();
    });
  }

  @override
  bool get isActive => active;
  @override
  int get tick => ticks;
  @override
  void cancel() {
    if (!active) return;
    active = false;
    timer?.cancel();
    watch.stop();
    lifecycle.removeListener(changed);
  }
}
