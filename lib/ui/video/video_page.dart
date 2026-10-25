import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/app_lock.dart';
import '../../core/app_log.dart';
import '../../core/danmaku.dart';
import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../engine/live_chat.dart';
import '../../engine/live_chat_protocol.dart';
import '../../engine/platform_bridge.dart';
import '../../engine/source_manager.dart';
import '../kit/adaptive_sheet.dart';
import '../kit/components.dart';
import '../nav.dart';
import '../theme.dart';
import '../web/web_video_page.dart';
import '../widgets/content_translation.dart';
import 'live_chat_overlay.dart';
import 'live_recording_button.dart';
import 'temporary_playback_speed.dart';
import 'video_controls.dart';
import 'video_episode_sheet.dart';
import 'video_gestures.dart';
import 'video_layout.dart';
import 'video_player_input.dart';
import 'video_session.dart';
import 'video_stage.dart';

part 'video_page_gestures.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({
    super.key,
    required this.work,
    this.episodeId,
    this.initialSources,
    this.localFile,
    this.recordHistory = true,
    this.fetchDetails = false,
    this.downloadedOnly = false,
  });
  final WorkDetail work;
  final String? episodeId;
  final List<VideoSource>? initialSources;
  final File? localFile;
  final bool recordHistory;

  /// [work] was rebuilt from stored data (resuming from history or the shelf), so the site's
  /// detail is loaded for the panel below the player: metadata, series and related videos.
  final bool fetchDetails;
  final bool downloadedOnly;

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage>
    with WidgetsBindingObserver, RouteAware, _VideoGestures {
  @override
  late final VideoSession _session = VideoSession(
    work: widget.work,
    episodeId: widget.episodeId,
    initialSources: widget.initialSources,
    localFile: widget.localFile,
    recordHistory: widget.recordHistory,
    downloadedOnly: widget.downloadedOnly,
  );
  late final PageController _episodePages;
  WorkDetail? _details;
  bool _controls = true;
  int _openPanels = 0;
  bool _menuOpen = false;
  bool _interacting = false;
  VideoDisplayMode _displayMode = VideoDisplayMode.inline;
  StreamSubscription<double>? _volumeSub;
  Future<void> _screenUpdates = Future.value();
  final _detailsRequest = CancelToken();
  bool _webFallbackScheduled = false;
  double _unmutedVolume = 1;
  ModalRoute<dynamic>? _route;
  LiveChatSession? _liveChat;
  bool _chatEnabled = true;
  TemporaryPlaybackSpeed? _temporarySpeed;
  Future<void> _speedUpdates = Future.value();

  List<Chapter> get _episodes => _session.episodes;
  int get _episodeIndex => _session.episodeIndex;
  bool get _fullscreen => _displayMode != VideoDisplayMode.inline;

  @override
  void initState() {
    super.initState();
    _episodePages = PageController(initialPage: _episodeIndex);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _session
      ..foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed
      ..onInterrupt = _onInterrupt
      ..onStarted = _scheduleHide
      ..addListener(_onSession);
    WidgetsBinding.instance.addObserver(this);
    AppLock.instance.addListener(_onLockChanged);
    WakelockPlus.enable();
    _volumeSub = PlatformBridge.mediaVolumeChanges.listen((volume) {
      if (mounted) setState(() => _volume = volume);
    });
    unawaited(_readLevels());
    _session.init();
    _syncLiveChat();
    if (widget.fetchDetails && !widget.downloadedOnly) {
      unawaited(_loadDetails());
    }
  }

  Future<void> _loadDetails() async {
    final work = widget.work;
    try {
      final details = await SourceManager.instance.detail(
        work.source,
        work.id,
        preview: work.toItem(),
        cancelToken: _detailsRequest,
      );
      if (mounted) setState(() => _details = details);
    } catch (e, stack) {
      if (_detailsRequest.isCancelled) return;
      // Playback does not depend on it; the panel keeps the stored title and metadata.
      AppLog.error(e, event: 'video_details', site: work.source, stack: stack);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (identical(route, _route)) return;
    Nav.routeObserver.unsubscribe(this);
    _route = route;
    _session.visible = route?.isCurrent ?? true;
    _syncLiveChat();
    if (route is PageRoute<dynamic>) Nav.routeObserver.subscribe(this, route);
    unawaited(_session.syncPlayback());
  }

  @override
  void didPushNext() => _setRouteVisible(false);

  @override
  void didPopNext() => _setRouteVisible(true);

  @override
  void didPop() => _setRouteVisible(false);

  void _setRouteVisible(bool visible) {
    _session.visible = visible;
    _syncLiveChat();
    if (visible) {
      unawaited(_readLevels());
      unawaited(_updateScreen(_displayMode));
      _scheduleHide();
    } else {
      _endTemporarySpeed();
      _session.savePosition();
      _cancelGesture();
      _hide?.cancel();
    }
    unawaited(_session.syncPlayback());
  }

  @override
  void dispose() {
    _endTemporarySpeed();
    _liveChat?.dispose();
    Nav.routeObserver.unsubscribe(this);
    _detailsRequest.cancel('video page closed');
    _episodePages.dispose();
    _hide?.cancel();
    _hintTimer?.cancel();
    _volumeSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    AppLock.instance.removeListener(_onLockChanged);
    _session
      ..removeListener(_onSession)
      ..dispose();
    WakelockPlus.disable();
    PlatformBridge.resetVideoBrightness();
    _updateScreen(VideoDisplayMode.inline);
    super.dispose();
  }

  void _onSession() {
    if (!mounted) return;
    _syncLiveChat();
    final manifest = SourceManager.instance.manifest(widget.work.source);
    if (widget.localFile == null &&
        !widget.downloadedOnly &&
        !_webFallbackScheduled &&
        manifest?.shouldFallbackToWebVideo(_session.error) == true) {
      _webFallbackScheduled = true;
      final generation = _session.generation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _webFallbackScheduled = false;
        if (generation != _session.generation ||
            manifest?.shouldFallbackToWebVideo(_session.error) != true ||
            ModalRoute.of(context)?.isCurrent != true) {
          return;
        }
        Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute(
            builder: (_) => TranslationPage(
              child: WebVideoPage(
                work: widget.work,
                episodeId: _session.episode.id,
              ),
            ),
          ),
        );
      });
    }
    setState(() {});
    // Keep the drama pager on the playing episode, e.g. after auto-advance.
    if (_episodePages.hasClients &&
        _episodePages.page?.round() != _episodeIndex) {
      _episodePages.jumpToPage(_episodeIndex);
    }
  }

  /// The player is about to be replaced: drop gestures and show the controls.
  void _onInterrupt() {
    _interacting = false;
    _hide?.cancel();
    _cancelGesture();
    _controls = true;
  }

  @override
  void didChangeMetrics() {
    _endTemporarySpeed();
    _cancelGesture();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _session.foreground = state == AppLifecycleState.resumed;
    _syncLiveChat();
    if (state == AppLifecycleState.resumed) {
      unawaited(_readLevels());
      _updateScreen(_displayMode);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _endTemporarySpeed();
      _session.savePosition();
      _cancelGesture();
      PlatformBridge.resetVideoBrightness();
    }
    // Queue playback after all lifecycle observers have updated the app lock.
    _session.syncPlayback();
  }

  void _onLockChanged() {
    _syncLiveChat();
    if (AppLock.instance.locked) {
      _endTemporarySpeed();
      _cancelGesture();
    }
    _session.syncPlayback();
  }

  void _syncLiveChat() {
    final manifest = SourceManager.instance.manifest(widget.work.source);
    final supported = _session.isLive && manifest?.can('liveChat') == true;
    if (!supported) {
      _liveChat?.dispose();
      _liveChat = null;
      return;
    }
    _liveChat ??= LiveChatSession(
      source: widget.work.source,
      room: widget.work.id,
      domains: liveChatDomains(manifest!.json),
    );
    _liveChat!.setActive(
      _chatEnabled &&
          _session.foreground &&
          _session.visible &&
          !AppLock.instance.locked &&
          _session.error == null,
    );
  }

  void _toggleChat() {
    setState(() => _chatEnabled = !_chatEnabled);
    _syncLiveChat();
  }

  Future<void> _pickChatArea() async {
    _hide?.cancel();
    final picked = await _withVisibleControls(
      () => showChoiceSheet<DanmakuArea>(
        context,
        title: tr('弹幕显示区域'),
        options: DanmakuArea.values,
        selected: AppSettings.instance.danmakuArea,
        label: (area) => area.label,
      ),
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() => AppSettings.instance.danmakuArea = picked);
    }
    _scheduleHide();
  }

  @override
  void _scheduleHide() {
    _hide?.cancel();
    if (!mounted || _openPanels > 0 || _menuOpen || _interacting) return;
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted &&
          _gesture == null &&
          _previewPosition == null &&
          (_session.controller?.value.isPlaying ?? false)) {
        setState(() => _controls = false);
      }
    });
  }

  Future<T?> _withVisibleControls<T>(Future<T?> Function() show) async {
    _openPanels++;
    _hide?.cancel();
    try {
      return await show();
    } finally {
      _openPanels--;
      if (mounted) _scheduleHide();
    }
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  void _showControls() {
    if (!_controls) setState(() => _controls = true);
    _scheduleHide();
  }

  void _togglePlayback() {
    _session.togglePlayback();
    _showControls();
  }

  void _changeVolume(double delta) {
    final controller = _session.controller;
    if (controller == null || !controller.value.isInitialized) return;
    final volume = _nativeLevels ? _volume : controller.value.volume;
    _setVolume((volume + delta).clamp(0.0, 1.0));
  }

  void _toggleMute() {
    final controller = _session.controller;
    if (controller == null || !controller.value.isInitialized) return;
    final volume = _nativeLevels ? _volume : controller.value.volume;
    if (volume > 0) {
      _unmutedVolume = volume;
      _setVolume(0);
    } else {
      _setVolume(_unmutedVolume);
    }
  }

  void _setVolume(double volume) {
    setState(() {
      _volume = volume;
      _seekHint = tr('音量 {percent}%', {'percent': (volume * 100).round()});
    });
    if (_nativeLevels) {
      PlatformBridge.setVideoVolume(volume);
    } else {
      _session.controller?.setVolume(volume);
    }
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _seekHint = null);
    });
    _showControls();
  }

  Future<void> _toggleFullscreen() => _setDisplayMode(
    _fullscreen
        ? VideoDisplayMode.inline
        : (_session.controller?.value.aspectRatio ?? 16 / 9) >= 1
        ? VideoDisplayMode.landscape
        : VideoDisplayMode.portrait,
  );

  Future<void> _setDisplayMode(VideoDisplayMode mode) async {
    _interacting = false;
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
          if (mounted && !_session.visible) return;
          if (!mounted && mode != VideoDisplayMode.inline) return;
          await SystemChrome.setPreferredOrientations(videoOrientations(mode));
          await PlatformBridge.applyVideoFullscreen(
            mode != VideoDisplayMode.inline,
            landscape: mode == VideoDisplayMode.landscape,
          );
        })
        .catchError((Object _) {});
  }

  Future<void> _switchQuality() async {
    final session = _session;
    if (session.sources.length < 2) return;
    final episode = session.episode;
    final generation = session.generation;
    final picked = await _withVisibleControls(
      () => showChoiceSheet<VideoSource>(
        context,
        title: tr('清晰度'),
        options: session.sources,
        selected: session.current,
        label: (s) => s.label,
      ),
    );
    if (mounted &&
        episode == session.episode &&
        generation == session.generation &&
        picked != null &&
        picked != session.current) {
      await session.switchSource(picked);
    }
  }

  Future<void> _pickEpisode() async {
    _hide?.cancel();
    final picked = await _withVisibleControls(
      () => showAdaptiveSheet<Chapter>(
        context: context,
        isScrollControlled: true,
        builder: (_) => VideoEpisodeSheet(
          work: widget.work,
          currentId: _session.episode.id,
        ),
      ),
    );
    if (!mounted) return;
    if (picked != null && picked.id != _session.episode.id) {
      await _session.selectEpisode(picked);
    }
    _scheduleHide();
  }

  Future<void> _pickSpeed() async {
    _hide?.cancel();
    final picked = await _withVisibleControls(
      () => showChoiceSheet<double>(
        context,
        title: tr('播放速度'),
        options: const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0],
        selected: _session.speed,
        label: (s) => '${s}x',
      ),
    );
    if (mounted && picked != null) await _session.setSpeed(picked);
    if (mounted) _scheduleHide();
  }

  void _queueSpeed(double speed) {
    _speedUpdates = _speedUpdates.then((_) => _session.setSpeed(speed));
  }

  void _startTemporarySpeed() {
    if (_session.isLive || _temporarySpeed != null) return;
    final temporary = TemporaryPlaybackSpeed(_session.speed);
    _temporarySpeed = temporary;
    _queueSpeed(temporary.press());
  }

  void _endTemporarySpeed() {
    final temporary = _temporarySpeed;
    if (temporary == null) return;
    _temporarySpeed = null;
    _queueSpeed(temporary.release());
  }

  Widget _episodeBar({bool overlay = false}) => VideoEpisodeBar(
    title: _session.episode.title,
    overlay: overlay,
    onPrevious: _episodeIndex > 0
        ? () => _session.selectEpisode(_episodes[_episodeIndex - 1])
        : null,
    onNext: _episodeIndex < _episodes.length - 1
        ? () => _session.selectEpisode(_episodes[_episodeIndex + 1])
        : null,
    onPick: _pickEpisode,
  );

  Widget _controlsLayer(VideoPlayerValue value, Widget progress) =>
      VideoControls(
        progress: _session.isLive ? null : progress,
        live: _session.isLive,
        chatEnabled: _chatEnabled,
        onToggleChat: _liveChat == null ? null : _toggleChat,
        chatAreaLabel: AppSettings.instance.danmakuArea.label,
        onChatArea: _liveChat == null ? null : _pickChatArea,
        recordingAction: _session.isLive && _fullscreen
            ? LiveRecordingButton(
                item: widget.work.toItem(),
                color: Colors.white,
              )
            : null,
        value: value,
        position: _previewPosition ?? value.position,
        title: widget.work.title,
        fullscreen: _fullscreen,
        displayMode: _displayMode,
        speed: _session.speed,
        quality: _session.sources.length > 1 ? _session.current?.label : null,
        onQuality: _switchQuality,
        onSpeed: _pickSpeed,
        onEpisodes: _episodes.length > 1 ? _pickEpisode : null,
        onPrevious: _episodeIndex > 0
            ? () => _session.selectEpisode(_episodes[_episodeIndex - 1])
            : null,
        onNext: _episodeIndex < _episodes.length - 1
            ? () => _session.selectEpisode(_episodes[_episodeIndex + 1])
            : null,
        onInteractionChanged: (active) {
          _menuOpen = active;
          if (active) {
            _hide?.cancel();
          } else {
            _scheduleHide();
          }
        },
        onBack: () =>
            _fullscreen ? _toggleFullscreen() : Navigator.maybePop(context),
        onPlayPause: _togglePlayback,
        onDisplayMode: _setDisplayMode,
        onFullscreen: _toggleFullscreen,
      );

  @override
  Widget build(BuildContext context) {
    final player = VideoPlayerInput(
      onPlayPause: _togglePlayback,
      onSeek: _seekBy,
      onVolume: _changeVolume,
      onMute: _toggleMute,
      onFullscreen: _toggleFullscreen,
      onExitFullscreen: () {
        if (_fullscreen) _toggleFullscreen();
      },
      onTemporarySpeedStart: _startTemporarySpeed,
      onTemporarySpeedEnd: _endTemporarySpeed,
      child: MouseRegion(
        onHover: (_) => _showControls(),
        child: VideoStage(
          liveChat: _chatEnabled && _liveChat != null
              ? LiveChatOverlay(
                  session: _liveChat!,
                  area: AppSettings.instance.danmakuArea,
                  vpnHint:
                      SourceManager.instance
                          .manifest(widget.work.source)
                          ?.network['vpnHint'] ==
                      true,
                )
              : null,
          session: _session,
          fullscreen: _fullscreen,
          controlsVisible: _controls,
          controls: _controlsLayer,
          episodePages: _episodePages,
          previewPosition: _previewPosition,
          hint: _seekHint,
          dim: !_nativeLevels && _brightness < 1 ? (1 - _brightness) * 0.8 : 0,
          onTap: _toggleControls,
          onMouseTap: _showControls,
          onDoubleTap: _togglePlayback,
          onLongPressStart: _startTemporarySpeed,
          onLongPressEnd: _endTemporarySpeed,
          onLongPressCancel: _endTemporarySpeed,
          onGestureStart: _startGesture,
          onGestureUpdate: _updateGesture,
          onGestureEnd: _endGesture,
          onGestureCancel: _cancelGesture,
          onShowControls: () {
            _hide?.cancel();
            setState(() => _controls = true);
          },
          onInteract: () {
            _interacting = true;
            _hide?.cancel();
          },
          onIdle: () {
            _interacting = false;
            _scheduleHide();
          },
          onEpisodePage: (index) {
            if (_episodes[index] != _session.episode) {
              _session.selectEpisode(_episodes[index]);
            }
          },
        ),
      ),
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
    return Scaffold(
      backgroundColor: context.colors.surface,
      appBar: AppBar(
        title: Text(tr('播放')),
        actions: [
          TranslationControls(source: widget.work.source),
          if (_session.isLive) LiveRecordingButton(item: widget.work.toItem()),
        ],
      ),
      body: SafeArea(
        child: VideoLayout(
          player: player,
          header: VideoDetails(
            episodeId: _session.episode.id,
            work: _details ?? widget.work,
            offline: widget.downloadedOnly || _session.offline,
            quality: _session.current?.label,
            showRelated: false,
          ),
          sidebar: _episodes.length > 1 ? _episodeBar() : null,
          details: VideoDetails(
            episodeId: _session.episode.id,
            work: _details ?? widget.work,
            showHeader: false,
            offline: widget.downloadedOnly || _session.offline,
            showRelated: !widget.downloadedOnly,
          ),
        ),
      ),
    );
  }
}
