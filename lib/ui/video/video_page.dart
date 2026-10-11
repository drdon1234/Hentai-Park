import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../engine/source_manager.dart';
import '../../library/downloads.dart';
import '../../library/library.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/error_view.dart';
import '../widgets/paged_grid.dart';
import 'video_gesture_surface.dart';
import 'video_gestures.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({super.key, required this.work});
  final WorkDetail work;

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> with WidgetsBindingObserver {
  VideoPlayerController? _c;
  List<VideoSource> _sources = [];
  VideoSource? _current;
  Object? _error;
  bool _offline = false;
  bool _controls = true;
  VideoDisplayMode _displayMode = VideoDisplayMode.inline;
  double _speed = 1;
  Timer? _hide;
  Timer? _savePos;
  Timer? _hintTimer;
  StreamSubscription<double>? _volumeSub;
  String? _seekHint;
  Duration? _previewPosition;
  VideoGestureSession? _gesture;
  double _brightness = 1;
  double _volume = 1;
  bool _nativeLevels = false;
  Future<void> _screenUpdates = Future.value();
  int _openRequest = 0;

  bool get _fullscreen => _displayMode != VideoDisplayMode.inline;

  static bool get _supported => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    _volumeSub = PlatformBridge.mediaVolumeChanges.listen((volume) {
      if (mounted) setState(() => _volume = volume);
    });
    _readLevels();
    _init();
  }

  @override
  void dispose() {
    _savePosition();
    _hide?.cancel();
    _savePos?.cancel();
    _hintTimer?.cancel();
    _volumeSub?.cancel();
    _openRequest++;
    WidgetsBinding.instance.removeObserver(this);
    _c?.removeListener(_onTick);
    _c?.dispose();
    WakelockPlus.disable();
    PlatformBridge.resetVideoBrightness();
    _updateScreen(VideoDisplayMode.inline);
    super.dispose();
  }

  @override
  void didChangeMetrics() => _cancelGesture();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _readLevels();
      _updateScreen(_displayMode);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _cancelGesture();
      PlatformBridge.resetVideoBrightness();
    }
  }

  Future<void> _readLevels() async {
    final levels = await PlatformBridge.videoLevels();
    if (!mounted || _gesture != null || levels == null) return;
    setState(() {
      _nativeLevels = true;
      _brightness = levels.brightness;
      _volume = levels.volume;
    });
  }

  Future<void> _init() async {
    setState(() => _error = null);
    try {
      final local = await DownloadManager.instance.localVideo(widget.work.source, widget.work.id);
      if (!mounted) return;
      if (local != null) {
        _offline = true;
        await _open(VideoPlayerController.file(local));
        return;
      }
      final sources = await SourceManager.instance.videos(widget.work.source, widget.work.id);
      if (!mounted) return;
      _sources = sources;
      await _play(sources.firstWhere((s) => s.preferred, orElse: () => sources.first));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _play(VideoSource s, {Duration? at}) async {
    _current = s;
    if (!_supported) {
      setState(() {});
      return;
    }
    await _open(VideoPlayerController.networkUrl(Uri.parse(s.url), httpHeaders: s.headers), at: at);
  }

  Future<void> _open(VideoPlayerController c, {Duration? at}) async {
    final request = ++_openRequest;
    _savePos?.cancel();
    _hide?.cancel();
    _cancelGesture();
    final old = _c;
    old?.removeListener(_onTick);
    setState(() => _c = null);
    await old?.dispose();
    try {
      await c.initialize();
    } catch (e) {
      await c.dispose();
      if (mounted && request == _openRequest) setState(() => _error = SourceError('NETWORK', '视频加载失败：${e is SourceError ? e.rawMessage : e}'));
      return;
    }
    if (!mounted || request != _openRequest) {
      await c.dispose();
      return;
    }
    final resume = at ?? _resumePoint(c.value.duration);
    if (resume != null) await c.seekTo(resume);
    await c.setPlaybackSpeed(_speed);
    await c.play();
    if (!mounted || request != _openRequest) {
      await c.dispose();
      return;
    }
    c.addListener(_onTick);
    setState(() => _c = c);
    _savePos = Timer.periodic(const Duration(seconds: 10), (_) => _savePosition());
    _scheduleHide();
  }

  Duration? _resumePoint(Duration total) {
    final pos = Library.instance.historyOf(widget.work.uid)?.position;
    if (pos == null || pos < 5 || pos > total.inSeconds - 10) return null;
    return Duration(seconds: pos);
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _savePosition() {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    Library.instance.recordVideoPosition(widget.work.toItem(), c.value.position.inSeconds);
  }

  void _scheduleHide() {
    _hide?.cancel();
    if (!mounted) return;
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && _gesture == null && _previewPosition == null && (_c?.value.isPlaying ?? false)) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  Future<void> _seekBy(int seconds) async {
    final c = _c;
    if (c == null) return;
    final target = (c.value.position.inMilliseconds + seconds * 1000).clamp(0, c.value.duration.inMilliseconds);
    await c.seekTo(Duration(milliseconds: target));
    if (!mounted) return;
    setState(() => _seekHint = tr('{seconds}秒', {'seconds': seconds > 0 ? '+$seconds' : '$seconds'}));
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _seekHint = null);
    });
  }

  Future<void> _toggleFullscreen() async {
    await _setDisplayMode(_fullscreen ? VideoDisplayMode.inline : VideoDisplayMode.portrait);
  }

  Future<void> _setDisplayMode(VideoDisplayMode mode) async {
    _cancelGesture();
    setState(() {
      _displayMode = mode;
      _controls = true;
    });
    await _updateScreen(mode);
    _scheduleHide();
  }

  Future<void> _updateScreen(VideoDisplayMode mode) {
    return _screenUpdates = _screenUpdates
        .then((_) async {
          if (!mounted && mode != VideoDisplayMode.inline) return;
          await SystemChrome.setPreferredOrientations(videoOrientations(mode));
          await PlatformBridge.applyVideoFullscreen(mode != VideoDisplayMode.inline);
        })
        .catchError((Object _) {});
  }

  void _startGesture(Offset point, Size viewport) {
    final c = _c;
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
    setState(() {
      switch (action) {
        case VideoGestureAction.seek:
          _previewPosition = gesture.position;
          _seekHint = '${_fmt(gesture.position)} / ${_fmt(gesture.duration)}';
        case VideoGestureAction.brightness:
          _brightness = gesture.brightness;
          _seekHint = tr('亮度 {percent}%', {'percent': (_brightness * 100).round()});
        case VideoGestureAction.volume:
          _volume = gesture.volume;
          _seekHint = tr('音量 {percent}%', {'percent': (_volume * 100).round()});
      }
    });
    if (action == VideoGestureAction.brightness && _nativeLevels) PlatformBridge.setVideoBrightness(_brightness);
    if (action == VideoGestureAction.volume) {
      if (_nativeLevels) {
        PlatformBridge.setVideoVolume(_volume);
      } else {
        _c?.setVolume(_volume);
      }
    }
  }

  Future<void> _endGesture() async {
    final gesture = _gesture;
    final c = _c;
    _gesture = null;
    if (gesture?.action == VideoGestureAction.seek && c != null) await c.seekTo(gesture!.position);
    if (!mounted || _gesture != null) return;
    setState(() {
      _previewPosition = null;
      _seekHint = null;
    });
    _readLevels();
    _scheduleHide();
  }

  void _cancelGesture() {
    if (_gesture == null && _previewPosition == null) return;
    _gesture = null;
    if (mounted)
      setState(() {
        _previewPosition = null;
        _seekHint = null;
      });
    _scheduleHide();
  }

  Future<void> _switchQuality() async {
    if (_sources.length < 2) return;
    final picked = await showModalBottomSheet<VideoSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(tr('清晰度'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final s in _sources)
              ListTile(
                leading: Icon(s == _current ? Icons.radio_button_checked : Icons.radio_button_off),
                title: Text(s.label),
                onTap: () => Navigator.pop(ctx, s),
              ),
          ],
        ),
      ),
    );
    if (mounted && picked != null && picked != _current) {
      final pos = _c?.value.position;
      await _play(picked, at: pos);
    }
  }

  Future<void> _pickSpeed() async {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final picked = await showModalBottomSheet<double>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(tr('播放速度'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final s in speeds)
              ListTile(
                leading: Icon(s == _speed ? Icons.radio_button_checked : Icons.radio_button_off),
                title: Text('${s}x'),
                onTap: () => Navigator.pop(ctx, s),
              ),
          ],
        ),
      ),
    );
    if (mounted && picked != null) {
      _speed = picked;
      await _c?.setPlaybackSpeed(picked);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final player = _player(context);
    if (_fullscreen) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _toggleFullscreen();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: player),
        ),
      );
    }
    final d = widget.work;
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            player,
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          Text(
                            [
                              if (d.authors.isNotEmpty) d.authors.join(' / '),
                              if (d.views != null) tr('{count} 次观看', {'count': formatCount(d.views)}),
                              if (d.uploaded.isNotEmpty) d.uploaded,
                              if (_offline) tr('离线播放'),
                              if (_current != null) _current!.label,
                            ].join(' · '),
                            style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (d.series.isNotEmpty)
                    SliverToBoxAdapter(
                      child: WorkCarousel(title: tr('同系列'), items: d.series),
                    ),
                  if (d.related.isNotEmpty)
                    SliverToBoxAdapter(
                      child: WorkCarousel(title: tr('相关推荐'), items: d.related),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _player(BuildContext context) {
    final c = _c;
    Widget inner;
    if (_error != null) {
      inner = Theme(
        data: ParkTheme.build(Brightness.dark, context.colors.primary),
        child: SourceErrorView(error: _error!, source: widget.work.source, onRetry: _init, compact: true),
      );
    } else if (!_supported && _current != null) {
      inner = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('当前平台不支持内置播放'), style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => launchUrl(Uri.parse(_current!.url), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(tr('用外部播放器打开（{quality}）', {'quality': _current!.label})),
            ),
          ],
        ),
      );
    } else if (c == null || !c.value.isInitialized) {
      inner = Center(
        child: LoadingIndicator(label: tr(_sources.isEmpty && !_offline ? '正在获取视频地址…' : '正在缓冲…'), color: Colors.white70),
      );
    } else {
      inner = VideoGestureSurface(
        onTap: _toggleControls,
        onDoubleTap: (point) {
          final box = context.findRenderObject() as RenderBox?;
          _seekBy(point.dx < (box?.size.width ?? MediaQuery.sizeOf(context).width) / 2 ? -10 : 10);
        },
        onStart: _startGesture,
        onUpdate: _updateGesture,
        onEnd: _endGesture,
        onCancel: _cancelGesture,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
            ),
            if (!_nativeLevels && _brightness < 1)
              IgnorePointer(
                child: ColoredBox(color: Colors.black.withValues(alpha: (1 - _brightness) * 0.8)),
              ),
            if (c.value.isBuffering) const Center(child: CircularProgressIndicator(color: Colors.white70)),
          ],
        ),
        overlay: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedOpacity(
              opacity: _controls ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(ignoring: !_controls, child: _controlsOverlay(c)),
            ),
            if (_seekHint != null)
              IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      _seekHint!,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    final box = ColoredBox(color: Colors.black, child: inner);
    if (_fullscreen) return box;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = (constraints.maxWidth * 9 / 16).clamp(0.0, MediaQuery.sizeOf(context).height * 0.6);
        return SizedBox(width: double.infinity, height: height, child: box);
      },
    );
  }

  Widget _controlsOverlay(VideoPlayerController c) {
    final v = c.value;
    final total = v.duration.inMilliseconds.toDouble();
    final displayPosition = _previewPosition ?? v.position;
    final pos = displayPosition.inMilliseconds.clamp(0, total).toDouble();
    final buffered = v.buffered.isEmpty ? 0.0 : v.buffered.last.end.inMilliseconds.toDouble();
    return Stack(
      fit: StackFit.expand,
      children: [
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black54, Colors.transparent, Colors.transparent, Colors.black87],
              ),
            ),
          ),
        ),
        SafeArea(
          top: _fullscreen,
          bottom: _fullscreen,
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: tr('返回'),
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    onPressed: () => _fullscreen ? _toggleFullscreen() : Navigator.maybePop(context),
                  ),
                  Expanded(
                    child: Text(
                      widget.work.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (_sources.length > 1)
                    TextButton(
                      onPressed: _switchQuality,
                      child: Text(_current?.label ?? '', style: const TextStyle(color: Colors.white)),
                    ),
                  TextButton(
                    onPressed: _pickSpeed,
                    child: Text('${_speed}x', style: const TextStyle(color: Colors.white)),
                  ),
                ],
              ),
              const Spacer(),
              IconButton(
                tooltip: tr(v.isPlaying ? '暂停' : '播放'),
                iconSize: 56,
                icon: Icon(v.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: Colors.white),
                onPressed: () {
                  v.isPlaying ? c.pause() : c.play();
                  _scheduleHide();
                },
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Text(_fmt(displayPosition), style: const TextStyle(color: Colors.white, fontSize: 12)),
                    Expanded(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (total > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: LinearProgressIndicator(
                                value: (buffered / total).clamp(0, 1),
                                minHeight: 2,
                                backgroundColor: Colors.white24,
                                color: Colors.white38,
                              ),
                            ),
                          Slider(
                            value: pos,
                            max: total > 0 ? total : 1,
                            onChangeStart: total > 0 ? (_) => _hide?.cancel() : null,
                            onChanged: total > 0 ? (x) => setState(() => _previewPosition = Duration(milliseconds: x.round())) : null,
                            onChangeEnd: total > 0
                                ? (x) async {
                                    await c.seekTo(Duration(milliseconds: x.round()));
                                    if (!mounted) return;
                                    setState(() => _previewPosition = null);
                                    _scheduleHide();
                                  }
                                : null,
                            activeColor: Theme.of(context).colorScheme.primary,
                            inactiveColor: Colors.transparent,
                          ),
                        ],
                      ),
                    ),
                    Text(_fmt(v.duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
                    IconButton(
                      tooltip: tr(_displayMode == VideoDisplayMode.landscape ? '竖屏展开' : '横屏播放'),
                      icon: Icon(
                        _displayMode == VideoDisplayMode.landscape ? Icons.stay_current_portrait_rounded : Icons.screen_rotation_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => _setDisplayMode(
                        _displayMode == VideoDisplayMode.landscape ? VideoDisplayMode.portrait : VideoDisplayMode.landscape,
                      ),
                    ),
                    IconButton(
                      tooltip: tr(_fullscreen ? '退出全屏' : '竖屏展开'),
                      icon: Icon(_fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, color: Colors.white),
                      onPressed: _toggleFullscreen,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _fmt(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0'), ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}
