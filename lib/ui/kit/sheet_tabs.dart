import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 分页设置面板：短页随内容收紧，长页在可用高度内独立滚动。
/// [children] 应使用 shrinkWrap 的滚动列表，并提供独立的 PageStorageKey。
class SheetTabs extends StatelessWidget {
  const SheetTabs({
    super.key,
    required this.tabs,
    required this.children,
    this.isScrollable = false,
  }) : assert(tabs.length == children.length);

  final List<Widget> tabs;
  final List<Widget> children;
  final bool isScrollable;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: tabs.length,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TabBar(
            isScrollable: isScrollable,
            tabAlignment: isScrollable ? TabAlignment.start : TabAlignment.fill,
            tabs: tabs,
          ),
          Flexible(
            child: Builder(
              builder: (context) {
                final controller = DefaultTabController.of(context);
                var dragDistance = 0.0;
                return AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) => GestureDetector(
                    onHorizontalDragStart: (_) => dragDistance = 0,
                    onHorizontalDragUpdate: (details) =>
                        dragDistance += details.primaryDelta ?? 0,
                    onHorizontalDragEnd: (details) {
                      final velocity = details.primaryVelocity ?? 0;
                      final fling = velocity.abs() >= kMinFlingVelocity;
                      if (!fling && dragDistance.abs() < 48) return;
                      final direction = fling ? velocity : dragDistance;
                      final forward =
                          Directionality.of(context) == TextDirection.ltr
                          ? direction < 0
                          : direction > 0;
                      final next = (controller.index + (forward ? 1 : -1))
                          .clamp(0, children.length - 1);
                      if (next != controller.index) controller.animateTo(next);
                    },
                    child: children[controller.index],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
