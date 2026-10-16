import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../updates/updates_page.dart';
import 'library_page.dart';
import 'shelf_components.dart';

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
