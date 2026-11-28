import 'package:flutter/material.dart';

import '../../core/platform_capabilities.dart';
import '../theme.dart';

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
    if (!strip && !widget.sideSafeArea) return scoped;
    return ValueListenableBuilder<int>(
      valueListenable: _depth,
      child: scoped,
      builder: (context, depth, child) {
        final immersive = depth > 0;
        final bottom = !immersive && strip ? mq.viewPadding.bottom : 0.0;
        final side = !immersive && widget.sideSafeArea;
        final left = side ? mq.padding.left : 0.0;
        final right = side ? mq.padding.right : 0.0;
        final inset = EdgeInsets.only(left: left, right: right, bottom: bottom);
        return ColoredBox(
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
                  bottom: bottom > 0 ? 0 : mq.padding.bottom,
                ),
                viewPadding: mq.viewPadding.copyWith(
                  left: mq.viewPadding.left - left,
                  right: mq.viewPadding.right - right,
                  bottom: bottom > 0 ? 0 : mq.viewPadding.bottom,
                ),
                viewInsets: mq.viewInsets.copyWith(
                  bottom: (mq.viewInsets.bottom - bottom).clamp(
                    0,
                    double.infinity,
                  ),
                ),
              ),
              child: child!,
            ),
          ),
        );
      },
    );
  }
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
