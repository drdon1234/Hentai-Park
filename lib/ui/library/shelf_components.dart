import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../kit/kit.dart';

/// Segments of the shelf tab. Updates matter only for serialized comics and subscriptions, so
/// they live here instead of taking a navigation destination of their own.
enum ShelfSegment { favorites, updates }

class ShelfScope extends InheritedWidget {
  const ShelfScope({
    super.key,
    required this.segment,
    required this.unseenUpdates,
    required this.onSelect,
    required super.child,
  });
  final ShelfSegment segment;
  final int unseenUpdates;
  final ValueChanged<ShelfSegment> onSelect;

  static ShelfScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShelfScope>();

  @override
  bool updateShouldNotify(ShelfScope old) =>
      old.segment != segment || old.unseenUpdates != unseenUpdates;
}

/// Page title for a shelf segment: the segment switcher inside the shelf, a plain title when the
/// page is opened on its own.
class ShelfTitle extends StatelessWidget {
  const ShelfTitle(this.fallback, {super.key});
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final scope = ShelfScope.of(context);
    if (scope == null) return Text(fallback);
    return HeaderTabs(
      tabs: [
        HeaderTab(tr('收藏夹')),
        HeaderTab(tr('更新'), count: scope.unseenUpdates),
      ],
      selected: scope.segment.index,
      onSelected: (i) => scope.onSelect(ShelfSegment.values[i]),
    );
  }

  /// Whether the page is shown inside the shelf (and so uses the large page header).
  static bool embedded(BuildContext context) => ShelfScope.of(context) != null;
}
