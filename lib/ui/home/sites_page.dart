import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../engine/source_manager.dart';
import '../nav.dart';
import '../settings/source_manage_page.dart';
import '../settings/source_settings_page.dart';
import '../source/source_page.dart';
import '../widgets/common.dart';

/// Every enabled site, grouped by category, as a hairline list. Sites are a secondary entry:
/// the home page leads with content.
class SitesPage extends StatelessWidget {
  const SitesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final sm = SourceManager.instance;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('站点')),
        actions: [
          TextButton(
            onPressed: () => Nav.push(context, const SourceManagePage()),
            child: Text(tr('管理')),
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
          final sources = sm.enabled;
          if (sources.isEmpty) {
            return EmptyState(
              icon: Icons.extension_off_outlined,
              title: tr('还没有启用的站点'),
              message: tr('在站点管理中启用或安装站点'),
              actions: [
                FilledButton(
                  onPressed: () => Nav.push(context, const SourceManagePage()),
                  child: Text(tr('管理站点')),
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: Gap.xl),
            children: [
              for (final category in AppSettings.instance.domainOrder)
                if (sources.any((s) => s.manifest!.category == category))
                  RowGroup(
                    title: category.label,
                    children: [
                      for (final s in sources.where(
                        (s) => s.manifest!.category == category,
                      ))
                        SiteRow(source: s),
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
  const SiteRow({super.key, required this.source});
  final InstalledSource source;

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
      leading: SourceAvatar(source.key),
      title: m.name,
      subtitle: [
        ?status,
        if (m.description.isNotEmpty) m.description,
      ].join(' · '),
      subtitleMaxLines: 1,
      onTap: () => Nav.openSource(context, source.key),
      onLongPress: () => Nav.openSourceSettings(context, source.key),
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.s, Gap.xs, Gap.s),
      trailing: PopupMenuButton<String>(
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
                  showManagedAccountPrompt: m.account?.managedAccount == true,
                ),
              );
            case 'settings':
              Nav.openSourceSettings(context, source.key);
          }
        },
        itemBuilder: (_) => [
          if (m.can('search'))
            PopupMenuItem(value: 'search', child: Text(tr('在此站点搜索'))),
          if (ranking != null)
            PopupMenuItem(value: 'ranking', child: Text(tr('排行'))),
          if (m.can('random'))
            PopupMenuItem(value: 'random', child: Text(tr('随机一部'))),
          if (needsAccount)
            PopupMenuItem(value: 'account', child: Text(tr('登录或配置账号'))),
          PopupMenuItem(value: 'settings', child: Text(tr('站点设置'))),
        ],
      ),
    );
  }
}

/// Sources that can appear in a category on the home page.
List<InstalledSource> browsableSources(SourceCategory? category) =>
    SourceManager.instance.enabled
        .where(
          (s) =>
              s.manifest!.feeds.isNotEmpty &&
              (category == null || s.manifest!.category == category),
        )
        .toList();
