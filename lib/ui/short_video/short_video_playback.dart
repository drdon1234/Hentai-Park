import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/models.dart';

abstract interface class ShortVideoHandle {
  Future<void> play();
  Future<void> pause();
  Future<void> close();
}

typedef ShortVideoOpener = Future<ShortVideoHandle> Function(
  WorkItem item,
  CancelToken cancel,
);

class _Slot {
  _Slot(this.item);
  final WorkItem item;
  final CancelToken cancel = CancelToken();
  late Future<void> ready;
  ShortVideoHandle? handle;
  Object? error;
}

/// 最多两个资源（当前及下一条）；过期初始化也必须关闭后才能补充新资源。
class ShortVideoPlayback extends ChangeNotifier {
  ShortVideoPlayback(this._open);
  final ShortVideoOpener _open;
  final _slots = <String, _Slot>{};
  final _retiring = <Future<void>>[];
  Future<void> _maintenance = Future.value(), _commands = Future.value();
  WorkItem? _current, _next;
  bool _enabled = true, _wants = true, _closed = false, _disposed = false;
  int get count => _slots.length;
  bool get wantsPlayback => _wants;
  ShortVideoHandle? handle(String uid) => _slots[uid]?.handle;
  Object? error(String uid) => _slots[uid]?.error;
  void _notify() {
    if (!_disposed && !_closed) notifyListeners();
  }

  Future<void> get settled => _maintenance.then((_) async {
    await Future.wait(_slots.values.map((s) => s.ready).toList());
    await _sync();
  });

  Future<void> select(WorkItem? current, WorkItem? next) {
    if (_closed) return Future.value();
    if (_current?.uid != current?.uid) _wants = true;
    _current = current;
    _next = next?.uid == current?.uid ? null : next;
    final desired = {
      if (current != null) current.uid,
      if (_next != null) _next!.uid,
    };
    for (final uid in _slots.keys.toList()) {
      if (!desired.contains(uid)) _retire(_slots.remove(uid)!);
    }
    // 停旧声音不等待下一个网络初始化。
    unawaited(_sync());
    _maintenance = _maintenance.then((_) async {
      final retiring = _retiring.toList();
      await Future.wait(retiring);
      _retiring.removeWhere(retiring.contains);
      if (_closed) return;
      for (final item in [_current, _next]) {
        if (item == null || _slots.containsKey(item.uid)) continue;
        final slot = _Slot(item);
        _slots[item.uid] = slot;
        slot.ready = _load(slot);
      }
      _notify();
    });
    return settled;
  }

  Future<void> _load(_Slot slot) async {
    try {
      final handle = await _open(slot.item, slot.cancel);
      if (_closed ||
          slot.cancel.isCancelled ||
          !identical(_slots[slot.item.uid], slot)) {
        await handle.close();
        return;
      }
      slot.handle = handle;
    } catch (e) {
      if (!slot.cancel.isCancelled && !_closed) {
        slot.error = e is SourceError ? e : SourceError('NETWORK', '短视频播放失败');
      }
    }
    _notify();
    unawaited(_sync());
  }

  void _retire(_Slot slot) {
    slot.cancel.cancel('short video no longer visible');
    // 已初始化的旧播放器立即排队停止，不等待其他加载。
    if (slot.handle case final handle?) {
      _commands = _commands
          .then((_) async {
            await handle.pause().whenComplete(handle.close);
          })
          .catchError((Object _) {});
      _retiring.add(_commands);
    } else {
      _retiring.add(slot.ready.then((_) async => slot.handle?.close()));
    }
  }

  Future<void> _sync() {
    return _commands = _commands.then((_) async {
      final slots = _slots.values.toList();
      for (final slot in slots) {
        final h = slot.handle;
        if (h == null) continue;
        try {
          if (_closed ||
              !_enabled ||
              !_wants ||
              slot.item.uid != _current?.uid ||
              slot.cancel.isCancelled) {
            await h.pause();
          }
        } catch (_) {
          slot.error = SourceError('NETWORK', '短视频播放失败');
        }
      }
      final slot = _slots[_current?.uid];
      if (!_closed &&
          _enabled &&
          _wants &&
          slot != null &&
          !slot.cancel.isCancelled &&
          slot.handle != null) {
        try {
          await slot.handle!.play();
        } catch (_) {
          slot.error = SourceError('NETWORK', '短视频播放失败');
          _notify();
        }
      }
    });
  }

  Future<void> setEnabled(bool value) {
    _enabled = value;
    return _sync();
  }

  Future<void> toggle() {
    _wants = !_wants;
    _notify();
    return _sync();
  }

  Future<void> retry() {
    final slot = _slots.remove(_current?.uid);
    if (slot != null) _retire(slot);
    return select(_current, _next);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final slot in _slots.values.toList()) {
      _retire(slot);
    }
    _slots.clear();
    await _maintenance;
    await Future.wait(_retiring.toList());
    await _commands;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(close());
    super.dispose();
  }
}
