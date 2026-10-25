import 'package:flutter/material.dart';

import '../../core/content_scope.dart';
import '../../library/library.dart';
import '../widgets/content_scope_selector.dart';

/// Compatibility wrapper for history callers; the selector itself is shared.
class HistoryScopeSelector extends StatelessWidget {
  const HistoryScopeSelector({
    super.key,
    required this.scope,
    required this.onChanged,
  });
  final ContentScope scope;
  final ValueChanged<ContentScope> onChanged;

  @override
  Widget build(BuildContext context) => ContentScopeSelector(
    scope: scope,
    onChanged: onChanged,
    items: [for (final h in Library.instance.history()) h.item],
  );
}
