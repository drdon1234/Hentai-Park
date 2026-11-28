import 'package:flutter/widgets.dart';

/// 页面悬浮操作在侧边安全区内的停靠位。一侧安全区明显更宽时（如 iPhone Duo 外屏右侧状态区），
/// 由路由边界（`SystemNavBoundary`）在该侧安全区内展示，不再遮挡列表内容。
class SideDock extends InheritedWidget {
  const SideDock({
    super.key,
    required this.slot,
    required this.active,
    required super.child,
  });

  /// 当前停靠的操作及其所属页面。
  final ValueNotifier<SideDockEntry?> slot;

  /// 当前是否存在可停靠的侧边安全区。
  final bool active;

  static SideDock? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SideDock>();

  @override
  bool updateShouldNotify(SideDock oldWidget) =>
      oldWidget.active != active || !identical(oldWidget.slot, slot);
}

typedef SideDockEntry = ({Object owner, Widget child});

/// 可停靠的悬浮操作：有侧边停靠位时移入侧边安全区并在原位置不占空间，否则原地显示。
class SideDockable extends StatefulWidget {
  const SideDockable({super.key, required this.child});

  final Widget child;

  @override
  State<SideDockable> createState() => _SideDockableState();
}

class _SideDockableState extends State<SideDockable> {
  SideDock? _dock;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dock = SideDock.maybeOf(context);
    if (!identical(dock?.slot, _dock?.slot)) _withdraw(_dock?.slot);
    _dock = dock;
  }

  @override
  void dispose() {
    _withdraw(_dock?.slot);
    super.dispose();
  }

  // 停靠位在构建阶段之外更新，避免构建期间通知另一棵子树。
  void _publish(ValueNotifier<SideDockEntry?> slot, Widget child) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_dock?.slot, slot) || _dock?.active != true) {
        return;
      }
      slot.value = (owner: this, child: child);
    });
  }

  void _withdraw(ValueNotifier<SideDockEntry?>? slot) {
    if (slot == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (identical(slot.value?.owner, this)) slot.value = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dock = _dock;
    if (dock != null && dock.active) {
      _publish(dock.slot, widget.child);
      return const SizedBox.shrink();
    }
    _withdraw(dock?.slot);
    return widget.child;
  }
}
