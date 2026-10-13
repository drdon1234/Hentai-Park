import 'package:flutter/material.dart';

import '../../core/content_scope.dart';
import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../engine/source_manager.dart';
import '../../library/library.dart';

class HistoryScopeSelector extends StatelessWidget {
  const HistoryScopeSelector({
    super.key,
    required this.scope,
    required this.onChanged,
  });
  final ContentScope scope;
  final ValueChanged<ContentScope> onChanged;
  @override
  Widget build(BuildContext context) {
    final lib = Library.instance;
    final source = scope.sourceKey;
    final category =
        scope.category ??
        (source == null
            ? null
            : SourceManager.instance.manifest(source)?.category ??
                  lib
                      .history(source: source)
                      .map((h) => lib.domainOf(h.item))
                      .firstOrNull);
    final keys = {
      for (final h in lib.history())
        if (category == null || lib.domainOf(h.item) == category) h.item.source,
      for (final s in SourceManager.instance.all)
        if (s.manifest != null &&
            (category == null || s.manifest!.category == category))
          s.key,
      ?source,
    }.toList();
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Wrap(
          spacing: 16,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: (constraints.maxWidth - 24).clamp(0, 200),
              child: DropdownButton<SourceCategory>(
                isExpanded: true,
                value: category,
                hint: Text(tr('全部域')),
                items: [
                  DropdownMenuItem(value: null, child: Text(tr('全部域'))),
                  for (final d in AppSettings.instance.domainOrder)
                    DropdownMenuItem(value: d, child: Text(d.label)),
                ],
                onChanged: (d) => onChanged(
                  d == null ? const ContentScope.all() : ContentScope.domain(d),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: (constraints.maxWidth - 24).clamp(0, 360),
                maxWidth: (constraints.maxWidth - 24).clamp(0, double.infinity),
              ),
              child: DropdownButton<String>(
                isExpanded: true,
                value: source,
                hint: Text(tr('域内全部站点')),
                items: [
                  DropdownMenuItem(value: null, child: Text(tr('域内全部站点'))),
                  for (final key in keys)
                    DropdownMenuItem(
                      value: key,
                      child: Text(
                        SourceManager.instance.manifest(key)?.name ?? key,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (key) => onChanged(
                  key != null
                      ? ContentScope.source(key)
                      : category == null
                      ? const ContentScope.all()
                      : ContentScope.domain(category),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
