import 'package:flutter/material.dart';

import '../../core/localization.dart';
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
  // 整行作为一个可访问性入口，长按统一交给作品操作菜单。
  Widget build(BuildContext context) => MergeSemantics(
    child: ActionInkWell(
      onTap: () => Nav.openWork(context, item),
      onLongPress: () => showWorkActions(context, item),
      child: SelectionContainer.disabled(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.page,
            vertical: Gap.m,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ContentTranslation(
                text: item.title,
                source: item.source,
                builder: (text) =>
                    Text(text, style: ParkText.serif(context.text.titleMedium)),
              ),
              if (item.authors.isNotEmpty) ...[
                const SizedBox(height: Gap.xs),
                Text(
                  '${tr('作者')}：${item.authors.join('、')}',
                  style: context.text.bodySmall,
                ),
              ],
              if (item.subtitle.isNotEmpty && item.subtitle != item.title) ...[
                const SizedBox(height: Gap.s),
                ContentTranslation(
                  text: item.subtitle,
                  source: item.source,
                  builder: (text) => Text(text, style: context.text.bodyMedium),
                ),
              ],
              if (showSource ||
                  item.editions.isNotEmpty ||
                  item.category.isNotEmpty ||
                  item.uploaded.isNotEmpty ||
                  item.tags.isNotEmpty) ...[
                const SizedBox(height: Gap.s),
                Wrap(
                  spacing: Gap.s,
                  runSpacing: Gap.xs,
                  children: [
                    if (showSource) SourceAvatar(item.source, size: 20),
                    if (item.editions.isNotEmpty)
                      Text(
                        workEditionLabel(item),
                        style: context.text.bodySmall,
                      ),
                    if (item.uploaded.isNotEmpty)
                      Text(item.uploaded, style: context.text.bodySmall),
                    if (item.category.isNotEmpty)
                      Text(item.category, style: context.text.bodySmall),
                    for (final tag
                        in item.tags
                            .where((tag) => tag != item.category)
                            .take(4))
                      Text(tag, style: context.text.bodySmall),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
