import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../core/localization.dart';
import '../core/settings.dart';
import '../core/storage.dart';
import '../data/database.dart';
import '../engine/cookie_store.dart';
import '../engine/http_service.dart';
import '../engine/js_engine.dart';
import '../engine/source_manager.dart';
import '../library/library.dart';
import 'subscription_store.dart';
import 'updater.dart';

/// Android 无界面入口与前台共用源沙箱、Cookie 分区和检查器。
@pragma('vm:entry-point')
Future<void> subscriptionBackground() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('hentai_park/subscription_background');
  final updater = SubscriptionUpdater.instance;
  channel.setMethodCallHandler((call) async {
    if (call.method == 'cancel') updater.cancel();
  });
  AppDatabase? db;
  try {
    await AppPaths.init();
    await AppSettings.instance.load();
    if (AppSettings.instance.subscriptionUpdateHours == 0 ||
        updater.cancelled) {
      return;
    }
    await AppLocalizations.instance.load();
    AppLocalizations.instance.setLocale(
      AppSettings.instance.locale ?? const Locale('zh', 'CN'),
    );
    db = AppDatabase.file(File(p.join(AppPaths.data.path, 'park.db')));
    await Library.instance.open(db);
    await SubscriptionStore.instance.load();
    final keys = SubscriptionStore.instance.items
        .where((e) => e.enabled)
        .map((e) => e.source)
        .toSet();
    if (keys.isEmpty || updater.cancelled) return;
    await CookieStore.instance.init();
    HttpService.instance.init();
    await SourceManager.instance.init(backgroundKeys: keys);
    if (!updater.cancelled) await updater.run();
  } catch (_) {
    // 不记录远端正文、Cookie 或原始异常。失败目标由检查器保存安全错误码。
  } finally {
    try {
      for (final s in SourceManager.instance.enabled) {
        await JsEngine.instance.disposeRuntime(s.key);
      }
      await SourceManager.instance.flush();
    } finally {
      try {
        await db?.close();
      } finally {
        await channel.invokeMethod<void>('finished');
      }
    }
  }
}
