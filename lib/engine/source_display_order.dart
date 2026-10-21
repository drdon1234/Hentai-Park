import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/models.dart';
import 'cancellation.dart';

enum SourceProbeState {
  available,
  loginRequired,
  verificationRequired,
  unsupported,
  unavailable,
  timedOut,
}

class SourceProbeResult {
  const SourceProbeResult(this.state, [this.elapsed]);

  final SourceProbeState state;
  final Duration? elapsed;

  int get _priority => switch (state) {
    SourceProbeState.available => 0,
    SourceProbeState.unavailable || SourceProbeState.timedOut => 2,
    _ => 1,
  };
}

/// 用户手动运行一次；结果仅在内存中派生显示顺序，不修改任何持久化顺序。
class SourceDisplayOrder extends ChangeNotifier {
  SourceDisplayOrder({
    required List<String> Function() sources,
    required Future<void> Function(String, CancelToken) probe,
    Future<void> Function()? ready,
    this.timeout = const Duration(seconds: 8),
    this.concurrency = 12,
    // 保持公开注入参数，内部字段不作为调用方接口。
    // ignore: prefer_initializing_formals
  }) : _sources = sources,
       // ignore: prefer_initializing_formals
       _probe = probe,
       // ignore: prefer_initializing_formals
       _ready = ready,
       assert(concurrency > 0);

  final List<String> Function() _sources;
  final Future<void> Function(String, CancelToken) _probe;
  final Future<void> Function()? _ready;
  final Duration timeout;
  final int concurrency;
  Map<String, SourceProbeResult> _results = {};
  Map<String, SourceProbeResult> get results => Map.unmodifiable(_results);
  final Set<CancelToken> _tokens = {};
  Future<void>? _flight;
  int _generation = 0;
  bool _disposed = false;
  int done = 0;
  int total = 0;
  bool get running => _flight != null;
  bool failed = false;

  /// 不跨域移动，group 为 null 的独立榜单、反搜等始终留在原位。
  List<T> apply<T>(
    List<T> baseline, {
    required String Function(T) key,
    required String? Function(T) group,
  }) {
    final output = baseline.toList();
    final groups = <String, List<int>>{};
    for (var i = 0; i < baseline.length; i++) {
      final category = group(baseline[i]);
      if (category != null) (groups[category] ??= []).add(i);
    }
    for (final positions in groups.values) {
      final sorted = positions.toList()
        ..sort((a, b) {
          final left = _results[key(baseline[a])];
          final right = _results[key(baseline[b])];
          final state = (left?._priority ?? 1).compareTo(right?._priority ?? 1);
          if (state != 0) return state;
          if (left?.state == SourceProbeState.available &&
              right?.state == SourceProbeState.available) {
            final speed = left!.elapsed!.compareTo(right!.elapsed!);
            if (speed != 0) return speed;
          }
          return a.compareTo(b);
        });
      for (var i = 0; i < positions.length; i++) {
        output[positions[i]] = baseline[sorted[i]];
      }
    }
    return output;
  }

  /// 只由明确的用户操作调用；没有定时器、启动或网络变化后的自动探测。
  Future<void> checkNow() {
    if (_disposed) return Future.value();
    if (_flight != null) return _flight!;
    final generation = ++_generation;
    done = total = 0;
    failed = false;
    final completed = Completer<void>();
    _flight = completed.future;
    notifyListeners();
    unawaited(() async {
      try {
        await _run(generation);
      } catch (_) {
        if (generation == _generation) failed = true;
      } finally {
        if (generation == _generation) {
          _flight = null;
          _notify();
        }
        completed.complete();
      }
    }());
    return completed.future;
  }

  Future<void> _run(int generation) async {
    final preparing = CancelToken();
    _tokens.add(preparing);
    try {
      if (_ready != null) await awaitCancelled(_ready(), preparing);
    } finally {
      _tokens.remove(preparing);
    }
    if (generation != _generation) return;
    final keys = _sources();
    total = keys.length;
    _notify();
    final next = <String, SourceProbeResult>{};
    var index = 0;
    Future<void> worker() async {
      while (generation == _generation && index < keys.length) {
        final key = keys[index++];
        final token = CancelToken();
        _tokens.add(token);
        final watch = Stopwatch()..start();
        var timedOut = false;
        final timer = Timer(timeout, () {
          timedOut = true;
          token.cancel('source display probe timeout');
        });
        SourceProbeResult? result;
        try {
          await awaitCancelled(_probe(key, token), token);
          result = SourceProbeResult(SourceProbeState.available, watch.elapsed);
        } catch (error) {
          if (timedOut) {
            result = const SourceProbeResult(SourceProbeState.timedOut);
          } else if (!token.isCancelled) {
            result = switch (error) {
              SourceError(code: 'LOGIN_REQUIRED') => const SourceProbeResult(
                SourceProbeState.loginRequired,
              ),
              SourceError(code: 'CLOUDFLARE' || 'CONFIRM_REQUIRED') =>
                const SourceProbeResult(SourceProbeState.verificationRequired),
              SourceError(code: 'UNSUPPORTED' || 'CONFIG') =>
                const SourceProbeResult(SourceProbeState.unsupported),
              SourceError(code: 'CANCELLED') => null,
              _ => const SourceProbeResult(SourceProbeState.unavailable),
            };
          }
        } finally {
          watch.stop();
          timer.cancel();
          _tokens.remove(token);
        }
        if (generation != _generation) return;
        if (result != null) next[key] = result;
        done++;
        _notify();
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
    if (generation == _generation) _results = next;
  }

  /// 取消本轮不应用半成品，也不清除上次完整结果。
  void cancel() {
    _generation++;
    for (final token in _tokens.toList()) {
      token.cancel('source display probe cancelled');
    }
    _tokens.clear();
    _flight = null;
    _notify();
  }

  /// 原显示顺序、代理或站点身份变化时仅失效，不发起新请求。
  void invalidate([String? key]) {
    cancel();
    if (key == null) {
      _results = {};
    } else {
      _results.remove(key);
    }
    failed = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }
}
