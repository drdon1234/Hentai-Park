import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../engine/source_manager.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/option_bar.dart';
import '../widgets/paged_grid.dart';

/// A single source's own entry: one tab per feed (latest, ranking, categories…), each with the
/// source's native options (periods, categories, sort) as chips.
class SourcePage extends StatefulWidget {
  const SourcePage({super.key, required this.sourceKey, this.initialFeed});
  final String sourceKey;
  /// Feed tab to open; null = the source's default feed (manifest `defaultFeed`).
  final int? initialFeed;

  @override
  State<SourcePage> createState() => _SourcePageState();
}

class _SourcePageState extends State<SourcePage> {
  @override
  Widget build(BuildContext context) {
    final m = SourceManager.instance.manifest(widget.sourceKey);
    if (m == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const MessageView(icon: Icons.extension_off_outlined, title: '源未加载'),
      );
    }
    final account = SourceManager.instance[widget.sourceKey]?.account;
    final needsLogin = m.account?.required == true && account?.loggedIn != true;
    return Theme(
      // Tint the page with the source's brand color so each site feels distinct.
      data: ParkTheme.build(Theme.of(context).brightness, m.color),
      child: DefaultTabController(
        length: m.feeds.length,
        initialIndex: (widget.initialFeed ?? m.defaultFeedIndex).clamp(0, m.feeds.isEmpty ? 0 : m.feeds.length - 1),
        child: Builder(
          builder: (context) {
            return Scaffold(
              body: NestedScrollView(
                headerSliverBuilder: (context, inner) => [
                  SliverOverlapAbsorber(
                    handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
                    sliver: SliverAppBar(
                      pinned: true,
                      floating: true,
                      snap: true,
                      forceElevated: inner,
                      title: Row(
                        children: [
                          SourceAvatar(widget.sourceKey, size: 30),
                          const SizedBox(width: 10),
                          Flexible(child: Text(m.name, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                      actions: [
                        if (m.can('search'))
                          IconButton(tooltip: '搜索', icon: const Icon(Icons.search_rounded), onPressed: () => Nav.openSourceSearch(context, widget.sourceKey)),
                        if (m.can('random'))
                          TextButton(onPressed: () => Nav.random(context, widget.sourceKey), child: const Text('随机')),
                        IconButton(
                          tooltip: '源设置',
                          icon: Badge(isLabelVisible: needsLogin, smallSize: 8, child: const Icon(Icons.settings_outlined)),
                          onPressed: () async {
                            await Nav.openSourceSettings(context, widget.sourceKey);
                            if (mounted) setState(() {});
                          },
                        ),
                      ],
                      bottom: m.feeds.length > 1 ? TabBar(isScrollable: true, tabs: [for (final f in m.feeds) Tab(text: f.label)]) : null,
                    ),
                  ),
                ],
                body: m.feeds.isEmpty
                    ? const MessageView(icon: Icons.dashboard_customize_outlined, title: '该源没有提供浏览页', message: '请使用搜索')
                    : TabBarView(
                        children: [for (final f in m.feeds) FeedTab(key: PageStorageKey('${m.key}-${f.key}'), source: m, feed: f)],
                      ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class FeedTab extends StatefulWidget {
  const FeedTab({super.key, required this.source, required this.feed});
  final SourceManifest source;
  final FeedDef feed;

  @override
  State<FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<FeedTab> with AutomaticKeepAliveClientMixin {
  late Map<String, Object?> _options = widget.feed.defaultOptions();
  late final PagedController _controller = PagedController(_load, source: widget.source.key)..loadMore();

  Future<WorkPage> _load(int page, String? cursor) =>
      SourceManager.instance.feed(widget.source.key, widget.feed.key, page: page, cursor: cursor, options: _options);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _controller.refresh,
      child: CustomScrollView(
        key: PageStorageKey('scroll-${widget.source.key}-${widget.feed.key}'),
        slivers: [
          SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
          if (widget.feed.options.isNotEmpty)
            SliverToBoxAdapter(
              child: OptionBar(
                options: widget.feed.options,
                values: _options,
                onChanged: (values) {
                  setState(() => _options = values);
                  _controller.refresh();
                },
              ),
            ),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => _controller.total != null && _controller.items.isNotEmpty
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                      child: Text('约 ${formatCount(_controller.total)} 部作品', style: context.text.labelMedium?.copyWith(color: context.colors.onSurfaceVariant)),
                    ),
                  )
                : const SliverToBoxAdapter(),
          ),
          PagedSliverGrid(controller: _controller, kind: widget.source.kind),
        ],
      ),
    );
  }
}
