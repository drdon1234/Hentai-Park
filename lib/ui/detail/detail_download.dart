import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../engine/source_manager.dart';
import '../../library/downloads.dart';
import '../kit/adaptive_sheet.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/error_view.dart';
import 'detail_sections.dart';

/// 已有任务时确认移除并删除文件；否则选择章节、分集与清晰度后加入队列。
Future<void> downloadWork(
  BuildContext context,
  WorkDetail? detail,
  WorkItem item, {
  required bool isVideo,
}) async {
  if (SourceManager.instance.manifest(item.source)?.isLive == true) return;
  final manager = DownloadManager.instance;
  if (manager.hasRestoreFailure(item.uid)) {
    context.toast(tr('下载记录恢复失败，请前往下载页处理'));
    return;
  }
  final existing = manager.task(item.uid);
  if (existing != null) {
    final confirmed = await confirmAction(
      context,
      title: tr('移除下载项'),
      message: tr('从下载列表移除「{title}」并删除已下载内容？', {'title': item.title}),
      confirmLabel: tr('删除'),
      destructive: true,
    );
    if (!confirmed || !identical(manager.task(item.uid), existing)) return;
    try {
      await manager.delete(item.uid);
    } catch (error) {
      if (context.mounted) {
        context.toast(
          tr('操作失败：{value0}', {'value0': error.asSourceError.friendly}),
        );
      }
    }
    return;
  }
  if (detail == null) return;
  if (isVideo) {
    var episodes = detail.videoEpisodes;
    if (episodes.length > 1) {
      final picked = await showAdaptiveSheet<List<Chapter>>(
        context: context,
        isScrollControlled: true,
        builder: (_) => ChapterPicker(
          chapters: episodes,
          isVideo: true,
          completed: DownloadManager.instance.task(item.uid)?.completed ?? {},
        ),
      );
      if (picked == null || picked.isEmpty || !context.mounted) return;
      episodes = picked;
    }
    await downloadEpisodes(context, detail, item, episodes);
    return;
  }
  final chapters = detail.chapters;
  if (chapters != null && chapters.length > 1) {
    final picked = await showAdaptiveSheet<List<Chapter>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChapterPicker(chapters: chapters),
    );
    if (picked == null || picked.isEmpty || !context.mounted) return;
    DownloadManager.instance.enqueue(item, picked);
  } else if (detail.hasNoChapters) {
    context.toast(tr('暂无章节'));
    return;
  } else {
    final id = detail.chapterToOpen()?.id ?? detail.singleChapterId ?? '_';
    DownloadManager.instance.enqueue(item, [Chapter(id, tr('全本'))]);
  }
  if (context.mounted) context.toast(tr('已加入下载队列'));
}

/// Asks for a quality (from the first episode's sources) and queues [episodes].
Future<void> downloadEpisodes(
  BuildContext context,
  WorkDetail detail,
  WorkItem item,
  List<Chapter> episodes,
) async {
  if (SourceManager.instance.manifest(item.source)?.isLive == true) return;
  if (episodes.isEmpty) return;
  if (DownloadManager.instance.hasRestoreFailure(item.uid)) {
    context.toast(tr('下载记录恢复失败，请前往下载页处理'));
    return;
  }
  final sources = await guarded(
    context,
    detail.source,
    () => SourceManager.instance.videos(
      detail.source,
      detail.id,
      episodeId: episodes.first.id,
    ),
  );
  if (sources == null || !context.mounted) return;
  final picked = await showAdaptiveSheet<VideoSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: SelectionContainer.disabled(
              child: Text(tr('选择下载清晰度'), style: ctx.text.titleMedium),
            ),
          ),
          for (final s in sources)
            ListTile(
              leading: const Icon(Icons.high_quality_outlined),
              title: SelectionContainer.disabled(child: Text(s.label)),
              trailing: s.preferred
                  ? SelectionContainer.disabled(child: Tag(tr('推荐')))
                  : null,
              onTap: () => Navigator.pop(ctx, s),
            ),
        ],
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  DownloadManager.instance.enqueueVideo(
    item,
    episodes,
    quality: picked.quality,
  );
  context.toast(tr('已加入下载队列'));
}
