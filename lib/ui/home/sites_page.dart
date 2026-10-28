import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../engine/source_manager.dart';
import '../discovery_navigation.dart';
import '../nav.dart';
import '../settings/source_manage_page.dart';
import '../settings/source_settings_page.dart';
import '../source/source_page.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Every enabled site, grouped by category, as a hairline list. Sites are a secondary entry:
/// the home page leads with content.
class SitesPage extends StatelessWidget {
  const SitesPage({super.key, this.sourceManager});
  final SourceManager? sourceManager;

  @override
  Widget build(BuildContext context) {
    final sm = sourceManager ?? SourceManager.instance;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('站点')),
        actions: [
          OutlinedButton(
            onPressed: () => Nav.push(context, const SourceManagePage()),
            child: SelectionContainer.disabled(child: Text(tr('管理'))),
          ),
          const SizedBox(width: Gap.xs),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          sm,
          AppSettings.instance.watch(const {'domainOrder'}),
        ]),
        builder: (context, _) {
          final sources = sm.displayEnabled
              .where(
                (source) =>
                    !source.manifest!.metadataOnly &&
                    !source.manifest!.rankingOnly &&
                    !source.manifest!.reverseSearchOnly,
              )
              .toList();
          if (sources.isEmpty) {
            return EmptyState(
              icon: Icons.extension_off_outlined,
              title: tr('还没有启用的站点'),
              message: tr('在站点管理中启用或安装站点'),
              actions: [
                FilledButton(
                  onPressed: () => Nav.push(context, const SourceManagePage()),
                  child: SelectionContainer.disabled(child: Text(tr('管理站点'))),
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: Gap.xl),
            children: [
              for (final category in AppSettings.instance.domainOrder)
                if (sources.any((s) => s.manifest!.category == category))
                  Column(
                    children: [
                      SectionHeader(
                        category.label,
                        titleStyle: ParkText.serif(
                          context.text.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        emphasizeTrailing: false,
                        trailing: DomainEntryButton(
                          onPressed: () => DiscoveryNavigation.of(context)!
                              .onSelect(DiscoveryDestination.domain(category)),
                        ),
                      ),
                      RowGroup(
                        children: [
                          for (final s in sources.where(
                            (s) => s.manifest!.category == category,
                          ))
                            SiteRow(source: s),
                        ],
                      ),
                    ],
                  ),
            ],
          );
        },
      ),
    );
  }
}

/// One site: tap to browse it; the visible “更多” menu carries search, ranking, random and
/// settings, so nothing depends on a long press.
class SiteRow extends StatelessWidget {
  const SiteRow({
    super.key,
    required this.source,
    this.homeSourceVisible,
    this.onToggleWorks,
    this.showMore = true,
    this.showDetails = true,
    this.showEnterButton = false,
    this.avatarFontWeight = FontWeight.w600,
  });
  final InstalledSource source;
  final bool? homeSourceVisible;
  final VoidCallback? onToggleWorks;
  final bool showMore;
  final bool showDetails;
  final bool showEnterButton;
  final FontWeight avatarFontWeight;

  int? get _ranking {
    final feeds = source.manifest!.feeds;
    for (final key in ['rank', 'toplist', 'popular']) {
      final index = feeds.indexWhere((f) => f.key.toLowerCase().contains(key));
      if (index >= 0) return index;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: source.accountListenable,
    builder: (context, account, _) => _build(context, account),
  );

  Widget _build(BuildContext context, AccountStatus? account) {
    final m = source.manifest!;
    final needsAccount =
        (m.account?.required == true || m.account?.managedAccount == true) &&
        account?.loggedIn != true;
    final status = account?.loggedIn == true
        ? (account!.name.isEmpty
              ? tr('已登录')
              : tr('已登录：{name}', {'name': account.name}))
        : needsAccount
        ? tr('需要登录')
        : null;
    final ranking = _ranking;
    return ListRow(
      leading: SourceAvatar(source.key, fontWeight: avatarFontWeight),
      title: m.name,
      subtitle: showDetails
          ? [?status, if (m.description.isNotEmpty) m.description].join(' · ')
          : null,
      subtitleMaxLines: 1,
      titleStyle: showDetails
          ? null
          : context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      onTap: () => Nav.openSource(context, source.key),
      onLongPress: () => Nav.openSourceSettings(context, source.key),
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.s, Gap.xs, Gap.s),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onToggleWorks != null)
            IconButton(
              tooltip: tr(
                homeSourceVisible == true ? '隐藏该站点的作品并停止自动加载' : '显示该站点的作品并自动加载',
              ),
              icon: Icon(
                homeSourceVisible == true
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: onToggleWorks,
            ),
          if (showEnterButton)
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: context.colors.primary,
                minimumSize: const Size(48, 40),
                padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
              ),
              onPressed: () => Nav.openSource(context, source.key),
              child: SelectionContainer.disabled(
                child: Text(
                  tr('进入'),
                  style: context.text.labelLarge?.copyWith(
                    color: context.colors.primary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          if (showMore)
            PopupMenuButton<String>(
              tooltip: tr('更多'),
              onSelected: (action) {
                switch (action) {
                  case 'search':
                    Nav.openSourceSearch(context, source.key);
                  case 'ranking':
                    Nav.push(
                      context,
                      SourcePage(sourceKey: source.key, initialFeed: ranking),
                    );
                  case 'random':
                    Nav.random(context, source.key);
                  case 'account':
                    Nav.push(
                      context,
                      SourceSettingsPage(
                        sourceKey: source.key,
                        showManagedAccountPrompt:
                            m.account?.managedAccount == true,
                      ),
                    );
                  case 'settings':
                    Nav.openSourceSettings(context, source.key);
                }
              },
              itemBuilder: (_) => [
                if (m.can('search'))
                  PopupMenuItem(
                    value: 'search',
                    child: SelectionContainer.disabled(
                      child: Text(tr('在此站点搜索')),
                    ),
                  ),
                if (ranking != null && !AppSettings.instance.searchOnlySources)
                  PopupMenuItem(
                    value: 'ranking',
                    child: SelectionContainer.disabled(child: Text(tr('排行'))),
                  ),
                if (m.can('random') && !AppSettings.instance.searchOnlySources)
                  PopupMenuItem(
                    value: 'random',
                    child: SelectionContainer.disabled(child: Text(tr('随机一部'))),
                  ),
                if (needsAccount)
                  PopupMenuItem(
                    value: 'account',
                    child: SelectionContainer.disabled(
                      child: Text(tr('登录或配置账号')),
                    ),
                  ),
                PopupMenuItem(
                  value: 'settings',
                  child: SelectionContainer.disabled(child: Text(tr('站点设置'))),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Sources that can appear in a category on the home page.
List<InstalledSource> browsableSources(SourceCategory? category) =>
    SourceManager.instance.displayEnabled
        .where(
          (s) =>
              (s.manifest!.feeds.isNotEmpty ||
                  s.manifest!.can('subscription')) &&
              (category == null || s.manifest!.category == category),
        )
        .toList();
