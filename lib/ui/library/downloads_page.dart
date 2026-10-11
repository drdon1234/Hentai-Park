import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../core/settings.dart';
import '../../library/cbz.dart';
import '../../library/downloads.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  Future<void> _import(BuildContext context) async {
    final files = await FilePicker.pickFiles(dialogTitle: '导入 CBZ / ZIP', type: FileType.custom, allowedExtensions: const ['cbz', 'zip']);
    if (files.isEmpty || !context.mounted) return;
    var ok = 0;
    final errors = <String>[];
    for (final f in files) {
      try {
        final task = await Cbz.importArchive(f.name, await f.xFile.readAsBytes(), root: DownloadManager.instance.root);
        DownloadManager.instance.addCompleted(task);
        ok++;
      } catch (e) {
        errors.add('${f.name}：${e is FormatException ? e.message : e}');
      }
    }
    if (!context.mounted) return;
    context.toast(['已导入 $ok 个文件', ...errors].join('\n'));
  }

  @override
  Widget build(BuildContext context) {
    final dm = DownloadManager.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载'),
        actions: [
          IconButton(tooltip: '全部暂停', icon: const Icon(Icons.pause_circle_outline_rounded), onPressed: dm.pauseAll),
          IconButton(tooltip: '全部继续', icon: const Icon(Icons.play_circle_outline_rounded), onPressed: dm.resumeAll),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _import(context),
        icon: const Icon(Icons.file_open_outlined),
        label: const Text('导入本地漫画'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([dm, AppSettings.instance]),
        builder: (context, _) {
          final tasks = dm.tasks;
          return Column(
            children: [
              if (!dm.networkAllowed)
                const MaterialBanner(
                  leading: Icon(Icons.wifi_off_rounded),
                  content: Text('已开启"仅在 Wi-Fi 下下载"，连接 Wi-Fi 后自动继续'),
                  actions: [SizedBox.shrink()],
                ),
              Expanded(
                child: tasks.isEmpty
                    ? const MessageView(
                        icon: Icons.download_for_offline_outlined,
                        title: '没有下载任务',
                        message: '在作品详情页点击下载按钮，下载后可离线阅读或观看\n也可以导入本地的 CBZ / ZIP 漫画',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                        itemCount: tasks.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 4),
                        itemBuilder: (context, i) => _TaskTile(task: tasks[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});
  final DownloadTask task;

  Future<void> _menu(BuildContext context) async {
    final t = task;
    final canExport = !t.isVideo && t.completed.isNotEmpty;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(t.item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
            if (t.chapters.length > 1) ListTile(leading: const Icon(Icons.list_rounded), title: const Text('管理章节'), onTap: () => Navigator.pop(ctx, 'chapters')),
            if (canExport) ListTile(leading: const Icon(Icons.archive_outlined), title: const Text('导出为 CBZ'), onTap: () => Navigator.pop(ctx, 'cbz')),
            if (t.isVideo && t.status == DownloadStatus.done)
              ListTile(leading: const Icon(Icons.ios_share_rounded), title: const Text('导出视频文件'), onTap: () => Navigator.pop(ctx, 'video')),
            ListTile(leading: const Icon(Icons.delete_outline_rounded), title: const Text('删除'), onTap: () => Navigator.pop(ctx, 'delete')),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'chapters':
        await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => _ChapterSheet(task: t));
      case 'cbz':
        await _exportCbz(context);
      case 'video':
        final file = await DownloadManager.instance.localVideo(t.item.source, t.item.id);
        if (file != null) await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
      case 'delete':
        await _confirmDelete(context);
    }
  }

  Future<void> _exportCbz(BuildContext context) async {
    final progress = ValueNotifier<String>('正在打包…');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 16),
            Expanded(
              child: ValueListenableBuilder(valueListenable: progress, builder: (_, v, _) => Text(v)),
            ),
          ],
        ),
      ),
    );
    final nav = Navigator.of(context, rootNavigator: true);
    try {
      final out = Directory(p.join(DownloadManager.instance.root.path, 'exports'));
      final files = await Cbz.exportTask(task, out, onProgress: (d, n) => progress.value = '正在打包 $d/$n…');
      nav.pop();
      if (!context.mounted) return;
      context.toast('已导出到 ${out.path}');
      await SharePlus.instance.share(ShareParams(files: [for (final f in files) XFile(f.path)]));
    } catch (e) {
      nav.pop();
      if (context.mounted) context.toast('导出失败：$e');
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除下载？'),
        content: Text(task.item.source == localSource ? '导入的本地文件会被删除。' : '已下载的文件也会一并删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) await DownloadManager.instance.delete(task.uid);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = task;
    final waitingWifi = t.status == DownloadStatus.queued && !DownloadManager.instance.networkAllowed;
    final (statusText, statusColor) = switch (t.status) {
      _ when waitingWifi => ('等待 Wi-Fi', c.onSurfaceVariant),
      DownloadStatus.queued => ('等待中', c.onSurfaceVariant),
      DownloadStatus.running => (t.total > 0 ? (t.isVideo ? '${t.done}% · ${formatBytes(t.bytes)}' : '${t.done}/${t.total} 页') : '准备中…', c.primary),
      DownloadStatus.paused => ('已暂停 ${t.total > 0 ? '${t.done}/${t.total}' : ''}', c.onSurfaceVariant),
      DownloadStatus.done => (t.item.source == localSource ? '本地导入${t.bytes > 0 ? ' · ${formatBytes(t.bytes)}' : ''}' : '已完成${t.bytes > 0 ? ' · ${formatBytes(t.bytes)}' : ''}', Colors.green),
      DownloadStatus.failed => ('失败：${t.error ?? ''}', c.error),
    };
    return Card(
      child: InkWell(
        onTap: () => Nav.openWork(context, t.item),
        onLongPress: () => _menu(context),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                height: 78,
                child: CoverImage(source: t.item.source, url: t.item.cover, radius: 8),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
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
                            style: context.text.labelMedium?.copyWith(color: statusColor),
                          ),
                        ),
                        if (t.chapters.length > 1) Text('${t.completed.length}/${t.chapters.length} 章', style: context.text.labelSmall),
                      ],
                    ),
                    if (t.status == DownloadStatus.running || t.status == DownloadStatus.paused) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: t.total > 0 ? t.progress : null, minHeight: 4, backgroundColor: c.surfaceContainerHighest),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              if (t.status == DownloadStatus.running)
                IconButton(tooltip: '暂停', icon: const Icon(Icons.pause_rounded), onPressed: () => DownloadManager.instance.pause(t.uid))
              else if (t.status == DownloadStatus.paused || t.status == DownloadStatus.failed)
                IconButton(tooltip: '继续', icon: const Icon(Icons.play_arrow_rounded), onPressed: () => DownloadManager.instance.resume(t.uid)),
              IconButton(tooltip: '更多', icon: const Icon(Icons.more_vert_rounded), onPressed: () => _menu(context)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChapterSheet extends StatefulWidget {
  const _ChapterSheet({required this.task});
  final DownloadTask task;

  @override
  State<_ChapterSheet> createState() => _ChapterSheetState();
}

class _ChapterSheetState extends State<_ChapterSheet> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('下载的章节', style: TextStyle(fontWeight: FontWeight.w700)),
              trailing: FilledButton.tonalIcon(
                onPressed: _selected.isEmpty
                    ? null
                    : () async {
                        await DownloadManager.instance.deleteChapters(t.uid, _selected.toList());
                        if (context.mounted) Navigator.pop(context);
                      },
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text('删除 ${_selected.length}'),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final ch in t.chapters)
                    CheckboxListTile(
                      value: _selected.contains(ch.id),
                      title: Text(ch.title),
                      subtitle: Text(t.completed.contains(ch.id) ? '已下载' : '未完成'),
                      onChanged: (v) => setState(() => v == true ? _selected.add(ch.id) : _selected.remove(ch.id)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
