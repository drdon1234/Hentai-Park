import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../game/downloads.dart';
import '../../library/cbz.dart';
import '../../library/comic_pdf.dart';
import '../../library/downloads.dart';
import '../../video/offline_video_export.dart';
import '../game/game_resources.dart';
import '../kit/adaptive_sheet.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/platform_share.dart';

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  Future<void> _import(BuildContext context) async {
    final files = await FilePicker.pickFiles(
      dialogTitle: tr('导入 CBZ / ZIP'),
      type: FileType.custom,
      allowedExtensions: const ['cbz', 'zip'],
    );
    if (files.isEmpty || !context.mounted) return;
    var ok = 0;
    final errors = <String>[];
    for (final f in files) {
      try {
        final task = await Cbz.importArchive(
          f.name,
          await f.xFile.readAsBytes(),
          root: DownloadManager.instance.root,
        );
        DownloadManager.instance.addCompleted(task);
        ok++;
      } catch (e) {
        errors.add('${f.name}：${e is FormatException ? e.message : e}');
      }
    }
    if (!context.mounted) return;
    context.toast(
      [
        tr('已导入 {value0} 个文件', {'value0': ok}),
        ...errors,
      ].join('\n'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dm = DownloadManager.instance;
    final games = GameDownloadManager.instance;
    return Scaffold(
      appBar: PageHeader(
        title: tr('下载'),
        actions: [
          ListenableBuilder(
            listenable: Listenable.merge([dm, games]),
            builder: (context, _) {
              if (dm.tasks.isEmpty && games.tasks.isEmpty) {
                return const SizedBox.shrink();
              }
              return Row(
                children: [
                  TextButton(
                    onPressed: () {
                      dm.pauseAll();
                      for (final task in games.tasks) {
                        if (task.status == DownloadStatus.running ||
                            task.status == DownloadStatus.queued) {
                          games.cancel(task.key);
                        }
                      }
                    },
                    child: SelectionContainer.disabled(child: Text(tr('全部暂停'))),
                  ),
                  TextButton(
                    onPressed: () {
                      dm.resumeAll();
                      for (final task in games.tasks) {
                        if (task.status == DownloadStatus.paused ||
                            task.status == DownloadStatus.failed) {
                          games.retry(task.key);
                        }
                      }
                    },
                    child: SelectionContainer.disabled(child: Text(tr('全部继续'))),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _import(context),
        icon: const Icon(Icons.file_open_outlined),
        label: SelectionContainer.disabled(child: Text(tr('导入本地漫画'))),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([dm, games, AppSettings.instance]),
        builder: (context, _) {
          final tasks = dm.tasks;
          final gameTasks = games.tasks;
          final failures = dm.restoreFailures;
          return Column(
            children: [
              if (!dm.networkAllowed)
                MaterialBanner(
                  leading: const Icon(Icons.wifi_off_rounded),
                  content: Text(tr('已开启"仅在 Wi-Fi 下下载"，连接 Wi-Fi 后自动继续')),
                  actions: [const SizedBox.shrink()],
                ),
              Expanded(
                child: tasks.isEmpty && gameTasks.isEmpty && failures.isEmpty
                    ? EmptyState(
                        icon: Icons.download_for_offline_outlined,
                        title: tr('没有下载任务'),
                        message: tr(
                          '在作品详情页点击下载按钮，下载后可离线阅读或观看\n也可以导入本地的 CBZ / ZIP 漫画',
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount:
                            failures.length + gameTasks.length + tasks.length,
                        separatorBuilder: (_, _) => const Divider(
                          indent: Gap.page,
                          endIndent: Gap.page,
                        ),
                        itemBuilder: (context, i) {
                          if (i < failures.length) {
                            return _RestoreFailureTile(
                              uid: failures[i].uid,
                              source: failures[i].source,
                            );
                          }
                          i -= failures.length;
                          return i < gameTasks.length
                              ? GameDownloadTile(task: gameTasks[i])
                              : _TaskTile(task: tasks[i - gameTasks.length]);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RestoreFailureTile extends StatelessWidget {
  const _RestoreFailureTile({required this.uid, required this.source});
  final String uid, source;

  Future<void> _retry(BuildContext context) async {
    try {
      await DownloadManager.instance.retryRestore(uid);
    } catch (_) {
      if (context.mounted) context.toast(tr('下载记录恢复失败，请前往下载页处理'));
    }
  }

  Future<void> _remove(BuildContext context) async {
    final confirmed = await confirmAction(
      context,
      title: tr('移除损坏的下载记录？'),
      message: tr('只移除无法恢复的下载记录，保留本地文件。'),
      confirmLabel: tr('移除记录'),
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await DownloadManager.instance.removeRestoreFailure(uid);
    } catch (_) {
      if (context.mounted) context.toast(tr('删除失败，请重试'));
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(Gap.page),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('下载记录恢复失败'), style: context.text.titleMedium),
        const SizedBox(height: Gap.s),
        Text(source, style: context.text.bodyMedium),
        Text(tr('原始记录和本地文件已保留，可以重试或仅移除记录。')),
        Wrap(
          spacing: Gap.s,
          children: [
            TextButton(
              onPressed: () => _retry(context),
              child: SelectionContainer.disabled(child: Text(tr('重试'))),
            ),
            TextButton(
              onPressed: () => _remove(context),
              child: SelectionContainer.disabled(child: Text(tr('移除记录'))),
            ),
          ],
        ),
      ],
    ),
  );
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});
  final DownloadTask task;

  Future<void> _chapters(BuildContext context) async {
    final t = DownloadManager.instance.task(task.uid);
    if (!context.mounted || t == null) return;
    return showAdaptiveSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ChapterSheet(
        task: t,
        onOpen: (chapter) => Nav.openChapter(context, t.item, chapter.id),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final t = DownloadManager.instance.task(task.uid);
    if (!context.mounted || t == null) return;
    if (!t.isVideo) return Nav.openWork(context, t.item);
    if (t.chapters.length > 1) return _chapters(context);
    if (t.chapters.isNotEmpty && t.completed.contains(t.chapters.first.id)) {
      return Nav.openChapter(context, t.item, t.chapters.first.id);
    }
    return Nav.openWork(context, t.item);
  }

  Future<void> _menu(BuildContext context) async {
    final t = DownloadManager.instance.task(task.uid);
    if (!context.mounted || t == null) return;
    final canExport = !t.isVideo && !t.isNovel && t.completed.isNotEmpty;
    final action = await showAdaptiveSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: SelectionContainer.disabled(
                child: Text(
                  t.item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            if (t.chapters.length > 1)
              ListTile(
                leading: const Icon(Icons.list_rounded),
                title: SelectionContainer.disabled(
                  child: Text(tr(t.isVideo ? '管理分集' : '管理章节')),
                ),
                onTap: () => Navigator.pop(ctx, 'chapters'),
              ),
            if (canExport)
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: SelectionContainer.disabled(child: Text(tr('导出为 CBZ'))),
                onTap: () => Navigator.pop(ctx, 'cbz'),
              ),
            if (canExport)
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: SelectionContainer.disabled(child: Text(tr('导出为 PDF'))),
                subtitle: SelectionContainer.disabled(
                  child: Text(tr('按已完成章节导出，动图仅保留第一帧')),
                ),
                onTap: () => Navigator.pop(ctx, 'pdf'),
              ),
            if (t.isVideo &&
                t.chapters.length == 1 &&
                t.completed.contains(t.chapters.first.id))
              ListTile(
                leading: const Icon(Icons.ios_share_rounded),
                title: SelectionContainer.disabled(child: Text(tr('导出视频文件'))),
                onTap: () => Navigator.pop(ctx, 'video'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: SelectionContainer.disabled(child: Text(tr('删除'))),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'chapters':
        await _chapters(context);
      case 'cbz':
        await _exportImages(context);
      case 'pdf':
        await _exportImages(context, pdf: true);
      case 'video':
        final file = await DownloadManager.instance.localVideo(
          t.item.source,
          t.item.id,
          episodeId: t.chapters.first.id,
        );
        if (file != null && context.mounted) {
          final exported = await exportOfflineVideo(
            file,
            Directory(p.join(DownloadManager.instance.root.path, 'exports')),
          );
          if (!context.mounted) return;
          await shareContent(context, files: [XFile(exported.path)]);
        }
      case 'delete':
        await _confirmDelete(context);
    }
  }

  Future<void> _exportImages(BuildContext context, {bool pdf = false}) async {
    final progress = ValueNotifier<String>(tr('正在导出…'));
    final nav = Navigator.of(context, rootNavigator: true);
    final dialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ValueListenableBuilder(
                  valueListenable: progress,
                  builder: (_, v, _) => Text(v),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    var showingProgress = true;
    Future<void> closeProgress() async {
      if (!showingProgress) return;
      showingProgress = false;
      if (nav.mounted) nav.pop();
      await dialog;
    }

    try {
      final out = Directory(
        p.join(DownloadManager.instance.root.path, 'exports'),
      );
      void onProgress(int done, int total) => progress.value = tr(
        '正在导出 {value0}/{value1}…',
        {'value0': done, 'value1': total},
      );
      final export = pdf ? ComicPdf.exportTask : Cbz.exportTask;
      final files = await export(task, out, onProgress: onProgress);
      await closeProgress();
      if (!context.mounted) return;
      context.toast(tr('已导出到 {value0}', {'value0': out.path}));
      await shareContent(
        context,
        files: [for (final f in files) XFile(f.path)],
      );
    } catch (e) {
      await closeProgress();
      if (context.mounted) context.toast(tr('导出失败：{value0}', {'value0': e}));
    } finally {
      progress.dispose();
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await confirmAction(
      context,
      title: tr('删除下载？'),
      message: task.item.source == localSource
          ? tr('导入的本地文件会被删除。')
          : tr('已下载的文件也会一并删除。'),
      confirmLabel: tr('删除'),
      destructive: true,
    );
    if (!ok) return;
    try {
      await DownloadManager.instance.delete(task.uid);
    } catch (_) {
      if (context.mounted) context.toast(tr('删除失败，请重试'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = task;
    final waitingWifi =
        t.status == DownloadStatus.queued &&
        !DownloadManager.instance.networkAllowed;
    final (statusText, statusColor) = switch (t.status) {
      _ when waitingWifi => (tr('等待 Wi-Fi'), c.onSurfaceVariant),
      DownloadStatus.queued => (tr('等待中'), c.onSurfaceVariant),
      DownloadStatus.running => (
        t.total > 0
            ? (t.isVideo
                  ? '${(t.progress * 100).clamp(0, 100).round()}% · ${formatBytes(t.bytes)}'
                  : tr(
                      t.isNovel ? '{value0}/{value1} 章' : '{value0}/{value1} 页',
                      {'value0': t.done, 'value1': t.total},
                    ))
            : tr('准备中…'),
        c.primary,
      ),
      DownloadStatus.paused => (
        tr('已暂停 {value0}', {
          'value0': t.total > 0
              ? (t.isVideo
                    ? '${(t.progress * 100).clamp(0, 100).round()}%'
                    : '${t.done}/${t.total}')
              : '',
        }),
        c.onSurfaceVariant,
      ),
      DownloadStatus.done => (
        t.item.source == localSource
            ? tr('本地导入{value0}', {
                'value0': t.bytes > 0 ? ' · ${formatBytes(t.bytes)}' : '',
              })
            : tr('已完成{value0}', {
                'value0': t.bytes > 0 ? ' · ${formatBytes(t.bytes)}' : '',
              }),
        c.onSurfaceVariant,
      ),
      DownloadStatus.failed => (
        tr('失败：{value0}', {'value0': t.error ?? ''}),
        c.error,
      ),
    };
    return InkWell(
      onTap: () => _open(context),
      onLongPress: () => _menu(context),
      child: SelectionContainer.disabled(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.page, Gap.m, Gap.xs, Gap.m),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                height: 78,
                child: CoverImage(
                  source: t.item.source,
                  url: t.item.cover,
                  title: t.item.title,
                  mediaKind: t.isNovel ? MediaKind.novel : null,
                ),
              ),
              const SizedBox(width: Gap.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        SourceAvatar(t.item.source, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            statusText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelMedium?.copyWith(
                              color: statusColor,
                            ),
                          ),
                        ),
                        if (t.chapters.length > 1)
                          Text(
                            tr(
                              t.isVideo
                                  ? '{value0}/{value1} 集'
                                  : '{value0}/{value1} 章',
                              {
                                'value0': t.completed.length,
                                'value1': t.chapters.length,
                              },
                            ),
                            style: context.text.labelSmall,
                          ),
                      ],
                    ),
                    if (t.status == DownloadStatus.running ||
                        t.status == DownloadStatus.paused) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: const BorderRadius.all(
                          Radius.circular(2),
                        ),
                        child: LinearProgressIndicator(
                          value: t.total > 0 ? t.progress : null,
                          minHeight: 4,
                          backgroundColor: c.surfaceContainerHighest,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (t.status == DownloadStatus.running)
                IconButton(
                  tooltip: tr('暂停'),
                  icon: const Icon(Icons.pause_rounded),
                  onPressed: () => DownloadManager.instance.pause(t.uid),
                )
              else if (t.status == DownloadStatus.paused ||
                  t.status == DownloadStatus.failed)
                IconButton(
                  tooltip: tr('继续'),
                  icon: const Icon(Icons.play_arrow_rounded),
                  onPressed: () => DownloadManager.instance.resume(t.uid),
                ),
              IconButton(
                tooltip: tr('更多'),
                icon: const Icon(Icons.more_vert_rounded),
                onPressed: () => _menu(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChapterSheet extends StatefulWidget {
  const _ChapterSheet({required this.task, required this.onOpen});
  final DownloadTask task;
  final ValueChanged<Chapter> onOpen;

  @override
  State<_ChapterSheet> createState() => _ChapterSheetState();
}

class _ChapterSheetState extends State<_ChapterSheet> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    return ListenableBuilder(
      listenable: DownloadManager.instance,
      builder: (context, _) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: SelectionContainer.disabled(
                  child: Text(
                    tr(t.isVideo ? '下载的分集' : '下载的章节'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                trailing: SelectionContainer.disabled(
                  child: FilledButton.tonalIcon(
                    onPressed: _selected.isEmpty
                        ? null
                        : () async {
                            try {
                              await DownloadManager.instance.deleteChapters(
                                t.uid,
                                _selected.toList(),
                              );
                              if (context.mounted) Navigator.pop(context);
                            } catch (_) {
                              if (context.mounted) {
                                context.toast(tr('删除失败，请重试'));
                              }
                            }
                          },
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: Text(
                      tr('删除 {value0}', {'value0': _selected.length}),
                    ),
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final ch in t.chapters)
                      CheckboxListTile(
                        value: _selected.contains(ch.id),
                        title: SelectionContainer.disabled(
                          child: Text(ch.title),
                        ),
                        subtitle: SelectionContainer.disabled(
                          child: Text(
                            t.completed.contains(ch.id) ? tr('已下载') : tr('未完成'),
                          ),
                        ),
                        secondary: t.isVideo
                            ? SelectionContainer.disabled(
                                child: IconButton(
                                  tooltip: tr('播放'),
                                  icon: const Icon(
                                    Icons.play_circle_outline_rounded,
                                  ),
                                  onPressed: t.completed.contains(ch.id)
                                      ? () {
                                          Navigator.pop(context);
                                          widget.onOpen(ch);
                                        }
                                      : null,
                                ),
                              )
                            : null,
                        onChanged: (v) => setState(
                          () => v == true
                              ? _selected.add(ch.id)
                              : _selected.remove(ch.id),
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
