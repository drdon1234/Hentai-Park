import 'package:flutter/foundation.dart';

/// 能力只描述已接入的实现，不以宿主目录存在作为支持依据。
abstract final class PlatformCapabilities {
  static bool get secureScreen =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get volumeKeyPaging =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get screenBrightness => !kIsWeb && _mobile;

  static bool get desktop => false;

  /// Android 在系统导航栏下方保留应用底色条；iOS 的主屏幕指示条浮在内容之上，内容延伸到屏幕底边。
  static bool get systemNavigationStrip =>
      kIsWeb || defaultTargetPlatform != TargetPlatform.iOS;

  static bool get nativeVideo => !kIsWeb && _mobile;

  static bool get photoLibrary => !kIsWeb && _mobile;

  static bool get _mobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}
