import 'package:flutter/services.dart';

enum VideoDisplayMode { inline, portrait, landscape }

List<DeviceOrientation> videoOrientations(VideoDisplayMode mode) =>
    switch (mode) {
      VideoDisplayMode.inline => const [],
      VideoDisplayMode.portrait => const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ],
      VideoDisplayMode.landscape => const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
    };

enum VideoGestureAction { seek, brightness, volume }

/// One drag uses a snapshot of playback and the current viewport's coordinates.
/// Native rotation already transforms Flutter coordinates, including upside-down
/// portrait: visual left stays brightness and upward motion always increases it.
class VideoGestureSession {
  VideoGestureSession({
    required this.start,
    required this.size,
    required Duration position,
    required this.duration,
    required double brightness,
    required double volume,
  }) : _startPosition = position,
       _startBrightness = brightness,
       _startVolume = volume,
       position = position,
       brightness = brightness,
       volume = volume;

  final Offset start;
  final Size size;
  final Duration duration;
  final Duration _startPosition;
  final double _startBrightness;
  final double _startVolume;
  VideoGestureAction? action;
  Duration position;
  double brightness;
  double volume;

  void update(Offset point) {
    final delta = point - start;
    if (action == null) {
      if (delta.distance < 12) return;
      // System gestures and the lower control bar never initiate level changes.
      if (start.dy < 16 || start.dy >= size.height - 48) return;
      if (delta.dx.abs() > delta.dy.abs()) {
        action = VideoGestureAction.seek;
      } else if (start.dx < size.width / 3) {
        action = VideoGestureAction.brightness;
      } else if (start.dx > size.width * 2 / 3) {
        action = VideoGestureAction.volume;
      } else {
        return;
      }
    }
    switch (action!) {
      case VideoGestureAction.seek:
        if (size.width <= 0 || duration <= Duration.zero) {
          position = Duration.zero;
          return;
        }
        final span = duration.inMilliseconds.clamp(0, 120000);
        final target =
            _startPosition.inMilliseconds + delta.dx / size.width * span;
        position = Duration(
          milliseconds: target.round().clamp(0, duration.inMilliseconds),
        );
      case VideoGestureAction.brightness:
        if (size.height > 0) {
          brightness = (_startBrightness - delta.dy / size.height).clamp(
            0.0,
            1.0,
          );
        }
      case VideoGestureAction.volume:
        if (size.height > 0) {
          volume = (_startVolume - delta.dy / size.height).clamp(0.0, 1.0);
        }
    }
  }
}
