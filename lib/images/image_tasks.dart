import 'dart:async';

import 'package:dio/dio.dart';

import '../engine/cancellation.dart';

enum ImagePriority { visible, preload, background }

/// 调用者各自取消；只有最后一个使用者离开才终止共享操作。
class ImageTasks<T> {
  final _tasks = <String, _SharedTask<T>>{};

  Future<T> run(
    String key,
    Future<T> Function(CancelToken, ImagePriority Function()) action, {
    required ImagePriority priority,
    CancelToken? cancelToken,
    void Function()? onPromoted,
  }) async {
    if (cancelToken?.cancelError case final error?) throw error;
    final task = _tasks.putIfAbsent(key, () {
      final task = _SharedTask<T>(priority);
      task.result = Future.sync(() => action(task.token, () => task.priority));
      task.result.then<void>(
        (_) => _remove(key, task),
        onError: (Object _, StackTrace _) => _remove(key, task),
      );
      return task;
    });
    task.users++;
    if (priority.index < task.priority.index) {
      task.priority = priority;
      onPromoted?.call();
    }
    try {
      return await awaitCancelled(task.result, cancelToken);
    } finally {
      if (--task.users == 0) {
        _remove(key, task);
        task.token.cancel();
      }
    }
  }

  void _remove(String key, _SharedTask<T> task) {
    if (identical(_tasks[key], task)) _tasks.remove(key);
  }
}

class _SharedTask<T> {
  _SharedTask(this.priority);
  ImagePriority priority;
  final token = CancelToken();
  late Future<T> result;
  int users = 0;
}

/// 同时取得全局、主机和浏览器额度，等待期间不占用任何一种额度。
class ImageScheduler {
  ImageScheduler({required this.hostLimit, this.maximum = 16});
  final int Function() hostLimit;
  final int maximum;
  final _waiting = <_WaitingImage>[];
  final _hosts = <String, int>{};
  final _sessions = <String, int>{};
  int _running = 0, _browser = 0, _preferred = 0;

  Future<void Function()> acquire(
    String host, {
    required ImagePriority Function() priority,
    required CancelToken token,
    String? browserSession,
  }) async {
    if (token.cancelError case final error?) throw error;
    final entry = _WaitingImage(host, priority, browserSession);
    _waiting.add(entry);
    refresh();
    try {
      await awaitCancelled(entry.ready.future, token);
      if (token.cancelError case final error?) throw error;
    } catch (_) {
      if (!_waiting.remove(entry)) _release(entry);
      rethrow;
    }
    var released = false;
    return () {
      if (released) return;
      released = true;
      _release(entry);
    };
  }

  void refresh() {
    while (_running < maximum) {
      final eligible = _waiting
          .where(
            (e) =>
                (_hosts[e.host] ?? 0) < hostLimit() &&
                (e.session == null ||
                    (_browser < 4 && (_sessions[e.session] ?? 0) < 2)),
          )
          .toList();
      if (eligible.isEmpty) return;
      // 每八个优先任务让出一次给最早的可运行任务，避免后台长期饥饿。
      var next = eligible.first;
      if (_preferred < 8) {
        for (final entry in eligible) {
          if (entry.priority().index < next.priority().index) next = entry;
        }
        _preferred++;
      } else {
        _preferred = 0;
      }
      _waiting.remove(next);
      _running++;
      _hosts.update(next.host, (n) => n + 1, ifAbsent: () => 1);
      if (next.session case final session?) {
        _browser++;
        _sessions.update(session, (n) => n + 1, ifAbsent: () => 1);
      }
      next.ready.complete();
    }
  }

  void _release(_WaitingImage entry) {
    _running--;
    if (_hosts.update(entry.host, (n) => n - 1) == 0) _hosts.remove(entry.host);
    if (entry.session case final session?) {
      _browser--;
      if (_sessions.update(session, (n) => n - 1) == 0) {
        _sessions.remove(session);
      }
    }
    refresh();
  }
}

class _WaitingImage {
  _WaitingImage(this.host, this.priority, this.session);
  final String host;
  final ImagePriority Function() priority;
  final String? session;
  final ready = Completer<void>();
}
