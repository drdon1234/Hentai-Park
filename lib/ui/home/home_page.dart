import 'package:flutter/material.dart';

import '../../core/content_scope.dart';
import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../engine/source_manager.dart';
import '../../library/library.dart';
import '../discovery_navigation.dart';
import '../history/history_page.dart';
import '../history/recent_history.dart';
import '../kit/kit.dart';
import '../nav.dart';
import '../rankings/rankings_page.dart';
import '../search/reverse_search_page.dart';
import '../settings/source_manage_page.dart';
import '../subscriptions/subscriptions_page.dart';
import '../theme.dart';
import 'dimension_filter.dart';
import 'feed_sessions.dart';
import 'feed_shelf.dart';
import 'sites_page.dart';

/// 发现: search first, then 继续看, then one shelf per category (or per site inside a category).
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.destination, this.onOpenHistory});
  final ValueNotifier<DiscoveryDestination>? destination;
  final ValueChanged<ContentScope>? onOpenHistory;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final _feeds = FeedSessions(SourceManager.instance);
  final _localDestination = ValueNotifier(const DiscoveryDestination.all());
  final _destinations = <String, DiscoveryDestination>{};
  final _scrolls = <String, ScrollController>{};
  late final Listenable _domainOrder = AppSettings.instance.watch(const {
    'domainOrder',
    'homeCategories',
    'homeSources',
    'homeExpandedDomains',
    'homeHiddenSources',
    'dataSavingMode',
    'homeDimension',
    'homeMedia',
  });
  ValueNotifier<DiscoveryDestination> get _destination =>
      widget.destination ?? _localDestination;

  @override
  void initState() {
    super.initState();
    _destinations[_destination.value.key] = _destination.value;
    _destination.addListener(_changed);
    _domainOrder.addListener(_filterChanged);
    _revealDestination();
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destination != widget.destination) {
      (oldWidget.destination ?? _localDestination).removeListener(_changed);
      _destination.addListener(_changed);
      _destinations[_destination.value.key] = _destination.value;
      _revealDestination();
    }
  }

  void _changed() {
    _revealDestination();
    setState(() {
      _destinations[_destination.value.key] = _destination.value;
    });
  }

  void _revealDestination() {
    final category = _destination.value.category;
    final settings = AppSettings.instance;
    if (category != null && !settings.homeIncludes(category)) {
      settings.homeDimension = ContentDimension.all;
      settings.homeMedia = ContentMedia.all;
    }
  }

  void _filterChanged() {
    final category = _destination.value.category;
    if (category != null && !AppSettings.instance.homeIncludes(category)) {
      _select(const DiscoveryDestination.all());
    }
  }

  void _select(DiscoveryDestination destination) =>
      _destination.value = destination;

  void _history(ContentScope scope) {
    if (widget.onOpenHistory != null) {
      widget.onOpenHistory!(scope);
    } else {
      Nav.push(context, HistoryPage(scope: scope));
    }
  }

  @override
  void dispose() {
    _feeds.dispose();
    _destination.removeListener(_changed);
    _domainOrder.removeListener(_filterChanged);
    _localDestination.dispose();
    for (final scroll in _scrolls.values) {
      scroll.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _destination.value;
    return ListenableBuilder(
      listenable: _domainOrder,
      builder: (context, _) => Scaffold(
        appBar: PageHeader(
          toolbarHeight: 56,
          titleWidget: Text(
            'HentaiPark',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ParkText.serif(
              context.text.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          actions: [
            ToolbarActions(
              actions: [
                ToolbarAction(
                  label: tr('排行榜'),
                  icon: Icons.leaderboard_outlined,
                  showLabel: true,
                  shortLabel: tr('排行'),
                  compactLabel: true,
                  onPressed: () => Nav.push(
                    context,
                    RankingsPage(category: selected.category),
                  ),
                ),
                ToolbarAction(
                  label: tr('图片反搜'),
                  icon: Icons.image_search_outlined,
                  showLabel: true,
                  shortLabel: tr('反搜'),
                  compactLabel: true,
                  onPressed: () => Nav.push(context, const ReverseSearchPage()),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            DimensionFilter(
              dimension: AppSettings.instance.homeDimension,
              media: AppSettings.instance.homeMedia,
              onDimension: (value) =>
                  AppSettings.instance.homeDimension = value,
              onMedia: (value) => AppSettings.instance.homeMedia = value,
            ),
            Expanded(
              child: IndexedStack(
                index: _destinations.keys.toList().indexOf(selected.key),
                children: [
                  for (final destination in _destinations.values)
                    KeyedSubtree(
                      key: ValueKey(destination.key),
                      child: TickerMode(
                        enabled: destination == selected,
                        child: ExcludeFocus(
                          excluding: destination != selected,
                          child: destination.subscription
                              ? const SubscriptionsPage(embedded: true)
                              : _content(context, destination),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, DiscoveryDestination selected) {
    final sm = SourceManager.instance;
    final dataSaver = AppSettings.instance.dataSaver;
    final settings = AppSettings.instance;
    final scope = selected.category != null
        ? ContentScope.domain(selected.category!)
        : settings.homeDimension == ContentDimension.all &&
              settings.homeMedia == ContentMedia.all
        ? const ContentScope.all()
        : ContentScope.domains({
            for (final category in SourceCategory.values)
              if (settings.homeIncludes(category)) category,
          });
    return ParkRefresh(
      onRefresh: () async {
        if (!dataSaver) _feeds.refreshAll();
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        controller: _scrolls.putIfAbsent(selected.key, ScrollController.new),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Gap.page, Gap.s, Gap.page, 0),
              child: ParkSearchField(
                hint: selected.category == null
                    ? tr('搜索作品、标签，或粘贴链接 / 车号')
                    : tr('在{category}中搜索', {
                        'category': selected.category!.label,
                      }),
                onTap: () => Nav.openAggregateSearch(context, scope: scope),
                outlined: true,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Gap.page, Gap.xs, Gap.page, 0),
              child: Text(
                _searchScopeSummary(settings),
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
          if (dataSaver)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Gap.page,
                  Gap.m,
                  Gap.page,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('省流量模式'),
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w400),
                    ),
                    Text(
                      tr(
                        AppSettings.instance.searchOnlySources
                            ? '主页和域页仅显示站点入口；站点页不自动加载作品，只响应搜索'
                            : '主页和域页仅显示站点入口，进入站点后再加载作品',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          if (!dataSaver)
            SliverToBoxAdapter(
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  Library.instance.collection(LibraryCollection.history),
                  sm,
                ]),
                builder: (context, _) => RecentHistory(
                  scope: scope,
                  limit: 20,
                  onOpenHistory: () => _history(scope),
                ),
              ),
            ),
          if (selected.category == null)
            SliverToBoxAdapter(child: _allSitesEntry(context)),
          ListenableBuilder(
            listenable: Listenable.merge([sm, _domainOrder]),
            builder: (context, _) => _shelves(context, selected),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: Gap.xl)),
        ],
      ),
    );
  }

  String _searchScopeSummary(AppSettings settings) {
    final dimension = settings.homeDimension == ContentDimension.all
        ? tr('全部内容')
        : '${settings.homeDimension.label}${tr('内容')}';
    final media = settings.homeMedia == ContentMedia.all
        ? tr('全部类型')
        : settings.homeMedia.label;
    return tr('聚合搜索：{dimension}、{media}', {
      'dimension': dimension,
      'media': media,
    });
  }

  // 全部站点 > 域 > 站点只用字号建立层级，三者保持同一左边界。
  Widget _allSitesEntry(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Gap.page, Gap.xxl, Gap.xs, Gap.xs),
    child: Semantics(
      button: true,
      label: tr('全部站点'),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: Radii.small,
          onTap: () => Nav.push(context, const SitesPage()),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tr('全部站点'),
                    style: ParkText.serif(
                      context.text.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Text(
                  tr('查看全部'),
                  style: context.text.labelLarge?.copyWith(
                    color: context.colors.primary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(width: Gap.xs),
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: context.colors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  /// Categories chosen in the first-run flow (or settings) get shelves on “全部”.
  bool _interesting(SourceCategory category) {
    final chosen = AppSettings.instance.homeCategories;
    return chosen.isEmpty || chosen.contains(category);
  }

  Widget _shelves(BuildContext context, DiscoveryDestination selected) {
    final sm = SourceManager.instance;
    if (sm.initializationError != null) {
      return SliverToBoxAdapter(
        child: EmptyState(
          icon: Icons.error_outline,
          title: tr('站点加载失败'),
          actions: [
            FilledButton(
              onPressed: () async {
                try {
                  await sm.init();
                } catch (_) {}
              },
              child: SelectionContainer.disabled(child: Text(tr('重试'))),
            ),
          ],
        ),
      );
    }
    if (!sm.loaded) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(Gap.xl),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final category = selected.category;
    final dataSaver = AppSettings.instance.dataSaver;
    final enabled = sm.displayEnabled
        .where(
          (source) =>
              !source.manifest!.rankingOnly &&
              !source.manifest!.reverseSearchOnly &&
              AppSettings.instance.homeIncludes(source.manifest!.category) &&
              (category == null || source.manifest!.category == category),
        )
        .toList();
    final sources = enabled
        .where(
          (source) =>
              (category != null || _interesting(source.manifest!.category)) &&
              (dataSaver ||
                  source.manifest!.feeds.isNotEmpty ||
                  source.manifest!.can('subscription')),
        )
        .toList();
    if (sources.isEmpty) {
      if (enabled.isNotEmpty) {
        return SliverToBoxAdapter(
          child: EmptyState(
            icon: Icons.explore_outlined,
            title: tr('暂时没有内容'),
            message: tr('可切换分类，或通过站点入口浏览和搜索'),
            actions: [
              FilledButton(
                onPressed: () => Nav.push(context, const SitesPage()),
                child: SelectionContainer.disabled(child: Text(tr('站点'))),
              ),
            ],
          ),
        );
      }
      return SliverToBoxAdapter(
        child: EmptyState(
          icon: Icons.extension_off_outlined,
          title: category == null ? tr('还没有启用的站点') : tr('这个分类还没有启用的站点'),
          message: tr('在站点管理中启用或安装站点'),
          actions: [
            FilledButton(
              onPressed: () => Nav.push(context, const SourceManagePage()),
              child: SelectionContainer.disabled(child: Text(tr('管理站点'))),
            ),
          ],
        ),
      );
    }
    if (dataSaver && category != null) {
      return SliverList.list(
        children: [
          RowGroup(
            title: category.label,
            children: [for (final source in sources) _siteEntry(source)],
          ),
        ],
      );
    }
    final sections = <Widget>[];
    if (category != null) {
      sections.addAll([
        for (final source in sources) _homeSource(context, source),
      ]);
    } else {
      for (final domain in AppSettings.instance.domainOrder) {
        final candidates = sources
            .where((source) => source.manifest!.category == domain)
            .toList();
        if (candidates.isEmpty) continue;
        final expanded = AppSettings.instance.homeDomainExpanded(domain);
        sections.add(
          _domainHeader(context, domain, candidates, expanded: expanded),
        );
        if (dataSaver) {
          sections.add(
            RowGroup(
              children: [
                for (final source in _domainSources(
                  candidates,
                  domain,
                  expanded: expanded,
                ))
                  _siteEntry(source),
              ],
            ),
          );
          sections.add(const Divider(indent: Gap.page, endIndent: Gap.page));
          continue;
        }
        sections.addAll([
          for (final source in _domainSources(
            candidates,
            domain,
            expanded: expanded,
          ))
            _homeSource(context, source),
        ]);
        sections.add(const Divider(indent: Gap.page, endIndent: Gap.page));
      }
    }
    return SliverList.list(children: sections);
  }

  Widget _domainHeader(
    BuildContext context,
    SourceCategory domain,
    List<InstalledSource> sources, {
    required bool expanded,
  }) {
    final configurable = browsableSources(domain);
    return Column(
      children: [
        SectionHeader(
          domain.label,
          padding: const EdgeInsets.fromLTRB(Gap.page, Gap.l, Gap.page, Gap.xs),
          titleStyle: ParkText.serif(
            context.text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          emphasizeTrailing: false,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (configurable.isNotEmpty)
                IconButton(
                  tooltip: tr('选择展示站点'),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(40, 40),
                    padding: EdgeInsets.zero,
                  ),
                  icon: const Icon(Icons.tune_rounded),
                  onPressed: () => _configure(
                    domain,
                    _displaySource(configurable, domain)!.key,
                  ),
                ),
              if (sources.length > 1)
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: context.colors.onSurfaceVariant,
                    minimumSize: const Size(40, 40),
                    padding: EdgeInsets.zero,
                    textStyle: context.text.labelLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onPressed: () => AppSettings.instance.setHomeDomainExpanded(
                    domain,
                    !expanded,
                  ),
                  child: SelectionContainer.disabled(
                    child: Text(tr(expanded ? '收起' : '展开')),
                  ),
                ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.primary,
                  minimumSize: const Size(48, 40),
                  padding: EdgeInsets.zero,
                  textStyle: context.text.labelLarge?.copyWith(
                    fontWeight: FontWeight.w400,
                  ),
                ),
                onPressed: () => _select(DiscoveryDestination.domain(domain)),
                child: SelectionContainer.disabled(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(tr('进入域')),
                      const SizedBox(width: Gap.xs),
                      const SizedBox(
                        width: 24,
                        height: 40,
                        child: Center(
                          child: Icon(Icons.chevron_right_rounded, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(indent: Gap.page, endIndent: Gap.page),
      ],
    );
  }

  List<InstalledSource> _domainSources(
    List<InstalledSource> sources,
    SourceCategory category, {
    required bool expanded,
  }) {
    final first = _displaySource(sources, category);
    if (first == null) return const [];
    if (!expanded) return [first];
    return [first, ...sources.where((source) => source.key != first.key)];
  }

  Widget _homeSource(BuildContext context, InstalledSource source) {
    final visible = AppSettings.instance.homeSourceVisible(source.key);
    if (AppSettings.instance.dataSaver || !visible) return _siteEntry(source);
    return FeedShelf(
      key: ValueKey('home:${source.key}'),
      sessions: _feeds,
      sourceKey: source.key,
      title: source.name,
      moreLabel: tr('进入'),
      moreChevron: false,
      onToggleVisibility: () =>
          AppSettings.instance.setHomeSourceVisible(source.key, false),
      onMore: () => Nav.openSource(context, source.key),
    );
  }

  Widget _siteEntry(InstalledSource source) {
    final visible = AppSettings.instance.homeSourceVisible(source.key);
    return HairlineItem(
      key: ValueKey('home:${source.key}'),
      child: SiteRow(
        source: source,
        homeSourceVisible: visible,
        showMore: false,
        showDetails: false,
        showEnterButton: true,
        onToggleWorks: () =>
            AppSettings.instance.setHomeSourceVisible(source.key, !visible),
      ),
    );
  }

  InstalledSource? _displaySource(
    List<InstalledSource> sources,
    SourceCategory category,
  ) {
    final eligible = sources.where((s) => s.manifest!.category == category);
    final chosen = AppSettings.instance.homeSource(category);
    return eligible.where((s) => s.key == chosen).firstOrNull ??
        eligible.firstOrNull;
  }

  Future<void> _configure(SourceCategory category, String selected) async {
    final sources = browsableSources(category);
    final chosen = await showChoiceSheet<String>(
      context,
      title: tr('选择展示站点'),
      selected: selected,
      options: sources.map((source) => source.key).toList(),
      label: (key) => sources.firstWhere((source) => source.key == key).name,
    );
    if (chosen != null) AppSettings.instance.setHomeSource(category, chosen);
  }
}
