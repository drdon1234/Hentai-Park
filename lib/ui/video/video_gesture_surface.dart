import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Controls sit above the detector, so their taps never enter its gesture arena.
/// Transparent space between controls still reaches the video underneath.
class VideoGestureSurface extends StatefulWidget {
  const VideoGestureSurface({
    super.key,
    required this.child,
    this.overlay,
    required this.onTap,
    required this.onDoubleTap,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  final Widget child;
  final Widget? overlay;
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

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onTap: widget.onTap,
          onDoubleTapDown: (details) => _doubleTap = details.localPosition,
          onDoubleTap: () => widget.onDoubleTap(_doubleTap),
          onPanDown: (details) => _down = details.localPosition,
          onPanStart: (_) => widget.onStart(_down, constraints.biggest),
          onPanUpdate: (details) => widget.onUpdate(details.localPosition),
          onPanEnd: (_) => widget.onEnd(),
          onPanCancel: widget.onCancel,
          child: widget.child,
        ),
        if (widget.overlay != null) widget.overlay!,
      ],
    ),
  );
}
