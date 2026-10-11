import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/tag_blocklist.dart';
import '../theme.dart';
import 'common.dart';
import 'error_view.dart';
import 'work_card.dart';
import '../../core/localization.dart';

typedef PageLoader = Future<WorkPage> Function(int page, String? cursor);

/// Infinite-scroll state for a cursor- or page-based listing.
class PagedController extends ChangeNotifier {
  PagedController(this.loader, {required this.source});

  PageLoader loader;
  final String source;
  final List<WorkItem> items = [];
  final Set<String> _seen = {};

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
  String? _cursor;
  int _generation = 0;
  bool _disposed = false;

  Future<void> refresh() async {
    _generation++;
    items.clear();
    _seen.clear();
    hidden = 0;
    _emptyPages = 0;
    sections = null;
    error = null;
    hasNext = true;
    page = 0;
    _cursor = null;
    totalPages = null;
    loading = false;
    _notify();
    await loadMore();
  }

  Future<void> loadMore() async {
    if (loading || !hasNext) return;
    final gen = _generation;
    loading = true;
    error = null;
    _notify();
    try {
      final result = await loader(page + 1, _cursor);
      if (gen != _generation) return;
      page = result.page > page ? result.page : page + 1;
      _cursor = result.cursor;
      totalPages = result.totalPages ?? totalPages;
      total = result.total ?? total;
      var added = 0;
      var shown = 0;
      final blocklist = TagBlocklist.current();
      if (result.sections != null) {
        sections = [for (final s in result.sections!) WorkSection(s.title, s.items.where((e) => blocklist.matchItem(e) == null).toList())];
      }
      for (final item in result.items) {
        if (_seen.add(item.id)) {
          added++;
          if (blocklist.matchItem(item) != null) {
            hidden++;
            continue;
          }
          items.add(item);
          shown++;
        }
      }
      hasNext = result.hasNext && (result.items.isEmpty ? false : true) && (added > 0 || result.cursor != null);
      // A page where everything was filtered would leave nothing to scroll to; fetch on (a few times).
      _emptyPages = shown == 0 ? _emptyPages + 1 : 0;
      if (shown == 0 && hasNext && _emptyPages <= 3) {
        Future.microtask(() {
          if (gen == _generation) loadMore();
        });
      }
    } catch (e) {
      if (gen != _generation) return;
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
    this.padding = const EdgeInsets.fromLTRB(12, 8, 12, 24),
  });
  final PagedController controller;
  final MediaKind kind;
  final bool showSource;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        if (c.sections != null) return _SectionsSliver(controller: c);
        if (c.items.isEmpty) {
          if (c.error != null) {
            return SliverFillRemaining(
              hasScrollBody: false,
              child: SourceErrorView(error: c.error!, source: c.source, onRetry: c.refresh),
            );
          }
          if (!c.loading && !c.hasNext) {
            return SliverFillRemaining(
              hasScrollBody: false,
              child: MessageView(icon: Icons.search_off_rounded, title: tr('这里什么都没有'), message: tr('换个关键词或筛选条件试试')),
            );
          }
          return _skeletonGrid(context);
        }
        final aspect = gridAspectFor(c.items, kind);
        return SliverLayoutBuilder(
          builder: (context, constraints) {
            final cols = gridColumnsFor(constraints.crossAxisExtent);
            final cardWidth = (constraints.crossAxisExtent - padding.horizontal - (cols - 1) * 10) / cols;
            final extraText = cardTextExtent(context);
            return SliverMainAxisGroup(
              slivers: [
                SliverPadding(
                  padding: padding.copyWith(bottom: 0),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 14,
                      mainAxisExtent: cardWidth / aspect + extraText,
                    ),
                    delegate: SliverChildBuilderDelegate((context, i) {
                      if (i >= c.items.length - cols * 3 && c.hasNext && !c.loading && c.error == null) {
                        WidgetsBinding.instance.addPostFrameCallback((_) => c.loadMore());
                      }
                      return WorkCard(item: c.items[i], aspect: aspect, showSource: showSource);
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
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: FilledButton.tonalIcon(
            onPressed: c.loadMore,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(tr('加载失败，点击重试  {value0}', {'value0': c.error!.asSourceError.code})),
          ),
        ),
      );
    }
    if (c.loading)
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))),
      );
    if (!c.hasNext) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(
            tr('· 已经到底了 · 共 {value0} 部{value1} ·', {'value0': c.items.length, 'value1': c.hidden > 0 ? tr('（已屏蔽 {value0} 部）', {'value0': c.hidden}) : ''}),
            style: context.text.labelMedium?.copyWith(color: context.colors.onSurfaceVariant),
          ),
        ),
      );
    }
    return const SizedBox(height: 40);
  }

  Widget _skeletonGrid(BuildContext context) {
    final aspect = kind == MediaKind.video ? 16 / 9 : 0.7;
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final cols = gridColumnsFor(constraints.crossAxisExtent);
        final cardWidth = (constraints.crossAxisExtent - padding.horizontal - (cols - 1) * 10) / cols;
        return SliverMainAxisGroup(
          slivers: [
            const SliverToBoxAdapter(child: LoadingIndicator(padding: EdgeInsets.fromLTRB(16, 16, 16, 4))),
            SliverPadding(
              padding: padding,
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 14,
                  mainAxisExtent: cardWidth / aspect + cardTextExtent(context),
                ),
                delegate: SliverChildBuilderDelegate((_, __) => WorkCardSkeleton(aspect: aspect), childCount: cols * 4),
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
    AppLocalizations.of(context);
    final sections = controller.sections!;
    return SliverList.builder(
      itemCount: sections.length,
      itemBuilder: (context, i) => WorkCarousel(title: sections[i].title, items: sections[i].items),
    );
  }
}

/// Horizontal strip of cards with a header.
class WorkCarousel extends StatelessWidget {
  const WorkCarousel({super.key, required this.title, required this.items, this.leading, this.trailing, this.showSource = false, this.height});
  final String title;
  final List<WorkItem> items;
  final Widget? leading;
  final Widget? trailing;
  final bool showSource;
  final double? height;

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    if (items.isEmpty) return const SizedBox.shrink();
    final aspect = gridAspectFor(items, kindOf(items.first.source));
    final cardWidth = aspect > 1 ? 200.0 : 118.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title, leading: leading, trailing: trailing),
        SizedBox(
          height: height ?? cardWidth / aspect + cardTextExtent(context),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) => SizedBox(
              width: cardWidth,
              child: WorkCard(item: items[i], aspect: aspect, showSource: showSource),
            ),
          ),
        ),
      ],
    );
  }
}
