import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/localization.dart';
import '../../core/app_lock.dart';
import '../../core/models.dart';
import '../../engine/source_manager.dart';
import '../../engine/browser_media.dart';
import '../../library/downloads.dart';
import '../../library/library.dart';
import '../../video/hls_playback.dart';
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
  HlsPlayback? _media;
  HlsPlayback? _preparingMedia;
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
  bool _wantsPlayback = true;
  bool _completed = false;
  bool _foreground = true;
  Future<void> _playbackUpdates = Future.value();
  Future<void> _screenUpdates = Future.value();
  int _openRequest = 0;
  CancelToken? _sourceRequest;

  bool get _fullscreen => _displayMode != VideoDisplayMode.inline;

  static bool get _supported => switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.macOS => true,
    _ => false,
  };

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    AppLock.instance.addListener(_onLockChanged);
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
    _sourceRequest?.cancel('video page closed');
    WidgetsBinding.instance.removeObserver(this);
    AppLock.instance.removeListener(_onLockChanged);
    _c?.removeListener(_onTick);
    final media = _media;
    unawaited(
      (_c?.dispose() ?? Future<void>.value()).whenComplete(
        () async => media?.close(),
      ),
    );
    unawaited(_preparingMedia?.close());
    WakelockPlus.disable();
    PlatformBridge.resetVideoBrightness();
    _updateScreen(VideoDisplayMode.inline);
    super.dispose();
  }

  @override
  void didChangeMetrics() => _cancelGesture();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      _readLevels();
      _updateScreen(_displayMode);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _savePosition();
      _cancelGesture();
      PlatformBridge.resetVideoBrightness();
    }
    // Queue playback after all lifecycle observers have updated the app lock.
    _syncPlayback();
  }

  void _onLockChanged() {
    if (AppLock.instance.locked) _cancelGesture();
    _syncPlayback();
  }

  Future<void> _syncPlayback() {
    final c = _c;
    return _playbackUpdates = _playbackUpdates
        .then((_) async {
          if (!mounted || c == null || !identical(c, _c)) return;
          if (_foreground && !AppLock.instance.locked && _wantsPlayback) {
            await c.play();
          } else {
            await c.pause();
          }
        })
        .catchError((Object error) {
          if (mounted && c != null && identical(c, _c)) {
            setState(() => _error = error);
          }
        });
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
    _sourceRequest?.cancel('video source reloaded');
    final request = _sourceRequest = CancelToken();
    setState(() => _error = null);
    try {
      final local = await DownloadManager.instance.localVideo(
        widget.work.source,
        widget.work.id,
      );
      if (!mounted || request.isCancelled) return;
      if (local != null) {
        _offline = true;
        await _open(
          VideoPlayerController.file(
            local,
            videoPlayerOptions: VideoPlayerOptions(
              allowBackgroundPlayback: true,
            ),
          ),
        );
        return;
      }
      final sources = await SourceManager.instance.videos(
        widget.work.source,
        widget.work.id,
        cancelToken: request,
      );
      if (!mounted || request.isCancelled) return;
      _sources = sources;
      await _play(
        sources.firstWhere((s) => s.preferred, orElse: () => sources.first),
      );
    } catch (e) {
      if (mounted && !request.isCancelled) setState(() => _error = e);
    } finally {
      if (identical(_sourceRequest, request)) _sourceRequest = null;
    }
  }

  Future<void> _play(VideoSource s, {Duration? at}) async {
    final request = ++_openRequest;
    final preparing = _preparingMedia;
    _preparingMedia = null;
    await preparing?.close();
    if (!mounted || request != _openRequest) return;
    _current = s;
    if (!_supported) {
      setState(() {});
      return;
    }
    HlsPlayback? media;
    try {
      var url = Uri.parse(s.url);
      if (s.format == 'hls') {
        final manifest = SourceManager.instance.manifest(widget.work.source);
        if (manifest == null) throw SourceError('CONFIG', '视频源未加载');
        media = HlsPlayback(
          BrowserMedia(BrowserMediaPolicy.fromManifest(manifest)),
        );
        _preparingMedia = media;
        url = await media.open(url);
      }
      if (!mounted || request != _openRequest) {
        await media?.close();
        return;
      }
      await _open(
        VideoPlayerController.networkUrl(
          url,
          httpHeaders: media == null ? s.headers : const {},
          videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: true),
        ),
        at: at,
        media: media,
        requestId: request,
      );
    } catch (e) {
      await media?.close();
      if (mounted && request == _openRequest) setState(() => _error = e);
    } finally {
      if (identical(_preparingMedia, media)) _preparingMedia = null;
    }
  }

  Future<void> _open(
    VideoPlayerController c, {
    Duration? at,
    HlsPlayback? media,
    int? requestId,
  }) async {
    final request = requestId ?? ++_openRequest;
    if (!mounted || request != _openRequest) {
      await c.dispose();
      await media?.close();
      return;
    }
    _savePos?.cancel();
    _hide?.cancel();
    _cancelGesture();
    final old = _c;
    final oldMedia = _media;
    _media = null;
    old?.removeListener(_onTick);
    setState(() => _c = null);
    await old?.dispose();
    await oldMedia?.close();
    try {
      await c.initialize();
      if (!mounted || request != _openRequest) {
        await c.dispose();
        await media?.close();
        return;
      }
      final resume = at ?? _resumePoint(c.value.duration);
      if (resume != null) await c.seekTo(resume);
      await c.setPlaybackSpeed(_speed);
    } catch (e) {
      await c.dispose();
      await media?.close();
      if (mounted && request == _openRequest) {
        setState(
          () => _error = SourceError(
            'NETWORK',
            '视频加载失败：${e is SourceError ? e.rawMessage : e}',
          ),
        );
      }
      return;
    }
    if (!mounted || request != _openRequest) {
      await c.dispose();
      await media?.close();
      return;
    }
    c.addListener(_onTick);
    _completed = c.value.isCompleted;
    setState(() {
      _c = c;
      _media = media;
      _error = null;
    });
    await _syncPlayback();
    if (!mounted || request != _openRequest) return;
    _savePos = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _savePosition(),
    );
    _scheduleHide();
  }

  Duration? _resumePoint(Duration total) {
    final pos = Library.instance.historyOf(widget.work.uid)?.position;
    if (pos == null || pos < 5 || pos > total.inSeconds - 10) return null;
    return Duration(seconds: pos);
  }

  void _onTick() {
    final completed = _c?.value.isCompleted ?? false;
    // Completion ends playback once. Repeated notifications during a replay
    // seek must not overwrite the user's new play request.
    if (completed && !_completed) _wantsPlayback = false;
    _completed = completed;
    if (mounted) setState(() {});
  }

  void _savePosition() {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    Library.instance.recordVideoPosition(
      widget.work.toItem(),
      c.value.position.inSeconds,
    );
  }

  void _scheduleHide() {
    _hide?.cancel();
    if (!mounted) return;
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted &&
          _gesture == null &&
          _previewPosition == null &&
          (_c?.value.isPlaying ?? false)) {
        setState(() => _controls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  Future<void> _seekBy(int seconds) async {
    final c = _c;
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

  Future<void> _toggleFullscreen() async {
    await _setDisplayMode(
      _fullscreen ? VideoDisplayMode.inline : VideoDisplayMode.portrait,
    );
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
          await PlatformBridge.applyVideoFullscreen(
            mode != VideoDisplayMode.inline,
          );
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
        _c?.setVolume(_volume);
      }
    }
  }

  Future<void> _endGesture() async {
    final gesture = _gesture;
    final c = _c;
    _gesture = null;
    if (gesture?.action == VideoGestureAction.seek && c != null) {
      await c.seekTo(gesture!.position);
    }
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
    if (mounted) {
      setState(() {
        _previewPosition = null;
        _seekHint = null;
      });
    }
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
              title: Text(
                tr('清晰度'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            for (final s in _sources)
              ListTile(
                leading: Icon(
                  s == _current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
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
              title: Text(
                tr('播放速度'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            for (final s in speeds)
              ListTile(
                leading: Icon(
                  s == _speed
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
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
                          Text(
                            d.title,
                            style: context.text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            [
                              if (d.authors.isNotEmpty) d.authors.join(' / '),
                              if (d.views != null)
                                tr('{count} 次观看', {
                                  'count': formatCount(d.views),
                                }),
                              if (d.uploaded.isNotEmpty) d.uploaded,
                              if (_offline) tr('离线播放'),
                              if (_current != null) _current!.label,
                            ].join(' · '),
                            style: context.text.bodySmall?.copyWith(
                              color: context.colors.onSurfaceVariant,
                            ),
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
        child: SourceErrorView(
          error: _error!,
          source: widget.work.source,
          onRetry: _init,
          compact: true,
        ),
      );
    } else if (!_supported && _current != null) {
      inner = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr('当前平台不支持内置播放'),
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(_current!.url),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(
                tr('用外部播放器打开（{quality}）', {'quality': _current!.label}),
              ),
            ),
          ],
        ),
      );
    } else if (c == null || !c.value.isInitialized) {
      inner = Center(
        child: LoadingIndicator(
          label: tr(_sources.isEmpty && !_offline ? '正在获取视频地址…' : '正在缓冲…'),
          color: Colors.white70,
        ),
      );
    } else {
      inner = VideoGestureSurface(
        onTap: _toggleControls,
        onDoubleTap: (point) {
          final box = context.findRenderObject() as RenderBox?;
          _seekBy(
            point.dx < (box?.size.width ?? MediaQuery.sizeOf(context).width) / 2
                ? -10
                : 10,
          );
        },
        onStart: _startGesture,
        onUpdate: _updateGesture,
        onEnd: _endGesture,
        onCancel: _cancelGesture,
        overlay: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedOpacity(
              opacity: _controls ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_controls,
                child: _controlsOverlay(c),
              ),
            ),
            if (_seekHint != null)
              IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _seekHint!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: c.value.aspectRatio,
                child: VideoPlayer(c),
              ),
            ),
            if (!_nativeLevels && _brightness < 1)
              IgnorePointer(
                child: ColoredBox(
                  color: Colors.black.withValues(
                    alpha: (1 - _brightness) * 0.8,
                  ),
                ),
              ),
            if (c.value.isBuffering)
              const Center(
                child: CircularProgressIndicator(color: Colors.white70),
              ),
          ],
        ),
      );
    }
    final box = ColoredBox(color: Colors.black, child: inner);
    if (_fullscreen) return box;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = (constraints.maxWidth * 9 / 16).clamp(
          0.0,
          MediaQuery.sizeOf(context).height * 0.6,
        );
        return SizedBox(width: double.infinity, height: height, child: box);
      },
    );
  }

  Widget _controlsOverlay(VideoPlayerController c) {
    final v = c.value;
    final total = v.duration.inMilliseconds.toDouble();
    final displayPosition = _previewPosition ?? v.position;
    final pos = displayPosition.inMilliseconds.clamp(0, total).toDouble();
    final buffered = v.buffered.isEmpty
        ? 0.0
        : v.buffered.last.end.inMilliseconds.toDouble();
    return Stack(
      fit: StackFit.expand,
      children: [
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black54,
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black87,
                ],
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
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                    ),
                    onPressed: () => _fullscreen
                        ? _toggleFullscreen()
                        : Navigator.maybePop(context),
                  ),
                  Expanded(
                    child: Text(
                      widget.work.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_sources.length > 1)
                    TextButton(
                      onPressed: _switchQuality,
                      child: Text(
                        _current?.label ?? '',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  TextButton(
                    onPressed: _pickSpeed,
                    child: Text(
                      '${_speed}x',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              IconButton(
                tooltip: tr(v.isPlaying ? '暂停' : '播放'),
                iconSize: 56,
                icon: Icon(
                  v.isPlaying
                      ? Icons.pause_circle_filled_rounded
                      : Icons.play_circle_fill_rounded,
                  color: Colors.white,
                ),
                onPressed: () {
                  _wantsPlayback = !v.isPlaying;
                  _syncPlayback();
                  _scheduleHide();
                },
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Text(
                      _fmt(displayPosition),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    Expanded(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (total > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
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
                            onChangeStart: total > 0
                                ? (_) => _hide?.cancel()
                                : null,
                            onChanged: total > 0
                                ? (x) => setState(
                                    () => _previewPosition = Duration(
                                      milliseconds: x.round(),
                                    ),
                                  )
                                : null,
                            onChangeEnd: total > 0
                                ? (x) async {
                                    await c.seekTo(
                                      Duration(milliseconds: x.round()),
                                    );
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
                    Text(
                      _fmt(v.duration),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    IconButton(
                      tooltip: tr(
                        _displayMode == VideoDisplayMode.landscape
                            ? '竖屏展开'
                            : '横屏播放',
                      ),
                      icon: Icon(
                        _displayMode == VideoDisplayMode.landscape
                            ? Icons.stay_current_portrait_rounded
                            : Icons.screen_rotation_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => _setDisplayMode(
                        _displayMode == VideoDisplayMode.landscape
                            ? VideoDisplayMode.portrait
                            : VideoDisplayMode.landscape,
                      ),
                    ),
                    IconButton(
                      tooltip: tr(_fullscreen ? '退出全屏' : '竖屏展开'),
                      icon: Icon(
                        _fullscreen
                            ? Icons.fullscreen_exit_rounded
                            : Icons.fullscreen_rounded,
                        color: Colors.white,
                      ),
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
