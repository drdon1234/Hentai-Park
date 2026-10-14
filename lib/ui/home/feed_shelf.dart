import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../core/tag_blocklist.dart';
import '../../engine/source_manager.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/cover_tile.dart';
import '../widgets/on_visible.dart';
import '../widgets/source_network_hint.dart';
import '../widgets/work_text_row.dart';

/// A horizontal shelf with the first page of a site's default feed. It requests only once it
/// scrolls into view, so the home page never fans out to every site at launch.
class FeedShelf extends StatefulWidget {
  const FeedShelf({
    super.key,
    required this.sourceKey,
    required this.title,
    this.onMore,
    this.moreLabel,
    this.onConfigure,
  });
  final String sourceKey;
  final String title;
  final VoidCallback? onMore;
  final String? moreLabel;
  final VoidCallback? onConfigure;

  static final _pages = <String, Future<List<WorkItem>>>{};
  static final refreshes = ValueNotifier(0);
  static Future<List<WorkItem>> cachedItems(
    String key,
    Future<List<WorkItem>> Function() load,
  ) async {
    final pending = _pages.putIfAbsent(key, load);
    try {
      return await pending;
    } catch (_) {
      if (identical(_pages[key], pending)) {
        _pages.remove(key)?.ignore();
      }
      rethrow;
    }
  }

  static void refreshAll() {
    _pages.clear();
    refreshes.value++;
  }

  @override
  State<FeedShelf> createState() => _FeedShelfState();
}

class _FeedShelfState extends State<FeedShelf>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  List<WorkItem>? _items;
  Object? _error;
  bool _loading = false;
  bool _visible = false;
  late final Listenable _filters = AppSettings.instance.watch(
    AppSettings.filterKeys,
  );

  @override
  void initState() {
    super.initState();
    _filters.addListener(_filtersChanged);
    FeedShelf.refreshes.addListener(_refresh);
  }

  @override
  void dispose() {
    _filters.removeListener(_filtersChanged);
    FeedShelf.refreshes.removeListener(_refresh);
    super.dispose();
  }

  void _filtersChanged() {
    if (mounted) setState(() {});
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _items = null;
      _error = null;
    });
    if (_visible) unawaited(_load());
  }

  @override
  void didUpdateWidget(FeedShelf old) {
    super.didUpdateWidget(old);
    if (old.sourceKey != widget.sourceKey) {
      _items = null;
      _error = null;
      if (_visible) unawaited(_load());
    }
  }

  void _onVisible(bool visible) {
    _visible = visible;
    if (visible && _items == null && _error == null) unawaited(_load());
  }

  Future<void> _load() async {
    if (_loading) return;
    final key = widget.sourceKey;
    final manifest = SourceManager.instance.manifest(key);
    if (manifest == null || manifest.feeds.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final generation = FeedShelf.refreshes.value;
    try {
      final feed = manifest.feeds[manifest.defaultFeedIndex];
      final page = await FeedShelf.cachedItems(key, () async {
        final page = await SourceManager.instance.feed(
          key,
          feed.key,
          options: feed.defaultOptions(),
          refresh: generation > 0,
        );
        return [
          ...?page.sections?.expand((section) => section.items),
          ...page.items,
        ].take(24).toList();
      });
      if (!mounted || key != widget.sourceKey) return;
      if (generation != FeedShelf.refreshes.value) return;
      setState(() => _items = page);
    } catch (error) {
      if (mounted &&
          key == widget.sourceKey &&
          generation == FeedShelf.refreshes.value) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (_visible && _items == null && _error == null) unawaited(_load());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final manifest = SourceManager.instance.manifest(widget.sourceKey);
    final blocklist = TagBlocklist.current();
    final items = _items
        ?.where((item) => blocklist.matchItem(item) == null)
        .toList();
    final novel = manifest?.isNovel == true;
    final Widget body;
    if (_error != null) {
      body = _ShelfMessage(
        message: _error!.asSourceError.friendly,
        source: widget.sourceKey,
        onRetry: _load,
      );
    } else if (items == null) {
      // A shelf waiting to scroll into view keeps a still placeholder; only a
      // request in flight shimmers, so an idle home page draws no frames.
      body = TickerMode(
        enabled: _loading,
        child: _ShelfSkeleton(
          aspect: manifest?.isVideo == true ? 16 / 9 : .7,
          novel: novel,
          source: widget.sourceKey,
        ),
      );
    } else if (items.isEmpty) {
      body = _ShelfMessage(message: tr('暂时没有内容'), onRetry: _load);
    } else if (novel) {
      body = Column(
        children: [for (final item in items.take(4)) WorkTextRow(item: item)],
      );
    } else {
      final aspect = gridAspectFor(items, manifest?.kind ?? MediaKind.comic);
      final width = aspect > 1 ? 200.0 : 112.0;
      body = SizedBox(
        height: width / aspect + cardTextExtent(context),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Gap.page),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: Gap.m),
          itemBuilder: (context, i) => SizedBox(
            width: width,
            child: CoverTile(item: items[i], aspect: aspect),
          ),
        ),
      );
    }
    return OnVisible(
      onVisible: _onVisible,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            widget.title,
            leading: SourceAvatar(widget.sourceKey, size: 22),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.onConfigure != null)
                  IconButton(
                    tooltip: tr('选择展示站点'),
                    icon: const Icon(Icons.tune_rounded),
                    onPressed: widget.onConfigure,
                  ),
                if (widget.onMore != null)
                  TextButton(
                    onPressed: widget.onMore,
                    child: Text(widget.moreLabel ?? tr('全部')),
                  ),
              ],
            ),
          ),
          AnimatedSwitcher(
            duration: Motion.of(context, Motion.medium),
            child: KeyedSubtree(
              key: ValueKey(
                _error != null
                    ? 'error'
                    : items == null
                    ? 'loading'
                    : 'items',
              ),
              child: body,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShelfSkeleton extends StatelessWidget {
  const _ShelfSkeleton({
    required this.aspect,
    required this.novel,
    required this.source,
  });
  final double aspect;
  final bool novel;
  final String source;

  @override
  Widget build(BuildContext context) {
    final width = aspect > 1 ? 200.0 : 112.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (novel)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: Gap.page),
            child: Column(
              children: [
                Skeleton(height: 16),
                SizedBox(height: Gap.s),
                Skeleton(height: 16),
              ],
            ),
          )
        else
          SizedBox(
            height: width / aspect + cardTextExtent(context),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: Gap.page),
              itemCount: 6,
              separatorBuilder: (_, _) => const SizedBox(width: Gap.m),
              itemBuilder: (_, _) => SizedBox(
                width: width,
                child: CoverTileSkeleton(aspect: aspect),
              ),
            ),
          ),
        SourceNetworkHint(source: source),
      ],
    );
  }
}

class _ShelfMessage extends StatelessWidget {
  const _ShelfMessage({required this.message, this.onRetry, this.source});
  final String message;
  final VoidCallback? onRetry;
  final String? source;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.s, Gap.s),
    child: Row(
      children: [
        Expanded(
          child: Text(
            message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: Text(tr('重试'))),
      ],
    ),
  );
}
