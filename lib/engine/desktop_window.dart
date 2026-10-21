import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../core/localization.dart';
import '../core/platform_capabilities.dart';
import '../core/settings.dart';
import '../game/downloads.dart';
import '../library/backup.dart';
import '../library/downloads.dart';
import '../library/library.dart';
import '../library/live_recordings.dart';
import '../library/updater.dart';
import '../subscriptions/updater.dart';
import 'browser_fetcher.dart';
import 'desktop_shutdown.dart';
import 'js_engine.dart';
import 'source_manager.dart';

/// 原生桌面窗口关闭前等待已排队的数据写入；最小化仍由页面生命周期暂停播放。
class DesktopWindow with WindowListener {
  DesktopWindow._();
  static final instance = DesktopWindow._();
  static final navigatorKey = GlobalKey<NavigatorState>();
  bool _closing = false;
  bool _choosing = false;
  late final shutdown = DesktopShutdown(
    prepare: _prepareExit,
    detach: () async {
      // 移除整个 Navigator（包括弹窗和可见 WebView），不是只停止后台源。
      await WidgetsBinding.instance.endOfFrame;
      await PendingDisposals.instance.drain();
    },
    flush: _flush,
    stop: () async {
      await JsEngine.instance.dispose();
      await BrowserFetcher.instance.dispose();
      // 显式关闭后台 SQLite 连接及缓存语句，避免引擎退出时 finalizer 并发释放。
      await Library.instance.db.close();
      await windowManager.destroy();
    },
    resume: () async {
      JsEngine.instance.resume();
      LibraryUpdater.instance.resume();
      BackupService.instance.resume();
      SubscriptionUpdater.instance.start();
      await windowManager.show();
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
    },
  );
  static const _tray = MethodChannel('hentai_park/tray');

  Future<void> _updateTrayLabels() =>
      _tray.invokeMethod<void>('setLabels', [tr('恢复窗口'), tr('退出')]);

  Future<void> init() async {
    if (!PlatformCapabilities.desktop) return;
    await windowManager.ensureInitialized();
    await windowManager.setTitle('HentaiPark');
    await windowManager.setMinimumSize(const Size(360, 480));
    if (Platform.isWindows) {
      await _updateTrayLabels();
    }
    // 启动错误页尚无主导航；初始化成功前保留原生关闭能力。
    await windowManager.setPreventClose(true);
    if (Platform.isWindows) {
      _tray.setMethodCallHandler((call) async {
        if (call.method == 'exit') await _exit();
      });
      AppSettings.instance.watch({'language'}).addListener(_updateTrayLabels);
    }
    // 所有可能失败的初始化完成后再注册，启动重试不会重复添加监听。
    windowManager.addListener(this);
  }

  @override
  void onWindowClose() async {
    if (_closing || _choosing) return;
    if (!Platform.isWindows) return _exit();
    final context = navigatorKey.currentContext;
    if (context == null) return;
    _choosing = true;
    try {
      final canHide = await _tray.invokeMethod<bool>('isReady') ?? false;
      if (!context.mounted || _closing) return;
      final exit = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('关闭应用')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: SelectionContainer.disabled(child: Text(tr('取消'))),
            ),
            if (canHide)
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: SelectionContainer.disabled(child: Text(tr('收起到托盘'))),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: SelectionContainer.disabled(child: Text(tr('退出'))),
            ),
          ],
        ),
      );
      if (_closing) return;
      if (exit == true) {
        await _exit();
      } else if (exit == false) {
        // 原生层在隐藏前再次检查托盘，创建失败时保留可见窗口。
        await _tray.invokeMethod<bool>('hide');
      }
    } finally {
      _choosing = false;
    }
  }

  Future<void> _exit() async {
    if (_closing) return;
    _closing = true;
    try {
      await shutdown.exit();
    } finally {
      _closing = false;
    }
  }

  Future<void> _prepareExit() async {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.inactive,
    );
    await Future.wait([
      LibraryUpdater.instance.suspend(),
      SubscriptionUpdater.instance.suspend(),
      BackupService.instance.suspend(),
      DownloadManager.instance.pauseAndFlush(),
      LiveRecordings.instance.stopAll(),
      GameDownloadManager.instance.pauseAndFlush(),
    ]);
    await JsEngine.instance.suspend();
    await _flush();
  }

  Future<void> _flush() => Future.wait([
    AppSettings.instance.flush(),
    Library.instance.flush(),
    DownloadManager.instance.flush(),
    SourceManager.instance.flush(),
    GameDownloadManager.instance.flush(),
  ]);
}

/// 放在 MaterialApp.builder 内，关闭时真正销毁所有路由及其原生资源。
class DesktopShutdownGate extends StatelessWidget {
  const DesktopShutdownGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!PlatformCapabilities.desktop) return child;
    final window = DesktopWindow.instance;
    return ListenableBuilder(
      listenable: window.shutdown,
      builder: (context, _) => !window.shutdown.detached
          ? child
          : Material(
              child: Center(
                child: window.shutdown.failed
                    ? FilledButton.icon(
                        onPressed: window._exit,
                        icon: const Icon(Icons.refresh_rounded),
                        label: SelectionContainer.disabled(
                          child: Text(tr('重试')),
                        ),
                      )
                    : const CircularProgressIndicator(),
              ),
            ),
    );
  }
}
