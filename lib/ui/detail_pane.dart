import 'package:flutter/material.dart';

import '../core/models.dart';

/// On wide screens the shell shows a work's page beside the list it was opened from
/// instead of covering the list. Pages pushed on top of the shell are not inside this
/// scope, so they keep opening works as full pages.
class DetailPane extends InheritedWidget {
  const DetailPane({
    super.key,
    required this.selected,
    required this.onShow,
    required super.child,
  });

  /// The work currently shown beside the list, if any.
  final String? selected;
  final ValueChanged<WorkItem> onShow;

  static DetailPane? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DetailPane>();

  @override
  bool updateShouldNotify(DetailPane oldWidget) =>
      oldWidget.selected != selected || oldWidget.onShow != onShow;
}
