import 'package:flutter/foundation.dart';

/// 能力只描述已接入的实现，不以宿主目录存在作为支持依据。
abstract final class PlatformCapabilities {
  static bool get secureScreen =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get volumeKeyPaging =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get screenBrightness =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get desktop =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.windows ||
        TargetPlatform.macOS ||
        TargetPlatform.linux => true,
        _ => false,
      };

  static bool get nativeVideo =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.android ||
        TargetPlatform.iOS ||
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.linux => true,
        _ => false,
      };

  static bool get photoLibrary =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.android || TargetPlatform.iOS => true,
        _ => false,
      };

  static bool get androidBackground =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}
