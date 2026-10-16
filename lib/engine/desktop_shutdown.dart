import 'dart:async';

import 'package:flutter/foundation.dart';

/// 页面 dispose 不能返回 Future；退出前显式等待它启动的原生资源释放。
class PendingDisposals {
  static final instance = PendingDisposals();
  final _pending = <Future<void>>{};
  final _errors = <(Object, StackTrace)>[];

  /// 等待创建中的原生资源及其取消清理；业务错误仍由原调用者处理。
  Future<T> watch<T>(Future<T> task) {
    add(task.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
    return task;
  }

  void add(Future<void> task) {
    late final Future<void> settled;
    settled = task
        .then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) =>
              _errors.add((error, stack)),
        )
        .whenComplete(() => _pending.remove(settled));
    _pending.add(settled);
  }

  Future<void> drain() async {
    while (_pending.isNotEmpty) {
      await Future.wait(_pending.toList());
    }
    if (_errors.isNotEmpty) {
      final (error, stack) = _errors.first;
      _errors.clear();
      Error.throwWithStackTrace(error, stack);
    }
  }
}

/// 写入完成前可恢复运行；停止引擎后只能重试退出，不能恢复失效页面。
class DesktopShutdown extends ChangeNotifier {
  DesktopShutdown({
    required this.prepare,
    required this.detach,
    required this.flush,
    required this.stop,
    required this.resume,
  });

  final Future<void> Function() prepare, detach, flush, stop, resume;
  bool detached = false;
  bool failed = false;
  bool _busy = false;
  bool _committed = false;

  Future<void> exit() async {
    if (_busy) return;
    _busy = true;
    failed = false;
    notifyListeners();
    try {
      if (!_committed) {
        await prepare();
        detached = true;
        notifyListeners();
        await detach();
        await flush();
        _committed = true;
      }
      await stop();
    } catch (_) {
      if (_committed) {
        failed = true;
      } else {
        detached = false;
        notifyListeners();
        await resume();
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
