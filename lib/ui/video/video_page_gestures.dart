part of 'video_page.dart';

/// Swipe and double-tap gestures on the player: seek preview, brightness and volume.
mixin _VideoGestures on State<VideoPage> {
  VideoSession get _session;
  void _scheduleHide();

  Timer? _hide;
  Timer? _hintTimer;
  String? _seekHint;
  Duration? _previewPosition;
  VideoGestureSession? _gesture;
  double _brightness = 1;
  double _volume = 1;
  bool _nativeLevels = false;

  Future<void> _readLevels() async {
    final levels = await PlatformBridge.videoLevels();
    if (!mounted || _gesture != null || levels == null) return;
    setState(() {
      _nativeLevels = true;
      _brightness = levels.brightness;
      _volume = levels.volume;
    });
  }

  Future<void> _seekBy(int seconds) async {
    if (_session.isLive) return;
    final c = _session.controller;
    if (c == null) return;
    final target = (c.value.position.inMilliseconds + seconds * 1000).clamp(
      0,
      c.value.duration.inMilliseconds,
    );
    await c.seekTo(Duration(milliseconds: target));
    if (!mounted) return;
    setState(
      () => _seekHint = tr('{seconds}秒', {
        'seconds': seconds > 0 ? '+$seconds' : '$seconds',
      }),
    );
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _seekHint = null);
    });
  }

  void _startGesture(Offset point, Size viewport) {
    final c = _session.controller;
    if (c == null) return;
    _hide?.cancel();
    _hintTimer?.cancel();
    _gesture = VideoGestureSession(
      start: point,
      size: viewport,
      position: c.value.position,
      duration: c.value.duration,
      brightness: _brightness,
      volume: _nativeLevels ? _volume : c.value.volume,
    );
  }

  void _updateGesture(Offset point) {
    final gesture = _gesture;
    if (gesture == null) return;
    gesture.update(point);
    final action = gesture.action;
    if (action == null) return;
    if (_session.isLive && action == VideoGestureAction.seek) return;
    setState(() {
      switch (action) {
        case VideoGestureAction.seek:
          _previewPosition = gesture.position;
          _seekHint =
              '${formatPlaybackTime(gesture.position)} / ${formatPlaybackTime(gesture.duration)}';
        case VideoGestureAction.brightness:
          _brightness = gesture.brightness;
          _seekHint = tr('亮度 {percent}%', {
            'percent': (_brightness * 100).round(),
          });
        case VideoGestureAction.volume:
          _volume = gesture.volume;
          _seekHint = tr('音量 {percent}%', {'percent': (_volume * 100).round()});
      }
    });
    if (action == VideoGestureAction.brightness && _nativeLevels) {
      PlatformBridge.setVideoBrightness(_brightness);
    }
    if (action == VideoGestureAction.volume) {
      if (_nativeLevels) {
        PlatformBridge.setVideoVolume(_volume);
      } else {
        _session.controller?.setVolume(_volume);
      }
    }
  }

  Future<void> _endGesture() async {
    final gesture = _gesture;
    final c = _session.controller;
    _gesture = null;
    if (!_session.isLive &&
        gesture?.action == VideoGestureAction.seek &&
        c != null) {
      await c.seekTo(gesture!.position);
    }
    if (!mounted || _gesture != null) return;
    setState(() {
      _previewPosition = null;
      _seekHint = null;
    });
    unawaited(_readLevels());
    _scheduleHide();
  }

  void _cancelGesture() {
    if (_gesture == null && _previewPosition == null) return;
    _gesture = null;
    if (mounted) {
      setState(() {
        _previewPosition = null;
        _seekHint = null;
      });
    }
    _scheduleHide();
  }
}
