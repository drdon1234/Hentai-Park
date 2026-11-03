import 'package:flutter/material.dart';

import '../../core/content_scope.dart';
import '../../core/localization.dart';
import '../../core/models.dart';
import '../../engine/source_manager.dart';
import '../kit/kit.dart';
import '../nav.dart';
import '../search/aggregate_search_page.dart';
import '../source/source_page.dart';
import '../widgets/common.dart';

/// 资料浏览保留在对应域中，列表与搜索复用站点原生的分页、筛选能力。
class MetadataSitesPage extends StatelessWidget {
  const MetadataSitesPage({super.key, required this.category});
  final SourceCategory category;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('搜索作品资料'))),
    body: ListenableBuilder(
      listenable: SourceManager.instance,
      builder: (context, _) {
        final sources = SourceManager.instance.enabled
            .where(
              (source) =>
                  (source.manifest!.metadataOnly ||
                      source.manifest!.rankingOnly &&
                          source.manifest!.can('metadataDetail')) &&
                  (source.manifest!.category == category ||
                      source.manifest!.rankings.any(
                        (board) => board.category == category,
                      )),
            )
            .toList();
        return SettingsBody(
          child: sources.isEmpty
              ? EmptyState(
                  icon: Icons.info_outline_rounded,
                  title: tr('没有启用的资料插件'),
                  message: tr('在站点管理中启用或安装资料插件'),
                )
              : ListView(
                  children: [
                    ParkSearchField(
                      hint: tr(
                        category == SourceCategory.jav
                            ? '搜索番号、作品名或演员'
                            : '搜索作品名、标签或作者',
                      ),
                      onSubmitted: (keyword) {
                        if (keyword.trim().isEmpty) return;
                        Nav.push(
                          context,
                          AggregateSearchPage(
                            initialKeyword: keyword.trim(),
                            scope: ContentScope.domain(category),
                            metadataOnly: true,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: Gap.m),
                    RowGroup(
                      children: [
                        for (final source in sources)
                          ListTile(
                            title: Text(source.manifest!.name),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => Nav.push(
                              context,
                              SourcePage(sourceKey: source.key),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
        );
      },
    ),
  );
}
