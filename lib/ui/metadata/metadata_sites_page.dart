import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../engine/source_manager.dart';
import '../kit/kit.dart';
import '../nav.dart';
import '../source/source_page.dart';
import '../widgets/common.dart';

/// 资料浏览保留在对应域中，列表与搜索复用站点原生的分页、筛选能力。
class MetadataSitesPage extends StatelessWidget {
  const MetadataSitesPage({super.key, required this.category});
  final SourceCategory category;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('作品资料'))),
    body: ListenableBuilder(
      listenable: SourceManager.instance,
      builder: (context, _) {
        final sources = SourceManager.instance.enabled
            .where(
              (source) =>
                  source.manifest!.metadataOnly &&
                  source.manifest!.category == category,
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
