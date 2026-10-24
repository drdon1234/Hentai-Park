import 'package:flutter/material.dart';

import '../../core/content_scope.dart';
import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../engine/source_manager.dart';
import '../../library/library.dart';
import '../kit/kit.dart';

/// Narrows history to a category, then to one site within it.
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
    String siteName(String key) =>
        SourceManager.instance.manifest(key)?.name ?? key;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.s),
      child: Wrap(
        spacing: Gap.s,
        runSpacing: Gap.s,
        children: [
          MenuChip<SourceCategory?>(
            label: category?.label ?? tr('全部分类'),
            active: category != null,
            selected: category,
            options: {
              null: tr('全部分类'),
              for (final d in AppSettings.instance.domainOrder) d: d.label,
            },
            onSelected: (d) => onChanged(
              d == null ? const ContentScope.all() : ContentScope.domain(d),
            ),
          ),
          MenuChip<String?>(
            label: source == null ? tr('全部站点') : siteName(source),
            active: source != null,
            selected: source,
            options: {
              null: tr('全部站点'),
              for (final key in keys) key: siteName(key),
            },
            onSelected: (key) => onChanged(
              key != null
                  ? ContentScope.source(key)
                  : category == null
                  ? const ContentScope.all()
                  : ContentScope.domain(category),
            ),
          ),
        ],
      ),
    );
  }
}
