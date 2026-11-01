import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../engine/source_manager.dart';
import '../kit/kit.dart';

class RankingPriorityPage extends StatelessWidget {
  const RankingPriorityPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    final manager = SourceManager.instance;
    return Scaffold(
      appBar: AppBar(title: Text(tr('排行榜作品详情站点优先级'))),
      body: SettingsBody(
        child: ListenableBuilder(
          listenable: Listenable.merge([
            manager,
            settings.domain(SettingsDomain.search),
          ]),
          builder: (context, _) {
            final sources = manager.enabled.where((source) {
              final m = source.manifest!;
              return m.can('metadataDetail') ||
                  (!m.rankingOnly && m.can('search') && m.can('detail'));
            }).toList();
            final priority = settings.rankingDetailPriority;
            final keys = [
              ...priority.where((key) => sources.any((s) => s.key == key)),
              ...sources
                  .map((s) => s.key)
                  .where((key) => !priority.contains(key)),
            ];
            return ReorderableListView.builder(
              header: Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.m),
                child: Text(tr('拖动排序；本站榜单默认打开本站详情，跨站查找按同域优先级，指定详情站点时使用所选站点。')),
              ),
              buildDefaultDragHandles: false,
              itemCount: keys.length,
              onReorderItem: (from, to) {
                keys.insert(to, keys.removeAt(from));
                // 暂时停用的站点保留其记录，重新启用后仍可继续调整。
                settings.rankingDetailPriority = [
                  ...keys,
                  ...priority.where((key) => !keys.contains(key)),
                ];
              },
              itemBuilder: (context, index) {
                final m = manager.manifest(keys[index])!;
                return HairlineItem(
                  key: ValueKey(keys[index]),
                  child: ListTile(
                    title: Text(m.name),
                    subtitle: Text(m.category.label),
                    trailing: ReorderableDragStartListener(
                      index: index,
                      child: Padding(
                        padding: const EdgeInsets.all(Gap.m),
                        child: Icon(
                          Icons.drag_handle_rounded,
                          semanticLabel: tr('拖动排序'),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
