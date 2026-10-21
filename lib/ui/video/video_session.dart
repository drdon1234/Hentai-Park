import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../../core/app_lock.dart';
import '../../core/app_log.dart';
import '../../core/models.dart';
import '../../core/platform_capabilities.dart';
import '../../engine/desktop_shutdown.dart';
import '../../engine/media_transport_factory.dart';
import '../../engine/source_manager.dart';
import '../../images/image_store.dart';
import '../../images/subscription_cache.dart';
import '../../library/downloads.dart';
import '../../library/library.dart';
import '../../video/hls_playback.dart';
import 'player_initialization.dart';
import 'prepared_video.dart';

part 'video_session_drama.dart';

/// The player of one video work: episode choice, source loading, the preloaded next
/// AI-drama episode and resume positions. Every async step checks the open request,
/// so a late result from an earlier episode or source never replaces the current one.
class VideoSession extends ChangeNotifier {
  VideoSession({
    required this.work,
    String? episodeId,
    this.initialSources,
    this.localFile,
    this.recordHistory = true,
  }) : episodes = work.videoEpisodes {
    if (localFile case final file?) SubscriptionCache.instance.retain(file);
    final selected = isLive
        ? episodeId
        : episodeId ?? Library.instance.historyOf(work.uid)?.chapterId;
    episode = episodes.firstWhere(
      (episode) => episode.id == chapterKeyOf(selected),
      orElse: () => episodes.first,
    );
  }

  final WorkDetail work;
  final List<VideoSource>? initialSources;
  final File? localFile;
  final bool recordHistory;
  final List<Chapter> episodes;
  late Chapter episode;

  bool get isLive =>
      localFile == null &&
      SourceManager.instance.manifest(work.source)?.isLive == true;

  /// Called before the player is replaced, so the page can drop gestures and timers.
  VoidCallback? onInterrupt;

  /// Called once a new player is playing, so the page can schedule hiding controls.
  VoidCallback? onStarted;

  /// Ticks on every player update; only the player area listens to it.
  final playerUpdates = ValueNotifier(0);

  VideoPlayerController? controller;
  List<VideoSource> sources = [];
  VideoSource? current;
  Object? error;
  bool offline = false;
  double speed = 1;

  /// Whether the app is in the foreground; playback pauses while it is not.
  bool foreground = true;
  bool _wantsPlayback = true;
  bool _completed = false;
  bool _disposed = false;
  HlsPlayback? _media;
  HlsPlayback? _preparingMedia;
  Timer? _savePos;
  Future<void> _playbackUpdates = Future.value();
  int _request = 0;
  CancelToken? _sourceRequest;
  CancelToken? _openingRequest;
  Chapter? preloadedEpisode;
  CancelToken? _preloadCancel;
  Future<PreparedVideo>? _preloaded;
  PreparedVideo? nextPreview;
  Future<void> _preloadClosing = Future.value();

  static bool get supported => PlatformCapabilities.nativeVideo;

  /// AI dramas page vertically between episodes and preload the next one.
  bool get scrollEpisodes =>
      episodes.length > 1 &&
      (SourceManager.instance.manifest(work.source)?.category ==
              SourceCategory.aiDrama ||
          work.json['category'] == 'aiDrama');

  int get episodeIndex => episodes.indexOf(episode);

  /// Changes whenever a new episode or source is requested.
  int get generation => _request;

  bool get _active => !_disposed;

  void _update() {
    if (_active) notifyListeners();
  }

  Future<void> init() async {
    final request = ++_request;
    try {
      if (!isLive && work.hasVideoEpisodes) {
        await Library.instance.loadChapters(work.uid);
        if (!_active || request != _request) return;
        await Library.instance.syncChapters(
          work.toItem(),
          episodes,
          complete: work.chaptersComplete,
        );
      }
      if (!_active || request != _request) return;
      await selectEpisode(episode);
    } catch (e) {
      if (_active && request == _request) {
        error = e;
        _update();
      }
    }
  }

  Future<void> syncPlayback() {
    final c = controller;
    return _playbackUpdates = _playbackUpdates
        .then((_) async {
          if (!_active || c == null || !identical(c, controller)) return;
          if (foreground && !AppLock.instance.locked && _wantsPlayback) {
            await c.play();
          } else {
            await c.pause();
          }
        })
        .catchError((Object e) {
          if (_active && c != null && identical(c, controller)) {
            error = e;
            _update();
          }
        });
  }

  void togglePlayback() {
    _wantsPlayback = !(controller?.value.isPlaying ?? false);
    unawaited(syncPlayback());
  }

  Future<void> setSpeed(double value) async {
    speed = value;
    await controller?.setPlaybackSpeed(value);
    _update();
  }

  /// Plays [source] from the current position, unless the episode changed meanwhile.
  Future<void> switchSource(VideoSource source) async {
    final position = controller?.value.position;
    savePosition();
    await _play(source, at: position);
  }

  void _resetFor(Chapter next) {
    onInterrupt?.call();
    _savePos?.cancel();
    controller?.removeListener(_onTick);
    episode = next;
    controller = null;
    _media = null;
    sources = [];
    current = null;
    offline = false;
    error = null;
    _completed = false;
    _wantsPlayback = true;
  }

  Future<void> selectEpisode(Chapter next) {
    return PendingDisposals.instance.watch(() async {
      if (scrollEpisodes && supported) return _selectDramaEpisode(next);
      final refreshSources = error != null && next.id == episode.id;
      savePosition();
      _openingRequest?.cancel('video episode changed');
      _sourceRequest?.cancel('video source reloaded');
      final request = _sourceRequest = CancelToken();
      final openRequest = ++_request;
      final old = controller;
      final oldMedia = _media;
      final preparing = _preparingMedia;
      _preparingMedia = null;
      _resetFor(next);
      _update();
      try {
        await preparing?.close();
        await (old?.dispose() ?? Future<void>.value()).whenComplete(
          () async => oldMedia?.close(),
        );
        if (!_active || request.isCancelled || openRequest != _request) return;
        final local = await DownloadManager.instance.localVideo(
          work.source,
          work.id,
          episodeId: next.id,
        );
        if (!_active || request.isCancelled || openRequest != _request) return;
        final playbackFile = localFile ?? local;
        if (playbackFile != null) {
          offline = true;
          if (!supported) {
            current = VideoSource({
              'url': playbackFile.uri.toString(),
              'format': 'mp4',
            });
            _update();
            return;
          }
          if (playbackFile.path.endsWith('.m3u8')) {
            final media = _preparingMedia = HlsPlayback.local(playbackFile);
            try {
              final url = await media.openLocal();
              if (!_active || request.isCancelled || openRequest != _request) {
                await media.close();
                return;
              }
              await _open(
                VideoPlayerController.networkUrl(url),
                media: media,
                requestId: openRequest,
              );
            } catch (_) {
              await media.close();
              rethrow;
            } finally {
              if (identical(_preparingMedia, media)) _preparingMedia = null;
            }
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
        final loaded = initialSources != null
            ? await SourceManager.instance.resolveVideoSources(
                work.source,
                initialSources!,
                cancelToken: request,
              )
            : await SourceManager.instance.videos(
                work.source,
                work.id,
                episodeId: next.id,
                cancelToken: request,
                refresh: refreshSources,
              );
        if (!_active || request.isCancelled || openRequest != _request) return;
        sources = loaded;
        if (loaded.isEmpty) {
          throw SourceError('UNSUPPORTED', '此影片暂无可用播放地址');
        }
        await _play(
          loaded.firstWhere((s) => s.preferred, orElse: () => loaded.first),
          requestId: openRequest,
        );
      } catch (e) {
        if (_active && !request.isCancelled && openRequest == _request) {
          error = e;
          _update();
        }
      } finally {
        if (identical(_sourceRequest, request)) _sourceRequest = null;
      }
    }());
  }

  Future<void> _play(VideoSource s, {Duration? at, int? requestId}) async {
    _openingRequest?.cancel('video source changed');
    final request = requestId ?? ++_request;
    final preparing = _preparingMedia;
    _preparingMedia = null;
    await preparing?.close();
    if (!_active || request != _request) return;
    current = s;
    if (!supported) {
      _update();
      return;
    }
    HlsPlayback? media;
    try {
      var url = Uri.parse(s.url);
      if (s.format == 'hls') {
        final manifest = SourceManager.instance.manifest(work.source);
        if (manifest == null) throw SourceError('CONFIG', '视频站点未加载');
        media = HlsPlayback(
          createMediaTransport(
            manifest,
            headers: s.headers,
            initialUrl: Uri.parse(s.url),
            hls: s.hls,
          ),
          live: manifest.category == SourceCategory.live,
        );
        _preparingMedia = media;
        url = await media.open(url);
      }
      if (!_active || request != _request) {
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
    } catch (e, stack) {
      await media?.close();
      if (_active && request == _request) {
        _logPlayback(e, s.format == 'hls' ? 'hls' : 'direct', stack);
        error = e;
        _update();
      }
    } finally {
      if (identical(_preparingMedia, media)) _preparingMedia = null;
    }
  }

  void _logPlayback(Object error, String action, StackTrace stack) =>
      AppLog.error(
        error,
        event: 'playback',
        site: work.source,
        action: action,
        stack: error is SourceError ? null : stack,
      );

  Future<void> _open(
    VideoPlayerController c, {
    Duration? at,
    HlsPlayback? media,
    int? requestId,
  }) {
    return PendingDisposals.instance.watch(() async {
      final request = requestId ?? ++_request;
      if (!_active || request != _request) {
        await c.dispose();
        await media?.close();
        return;
      }
      _savePos?.cancel();
      onInterrupt?.call();
      final old = controller;
      final oldMedia = _media;
      _media = null;
      old?.removeListener(_onTick);
      controller = null;
      _update();
      await old?.dispose();
      await oldMedia?.close();
      if (!_active || request != _request) {
        await c.dispose();
        await media?.close();
        return;
      }
      _openingRequest?.cancel('video player replaced');
      final cancellation = _openingRequest = CancelToken();
      try {
        await initializePlayer(c, cancellation);
        if (!_active || request != _request) {
          await c.dispose();
          await media?.close();
          return;
        }
        final resume = isLive ? null : (at ?? _resumePoint(c.value.duration));
        if (resume != null) await c.seekTo(resume);
        await c.setPlaybackSpeed(speed);
      } catch (e, stack) {
        await c.dispose();
        await media?.close();
        if (_active && request == _request) {
          _logPlayback(e, 'player', stack);
          error = e is SourceError
              ? e
              : SourceError(
                  'NETWORK',
                  '视频加载失败：{error}',
                  params: {'error': e is SourceError ? e.message : '$e'},
                );
          _update();
        }
        return;
      } finally {
        if (identical(_openingRequest, cancellation)) _openingRequest = null;
      }
      if (!_active || request != _request) {
        await c.dispose();
        await media?.close();
        return;
      }
      c.addListener(_onTick);
      _completed = c.value.isCompleted;
      controller = c;
      _media = media;
      error = null;
      _update();
      await syncPlayback();
      if (!_active || request != _request) return;
      if (!isLive) _startSaving();
      onStarted?.call();
    }());
  }

  void _startSaving() {
    _savePos = Timer.periodic(
      const Duration(seconds: 10),
      (_) => savePosition(),
    );
  }

  Duration? _resumePoint(Duration total) {
    final state = Library.instance.chapterState(work.uid, episode.id);
    final history = Library.instance.historyOf(work.uid);
    final pos =
        state?.position ??
        (chapterKeyOf(history?.chapterId) == episode.id
            ? history?.position
            : null);
    if (pos == null || pos < 5 || pos > total.inSeconds - 10) return null;
    return Duration(seconds: pos);
  }

  void _onTick() {
    final completed = controller?.value.isCompleted ?? false;
    // Completion ends playback once. Repeated notifications during a replay
    // seek must not overwrite the user's new play request.
    final newlyCompleted = completed && !_completed;
    _completed = completed;
    if (_active) playerUpdates.value++;
    if (newlyCompleted) {
      savePosition();
      if (_wantsPlayback && episodeIndex < episodes.length - 1) {
        unawaited(selectEpisode(episodes[episodeIndex + 1]));
      } else {
        _wantsPlayback = false;
      }
    }
  }

  void savePosition() {
    if (!recordHistory || isLive) return;
    final c = controller;
    if (c == null || !c.value.isInitialized) return;
    Library.instance.recordVideoPosition(
      work.toItem(),
      (c.value.isCompleted ? c.value.duration : c.value.position).inSeconds,
      episodeId: episode.id,
      episodeTitle: episode.title,
      duration: c.value.duration.inSeconds,
    );
  }

  @override
  void dispose() {
    savePosition();
    _disposed = true;
    _savePos?.cancel();
    _request++;
    _sourceRequest?.cancel('video page closed');
    _openingRequest?.cancel('video page closed');
    PendingDisposals.instance.add(_discardPreload());
    controller?.removeListener(_onTick);
    playerUpdates.dispose();
    final media = _media;
    PendingDisposals.instance.add(
      (controller?.dispose() ?? Future<void>.value()).whenComplete(() async {
        try {
          await media?.close();
        } finally {
          if (localFile case final file?) {
            SubscriptionCache.instance.release(file);
            await ImageStore.instance.trim();
          }
        }
      }),
    );
    PendingDisposals.instance.add(
      _preparingMedia?.close() ?? Future<void>.value(),
    );
    super.dispose();
  }
}
