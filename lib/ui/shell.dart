import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/settings.dart';
import '../core/content_scope.dart';
import '../library/backup.dart';
import '../library/updater.dart';
import 'history/history_page.dart';
import 'discovery_navigation.dart';
import 'home/home_page.dart';
import 'library/library_page.dart';
import '../engine/platform_bridge.dart';
import 'settings/settings_page.dart';
import 'theme.dart';
import 'updates/updates_page.dart';
import 'updates/startup_update_check.dart';
import 'widgets/content_translation.dart';
import '../core/localization.dart';
import '../subscriptions/updater.dart';
import 'subscriptions/subscription_updates_page.dart';
import 'nav.dart';

/// Root navigation: 发现 / 书架 / 更新 / 历史 / 我的 (Mihon's Browse / Library / Updates / History / More).
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  static const _updatesTab = 2;
  static const _progressNotification = 1001;
  static const _resultNotification = 1002;

  int _index = 0;
  final _visited = <int>{0};
  final _discovery = ValueNotifier(const DiscoveryDestination.all());
  ContentScope _historyScope = const ContentScope.all();
  int _historyOpenRequest = 0;
  DateTime? _lastBack;
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<String>? _taps;
  StreamSubscription<void>? _subscriptionWakes;

  /// New chapters found since the updates tab was last opened (badge).
  int _unseenUpdates = 0;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    final updater = LibraryUpdater.instance;
    updater.onProgress = _notifyProgress;
    updater.onFinished.add(_onUpdateFinished);
    _taps = PlatformBridge.notificationTaps.listen(_onNotificationTap);
    PlatformBridge.takeLaunchPayload().then((p) {
      if (p != null) _onNotificationTap(p);
    });
    unawaited(updater.autoUpdateIfDue());
    _subscriptionWakes = PlatformBridge.subscriptionWakes.listen(
      (_) => unawaited(SubscriptionUpdater.instance.run()),
    );
    SubscriptionUpdater.instance.start();
  }

  @override
  void dispose() {
    _discovery.dispose();
    _lifecycle.dispose();
    _taps?.cancel();
    _subscriptionWakes?.cancel();
    LibraryUpdater.instance.onFinished.remove(_onUpdateFinished);
    LibraryUpdater.instance.onProgress = null;
    SubscriptionUpdater.instance.stop();
    super.dispose();
  }

  void _onResume() {
    BackupService.instance.autoBackupIfDue();
    LibraryUpdater.instance.autoUpdateIfDue();
    unawaited(SubscriptionUpdater.instance.run());
  }

  void _onNotificationTap(String payload) {
    if (payload == 'updates') _select(_updatesTab);
    if (payload == 'subscriptions' && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Nav.push(context, const SubscriptionUpdatesPage());
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  void _notifyProgress(LibraryUpdater u) {
    PlatformBridge.notify(
      id: _progressNotification,
      title: tr('正在检查书库更新'),
      text: '${u.done}/${u.total}${u.current != null ? ' · ${u.current}' : ''}',
      ongoing: true,
      progress: u.done,
      max: u.total,
      channel: 'library_progress',
      channelName: tr('书库更新进度'),
    );
  }

  void _onUpdateFinished(UpdateResult r) {
    PlatformBridge.cancelNotification(_progressNotification);
    if (r.updated.isEmpty) return;
    if (mounted && _index != _updatesTab) {
      setState(() => _unseenUpdates += r.newChapters);
    }
    final lines = [
      for (final u in r.updated.take(5))
        '${u.item.title}：${u.chapterTitles.join('、')}',
    ];
    if (r.updated.length > 5) {
      lines.add(tr('等 {value0} 部作品', {'value0': r.updated.length}));
    }
    PlatformBridge.notify(
      id: _resultNotification,
      title: tr('{value0} 部作品有 {value1} 个新章节', {
        'value0': r.updated.length,
        'value1': r.newChapters,
      }),
      text: lines.join('\n'),
      payload: 'updates',
    );
  }

  /// Back on another tab returns to 发现; on 发现 it needs a second press within 2 s to leave,
  /// so a stray back gesture never closes the app mid-browse.
  void _onBack() {
    if (_index != 0) {
      _select(0);
      return;
    }
    final now = DateTime.now();
    if (_lastBack != null &&
        now.difference(_lastBack!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBack = now;
    context.toast(tr('再按一次返回键退出'));
  }

  void _select(int i) => setState(() {
    _index = i;
    _visited.add(i);
    if (i == _updatesTab) _unseenUpdates = 0;
  });

  List<NavigationDestination> get _destinations {
    final badge = _unseenUpdates > 0;
    Widget updatesIcon(IconData icon) => Badge(
      isLabelVisible: badge,
      label: Text('$_unseenUpdates'),
      child: Icon(icon),
    );
    return [
      NavigationDestination(
        icon: Icon(Icons.explore_outlined),
        selectedIcon: Icon(Icons.explore_rounded),
        label: tr('发现'),
      ),
      NavigationDestination(
        icon: Icon(Icons.collections_bookmark_outlined),
        selectedIcon: Icon(Icons.collections_bookmark_rounded),
        label: tr('书架'),
      ),
      NavigationDestination(
        icon: updatesIcon(Icons.new_releases_outlined),
        selectedIcon: updatesIcon(Icons.new_releases_rounded),
        label: tr('更新'),
      ),
      NavigationDestination(
        icon: Icon(Icons.history_outlined),
        selectedIcon: Icon(Icons.history_rounded),
        label: tr('历史'),
      ),
      NavigationDestination(
        icon: Icon(Icons.person_outline_rounded),
        selectedIcon: Icon(Icons.person_rounded),
        label: tr('我的'),
      ),
    ];
  }

  Widget _page(int i) => switch (i) {
    0 => HomePage(
      destination: _discovery,
      onOpenHistory: (scope) {
        _historyScope = scope;
        _historyOpenRequest++;
        _select(3);
      },
    ),
    1 => const LibraryPage(),
    2 => const UpdatesPage(),
    3 => HistoryPage(scope: _historyScope, openRequest: _historyOpenRequest),
    _ => const SettingsPage(),
  };

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 840;
    // Tabs are built lazily on first visit and then kept alive.
    final body = IndexedStack(
      index: _index,
      children: [
        for (var i = 0; i < 5; i++)
          _visited.contains(i)
              ? TranslationPage(active: i == _index, child: _page(i))
              : const SizedBox.shrink(),
      ],
    );
    final destinations = _destinations;
    final content = ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        if (!AppSettings.instance.incognito) return body;
        // The banner takes the status-bar inset; pages below must not add it again.
        return Column(
          children: [
            const _IncognitoBanner(),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: body,
              ),
            ),
          ],
        );
      },
    );
    final scaffold = wide
        ? Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: _select,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final d in destinations)
                      NavigationRailDestination(
                        icon: d.icon,
                        selectedIcon: d.selectedIcon,
                        label: Text(d.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            ),
          )
        : Scaffold(
            body: content,
            bottomNavigationBar: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _select,
              destinations: destinations,
            ),
          );
    return DiscoveryNavigation(
      onSelect: (destination) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        _discovery.value = destination;
        _select(0);
      },
      child: StartupUpdateCheck(
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _onBack();
          },
          child: scaffold,
        ),
      ),
    );
  }
}

/// A thin strip at the top while incognito mode is on (Mihon shows the same reminder).
class _IncognitoBanner extends StatelessWidget {
  const _IncognitoBanner();

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final s = AppSettings.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        if (!s.incognito) return const SizedBox.shrink();
        final c = context.colors;
        return Material(
          color: c.tertiary,
          child: SafeArea(
            bottom: false,
            child: InkWell(
              onTap: () => s.incognito = false,
              child: SizedBox(
                height: 22,
                child: Center(
                  child: Text(
                    tr('无痕模式 · 点击关闭'),
                    style: TextStyle(
                      color: c.onTertiary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
