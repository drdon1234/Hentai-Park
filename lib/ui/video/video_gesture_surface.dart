import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Controls sit above the detector, so their taps never enter its gesture arena.
/// Transparent space between controls still reaches the video underneath.
class VideoGestureSurface extends StatefulWidget {
  const VideoGestureSurface({
    super.key,
    required this.child,
    this.overlay,
    this.pageVertically = false,
    required this.onTap,
    required this.onDoubleTap,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  final Widget child;
  final Widget? overlay;
  final bool pageVertically;
  final VoidCallback onTap;
  final ValueChanged<Offset> onDoubleTap;
  final void Function(Offset point, Size viewport) onStart;
  final ValueChanged<Offset> onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;

  @override
  State<VideoGestureSurface> createState() => _VideoGestureSurfaceState();
}

class _VideoGestureSurfaceState extends State<VideoGestureSurface> {
  Offset _down = Offset.zero;
  Offset _doubleTap = Offset.zero;
  bool _blocked = false;

  Widget _detector(Size viewport, {double x = 0, bool horizontalOnly = false}) {
    void down(DragDownDetails details) {
      _down = details.localPosition + Offset(x, 0);
      final media = MediaQuery.of(context);
      final insets = media.systemGestureInsets;
      final box = context.findRenderObject() as RenderBox?;
      final screenPoint =
          (box?.localToGlobal(Offset.zero) ?? Offset.zero) + _down;
      _blocked =
          _down.dy < 16 ||
          _down.dy >= viewport.height - 56 ||
          screenPoint.dy >=
              media.size.height -
                  (insets.bottom + 24).clamp(48.0, double.infinity) ||
          screenPoint.dx < insets.left ||
          screenPoint.dx >= media.size.width - insets.right;
    }

    void start(DragStartDetails details) {
      if (!_blocked) widget.onStart(_down, viewport);
    }

    void update(DragUpdateDetails details) {
      if (!_blocked) widget.onUpdate(details.localPosition + Offset(x, 0));
    }

    void end(DragEndDetails details) {
      if (!_blocked) widget.onEnd();
    }

    void cancel() {
      if (!_blocked) widget.onCancel();
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onTap: widget.onTap,
      onDoubleTapDown: (details) =>
          _doubleTap = details.localPosition + Offset(x, 0),
      onDoubleTap: () => widget.onDoubleTap(_doubleTap),
      onPanDown: horizontalOnly ? null : down,
      onPanStart: horizontalOnly ? null : start,
      onPanUpdate: horizontalOnly ? null : update,
      onPanEnd: horizontalOnly ? null : end,
      onPanCancel: horizontalOnly ? null : cancel,
      onHorizontalDragDown: horizontalOnly ? down : null,
      onHorizontalDragStart: horizontalOnly ? start : null,
      onHorizontalDragUpdate: horizontalOnly ? update : null,
      onHorizontalDragEnd: horizontalOnly ? end : null,
      onHorizontalDragCancel: horizontalOnly ? cancel : null,
      child: const SizedBox.expand(),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (widget.pageVertically)
          Row(
            children: [
              Expanded(child: _detector(constraints.biggest)),
              Expanded(
                child: _detector(
                  constraints.biggest,
                  x: constraints.maxWidth / 3,
                  horizontalOnly: true,
                ),
              ),
              Expanded(
                child: _detector(
                  constraints.biggest,
                  x: constraints.maxWidth * 2 / 3,
                ),
              ),
            ],
          )
        else
          _detector(constraints.biggest),
        if (widget.overlay != null) widget.overlay!,
      ],
    ),
  );
}
