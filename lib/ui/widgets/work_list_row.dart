import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../engine/source_manager.dart';
import '../nav.dart';
import '../short_video/short_video_sequence.dart';
import '../theme.dart';
import 'common.dart';
import 'content_translation.dart';
import 'cover_tile.dart';

/// 一行一部作品，封面旁展示源已提供的信息，不为缺失字段占位。
class WorkListRow extends StatelessWidget {
  const WorkListRow({super.key, required this.item, this.sequence});
  final WorkItem item;
  final ShortVideoSequence Function()? sequence;

  @override
  Widget build(BuildContext context) {
    final metadata = [
      ...workMetadata(item),
      if (item.duration.isNotEmpty) item.duration,
      if (item.badge.isNotEmpty && !workMetadata(item).contains(item.badge))
        item.badge,
    ];
    return SelectionContainer.disabled(
      child: ActionInkWell(
        onTap: () => Nav.openWork(context, item, sequence: sequence?.call()),
        onLongPress: () => showWorkActions(context, item),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.page,
            vertical: Gap.s,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 88,
                child: AspectRatio(
                  aspectRatio:
                      (item.coverAspect ??
                              (kindOf(item) == MediaKind.video ? 16 / 9 : .7))
                          .clamp(.5, 1.9),
                  child: CoverImage(
                    source: item.source,
                    url: item.cover,
                    title: item.title,
                  ),
                ),
              ),
              const SizedBox(width: Gap.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ContentTranslation(
                      text: item.title,
                      source: item.source,
                      builder: (text) => Text(
                        text,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: ParkText.serif(context.text.titleSmall),
                      ),
                    ),
                    if (item.authors.isNotEmpty) ...[
                      const SizedBox(height: Gap.xs),
                      Text(
                        item.authors.join(' · '),
                        style: context.text.bodySmall,
                      ),
                    ],
                    if (SourceManager.instance
                                .manifest(item.source)
                                ?.category !=
                            SourceCategory.doujin &&
                        item.subtitle.isNotEmpty &&
                        item.subtitle != item.title) ...[
                      const SizedBox(height: Gap.xs),
                      ContentTranslation(
                        text: item.subtitle,
                        source: item.source,
                        builder: (text) => Text(
                          text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                    if (metadata.isNotEmpty) ...[
                      const SizedBox(height: Gap.xs),
                      Text(
                        metadata.join(' · '),
                        style: context.text.labelSmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (item.uploaded.isNotEmpty) ...[
                      const SizedBox(height: Gap.xs),
                      Text(
                        item.uploaded,
                        style: context.text.labelSmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
