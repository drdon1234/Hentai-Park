import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../core/platform_capabilities.dart';
import '../core/settings.dart';
import '../game/downloads.dart';
import '../library/downloads.dart';
import '../library/library.dart';
import 'source_manager.dart';

/// 原生桌面窗口关闭前等待已排队的数据写入；最小化仍由页面生命周期暂停播放。
class DesktopWindow with WindowListener {
  DesktopWindow._();
  static final instance = DesktopWindow._();
  bool _closing = false;

  Future<void> init() async {
    if (!PlatformCapabilities.desktop) return;
    await windowManager.ensureInitialized();
    await windowManager.setTitle('HentaiPark');
    await windowManager.setMinimumSize(const Size(360, 480));
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
  }

  @override
  void onWindowClose() async {
    if (_closing) return;
    _closing = true;
    try {
      // 先通知当前阅读/播放页面保存位置，再排空公共持久化队列。
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.inactive,
      );
      await Future.wait([
        DownloadManager.instance.pauseAndFlush(),
        GameDownloadManager.instance.pauseAndFlush(),
      ]);
      await Future.wait([
        AppSettings.instance.flush(),
        Library.instance.flush(),
        DownloadManager.instance.flush(),
        SourceManager.instance.flush(),
        GameDownloadManager.instance.flush(),
      ]);
      await windowManager.destroy();
    } catch (_) {
      // 写入失败时保留窗口与数据，让用户仍能导出或重试退出。
      _closing = false;
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
    }
  }
}
