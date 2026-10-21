import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../library/downloads.dart' show localSource;
import '../../library/live_recordings.dart';
import '../nav.dart';
import '../theme.dart';
import '../video/video_controls.dart' show formatPlaybackTime;
import '../video/video_page.dart';
import '../widgets/common.dart';

class RecordingTile extends StatelessWidget {
  const RecordingTile({super.key, required this.task});
  final LiveRecording task;

  Future<void> _open(BuildContext context) async {
    try {
      final files = await task.volumes();
      if (files.isEmpty || !context.mounted) return;
      final index = files.length == 1
          ? 0
          : await showChoiceSheet<int>(
              context,
              title: tr('录制分卷'),
              options: List.generate(files.length, (i) => i),
              selected: 0,
              label: (index) => '${index + 1}',
            );
      if (index == null || !context.mounted) return;
      await Nav.push(
        context,
        VideoPage(
          work: WorkDetail({
            'id': '${task.id}:$index',
            'title': task.item.title,
            'mediaKind': 'video',
          }, localSource),
          localFile: files[index],
          recordHistory: false,
        ),
      );
    } catch (_) {
      if (context.mounted) context.toast(tr('无法读取录制文件'));
    }
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await confirmAction(
      context,
      title: tr('删除录制'),
      message: tr('删除这次录制及其全部文件？'),
      confirmLabel: tr('删除'),
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await LiveRecordings.instance.delete(task);
    } catch (_) {
      if (context.mounted) context.toast(tr('删除失败，请重试'));
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(
      task.active
          ? Icons.fiber_manual_record_rounded
          : Icons.video_file_outlined,
      color: task.active ? context.colors.error : null,
    ),
    title: Text(task.item.title),
    subtitle: Text(
      [
        tr(switch (task.status) {
          RecordingStatus.recording => '正在录制',
          RecordingStatus.stopping => '正在结束录制',
          RecordingStatus.finished => '录制已完成',
          RecordingStatus.interrupted => '录制已中断，已保存已有内容',
          RecordingStatus.failed => '录制失败，已保存已有内容',
        }),
        task.startedAt.toLocal().toString().split('.').first,
        '${formatPlaybackTime(Duration(seconds: task.seconds.toInt()))} · ${(task.bytes / 1024 / 1024).toStringAsFixed(1)} MB',
      ].join('\n'),
    ),
    isThreeLine: true,
    onTap: task.active || task.bytes == 0 ? null : () => _open(context),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (task.active)
          IconButton(
            tooltip: tr('停止录制'),
            icon: const Icon(Icons.stop_circle_outlined),
            onPressed: task.status == RecordingStatus.stopping
                ? null
                : () => LiveRecordings.instance.stop(task),
          )
        else
          IconButton(
            tooltip: tr('删除录制'),
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _delete(context),
          ),
      ],
    ),
  );
}
