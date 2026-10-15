import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../kit/kit.dart';
import '../updates/updates_page.dart';
import 'library_page.dart';

/// Segments of the shelf tab. Updates matter only for serialized comics and subscriptions, so
/// they live here instead of taking a navigation destination of their own.
enum ShelfSegment { favorites, updates }

/// The shelf: 收藏 · 更新. Each segment keeps its own page bar; [ShelfTitle] turns that
/// bar's title into the segment switcher.
class ShelfPage extends StatefulWidget {
  const ShelfPage({
    super.key,
    required this.segment,
    required this.unseenUpdates,
  });
  final ValueNotifier<ShelfSegment> segment;
  final ValueListenable<int> unseenUpdates;

  @override
  State<ShelfPage> createState() => _ShelfPageState();
}

class _ShelfPageState extends State<ShelfPage> {
  final _visited = <ShelfSegment>{};

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.segment, widget.unseenUpdates]),
    builder: (context, _) {
      final segment = widget.segment.value;
      _visited.add(segment);
      return ShelfScope(
        segment: segment,
        unseenUpdates: widget.unseenUpdates.value,
        onSelect: (value) => widget.segment.value = value,
        child: IndexedStack(
          index: segment.index,
          children: [
            for (final s in ShelfSegment.values)
              if (!_visited.contains(s))
                const SizedBox.shrink()
              else
                switch (s) {
                  ShelfSegment.favorites => const LibraryPage(),
                  ShelfSegment.updates => const UpdatesPage(),
                },
          ],
        ),
      );
    },
  );
}

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
