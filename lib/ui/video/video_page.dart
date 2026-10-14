import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/app_lock.dart';
import '../../core/app_log.dart';
import '../../core/localization.dart';
import '../../core/models.dart';
import '../../engine/platform_bridge.dart';
import '../../engine/source_manager.dart';
import '../kit/components.dart';
import '../theme.dart';
import 'video_controls.dart';
import 'video_episode_sheet.dart';
import 'video_gestures.dart';
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
  });
  final WorkDetail work;
  final String? episodeId;
  final List<VideoSource>? initialSources;
  final File? localFile;
  final bool recordHistory;

  /// [work] was rebuilt from stored data (resuming from history or the shelf), so the site's
  /// detail is loaded for the panel below the player: metadata, series and related videos.
  final bool fetchDetails;

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage>
    with WidgetsBindingObserver, _VideoGestures {
  @override
  late final VideoSession _session = VideoSession(
    work: widget.work,
    episodeId: widget.episodeId,
    initialSources: widget.initialSources,
    localFile: widget.localFile,
    recordHistory: widget.recordHistory,
  );
  late final PageController _episodePages;
  WorkDetail? _details;
  bool _controls = true;
  VideoDisplayMode _displayMode = VideoDisplayMode.inline;
  StreamSubscription<double>? _volumeSub;
  Future<void> _screenUpdates = Future.value();

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
    if (widget.fetchDetails) unawaited(_loadDetails());
  }

  Future<void> _loadDetails() async {
    final work = widget.work;
    try {
      final details = await SourceManager.instance.detail(
        work.source,
        work.id,
        preview: work.toItem(),
      );
      if (mounted) setState(() => _details = details);
    } catch (e, stack) {
      // Playback does not depend on it; the panel keeps the stored title and metadata.
      AppLog.error(e, event: 'video_details', site: work.source, stack: stack);
    }
  }

  @override
  void dispose() {
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
    setState(() {});
    // Keep the drama pager on the playing episode, e.g. after auto-advance.
    if (_episodePages.hasClients &&
        _episodePages.page?.round() != _episodeIndex) {
      _episodePages.jumpToPage(_episodeIndex);
    }
  }

  /// The player is about to be replaced: drop gestures and show the controls.
  void _onInterrupt() {
    _hide?.cancel();
    _cancelGesture();
    _controls = true;
  }

  @override
  void didChangeMetrics() => _cancelGesture();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _session.foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      unawaited(_readLevels());
      _updateScreen(_displayMode);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _session.savePosition();
      _cancelGesture();
      PlatformBridge.resetVideoBrightness();
    }
    // Queue playback after all lifecycle observers have updated the app lock.
    _session.syncPlayback();
  }

  void _onLockChanged() {
    if (AppLock.instance.locked) _cancelGesture();
    _session.syncPlayback();
  }

  @override
  void _scheduleHide() {
    _hide?.cancel();
    if (!mounted) return;
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted &&
          _gesture == null &&
          _previewPosition == null &&
          (_session.controller?.value.isPlaying ?? false)) {
        setState(() => _controls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  Future<void> _toggleFullscreen() => _setDisplayMode(
    _fullscreen ? VideoDisplayMode.inline : VideoDisplayMode.portrait,
  );

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

  Future<void> _switchQuality() async {
    final session = _session;
    if (session.sources.length < 2) return;
    final episode = session.episode;
    final generation = session.generation;
    final picked = await showChoiceSheet<VideoSource>(
      context,
      title: tr('清晰度'),
      options: session.sources,
      selected: session.current,
      label: (s) => s.label,
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
    final picked = await showModalBottomSheet<Chapter>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          VideoEpisodeSheet(work: widget.work, currentId: _session.episode.id),
    );
    if (!mounted) return;
    if (picked != null && picked.id != _session.episode.id) {
      await _session.selectEpisode(picked);
    }
    _scheduleHide();
  }

  Future<void> _pickSpeed() async {
    final picked = await showChoiceSheet<double>(
      context,
      title: tr('播放速度'),
      options: const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0],
      selected: _session.speed,
      label: (s) => '${s}x',
    );
    if (mounted && picked != null) await _session.setSpeed(picked);
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

  Widget _controlsLayer(VideoPlayerValue value) => VideoControls(
    value: value,
    position: _previewPosition ?? value.position,
    title: widget.work.title,
    fullscreen: _fullscreen,
    displayMode: _displayMode,
    speed: _session.speed,
    quality: _session.sources.length > 1 ? _session.current?.label : null,
    onQuality: _switchQuality,
    onSpeed: _pickSpeed,
    episodes: _fullscreen && _episodes.length > 1
        ? _episodeBar(overlay: true)
        : null,
    onBack: () =>
        _fullscreen ? _toggleFullscreen() : Navigator.maybePop(context),
    onPlayPause: () {
      _session.togglePlayback();
      _scheduleHide();
    },
    onDisplayMode: _setDisplayMode,
    onFullscreen: _toggleFullscreen,
  );

  @override
  Widget build(BuildContext context) {
    final player = VideoStage(
      session: _session,
      fullscreen: _fullscreen,
      controlsVisible: _controls,
      controls: _controlsLayer,
      episodePages: _episodePages,
      previewPosition: _previewPosition,
      hint: _seekHint,
      dim: !_nativeLevels && _brightness < 1 ? (1 - _brightness) * 0.8 : 0,
      onTap: _toggleControls,
      onDoubleTap: _seekBy,
      onGestureStart: _startGesture,
      onGestureUpdate: _updateGesture,
      onGestureEnd: _endGesture,
      onGestureCancel: _cancelGesture,
      onShowControls: () {
        _hide?.cancel();
        setState(() => _controls = true);
      },
      onInteract: () => _hide?.cancel(),
      onIdle: _scheduleHide,
      onEpisodePage: (index) {
        if (_episodes[index] != _session.episode) {
          _session.selectEpisode(_episodes[index]);
        }
      },
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
      body: SafeArea(
        child: Column(
          children: [
            player,
            if (_episodes.length > 1) _episodeBar(),
            Expanded(
              child: VideoDetails(
                work: _details ?? widget.work,
                offline: _session.offline,
                quality: _session.current?.label,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
