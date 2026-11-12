import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/voice.dart';
import '../nav.dart';
import '../widgets/content_translation.dart';
import 'voice_directory_page.dart';

/// 浏览和搜索共用目录入口；展开后沿用目录播放器的分页、字幕与附件规则。
class VoiceTreeTile extends StatelessWidget {
  const VoiceTreeTile({super.key, required this.item});
  final WorkItem item;

  @override
  Widget build(BuildContext context) {
    final kind = VoiceNodeKind.fromJson(item.json['voiceNodeType']);
    final root = VoiceNode(id: item.id, name: item.title, kind: kind);
    final work = WorkDetail({
      ...item.json,
      'voiceRoot': {'id': root.id, 'name': root.name, 'type': kind.name},
    }, item.source);
    if (kind != VoiceNodeKind.directory) {
      return ListTile(
        leading: Icon(
          kind == VoiceNodeKind.audio
              ? Icons.audio_file_outlined
              : Icons.insert_drive_file_outlined,
        ),
        title: Text(item.title),
        subtitle: Text(item.id),
        onTap: () =>
            Nav.push(context, VoiceDirectoryPage(work: work, root: root)),
      );
    }
    return ExpansionTile(
      key: PageStorageKey(item.uid),
      leading: const Icon(Icons.folder_outlined),
      title: ContentTranslation(
        text: item.title,
        source: item.source,
        builder: (text) => Text(text),
      ),
      subtitle: Text(item.id, maxLines: 2, overflow: TextOverflow.ellipsis),
      children: [
        VoiceDirectoryPage(
          key: PageStorageKey('${item.uid}:directory'),
          work: work,
          root: root,
          embedded: true,
        ),
      ],
    );
  }
}
