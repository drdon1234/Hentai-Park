/// 新页面等待旧页面的媒体资源释放，避免快速连续导航叠加解码器和连接。
class PlaybackRelease {
  PlaybackRelease._();
  static Future<void> _pending = Future.value();

  static Future<void> get ready => _pending;

  // 释放错误由资源所有者记录；准入等待不能因一次错误永久失效。
  static void track(Future<void> closing) {
    _pending = Future.wait([
      _pending,
      closing.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    ]).then((_) {});
  }
}
