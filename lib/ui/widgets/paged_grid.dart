import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../core/tag_blocklist.dart';
import '../../engine/home_cache.dart';
import '../../subscriptions/models.dart';
import '../subscriptions/subscription_posts_page.dart';
import '../theme.dart';
import 'common.dart';
import 'cover_tile.dart';
import 'error_view.dart';
import 'source_network_hint.dart';
import 'work_text_row.dart';

typedef PageLoader = Future<WorkPage> Function(int page, String? cursor);

/// Infinite-scroll state for a cursor- or page-based listing.
class PagedController extends ChangeNotifier {
  PagedController(this.loader, {required this.source}) {
    _filters.addListener(_rulesChanged);
  }

  final _filters = AppSettings.instance.watch(AppSettings.filterKeys);

  PageLoader loader;
  final String source;
  final List<WorkItem> items = [];
  final Set<String> _seen = {};
  final _loaded = <WorkItem>[];
  List<WorkSection>? _rawSections;
  void _rulesChanged() {
    if (_disposed) return;
    final blocklist = TagBlocklist.current();
    items
      ..clear()
      ..addAll(_loaded.where((i) => blocklist.matchItem(i) == null));
    hidden = _loaded.length - items.length;
    if (_rawSections != null) {
      sections = [
        for (final s in _rawSections!)
          WorkSection(
            s.title,
            s.items.where((i) => blocklist.matchItem(i) == null).toList(),
          ),
      ];
    }
    _notify();
  }

  /// Works hidden by the tag blocklist so far.
  int hidden = 0;
  int _emptyPages = 0;
  List<WorkSection>? sections;
  Object? error;
  bool loading = false;
  bool hasNext = true;
  int page = 0;
  int? totalPages;
  int? total;
  bool staleCache = false;
  bool _preview = false;
  void Function(WorkPage) cachedReceiver() {
    final generation = _generation;
    return (cached) {
      if (generation == _generation) showCached(cached);
    };
  }

  /// 先显示可打开的缓存作品，不推进实时请求的页号或游标。
  void showCached(WorkPage cached) {
    if (_disposed || page != 0 || !loading) return;
    _preview = true;
    _loaded
      ..clear()
      ..addAll(cached.items);
    _rawSections = cached.sections;
    _rulesChanged();
  }

  String? _cursor;
  int _generation = 0;
  bool _disposed = false;

  Future<void> refresh() async {
    _generation++;
    items.clear();
    _seen.clear();
    _loaded.clear();
    _rawSections = null;
    hidden = 0;
    _emptyPages = 0;
    sections = null;
    error = null;
    hasNext = true;
    page = 0;
    _cursor = null;
    totalPages = null;
    total = null;
    staleCache = false;
    _preview = false;
    loading = false;
    _notify();
    await loadMore();
  }

  Future<void> loadMore() async {
    if (_disposed || loading || !hasNext) return;
    final gen = _generation;
    loading = true;
    error = null;
    _notify();
    try {
      final result = await loader(page + 1, _cursor);
      if (_disposed || gen != _generation) return;
      if (_preview) {
        _preview = false;
        _loaded.clear();
        items.clear();
        _seen.clear();
        hidden = 0;
        sections = null;
        _rawSections = null;
      }
      page = result.page > page ? result.page : page + 1;
      _cursor = result.cursor;
      totalPages = result.totalPages ?? totalPages;
      total = result.total ?? total;
      staleCache = staleCache || result.staleCache;
      var added = 0;
      var shown = 0;
      final blocklist = TagBlocklist.current();
      if (result.sections != null) {
        _rawSections = result.sections;
        sections = [
          for (final s in result.sections!)
            WorkSection(
              s.title,
              s.items.where((e) => blocklist.matchItem(e) == null).toList(),
            ),
        ];
      }
      for (final item in result.items) {
        if (_seen.add(item.id)) {
          _loaded.add(item);
          added++;
          if (blocklist.matchItem(item) != null) {
            hidden++;
            continue;
          }
          items.add(item);
          shown++;
        }
      }
      hasNext =
          result.hasNext &&
          (result.items.isNotEmpty || result.cursor != null) &&
          (added > 0 || result.cursor != null);
      // A page where everything was filtered would leave nothing to scroll to; fetch on (a few times).
      _emptyPages = shown == 0 ? _emptyPages + 1 : 0;
      if (shown == 0 && hasNext && _emptyPages <= 3) {
        unawaited(
          Future.microtask(() {
            if (gen == _generation) loadMore();
          }),
        );
      }
    } catch (e) {
      if (gen != _generation) return;
      if (_preview && HomeCache.invalidatesContent(e)) {
        _preview = false;
        _loaded.clear();
        items.clear();
        sections = null;
        _rawSections = null;
      }
      error = e;
    } finally {
      if (gen == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _filters.removeListener(_rulesChanged);
    super.dispose();
  }
}

/// Grid of works with skeletons, end-of-list states and auto-loading near the bottom.
/// Renders as slivers so it can live inside larger scroll views.
class PagedSliverGrid extends StatelessWidget {
  const PagedSliverGrid({
    super.key,
    required this.controller,
    required this.kind,
    this.showSource = false,
    this.padding = const EdgeInsets.fromLTRB(Gap.page, Gap.s, Gap.page, Gap.xl),
  });
  final PagedController controller;
  final MediaKind kind;
  final bool showSource;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        if (c.sections != null) {
          return SliverMainAxisGroup(
            slivers: [
              _SectionsSliver(controller: c),
              SliverToBoxAdapter(child: _footer(context)),
            ],
          );
        }
        if (c.items.isEmpty) {
          if (c.error != null) {
            return SliverFillRemaining(
              hasScrollBody: false,
              child: SourceErrorView(
                error: c.error!,
                source: c.source,
                onRetry: c.refresh,
              ),
            );
          }
          if (!c.loading && !c.hasNext) {
            return SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.search_off_rounded,
                title: tr('这里什么都没有'),
                message: tr('换个关键词或筛选条件试试'),
              ),
            );
          }
          if (!c.loading && c.hasNext) {
            return SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.filter_alt_outlined,
                title: tr('这里什么都没有'),
                message: c.hidden > 0
                    ? tr('（已屏蔽 {value0} 部）', {'value0': c.hidden})
                    : null,
                actions: [
                  FilledButton.tonalIcon(
                    onPressed: () {
                      c._emptyPages = 0;
                      c.loadMore();
                    },
                    icon: const Icon(Icons.expand_more_rounded),
                    label: SelectionContainer.disabled(child: Text(tr('继续加载'))),
                  ),
                ],
              ),
            );
          }
          return _skeletonGrid(context);
        }
        if (kind == MediaKind.novel ||
            c.items.any((item) => item.json['presentation'] == 'post')) {
          return SliverMainAxisGroup(
            slivers: [
              SliverList.builder(
                itemCount: c.items.length,
                itemBuilder: (context, i) {
                  if (i >= c.items.length - 3 &&
                      c.hasNext &&
                      !c.loading &&
                      c.error == null) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => c.loadMore(),
                    );
                  }
                  final item = c.items[i];
                  return item.json['presentation'] == 'post'
                      ? SubscriptionPostCard(
                          source: item.source,
                          post: SubscriptionPost(item.json),
                        )
                      : WorkTextRow(item: item, showSource: showSource);
                },
              ),
              SliverToBoxAdapter(child: _footer(context)),
            ],
          );
        }
        final aspect = gridAspectFor(c.items, kind);
        return SliverLayoutBuilder(
          builder: (context, constraints) {
            final cols = gridColumnsFor(constraints.crossAxisExtent);
            final cardWidth =
                (constraints.crossAxisExtent -
                    padding.horizontal -
                    (cols - 1) * Gap.m) /
                cols;
            final extraText = cardTextExtent(context);
            return SliverMainAxisGroup(
              slivers: [
                SliverPadding(
                  padding: padding.copyWith(bottom: 0),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      crossAxisSpacing: Gap.m,
                      mainAxisSpacing: Gap.l,
                      mainAxisExtent: cardWidth / aspect + extraText,
                    ),
                    delegate: SliverChildBuilderDelegate((context, i) {
                      if (i >= c.items.length - cols * 3 &&
                          c.hasNext &&
                          !c.loading &&
                          c.error == null) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => c.loadMore(),
                        );
                      }
                      return CoverTile(
                        item: c.items[i],
                        aspect: aspect,
                        showSource: showSource,
                      );
                    }, childCount: c.items.length),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: padding.bottom),
                    child: _footer(context),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _footer(BuildContext context) {
    final c = controller;
    if (c.error != null) {
      return SourceErrorView(
        error: c.error!,
        source: c.source,
        onRetry: c.loadMore,
        compact: true,
      );
    }
    if (c.loading) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            SourceNetworkHint(source: c.source),
          ],
        ),
      );
    }
    if (!c.hasNext) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(
            tr('· 已经到底了 · 共 {value0} 部{value1} ·', {
              'value0': c.items.length,
              'value1': c.hidden > 0
                  ? tr('（已屏蔽 {value0} 部）', {'value0': c.hidden})
                  : '',
            }),
            style: context.text.labelMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return const SizedBox(height: 40);
  }

  Widget _skeletonGrid(BuildContext context) {
    if (kind == MediaKind.novel) {
      return SliverToBoxAdapter(
        child: Column(
          children: [
            const LoadingIndicator(),
            SourceNetworkHint(source: controller.source),
            for (var i = 0; i < 6; i++)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Skeleton(height: 18),
                    SizedBox(height: 10),
                    Skeleton(height: 12),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    final aspect = kind == MediaKind.video ? 16 / 9 : 0.7;
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final cols = gridColumnsFor(constraints.crossAxisExtent);
        final cardWidth =
            (constraints.crossAxisExtent -
                padding.horizontal -
                (cols - 1) * Gap.m) /
            cols;
        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  const LoadingIndicator(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  ),
                  SourceNetworkHint(source: controller.source),
                ],
              ),
            ),
            SliverPadding(
              padding: padding,
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: Gap.m,
                  mainAxisSpacing: Gap.l,
                  mainAxisExtent: cardWidth / aspect + cardTextExtent(context),
                ),
                delegate: SliverChildBuilderDelegate(
                  (_, _) => CoverTileSkeleton(aspect: aspect),
                  childCount: cols * 4,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SectionsSliver extends StatelessWidget {
  const _SectionsSliver({required this.controller});
  final PagedController controller;

  @override
  Widget build(BuildContext context) {
    final sections = controller.sections!;
    return SliverList.builder(
      itemCount: sections.length,
      itemBuilder: (context, i) =>
          WorkCarousel(title: sections[i].title, items: sections[i].items),
    );
  }
}

/// Horizontal strip of cards with a header.
class WorkCarousel extends StatelessWidget {
  const WorkCarousel({
    super.key,
    required this.title,
    required this.items,
    this.leading,
    this.trailing,
    this.showSource = false,
    this.height,
  });
  final String title;
  final List<WorkItem> items;
  final Widget? leading;
  final Widget? trailing;
  final bool showSource;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    if (kindOf(items.first) == MediaKind.novel || items.first.isNovel) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title, leading: leading, trailing: trailing),
          for (final item in items)
            WorkTextRow(item: item, showSource: showSource),
        ],
      );
    }
    final aspect = gridAspectFor(items, kindOf(items.first));
    final cardWidth = aspect > 1 ? 200.0 : 118.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title, leading: leading, trailing: trailing),
        SizedBox(
          height: height ?? cardWidth / aspect + cardTextExtent(context),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Gap.page),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: Gap.m),
            itemBuilder: (context, i) => SizedBox(
              width: cardWidth,
              child: CoverTile(
                item: items[i],
                aspect: aspect,
                showSource: showSource,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
