import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;

import '../core/app_log.dart';
import '../core/diagnostic_entry.dart';
import '../core/localization.dart';
import '../core/settings.dart';
import 'native_notifications.dart';

/// 顶部栏布局区域：距顶、左右让位与栏高。
typedef TopBarRegion = ({double top, double left, double right, double height});

/// 移动平台原生能力；平台限制由实际实现和能力声明决定。
class PlatformBridge {
  static const _channel = MethodChannel('hentai_park/platform');
  static Future<bool> Function()? refreshSubscriptions;

  /// iOS 顶部栏布局区域（逻辑像素）：状态区只占一角时（iPhone Duo 内屏）导航栏可与之同排；
  /// 常规设备为 null，按安全区布局。
  static final topBarRegion = ValueNotifier<TopBarRegion?>(null);
  static bool _watchingTopBar = false;

  static Future<void> watchTopBarRegion() async {
    if (_watchingTopBar || kIsWeb || !Platform.isIOS) return;
    _watchingTopBar = true;
    _listen();
    try {
      _setTopBarRegion(await _channel.invokeMethod<Object?>('topBarRegion'));
    } catch (_) {}
  }

  static void _setTopBarRegion(Object? value) {
    if (value is! Map) {
      topBarRegion.value = null;
      return;
    }
    double read(String key) => (value[key] as num?)?.toDouble() ?? 0;
    final region = (
      top: read('top'),
      left: read('left'),
      right: read('right'),
      height: read('height'),
    );
    topBarRegion.value = region.height > 0 ? region : null;
  }

  static void Function()? cancelSubscriptionRefresh;

  static Future<bool> startVoicePlayback(String id) async {
    _listen();
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    try {
      return await _channel.invokeMethod<bool>('startVoicePlayback', {
            'id': id,
            'text': tr('音声'),
            'play': tr('播放'),
            'pause': tr('暂停'),
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stopVoicePlayback(String id) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('stopVoicePlayback', id);
    } catch (_) {}
  }

  static Future<void> updateVoicePlayback(
    String id,
    bool playing, {
    required bool available,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('updateVoicePlayback', {
        'id': id,
        'playing': playing,
        'available': available,
      });
    } catch (_) {}
  }

  static Future<List<DiagnosticEntry>> readCrashDiagnostics() async {
    if (!Platform.isAndroid) return const [];
    try {
      final values = await _channel.invokeListMethod<Object?>(
        'readCrashDiagnostics',
      );
      return [
        for (final value in values ?? const [])
          ?DiagnosticEntry.fromJson(value),
      ];
    } catch (error, stack) {
      AppLog.error(error, event: 'native_diagnostics', stack: stack);
      return const [];
    }
  }

  static final _wakes = StreamController<void>.broadcast();
  static final _volume = StreamController<int>.broadcast();
  static final _taps = StreamController<String>.broadcast();
  static final _mediaVolume = StreamController<double>.broadcast();
  static final _voiceControls =
      StreamController<({String id, String action})>.broadcast();
  static Stream<({String id, String action})> get voiceControls {
    _listen();
    return _voiceControls.stream;
  }

  static Future<void> _videoBrightnessUpdates = Future.value();
  static bool _listening = false;
  static bool _settingsBound = false;
  static bool? _secureScreen;
  static int? _refreshRate;
  static int? _subscriptionHours;
  static String? _proxy;
  static bool? _webViewProxySupported;
  static Future<void> _settingsUpdates = Future.value();

  static bool? get webViewProxySupported => _webViewProxySupported;

  /// Apply device preferences at startup and after every change, including backup restore.
  static Future<void> bindSettings() {
    if (!_settingsBound) {
      _settingsBound = true;
      AppSettings.instance
          .watch(const {
            'secureScreen',
            'appLock',
            'refreshRate',
            'subscriptionUpdateHours',
            'proxy',
          })
          .addListener(() => unawaited(bindSettings()));
    }
    final settings = AppSettings.instance;
    final secure = settings.secureScreen || settings.appLock;
    final rate = settings.refreshRate;
    final hours = settings.subscriptionUpdateHours;
    final proxy = settings.proxy;
    final schedule = hours != _subscriptionHours;
    _subscriptionHours = hours;
    final updateSecure = secure != _secureScreen;
    final updateRate = rate != _refreshRate;
    final updateProxy = proxy != _proxy;
    _secureScreen = secure;
    _refreshRate = rate;
    _proxy = proxy;
    return _settingsUpdates = _settingsUpdates.then((_) async {
      if (updateSecure) await applySecureScreen(secure);
      if (updateRate) await applyRefreshRate(rate);
      if (updateProxy) await applyWebViewProxy(proxy);
      if (schedule && (Platform.isAndroid || Platform.isIOS)) {
        try {
          await _channel.invokeMethod<void>('scheduleSubscriptions', hours);
        } catch (_) {
          _subscriptionHours = null;
        }
      }
    });
  }

  /// Parses an HTTP proxy setting into discrete endpoint fields for WebView.
  static ({String host, int port, String username, String password})?
  parseHttpProxy(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final normalized =
        RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)
        ? trimmed
        : 'http://$trimmed';
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        uri.host.isEmpty ||
        !uri.hasPort ||
        uri.port < 1 ||
        uri.port > 65535) {
      return null;
    }
    var username = '';
    var password = '';
    if (uri.userInfo.isNotEmpty) {
      final sep = uri.userInfo.indexOf(':');
      if (sep < 0) {
        username = Uri.decodeComponent(uri.userInfo);
      } else {
        username = Uri.decodeComponent(uri.userInfo.substring(0, sep));
        password = Uri.decodeComponent(uri.userInfo.substring(sep + 1));
      }
    }
    return (
      host: uri.host,
      port: uri.port,
      username: username,
      password: password,
    );
  }

  static Future<bool> applyWebViewProxy(String raw) async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    final trimmed = raw.trim();
    Map<String, Object?> payload;
    if (trimmed.isEmpty) {
      payload = const {'host': ''};
    } else {
      final parsed = parseHttpProxy(trimmed);
      if (parsed == null) return false;
      payload = {
        'host': parsed.host,
        'port': parsed.port,
        if (parsed.username.isNotEmpty) 'username': parsed.username,
        if (parsed.password.isNotEmpty) 'password': parsed.password,
      };
    }
    try {
      final ok = await _channel.invokeMethod<bool>('setWebViewProxy', payload);
      _webViewProxySupported = ok;
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> notifySubscriptionEngineReady() async {
    _listen();
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('subscriptionEngineReady');
    } catch (_) {}
  }

  static Future<void> setAuthenticating(bool active) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('setAuthenticating', active);
    } catch (_) {}
  }

  static Future<void> excludeFromBackup(List<String> paths) async {
    if (!Platform.isIOS || paths.isEmpty) return;
    try {
      await _channel.invokeMethod<bool>('excludeFromBackup', paths);
    } catch (_) {}
  }

  static void _listen() {
    if (_listening) return;
    _listening = true;
    NativeNotifications.instance.onTap = _taps.add;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'subscriptionRefresh':
          return await refreshSubscriptions?.call() ?? false;
        case 'cancelSubscriptionRefresh':
          cancelSubscriptionRefresh?.call();
        case 'subscriptionWake':
          _wakes.add(null);
        case 'volumeKey':
          _volume.add(call.arguments as int);
        case 'notificationTap':
          _taps.add(call.arguments.toString());
        case 'topBarRegion':
          _setTopBarRegion(call.arguments);
        case 'mediaVolume':
          _mediaVolume.add((call.arguments as num).toDouble().clamp(0.0, 1.0));
        case 'voiceControl':
          final value = call.arguments;
          if (value is Map &&
              value['id'] is String &&
              value['action'] is String) {
            _voiceControls.add((
              id: value['id'] as String,
              action: value['action'] as String,
            ));
          }
      }
    });
  }

  /// Android 使用 FLAG_SECURE；iOS 仅遮盖任务切换器快照。
  static Future<void> applySecureScreen(bool enabled) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
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
  /// ignored on target SDK 36. Portrait players retain navigation; readers may
  /// still hide all bars. The same native session restores prior bar state.
  static Future<void> applyVideoFullscreen(
    bool enabled, {
    bool landscape = false,
    bool keepNavigationBar = false,
  }) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _channel.invokeMethod('setVideoFullscreen', {
          'enabled': enabled,
          'landscape': landscape,
          'keepNavigationBar': keepNavigationBar,
        });
        return;
      } catch (_) {}
    }
    await SystemChrome.setEnabledSystemUIMode(
      enabled
          ? (keepNavigationBar
                ? SystemUiMode.manual
                : SystemUiMode.immersiveSticky)
          : SystemUiMode.edgeToEdge,
      overlays: enabled && keepNavigationBar ? [SystemUiOverlay.bottom] : null,
    );
  }

  /// Hides or restores system status/navigation bars for readers without
  /// overriding or resetting the active reader orientation session.
  static Future<void> setSystemBarsHidden(bool hidden) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _channel.invokeMethod('setSystemBarsHidden', hidden);
        return;
      } catch (_) {}
    }
    await SystemChrome.setEnabledSystemUIMode(
      hidden ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  /// Restores default screen orientation: portraitUp on phones (<600dp shortest
  /// side) so exiting landscape video/game/reader actively rotates back on iOS,
  /// and unrestricted on tablets / large screens.
  static Future<void> restoreDefaultOrientations() async {
    bool isPhone = true;
    try {
      final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
      if (view != null && view.devicePixelRatio > 0) {
        final shortestSide =
            view.physicalSize.shortestSide / view.devicePixelRatio;
        isPhone = shortestSide < 600;
      }
    } catch (_) {}
    await SystemChrome.setPreferredOrientations(
      isPhone ? const [DeviceOrientation.portraitUp] : const [],
    );
  }

  /// Window-local brightness and the media stream's volume, both normalized.
  /// The native side remembers the original window brightness until reset.
  static Future<({double brightness, double volume})?> videoLevels() async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;
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
      if (!Platform.isAndroid && !Platform.isIOS) return;
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
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await _channel.invokeMethod('setVideoVolume', value.clamp(0.0, 1.0));
    } catch (_) {}
  }

  /// Restores the brightness override, including -1 (follow system brightness).
  /// Media volume remains the user's chosen system volume.
  static Future<void> resetVideoBrightness() {
    return _videoBrightnessUpdates = _videoBrightnessUpdates.then((_) async {
      if (!Platform.isAndroid && !Platform.isIOS) return;
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
    if (!Platform.isAndroid) {
      await NativeNotifications.instance.init();
      return NativeNotifications.instance.takeLaunchPayload();
    }
    try {
      return await _channel.invokeMethod<String>('takeLaunchPayload');
    } catch (_) {
      return null;
    }
  }

  /// Asks for POST_NOTIFICATIONS on Android 13+; true when already granted.
  static Future<bool> requestNotificationPermission() async {
    if (!Platform.isAndroid) {
      return NativeNotifications.instance.requestPermission();
    }
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
    if (!Platform.isAndroid) {
      // iOS 无常驻静默通知栏进度条；忽略逐项 ongoing 进度通知，仅发送完成汇总通知。
      if (ongoing) return;
      await NativeNotifications.instance.show(
        id: id,
        title: title,
        body: text,
        payload: payload,
      );
      return;
    }
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
    if (!Platform.isAndroid) return NativeNotifications.instance.cancel(id);
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
    if (!Platform.isAndroid) {
      return NativeNotifications.instance.show(
        id: id,
        title: title,
        body: text,
        payload: payload,
      );
    }
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
