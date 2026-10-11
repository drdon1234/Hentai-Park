import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Small Android-only native hooks (MainActivity): screenshot protection, volume-key paging and
/// plain system notifications.
class PlatformBridge {
  static const _channel = MethodChannel('hentai_park/platform');
  static final _volume = StreamController<int>.broadcast();
  static final _taps = StreamController<String>.broadcast();
  static bool _listening = false;

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'volumeKey':
          _volume.add(call.arguments as int);
        case 'notificationTap':
          _taps.add(call.arguments.toString());
      }
    });
  }

  /// Hides content in the recent-apps switcher and blocks screenshots (FLAG_SECURE).
  static Future<void> applySecureScreen(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setSecure', enabled);
    } catch (_) {}
  }

  // ── Display ──

  /// Refresh rates (Hz) the display supports at the current resolution; empty if unknown.
  static Future<List<int>> refreshRates() async {
    if (!Platform.isAndroid) return const [];
    try {
      return ((await _channel.invokeMethod<List>('refreshRates')) ?? const []).map((e) => (e as num).toInt()).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<double?> currentRefreshRate() async {
    if (!Platform.isAndroid) return null;
    try {
      return (await _channel.invokeMethod<num>('currentRefreshRate'))?.toDouble();
    } catch (_) {
      return null;
    }
  }

  /// Asks for [hz] (0 = the highest available). Many high-refresh phones keep apps at 60 Hz otherwise.
  static Future<void> applyRefreshRate(int hz) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setRefreshRate', hz);
    } catch (_) {}
  }

  /// Emits -1 for volume-up and +1 for volume-down while intercepting is enabled.
  static Stream<int> get volumeKeys {
    _listen();
    return _volume.stream;
  }

  static Future<void> interceptVolumeKeys(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('interceptVolume', enabled);
    } catch (_) {}
  }

  // ── Notifications ──

  /// Payloads of tapped notifications while the app is running.
  static Stream<String> get notificationTaps {
    _listen();
    return _taps.stream;
  }

  /// The payload of the notification that launched the app, if any (returned once).
  static Future<String?> takeLaunchPayload() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('takeLaunchPayload');
    } catch (_) {
      return null;
    }
  }

  /// Asks for POST_NOTIFICATIONS on Android 13+; true when already granted.
  static Future<bool> requestNotificationPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('requestNotificationPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> notify({
    required int id,
    required String title,
    String text = '',
    bool ongoing = false,
    int progress = 0,
    int max = 0,
    String? payload,
    String channel = 'library',
    String channelName = '书库更新',
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('notify', {
        'id': id,
        'title': title,
        'text': text,
        'ongoing': ongoing,
        'progress': progress,
        'max': max,
        'payload': payload,
        'channel': channel,
        'channelName': channelName,
      });
    } catch (_) {}
  }

  static Future<void> cancelNotification(int id) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('cancelNotification', id);
    } catch (_) {}
  }
}
