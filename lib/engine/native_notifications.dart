import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/app_log.dart';

/// iOS 系统通知；Android 使用原生桥，避免重复注册通知处理器。
class NativeNotifications {
  NativeNotifications._();
  static final instance = NativeNotifications._();
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _initializing;
  bool _ready = false;
  String? _launchPayload;
  void Function(String)? onTap;

  Future<void> init() => _initializing ??= _init();

  Future<void> _init() async {
    if (!Platform.isIOS) return;
    try {
      _ready =
          await _plugin.initialize(
            settings: const InitializationSettings(
              iOS: DarwinInitializationSettings(
                requestAlertPermission: false,
                requestBadgePermission: false,
                requestSoundPermission: false,
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
      AppLog.error(error, event: 'native_notifications');
    }
  }

  Future<bool> requestPermission() async {
    await init();
    if (!_ready) return false;
    return await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true) ??
        false;
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
      final permission = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.checkPermissions();
      if (permission?.isEnabled != true) return false;
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          iOS: DarwinNotificationDetails(),
        ),
        payload: payload,
      );
      return true;
    } catch (error) {
      AppLog.error(error, event: 'native_notifications');
      return false;
    }
  }

  Future<void> cancel(int id) async {
    await init();
    if (_ready) await _plugin.cancel(id: id);
  }
}
