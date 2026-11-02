import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../library/downloads.dart';
import '../kit/tokens.dart';
import '../theme.dart';

Color _progressColor(BuildContext context, DownloadStatus status) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (status) {
    DownloadStatus.running => DownloadPalette.running(dark),
    DownloadStatus.paused => DownloadPalette.paused(dark),
    DownloadStatus.done => DownloadPalette.done(dark),
    DownloadStatus.failed => context.colors.error,
    DownloadStatus.queued => context.colors.onSurfaceVariant,
  };
}

/// 只在封面边缘描绘进度，画面中央不放遮罩、底色或文字。
class DownloadCoverProgress extends StatefulWidget {
  const DownloadCoverProgress({
    super.key,
    required this.status,
    required this.label,
    required this.child,
    this.progress,
  });

  final DownloadStatus status;
  final String label;
  final Widget child;
  final double? progress;

  @override
  State<DownloadCoverProgress> createState() => _DownloadCoverProgressState();
}

class _DownloadCoverProgressState extends State<DownloadCoverProgress>
    with SingleTickerProviderStateMixin {
  late final _phase = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );
  bool _reducedMotion = false;
  bool get _indeterminate =>
      widget.status == DownloadStatus.running && widget.progress == null;

  void _syncAnimation() {
    if (widget.status == DownloadStatus.running && !_reducedMotion) {
      if (!_phase.isAnimating) _phase.repeat();
    } else {
      _phase.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    _syncAnimation();
  }

  @override
  void didUpdateWidget(DownloadCoverProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  @override
  void dispose() {
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    child: AnimatedBuilder(
      animation: _phase,
      child: widget.child,
      builder: (context, child) => CustomPaint(
        foregroundPainter: _CoverProgressPainter(
          progress: widget.status == DownloadStatus.done
              ? 1
              : widget.progress?.clamp(0.0, 1.0),
          phase: _phase.value,
          indeterminate: _indeterminate,
          wave: widget.status == DownloadStatus.running && !_reducedMotion,
          color: _progressColor(context, widget.status),
          track:
              widget.status == DownloadStatus.paused ||
                  widget.status == DownloadStatus.failed
              ? _progressColor(context, widget.status).withValues(alpha: .4)
              : context.colors.outlineVariant,
        ),
        child: child,
      ),
    ),
  );
}

class _CoverProgressPainter extends CustomPainter {
  const _CoverProgressPainter({
    required this.progress,
    required this.phase,
    required this.indeterminate,
    required this.wave,
    required this.color,
    required this.track,
  });

  final double? progress;
  final double phase;
  final bool indeterminate, wave;
  final Color color, track;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = (Offset.zero & size).deflate(.75);
    final radius = math.min(Radii.sm - .75, rect.shortestSide / 2);
    final path = Path()
      ..moveTo(rect.center.dx, rect.top)
      ..lineTo(rect.right - radius, rect.top)
      ..arcToPoint(
        Offset(rect.right, rect.top + radius),
        radius: Radius.circular(radius),
      )
      ..lineTo(rect.right, rect.bottom - radius)
      ..arcToPoint(
        Offset(rect.right - radius, rect.bottom),
        radius: Radius.circular(radius),
      )
      ..lineTo(rect.left + radius, rect.bottom)
      ..arcToPoint(
        Offset(rect.left, rect.bottom - radius),
        radius: Radius.circular(radius),
      )
      ..lineTo(rect.left, rect.top + radius)
      ..arcToPoint(
        Offset(rect.left + radius, rect.top),
        radius: Radius.circular(radius),
      )
      ..close();
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = track;
    canvas.drawPath(path, paint);
    paint.color = color;
    if (wave) {
      paint.shader = SweepGradient(
        colors: [
          color.withValues(alpha: .45),
          color,
          color.withValues(alpha: .45),
        ],
        transform: GradientRotation(phase * math.pi * 2),
      ).createShader(rect);
    }
    final metric = path.computeMetrics().first;
    if (indeterminate) {
      final start = phase * metric.length;
      final end = start + metric.length * .18;
      canvas.drawPath(
        metric.extractPath(start, math.min(end, metric.length)),
        paint,
      );
      if (end > metric.length) {
        canvas.drawPath(metric.extractPath(0, end - metric.length), paint);
      }
    } else if (progress != null) {
      canvas.drawPath(metric.extractPath(0, metric.length * progress!), paint);
    }
  }

  @override
  bool shouldRepaint(_CoverProgressPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      phase != oldDelegate.phase ||
      indeterminate != oldDelegate.indeterminate ||
      wave != oldDelegate.wave ||
      color != oldDelegate.color ||
      track != oldDelegate.track;
}

/// 列表横向进度：暂停后冻结，未知总量仅在下载中运动。
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
      color: _progressColor(context, status),
      backgroundColor: context.colors.surfaceContainerHighest,
    );
  }
}
