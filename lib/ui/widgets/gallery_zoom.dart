import 'package:flutter/material.dart';

/// 图片页独占拖动与缩放；累计超出左右边界的单指位移，在松手时翻页。
class GalleryZoom extends StatefulWidget {
  const GalleryZoom({
    super.key,
    required this.child,
    required this.onPage,
    this.maxScale = 8,
  });
  final Widget child;
  final ValueChanged<int> onPage;
  final double maxScale;

  @override
  State<GalleryZoom> createState() => _GalleryZoomState();
}

class _GalleryZoomState extends State<GalleryZoom> {
  final _transform = TransformationController();
  final _pointers = <int>{};
  Offset _start = Offset.zero;
  double _leftRoom = 0, _rightRoom = 0;
  bool _pinched = false;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        _pointers.add(event.pointer);
        if (_pointers.length > 1) {
          _pinched = true;
          return;
        }
        _pinched = false;
        _start = event.localPosition;
        final matrix = _transform.value;
        final x = matrix.getTranslation().x;
        _rightRoom = -x;
        _leftRoom = bounds.maxWidth * (matrix.getMaxScaleOnAxis() - 1) + x;
      },
      onPointerCancel: (event) {
        _pointers.remove(event.pointer);
        _pinched = true;
      },
      onPointerUp: (event) {
        _pointers.remove(event.pointer);
        if (_pinched || _pointers.isNotEmpty) return;
        final delta = event.localPosition - _start;
        if (delta.dx.abs() <= delta.dy.abs()) return;
        final room = delta.dx > 0 ? _rightRoom : _leftRoom;
        if (delta.dx.abs() - room < 48) return;
        final rtl = Directionality.of(context) == TextDirection.rtl;
        widget.onPage((delta.dx < 0) != rtl ? 1 : -1);
      },
      child: InteractiveViewer(
        transformationController: _transform,
        maxScale: widget.maxScale,
        child: SizedBox.expand(child: widget.child),
      ),
    ),
  );
}
