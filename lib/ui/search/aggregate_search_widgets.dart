import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/content_scope.dart';
import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../core/tag_blocklist.dart';
import '../../engine/source_manager.dart';
import '../../subscriptions/models.dart';
import '../nav.dart';
import '../subscriptions/subscription_posts_page.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/cover_tile.dart';
import '../widgets/error_view.dart';
import '../widgets/source_network_hint.dart';
import '../widgets/work_text_row.dart';
import 'aggregate_search_controller.dart';
import 'multi_language.dart';
import 'source_search_page.dart';

class DirectJump extends StatelessWidget {
  const DirectJump({super.key, required this.refs, this.sourceManager});
  final List<({String source, String id})> refs;
  final SourceManager? sourceManager;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(tr('直达作品')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.page),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in refs)
                ActionChip(
                  avatar: SourceAvatar(r.source, size: 22),
                  label: SelectionContainer.disabled(
                    child: Text(
                      '${(sourceManager ?? SourceManager.instance).manifest(r.source)?.name ?? r.source}  ${r.id}',
                    ),
                  ),
                  onPressed: () => Nav.openRef(
                    context,
                    r.source,
                    r.id,
                    sourceManager: sourceManager,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class SearchScopeBar extends StatelessWidget {
  const SearchScopeBar({
    super.key,
    required this.sources,
    required this.scope,
    required this.onToggle,
  });
  final List<InstalledSource> sources;
  final void Function(String key, bool included) onToggle;
  final Set<String> scope;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.m),
          child: Text(tr('参与搜索的站点'), style: context.text.titleLarge),
        ),
        for (final category in AppSettings.instance.domainOrder)
          if (sources.any((s) => s.manifest!.category == category))
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.label,
                    style: context.text.labelLarge?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Gap.s),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in sources.where(
                        (s) => s.manifest!.category == category,
                      ))
                        FilterChip(
                          avatar: SourceAvatar(s.key, size: 20),
                          label: SelectionContainer.disabled(
                            child: Text(s.name),
                          ),
                          selected: scope.contains(s.key),
                          showCheckmark: false,
                          onSelected: (on) {
                            HapticFeedback.selectionClick();
                            onToggle(s.key, on);
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class SearchHistoryList extends StatelessWidget {
  const SearchHistoryList({
    super.key,
    required this.onPick,
    required this.scope,
  });
  final ContentScope scope;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final history = AppSettings.instance.searchHistoryFor(scope);
    if (history.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          tr('最近搜索'),
          trailing: OutlinedButton(
            onPressed: () =>
                AppSettings.instance.clearSearchHistory(scope: scope),
            child: SelectionContainer.disabled(child: Text(tr('清空'))),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.page),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in history)
                InputChip(
                  label: SelectionContainer.disabled(child: Text(k)),
                  onPressed: () => onPick(k),
                  onDeleted: () =>
                      AppSettings.instance.removeSearchHistory(k, scope: scope),
                  deleteIconColor: context.colors.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class SourceResultsRow extends StatelessWidget {
  const SourceResultsRow({
    super.key,
    required this.source,
    required this.keyword,
    this.multi,
    required this.result,
    required this.onRetry,
    required this.manifest,
  });
  final SourceManifest manifest;
  final String source, keyword;
  final MultiKeyword? multi;
  final AggregateResult result;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final m = manifest;
    final header = SectionHeader(
      m.name,
      leading: SourceAvatar(source, size: 22),
      trailing: OutlinedButton(
        onPressed: () => multi != null
            ? Nav.push(
                context,
                SourceSearchPage(
                  sourceKey: source,
                  initialKeyword: keyword,
                  initialMulti: multi,
                ),
              )
            : Nav.openSourceSearch(context, source, keyword: keyword),
        child: SelectionContainer.disabled(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (result.loading) ...[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
              ],
              if (result.page != null && (result.page!.total ?? 0) > 0)
                Text(
                  tr('{count} 部 ', {'count': formatCount(result.page!.total)}),
                  style: context.text.labelMedium,
                ),
              Text(tr('全部')),
              const Icon(Icons.chevron_right_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
    final kind = m.kind;
    final aspect = kind == MediaKind.video ? 16 / 9 : 0.7;
    final cardWidth = aspect > 1 ? 200.0 : 118.0;
    Widget body;
    if (result.loading) {
      body = kind == MediaKind.novel
          ? Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Skeleton(height: 18),
                ),
                SourceNetworkHint(source: source),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: cardWidth / aspect + cardTextExtent(context),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: Gap.page),
                    itemCount: 5,
                    physics: const NeverScrollableScrollPhysics(),
                    separatorBuilder: (_, _) => const SizedBox(width: Gap.m),
                    itemBuilder: (_, _) => SizedBox(
                      width: cardWidth,
                      child: CoverTileSkeleton(aspect: aspect),
                    ),
                  ),
                ),
                SourceNetworkHint(source: source),
              ],
            );
    } else if (result.error != null) {
      // A failing site reports in its own group; the other results stay put.
      body = SourceErrorView(
        error: result.error!,
        source: source,
        compact: true,
        onRetry: onRetry,
      );
    } else if (result.page!.items.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          tr('没有找到相关作品'),
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      );
    } else {
      final blocklist = TagBlocklist.current();
      final items = result.page!.items
          .where((e) => blocklist.matchItem(e) == null)
          .toList();
      if (items.isEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                tr('（已屏蔽 {value0} 部）', {'value0': result.page!.items.length}),
                style: context.text.bodySmall,
              ),
            ),
          ],
        );
      }
      final a = gridAspectFor(items, kind);
      final w = a > 1 ? 200.0 : 118.0;
      body = kind == MediaKind.novel
          ? Column(
              children: [for (final item in items) WorkTextRow(item: item)],
            )
          : items.any((item) => item.json['presentation'] == 'post')
          ? Column(
              children: [
                for (final item in items)
                  SubscriptionPostCard(
                    source: item.source,
                    post: SubscriptionPost(item.json),
                  ),
              ],
            )
          : SizedBox(
              height: w / a + cardTextExtent(context),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Gap.page),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: Gap.m),
                itemBuilder: (context, i) => SizedBox(
                  width: w,
                  child: CoverTile(item: items[i], aspect: a),
                ),
              ),
            );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [header, body],
    );
  }
}

/// A compact menu in a chip, for choosing one value from a short list.
class MenuChip<T> extends StatelessWidget {
  const MenuChip({
    super.key,
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
        child: IgnorePointer(
          child: FilterChip(
            label: SelectionContainer.disabled(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down_rounded),
                ],
              ),
            ),
            selected: active,
            showCheckmark: false,
            onSelected: (_) {},
          ),
        ),
      ),
    );
  }
}
