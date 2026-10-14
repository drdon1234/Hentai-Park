import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../engine/source_manager.dart';
import '../../library/downloads.dart';
import '../kit/kit.dart';
import '../theme.dart';
import '../widgets/error_view.dart';
import 'detail_sections.dart';

/// Download from the detail page: picks chapters or episodes when there are several, and
/// a quality for videos, then queues the download.
Future<void> downloadWork(
  BuildContext context,
  WorkDetail detail,
  WorkItem item, {
  required bool isVideo,
}) async {
  if (isVideo) {
    var episodes = detail.videoEpisodes;
    if (episodes.length > 1) {
      final picked = await showModalBottomSheet<List<Chapter>>(
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
    final picked = await showModalBottomSheet<List<Chapter>>(
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
  if (episodes.isEmpty) return;
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
  final picked = await showModalBottomSheet<VideoSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text(tr('选择下载清晰度'), style: ctx.text.titleMedium)),
          for (final s in sources)
            ListTile(
              leading: const Icon(Icons.high_quality_outlined),
              title: Text(s.label),
              trailing: s.preferred ? Tag(tr('推荐')) : null,
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
