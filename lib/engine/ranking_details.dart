import '../core/models.dart';
import '../core/settings.dart';
import 'source_manager.dart';

/// 仅按实际能力列出候选；不把排名身份当成其他站点的作品 ID。
List<InstalledSource> rankingDetailSources(
  SourceManager manager,
  SourceCategory category, {
  String? origin,
}) {
  final sources = manager.enabled.where((source) {
    final m = source.manifest!;
    return (m.category == category ||
            m.rankings.any((board) => board.category == category)) &&
        ((m.can('metadataDetail') &&
                (m.can('metadataSearch') || source.key == origin)) ||
            (!m.rankingOnly && m.can('search') && m.can('detail')));
  }).toList();
  return sources;
}

/// 榜单与资料详情共用同一搜索选择；首选站失效时使用同域首个可搜索站。
String? rankingSearchSource(SourceManager manager, SourceCategory category) {
  final settings = AppSettings.instance;
  final selected =
      (settings.rankingSelection['searchSources'] as Map?)?[category.name];
  final candidates = manager.displayEnabled
      .where(
        (source) =>
            source.manifest!.category == category &&
            source.manifest!.can('search') &&
            !source.manifest!.metadataOnly &&
            !source.manifest!.rankingOnly,
      )
      .toList();
  if (selected == 'preferred') {
    final preferred = settings.homeSource(category);
    return candidates.any((source) => source.key == preferred)
        ? preferred
        : candidates.firstOrNull?.key;
  }
  return candidates.any((source) => source.key == selected)
      ? selected as String
      : null;
}
