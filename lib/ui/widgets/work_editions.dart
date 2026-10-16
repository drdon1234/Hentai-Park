import '../../core/localization.dart';
import '../../core/models.dart';
import '../../engine/source_manager.dart';

/// 版本名称属于插件固定文案，搜索与保存继续使用原始 ID 和标签。
String workEditionLabel(WorkItem item) {
  final copy = SourceManager.instance.manifest(item.source)?.copy;
  return item.editions
      .map((label) => copy?.text(label) ?? tr(label))
      .join(' · ');
}
