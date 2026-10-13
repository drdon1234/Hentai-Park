import 'dart:async';

import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/async_tasks.dart';
import '../../engine/platform_bridge.dart';

/// 阅读页面统一管理设备状态；异步设置顺序执行，退出最终恢复系统状态。
class ReaderDeviceSession {
  ReaderDeviceSession({required this.onVolume});
  final void Function(int) onVolume;
  // 跨阅读页面共用队列，旧页面的延迟清理不能覆盖新页面的设备设置。
  static final _updates = SerialExecutor();
  static ReaderDeviceSession? _current;
  StreamSubscription<int>? _volume;
  bool? _wake, _keys;
  String? _orientation;
  bool _disposed = false;
  void _update(Future<void> Function() action, {bool cleanup = false}) {
    unawaited(
      _updates
          .run(() async {
            if (cleanup ? _current == null : identical(_current, this)) {
              await action();
            }
          })
          .catchError((Object _) {}),
    );
  }

  void synchronize({
    required bool keepScreenOn,
    required bool volumeKeys,
    required String orientation,
  }) {
    if (_disposed) return;
    if (!identical(_current, this)) {
      _wake = _keys = null;
      _orientation = null;
      _volume?.cancel();
      _volume = null;
    }
    _current = this;
    if (_wake != keepScreenOn) {
      _wake = keepScreenOn;
      _update(() => WakelockPlus.toggle(enable: keepScreenOn));
    }
    if (_keys != volumeKeys) {
      _keys = volumeKeys;
      _update(() => PlatformBridge.interceptVolumeKeys(volumeKeys));
      if (volumeKeys) {
        _volume = PlatformBridge.volumeKeys.listen((value) {
          if (identical(_current, this)) onVolume(value);
        });
      } else {
        _volume?.cancel();
        _volume = null;
      }
    }
    if (_orientation != orientation) {
      _orientation = orientation;
      _update(
        () => SystemChrome.setPreferredOrientations(switch (orientation) {
          'portrait' => const [
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ],
          'landscape' => const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ],
          _ => const [],
        }),
      );
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _volume?.cancel();
    if (!identical(_current, this)) return;
    _current = null;
    _update(() => PlatformBridge.interceptVolumeKeys(false), cleanup: true);
    _update(() => WakelockPlus.disable(), cleanup: true);
    _update(
      () => SystemChrome.setPreferredOrientations(const []),
      cleanup: true,
    );
  }
}
