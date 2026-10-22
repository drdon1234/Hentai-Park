import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/localization.dart';

/// Controls sit above the detector, so their taps never enter its gesture arena.
/// Transparent space between controls still reaches the video underneath.
class VideoGestureSurface extends StatefulWidget {
  const VideoGestureSurface({
    super.key,
    required this.child,
    this.overlay,
    this.pageVertically = false,
    this.showLevelControls = false,
    required this.onTap,
    this.onMouseTap,
    required this.onDoubleTap,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  final Widget child;
  final Widget? overlay;
  final bool pageVertically;
  final bool showLevelControls;
  final VoidCallback onTap;
  final VoidCallback? onMouseTap;
  final VoidCallback onDoubleTap;
  final void Function(Offset point, Size viewport) onStart;
  final ValueChanged<Offset> onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;

  @override
  State<VideoGestureSurface> createState() => _VideoGestureSurfaceState();
}

class _VideoGestureSurfaceState extends State<VideoGestureSurface> {
  Offset _down = Offset.zero;
  bool _blocked = false;
  PointerDeviceKind? _tapKind;

  Widget _detector(
    Size viewport, {
    Offset origin = Offset.zero,
    bool horizontalOnly = false,
    bool verticalOnly = false,
  }) {
    void down(DragDownDetails details) {
      _down = details.localPosition + origin;
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
      if (!_blocked) widget.onUpdate(details.localPosition + origin);
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
      onTapDown: (details) => _tapKind = details.kind,
      onTap: () {
        if (_tapKind == PointerDeviceKind.mouse && widget.onMouseTap != null) {
          widget.onMouseTap!();
        } else {
          widget.onTap();
        }
      },
      onDoubleTap: widget.onDoubleTap,
      onPanDown: horizontalOnly || verticalOnly ? null : down,
      onPanStart: horizontalOnly || verticalOnly ? null : start,
      onPanUpdate: horizontalOnly || verticalOnly ? null : update,
      onPanEnd: horizontalOnly || verticalOnly ? null : end,
      onPanCancel: horizontalOnly || verticalOnly ? null : cancel,
      onVerticalDragDown: verticalOnly ? down : null,
      onVerticalDragStart: verticalOnly ? start : null,
      onVerticalDragUpdate: verticalOnly ? update : null,
      onVerticalDragEnd: verticalOnly ? end : null,
      onVerticalDragCancel: verticalOnly ? cancel : null,
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
        _detector(constraints.biggest, horizontalOnly: widget.pageVertically),
        if (widget.pageVertically &&
            widget.showLevelControls &&
            constraints.maxHeight >= 180)
          for (final left in [true, false])
            Positioned(
              left: left ? 8 : null,
              right: left ? null : 8,
              top:
                  (constraints.maxHeight -
                      (constraints.maxHeight * .3).clamp(72.0, 144.0)) /
                  2,
              width: 48,
              height: (constraints.maxHeight * .3).clamp(72.0, 144.0),
              child: Tooltip(
                message: tr(left ? '亮度' : '音量'),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                        ),
                      ),
                    ),
                    IgnorePointer(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            left
                                ? Icons.brightness_6_outlined
                                : Icons.volume_up_outlined,
                            color: Colors.white70,
                            size: 20,
                          ),
                          const SizedBox(height: 8),
                          const Icon(
                            Icons.unfold_more_rounded,
                            color: Colors.white70,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                    _detector(
                      constraints.biggest,
                      verticalOnly: true,
                      origin: Offset(
                        left ? 8 : constraints.maxWidth - 56,
                        (constraints.maxHeight -
                                (constraints.maxHeight * .3).clamp(
                                  72.0,
                                  144.0,
                                )) /
                            2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        if (widget.overlay != null) widget.overlay!,
      ],
    ),
  );
}
