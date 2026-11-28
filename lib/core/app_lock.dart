import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';

import '../engine/platform_bridge.dart';
import 'app_log.dart';
import 'app_visibility.dart';
import 'localization.dart';
import 'settings.dart';

/// Mihon's app lock: biometrics / device credential on launch and after the app was in the
/// background longer than the configured delay.
class AppLock extends ChangeNotifier with WidgetsBindingObserver {
  AppLock._();
  static final AppLock instance = AppLock._();

  final _auth = LocalAuthentication();
  bool _locked = false;
  bool _authenticating = false;
  DateTime? _backgroundSince;

  bool get locked => _locked;
  static bool get platformSupported => Platform.isAndroid || Platform.isIOS;

  void init() {
    WidgetsBinding.instance.addObserver(this);
    _locked = platformSupported && AppSettings.instance.appLock;
  }

  /// Whether the device can authenticate at all (biometrics or a screen lock is set up).
  Future<bool> available() async {
    if (!platformSupported) return false;
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate({String reason = '验证身份以解锁 HentaiPark'}) async {
    if (_authenticating) return false;
    _authenticating = true;
    await PlatformBridge.setAuthenticating(true);
    try {
      return await _auth.authenticate(
        localizedReason: tr(reason),
        persistAcrossBackgrounding: true,
      );
    } catch (e) {
      AppLog.error(e, event: 'app_lock');
      return false;
    } finally {
      _authenticating = false;
      unawaited(PlatformBridge.setAuthenticating(false));
      final state = WidgetsBinding.instance.lifecycleState;
      if (state != null && isAppVisible(state)) {
        _checkRelockOnResume();
      }
    }
  }

  Future<void> unlock() async {
    if (!_locked) return;
    if (await authenticate()) {
      _locked = false;
      _backgroundSince = null;
      notifyListeners();
    }
  }

  /// Turning the lock on requires a successful authentication first, so users cannot lock themselves out.
  Future<bool> enable() async {
    if (!await available()) return false;
    if (!await authenticate(reason: '验证身份以开启应用锁')) return false;
    AppSettings.instance.appLock = true;
    return true;
  }

  void disable() {
    AppSettings.instance.appLock = false;
    _locked = false;
    _backgroundSince = null;
    notifyListeners();
  }

  void _checkRelockOnResume() {
    if (!platformSupported || !AppSettings.instance.appLock) return;
    final since = _backgroundSince;
    _backgroundSince = null;
    if (since != null &&
        DateTime.now().difference(since).inSeconds >=
            AppSettings.instance.appLockAfter) {
      _locked = true;
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!platformSupported || !AppSettings.instance.appLock) {
      return;
    }
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        // 即使认证弹窗正在展示，真正切入后台也必须记录时间戳，防止取消认证后绕过重锁。
        _backgroundSince ??= DateTime.now();
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        if (!_authenticating && isAppVisible(state)) _checkRelockOnResume();
      default:
        break;
    }
  }
}
