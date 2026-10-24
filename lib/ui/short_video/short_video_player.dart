import 'dart:async';

import 'package:dio/dio.dart';
import 'package:video_player/video_player.dart';

import '../../core/app_log.dart';
import '../../core/models.dart';
import '../../core/platform_capabilities.dart';
import '../../engine/cancellation.dart';
import '../../engine/source_manager.dart';
import '../../video/playback.dart';
import '../video/player_initialization.dart';
import 'post_video_feed.dart';
import 'short_video_playback.dart';

class ShortVideoPlayer implements ShortVideoHandle {
  ShortVideoPlayer._(this.controller, this._media);
  final VideoPlayerController controller;
  final Playback? _media;
  Future<void>? _closing;
  static void _check(CancelToken cancel) {
    if (cancel.isCancelled) throw SourceError('CANCELLED', '视频请求已取消');
  }

  static Future<List<VideoSource>> sources(
    WorkItem item,
    CancelToken cancel, {
    bool refresh = false,
    SourceManager? sourceManager,
  }) async {
    final manager = sourceManager ?? SourceManager.instance;
    final media = item.json['media'];
    final attachment = media is List
        ? media.where(isPostVideoAttachment).cast<Map>().firstOrNull
        : null;
    final url = attachment?['url'] as String? ?? '';
    if (url.isEmpty) {
      return awaitCancelled(
        manager.videos(
          item.source,
          item.id,
          episodeId: attachment?['episodeId'] as String?,
          cancelToken: cancel,
          refresh: refresh,
        ),
        cancel,
      );
    }
    return manager.resolveVideoSources(item.source, [
      VideoSource({
        'url': url,
        'format':
            attachment?['format'] ?? (url.contains('.m3u8') ? 'hls' : 'mp4'),
        'headers': attachment?['headers'] ?? {},
        'preferred': true,
        'label': '原画',
      }),
    ], cancelToken: cancel);
  }

  static Future<ShortVideoHandle> open(
    WorkItem item,
    CancelToken cancel, {
    bool refresh = false,
  }) async {
    if (!PlatformCapabilities.nativeVideo) {
      throw SourceError('UNSUPPORTED', '此设备暂不支持短视频播放');
    }
    final manifest = SourceManager.instance.manifest(item.source);
    if (manifest == null) throw SourceError('CONFIG', '站点未加载');
    final resolvedSources = await sources(item, cancel, refresh: refresh);
    _check(cancel);
    if (resolvedSources.isEmpty) {
      throw SourceError('UNSUPPORTED', '此影片暂无可用播放地址');
    }
    // 首选线路失败时依次尝试其余候选。
    Object? failure;
    for (final source in orderedVideoSources(resolvedSources)) {
      try {
        return await _open(item, manifest, source, cancel);
      } on SourceError catch (error) {
        if (cancel.isCancelled || error.code == 'CANCELLED') rethrow;
        failure ??= error;
      }
    }
    throw failure!;
  }

  static Future<ShortVideoHandle> _open(
    WorkItem item,
    SourceManifest manifest,
    VideoSource source,
    CancelToken cancel,
  ) async {
    var uri = Uri.parse(source.url);
    Playback? media;
    VideoPlayerController? controller;
    StreamSubscription<DioException>? cancellation;
    try {
      final opening = media = Playback.network(manifest, source);
      cancellation = cancel.whenCancel.asStream().listen(
        (_) => unawaited(opening.close()),
      );
      uri = await awaitCancelled(opening.open(uri), cancel);
      _check(cancel);
      controller = VideoPlayerController.networkUrl(
        uri,
        videoPlayerOptions: VideoPlayerOptions(),
      );
      await initializePlayer(controller, cancel);
      _check(cancel);
      await awaitCancelled(controller.setLooping(true), cancel);
      _check(cancel);
      return ShortVideoPlayer._(controller, media);
    } catch (error, stack) {
      await (controller?.dispose() ?? Future<void>.value()).whenComplete(
        () async => media?.close(),
      );
      if (!cancel.isCancelled) {
        AppLog.error(
          error,
          event: 'playback',
          site: item.source,
          action: source.format == 'hls' ? 'hls' : 'direct',
          stack: error is SourceError ? null : stack,
        );
      }
      if (error is SourceError) rethrow;
      throw SourceError('NETWORK', '短视频播放失败');
    } finally {
      await cancellation?.cancel();
    }
  }

  @override
  Future<void> play() async {
    if (_closing == null) await controller.play();
  }

  @override
  Future<void> pause() async {
    if (_closing == null) await controller.pause();
  }

  @override
  Future<void> close() => _closing ??= controller.dispose().whenComplete(
    () async => _media?.close(),
  );
}
