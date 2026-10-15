import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/app_log.dart';

/// 非 Android 原生通知；Android 保留现有原生桥。
class NativeNotifications {
  NativeNotifications._();
  static final instance = NativeNotifications._();
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  Future<void>? _initializing;
  String? _launchPayload;
  void Function(String)? onTap;

  Future<void> init() => _initializing ??= _init();

  Future<void> _init() async {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.android) return;
    try {
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      _ready =
          await _plugin.initialize(
            settings: const InitializationSettings(
              iOS: darwin,
              macOS: darwin,
              linux: LinuxInitializationSettings(
                defaultActionName: 'HentaiPark',
              ),
              windows: WindowsInitializationSettings(
                appName: 'HentaiPark',
                appUserModelId: 'com.hentaipark.HentaiPark',
                guid: '5d9b4f8e-7d8d-4e0e-b9b4-0ccdf7a3f4b2',
              ),
            ),
            onDidReceiveNotificationResponse: (response) {
              final payload = response.payload;
              if (payload != null) onTap?.call(payload);
            },
          ) ??
          false;
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        _launchPayload = launch?.notificationResponse?.payload;
      }
    } catch (error) {
      AppLog.error(error, event: 'notifications');
    }
  }

  Future<bool> requestPermission() async {
    try {
      return await _requestPermission();
    } catch (error) {
      AppLog.error(error, event: 'notifications');
      return false;
    }
  }

  Future<bool> _requestPermission() async {
    await init();
    if (!_ready) return false;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    // Desktop notification services control permission in system settings.
    return true;
  }

  String? takeLaunchPayload() {
    final payload = _launchPayload;
    _launchPayload = null;
    return payload;
  }

  Future<bool> show({
    required int id,
    required String title,
    String body = '',
    String? payload,
  }) async {
    await init();
    if (!_ready) return false;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: const NotificationDetails(
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
          linux: LinuxNotificationDetails(),
          windows: WindowsNotificationDetails(),
        ),
      );
      return true;
    } catch (error) {
      AppLog.error(error, event: 'notifications');
      return false;
    }
  }

  Future<void> cancel(int id) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancel(id: id);
    } catch (error) {
      AppLog.error(error, event: 'notifications');
    }
  }
}
