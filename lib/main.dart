import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;

import 'core/app_lock.dart';
import 'core/app_log.dart';
import 'core/crash_log.dart';
import 'core/localization.dart';
import 'core/models.dart';
import 'core/settings.dart';
import 'core/startup.dart';
import 'core/storage.dart';
import 'core/tag_translations.dart';
import 'data/database.dart';
import 'engine/cookie_store.dart';
import 'engine/http_service.dart';
import 'engine/native_notifications.dart';
import 'engine/platform_bridge.dart';
import 'engine/request_lifecycle.dart';
import 'engine/source_manager.dart';
import 'game/downloads.dart';
import 'images/image_store.dart';
import 'library/backup.dart';
import 'library/downloads.dart';
import 'library/library.dart';
import 'library/live_recordings.dart';
import 'library/restore_transaction.dart';
import 'library/updater.dart';
import 'novel/reading_notes.dart';
import 'subscriptions/background.dart';
import 'subscriptions/subscription_store.dart';
import 'subscriptions/updater.dart';
import 'tavern/worldbook_terms.dart';
import 'ui/lock/lock_screen.dart';
import 'ui/nav.dart';
import 'ui/shell.dart';
import 'ui/startup/startup_gate.dart';
import 'ui/theme.dart';
import 'ui/widgets/storage_save_notice.dart';

@pragma('vm:entry-point')
Future<void> subscriptionBackgroundMain() => subscriptionBackground();

void main() {
  CrashLog.install();
  runZonedGuarded(_start, (error, stack) => CrashLog.record(error, stack));
}

Future<void> _start() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'OpenCC',
    ], await rootBundle.loadString('docs/licenses/opencc.txt'));
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
  late AppDatabase db;
  final startup = StartupSequence([
    () async {
      await AppLocalizations.instance.load();
      AppLocalizations.instance.setLocale(
        AppLocalizations.resolveLocales(
          WidgetsBinding.instance.platformDispatcher.locales,
        ),
      );
    },
    () async {
      if (Platform.isAndroid || Platform.isIOS) {
        await const MethodChannel('hentai_park/platform')
            .invokeMethod<void>('claimSourceEngine');
      }
    },
    AppPaths.init,
    AppLog.initialize,
    () async {
      CrashLog.initialize();
    },
    () async {
      final candidate = AppDatabase.file(
        File(p.join(AppPaths.data.path, 'park.db')),
      );
      try {
        await candidate.customSelect('SELECT 1').get();
        await RestoreTransaction.recover(candidate);
        db = candidate;
      } catch (_) {
        await candidate.close();
        rethrow;
      }
    },
    AppSettings.instance.load,
    TagTranslations.instance.init,
    WorldbookTerms.instance.init,
    CookieStore.instance.init,
    ReadingNotes.instance.load,
    () async {
      AppLocalizations.instance.setLocale(
        AppSettings.instance.locale ??
            AppLocalizations.resolveLocales(
              WidgetsBinding.instance.platformDispatcher.locales,
            ),
      );
      await WorldbookTerms.instance.ensureLoaded(
        AppLocalizations.localeKey(AppLocalizations.instance.locale),
      );
      HttpService.instance.init();
    },
    () => Library.instance.open(db),
    () => DownloadManager.instance.load(db),
    LiveRecordings.instance.load,
    GameDownloadManager.instance.load,
    () async {
      AppLock.instance.init();
      LibraryUpdater.instance.onFinished.add(_autoDownload);
    },
    () async {
      await PlatformBridge.restoreDefaultOrientations();
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
    },
    PlatformBridge.bindSettings,
    NativeNotifications.instance.init,
    () async {
      PlatformBridge.refreshSubscriptions = () =>
          RequestLifecycle.instance.withBackgroundExecution(() async {
            await SourceManager.instance.init();
            await SubscriptionStore.instance.load();
            final updater = SubscriptionUpdater.instance;
            try {
              await updater.run();
              return !updater.cancelled && updater.failures == 0;
            } finally {
              updater.cancelled = false;
            }
          });
      PlatformBridge.cancelSubscriptionRefresh =
          SubscriptionUpdater.instance.cancel;
      await PlatformBridge.notifySubscriptionEngineReady();
      // Sources load after the first frame; the UI shows skeletons meanwhile.
      WidgetsBinding.instance.addPostFrameCallback((_) {
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
      });
    },
  ]);
  runApp(StartupGate(initialize: startup.run, child: const ParkApp()));
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
              child: LockGate(
                child: StorageSaveNotice(
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
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
      // 依赖变化发生在构建期间，待本帧的控件树稳定后再刷新现有页面。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        void rebuild(Element element) {
          element.markNeedsBuild();
          element.visitChildElements(rebuild);
        }

        context.visitChildElements(rebuild);
      });
    }
    _locale = locale;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Applies the system UI overlay style at the app root without clipping the
/// root Navigator, so modal bottom sheets and dialog scrims extend seamlessly
/// to the physical bottom edge while each page route manages its own
/// [SystemNavBoundary].
class _SystemNavInset extends StatelessWidget {
  const _SystemNavInset({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final style = ParkTheme.overlayStyle(Theme.of(context).brightness);
    return AnnotatedRegion<SystemUiOverlayStyle>(value: style, child: child);
  }
}
