import 'package:flutter/material.dart';

import '../../core/platform_capabilities.dart';
import '../../engine/platform_bridge.dart';
import '../theme.dart';
import 'platform_navigation.dart';
import 'side_dock.dart';

/// Pages that draw edge to edge (readers, fullscreen players, the short-video feed) register here while they are
/// mounted, so the app stops painting its own strip under the system navigation bar and the
/// page's own background shows through instead.
abstract final class Immersive {
  static final depth = ValueNotifier<int>(0);
}

class _ImmersiveScope extends InheritedWidget {
  const _ImmersiveScope({required this.depth, required super.child});
  final ValueNotifier<int> depth;

  static ValueNotifier<int>? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_ImmersiveScope>()?.depth;

  @override
  bool updateShouldNotify(_ImmersiveScope oldWidget) =>
      !identical(depth, oldWidget.depth);
}

/// Per-route system navigation bar boundary. Wrapping each page route (instead
/// of the root Navigator) keeps modal sheets and dialog scrims full-screen to
/// the physical bottom edge, and ensures pushing a regular page over an
/// immersive page gives the new route its own bottom inset immediately.
///
/// 非沉浸页面同时避让左右安全区（如可折叠 iPhone 外屏右侧的状态区、横屏刘海），
/// 沉浸页面仍铺满屏幕。自行处理左右安全区的容器（主框架的侧边导航）传 [sideSafeArea] = false。
/// 结构保持不变，仅调整数值，切换沉浸或折叠状态时不重建页面。
class SystemNavBoundary extends StatefulWidget {
  const SystemNavBoundary({
    super.key,
    required this.child,
    this.sideSafeArea = true,
  });
  final Widget child;
  final bool sideSafeArea;

  @override
  State<SystemNavBoundary> createState() => _SystemNavBoundaryState();
}

class _SystemNavBoundaryState extends State<SystemNavBoundary> {
  final _depth = ValueNotifier<int>(0);
  final _dock = ValueNotifier<SideDockEntry?>(null);

  @override
  void initState() {
    super.initState();
    PlatformBridge.watchTopBarRegion();
  }

  @override
  void dispose() {
    _depth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final theme = Theme.of(context);
    final scoped = _ImmersiveScope(depth: _depth, child: widget.child);
    final strip = PlatformCapabilities.systemNavigationStrip;
    final rail = widget.sideSafeArea
        ? PlatformNavigation.insetRail(context)
        : EdgeInsets.zero;
    return ListenableBuilder(
      listenable: Listenable.merge([_depth, PlatformBridge.topBarRegion]),
      child: scoped,
      builder: (context, child) {
        final immersive = _depth.value > 0;
        final bottom = !immersive && strip ? mq.viewPadding.bottom : 0.0;
        final side = !immersive && widget.sideSafeArea;
        final left = side ? mq.padding.left : 0.0;
        final right = side ? mq.padding.right : 0.0;
        final inset = EdgeInsets.only(left: left, right: right, bottom: bottom);
        // 状态区只占右上角时（iPhone Duo 内屏），顶部栏与状态区同排：按系统栏区垂直居中，
        // 右侧操作让出状态区；栏下内容使用整屏宽度。
        final region = immersive ? null : PlatformBridge.topBarRegion.value;
        final top = region == null
            ? mq.padding.top
            : (region.top + (region.height - kToolbarHeight) / 2).clamp(
                0.0,
                mq.padding.top,
              );
        final corner = region == null
            ? 0.0
            : (region.right - (mq.padding.right - right)).clamp(
                0.0,
                double.infinity,
              );
        final pageTheme = corner > 0
            ? theme.copyWith(
                appBarTheme: theme.appBarTheme.copyWith(
                  actionsPadding: EdgeInsets.only(right: corner),
                ),
              )
            : theme;
        final dockActive = !immersive && rail != EdgeInsets.zero;
        return Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: inset == EdgeInsets.zero
                    ? Colors.transparent
                    : ParkTheme.navigationColor(theme.colorScheme),
                child: Padding(
                  padding: inset,
                  child: MediaQuery(
                    data: mq.copyWith(
                      padding: mq.padding.copyWith(
                        left: mq.padding.left - left,
                        right: mq.padding.right - right,
                        top: top,
                        bottom: bottom > 0 ? 0 : mq.padding.bottom,
                      ),
                      viewPadding: mq.viewPadding.copyWith(
                        left: mq.viewPadding.left - left,
                        right: mq.viewPadding.right - right,
                        top: region == null ? mq.viewPadding.top : top,
                        bottom: bottom > 0 ? 0 : mq.viewPadding.bottom,
                      ),
                      viewInsets: mq.viewInsets.copyWith(
                        bottom: (mq.viewInsets.bottom - bottom).clamp(
                          0,
                          double.infinity,
                        ),
                      ),
                    ),
                    child: Theme(
                      data: pageTheme,
                      child: TopCorner(
                        right: corner,
                        child: SideDock(
                          slot: _dock,
                          active: dockActive,
                          child: child!,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 侧边安全区内的悬浮操作，与侧边导航胶囊同列。
            if (dockActive)
              Positioned(
                top: 0,
                bottom: 0,
                left: rail.left > 0 ? 0 : null,
                right: rail.right > 0 ? 0 : null,
                width: rail.horizontal,
                child: ValueListenableBuilder<SideDockEntry?>(
                  valueListenable: _dock,
                  builder: (context, entry, _) => entry == null
                      ? const SizedBox.shrink()
                      : Align(
                          alignment: rail.right > 0
                              ? Alignment.bottomRight
                              : Alignment.bottomLeft,
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: rail.left > 0 ? 24 : 0,
                              right: rail.right > 0 ? 24 : 0,
                              bottom: 24,
                            ),
                            child: SizedBox(
                              width: 48,
                              child: Center(
                                heightFactor: 1,
                                child: entry.child,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 顶部栏需在右侧额外让出的宽度（状态区只占右上角时）；不使用 AppBar 的顶部元素据此避让。
class TopCorner extends InheritedWidget {
  const TopCorner({super.key, required this.right, required super.child});

  final double right;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TopCorner>()?.right ?? 0;

  @override
  bool updateShouldNotify(TopCorner oldWidget) => oldWidget.right != right;
}

class ImmersiveRegion extends StatefulWidget {
  const ImmersiveRegion({super.key, required this.child, this.enabled = true});
  final bool enabled;
  final Widget child;

  @override
  State<ImmersiveRegion> createState() => _ImmersiveRegionState();
}

class _ImmersiveRegionState extends State<ImmersiveRegion> {
  ValueNotifier<int>? _localDepth;
  bool _registered = false;

  static void _change(ValueNotifier<int>? local, int delta) {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        Immersive.depth.value = (Immersive.depth.value + delta).clamp(0, 9999);
        if (local != null) {
          try {
            local.value = (local.value + delta).clamp(0, 9999);
          } catch (_) {}
        }
      })
      ..scheduleFrame();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextLocal = _ImmersiveScope.of(context);
    if (!identical(nextLocal, _localDepth)) {
      if (_registered) {
        _change(_localDepth, -1);
        _registered = false;
      }
      _localDepth = nextLocal;
    }
    if (widget.enabled && !_registered) {
      _registered = true;
      _change(_localDepth, 1);
    }
  }

  @override
  void didUpdateWidget(ImmersiveRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_registered) {
      _registered = true;
      _change(_localDepth, 1);
    } else if (!widget.enabled && _registered) {
      _registered = false;
      _change(_localDepth, -1);
    }
  }

  @override
  void dispose() {
    if (_registered) {
      _registered = false;
      _change(_localDepth, -1);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
