import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../nav.dart';
import '../theme.dart';
import 'common.dart';
import 'content_translation.dart';
import 'cover_tile.dart';
import 'work_editions.dart';

/// 小说作品不构造封面；行高随标题、简介和系统字体增长。
class WorkTextRow extends StatelessWidget {
  const WorkTextRow({super.key, required this.item, this.showSource = false});
  final WorkItem item;
  final bool showSource;

  @override
  // One semantics node: the translatable texts below have their own long-press
  // handlers, which would otherwise split the row from its title.
  Widget build(BuildContext context) => MergeSemantics(
    child: InkWell(
      onTap: () => Nav.openWork(context, item),
      onLongPress: () => showWorkActions(context, item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ContentTranslation(
              text: item.title,
              source: item.source,
              builder: (text) => Text(text, style: context.text.titleMedium),
            ),
            if (item.subtitle.isNotEmpty && item.subtitle != item.title) ...[
              const SizedBox(height: 6),
              ContentTranslation(
                text: item.subtitle,
                source: item.source,
                builder: (text) => Text(text, style: context.text.bodyMedium),
              ),
            ],
            if (showSource ||
                item.editions.isNotEmpty ||
                item.uploaded.isNotEmpty ||
                item.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (showSource) SourceAvatar(item.source, size: 20),
                  if (item.editions.isNotEmpty)
                    Text(workEditionLabel(item), style: context.text.bodySmall),
                  if (item.uploaded.isNotEmpty)
                    Text(item.uploaded, style: context.text.bodySmall),
                  for (final tag in item.tags.take(4))
                    Text(tag, style: context.text.bodySmall),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
