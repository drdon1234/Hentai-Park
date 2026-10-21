import 'package:flutter/material.dart';

import '../../core/content_scope.dart';
import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../core/tag_blocklist.dart';
import '../../engine/source_manager.dart';
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = ((constraints.maxWidth - Gap.page * 2) * 0.64).clamp(
          160.0,
          224.0,
        );
        final height = recent.fold(116.0, (height, entry) {
          final extent = _ContinueCard(entry: entry).heightFor(context, width);
          return extent > height ? extent : height;
        });
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
              height: height,
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
      },
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.entry});
  final HistoryEntry entry;

  static const _coverWidth = 48.0;

  String get _resumeLabel {
    final label = kindOf(entry.item) == MediaKind.video
        ? tr('继续播放')
        : tr('继续阅读');
    if (entry.position != null) {
      return '$label · ${entry.position! ~/ 60}:${(entry.position! % 60).toString().padLeft(2, '0')}';
    }
    return entry.pageCount > 0
        ? '$label · ${(entry.progress * 100).round()}%'
        : label;
  }

  String get _sourceName {
    final source = entry.item.source;
    if (source == 'local') return tr('本地导入');
    final name = SourceManager.instance.manifest(source)?.name;
    return name != null && name.trim().isNotEmpty ? name : source;
  }

  // 横向列表需要确定高度；逐种字号测量以兼容系统非线性字体缩放，站点全名不截断。
  double heightFor(BuildContext context, double width) {
    final textWidth = width - _coverWidth - Gap.s * 3;
    double textHeight(String text, TextStyle? style, {int? maxLines}) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        maxLines: maxLines,
        ellipsis: maxLines == null ? null : '…',
      )..layout(maxWidth: textWidth);
      final height = painter.height.ceilToDouble();
      painter.dispose();
      return height;
    }

    return Gap.s * 2 +
        textHeight(
          entry.item.title,
          ParkText.serif(context.text.titleSmall),
          maxLines: 2,
        ) +
        Gap.xs +
        textHeight(_sourceName, context.text.labelSmall) +
        (entry.chapterTitle?.isNotEmpty == true
            ? Gap.xs +
                  textHeight(
                    entry.chapterTitle!,
                    context.text.bodySmall,
                    maxLines: 1,
                  )
            : 0) +
        Gap.s +
        (entry.progress > 0 ? 3 + Gap.xs : 0) +
        textHeight(_resumeLabel, context.text.labelSmall, maxLines: 1);
  }

  @override
  Widget build(BuildContext context) {
    final item = entry.item;
    return Material(
      color: context.colors.surfaceContainer,
      borderRadius: Radii.medium,
      clipBehavior: Clip.antiAlias,
      child: ActionInkWell(
        onLongPress: () => showWorkActions(context, item),
        onTap: () => entry.position != null || entry.pageCount > 0
            ? Nav.openChapter(context, item, entry.chapterId, page: entry.page)
            : Nav.openWork(context, item),
        child: Padding(
          padding: const EdgeInsets.all(Gap.s),
          child: Row(
            children: [
              SizedBox(
                width: _coverWidth,
                child: ClipRRect(
                  borderRadius: Radii.small,
                  child: CoverImage(
                    url: item.cover,
                    sourceBlurred: item.json['coverBlurred'] == true,
                    source: item.source,
                    title: item.title,
                  ),
                ),
              ),
              const SizedBox(width: Gap.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ParkText.serif(context.text.titleSmall),
                    ),
                    const SizedBox(height: Gap.xs),
                    Text(
                      _sourceName,
                      style: context.text.labelSmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                    if (entry.chapterTitle?.isNotEmpty == true) ...[
                      const SizedBox(height: Gap.xs),
                      Text(
                        entry.chapterTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: Gap.s),
                    if (entry.progress > 0) ...[
                      LinearProgressIndicator(
                        value: entry.progress,
                        minHeight: 3,
                      ),
                      const SizedBox(height: Gap.xs),
                    ],
                    Text(
                      _resumeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelSmall?.copyWith(
                        color: context.colors.primary,
                      ),
                    ),
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
