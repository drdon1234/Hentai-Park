import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../core/localization.dart';
import '../core/platform_capabilities.dart';
import '../core/settings.dart';
import 'kit/kit.dart';
import 'nav.dart';
import 'theme.dart';

/// 桌面导航属于窗口，而不是某一个页面；弹窗与页面仍共用原来的路由栈。
class DesktopNavigation extends NavigatorObserver with ChangeNotifier {
  static final instance = DesktopNavigation();
  final _routes = <Route<dynamic>>[];
  ValueChanged<int>? onSelect;
  VoidCallback? onRootBack;
  int selected = 0;
  int unseen = 0;
  bool rootCanGoBack = false;
  bool _scheduled = false;

  bool get canGoBack => (navigator?.canPop() ?? false) || rootCanGoBack;
  bool get modalOpen => _routes.lastOrNull is PopupRoute;

  void changed() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      notifyListeners();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void back() {
    final state = navigator;
    if (state == null) return;
    if (state.canPop()) {
      // maybePop 尊重播放器全屏、未保存表单等页面自己的 PopScope。
      state.maybePop();
    } else {
      onRootBack?.call();
    }
  }

  void select(int index) {
    if (modalOpen) return;
    navigator?.popUntil((route) => route.isFirst);
    onSelect?.call(index);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null) _routes.clear();
    _routes.add(route);
    changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
    changed();
  }
}

/// 保留系统标题栏与窗口按钮，应用工具栏、侧栏不再随二级页面消失。
class DesktopWorkspace extends StatefulWidget {
  const DesktopWorkspace({super.key, required this.child});
  final Widget child;

  @override
  State<DesktopWorkspace> createState() => _DesktopWorkspaceState();
}

class _DesktopWorkspaceState extends State<DesktopWorkspace>
    with WindowListener {
  bool _fullscreen = false;
  final _navigation = DesktopNavigation.instance;
  late final _appearance = AppSettings.instance.watch(const {
    'adultConfirmed',
    'onboarded',
  });

  @override
  void initState() {
    super.initState();
    if (PlatformCapabilities.desktop) windowManager.addListener(this);
  }

  @override
  void dispose() {
    if (PlatformCapabilities.desktop) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() => setState(() => _fullscreen = true);

  @override
  void onWindowLeaveFullScreen() => setState(() => _fullscreen = false);

  void _search() {
    if (_navigation.modalOpen ||
        !AppSettings.instance.adultConfirmed ||
        !AppSettings.instance.onboarded) {
      return;
    }
    final context = _navigation.navigator?.overlay?.context;
    if (context != null) Nav.openAggregateSearch(context);
  }

  List<NavigationDestination> _destinations() => [
    NavigationDestination(
      icon: const Icon(Icons.explore_outlined),
      label: tr('发现'),
    ),
    NavigationDestination(
      icon: Badge(
        isLabelVisible: _navigation.unseen > 0,
        label: Text('${_navigation.unseen}'),
        child: const Icon(Icons.collections_bookmark_outlined),
      ),
      label: tr('收藏'),
    ),
    NavigationDestination(
      icon: const Icon(Icons.download_outlined),
      label: tr('下载'),
    ),
    NavigationDestination(
      icon: const Icon(Icons.settings_outlined),
      label: tr('我的'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (!PlatformCapabilities.desktop) return widget.child;
    return _WorkspaceOverlay(
      child: ListenableBuilder(
        listenable: Listenable.merge([
          _navigation,
          _appearance,
          Immersive.depth,
        ]),
        child: RepaintBoundary(child: widget.child),
        builder: (context, child) {
          final ready =
              AppSettings.instance.adultConfirmed &&
              AppSettings.instance.onboarded;
          final visible = ready && !_fullscreen && Immersive.depth.value == 0;
          final destinations = _destinations();
          final wide = PlatformNavigation.expandedSidebar(context);
          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
                  _navigation.back,
              const SingleActivator(LogicalKeyboardKey.browserBack):
                  _navigation.back,
              const SingleActivator(LogicalKeyboardKey.keyL, control: true):
                  _search,
              for (var i = 0; i < 4; i++)
                SingleActivator(
                  [
                    LogicalKeyboardKey.digit1,
                    LogicalKeyboardKey.digit2,
                    LogicalKeyboardKey.digit3,
                    LogicalKeyboardKey.digit4,
                  ][i],
                  control: true,
                ): () =>
                    _navigation.select(i),
            },
            child: Focus(
              autofocus: true,
              child: Listener(
                onPointerDown: (event) {
                  if (ready && (event.buttons & kBackMouseButton) != 0) {
                    _navigation.back();
                  }
                },
                child: Material(
                  color: context.colors.surfaceContainerLow,
                  child: Column(
                    children: [
                      if (visible)
                        SizedBox(
                          height: 48,
                          child: Row(
                            children: [
                              const SizedBox(width: Gap.s),
                              IconButton(
                                tooltip: '${tr('返回')} (Alt+←)',
                                onPressed: _navigation.canGoBack
                                    ? _navigation.back
                                    : null,
                                icon: const Icon(Icons.arrow_back_rounded),
                              ),
                              const SizedBox(width: Gap.s),
                              Expanded(
                                child: Text(
                                  'HentaiPark  /  ${destinations[_navigation.selected].label}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.text.titleSmall,
                                ),
                              ),
                              IconButton(
                                tooltip: '${tr('搜索')} (Ctrl+L)',
                                onPressed: _navigation.modalOpen
                                    ? null
                                    : _search,
                                icon: const Icon(Icons.search_rounded),
                              ),
                              const SizedBox(width: Gap.s),
                            ],
                          ),
                        ),
                      if (visible) const Divider(height: 1),
                      Expanded(
                        key: const ValueKey('desktop-content'),
                        child: Row(
                          children: [
                            // 保持 Navigator 的父节点与位置，隐藏侧栏不销毁播放/阅读状态。
                            Offstage(
                              offstage: !visible,
                              child: ExcludeFocus(
                                excluding: !visible || _navigation.modalOpen,
                                child: IgnorePointer(
                                  ignoring: _navigation.modalOpen,
                                  child: PlatformNavigation(
                                    destinations: destinations,
                                    selectedIndex: _navigation.selected,
                                    onSelected: _navigation.select,
                                    wide: wide,
                                  ),
                                ),
                              ),
                            ),
                            Offstage(
                              offstage: !visible,
                              child: const VerticalDivider(width: 1),
                            ),
                            Expanded(child: child!),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 窗口工具栏位于 Navigator 外，单独提供 tooltip 所需的 Overlay。
class _WorkspaceOverlay extends StatefulWidget {
  const _WorkspaceOverlay({required this.child});
  final Widget child;

  @override
  State<_WorkspaceOverlay> createState() => _WorkspaceOverlayState();
}

class _WorkspaceOverlayState extends State<_WorkspaceOverlay> {
  late final _entry = OverlayEntry(builder: (_) => widget.child);

  @override
  void didUpdateWidget(_WorkspaceOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    _entry.remove();
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}
