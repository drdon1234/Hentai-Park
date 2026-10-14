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
import '../settings/source_manage_page.dart';
import '../subscriptions/subscriptions_page.dart';
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
  final _localDestination = ValueNotifier(const DiscoveryDestination.all());
  final _scroll = ScrollController();
  bool _subscriptionsVisited = false;
  late final Listenable _domainOrder = AppSettings.instance.watch(const {
    'domainOrder',
    'homeCategories',
  });
  ValueNotifier<DiscoveryDestination> get _destination =>
      widget.destination ?? _localDestination;

  @override
  void initState() {
    super.initState();
    _subscriptionsVisited = _destination.value.subscription;
    _destination.addListener(_changed);
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destination != widget.destination) {
      (oldWidget.destination ?? _localDestination).removeListener(_changed);
      _destination.addListener(_changed);
    }
  }

  void _changed() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() => _subscriptionsVisited |= _destination.value.subscription);
  }

  void _select(DiscoveryDestination destination) =>
      _destination.value = destination;

  ContentScope get _scope {
    final category = _destination.value.category;
    return category == null
        ? const ContentScope.all()
        : ContentScope.domain(category);
  }

  void _history() {
    if (widget.onOpenHistory != null) {
      widget.onOpenHistory!(_scope);
    } else {
      Nav.push(context, HistoryPage(scope: _scope));
    }
  }

  @override
  void dispose() {
    _destination.removeListener(_changed);
    _localDestination.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _destination.value;
    return Scaffold(
      appBar: PageHeader(
        title: 'HentaiPark',
        actions: [
          TextButton(
            onPressed: () => Nav.push(context, const SitesPage()),
            child: Text(tr('站点')),
          ),
        ],
      ),
      body: Column(
        children: [
          ListenableBuilder(
            listenable: _domainOrder,
            builder: (context, _) =>
                DiscoveryDomainBar(selected: selected, onSelected: _select),
          ),
          Expanded(
            child: IndexedStack(
              index: selected.subscription ? 1 : 0,
              children: [
                _content(context, selected),
                if (_subscriptionsVisited)
                  const SubscriptionsPage(embedded: true)
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, DiscoveryDestination selected) {
    final sm = SourceManager.instance;
    return CustomScrollView(
      controller: _scroll,
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
              onTap: () => Nav.openAggregateSearch(context, scope: _scope),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: ListenableBuilder(
            listenable: Listenable.merge([
              Library.instance.collection(LibraryCollection.history),
              sm,
            ]),
            builder: (context, _) => RecentHistory(
              scope: _scope,
              limit: 20,
              onOpenHistory: _history,
            ),
          ),
        ),
        ListenableBuilder(
          listenable: Listenable.merge([sm, _domainOrder]),
          builder: (context, _) => _shelves(context, selected),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: Gap.xl)),
      ],
    );
  }

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
              child: Text(tr('重试')),
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
    final sources = browsableSources(category);
    if (sources.isEmpty) {
      return SliverToBoxAdapter(
        child: EmptyState(
          icon: Icons.extension_off_outlined,
          title: category == null ? tr('还没有启用的站点') : tr('这个分类还没有启用的站点'),
          message: tr('在站点管理中启用或安装站点'),
          actions: [
            FilledButton(
              onPressed: () => Nav.push(context, const SourceManagePage()),
              child: Text(tr('管理站点')),
            ),
          ],
        ),
      );
    }
    // Inside a category: one shelf per site. On “全部”: the first site of each category.
    final shelves = <({InstalledSource source, SourceCategory category})>[
      if (category != null)
        for (final s in sources) (source: s, category: category)
      else
        for (final c in AppSettings.instance.domainOrder)
          if (_interesting(c))
            if (sources.where((s) => s.manifest!.category == c).firstOrNull
                case final first?)
              (source: first, category: c),
    ];
    return SliverList.builder(
      itemCount: shelves.length,
      itemBuilder: (context, i) {
        final shelf = shelves[i];
        final name = shelf.source.manifest!.name;
        return FeedShelf(
          key: ValueKey('${shelf.category.name}:${shelf.source.key}'),
          sourceKey: shelf.source.key,
          title: category == null ? '${shelf.category.label} · $name' : name,
          moreLabel: category == null ? tr('更多') : tr('进入'),
          onMore: category == null
              ? () => _select(DiscoveryDestination.domain(shelf.category))
              : () => Nav.openSource(context, shelf.source.key),
        );
      },
    );
  }
}
