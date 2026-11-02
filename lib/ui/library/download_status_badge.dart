import 'package:flutter/material.dart';

import '../../library/downloads.dart';
import '../kit/tokens.dart';
import '../theme.dart';

/// 下载封面上的紧凑状态；只有正在准备的任务使用不确定进度。
class DownloadStatusBadge extends StatelessWidget {
  const DownloadStatusBadge({
    super.key,
    required this.status,
    required this.label,
    this.progress,
  });

  final DownloadStatus status;
  final String label;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final running = status == DownloadStatus.running;
    final paused = status == DownloadStatus.paused;
    final value = progress?.clamp(0.0, 1.0);
    final percentage = value == null ? null : '${(value * 100).round()}%';
    final text = (running || paused) && percentage != null ? percentage : label;
    final description = percentage == null ? label : '$label · $percentage';
    final color = status == DownloadStatus.failed
        ? colors.error
        : running
        ? colors.primary
        : colors.onSurfaceVariant;
    final icon = switch (status) {
      DownloadStatus.running => Icons.arrow_downward_rounded,
      DownloadStatus.paused => Icons.pause_rounded,
      DownloadStatus.queued => Icons.schedule_rounded,
      DownloadStatus.failed => Icons.error_outline_rounded,
      DownloadStatus.done => Icons.check_rounded,
    };
    return Tooltip(
      message: description,
      excludeFromSemantics: true,
      child: Semantics(
        label: description,
        excludeSemantics: true,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 120),
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.s,
            vertical: Gap.xs,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: Radii.small,
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: Gap.xs),
                  Flexible(
                    child: Text(
                      text,
                      style: context.text.labelSmall?.copyWith(color: color),
                    ),
                  ),
                ],
              ),
              if (running || paused && value != null) ...[
                const SizedBox(height: Gap.xs),
                DownloadProgressLine(status: status, progress: value),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 列表和封面状态共用横向进度：暂停后冻结，未知总量仅在下载中运动。
class DownloadProgressLine extends StatelessWidget {
  const DownloadProgressLine({super.key, required this.status, this.progress});

  final DownloadStatus status;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    if (status != DownloadStatus.running &&
        (status != DownloadStatus.paused || progress == null)) {
      return const SizedBox.shrink();
    }
    return LinearProgressIndicator(
      value:
          progress?.clamp(0.0, 1.0) ??
          (MediaQuery.disableAnimationsOf(context) ? 0 : null),
      minHeight: 3,
      borderRadius: Radii.tiny,
      color: status == DownloadStatus.running
          ? context.colors.primary
          : context.colors.onSurfaceVariant,
      backgroundColor: context.colors.surfaceContainerHighest,
    );
  }
}
