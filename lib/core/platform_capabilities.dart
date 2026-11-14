import 'package:flutter/foundation.dart';

/// 能力只描述已接入的实现，不以宿主目录存在作为支持依据。
abstract final class PlatformCapabilities {
  static bool get secureScreen =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get volumeKeyPaging =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get screenBrightness =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get desktop => false;

  static bool get nativeVideo =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get photoLibrary =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}
