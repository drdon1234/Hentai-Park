import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../engine/source_manager.dart';
import '../../library/library.dart';
import '../history/continue_reading_page.dart';
import '../nav.dart';
import '../settings/source_manage_page.dart';
import '../source/source_page.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/paged_grid.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final sm = SourceManager.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([sm, Library.instance]),
      builder: (context, _) {
        final recent = Library.instance.history().take(12).toList();
        return CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              snap: true,
              titleSpacing: 20,
              title: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      gradient: LinearGradient(colors: [context.colors.primary, context.colors.tertiary]),
                    ),
                    child: const Icon(Icons.auto_stories_rounded, size: 18, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  const Text('HentaiPark'),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Nav.push(context, const SourceManagePage()), child: const Text('源站管理')),
                const SizedBox(width: 8),
              ],
            ),
            SliverToBoxAdapter(child: _SearchEntry(onTap: () => Nav.openAggregateSearch(context))),
            if (recent.isNotEmpty)
              SliverToBoxAdapter(
                child: WorkCarousel(
                  title: '继续阅读',
                  items: recent.map((h) => h.item).toList(),
                  showSource: true,
                  leading: Icon(Icons.history_rounded, color: context.colors.primary, size: 20),
                  trailing: TextButton.icon(
                    onPressed: () => Nav.push(context, const ContinueReadingPage()),
                    icon: const Icon(Icons.checklist_rounded, size: 18),
                    label: const Text('管理'),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: SectionHeader(
                '源站',
                leading: Icon(Icons.hub_outlined, color: context.colors.primary, size: 20),
                trailing: TextButton.icon(
                  onPressed: () => Nav.push(context, const SourceManagePage()),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('管理'),
                ),
              ),
            ),
            if (!sm.loaded)
              const SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 360,
                    mainAxisExtent: 148,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildListDelegate.fixed([Skeleton(radius: 20), Skeleton(radius: 20), Skeleton(radius: 20), Skeleton(radius: 20)]),
                ),
              )
            else if (sm.enabled.isEmpty)
              SliverToBoxAdapter(
                child: MessageView(
                  icon: Icons.extension_off_outlined,
                  title: '还没有启用的源站',
                  message: '在源站管理中启用或安装源',
                  actions: [FilledButton(onPressed: () => Nav.push(context, const SourceManagePage()), child: const Text('管理源站'))],
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 360,
                    mainAxisExtent: 148,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate((context, i) => SourceTile(source: sm.enabled[i]), childCount: sm.enabled.length),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SearchEntry extends StatelessWidget {
  const _SearchEntry({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: c.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: c.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('聚合搜索所有源站', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('关键词、标签，或直接粘贴链接 / 车号', style: context.text.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_rounded, color: c.onSurfaceVariant, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Entry card for one source: brand color, what it offers, account state and quick actions.
class SourceTile extends StatelessWidget {
  const SourceTile({super.key, required this.source});
  final InstalledSource source;

  /// First feed matching the keys in priority order (so "toplist" wins over "popular").
  int? _feedIndex(SourceManifest m, List<String> keys) {
    for (final k in keys) {
      final i = m.feeds.indexWhere((f) => f.key.contains(k));
      if (i >= 0) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final m = source.manifest!;
    final c = context.colors;
    final needsLogin = m.account?.required == true && source.account?.loggedIn != true;
    final rankingIndex = _feedIndex(m, ['rank', 'toplist', 'popular']);
    return Material(
      color: c.surfaceContainer,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Nav.openSource(context, source.key),
        onLongPress: () => Nav.openSourceSettings(context, source.key),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [m.color.withValues(alpha: 0.30), m.color.withValues(alpha: 0.04)],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SourceAvatar(source.key, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.name,
                              style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            // One line only: a wrapped second row would push the description out of the tile.
                            Row(
                              children: [
                                Pill(m.isVideo ? '视频' : '漫画', color: m.color, icon: m.isVideo ? Icons.smart_display_outlined : Icons.menu_book_rounded),
                                if (needsLogin) ...[
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Pill('未登录', color: c.error, icon: Icons.lock_outline_rounded),
                                  ),
                                ],
                                if (source.account?.loggedIn == true) ...[
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Pill(source.account!.name.isEmpty ? '已登录' : source.account!.name, color: Colors.green, icon: Icons.person_rounded),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Text(
                      m.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodySmall?.copyWith(color: c.onSurfaceVariant, height: 1.35),
                    ),
                  ),
                  Row(
                    children: [
                      if (rankingIndex != null)
                        _QuickAction(
                          icon: Icons.leaderboard_outlined,
                          label: '排行',
                          onTap: () => Nav.push(context, SourcePage(sourceKey: source.key, initialFeed: rankingIndex)),
                        ),
                      if (m.can('search')) _QuickAction(icon: Icons.search_rounded, label: '搜索', onTap: () => Nav.openSourceSearch(context, source.key)),
                      if (m.can('random')) _QuickAction(icon: Icons.casino_outlined, label: '随机', onTap: () => Nav.random(context, source.key)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact action that shares the tile width equally with its siblings (never overflows).
class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: context.colors.onSurface),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
