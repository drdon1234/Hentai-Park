/// Android 通知由原生桥处理；其他平台暂不提供原生通知实现。
class NativeNotifications {
  NativeNotifications._();
  static final instance = NativeNotifications._();
  void Function(String)? onTap;

  Future<void> init() async {}
  Future<bool> requestPermission() async => false;
  String? takeLaunchPayload() => null;
  Future<bool> show({
    required int id,
    required String title,
    String body = '',
    String? payload,
  }) async => false;
  Future<void> cancel(int id) async {}
}
