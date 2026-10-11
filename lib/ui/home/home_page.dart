import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/localization.dart';
import '../../engine/source_manager.dart';
import '../../library/library.dart';
import '../history/continue_reading_page.dart';
import '../nav.dart';
import '../settings/source_manage_page.dart';
import '../settings/source_settings_page.dart';
import '../source/source_page.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/paged_grid.dart';

/// The same measurements are used by the loaded grid and its skeletons. Include the title,
/// account pill, two description lines, and quick actions at the user's current text scale.
double sourceTileExtent(BuildContext context) {
  double lineHeight(TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: 'Ag字', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.height;
  }

  final pill =
      lineHeight(
        const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ).clamp(11, double.infinity) +
      4;
  final heading =
      (lineHeight(
                context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ) +
              3 +
              pill)
          .clamp(40, double.infinity);
  final description =
      2 * lineHeight(context.text.bodySmall?.copyWith(height: 1.35));
  final actions =
      lineHeight(
        context.text.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      ).clamp(15, double.infinity) +
      16;
  return (14 + heading + 8 + description + actions + 8)
      .clamp(148, double.infinity)
      .toDouble();
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final sm = SourceManager.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([sm, Library.instance]),
      builder: (context, _) {
        final recent = Library.instance.history().take(12).toList();
        final pica = sm['pica'];
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
                      gradient: LinearGradient(
                        colors: [
                          context.colors.primary,
                          context.colors.tertiary,
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.auto_stories_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text('HentaiPark'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Nav.push(context, const SourceManagePage()),
                  child: Text(context.tr('源站管理')),
                ),
                const SizedBox(width: 8),
              ],
            ),
            SliverToBoxAdapter(
              child: _SearchEntry(
                onTap: () => Nav.openAggregateSearch(context),
              ),
            ),
            if (sm.loaded &&
                pica?.enabled == true &&
                pica?.ready == true &&
                pica?.manifest?.account?.managedAccount == true &&
                pica?.account != null &&
                pica!.account!.loggedIn != true)
              SliverToBoxAdapter(child: _AccountNotice(source: pica)),
            if (recent.isNotEmpty)
              SliverToBoxAdapter(
                child: WorkCarousel(
                  title: context.tr('继续阅读'),
                  items: recent.map((h) => h.item).toList(),
                  showSource: true,
                  leading: Icon(
                    Icons.history_rounded,
                    color: context.colors.primary,
                    size: 20,
                  ),
                  trailing: TextButton.icon(
                    onPressed: () =>
                        Nav.push(context, const ContinueReadingPage()),
                    icon: const Icon(Icons.checklist_rounded, size: 18),
                    label: Text(context.tr('管理')),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: SectionHeader(
                context.tr('源站'),
                leading: Icon(
                  Icons.hub_outlined,
                  color: context.colors.primary,
                  size: 20,
                ),
                trailing: TextButton.icon(
                  onPressed: () => Nav.push(context, const SourceManagePage()),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: Text(context.tr('管理')),
                ),
              ),
            ),
            if (!sm.loaded)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 360,
                    mainAxisExtent: sourceTileExtent(context),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildListDelegate.fixed([
                    const Skeleton(radius: 20),
                    const Skeleton(radius: 20),
                    const Skeleton(radius: 20),
                    const Skeleton(radius: 20),
                  ]),
                ),
              )
            else if (sm.enabled.isEmpty)
              SliverToBoxAdapter(
                child: MessageView(
                  icon: Icons.extension_off_outlined,
                  title: context.tr('还没有启用的源站'),
                  message: context.tr('在源站管理中启用或安装源'),
                  actions: [
                    FilledButton(
                      onPressed: () =>
                          Nav.push(context, const SourceManagePage()),
                      child: Text(context.tr('管理源站')),
                    ),
                  ],
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 360,
                    mainAxisExtent: sourceTileExtent(context),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => SourceTile(source: sm.enabled[i]),
                    childCount: sm.enabled.length,
                  ),
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
                      Text(
                        context.tr('聚合搜索所有源站'),
                        style: context.text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.tr('关键词、标签，或直接粘贴链接 / 车号'),
                        style: context.text.bodySmall?.copyWith(
                          color: c.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: c.onSurfaceVariant,
                  size: 20,
                ),
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
    final needsLogin =
        m.account?.required == true &&
        source.account != null &&
        source.account?.loggedIn != true;
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
                    colors: [
                      m.color.withValues(alpha: 0.30),
                      m.color.withValues(alpha: 0.04),
                    ],
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
                              style: context.text.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            // One line only: a wrapped second row would push the description out of the tile.
                            Row(
                              children: [
                                Pill(
                                  context.tr(m.isVideo ? '视频' : '漫画'),
                                  color: m.color,
                                  icon: m.isVideo
                                      ? Icons.smart_display_outlined
                                      : Icons.menu_book_rounded,
                                ),
                                if (needsLogin) ...[
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Pill(
                                      context.tr('未登录'),
                                      color: c.error,
                                      icon: Icons.lock_outline_rounded,
                                    ),
                                  ),
                                ],
                                if (source.account?.loggedIn == true) ...[
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Pill(
                                      source.account!.name.isEmpty
                                          ? context.tr('已登录')
                                          : source.account!.name,
                                      color: Colors.green,
                                      icon: Icons.person_rounded,
                                    ),
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
                      style: context.text.bodySmall?.copyWith(
                        color: c.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      if (rankingIndex != null)
                        _QuickAction(
                          icon: Icons.leaderboard_outlined,
                          label: context.tr('排行'),
                          onTap: () => Nav.push(
                            context,
                            SourcePage(
                              sourceKey: source.key,
                              initialFeed: rankingIndex,
                            ),
                          ),
                        ),
                      if (m.can('search'))
                        _QuickAction(
                          icon: Icons.search_rounded,
                          label: context.tr('搜索'),
                          onTap: () =>
                              Nav.openSourceSearch(context, source.key),
                        ),
                      if (m.can('random'))
                        _QuickAction(
                          icon: Icons.casino_outlined,
                          label: context.tr('随机'),
                          onTap: () => Nav.random(context, source.key),
                        ),
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

class _AccountNotice extends StatelessWidget {
  const _AccountNotice({required this.source});
  final InstalledSource source;

  @override
  Widget build(BuildContext context) {
    final configured = source.account?.configured == true;
    final managed =
        SourceManager.instance.settingsOf(source.key)['managedAccount'] == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(configured ? '哔咔账号尚未登录' : '哔咔尚未配置账号'),
                style: context.text.titleSmall,
              ),
              const SizedBox(height: 6),
              Text(
                context.tr(
                  configured
                      ? '打开账号设置完成登录，或重试已保存的专用账号。'
                      : '请选择自行配置账号，或自动注册一个专用账号。',
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () =>
                        Nav.openSourceSettings(context, source.key),
                    child: Text(context.tr(configured ? '账号设置' : '自行配置')),
                  ),
                  if (!configured || managed)
                    FilledButton.icon(
                      onPressed: () => Nav.push(
                        context,
                        SourceSettingsPage(
                          sourceKey: source.key,
                          showManagedAccountPrompt: true,
                        ),
                      ),
                      icon: Icon(
                        managed
                            ? Icons.refresh_rounded
                            : Icons.person_add_alt_1_rounded,
                        size: 18,
                      ),
                      label: Text(context.tr(managed ? '重试专用账号' : '自动注册专用账号')),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact action that shares the tile width equally with its siblings (never overflows).
class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
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
                style: context.text.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
