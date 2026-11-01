import '../core/models.dart';
import '../core/settings.dart';
import 'source_manager.dart';

/// 仅按实际能力列出候选；不把排名身份当成其他站点的作品 ID。
List<InstalledSource> rankingDetailSources(
  SourceManager manager,
  SourceCategory category, {
  String? origin,
}) {
  final priority = AppSettings.instance.rankingDetailPriority;
  final sources = manager.enabled.where((source) {
    final m = source.manifest!;
    return (m.category == category ||
            m.rankings.any((board) => board.category == category)) &&
        ((m.can('metadataDetail') &&
                (m.can('metadataSearch') || source.key == origin)) ||
            (!m.rankingOnly && m.can('search') && m.can('detail')));
  }).toList();
  int rank(String key) {
    final index = priority.indexOf(key);
    return index < 0 ? priority.length : index;
  }

  // 原始顺序用于尚未配置优先级的新站点。
  final original = {for (var i = 0; i < sources.length; i++) sources[i].key: i};
  sources.sort((a, b) {
    final compared = rank(a.key).compareTo(rank(b.key));
    return compared != 0
        ? compared
        : original[a.key]!.compareTo(original[b.key]!);
  });
  return sources;
}
