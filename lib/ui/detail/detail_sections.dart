import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../library/downloads.dart';
import '../../library/library.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/source_network_hint.dart';

/// One chapter or episode as a hairline row: title, progress and whether it is downloaded.
class ChapterRow extends StatelessWidget {
  const ChapterRow({
    super.key,
    required this.chapter,
    required this.uid,
    required this.isVideo,
    required this.isNovel,
    required this.current,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });
  final Chapter chapter;
  final String uid;
  final bool isVideo;
  final bool isNovel;
  final bool current;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = Library.instance.chapterState(uid, chapter.id);
    final read = state?.read == true;
    final downloaded = DownloadManager.instance.isChapterDownloaded(
      uid,
      chapter.id,
    );
    String? progress;
    if (isVideo && state != null && state.position > 0) {
      progress =
          '${state.position ~/ 60}:${(state.position % 60).toString().padLeft(2, '0')}';
    } else if (!isVideo &&
        !read &&
        state != null &&
        state.lastPage > 0 &&
        state.pageCount > 0) {
      progress = isNovel
          ? '${((state.lastPage / (state.pageCount - 1).clamp(1, 1 << 31)) * 100).clamp(0, 100).round()}%'
          : '${state.lastPage + 1}/${state.pageCount}';
    }
    return Semantics(
      selected: selected,
      label: [
        chapter.title,
        if (current) tr('上次看到这里'),
        if (read) tr('已读'),
        ?progress,
        if (downloaded) tr('已下载'),
      ].join('，'),
      onTap: onTap,
      onLongPress: onLongPress,
      excludeSemantics: true,
      child: Material(
        color: selected ? c.secondaryContainer : Colors.transparent,
        child: ActionInkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: SelectionContainer.disabled(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.page,
                  vertical: Gap.s,
                ),
                child: Row(
                  children: [
                    if (current)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: Gap.s),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          size: 18,
                          color: c.primary,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        chapter.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodyMedium?.copyWith(
                          fontWeight: current ? FontWeight.w600 : null,
                          color: read && !current
                              ? c.onSurfaceVariant.withValues(alpha: .7)
                              : c.onSurface,
                        ),
                      ),
                    ),
                    if (progress != null) ...[
                      const SizedBox(width: Gap.s),
                      Text(
                        progress,
                        style: context.text.labelSmall?.copyWith(
                          color: c.primary,
                        ),
                      ),
                    ],
                    if (downloaded) ...[
                      const SizedBox(width: Gap.s),
                      Icon(
                        Icons.download_done_rounded,
                        size: 16,
                        color: c.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Actions for selected chapters, shown in place of the chapter header.
class ChapterSelectionBar extends StatelessWidget {
  const ChapterSelectionBar({
    super.key,
    required this.count,
    required this.isVideo,
    required this.onClear,
    required this.onSelectAll,
    required this.onDownload,
    required this.onMarkRead,
    this.allowDownload = true,
    this.onMarkPreviousRead,
  });
  final int count;
  final bool isVideo;
  final VoidCallback onClear;
  final VoidCallback onSelectAll;
  final VoidCallback onDownload;
  final bool allowDownload;
  final ValueChanged<bool> onMarkRead;
  final VoidCallback? onMarkPreviousRead;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Gap.s, Gap.m, Gap.s, Gap.xs),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: tr('取消选择'),
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded),
            ),
            Text(
              tr('已选 {count}', {'count': count}),
              style: context.text.titleSmall,
            ),
            const Spacer(),
            TextButton(
              onPressed: onSelectAll,
              child: SelectionContainer.disabled(child: Text(tr('全选'))),
            ),
            if (allowDownload)
              TextButton(
                onPressed: onDownload,
                child: SelectionContainer.disabled(child: Text(tr('下载'))),
              ),
          ],
        ),
        if (!isVideo)
          Wrap(
            spacing: Gap.xs,
            children: [
              TextButton(
                onPressed: () => onMarkRead(true),
                child: SelectionContainer.disabled(child: Text(tr('标为已读'))),
              ),
              TextButton(
                onPressed: () => onMarkRead(false),
                child: SelectionContainer.disabled(child: Text(tr('标为未读'))),
              ),
              if (onMarkPreviousRead != null)
                TextButton(
                  onPressed: onMarkPreviousRead,
                  child: SelectionContainer.disabled(
                    child: Text(tr('之前的章节标为已读')),
                  ),
                ),
            ],
          ),
      ],
    ),
  );
}

class DetailBodySkeleton extends StatelessWidget {
  const DetailBodySkeleton({super.key, required this.source});
  final String source;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(Gap.page),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LoadingIndicator(padding: EdgeInsets.only(bottom: Gap.l)),
        SourceNetworkHint(source: source),
        const Skeleton(height: 14, radius: 4),
        const SizedBox(height: Gap.s),
        const Skeleton(height: 14, width: 220, radius: 4),
        const SizedBox(height: Gap.xl),
        const Wrap(
          spacing: Gap.s,
          runSpacing: Gap.s,
          children: [
            Skeleton(width: 64, height: 28),
            Skeleton(width: 90, height: 28),
            Skeleton(width: 54, height: 28),
            Skeleton(width: 80, height: 28),
            Skeleton(width: 70, height: 28),
          ],
        ),
      ],
    ),
  );
}

/// Bottom sheet for choosing chapters or episodes to download.
class ChapterPicker extends StatefulWidget {
  const ChapterPicker({
    super.key,
    required this.chapters,
    this.isVideo = false,
    this.completed = const {},
  });
  final List<Chapter> chapters;
  final bool isVideo;
  final Set<String> completed;

  @override
  State<ChapterPicker> createState() => _ChapterPickerState();
}

class _ChapterPickerState extends State<ChapterPicker> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final all = _selected.length == widget.chapters.length;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (context, scroll) => Column(
        children: [
          ListTile(
            title: SelectionContainer.disabled(
              child: Text(
                tr(widget.isVideo ? '选择要下载的分集（{count}）' : '选择要下载的章节（{count}）', {
                  'count': _selected.length,
                }),
                style: context.text.titleMedium,
              ),
            ),
            trailing: SelectionContainer.disabled(
              child: TextButton(
                onPressed: () => setState(
                  () => all
                      ? _selected.clear()
                      : _selected.addAll(widget.chapters.map((c) => c.id)),
                ),
                child: Text(all ? tr('全不选') : tr('全选')),
              ),
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: widget.chapters.length,
              itemBuilder: (_, i) {
                final ch = widget.chapters[i];
                return CheckboxListTile(
                  value: _selected.contains(ch.id),
                  title: SelectionContainer.disabled(child: Text(ch.title)),
                  subtitle: widget.completed.contains(ch.id)
                      ? SelectionContainer.disabled(child: Text(tr('已下载')))
                      : null,
                  onChanged: (v) => setState(
                    () => v == true
                        ? _selected.add(ch.id)
                        : _selected.remove(ch.id),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(Gap.page),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.pop(
                          context,
                          widget.chapters
                              .where((c) => _selected.contains(c.id))
                              .toList(),
                        ),
                  child: SelectionContainer.disabled(child: Text(tr('开始下载'))),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
