import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/localization.dart';
import '../../library/exports.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/platform_share.dart';

/// 后台导出的进度与已导出的文件；文件可分享或删除。
class ExportsPage extends StatefulWidget {
  const ExportsPage({super.key});

  @override
  State<ExportsPage> createState() => _ExportsPageState();
}

class _ExportsPageState extends State<ExportsPage> {
  final _exports = ExportManager.instance;
  late Future<List<File>> _files = _exports.files();
  bool _wasBusy = ExportManager.instance.busy;

  @override
  void initState() {
    super.initState();
    _exports.addListener(_changed);
  }

  @override
  void dispose() {
    _exports.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    // 任务完成或删除文件后重新读取目录。
    setState(() {
      if (_wasBusy != _exports.busy || !_exports.busy) {
        _files = _exports.files();
      }
      _wasBusy = _exports.busy;
    });
  }

  String _format(ExportFormat format) => switch (format) {
    ExportFormat.pdf => 'PDF',
    ExportFormat.cbz => 'CBZ',
  };

  Widget _job(BuildContext context, ExportJob job) {
    final (subtitle, icon) = switch (job.status) {
      ExportStatus.queued => (tr('等待中'), Icons.schedule_rounded),
      ExportStatus.running => (
        job.total > 0
            ? tr('正在导出 {value0}/{value1}…', {
                'value0': job.done,
                'value1': job.total,
              })
            : tr('正在导出…'),
        Icons.sync_rounded,
      ),
      ExportStatus.done => (
        tr('已导出 {value0} 个文件', {'value0': job.files.length}),
        Icons.check_circle_outline_rounded,
      ),
      ExportStatus.failed => (
        tr('导出失败：{value0}', {'value0': job.error ?? ''}),
        Icons.error_outline_rounded,
      ),
    };
    final finished =
        job.status == ExportStatus.done || job.status == ExportStatus.failed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListRow(
          leading: Icon(icon),
          title: '${job.title} · ${_format(job.format)}',
          subtitle: subtitle,
          trailing: finished
              ? IconButton(
                  tooltip: tr('移除记录'),
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => _exports.dismiss(job),
                )
              : null,
        ),
        if (job.status == ExportStatus.running && job.total > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.page),
            child: LinearProgressIndicator(value: job.done / job.total),
          ),
      ],
    );
  }

  Future<void> _delete(BuildContext context, File file) async {
    final ok = await confirmAction(
      context,
      title: tr('删除导出文件？'),
      message: p.basename(file.path),
      confirmLabel: tr('删除'),
      destructive: true,
    );
    if (!ok) return;
    try {
      await _exports.delete(file);
    } catch (_) {
      if (context.mounted) context.toast(tr('删除失败，请重试'));
    }
  }

  Widget _file(BuildContext context, File file) {
    final stat = file.statSync();
    return ListRow(
      leading: Icon(switch (p.extension(file.path).toLowerCase()) {
        '.pdf' => Icons.picture_as_pdf_outlined,
        '.mp4' || '.m3u8' => Icons.movie_outlined,
        _ => Icons.folder_zip_outlined,
      }),
      title: p.basename(file.path),
      titleMaxLines: 2,
      subtitle: formatBytes(stat.size),
      onTap: () => shareContent(context, files: [XFile(file.path)]),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: tr('分享'),
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => shareContent(context, files: [XFile(file.path)]),
          ),
          IconButton(
            tooltip: tr('删除'),
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _delete(context, file),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PageHeader(title: tr('导出文件')),
      body: FutureBuilder<List<File>>(
        future: _files,
        builder: (context, snapshot) {
          final files = snapshot.data ?? const <File>[];
          final jobs = _exports.jobs;
          if (snapshot.connectionState != ConnectionState.done &&
              jobs.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (jobs.isEmpty && files.isEmpty) {
            return EmptyState(
              icon: Icons.folder_open_outlined,
              title: tr('还没有导出文件'),
              message: tr('在下载项的更多菜单中导出 PDF 或 CBZ'),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: Gap.xl),
            children: [
              if (jobs.isNotEmpty)
                RowGroup(
                  title: tr('导出任务'),
                  children: [for (final job in jobs) _job(context, job)],
                ),
              if (files.isNotEmpty)
                RowGroup(
                  title: tr('已导出'),
                  children: [for (final file in files) _file(context, file)],
                ),
              Padding(
                padding: const EdgeInsets.all(Gap.page),
                child: Text(
                  tr('文件位置：{value0}', {'value0': _exports.directory.path}),
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
