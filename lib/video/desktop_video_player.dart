import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Windows 的 video_player 桥接。先交还可释放的句柄，再初始化原生资源。
/// 原生创建或打开失败通过事件报告，不会困住控制器的 creating completer。
class DesktopVideoPlayer extends VideoPlayerPlatform {
  DesktopVideoPlayer({
    Player Function()? playerFactory,
    VideoController Function(Player)? outputFactory,
  }) : _playerFactory = playerFactory ?? Player.new,
       _outputFactory = outputFactory ?? VideoController.new;

  final Player Function() _playerFactory;
  final VideoController Function(Player) _outputFactory;
  final _sessions = <int, _Session>{};
  int _nextId = 0;

  static void register() {
    if (!Platform.isWindows) return;
    MediaKit.ensureInitialized();
    VideoPlayerPlatform.instance = DesktopVideoPlayer();
  }

  @override
  Future<void> init() async {
    await Future.wait(_sessions.keys.toList().map(dispose));
  }

  @override
  Future<int> create(DataSource dataSource) async {
    final id = ++_nextId;
    final session = _sessions[id] = _Session();
    session.opening = Future<void>(() async {
      if (session.closed) return;
      try {
        final player = session.player = _playerFactory();
        final output = session.output = _outputFactory(player);
        session.listen();
        // 输出创建失败同样必须通知 video_player，不能只等待媒体元数据。
        final outputReady = output.platform.future;
        unawaited(outputReady.then<void>((_) {}, onError: session.fail));
        await outputReady;
        if (session.closed) return;
        final resource = switch (dataSource.sourceType) {
          DataSourceType.asset =>
            'asset:///${dataSource.package == null ? '' : 'packages/${dataSource.package}/'}${dataSource.asset}',
          _ => dataSource.uri ?? (throw ArgumentError('Missing video URI')),
        };
        await player.open(
          Media(resource, httpHeaders: dataSource.httpHeaders),
          play: false,
        );
      } catch (error) {
        session.fail(error);
      }
    });
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    final session = _sessions[playerId]!;
    session.eventsClaimed = true;
    return session.events.stream;
  }

  @override
  Future<void> dispose(int playerId) async {
    final session = _sessions[playerId];
    if (session == null) return;
    await session.close();
    _sessions.remove(playerId);
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async =>
      _sessions[playerId]?.player?.setPlaylistMode(
        looping ? PlaylistMode.single : PlaylistMode.none,
      );
  @override
  Future<void> play(int playerId) async => _sessions[playerId]?.player?.play();
  @override
  Future<void> pause(int playerId) async =>
      _sessions[playerId]?.player?.pause();
  @override
  Future<void> setVolume(int playerId, double volume) async =>
      _sessions[playerId]?.player?.setVolume(volume * 100);
  @override
  Future<void> seekTo(int playerId, Duration position) async =>
      _sessions[playerId]?.player?.seek(position);
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async =>
      _sessions[playerId]?.player?.setRate(speed);
  @override
  Future<Duration> getPosition(int playerId) async =>
      _sessions[playerId]?.player?.state.position ?? Duration.zero;
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildView(int playerId) {
    final output = _sessions[playerId]?.output;
    if (output == null) return const SizedBox.shrink();
    return Video(
      key: ValueKey(output),
      controller: output,
      wakelock: false,
      controls: NoVideoControls,
      fill: Colors.transparent,
      pauseUponEnteringBackgroundMode: false,
    );
  }
}

class _Session {
  Player? player;
  VideoController? output;
  final events = StreamController<VideoEvent>();
  final subscriptions = <StreamSubscription<dynamic>>[];
  Future<void> opening = Future.value();
  Future<void>? _closing;
  bool closed = false;
  bool initialized = false;
  bool failed = false;
  bool eventsClaimed = false;

  void emit(VideoEvent event) {
    if (!closed && !failed) events.add(event);
  }

  void fail(Object error, [StackTrace? stack]) {
    if (closed || failed) return;
    failed = true;
    events.addError(
      error is PlatformException
          ? error
          : PlatformException(code: 'VIDEO_PLAYBACK', message: '$error'),
    );
  }

  void listen() {
    final player = this.player!;
    void notify() {
      if (initialized || closed || failed) return;
      final state = player.state;
      final width = state.videoParams.dw;
      final height = state.videoParams.dh;
      final audioOnly =
          state.tracks.video.length <= 2 && state.tracks.audio.length > 2;
      if (state.duration <= Duration.zero ||
          (!audioOnly && (width == null || height == null))) {
        return;
      }
      initialized = true;
      emit(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: state.duration,
          size: audioOnly
              ? Size.zero
              : Size(width!.toDouble(), height!.toDouble()),
        ),
      );
      emit(
        VideoEvent(
          eventType: VideoEventType.isPlayingStateUpdate,
          isPlaying: state.playing,
        ),
      );
    }

    subscriptions.addAll([
      player.stream.duration.listen((_) => notify()),
      player.stream.videoParams.listen((_) => notify()),
      player.stream.tracks.listen((_) => notify()),
      player.stream.error.listen(fail),
      player.stream.playing.listen((value) {
        if (initialized) {
          emit(
            VideoEvent(
              eventType: VideoEventType.isPlayingStateUpdate,
              isPlaying: value,
            ),
          );
        }
      }),
      player.stream.completed.listen((value) {
        if (initialized && value) {
          emit(VideoEvent(eventType: VideoEventType.completed));
        }
      }),
      player.stream.buffering.listen((value) {
        if (initialized) {
          emit(
            VideoEvent(
              eventType: value
                  ? VideoEventType.bufferingStart
                  : VideoEventType.bufferingEnd,
            ),
          );
        }
      }),
      player.stream.buffer.listen((value) {
        if (initialized) {
          emit(
            VideoEvent(
              eventType: VideoEventType.bufferingUpdate,
              buffered: [DurationRange(Duration.zero, value)],
            ),
          );
        }
      }),
    ]);
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    closed = true;
    // open 的原生命令与 dispose 不能竞争；所有迟到事件均已失效。
    await opening;
    await Future.wait(
      subscriptions.map((subscription) => subscription.cancel()),
    );
    try {
      await player?.dispose();
    } finally {
      // 无订阅者时单订阅流的 close 会等待首个订阅者，不能阻塞退出。
      final closing = events.close();
      if (!eventsClaimed) {
        await events.stream.handleError((Object _) {}).drain<void>();
      }
      await closing;
    }
  }
}
