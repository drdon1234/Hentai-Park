import 'package:flutter/material.dart';

/// 共享下载反馈：步骤未知时转圈，取得总量后显示计数和按钮外沿进度。
Future<T> showProgressOperation<T>(
  BuildContext context,
  String title,
  Future<T> Function(void Function(int completed, int total) report) action,
) async {
  final progress = ValueNotifier((completed: 0, total: 0));
  var closing = false;
  final future = Future<T>.sync(
    () => action((done, total) {
      progress.value = (completed: done, total: total);
    }),
  );
  future.ignore();
  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) {
        final route = ModalRoute.of(dialog)!;
        void close() {
          if (!closing && dialog.mounted && route.isActive) {
            closing = true;
            final navigator = Navigator.of(dialog);
            if (route.isCurrent) {
              navigator.pop();
            } else {
              navigator.removeRoute(route);
            }
          }
        }

        future.then(
          (_) => close(),
          onError: (Object _, StackTrace _) => close(),
        );
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text(title),
            content: ValueListenableBuilder(
              valueListenable: progress,
              builder: (context, value, _) {
                final fraction = value.total > 0
                    ? value.completed / value.total
                    : null;
                return ProgressOutline(
                  active: true,
                  value: fraction,
                  child: FilledButton.icon(
                    onPressed: null,
                    icon: ProgressRing(value: fraction),
                    label: Text(
                      value.total > 0
                          ? '${value.completed} / ${value.total}'
                          : title,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
    return await future;
  } finally {
    progress.dispose();
  }
}

/// 确定进度以完整一圈表示 100%，未知总量时保留不确定进度。
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, this.value, this.child});
  final double? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Semantics(
    value: value == null ? null : '${(value!.clamp(0, 1) * 100).round()}%',
    child: SizedBox.square(
      dimension: 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CircularProgressIndicator(
              value: value?.clamp(0, 1),
              strokeWidth: 2.5,
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest,
            ),
          ),
          ?child,
        ],
      ),
    ),
  );
}

/// 按钮外沿的进度描边，不改变点击区域和布局尺寸。
class ProgressOutline extends StatelessWidget {
  const ProgressOutline({
    super.key,
    required this.child,
    this.value,
    this.active = false,
  });
  final Widget child;
  final double? value;
  final bool active;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: active
        ? _OutlinePainter(value ?? 0, Theme.of(context).colorScheme.primary)
        : null,
    child: child,
  );
}

class _OutlinePainter extends CustomPainter {
  _OutlinePainter(this.value, this.color);
  final double value;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1.5);
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(size.height / 2)),
      );
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * value.clamp(0, 1)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_OutlinePainter oldDelegate) =>
      value != oldDelegate.value || color != oldDelegate.color;
}
