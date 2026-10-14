import 'dart:async';
import 'dart:io';

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
import '../../images/subscription_cache.dart';
import '../../images/image_store.dart';
import '../../engine/source_manager.dart';
import '../../engine/media_transport_factory.dart';
import '../../library/downloads.dart';
import '../../library/library.dart';
import '../../video/hls_playback.dart';
import '../../engine/platform_bridge.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/error_view.dart';
import '../widgets/paged_grid.dart';
import 'video_gesture_surface.dart';
import 'video_gestures.dart';
import 'video_episode_sheet.dart';
import 'adaptive_video_progress.dart';
import 'prepared_video.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({
    super.key,
    required this.work,
    this.episodeId,
    this.initialSources,
    this.localFile,
    this.recordHistory = true,
  });
  final WorkDetail work;
  final String? episodeId;
  final List<VideoSource>? initialSources;
  final File? localFile;
  final bool recordHistory;

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> with WidgetsBindingObserver {
  VideoPlayerController? _c;
  final _playerUpdates = ValueNotifier(0);
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
  late final List<Chapter> _episodes;
  late Chapter _episode;
  late final PageController _episodePages;
  Chapter? _preloadedEpisode;
  CancelToken? _preloadCancel;
  Future<PreparedVideo>? _preloaded;
  PreparedVideo? _nextPreview;
  Future<void> _preloadClosing = Future.value();
  bool get _scrollEpisodes =>
      _episodes.length > 1 &&
      (SourceManager.instance.manifest(widget.work.source)?.category ==
              SourceCategory.aiDrama ||
          widget.work.json['category'] == 'aiDrama');

  int get _episodeIndex => _episodes.indexOf(_episode);

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
    if (widget.localFile != null) {
      SubscriptionCache.instance.retain(widget.localFile!);
    }
    _episodes = widget.work.videoEpisodes;
    final selected =
        widget.episodeId ??
        Library.instance.historyOf(widget.work.uid)?.chapterId;
    _episode = _episodes.firstWhere(
      (episode) => episode.id == chapterKeyOf(selected),
      orElse: () => _episodes.first,
    );
    _episodePages = PageController(initialPage: _episodeIndex);
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
    _episodePages.dispose();
    _savePosition();
    _hide?.cancel();
    _savePos?.cancel();
    _hintTimer?.cancel();
    _volumeSub?.cancel();
    _openRequest++;
    _sourceRequest?.cancel('video page closed');
    unawaited(_discardPreload());
    WidgetsBinding.instance.removeObserver(this);
    AppLock.instance.removeListener(_onLockChanged);
    _c?.removeListener(_onTick);
    _playerUpdates.dispose();
    final media = _media;
    unawaited(
      (_c?.dispose() ?? Future<void>.value()).whenComplete(() async {
        try {
          await media?.close();
        } finally {
          if (widget.localFile case final file?) {
            SubscriptionCache.instance.release(file);
            await ImageStore.instance.trim();
          }
        }
      }),
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
    final request = ++_openRequest;
    try {
      if (widget.work.hasVideoEpisodes) {
        await Library.instance.loadChapters(widget.work.uid);
        if (!mounted || request != _openRequest) return;
        await Library.instance.syncChapters(
          widget.work.toItem(),
          _episodes,
          complete: widget.work.chaptersComplete,
        );
      }
      if (!mounted || request != _openRequest) return;
      await _selectEpisode(_episode);
    } catch (error) {
      if (mounted && request == _openRequest) setState(() => _error = error);
    }
  }

  Future<void> _selectEpisode(Chapter episode) async {
    if (_scrollEpisodes && _supported) return _selectDramaEpisode(episode);
    _savePosition();
    _sourceRequest?.cancel('video source reloaded');
    final request = _sourceRequest = CancelToken();
    final openRequest = ++_openRequest;
    _savePos?.cancel();
    _hide?.cancel();
    _cancelGesture();
    final old = _c;
    final oldMedia = _media;
    final preparing = _preparingMedia;
    old?.removeListener(_onTick);
    setState(() {
      _episode = episode;
      _c = null;
      _media = null;
      _preparingMedia = null;
      _sources = [];
      _current = null;
      _offline = false;
      _error = null;
      _controls = true;
      _completed = false;
      _wantsPlayback = true;
    });
    if (_episodePages.hasClients &&
        _episodePages.page?.round() != _episodes.indexOf(episode)) {
      _episodePages.jumpToPage(_episodes.indexOf(episode));
    }
    try {
      await preparing?.close();
      await (old?.dispose() ?? Future<void>.value()).whenComplete(
        () async => oldMedia?.close(),
      );
      if (!mounted || request.isCancelled || openRequest != _openRequest) {
        return;
      }
      final local = await DownloadManager.instance.localVideo(
        widget.work.source,
        widget.work.id,
        episodeId: episode.id,
      );
      if (!mounted || request.isCancelled || openRequest != _openRequest) {
        return;
      }
      final playbackFile = widget.localFile ?? local;
      if (playbackFile != null) {
        _offline = true;
        if (!_supported) {
          setState(
            () => _current = VideoSource({
              'url': playbackFile.uri.toString(),
              'format': 'mp4',
            }),
          );
          return;
        }
        await _open(
          VideoPlayerController.file(
            playbackFile,
            videoPlayerOptions: VideoPlayerOptions(
              allowBackgroundPlayback: true,
            ),
          ),
          requestId: openRequest,
        );
        return;
      }
      final sources =
          widget.initialSources ??
          await SourceManager.instance.videos(
            widget.work.source,
            widget.work.id,
            episodeId: episode.id,
            cancelToken: request,
          );
      if (!mounted || request.isCancelled || openRequest != _openRequest) {
        return;
      }
      _sources = sources;
      await _play(
        sources.firstWhere((s) => s.preferred, orElse: () => sources.first),
        requestId: openRequest,
      );
    } catch (e) {
      if (mounted && !request.isCancelled && openRequest == _openRequest) {
        setState(() => _error = e);
      }
    } finally {
      if (identical(_sourceRequest, request)) _sourceRequest = null;
    }
  }

  Future<void> _discardPreload() {
    final pending = _preloaded;
    _preloadCancel?.cancel('episode preload no longer needed');
    _preloaded = null;
    _preloadedEpisode = null;
    _preloadCancel = null;
    _nextPreview = null;
    if (pending != null) {
      final closing = pending
          .then((video) => video.close())
          .catchError((Object _) {});
      _preloadClosing = Future.wait([_preloadClosing, closing]).then((_) {});
    }
    return _preloadClosing;
  }

  void _preloadNext() {
    if (!mounted ||
        !_scrollEpisodes ||
        !_supported ||
        _preloaded != null ||
        _episodeIndex >= _episodes.length - 1) {
      return;
    }
    final next = _preloadedEpisode = _episodes[_episodeIndex + 1];
    final token = _preloadCancel = CancelToken();
    final pending = _preloaded = PreparedVideo.open(
      widget.work,
      next,
      token,
      localFile: widget.localFile,
      initialSources: widget.initialSources,
    );
    // 预加载失败不影响当前播放，切到该集时才显示或重试。
    pending.ignore();
    unawaited(
      pending
          .then((video) {
            if (mounted && identical(pending, _preloaded)) {
              setState(() => _nextPreview = video);
            }
          })
          .catchError((Object _) {}),
    );
  }

  Future<void> _selectDramaEpisode(Chapter episode) async {
    _savePosition();
    _sourceRequest?.cancel('episode changed');
    final token = _sourceRequest = CancelToken();
    final request = ++_openRequest;
    Future<PreparedVideo>? pending;
    if (_preloadedEpisode?.id == episode.id) {
      pending = _preloaded;
      // 转移所有权，当前请求取消时也取消尚未完成的预加载。
      final preloadToken = _preloadCancel;
      unawaited(token.whenCancel.then((error) => preloadToken?.cancel(error)));
      _preloaded = null;
      _preloadedEpisode = null;
      _preloadCancel = null;
      _nextPreview = null;
    } else {
      unawaited(_discardPreload());
    }
    _savePos?.cancel();
    _hide?.cancel();
    _cancelGesture();
    final old = _c;
    final oldMedia = _media;
    old?.removeListener(_onTick);
    // 只在确认换集后停止旧声音；释放与新播放器接管并行。
    final retiring = () async {
      try {
        await old?.pause();
      } finally {
        await (old?.dispose() ?? Future<void>.value()).whenComplete(
          () async => oldMedia?.close(),
        );
      }
    }();
    retiring.ignore();
    setState(() {
      _episode = episode;
      _c = null;
      _media = null;
      _sources = [];
      _current = null;
      _error = null;
      _offline = false;
      _completed = false;
      _controls = true;
      _wantsPlayback = true;
    });
    if (_episodePages.hasClients &&
        _episodePages.page?.round() != _episodeIndex) {
      _episodePages.jumpToPage(_episodeIndex);
    }
    PreparedVideo? prepared;
    try {
      if (pending == null) {
        await Future.wait([retiring, _preloadClosing]);
        if (!mounted || token.isCancelled || request != _openRequest) return;
      }
      prepared =
          await (pending ??
              PreparedVideo.open(
                widget.work,
                episode,
                token,
                localFile: widget.localFile,
                initialSources: widget.initialSources,
              ));
      if (!mounted || token.isCancelled || request != _openRequest) {
        await prepared.close();
        return;
      }
      final c = prepared.controller;
      final resume = _resumePoint(c.value.duration);
      if (resume != null) await c.seekTo(resume);
      await c.setPlaybackSpeed(_speed);
      if (!mounted || token.isCancelled || request != _openRequest) {
        await prepared.close();
        return;
      }
      c.addListener(_onTick);
      setState(() {
        _c = c;
        _media = prepared!.media;
        _sources = prepared.sources;
        _current = prepared.source;
        _offline = prepared.offline;
      });
      await _syncPlayback();
      if (!mounted || request != _openRequest) return;
      _savePos = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _savePosition(),
      );
      _scheduleHide();
      await retiring;
      if (mounted && request == _openRequest) _preloadNext();
    } catch (error) {
      if (prepared != null && !identical(prepared.controller, _c)) {
        await prepared.close();
      }
      if (mounted && !token.isCancelled && request == _openRequest) {
        setState(() => _error = error);
      }
    } finally {
      if (identical(_sourceRequest, token)) _sourceRequest = null;
    }
  }

  Future<void> _play(VideoSource s, {Duration? at, int? requestId}) async {
    final request = requestId ?? ++_openRequest;
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
          createMediaTransport(
            manifest,
            headers: s.headers,
            initialUrl: Uri.parse(s.url),
          ),
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
    final state = Library.instance.chapterState(widget.work.uid, _episode.id);
    final history = Library.instance.historyOf(widget.work.uid);
    final pos =
        state?.position ??
        (chapterKeyOf(history?.chapterId) == _episode.id
            ? history?.position
            : null);
    if (pos == null || pos < 5 || pos > total.inSeconds - 10) return null;
    return Duration(seconds: pos);
  }

  void _onTick() {
    final completed = _c?.value.isCompleted ?? false;
    // Completion ends playback once. Repeated notifications during a replay
    // seek must not overwrite the user's new play request.
    final newlyCompleted = completed && !_completed;
    _completed = completed;
    if (mounted) _playerUpdates.value++;
    if (newlyCompleted) {
      _savePosition();
      if (_wantsPlayback && _episodeIndex < _episodes.length - 1) {
        unawaited(_selectEpisode(_episodes[_episodeIndex + 1]));
      } else {
        _wantsPlayback = false;
      }
    }
  }

  void _savePosition() {
    if (!widget.recordHistory) return;
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    Library.instance.recordVideoPosition(
      widget.work.toItem(),
      (c.value.isCompleted ? c.value.duration : c.value.position).inSeconds,
      episodeId: _episode.id,
      episodeTitle: _episode.title,
      duration: c.value.duration.inSeconds,
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
    final episode = _episode;
    final request = _openRequest;
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
    if (mounted &&
        episode == _episode &&
        request == _openRequest &&
        picked != null &&
        picked != _current) {
      final pos = _c?.value.position;
      _savePosition();
      await _play(picked, at: pos);
    }
  }

  Future<void> _pickEpisode() async {
    _hide?.cancel();
    final picked = await showModalBottomSheet<Chapter>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          VideoEpisodeSheet(work: widget.work, currentId: _episode.id),
    );
    if (!mounted) return;
    if (picked != null && picked.id != _episode.id) {
      await _selectEpisode(picked);
    }
    _scheduleHide();
  }

  Widget _episodeControls({bool overlay = false}) => Row(
    children: [
      IconButton(
        tooltip: tr('上一集'),
        color: overlay ? Colors.white : null,
        disabledColor: overlay ? Colors.white38 : null,
        onPressed: _episodeIndex > 0
            ? () => _selectEpisode(_episodes[_episodeIndex - 1])
            : null,
        icon: const Icon(Icons.skip_previous_rounded),
      ),
      Expanded(
        child: Text(
          _episode.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: overlay ? Colors.white : null),
        ),
      ),
      IconButton(
        tooltip: tr('下一集'),
        color: overlay ? Colors.white : null,
        disabledColor: overlay ? Colors.white38 : null,
        onPressed: _episodeIndex < _episodes.length - 1
            ? () => _selectEpisode(_episodes[_episodeIndex + 1])
            : null,
        icon: const Icon(Icons.skip_next_rounded),
      ),
      IconButton(
        tooltip: tr('选集'),
        color: overlay ? Colors.white : null,
        onPressed: _pickEpisode,
        icon: const Icon(Icons.playlist_play_rounded),
      ),
    ],
  );

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
    final player = AnimatedBuilder(
      animation: _playerUpdates,
      builder: (context, _) => _player(context),
    );
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
            if (_episodes.length > 1) _episodeControls(),
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
        pageVertically: _scrollEpisodes,
        showLevelControls: _controls,
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
            Positioned(
              left: 8,
              right: 8,
              bottom: 0,
              child: SafeArea(
                top: false,
                bottom: _fullscreen,
                child: Listener(
                  onPointerDown: (_) {
                    _hide?.cancel();
                    setState(() => _controls = true);
                  },
                  child: AdaptiveVideoProgress(
                    position: c.value.position,
                    duration: c.value.duration,
                    buffered: c.value.buffered.isEmpty
                        ? Duration.zero
                        : c.value.buffered.last.end,
                    onScrubbingChanged: (scrubbing) {
                      if (scrubbing) {
                        _cancelGesture();
                        _hide?.cancel();
                      } else {
                        _scheduleHide();
                      }
                    },
                    onSeek: (position) => c.seekTo(position),
                  ),
                ),
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
    Widget box = ColoredBox(color: Colors.black, child: inner);
    if (_scrollEpisodes) {
      final active = box;
      box = NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.depth != 0) return false;
          if (notification is ScrollStartNotification) {
            _hide?.cancel();
          }
          if (notification is ScrollEndNotification) {
            _scheduleHide();
          }
          return false;
        },
        child: PageView.builder(
          controller: _episodePages,
          scrollDirection: Axis.vertical,
          itemCount: _episodes.length,
          onPageChanged: (index) {
            if (_episodes[index] != _episode) _selectEpisode(_episodes[index]);
          },
          itemBuilder: (_, index) => index == _episodeIndex
              ? active
              : _preloadedEpisode == _episodes[index] && _nextPreview != null
              ? ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: _nextPreview!.controller.value.aspectRatio,
                      child: VideoPlayer(_nextPreview!.controller),
                    ),
                  ),
                )
              : ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: Text(
                      _episodes[index].title,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
        ),
      );
    }
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
    final displayPosition = _previewPosition ?? v.position;
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
              if (_fullscreen && _episodes.length > 1)
                _episodeControls(overlay: true),
              const Spacer(),
              IconButton(
                tooltip: tr(v.isPlaying ? '暂停' : '播放'),
                iconSize: 40,
                padding: EdgeInsets.zero,
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
                    const Text(' / ', style: TextStyle(color: Colors.white70)),
                    Text(
                      _fmt(v.duration),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    const Spacer(),
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
              const SizedBox(height: 56),
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
