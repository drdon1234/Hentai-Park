import 'dart:async';

import 'package:dio/dio.dart';

import '../core/models.dart';
import 'cancellation.dart';

/// 原生资源按使用者借用；空闲 LRU 可淘汰，正在销毁的实例仍占额度。
class ResourcePool<K, V> {
  ResourcePool({
    required this.maximum,
    required this.idleTimeout,
    required this.create,
    required this.destroy,
    required this.onDisposeError,
  }) : assert(maximum > 0);

  final int maximum;
  final Duration idleTimeout;
  final V Function(K) create;
  final Future<void> Function(V) destroy;
  final void Function(Object, StackTrace) onDisposeError;
  final _entries = <K, _ResourceEntry<V>>{};
  final _closing = <Future<void>>{};
  Completer<void> _changed = Completer<void>();
  bool _closed = false;
  int _waiting = 0;

  int get retained => _entries.length;
  int get closing => _closing.length;
  int get waiting => _waiting;
  int get active => _entries.values.where((entry) => entry.users > 0).length;
  Iterable<K> get keys => _entries.keys;
  Iterable<V> get values => _entries.values.map((entry) => entry.value);

  void _wake() {
    final previous = _changed;
    _changed = Completer<void>();
    previous.complete();
  }

  Future<T> use<T>(
    K key,
    Future<T> Function(V) operation, {
    CancelToken? cancelToken,
  }) async {
    late _ResourceEntry<V> entry;
    while (true) {
      if (_closed) throw SourceError('CANCELLED', '资源池已关闭');
      if (cancelToken?.cancelError case final error?) throw error;
      final existing = _entries.remove(key);
      if (existing != null) {
        entry = existing;
        // 使用顺序即 LRU，不能只按创建顺序淘汰。
        _entries[key] = entry;
        break;
      }
      if (_entries.length + _closing.length < maximum) {
        entry = _ResourceEntry(create(key));
        _entries[key] = entry;
        break;
      }
      final idle = _entries.entries
          .where((candidate) => candidate.value.users == 0)
          .firstOrNull;
      if (idle != null) {
        await _retire(idle.key, idle.value);
        continue;
      }
      _waiting++;
      try {
        await awaitCancelled(_changed.future, cancelToken);
      } finally {
        _waiting--;
      }
    }
    entry.idle?.cancel();
    entry.users++;
    try {
      return await operation(entry.value);
    } finally {
      entry.users--;
      if (entry.users == 0 && identical(_entries[key], entry)) {
        entry.idle = Timer(idleTimeout, () {
          unawaited(_retire(key, entry).catchError(onDisposeError));
        });
      }
      _wake();
    }
  }

  Future<void> _retire(K key, _ResourceEntry<V> entry) {
    if (!identical(_entries[key], entry)) return Future.value();
    _entries.remove(key);
    entry.idle?.cancel();
    final done = Completer<void>();
    _closing.add(done.future);
    // 先登记销毁状态，再调用原生 API，避免创建和销毁的异步窗口突破上限。
    unawaited(() async {
      try {
        await destroy(entry.value);
        done.complete();
      } catch (error, stack) {
        done.completeError(error, stack);
      } finally {
        _closing.remove(done.future);
        _wake();
      }
    }());
    return done.future;
  }

  Future<void> removeWhere(bool Function(K) matches) async {
    final entries = _entries.entries
        .where((entry) => matches(entry.key))
        .toList();
    await Future.wait([
      for (final entry in entries) _retire(entry.key, entry.value),
    ]);
  }

  Future<void> close() async {
    _closed = true;
    _wake();
    final pending = _closing.toList();
    await Future.wait([removeWhere((_) => true), ...pending]);
  }
}

class _ResourceEntry<V> {
  _ResourceEntry(this.value);
  final V value;
  int users = 0;
  Timer? idle;
}
