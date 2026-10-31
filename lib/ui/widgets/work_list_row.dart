import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
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
      if (item.category.isNotEmpty) item.category,
      if (item.language.isNotEmpty) item.language,
      if (item.pages != null && item.pages! > 0)
        tr('{value0} 页', {'value0': item.pages}),
      if (item.duration.isNotEmpty) item.duration,
      if (item.rating != null)
        tr('评分 {rating}', {'rating': item.rating!.toStringAsFixed(1)}),
      if (item.views != null)
        tr('{count} 次观看', {'count': formatCount(item.views)}),
      if (item.badge.isNotEmpty) item.badge,
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
                    if (item.subtitle.isNotEmpty &&
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
                    if (item.tags.isNotEmpty) ...[
                      const SizedBox(height: Gap.xs),
                      Wrap(
                        spacing: Gap.s,
                        runSpacing: Gap.xs,
                        children: [
                          for (final tag in item.tags.take(8))
                            ContentTranslation(
                              text: tag,
                              source: item.source,
                              tag: true,
                              builder: (text) => Text(
                                text,
                                style: context.text.labelSmall?.copyWith(
                                  color: context.colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
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
