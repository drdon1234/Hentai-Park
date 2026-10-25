import 'package:flutter/material.dart';

import '../../core/content_scope.dart';
import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../engine/source_manager.dart';
import '../../library/library.dart';
import '../kit/kit.dart';

/// Shared category/site scope selector for user-owned work collections.
class ContentScopeSelector extends StatelessWidget {
  const ContentScopeSelector({
    super.key,
    required this.scope,
    required this.onChanged,
    required this.items,
  });

  final ContentScope scope;
  final ValueChanged<ContentScope> onChanged;
  final Iterable<WorkItem> items;

  @override
  Widget build(BuildContext context) {
    final allItems = items.toList(growable: false);
    final source = scope.sourceKey;
    final category =
        scope.category ??
        (source == null
            ? null
            : SourceManager.instance.manifest(source)?.category ??
                  allItems
                      .where((item) => item.source == source)
                      .map(Library.instance.domainOf)
                      .firstOrNull);
    final keys = {
      for (final item in allItems)
        if (category == null || Library.instance.domainOf(item) == category)
          item.source,
      for (final session in SourceManager.instance.all)
        if (session.manifest != null &&
            (category == null || session.manifest!.category == category))
          session.key,
      ?source,
    }.toList();
    keys.sort((a, b) => siteName(a).compareTo(siteName(b)));

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
            onSelected: (value) => onChanged(
              value == null
                  ? const ContentScope.all()
                  : ContentScope.domain(value),
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
            onSelected: (value) => onChanged(
              value != null
                  ? ContentScope.source(value)
                  : category == null
                  ? const ContentScope.all()
                  : ContentScope.domain(category),
            ),
          ),
        ],
      ),
    );
  }

  static String siteName(String key) =>
      SourceManager.instance.manifest(key)?.name ??
      (key == 'local' ? tr('本地') : key);
}
