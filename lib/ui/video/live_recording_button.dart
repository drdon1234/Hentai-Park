import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../library/live_recordings.dart';
import '../theme.dart';
import '../widgets/common.dart';

class LiveRecordingButton extends StatelessWidget {
  const LiveRecordingButton({super.key, required this.item, this.color});
  final WorkItem item;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final recordings = LiveRecordings.instance;
    return ListenableBuilder(
      listenable: recordings,
      builder: (context, _) {
        final task = recordings.activeFor(item.uid);
        final stopping = task?.status == RecordingStatus.stopping;
        return IconButton(
          tooltip: tr(
            task == null
                ? '开始录制'
                : stopping
                ? '正在结束录制'
                : '停止录制',
          ),
          color: task == null ? color : context.colors.error,
          icon: Icon(
            task == null
                ? Icons.fiber_manual_record_outlined
                : Icons.stop_circle_outlined,
          ),
          onPressed: stopping
              ? null
              : () async {
                  try {
                    if (task != null) {
                      await recordings.stop(task);
                    } else {
                      await recordings.start(item);
                      if (context.mounted) context.toast(tr('已开始录制，可在下载页管理'));
                    }
                  } catch (error) {
                    if (context.mounted) {
                      context.toast(error.asSourceError.friendly);
                    }
                  }
                },
        );
      },
    );
  }
}
