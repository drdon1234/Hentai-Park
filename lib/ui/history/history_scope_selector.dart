import 'package:flutter/material.dart';

import '../../core/content_scope.dart';
import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../engine/source_manager.dart';
import '../../library/library.dart';
import '../kit/kit.dart';
import '../theme.dart';

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
          _ScopeMenu<SourceCategory?>(
            label: category?.label ?? tr('全部分类'),
            active: category != null,
            options: {
              null: tr('全部分类'),
              for (final d in AppSettings.instance.domainOrder) d: d.label,
            },
            onSelected: (d) => onChanged(
              d == null ? const ContentScope.all() : ContentScope.domain(d),
            ),
          ),
          _ScopeMenu<String?>(
            label: source == null ? tr('全部站点') : siteName(source),
            active: source != null,
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

class _ScopeMenu<T> extends StatelessWidget {
  const _ScopeMenu({
    required this.label,
    required this.active,
    required this.options,
    required this.onSelected,
  });
  final String label;
  final bool active;
  final Map<T, String> options;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Indexes rather than values: a null value would read as a cancelled menu.
    final entries = options.entries.toList();
    return PopupMenuButton<int>(
      popUpAnimationStyle: Motion.menu(context),
      tooltip: label,
      onSelected: (i) => onSelected(entries[i].key),
      itemBuilder: (_) => [
        for (var i = 0; i < entries.length; i++)
          PopupMenuItem(
            value: i,
            child: SelectionContainer.disabled(child: Text(entries[i].value)),
          ),
      ],
      child: SelectionContainer.disabled(
        child: Container(
          constraints: const BoxConstraints(minHeight: 36, maxWidth: 240),
          padding: const EdgeInsets.only(left: Gap.m, right: Gap.s),
          decoration: BoxDecoration(
            color: active ? c.secondaryContainer : null,
            border: Border.all(
              color: active ? c.secondaryContainer : c.outlineVariant,
            ),
            borderRadius: Radii.small,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelLarge?.copyWith(
                    color: active ? c.onSecondaryContainer : c.onSurface,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_drop_down_rounded,
                color: active ? c.onSecondaryContainer : c.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
