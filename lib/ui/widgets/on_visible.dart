import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Reports visibility after layout, clipped by every enclosing scroll viewport.
/// A built item in a shrink-wrapped or cached list is not necessarily visible.
class OnVisible extends StatefulWidget {
  const OnVisible({super.key, required this.child, required this.onVisible});
  final Widget child;
  final ValueChanged<bool> onVisible;

  @override
  State<OnVisible> createState() => _OnVisibleState();
}

class _OnVisibleState extends State<OnVisible> {
  final Set<ScrollPosition> _positions = {};
  bool? _visible;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listen();
    _schedule();
  }

  void _listen() {
    final next = <ScrollPosition>{};
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        next.add((element.state as ScrollableState).position);
      }
      return true;
    });
    for (final position in _positions.difference(next)) {
      position.removeListener(_schedule);
    }
    for (final position in next.difference(_positions)) {
      position.addListener(_schedule);
    }
    _positions
      ..clear()
      ..addAll(next);
  }

  @override
  void didUpdateWidget(OnVisible oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  void _schedule() {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      _listen();
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return;
      var rect = MatrixUtils.transformRect(
        box.getTransformTo(null),
        Offset.zero & box.size,
      );
      RenderObject? ancestor = box.parent;
      RenderObject child = box;
      while (ancestor != null) {
        var painted = ancestor.paintsChild(child);
        // IndexedStack 给隐藏子项也保留布局与坐标，不能仅凭矩形判断。
        if (ancestor is RenderIndexedStack) {
          RenderBox? selected = ancestor.firstChild;
          for (var i = 0; i < (ancestor.index ?? -1) && selected != null; i++) {
            selected = ancestor.childAfter(selected);
          }
          painted = ancestor.index != null && identical(selected, child);
        }
        if (!painted) {
          rect = Rect.zero;
          break;
        }
        if (ancestor is RenderAbstractViewport) {
          final bounds = MatrixUtils.transformRect(
            ancestor.getTransformTo(null),
            ancestor.paintBounds,
          );
          rect = rect.intersect(bounds);
        }
        child = ancestor;
        ancestor = ancestor.parent;
      }
      final view = View.of(context);
      rect = rect.intersect(
        Offset.zero & (view.physicalSize / view.devicePixelRatio),
      );
      final visible = rect.width > 0 && rect.height > 0;
      if (_visible != visible) {
        _visible = visible;
        widget.onVisible(visible);
      }
    });
  }

  @override
  void dispose() {
    for (final position in _positions) {
      position.removeListener(_schedule);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _LayoutObserver(onLayout: _schedule, child: widget.child);
}

class _LayoutObserver extends SingleChildRenderObjectWidget {
  const _LayoutObserver({required this.onLayout, required super.child});
  final VoidCallback onLayout;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ObservedBox(onLayout);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _ObservedBox renderObject,
  ) {
    renderObject.onLayout = onLayout;
  }
}

class _ObservedBox extends RenderProxyBox {
  _ObservedBox(this.onLayout);
  VoidCallback onLayout;

  @override
  void performLayout() {
    super.performLayout();
    onLayout();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // 下拉菜单淡入只重绘、不重新布局；首次真正绘制时重新判断可见性。
    onLayout();
    super.paint(context, offset);
  }
}
