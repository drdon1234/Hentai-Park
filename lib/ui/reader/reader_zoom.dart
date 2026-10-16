import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 双指落下即接管缩放；单指仍由原来的滚动、翻页和放大后拖动处理。
class ReaderZoom extends StatefulWidget {
  const ReaderZoom({
    super.key,
    required this.controller,
    required this.child,
    this.maxScale = 5,
    this.panEnabled = true,
    this.onInteractionStart,
  });
  final TransformationController controller;
  final Widget child;
  final double maxScale;
  final bool panEnabled;
  final GestureScaleStartCallback? onInteractionStart;

  @override
  State<ReaderZoom> createState() => _ReaderZoomState();
}

class _ReaderZoomState extends State<ReaderZoom> {
  double _startScale = 1, _startDistance = 1;
  Offset _anchor = Offset.zero;

  void _start(Offset focal, double distance) {
    final box = context.findRenderObject()! as RenderBox;
    final local = box.globalToLocal(focal);
    _startScale = widget.controller.value.getMaxScaleOnAxis();
    _startDistance = distance;
    _anchor = widget.controller.toScene(local);
    widget.onInteractionStart?.call(
      ScaleStartDetails(
        focalPoint: focal,
        localFocalPoint: local,
        pointerCount: distance > 0 ? 2 : 1,
      ),
    );
  }

  void _update(Offset focal, double distance) {
    final box = context.findRenderObject()! as RenderBox;
    final scale =
        (_startDistance <= 0
                ? _startScale
                : _startScale * distance / _startDistance)
            .clamp(1.0, widget.maxScale);
    final offset = box.globalToLocal(focal) - _anchor * scale;
    final dx = offset.dx.clamp(box.size.width * (1 - scale), 0.0);
    final dy = offset.dy.clamp(box.size.height * (1 - scale), 0.0);
    widget.controller.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  Widget build(BuildContext context) => InteractiveViewer(
    transformationController: widget.controller,
    minScale: 1,
    maxScale: widget.maxScale,
    panEnabled: widget.panEnabled,
    onInteractionStart: widget.onInteractionStart,
    child: RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        _PinchGesture: GestureRecognizerFactoryWithHandlers<_PinchGesture>(
          _PinchGesture.new,
          (gesture) => gesture
            ..onStart = _start
            ..onUpdate = _update,
        ),
      },
      child: widget.child,
    ),
  );
}

class _PinchGesture extends OneSequenceGestureRecognizer {
  _PinchGesture()
    : super(
        supportedDevices: const {
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
        },
      );
  final _points = <int, Offset>{};
  bool _active = false;
  void Function(Offset focal, double distance)? onStart, onUpdate;

  void _emit(void Function(Offset, double)? callback) {
    final points = _points.values.take(2).toList();
    callback?.call(
      points.length == 1 ? points[0] : (points[0] + points[1]) / 2,
      points.length == 1 ? 0 : (points[0] - points[1]).distance,
    );
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    _points[event.pointer] = event.position;
    if (_active) {
      _emit(onStart);
    } else if (_points.length == 2) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void acceptGesture(int pointer) {
    if (!_active && _points.length >= 2) {
      _active = true;
      _emit(onStart);
    }
  }

  @override
  void rejectGesture(int pointer) {
    _remove(pointer);
  }

  void _remove(int pointer) {
    if (_points.remove(pointer) == null) return;
    stopTrackingPointer(pointer);
    if (_points.isEmpty) {
      _active = false;
    } else if (_active) {
      _emit(onStart);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent && _points.containsKey(event.pointer)) {
      _points[event.pointer] = event.position;
      if (_active) _emit(onUpdate);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _remove(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    resolve(GestureDisposition.rejected);
    _active = false;
  }

  @override
  String get debugDescription => 'reader pinch';
}
