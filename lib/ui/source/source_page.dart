import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/content_scope.dart';
import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../engine/source_manager.dart';
import '../history/history_page.dart';
import '../nav.dart';
import '../search/source_search_page.dart';
import '../short_video/short_video_page.dart';
import '../subscriptions/subscription_source_page.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/content_translation.dart';
import '../widgets/option_bar.dart';
import '../widgets/paged_grid.dart';

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
    final account = _sources.accountListenable(widget.sourceKey);
    return ListenableBuilder(
      listenable: AppSettings.instance.watch(const {'dataSavingMode'}),
      builder: (context, _) => account == null
          ? _build(context)
          : ValueListenableBuilder(
              valueListenable: account,
              builder: (context, status, _) => _build(context, status),
            ),
    );
  }

  Widget _build(BuildContext context, [AccountStatus? accountStatus]) {
    final m = _sources.manifest(widget.sourceKey);
    if (m == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.extension_off_outlined,
          title: tr('站点未加载'),
        ),
      );
    }
    if (AppSettings.instance.searchOnlySources) {
      return m.can('search')
          ? SourceSearchPage(
              sourceKey: widget.sourceKey,
              sourceManager: _sources,
              searchOnlyEntry: true,
            )
          : Scaffold(
              appBar: AppBar(title: Text(m.name)),
              body: EmptyState(
                icon: Icons.search_off_rounded,
                title: tr('超级省流'),
                message: tr('此站点不支持搜索'),
              ),
            );
    }
    if (m.feeds.isEmpty && m.can('subscription')) {
      return SubscriptionSourcePage(source: widget.sourceKey);
    }
    if (m.category == SourceCategory.shortvideo) {
      return ShortVideoPage(
        source: widget.sourceKey,
        feedIndex: widget.initialFeed,
      );
    }
    final needsLogin =
        m.account?.required == true && accountStatus?.loggedIn != true;
    final tabs = m.feeds.length > 1
        ? TabBar(
            isScrollable: true,
            tabs: [
              for (final f in m.feeds)
                Tab(child: SelectionContainer.disabled(child: Text(f.label))),
            ],
          )
        : null;
    return TranslationPage(
      child: DefaultTabController(
        key: ValueKey((widget.sourceKey, accountStatus?.loggedIn == true)),
        length: m.feeds.length,
        initialIndex:
            (widget.initialFeed ?? _sources.entryFeedIndex(widget.sourceKey))
                .clamp(0, m.feeds.isEmpty ? 0 : m.feeds.length - 1),
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
                          SourceAvatar(widget.sourceKey, size: 28),
                          const SizedBox(width: Gap.m),
                          Flexible(
                            child: Text(
                              m.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        TranslationControls(source: widget.sourceKey),
                        if (m.can('search'))
                          IconButton(
                            tooltip: tr('搜索'),
                            icon: const Icon(Icons.search_rounded),
                            onPressed: () =>
                                Nav.openSourceSearch(context, widget.sourceKey),
                          ),
                        PopupMenuButton<String>(
                          tooltip: tr('更多'),
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'history',
                              child: SelectionContainer.disabled(
                                child: Text(tr('浏览历史')),
                              ),
                            ),
                            if (m.can('random'))
                              PopupMenuItem(
                                value: 'random',
                                child: SelectionContainer.disabled(
                                  child: Text(tr('随机一部')),
                                ),
                              ),
                            PopupMenuItem(
                              value: 'settings',
                              child: SelectionContainer.disabled(
                                child: Text(tr('站点设置')),
                              ),
                            ),
                          ],
                          onSelected: (action) async {
                            if (action == 'history') {
                              await Nav.push(
                                context,
                                HistoryPage(
                                  scope: ContentScope.source(widget.sourceKey),
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
                      // Login is stated in words where browsing happens, not as a dot on a menu.
                      bottom: needsLogin
                          ? PreferredSize(
                              preferredSize: Size.fromHeight(
                                48 + (tabs?.preferredSize.height ?? 0),
                              ),
                              child: Column(
                                children: [
                                  _LoginStrip(source: widget.sourceKey),
                                  ?tabs,
                                ],
                              ),
                            )
                          : tabs,
                    ),
                  ),
                ],
                body: m.feeds.isEmpty
                    ? EmptyState(
                        icon: Icons.dashboard_customize_outlined,
                        title: tr('这个站点没有浏览页'),
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
    );
  }
}

class _LoginStrip extends StatelessWidget {
  const _LoginStrip({required this.source});
  final String source;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: Padding(
      padding: const EdgeInsets.only(left: Gap.page, right: Gap.s),
      child: Row(
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 18,
            color: context.colors.onSurfaceVariant,
          ),
          const SizedBox(width: Gap.s),
          Expanded(
            child: Text(
              tr('这个站点需要登录后才能浏览'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Nav.login(context, source),
            child: SelectionContainer.disabled(child: Text(tr('去登录'))),
          ),
        ],
      ),
    ),
  );
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
  StreamSubscription<String>? _authentication;
  @override
  void initState() {
    super.initState();
    _controller = PagedController(_load, source: widget.source.key);
    _controller.loadMore();
    _authentication = (widget.sourceManager ?? SourceManager.instance)
        .authenticationChanges
        .listen((key) {
          if (key == widget.source.key) unawaited(_refresh());
        });
  }

  bool _forceRefresh = false;
  late Map<String, Object?> _options = widget.feed.defaultOptions();
  late final PagedController _controller;

  Future<WorkPage> _load(int page, String? cursor) =>
      (widget.sourceManager ?? SourceManager.instance).feed(
        widget.source.key,
        widget.feed.key,
        page: page,
        cursor: cursor,
        options: _options,
        refresh: _forceRefresh,
        onCached: page == 1 ? _controller.cachedReceiver() : null,
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
    _authentication?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ParkRefresh(
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
                source: widget.source.key,
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
            builder: (context, _) =>
                _controller.loading && _controller.page == 0
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(Gap.page),
                      child: Text(tr('获取最新作品中')),
                    ),
                  )
                : const SliverToBoxAdapter(),
          ),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => _controller.staleCache
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Gap.page,
                        Gap.m,
                        Gap.page,
                        0,
                      ),
                      child: Text(
                        tr('网络暂不可用，正在显示之前缓存的主页数据'),
                        style: context.text.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
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
                      padding: const EdgeInsets.fromLTRB(
                        Gap.page,
                        Gap.s,
                        Gap.page,
                        0,
                      ),
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
