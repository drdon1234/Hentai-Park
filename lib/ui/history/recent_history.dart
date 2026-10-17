import 'package:flutter/material.dart';

import '../../core/content_scope.dart';
import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../core/tag_blocklist.dart';
import '../../library/library.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/cover_tile.dart';

/// 继续看: the most recent history in the selected scope as one horizontal row. Hidden when
/// there is nothing to continue.
class RecentHistory extends StatelessWidget {
  const RecentHistory({
    super.key,
    this.onOpenHistory,
    this.limit,
    this.scope = const ContentScope.all(),
  });
  final ContentScope scope;
  final VoidCallback? onOpenHistory;
  final int? limit;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppSettings.instance.watch(AppSettings.filterKeys),
    builder: (context, _) => _build(context),
  );
  Widget _build(BuildContext context) {
    final rules = TagBlocklist.current();
    final entries = Library.instance
        .history(scope: scope)
        .where((e) => rules.matchItem(e.item) == null)
        .toList();
    final recent = limit == null ? entries : entries.take(limit!).toList();
    if (recent.isEmpty) return const SizedBox.shrink();
    final width = (MediaQuery.sizeOf(context).width - Gap.page * 2).clamp(
      240.0,
      340.0,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          tr('继续看'),
          leading: const Icon(Icons.history_rounded),
          trailing: onOpenHistory == null
              ? null
              : TextButton(
                  onPressed: onOpenHistory,
                  child: SelectionContainer.disabled(child: Text(tr('全部'))),
                ),
        ),
        SizedBox(
          height:
              116 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Gap.page),
            itemCount: recent.length,
            separatorBuilder: (_, _) => const SizedBox(width: Gap.m),
            itemBuilder: (context, index) => SizedBox(
              width: width,
              child: _ContinueCard(entry: recent[index]),
            ),
          ),
        ),
      ],
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.entry});
  final HistoryEntry entry;
  @override
  Widget build(BuildContext context) {
    final item = entry.item;
    final video = kindOf(item) == MediaKind.video;
    final label = video ? tr('继续播放') : tr('继续阅读');
    return Material(
      color: context.colors.surfaceContainer,
      borderRadius: Radii.medium,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onLongPress: () => showWorkActions(context, item),
        onTap: () => entry.position != null || entry.pageCount > 0
            ? Nav.openChapter(context, item, entry.chapterId, page: entry.page)
            : Nav.openWork(context, item),
        child: Padding(
          padding: const EdgeInsets.all(Gap.s),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: ClipRRect(
                  borderRadius: Radii.small,
                  child: CoverImage(
                    url: item.cover,
                    source: item.source,
                    title: item.title,
                  ),
                ),
              ),
              const SizedBox(width: Gap.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleSmall,
                    ),
                    const SizedBox(height: Gap.xs),
                    if (entry.chapterTitle?.isNotEmpty == true)
                      Text(
                        entry.chapterTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall,
                      ),
                    const SizedBox(height: Gap.s),
                    if (entry.progress > 0)
                      LinearProgressIndicator(
                        value: entry.progress,
                        minHeight: 3,
                      ),
                    Text(
                      entry.position != null
                          ? '$label · ${entry.position! ~/ 60}:${(entry.position! % 60).toString().padLeft(2, '0')}'
                          : entry.pageCount > 0
                          ? '$label · ${(entry.progress * 100).round()}%'
                          : label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelSmall?.copyWith(
                        color: context.colors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Gap.s),
              const Icon(Icons.play_circle_outline_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
