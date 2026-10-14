import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/content_scope.dart';
import '../core/localization.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../engine/platform_bridge.dart';
import '../library/backup.dart';
import '../library/updater.dart';
import '../subscriptions/updater.dart';
import 'detail/detail_page.dart';
import 'detail_pane.dart';
import 'discovery_navigation.dart';
import 'history/history_page.dart';
import 'home/home_page.dart';
import 'kit/kit.dart';
import 'library/shelf_page.dart';
import 'nav.dart';
import 'onboarding/onboarding_page.dart';
import 'settings/settings_page.dart';
import 'subscriptions/subscription_updates_page.dart';
import 'theme.dart';
import 'updates/startup_update_check.dart';
import 'widgets/content_translation.dart';

/// Root navigation: 发现 / 书架 / 历史 / 我的. Library updates live inside 书架 as a segment.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  static const _shelfTab = 1;
  static const _historyTab = 2;
  static const _progressNotification = 1001;
  static const _resultNotification = 1002;

  int _index = 0;
  final _visited = <int>{0};
  final _discovery = ValueNotifier(const DiscoveryDestination.all());
  final _shelf = ValueNotifier(ShelfSegment.favorites);
  ContentScope _historyScope = const ContentScope.all();
  int _historyOpenRequest = 0;
  DateTime? _lastBack;
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<String>? _taps;
  StreamSubscription<void>? _subscriptionWakes;

  /// New chapters found since the updates segment was last opened (badge).
  final _unseenUpdates = ValueNotifier(0);

  /// The work shown beside the list on wide screens.
  WorkItem? _pane;

  void _showPane(WorkItem item) {
    if (_pane?.uid == item.uid) return;
    setState(() => _pane = item);
  }

  void _closePane() => setState(() => _pane = null);

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    final updater = LibraryUpdater.instance;
    updater.onProgress = _notifyProgress;
    updater.onFinished.add(_onUpdateFinished);
    _shelf.addListener(_shelfChanged);
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
    _shelf.dispose();
    _unseenUpdates.dispose();
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

  bool get _updatesVisible =>
      _index == _shelfTab && _shelf.value == ShelfSegment.updates;

  void _shelfChanged() {
    if (_updatesVisible) _unseenUpdates.value = 0;
  }

  void _openUpdates() {
    _shelf.value = ShelfSegment.updates;
    _select(_shelfTab);
  }

  void _onNotificationTap(String payload) {
    if (payload == 'updates') _openUpdates();
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
    if (mounted && !_updatesVisible) _unseenUpdates.value += r.newChapters;
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
    if (_pane != null) {
      _closePane();
      return;
    }
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

  void _select(int i) {
    if (i != _index) HapticFeedback.selectionClick();
    setState(() {
      // The work beside the list belongs to the tab it was opened from.
      if (i != _index) _pane = null;
      _index = i;
      _visited.add(i);
    });
    _shelfChanged();
  }

  List<NavigationDestination> _destinations(int unseen) {
    Widget shelfIcon(IconData icon) => Badge(
      isLabelVisible: unseen > 0,
      label: Text('$unseen'),
      child: Icon(icon),
    );
    return [
      NavigationDestination(
        icon: const Icon(Icons.explore_outlined),
        selectedIcon: const Icon(Icons.explore_rounded),
        label: tr('发现'),
      ),
      NavigationDestination(
        icon: shelfIcon(Icons.collections_bookmark_outlined),
        selectedIcon: shelfIcon(Icons.collections_bookmark_rounded),
        label: tr('书架'),
        tooltip: unseen > 0 ? tr('书架，{value0} 个新章节', {'value0': unseen}) : null,
      ),
      NavigationDestination(
        icon: const Icon(Icons.history_outlined),
        selectedIcon: const Icon(Icons.history_rounded),
        label: tr('历史'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.person_outline_rounded),
        selectedIcon: const Icon(Icons.person_rounded),
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
        _select(_historyTab);
      },
    ),
    _shelfTab => ShelfPage(segment: _shelf, unseenUpdates: _unseenUpdates),
    _historyTab => HistoryPage(
      scope: _historyScope,
      openRequest: _historyOpenRequest,
    ),
    _ => const SettingsPage(),
  };

  late final Listenable _adult = AppSettings.instance.watch(const {
    'adultConfirmed',
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _adult,
    builder: (context, _) => AppSettings.instance.adultConfirmed
        ? _shell(context)
        : const OnboardingPage(),
  );

  Widget _shell(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 840;
    if (!wide && _pane != null) {
      // Narrowed (e.g. rotated) with a work open beside the list: open it as a page.
      final item = _pane!;
      _pane = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Nav.openWork(context, item);
      });
    }
    // Tabs are built lazily on first visit and then kept alive. The body never changes its
    // parent, so toggling incognito keeps every tab's scroll position and state.
    final body = Column(
      children: [
        const _IncognitoBanner(),
        Expanded(
          child: _IncognitoInset(
            child: IndexedStack(
              index: _index,
              children: [
                // Hidden tabs keep their state but not their animations.
                for (var i = 0; i < 4; i++)
                  _visited.contains(i)
                      ? TickerMode(
                          enabled: i == _index,
                          child: TranslationPage(
                            active: i == _index,
                            child: _page(i),
                          ),
                        )
                      : const SizedBox.shrink(),
              ],
            ),
          ),
        ),
      ],
    );
    final navigation = ValueListenableBuilder<int>(
      valueListenable: _unseenUpdates,
      builder: (context, unseen, _) {
        final destinations = _destinations(unseen);
        if (wide) {
          return NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: _select,
            labelType: NavigationRailLabelType.all,
            groupAlignment: -0.9,
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(
                  icon: d.icon,
                  selectedIcon: d.selectedIcon,
                  label: Text(d.label),
                ),
            ],
          );
        }
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: context.colors.outlineVariant, width: .8),
            ),
          ),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _select,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: destinations,
          ),
        );
      },
    );
    final pane = _pane;
    final scaffold = wide
        ? DetailPane(
            selected: pane?.uid,
            onShow: _showPane,
            child: Scaffold(
              body: Row(
                children: [
                  SafeArea(right: false, child: navigation),
                  const VerticalDivider(width: 1, thickness: .8),
                  Expanded(child: body),
                  if (pane != null) ...[
                    const VerticalDivider(width: 1, thickness: .8),
                    SizedBox(
                      width: (width * .42).clamp(360.0, 560.0),
                      child: TranslationPage(
                        child: DetailPage(
                          key: ValueKey(pane.uid),
                          source: pane.source,
                          id: pane.id,
                          preview: pane,
                          onClose: _closePane,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          )
        : Scaffold(body: body, bottomNavigationBar: navigation);
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

Listenable get _incognito => AppSettings.instance.watch(const {'incognito'});

/// A readable strip at the top while incognito mode is on. It takes the status-bar inset itself;
/// when hidden it has no height.
class _IncognitoBanner extends StatelessWidget {
  const _IncognitoBanner();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _incognito,
    builder: (context, _) {
      final s = AppSettings.instance;
      if (!s.incognito) return const SizedBox.shrink();
      final c = context.colors;
      return Material(
        color: c.inverseSurface,
        child: SafeArea(
          bottom: false,
          child: Semantics(
            button: true,
            label: tr('无痕模式已开启，不记录历史与进度。点击关闭'),
            onTap: () => s.incognito = false,
            excludeSemantics: true,
            child: InkWell(
              onTap: () => s.incognito = false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.page,
                  vertical: Gap.s,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.visibility_off_outlined,
                      size: 18,
                      color: c.onInverseSurface,
                    ),
                    const SizedBox(width: Gap.s),
                    Expanded(
                      child: Text(
                        tr('无痕模式：不记录历史与进度'),
                        style: context.text.bodyMedium?.copyWith(
                          color: c.onInverseSurface,
                        ),
                      ),
                    ),
                    Text(
                      tr('关闭'),
                      style: context.text.labelLarge?.copyWith(
                        color: c.onInverseSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Pages below the banner must not add the status-bar inset again.
class _IncognitoInset extends StatelessWidget {
  const _IncognitoInset({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _incognito,
    child: child,
    builder: (context, child) => MediaQuery.removePadding(
      context: context,
      removeTop: AppSettings.instance.incognito,
      child: child!,
    ),
  );
}
