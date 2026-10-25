import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../engine/source_manager.dart';
import '../album/open_album.dart';
import '../nav.dart';
import '../search/source_search_page.dart';
import '../short_video/post_video_feed.dart';
import '../short_video/short_video_page.dart';
import '../subscriptions/subscription_source_page.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/common_filters.dart';
import '../widgets/content_translation.dart';
import '../widgets/filter_controller.dart';
import '../widgets/option_bar.dart';
import '../widgets/paged_grid.dart';
import '../widgets/source_account_strip.dart';

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
                        if ((m.json['subscription'] as Map?)?['communities'] ==
                            true)
                          IconButton(
                            tooltip: tr('社群'),
                            onPressed: () => Nav.push(
                              context,
                              SubscriptionSourcePage(
                                source: widget.sourceKey,
                                communitiesOnly: true,
                              ),
                            ),
                            icon: const Icon(Icons.groups_outlined),
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
                body: m.feeds.isEmpty
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
    _controller = PagedController(
      _load,
      source: widget.source.key,
      initiallyLoading: true,
    );
    _options = widget.feed.defaultOptions();
    final sources = widget.sourceManager ?? SourceManager.instance;
    _filters = FilterController(
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
    unawaited(_initializeFilters());
    _authentication = (widget.sourceManager ?? SourceManager.instance)
        .authenticationChanges
        .listen((key) {
          if (key == widget.source.key) unawaited(_refresh());
        });
  }

  bool _forceRefresh = false;
  late Map<String, Object?> _options;
  Map<String, Object?> _common = const {};
  late final FilterController _filters;
  late final PagedController _controller;

  Future<void> _initializeFilters() async {
    await _filters.initialize();
    await _filters.loadEnabledDynamic();
    if (!mounted) return;
    _options = _filters.values;
    _controller.loading = false;
    await _controller.loadMore();
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
    _filters.dispose();
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
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          key: PageStorageKey('scroll-${widget.source.key}-${widget.feed.key}'),
          slivers: [
            SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            if (widget.source.can('album'))
              SliverToBoxAdapter(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(tr('相册')),
                    onPressed: () => openMediaAlbum(
                      context,
                      source: widget.source.key,
                      title: '${widget.source.name} · ${widget.feed.label}',
                      scope: {
                        'feed': widget.feed.key,
                        'options': Map.of(_options),
                        'common': Map.of(_common),
                      },
                      sources: widget.sourceManager ?? SourceManager.instance,
                    ),
                  ),
                ),
              ),
            if (widget.feed.commonFilters.isNotEmpty)
              SliverToBoxAdapter(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Gap.page,
                      Gap.s,
                      Gap.page,
                      0,
                    ),
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.tune_rounded),
                      label: Text(_common.isEmpty ? tr('筛选与排序') : tr('筛选已启用')),
                      onPressed: () async {
                        final result = await showCommonFilterSheet(
                          context: context,
                          definitions: widget.feed.commonFilters,
                          initialValues: _common,
                        );
                        if (!mounted || result == null) return;
                        setState(() => _common = result);
                        await _refresh();
                      },
                    ),
                  ),
                ),
              ),
            if (widget.source.json['postShortVideos'] == true)
              SliverToBoxAdapter(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Gap.page),
                    child: OutlinedButton(
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
                      child: Text(tr('短视频模式')),
                    ),
                  ),
                ),
              ),
            if (widget.feed.options.isNotEmpty)
              SliverToBoxAdapter(
                child: ListenableBuilder(
                  listenable: _filters,
                  builder: (context, _) => OptionBar(
                    source: widget.source.key,
                    options: widget.feed.options,
                    values: _filters.values,
                    dynamicChoices: {
                      for (final option in widget.feed.options)
                        if (option.dynamicValues)
                          option.key: _filters.choicesFor(option.key),
                    },
                    loadingOptions: {
                      for (final option in widget.feed.options)
                        if (_filters.isLoadingOption(option.key)) option.key,
                    },
                    optionErrors: {
                      for (final option in widget.feed.options)
                        option.key: _filters.errorFor(option.key),
                    },
                    enabledOptions: {
                      for (final option in widget.feed.options)
                        option.key: _filters.isEnabled(option.key),
                    },
                    onRetry: (key) => _filters.loadDynamic(key),
                    onChanged: (values) async {
                      final previous = _filters.values;
                      for (final entry in values.entries) {
                        if (previous[entry.key] != entry.value) {
                          _filters.setValue(entry.key, entry.value);
                        }
                      }
                      _options = _filters.values;
                      for (final option in widget.feed.options.where(
                        (option) =>
                            option.dynamicValues &&
                            _filters.isEnabled(option.key),
                      )) {
                        await _filters.loadDynamic(option.key);
                      }
                      if (mounted) await _refresh();
                    },
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
            PagedSliverGrid(controller: _controller, kind: widget.source.kind),
          ],
        ),
      ),
    );
  }
}
