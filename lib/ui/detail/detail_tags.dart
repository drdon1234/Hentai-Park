import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../engine/source_manager.dart';
import '../../subscriptions/subscription_store.dart';
import '../../subscriptions/updater.dart';
import '../kit/adaptive_sheet.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/content_translation.dart';
import '../widgets/metadata_text_row.dart';
import '../widgets/text_translation.dart';

/// Shown above the description when the work matches the content filter.
class BlockedNotice extends StatelessWidget {
  const BlockedNotice({super.key, required this.tags});
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.m, Gap.page, 0),
      child: Row(
        children: [
          Icon(Icons.block_rounded, color: c.error, size: 18),
          const SizedBox(width: Gap.s),
          Expanded(
            child: Text(
              tr('包含已屏蔽的内容：{tags}', {'tags': tags.join(tr('、'))}),
              style: context.text.bodyMedium?.copyWith(color: c.error),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tag groups by namespace. Tap searches the tag on this site; long-press offers copy,
/// translate, subscribe and block.
class TagSection extends StatelessWidget {
  const TagSection({super.key, required this.detail, required this.source});
  final WorkDetail detail;
  final String source;

  void _search(BuildContext context, TagRef t) {
    Nav.openSourceSearch(
      context,
      source,
      keyword: t.keyword,
      filters: t.filters.isEmpty ? null : t.filters.cast<String, Object?>(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = [...detail.tagGroups];
    final hasAuthorGroup = groups.any(
      (g) => g.tags.any((t) => detail.authors.contains(t.name)),
    );
    final authorSearch = detail.authorSearch;
    final copy =
        SourceManager.instance.manifest(source)?.copy ?? PluginCopy.none;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.l, Gap.page, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hasAuthorGroup && detail.authors.isNotEmpty)
            _row(context, tr('作者'), [
              for (final a in detail.authors)
                _TagChip(
                  label: a,
                  source: source,
                  onTap: () => Nav.openSourceSearch(
                    context,
                    source,
                    keyword: (authorSearch?['keyword'] ?? a).toString(),
                    filters: (authorSearch?['filters'] as Map?)
                        ?.cast<String, Object?>(),
                  ),
                  subscriptionTag: TagRef(
                    a,
                    (authorSearch?['keyword'] ?? a).toString(),
                    (authorSearch?['filters'] as Map? ?? {})
                        .cast<String, dynamic>(),
                    null,
                  ),
                ),
            ]),
          for (final g in groups)
            _row(context, copy.text(g.label), [
              for (final t in g.tags)
                _TagChip(
                  label: t.name,
                  source: source,
                  onTap: () => _search(context, t),
                  count: t.count,
                  namespace: g.namespace,
                  subscriptionTag: t,
                ),
            ]),
          if (detail.uploader.isNotEmpty)
            MetadataTextRow(label: tr('上传者'), value: detail.uploader),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, List<Widget> chips) =>
      Padding(
        padding: const EdgeInsets.only(bottom: Gap.m),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 56,
              child: Padding(
                padding: const EdgeInsets.only(top: Gap.xs + 1),
                child: Text(
                  label,
                  style: context.text.labelMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Wrap(
                spacing: Gap.s - 2,
                runSpacing: Gap.s - 2,
                children: chips,
              ),
            ),
          ],
        ),
      );
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.source,
    required this.onTap,
    this.count,
    this.namespace = '',
    this.subscriptionTag,
  });
  final String label;
  final String source;
  final VoidCallback onTap;
  final int? count;
  final String namespace;
  final TagRef? subscriptionTag;

  Future<void> _menu(BuildContext context) async {
    final scoped = namespace.isEmpty ? null : '$namespace:$label';
    final canSubscribe =
        SourceManager.instance.manifest(source)?.can('subscriptionUpdates') ==
            true &&
        subscriptionTag != null;
    final action = await showAdaptiveSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: SelectionContainer.disabled(
                child: Text(scoped ?? label, style: ctx.text.titleMedium),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: SelectionContainer.disabled(child: Text(tr('复制'))),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.translate),
              title: SelectionContainer.disabled(child: Text(tr('翻译'))),
              onTap: () => Navigator.pop(ctx, 'translate'),
            ),
            if (canSubscribe)
              ListTile(
                leading: const Icon(Icons.notifications_none_rounded),
                title: SelectionContainer.disabled(child: Text(tr('订阅此标签更新'))),
                onTap: () => Navigator.pop(ctx, 'subscribe'),
              ),
            ListTile(
              leading: const Icon(Icons.block_rounded),
              title: SelectionContainer.disabled(
                child: Text(tr('屏蔽「{label}」', {'label': label})),
              ),
              onTap: () => Navigator.pop(ctx, 'block'),
            ),
            if (scoped != null)
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: SelectionContainer.disabled(
                  child: Text(tr('仅屏蔽「{label}」', {'label': scoped})),
                ),
                onTap: () => Navigator.pop(ctx, 'blockScoped'),
              ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'subscribe':
        final tag = subscriptionTag!;
        await SubscriptionStore.instance.load();
        await SubscriptionStore.instance.add(
          source: source,
          target: jsonEncode({'keyword': tag.keyword, 'filters': tag.filters}),
          label: label,
          dimension: 'filter',
        );
        unawaited(SubscriptionUpdater.instance.run(force: true));
        if (context.mounted) context.toast(tr('已添加更新订阅'));
      case 'translate':
        await showTextTranslation(
          context,
          label,
          source: source,
          namespace: namespace,
          tag: true,
        );
      case 'copy':
        await Clipboard.setData(ClipboardData(text: label));
        if (context.mounted) {
          context.toast(tr('已复制「{label}」', {'label': label}));
        }
      case 'block':
      case 'blockScoped':
        final entry = action == 'block' ? label : scoped!;
        AppSettings.instance.addBlockedTag(entry);
        context.toast(tr('已屏蔽「{label}」，列表中将隐藏带有该标签的作品', {'label': entry}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.small,
        side: BorderSide(color: c.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ActionInkWell(
        onTap: onTap,
        onLongPress: () => _menu(context),
        child: SelectionContainer.disabled(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            child: ContentTranslation(
              text: label,
              source: source,
              namespace: namespace,
              tag: true,
              builder: (value) => Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: value),
                    if (count != null)
                      TextSpan(
                        text: '  ${formatCount(count)}',
                        style: context.text.labelSmall?.copyWith(
                          color: c.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                style: context.text.labelLarge,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
