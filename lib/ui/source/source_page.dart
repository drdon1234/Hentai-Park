import 'package:flutter/material.dart';

import '../discovery_navigation.dart';

import '../../core/models.dart';
import '../../core/content_scope.dart';
import '../history/history_page.dart';
import '../widgets/content_translation.dart';
import '../../engine/source_manager.dart';
import '../nav.dart';
import '../short_video/short_video_page.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/option_bar.dart';
import '../widgets/paged_grid.dart';
import '../../core/localization.dart';

/// A single source's own entry: one tab per feed (latest, ranking, categories…), each with the
/// source's native options (periods, categories, sort) as chips.
class SourcePage extends StatefulWidget {
  const SourcePage({
    super.key,
    required this.sourceKey,
    this.initialFeed,
    this.sourceManager,
  });
  final SourceManager? sourceManager;
  final String sourceKey;

  /// Feed tab to open; null = the source's default feed (manifest `defaultFeed`).
  final int? initialFeed;

  @override
  State<SourcePage> createState() => _SourcePageState();
}

class _SourcePageState extends State<SourcePage> {
  SourceManager get _sources => widget.sourceManager ?? SourceManager.instance;
  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final m = _sources.manifest(widget.sourceKey);
    if (m == null) {
      return Scaffold(
        appBar: AppBar(),
        body: MessageView(
          icon: Icons.extension_off_outlined,
          title: tr('源未加载'),
        ),
      );
    }
    if (m.category == SourceCategory.shortvideo) {
      return ShortVideoPage(
        source: widget.sourceKey,
        feedIndex: widget.initialFeed,
      );
    }
    final account = _sources[widget.sourceKey]?.account;
    final needsLogin = m.account?.required == true && account?.loggedIn != true;
    return TranslationPage(
      child: Theme(
        // Tint the page with the source's brand color so each site feels distinct.
        data: ParkTheme.build(Theme.of(context).brightness, m.color),
        child: DefaultTabController(
          length: m.feeds.length,
          initialIndex: (widget.initialFeed ?? m.defaultFeedIndex).clamp(
            0,
            m.feeds.isEmpty ? 0 : m.feeds.length - 1,
          ),
          child: Builder(
            builder: (context) {
              return Scaffold(
                body: NestedScrollView(
                  headerSliverBuilder: (context, inner) => [
                    SliverOverlapAbsorber(
                      handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                        context,
                      ),
                      sliver: SliverAppBar(
                        pinned: true,
                        floating: true,
                        snap: true,
                        forceElevated: inner,
                        title: Row(
                          children: [
                            SourceAvatar(widget.sourceKey, size: 30),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                m.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          const DomainMenu(),
                          TranslationControls(source: widget.sourceKey),
                          if (m.can('search'))
                            IconButton(
                              tooltip: tr('搜索'),
                              icon: const Icon(Icons.search_rounded),
                              onPressed: () => Nav.openSourceSearch(
                                context,
                                widget.sourceKey,
                              ),
                            ),
                          PopupMenuButton<String>(
                            icon: Badge(
                              isLabelVisible: needsLogin,
                              smallSize: 8,
                              child: const Icon(Icons.more_vert),
                            ),
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'history',
                                child: Text(tr('浏览历史')),
                              ),
                              if (m.can('random'))
                                PopupMenuItem(
                                  value: 'random',
                                  child: Text(tr('随机')),
                                ),
                              PopupMenuItem(
                                value: 'settings',
                                child: Text(tr('源设置')),
                              ),
                            ],
                            onSelected: (action) async {
                              if (action == 'history') {
                                await Nav.push(
                                  context,
                                  HistoryPage(
                                    scope: ContentScope.source(
                                      widget.sourceKey,
                                    ),
                                  ),
                                );
                              } else if (action == 'random') {
                                await Nav.random(context, widget.sourceKey);
                              } else {
                                await Nav.openSourceSettings(
                                  context,
                                  widget.sourceKey,
                                );
                                if (mounted) setState(() {});
                              }
                            },
                          ),
                        ],
                        bottom: m.feeds.length > 1
                            ? TabBar(
                                isScrollable: true,
                                tabs: [
                                  for (final f in m.feeds) Tab(text: f.label),
                                ],
                              )
                            : null,
                      ),
                    ),
                  ],
                  body: m.feeds.isEmpty
                      ? MessageView(
                          icon: Icons.dashboard_customize_outlined,
                          title: tr('该源没有提供浏览页'),
                          message: tr('请使用搜索'),
                        )
                      : TabBarView(
                          children: [
                            for (final f in m.feeds)
                              FeedTab(
                                key: PageStorageKey('${m.key}-${f.key}'),
                                source: m,
                                sourceManager: _sources,
                                feed: f,
                              ),
                          ],
                        ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class FeedTab extends StatefulWidget {
  const FeedTab({
    super.key,
    required this.source,
    required this.feed,
    this.sourceManager,
  });
  final SourceManager? sourceManager;
  final SourceManifest source;
  final FeedDef feed;

  @override
  State<FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<FeedTab> with AutomaticKeepAliveClientMixin {
  bool _forceRefresh = false;
  late Map<String, Object?> _options = widget.feed.defaultOptions();
  late final PagedController _controller = PagedController(
    _load,
    source: widget.source.key,
  )..loadMore();

  Future<WorkPage> _load(int page, String? cursor) =>
      (widget.sourceManager ?? SourceManager.instance).feed(
        widget.source.key,
        widget.feed.key,
        page: page,
        cursor: cursor,
        options: _options,
        refresh: _forceRefresh,
      );

  Future<void> _refresh() async {
    _forceRefresh = true;
    try {
      await _controller.refresh();
    } finally {
      _forceRefresh = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    super.build(context);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        key: PageStorageKey('scroll-${widget.source.key}-${widget.feed.key}'),
        slivers: [
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          ),
          if (widget.feed.options.isNotEmpty)
            SliverToBoxAdapter(
              child: OptionBar(
                options: widget.feed.options,
                values: _options,
                onChanged: (values) {
                  setState(() => _options = values);
                  _refresh();
                },
              ),
            ),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => _controller.staleCache
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(tr('网络暂不可用，正在显示之前缓存的主页数据')),
                    ),
                  )
                : const SliverToBoxAdapter(),
          ),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) =>
                _controller.total != null && _controller.items.isNotEmpty
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                      child: Text(
                        tr('约 {value0} 部作品', {
                          'value0': formatCount(_controller.total),
                        }),
                        style: context.text.labelMedium?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
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
