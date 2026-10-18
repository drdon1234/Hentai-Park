import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../engine/source_manager.dart';
import '../../library/downloads.dart';
import '../../library/library.dart';
import '../kit/kit.dart';
import '../library/favorite_actions.dart';
import 'detail_actions.dart';

/// What the detail page's primary action does for this kind of work.
enum DetailKind { reading, novel, video, game, external }

/// One accent action (continue / read / play); favorite, download and more stay secondary.
class DetailActionBar extends StatelessWidget {
  const DetailActionBar({
    super.key,
    required this.item,
    required this.detail,
    required this.kind,
    required this.onPrimary,
    required this.onDownload,
    required this.onMore,
  });
  final WorkItem item;
  final WorkDetail? detail;
  final DetailKind kind;

  /// Null while the primary action cannot run (still loading, nothing to open).
  final VoidCallback? onPrimary;
  final VoidCallback onDownload;
  final VoidCallback onMore;

  bool get _empty =>
      detail?.hasNoChapters == true &&
      kind != DetailKind.video &&
      kind != DetailKind.game;

  @override
  Widget build(BuildContext context) {
    final fav = Library.instance.isFavorite(item.uid);
    final dl = DownloadManager.instance.task(item.uid);
    final downloads =
        kind != DetailKind.external &&
        kind != DetailKind.game &&
        SourceManager.instance.manifest(item.source)?.usesWebVideo != true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.xs),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: detail == null || _empty ? null : onPrimary,
              icon: Icon(switch (kind) {
                DetailKind.game => Icons.sports_esports_outlined,
                DetailKind.external => Icons.open_in_browser_rounded,
                DetailKind.video => Icons.play_arrow_rounded,
                DetailKind.reading ||
                DetailKind.novel => Icons.auto_stories_outlined,
              }),
              label: SelectionContainer.disabled(
                child: Text(
                  _empty ? tr('暂无章节') : _primaryLabel(),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          const SizedBox(width: Gap.s),
          DetailSecondaryButton(
            icon: fav ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            tooltip: fav ? tr('取消应用内收藏') : tr('应用内收藏'),
            active: fav,
            onPressed: () => toggleFavorite(context, item),
            onLongPress: fav
                ? () => editFavoriteCategories(context, item.uid)
                : null,
          ),
          if (downloads) ...[
            const SizedBox(width: Gap.s),
            DetailSecondaryButton(
              icon: dl == null
                  ? Icons.download_outlined
                  : (dl.status == DownloadStatus.done
                        ? Icons.download_done_rounded
                        : Icons.downloading_rounded),
              tooltip: dl == null ? tr('下载') : tr('移除下载项'),
              active: dl != null,
              onPressed: dl == null && (detail == null || _empty)
                  ? null
                  : onDownload,
            ),
          ],
          const SizedBox(width: Gap.s),
          DetailSecondaryButton(
            icon: Icons.more_horiz_rounded,
            tooltip: tr('更多'),
            onPressed: detail == null ? null : onMore,
          ),
        ],
      ),
    );
  }

  String _primaryLabel() {
    final h = Library.instance.historyOf(item.uid);
    switch (kind) {
      case DetailKind.game:
        return tr('查看游戏资源');
      case DetailKind.external:
        return tr('打开原站');
      case DetailKind.video:
        final resumed = h?.position != null && h!.position! > 5;
        return resumed ? tr('继续播放') : tr('立即播放');
      case DetailKind.novel || DetailKind.reading:
        if (h == null || h.pageCount <= 0) return tr('开始阅读');
        if (kind == DetailKind.novel) {
          return tr('继续阅读 · {percent}%', {
            'percent': ((h.page / (h.pageCount - 1).clamp(1, 1 << 31)) * 100)
                .clamp(0, 100)
                .round(),
          });
        }
        return tr('继续 {chapter}{page}/{total}', {
          'chapter': h.chapterTitle != null && detail?.chapters != null
              ? '${h.chapterTitle} · '
              : '',
          'page': h.page + 1,
          'total': h.pageCount,
        });
    }
  }
}
