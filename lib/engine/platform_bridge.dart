import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/localization.dart';
import '../core/settings.dart';

/// Small Android-only native hooks (MainActivity): screenshot protection, volume-key paging and
/// plain system notifications.
class PlatformBridge {
  static const _channel = MethodChannel('hentai_park/platform');
  static final _wakes = StreamController<void>.broadcast();
  static final _volume = StreamController<int>.broadcast();
  static final _taps = StreamController<String>.broadcast();
  static final _mediaVolume = StreamController<double>.broadcast();
  static Future<void> _videoBrightnessUpdates = Future.value();
  static bool _listening = false;
  static bool _settingsBound = false;
  static bool? _secureScreen;
  static int? _refreshRate;
  static int? _subscriptionHours;
  static Future<void> _settingsUpdates = Future.value();

  /// Apply device preferences at startup and after every change, including backup restore.
  static Future<void> bindSettings() {
    if (!_settingsBound) {
      _settingsBound = true;
      AppSettings.instance.addListener(() => unawaited(bindSettings()));
    }
    final settings = AppSettings.instance;
    final secure = settings.secureScreen || settings.appLock;
    final rate = settings.refreshRate;
    final hours = settings.subscriptionUpdateHours;
    final schedule = hours != _subscriptionHours;
    _subscriptionHours = hours;
    final updateSecure = secure != _secureScreen;
    final updateRate = rate != _refreshRate;
    _secureScreen = secure;
    _refreshRate = rate;
    return _settingsUpdates = _settingsUpdates.then((_) async {
      if (updateSecure) await applySecureScreen(secure);
      if (updateRate) await applyRefreshRate(rate);
      if (schedule && Platform.isAndroid) {
        try {
          await _channel.invokeMethod<void>('scheduleSubscriptions', hours);
        } catch (_) {
          _subscriptionHours = null;
        }
      }
    });
  }

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'subscriptionWake':
          _wakes.add(null);
        case 'volumeKey':
          _volume.add(call.arguments as int);
        case 'notificationTap':
          _taps.add(call.arguments.toString());
        case 'mediaVolume':
          _mediaVolume.add((call.arguments as num).toDouble().clamp(0.0, 1.0));
      }
    });
  }

  /// Hides content in the recent-apps switcher and blocks screenshots (FLAG_SECURE).
  static Future<void> applySecureScreen(bool enabled) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod('setSecure', enabled);
    } catch (_) {}
  }

  // ── Display ──

  /// Refresh rates (Hz) the display supports at the current resolution; empty if unknown.
  static Future<List<int>> refreshRates() async {
    if (!Platform.isAndroid) return const [];
    try {
      return ((await _channel.invokeMethod<List>('refreshRates')) ?? const [])
          .map((e) => (e as num).toInt())
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<double?> currentRefreshRate() async {
    if (!Platform.isAndroid) return null;
    try {
      return (await _channel.invokeMethod<num>('currentRefreshRate'))
          ?.toDouble();
    } catch (_) {
      return null;
    }
  }

  /// Asks for [hz] (0 = the highest available). Many high-refresh phones keep apps at 60 Hz otherwise.
  static Future<void> applyRefreshRate(int hz) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod('setRefreshRate', hz);
    } catch (_) {}
  }

  /// Native wake events are coordinated by the application, not the bridge.
  static Stream<void> get subscriptionWakes {
    _listen();
    return _wakes.stream;
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

  // ── Video controls ──

  /// Android uses its current insets API: Flutter's immersiveSticky request is
  /// ignored on target SDK 36. The same native session restores prior bar state.
  static Future<void> applyVideoFullscreen(bool enabled) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _channel.invokeMethod('setVideoFullscreen', enabled);
        return;
      } catch (_) {}
    }
    await SystemChrome.setEnabledSystemUIMode(
      enabled ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  /// Window-local brightness and the media stream's volume, both normalized.
  /// The native side remembers the original window brightness until reset.
  static Future<({double brightness, double volume})?> videoLevels() async {
    if (!Platform.isAndroid) return null;
    await _videoBrightnessUpdates;
    try {
      final levels = await _channel.invokeMapMethod<String, num>('videoLevels');
      if (levels == null) return null;
      return (
        brightness: (levels['brightness'] ?? 0.5).toDouble().clamp(0.0, 1.0),
        volume: (levels['volume'] ?? 1).toDouble().clamp(0.0, 1.0),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> setVideoBrightness(double value) {
    return _videoBrightnessUpdates = _videoBrightnessUpdates.then((_) async {
      if (!Platform.isAndroid) return;
      try {
        await _channel.invokeMethod(
          'setVideoBrightness',
          value.clamp(0.0, 1.0),
        );
      } catch (_) {}
    });
  }

  /// Physical volume buttons update the gesture's starting volume as well.
  static Stream<double> get mediaVolumeChanges {
    _listen();
    return _mediaVolume.stream;
  }

  static Future<void> setVideoVolume(double value) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setVideoVolume', value.clamp(0.0, 1.0));
    } catch (_) {}
  }

  /// Restores the brightness override, including -1 (follow system brightness).
  /// Media volume remains the user's chosen system volume.
  static Future<void> resetVideoBrightness() {
    return _videoBrightnessUpdates = _videoBrightnessUpdates.then((_) async {
      if (!Platform.isAndroid) return;
      try {
        await _channel.invokeMethod('resetVideoBrightness');
      } catch (_) {}
    });
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
      return await _channel.invokeMethod<bool>(
            'requestNotificationPermission',
          ) ??
          false;
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
        'channelName': tr(channelName),
      });
    } catch (_) {}
  }

  static Future<void> cancelNotification(int id) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('cancelNotification', id);
    } catch (_) {}
  }

  static Future<bool> notifyChecked({
    required int id,
    required String title,
    required String text,
    required String payload,
    required String channel,
    required String channelName,
  }) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('notifyChecked', {
            'id': id,
            'title': title,
            'text': text,
            'payload': payload,
            'channel': channel,
            'channelName': tr(channelName),
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
