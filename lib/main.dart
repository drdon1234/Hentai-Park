import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;

import 'core/app_lock.dart';
import 'core/crash_log.dart';
import 'core/models.dart';
import 'novel/reading_notes.dart';
import 'core/localization.dart';
import 'core/settings.dart';
import 'core/tag_translations.dart';
import 'core/storage.dart';
import 'data/database.dart';
import 'engine/cookie_store.dart';
import 'engine/http_service.dart';
import 'engine/source_manager.dart';
import 'images/image_store.dart';
import 'library/backup.dart';
import 'library/restore_transaction.dart';
import 'library/downloads.dart';
import 'game/downloads.dart';
import 'library/library.dart';
import 'library/updater.dart';
import 'ui/lock/lock_screen.dart';
import 'engine/platform_bridge.dart';
import 'ui/nav.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';
import 'subscriptions/background.dart';

@pragma('vm:entry-point')
Future<void> subscriptionBackgroundMain() => subscriptionBackground();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    await const MethodChannel('hentai_park/platform')
        .invokeMethod<void>('claimSourceEngine');
  }
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'HentaiPark (AGPL-3.0-only)',
    ], await rootBundle.loadString('LICENSE'));
    yield LicenseEntryWithLineBreaks([
      'Telegram source dependencies',
    ], await rootBundle.loadString('docs/licenses/telegram-dependencies.txt'));
    yield LicenseEntryWithLineBreaks([
      'EhTagTranslation names (CC-BY-NC-SA-3.0-CN)',
    ], await rootBundle.loadString('docs/licenses/ehtagtranslation.txt'));
  });
  await AppPaths.init();
  CrashLog.install();
  final db = AppDatabase.file(File(p.join(AppPaths.data.path, 'park.db')));
  await RestoreTransaction.recover(db);
  await AppSettings.instance.load();
  await TagTranslations.instance.init();
  await AppLocalizations.instance.load();
  AppLocalizations.instance.setLocale(
    AppSettings.instance.locale ??
        AppLocalizations.resolveLocales(
          WidgetsBinding.instance.platformDispatcher.locales,
        ),
  );
  await CookieStore.instance.init();
  HttpService.instance.init();
  await Library.instance.open(db);
  await ReadingNotes.instance.load();
  await DownloadManager.instance.load(db);
  await GameDownloadManager.instance.load();
  AppLock.instance.init();
  LibraryUpdater.instance.onFinished.add(_autoDownload);
  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  // Use the system WebView UA everywhere so Cloudflare clearance stays valid for native requests.
  try {
    final ua = await InAppWebViewController.getDefaultUserAgent();
    if (ua.isNotEmpty) {
      HttpService.instance.userAgent = ua.replaceAll('; wv)', ')');
    }
  } catch (_) {}
  // App lock also hides content in the recent-apps switcher.
  await PlatformBridge.bindSettings();
  runApp(const ParkApp());
  // Sources load after the first frame; the UI shows skeletons meanwhile.
  unawaited(
    SourceManager.instance
        .init()
        .then((_) => BackupService.instance.autoBackupIfDue())
        .catchError((Object error, StackTrace stack) {
          CrashLog.record(error, stack);
          return null;
        }),
  );
  unawaited(ImageStore.instance.trim());
}

/// "Download new chapters": queue what a library update found.
void _autoDownload(UpdateResult result) {
  if (!AppSettings.instance.autoDownloadNew) return;
  for (final u in result.updated) {
    DownloadManager.instance.enqueueNewChapters(u.item, [
      for (var i = 0; i < u.chapterIds.length; i++)
        Chapter(u.chapterIds[i], u.chapterTitles[i]),
    ]);
  }
}

class ParkApp extends StatelessWidget {
  const ParkApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final seed = Color(settings.seedColor);
        return MaterialApp(
          navigatorObservers: [Nav.routeObserver],
          title: 'HentaiPark',
          locale: settings.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.delegates,
          localeListResolutionCallback: (locales, supported) {
            final resolved = AppLocalizations.resolveLocales(locales);
            AppLocalizations.instance.setLocale(resolved);
            return resolved;
          },
          debugShowCheckedModeBanner: false,
          themeMode: settings.themeMode,
          theme: ParkTheme.build(Brightness.light, seed),
          darkTheme: ParkTheme.build(Brightness.dark, seed),
          home: const Shell(),
          builder: (context, child) => _SystemNavInset(
            child: LockGate(child: child ?? const SizedBox.shrink()),
          ),
        );
      },
    );
  }
}

/// Keeps every page above a three-button / gesture navigation bar. The app draws edge-to-edge, and
/// most pages pad their scroll views explicitly, which would otherwise leave the last items
/// hidden behind the bar. Immersive pages (reader, fullscreen video) hide the bar, so the inset is 0.
class _SystemNavInset extends StatelessWidget {
  const _SystemNavInset({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Transparent bar without the system's contrast scrim, so the bar area matches the app.
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
    );
    final bottom = mq.viewPadding.bottom;
    if (bottom <= 0) return child;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: MediaQuery(
          data: mq.copyWith(
            padding: mq.padding.copyWith(bottom: 0),
            viewPadding: mq.viewPadding.copyWith(bottom: 0),
            viewInsets: mq.viewInsets.copyWith(
              bottom: (mq.viewInsets.bottom - bottom).clamp(0, double.infinity),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
