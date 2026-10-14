import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;

import 'core/app_lock.dart';
import 'core/crash_log.dart';
import 'core/localization.dart';
import 'core/models.dart';
import 'core/settings.dart';
import 'core/storage.dart';
import 'core/tag_translations.dart';
import 'data/database.dart';
import 'engine/cookie_store.dart';
import 'engine/http_service.dart';
import 'engine/platform_bridge.dart';
import 'engine/source_manager.dart';
import 'game/downloads.dart';
import 'images/image_store.dart';
import 'library/backup.dart';
import 'library/downloads.dart';
import 'library/library.dart';
import 'library/restore_transaction.dart';
import 'library/updater.dart';
import 'novel/reading_notes.dart';
import 'subscriptions/background.dart';
import 'ui/lock/lock_screen.dart';
import 'ui/nav.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

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
  await Future.wait([
    TagTranslations.instance.init(),
    AppLocalizations.instance.load(),
    CookieStore.instance.init(),
    ReadingNotes.instance.load(),
  ]);
  AppLocalizations.instance.setLocale(
    AppSettings.instance.locale ??
        AppLocalizations.resolveLocales(
          WidgetsBinding.instance.platformDispatcher.locales,
        ),
  );
  HttpService.instance.init();
  await Library.instance.open(db);
  await DownloadManager.instance.load(db);
  await GameDownloadManager.instance.load();
  AppLock.instance.init();
  LibraryUpdater.instance.onFinished.add(_autoDownload);
  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(false);
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
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
      // Only theme and language rebuild the app; other settings have their own listeners.
      listenable: settings.watch(AppSettings.appearanceKeys),
      builder: (context, _) {
        final accent = Color(settings.seedColor);
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
          theme: ParkTheme.of(Brightness.light, accent),
          darkTheme: ParkTheme.of(Brightness.dark, accent),
          home: const Shell(),
          builder: (context, child) => _LanguageRefresh(
            child: _SystemNavInset(
              child: LockGate(child: child ?? const SizedBox.shrink()),
            ),
          ),
        );
      },
    );
  }
}

/// Application copy is looked up through the global [tr], so a language change rebuilds every
/// element once instead of making each widget subscribe to [Localizations] by hand.
class _LanguageRefresh extends StatefulWidget {
  const _LanguageRefresh({required this.child});
  final Widget child;

  @override
  State<_LanguageRefresh> createState() => _LanguageRefreshState();
}

class _LanguageRefreshState extends State<_LanguageRefresh> {
  Locale? _locale;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    if (_locale != null && _locale != locale) {
      void rebuild(Element element) {
        element.markNeedsBuild();
        element.visitChildElements(rebuild);
      }

      (context as Element).visitChildElements(rebuild);
    }
    _locale = locale;
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
    final theme = Theme.of(context);
    final bottom = mq.viewPadding.bottom;
    // Transparent system bar without the contrast scrim; the strip below it uses the same
    // color as the app's navigation bar so the two read as one surface.
    final style = ParkTheme.overlayStyle(theme.brightness);
    if (bottom <= 0) {
      return AnnotatedRegion<SystemUiOverlayStyle>(value: style, child: child);
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: style,
      child: ColoredBox(
        color: ParkTheme.navigationColor(theme.colorScheme),
        child: Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: MediaQuery(
            data: mq.copyWith(
              padding: mq.padding.copyWith(bottom: 0),
              viewPadding: mq.viewPadding.copyWith(bottom: 0),
              viewInsets: mq.viewInsets.copyWith(
                bottom: (mq.viewInsets.bottom - bottom).clamp(
                  0,
                  double.infinity,
                ),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
