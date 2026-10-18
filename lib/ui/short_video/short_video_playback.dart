import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/models.dart';
import '../../engine/desktop_shutdown.dart';

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
  final finished = Completer<void>();
  Future<void> get ready => finished.future;
  bool started = false, playing = false;
  ShortVideoHandle? handle;
  Object? error;
}

/// 当前视频优先，后台最多两个并发；保留最近播放的资源及其缓冲。
/// 已取消但尚未关闭的资源仍计入上限，避免快速滑动无限创建播放器。
class ShortVideoPlayback extends ChangeNotifier {
  ShortVideoPlayback(this._open, {int preloadCount = 2, int retainedCount = 2})
    : _preloadCount = RangeError.checkNotNegative(preloadCount),
      _retainedCount = RangeError.checkNotNegative(retainedCount);
  final ShortVideoOpener _open;
  final _slots = <String, _Slot>{};
  final _live = <_Slot>{}, _opening = <_Slot>{};
  final _retiring = <Future<void>>{};
  final _recent = <WorkItem>[];
  List<WorkItem> _upcoming = [];
  Future<void> _commands = Future.value();
  Future<void>? _closing;
  WorkItem? _current;
  int _preloadCount, _retainedCount;
  bool _enabled = true, _wants = true, _closed = false, _disposed = false;
  int get count => _slots.length;
  bool get wantsPlayback => _wants;
  ShortVideoHandle? handle(String uid) => _slots[uid]?.handle;
  Object? error(String uid) => _slots[uid]?.error;
  void _notify() {
    if (!_disposed && !_closed) notifyListeners();
  }

  Future<void> get settled async {
    await Future.wait([
      for (final slot in _slots.values)
        if (slot.started || _enabled || slot.item.uid == _current?.uid)
          slot.ready,
      ..._retiring,
    ]);
    await _sync();
  }

  Future<void> setLimits({
    required int preloadCount,
    required int retainedCount,
  }) {
    _preloadCount = RangeError.checkNotNegative(preloadCount);
    _retainedCount = RangeError.checkNotNegative(retainedCount);
    return select(_current, _upcoming);
  }

  Future<void> select(WorkItem? current, Iterable<WorkItem> upcoming) {
    if (_closed) return Future.value();
    if (_current?.uid != current?.uid) {
      _wants = true;
      final old = _current;
      // 一掠而过、尚未加载好的视频不占用已看缓存。
      if (old != null && _slots[old.uid]?.handle != null) {
        _recent.removeWhere((item) => item.uid == old.uid);
        _recent.insert(0, old);
      }
      // 后台加载失败不妨碍当前播放；实际切入时再尝试一次。
      final failed = _slots[current?.uid];
      if (failed?.error != null) {
        _slots.remove(current!.uid);
        _retire(failed!);
      }
    }
    _current = current;
    _upcoming = upcoming.toList();
    final desired = <String, WorkItem>{};
    if (current != null) {
      desired[current.uid] = current;
      for (final item in _upcoming) {
        if (desired.length >= _preloadCount + 1) break;
        desired[item.uid] = item;
      }
      _recent.removeWhere((item) => desired.containsKey(item.uid));
      if (_recent.length > _retainedCount) {
        _recent.removeRange(_retainedCount, _recent.length);
      }
      for (final item in _recent) {
        desired[item.uid] = item;
      }
    } else {
      _recent.clear();
    }
    for (final uid in _slots.keys.toList()) {
      if (!desired.containsKey(uid)) _retire(_slots.remove(uid)!);
    }
    for (final item in desired.values) {
      _slots.putIfAbsent(item.uid, () => _Slot(item));
    }
    // 暂停/播放不等待旧播放器销毁或后台网络请求。
    unawaited(_sync());
    _pump();
    _notify();
    return settled;
  }

  void _pump() {
    if (_closed) return;
    final current = _slots[_current?.uid];
    final candidates = [
      ?current,
      for (final item in _upcoming)
        if (_slots[item.uid] case final slot?)
          if (!identical(slot, current)) slot,
    ];
    for (final slot in candidates) {
      if (slot.started || slot.cancel.isCancelled) continue;
      if (_live.length >= 1 + _preloadCount + _retainedCount) break;
      if (!identical(slot, current) &&
          (!_enabled ||
              _opening.where((s) => !identical(s, current)).length >= 2)) {
        continue;
      }
      slot.started = true;
      _live.add(slot);
      _opening.add(slot);
      unawaited(_load(slot));
    }
  }

  Future<void> _load(_Slot slot) async {
    try {
      slot.handle = await _open(slot.item, slot.cancel);
    } catch (e) {
      if (!slot.cancel.isCancelled && !_closed) {
        slot.error = e is SourceError ? e : SourceError('NETWORK', '短视频播放失败');
      }
    } finally {
      _opening.remove(slot);
      if (slot.handle == null) _live.remove(slot);
      slot.finished.complete();
      _pump();
      _notify();
      unawaited(_sync());
    }
  }

  void _retire(_Slot slot) {
    slot.cancel.cancel('short video outside cache window');
    if (!slot.started) {
      slot.finished.complete();
      return;
    }
    // 关闭资源独立于播放命令队列，否则慢关闭会卡住新视频接管。
    if (slot.handle case final handle? when slot.playing) {
      slot.playing = false;
      _commands = _commands
          .then((_) => handle.pause())
          .catchError((Object _) {});
    }
    late final Future<void> retiring;
    retiring = Future.wait([_commands, slot.ready])
        .then((_) async => slot.handle?.close())
        .catchError((Object _) {})
        .whenComplete(() {
          _live.remove(slot);
          _retiring.remove(retiring);
          _pump();
        });
    _retiring.add(retiring);
  }

  Future<void> _sync() {
    return _commands = _commands.then((_) async {
      final slots = _slots.values.toList();
      for (final slot in slots) {
        final h = slot.handle;
        if (h == null) continue;
        try {
          if (slot.playing &&
              (_closed ||
                  !_enabled ||
                  !_wants ||
                  slot.item.uid != _current?.uid ||
                  slot.cancel.isCancelled)) {
            slot.playing = false;
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
          !slot.playing &&
          slot.handle != null) {
        try {
          slot.playing = true;
          await slot.handle!.play();
        } catch (_) {
          slot.playing = false;
          slot.error = SourceError('NETWORK', '短视频播放失败');
          _notify();
        }
      }
    });
  }

  Future<void> setEnabled(bool value) {
    _enabled = value;
    _pump();
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
    return select(_current, _upcoming);
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    for (final slot in _slots.values.toList()) {
      _retire(slot);
    }
    _slots.clear();
    await Future.wait(_retiring.toList());
    await _commands;
  }

  @override
  void dispose() {
    _disposed = true;
    PendingDisposals.instance.add(close());
    super.dispose();
  }
}
