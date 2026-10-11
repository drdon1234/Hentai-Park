import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/settings.dart';
import '../library/backup.dart';
import '../library/updater.dart';
import 'history/history_page.dart';
import 'home/home_page.dart';
import 'library/library_page.dart';
import 'platform.dart';
import 'settings/settings_page.dart';
import 'theme.dart';
import 'updates/updates_page.dart';

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
  DateTime? _lastBack;
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<String>? _taps;

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
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _taps?.cancel();
    LibraryUpdater.instance.onFinished.remove(_onUpdateFinished);
    LibraryUpdater.instance.onProgress = null;
    super.dispose();
  }

  void _onResume() {
    BackupService.instance.autoBackupIfDue();
    LibraryUpdater.instance.autoUpdateIfDue();
  }

  void _onNotificationTap(String payload) {
    if (payload == 'updates') _select(_updatesTab);
  }

  void _notifyProgress(LibraryUpdater u) {
    PlatformBridge.notify(
      id: _progressNotification,
      title: '正在检查书库更新',
      text: '${u.done}/${u.total}${u.current != null ? ' · ${u.current}' : ''}',
      ongoing: true,
      progress: u.done,
      max: u.total,
      channel: 'library_progress',
      channelName: '书库更新进度',
    );
  }

  void _onUpdateFinished(UpdateResult r) {
    PlatformBridge.cancelNotification(_progressNotification);
    if (r.updated.isEmpty) return;
    if (mounted && _index != _updatesTab) setState(() => _unseenUpdates += r.newChapters);
    final lines = [for (final u in r.updated.take(5)) '${u.item.title}：${u.chapterTitles.join('、')}'];
    if (r.updated.length > 5) lines.add('等 ${r.updated.length} 部作品');
    PlatformBridge.notify(id: _resultNotification, title: '${r.updated.length} 部作品有 ${r.newChapters} 个新章节', text: lines.join('\n'), payload: 'updates');
  }

  /// Back on another tab returns to 发现; on 发现 it needs a second press within 2 s to leave,
  /// so a stray back gesture never closes the app mid-browse.
  void _onBack() {
    if (_index != 0) {
      _select(0);
      return;
    }
    final now = DateTime.now();
    if (_lastBack != null && now.difference(_lastBack!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBack = now;
    context.toast('再按一次返回键退出');
  }

  void _select(int i) => setState(() {
    _index = i;
    _visited.add(i);
    if (i == _updatesTab) _unseenUpdates = 0;
  });

  List<NavigationDestination> get _destinations {
    final badge = _unseenUpdates > 0;
    Widget updatesIcon(IconData icon) => Badge(isLabelVisible: badge, label: Text('$_unseenUpdates'), child: Icon(icon));
    return [
      const NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore_rounded), label: '发现'),
      const NavigationDestination(icon: Icon(Icons.collections_bookmark_outlined), selectedIcon: Icon(Icons.collections_bookmark_rounded), label: '书架'),
      NavigationDestination(icon: updatesIcon(Icons.new_releases_outlined), selectedIcon: updatesIcon(Icons.new_releases_rounded), label: '更新'),
      const NavigationDestination(icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history_rounded), label: '历史'),
      const NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: '我的'),
    ];
  }

  Widget _page(int i) => switch (i) {
    0 => const HomePage(),
    1 => const LibraryPage(),
    2 => const UpdatesPage(),
    3 => const HistoryPage(),
    _ => const SettingsPage(),
  };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    // Tabs are built lazily on first visit and then kept alive.
    final body = IndexedStack(index: _index, children: [for (var i = 0; i < 5; i++) _visited.contains(i) ? _page(i) : const SizedBox.shrink()]);
    final destinations = _destinations;
    final content = ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        if (!AppSettings.instance.incognito) return body;
        // The banner takes the status-bar inset; pages below must not add it again.
        return Column(
          children: [
            const _IncognitoBanner(),
            Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: body)),
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
                  destinations: [for (final d in destinations) NavigationRailDestination(icon: d.icon, selectedIcon: d.selectedIcon, label: Text(d.label))],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            ),
          )
        : Scaffold(
            body: content,
            bottomNavigationBar: NavigationBar(selectedIndex: _index, onDestinationSelected: _select, destinations: destinations),
          );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: scaffold,
    );
  }
}

/// A thin strip at the top while incognito mode is on (Mihon shows the same reminder).
class _IncognitoBanner extends StatelessWidget {
  const _IncognitoBanner();

  @override
  Widget build(BuildContext context) {
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
                  child: Text('无痕模式 · 点击关闭', style: TextStyle(color: c.onTertiary, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
