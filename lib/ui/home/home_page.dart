import 'package:flutter/material.dart';

import '../../core/content_scope.dart';
import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../engine/source_manager.dart';
import '../../library/library.dart';
import '../discovery_navigation.dart';
import '../history/history_page.dart';
import '../nav.dart';
import '../settings/source_manage_page.dart';
import '../subscriptions/subscriptions_page.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/content_translation.dart';
import '../history/recent_history.dart';
import 'source_tile.dart';

export 'source_tile.dart' show SourceTile;

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.destination, this.onOpenHistory});
  final ValueNotifier<DiscoveryDestination>? destination;
  final VoidCallback? onOpenHistory;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _localDestination = ValueNotifier(const DiscoveryDestination.all());
  final _scroll = ScrollController();
  bool _subscriptionsVisited = false;
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
  void _history() {
    if (widget.onOpenHistory != null) {
      widget.onOpenHistory!();
    } else {
      Nav.push(context, const HistoryPage());
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
    AppLocalizations.of(context);
    final sm = SourceManager.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([
        sm,
        Library.instance,
        AppSettings.instance,
      ]),
      builder: (context, _) {
        final selected = _destination.value;
        final domains = selected.category == null
            ? AppSettings.instance.domainOrder
            : [selected.category!];
        final sources = sm.enabled
            .where(
              (s) =>
                  !s.manifest!.can('subscription') ||
                  s.manifest!.feeds.isNotEmpty,
            )
            .toList();
        return Column(
          children: [
            Material(
              color: context.colors.surface,
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    SizedBox(
                      height: 56,
                      child: Row(
                        children: [
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              'HentaiPark',
                              style: context.text.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DomainMenu(onSelected: _select),
                          const TranslationControls(),
                          IconButton(
                            onPressed: () =>
                                Nav.push(context, const SourceManagePage()),
                            tooltip: tr('源站管理'),
                            icon: const Icon(Icons.tune_rounded),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                    DiscoveryDomainBar(selected: selected, onSelected: _select),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: IndexedStack(
                index: selected.subscription ? 1 : 0,
                children: [
                  CustomScrollView(
                    controller: _scroll,
                    slivers: [
                      SliverToBoxAdapter(
                        child: _SearchEntry(
                          domain: selected.category,
                          onTap: () => Nav.openAggregateSearch(
                            context,
                            scope: selected.category == null
                                ? const ContentScope.all()
                                : ContentScope.domain(selected.category!),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: RecentHistory(
                          limit: 20,
                          onOpenHistory: _history,
                        ),
                      ),
                      if (sm.initializationError != null)
                        SliverToBoxAdapter(
                          child: MessageView(
                            icon: Icons.error_outline,
                            title: tr('源初始化失败，请重试'),
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
                        )
                      else if (!sm.loaded)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        )
                      else if (!sources.any(
                        (s) => domains.contains(s.manifest!.category),
                      ))
                        SliverToBoxAdapter(
                          child: MessageView(
                            icon: Icons.extension_off_outlined,
                            title: tr('还没有启用的源站'),
                            message: tr('在源站管理中启用或安装源'),
                            actions: [
                              FilledButton(
                                onPressed: () =>
                                    Nav.push(context, const SourceManagePage()),
                                child: Text(tr('管理源站')),
                              ),
                            ],
                          ),
                        )
                      else
                        for (final domain in domains)
                          if (sources.any(
                            (s) => s.manifest!.category == domain,
                          )) ...[
                            SliverToBoxAdapter(
                              child: SectionHeader(
                                domain.label,
                                trailing: IconButton(
                                  tooltip: tr('域内聚合搜索'),
                                  icon: const Icon(Icons.search),
                                  onPressed: () => Nav.openAggregateSearch(
                                    context,
                                    scope: ContentScope.domain(domain),
                                  ),
                                ),
                              ),
                            ),
                            _SourceGrid(
                              sources: sources
                                  .where((s) => s.manifest!.category == domain)
                                  .toList(),
                            ),
                          ],
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  ),
                  if (_subscriptionsVisited)
                    const SubscriptionsPage(embedded: true)
                  else
                    const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 不固定卡片高度：登录提示、大字体和长译文都可以自然扩展。
class _SourceGrid extends StatelessWidget {
  const _SourceGrid({required this.sources});
  final List<InstalledSource> sources;
  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns =
          ((constraints.crossAxisExtent - 20) /
                  (300 * scale.clamp(1, 1.6) + 12))
              .floor()
              .clamp(1, 6);
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.builder(
          itemCount: (sources.length / columns).ceil(),
          itemBuilder: (context, row) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var col = 0; col < columns; col++) ...[
                  if (col > 0) const SizedBox(width: 12),
                  Expanded(
                    child: row * columns + col < sources.length
                        ? SourceTile(
                            key: ValueKey(sources[row * columns + col].key),
                            source: sources[row * columns + col],
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _SearchEntry extends StatelessWidget {
  const _SearchEntry({required this.onTap, this.domain});
  final VoidCallback onTap;
  final SourceCategory? domain;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Material(
      color: context.colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: context.colors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(domain == null ? '跨域聚合搜索' : '域内聚合搜索'),
                      style: context.text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tr('关键词、标签，或直接粘贴链接 / 车号'),
                      style: context.text.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded, size: 20),
            ],
          ),
        ),
      ),
    ),
  );
}
