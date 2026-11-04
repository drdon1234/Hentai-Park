import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../engine/source_manager.dart';
import '../album/open_album.dart';
import '../kit/adaptive_sheet.dart';
import '../nav.dart';
import '../search/source_search_page.dart';
import '../short_video/post_video_feed.dart';
import '../short_video/short_video_page.dart';
import '../subscriptions/subscription_source_page.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/content_translation.dart';
import '../widgets/filter_controller.dart';
import '../widgets/paged_grid.dart';
import '../widgets/result_visibility.dart';
import '../widgets/source_account_strip.dart';

/// A single source's own entry: one tab per feed (latest, ranking, categories…), each with the
/// source's native filters in a shared sheet beside the tabs.
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
  bool _listMode = false;
  bool _hidePreviews = false;

  final _feedKeys = <String, GlobalKey<_FeedTabState>>{};

  Widget _displayControls(BuildContext context, SourceManifest manifest) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (manifest.feeds.isNotEmpty)
        AnimatedBuilder(
          animation: DefaultTabController.of(context),
          builder: (context, _) {
            final index = DefaultTabController.of(context).index;
            if (index >= manifest.feeds.length) return const SizedBox.shrink();
            final feed = manifest.feeds[index];
            if (feed.options.isEmpty && feed.commonFilters.isEmpty) {
              return const SizedBox.shrink();
            }
            final active =
                _feedKeys[feed.key]?.currentState?._activeFilters ?? 0;
            return Badge(
              isLabelVisible: active > 0,
              label: Text('$active'),
              child: IconButton(
                tooltip: tr('筛选'),
                isSelected: active > 0,
                icon: const Icon(Icons.filter_alt_outlined),
                onPressed: () =>
                    _feedKeys[feed.key]?.currentState?._openFilters(),
              ),
            );
          },
        ),
      ResultVisibility(
        supportsPreviews: manifest.can('previewContent'),
        hidePreviews: _hidePreviews,
        onPreviews: (value) => setState(() => _hidePreviews = value),
      ),
      if (!manifest.isArticle)
        IconButton(
          tooltip: tr(_listMode ? '切换为卡片' : '切换为单行列表'),
          icon: Icon(
            _listMode ? Icons.grid_view_rounded : Icons.view_list_rounded,
          ),
          onPressed: () => setState(() => _listMode = !_listMode),
        ),
    ],
  );
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
              appBar: AppBar(
                title: Text(m.name),
                bottom: m.account == null
                    ? null
                    : PreferredSize(
                        preferredSize: Size.fromHeight(
                          SourceAccountStrip.height(context),
                        ),
                        child: SourceAccountStrip(
                          source: widget.sourceKey,
                          sourceManager: _sources,
                        ),
                      ),
              ),
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
    final subscription = m.json['subscription'] as Map?;
    final joinedTabs = <({String label, bool communitiesOnly})>[
      if (subscription?['joinedTargets'] == true &&
          subscription?['joinedCreators'] == true)
        (label: '已关注博主', communitiesOnly: false),
      if (subscription?['joinedTargets'] == true &&
          subscription?['communities'] == true)
        (label: '已加入频道', communitiesOnly: true),
      if (subscription?['joinedTargets'] == true &&
          subscription?['joinedCreators'] != true &&
          subscription?['communities'] != true)
        (label: '已加入或已关注', communitiesOnly: false),
    ];
    final feedTabs = m.feeds.isNotEmpty || joinedTabs.isNotEmpty
        ? TabBar(
            isScrollable: true,
            tabs: [
              for (final f in m.feeds)
                Tab(
                  height:
                      (MediaQuery.textScalerOf(context).scale(16) * 1.5 + Gap.l)
                          .clamp(48.0, double.infinity),
                  child: SelectionContainer.disabled(child: Text(f.label)),
                ),
              for (final joined in joinedTabs)
                Tab(
                  height:
                      (MediaQuery.textScalerOf(context).scale(16) * 1.5 + Gap.l)
                          .clamp(48.0, double.infinity),
                  child: SelectionContainer.disabled(
                    child: Text(tr(joined.label)),
                  ),
                ),
            ],
          )
        : null;
    final tabs = feedTabs == null
        ? null
        : PreferredSize(
            preferredSize: feedTabs.preferredSize,
            child: Row(
              children: [
                Expanded(child: feedTabs),
                Builder(builder: (context) => _displayControls(context, m)),
                const SizedBox(width: Gap.s),
              ],
            ),
          );
    return TranslationPage(
      child: DefaultTabController(
        key: ValueKey((widget.sourceKey, accountStatus?.loggedIn == true)),
        length: m.feeds.length + joinedTabs.length,
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
                        if (tabs == null)
                          Builder(
                            builder: (context) => _displayControls(context, m),
                          ),
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
                            if (m.can('subscription'))
                              PopupMenuItem(
                                value: 'subscription',
                                child: Text(tr('访问频道或作者')),
                              ),
                            if (m.account == null && m.can('subscription'))
                              PopupMenuItem(
                                value: 'login',
                                child: Text(tr('在原站登录')),
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
                            if (action == 'subscription') {
                              await Nav.push(
                                context,
                                SubscriptionSourcePage(
                                  source: widget.sourceKey,
                                ),
                              );
                            } else if (action == 'login') {
                              await Nav.login(context, widget.sourceKey);
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
                      bottom: m.account != null
                          ? PreferredSize(
                              preferredSize: Size.fromHeight(
                                SourceAccountStrip.height(context) +
                                    (tabs?.preferredSize.height ?? 0),
                              ),
                              child: Column(
                                children: [
                                  SourceAccountStrip(
                                    source: widget.sourceKey,
                                    sourceManager: _sources,
                                  ),
                                  ?tabs,
                                ],
                              ),
                            )
                          : tabs,
                    ),
                  ),
                ],
                body: m.feeds.isEmpty && joinedTabs.isEmpty
                    ? LayoutBuilder(
                        builder: (context, constraints) =>
                            SingleChildScrollView(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight,
                                ),
                                child: EmptyState(
                                  icon: Icons.dashboard_customize_outlined,
                                  title: tr('这个站点没有浏览页'),
                                  message: tr('请使用搜索'),
                                ),
                              ),
                            ),
                      )
                    : TabBarView(
                        children: [
                          for (final f in m.feeds)
                            FeedTab(
                              key: _feedKeys.putIfAbsent(
                                f.key,
                                () => GlobalKey<_FeedTabState>(),
                              ),
                              source: m,
                              sourceManager: _sources,
                              feed: f,
                              listMode: _listMode,
                              hidePreviews: _hidePreviews,
                              onFiltersChanged: () => setState(() {}),
                            ),
                          for (final joined in joinedTabs)
                            SubscriptionSourcePage(
                              source: widget.sourceKey,
                              communitiesOnly: joined.communitiesOnly,
                              embedded: true,
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

class FeedTab extends StatefulWidget {
  const FeedTab({
    super.key,
    required this.source,
    required this.feed,
    this.listMode = false,
    this.hidePreviews = false,
    this.sourceManager,
    this.onFiltersChanged,
  });
  final VoidCallback? onFiltersChanged;
  final SourceManager? sourceManager;
  final SourceManifest source;
  final FeedDef feed;
  final bool listMode;
  final bool hidePreviews;

  @override
  State<FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<FeedTab> with AutomaticKeepAliveClientMixin {
  StreamSubscription<String>? _authentication;
  @override
  void initState() {
    super.initState();
    _controller = PagedController(
      _load,
      source: widget.source.key,
      initiallyLoading: true,
    );
    _controller.hidePreviews = widget.hidePreviews;
    _options = widget.feed.defaultOptions();
    final sources = widget.sourceManager ?? SourceManager.instance;
    _initialFilters = FilterController(
      source: widget.source.key,
      scope: 'feed',
      feed: widget.feed.key,
      definitions: widget.feed.options,
      loader: (filter, values, token) => sources.filterOptions(
        widget.source.key,
        scope: 'feed',
        feed: widget.feed.key,
        filter: filter,
        values: values,
        cancelToken: token,
      ),
    );
    _initialization = _initializeFilters();
    _authentication = (widget.sourceManager ?? SourceManager.instance)
        .authenticationChanges
        .listen((key) {
          if (key == widget.source.key) unawaited(_refresh());
        });
  }

  bool _forceRefresh = false;
  late Map<String, Object?> _options;
  Map<String, Object?> _common = const {};
  late final PagedController _controller;
  late final FilterController _initialFilters;
  late final Future<void> _initialization;

  int get _activeFilters {
    final defaults = widget.feed.defaultOptions();
    return _common.length +
        _options.entries.where((entry) {
          final initial = defaults[entry.key];
          return entry.value is List && initial is List
              ? !listEquals(entry.value as List, initial)
              : entry.value != initial;
        }).length;
  }

  Future<void> _openFilters() async {
    await _initialization;
    if (!mounted) return;
    final result = await showAdaptiveSheet<FilterSheetResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FilterSheet(
        manifest: widget.source,
        feed: widget.feed,
        values: _options,
        commonValues: _common,
        sourceManager: widget.sourceManager ?? SourceManager.instance,
        keyword: '',
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _options = result.filters;
      _common = result.common;
    });
    widget.onFiltersChanged?.call();
    await _refresh();
  }

  Future<void> _initializeFilters() async {
    await _initialFilters.initialize();
    await _initialFilters.loadEnabledDynamic();
    if (!mounted) return;
    _options = _initialFilters.values;
    _controller.loading = false;
    unawaited(_controller.loadMore());
  }

  Future<WorkPage> _load(int page, String? cursor) =>
      (widget.sourceManager ?? SourceManager.instance).feed(
        widget.source.key,
        widget.feed.key,
        page: page,
        cursor: cursor,
        options: _options,
        common: _common,
        refresh: _forceRefresh,
        onCached: page == 1 ? _controller.cachedReceiver() : null,
      );

  Future<void> _refresh({bool retainItems = false}) async {
    _forceRefresh = true;
    try {
      await _controller.refresh(retainItems: retainItems);
    } finally {
      _forceRefresh = false;
    }
  }

  @override
  void didUpdateWidget(covariant FeedTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hidePreviews != widget.hidePreviews) {
      _controller.setVisibility(previews: widget.hidePreviews);
    }
  }

  @override
  void dispose() {
    _authentication?.cancel();
    _initialFilters.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return PostVideoContext(
      scope: PostVideoScope(
        source: widget.source.key,
        title: '${widget.source.name} · ${widget.feed.label}',
        feed: widget.feed.key,
        options: Map.of(_options),
        common: Map.of(_common),
      ),
      child: ParkRefresh(
        onRefresh: () => _refresh(retainItems: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          key: PageStorageKey('scroll-${widget.source.key}-${widget.feed.key}'),
          slivers: [
            SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            if (widget.source.supportsAlbumMode ||
                widget.source.supportsShortVideoMode)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Gap.page,
                    Gap.s,
                    Gap.page,
                    0,
                  ),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: Gap.s,
                    runSpacing: Gap.xs,
                    children: [
                      if (widget.source.supportsAlbumMode)
                        ToolbarButton.icon(
                          label: Text(tr('相册')),
                          icon: const Icon(
                            Icons.photo_library_outlined,
                            size: 18,
                          ),
                          onPressed: () => openMediaAlbum(
                            context,
                            source: widget.source.key,
                            title:
                                '${widget.source.name} · ${widget.feed.label}',
                            scope: {
                              'feed': widget.feed.key,
                              'options': Map.of(_options),
                              'common': Map.of(_common),
                            },
                            sources:
                                widget.sourceManager ?? SourceManager.instance,
                          ),
                        ),
                      if (widget.source.supportsShortVideoMode)
                        ToolbarButton.icon(
                          label: Text(tr('短视频模式')),
                          icon: const Icon(
                            Icons.smart_display_outlined,
                            size: 18,
                          ),
                          onPressed: () => Nav.push(
                            context,
                            ShortVideoPage(
                              source: widget.source.key,
                              postScope: PostVideoScope(
                                source: widget.source.key,
                                title:
                                    '${widget.source.name} · ${widget.feed.label}',
                                feed: widget.feed.key,
                                options: Map.of(_options),
                                common: Map.of(_common),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
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
            PagedSliverGrid(
              controller: _controller,
              kind: widget.source.kind,
              listMode: widget.listMode,
            ),
          ],
        ),
      ),
    );
  }
}
