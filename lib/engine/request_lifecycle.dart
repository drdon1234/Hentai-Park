import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import '../core/models.dart';
import 'cancellation.dart';

/// 浏览器运行时在后台可能暂停；超时预算只计算可以执行的前台时间。
class RequestLifecycle extends ChangeNotifier with WidgetsBindingObserver {
  RequestLifecycle() {
    final binding = WidgetsBinding.instance;
    _background = _isBackground(binding.lifecycleState);
    if (!_background) _clock.start();
    binding.addObserver(this);
  }

  static final instance = RequestLifecycle();
  final _clock = Stopwatch();
  DateTime get foregroundNow =>
      DateTime.fromMicrosecondsSinceEpoch(_clock.elapsedMicroseconds);
  bool _observing = true;
  bool _background = false;
  int generation = 0;
  bool get background => _background;

  static bool _isBackground(AppLifecycleState? state) =>
      state == AppLifecycleState.paused || state == AppLifecycleState.hidden;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_observing) return;
    final next = _isBackground(state);
    if (next == _background) return;
    _background = next;
    if (next) {
      generation++;
      _clock.stop();
    } else {
      _clock.start();
    }
    notifyListeners();
  }

  /// 无界面的订阅引擎没有可恢复的前台，保持原有有界超时与后台执行。
  void useBackgroundWorkerMode() {
    WidgetsBinding.instance.removeObserver(this);
    _observing = false;
    _background = false;
    _clock.start();
    notifyListeners();
  }

  Future<void> waitForForeground(CancelToken? token) async {
    if (!_background) return;
    final ready = Completer<void>();
    void changed() {
      if (!_background && !ready.isCompleted) ready.complete();
    }

    addListener(changed);
    try {
      await awaitCancelled(ready.future, token);
    } finally {
      removeListener(changed);
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

  Timer foregroundTimer(Duration budget, void Function() callback) =>
      _ForegroundTimer(this, budget, callback);

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
  _ForegroundTimer(this.lifecycle, this.remaining, this.callback) {
    lifecycle.addListener(changed);
    changed();
  }
  final RequestLifecycle lifecycle;
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
    if (!active || lifecycle.background) return;
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
