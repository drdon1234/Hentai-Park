import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:video_player/video_player.dart';

import '../../core/models.dart';
import '../../engine/cancellation.dart';
import '../../engine/media_transport.dart';
import '../../engine/media_transport_factory.dart';
import '../../engine/source_manager.dart';
import '../../video/hls_playback.dart';
import 'short_video_playback.dart';

class ShortVideoPlayer implements ShortVideoHandle {
  ShortVideoPlayer._(this.controller, this._media);
  final VideoPlayerController controller;
  final HlsPlayback? _media;
  Future<void>? _closing;
  static void _check(CancelToken cancel) {
    if (cancel.isCancelled) throw SourceError('CANCELLED', '视频请求已取消');
  }

  static Future<ShortVideoHandle> open(
    WorkItem item,
    CancelToken cancel,
  ) async {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
      throw SourceError('UNSUPPORTED', '此设备暂不支持短视频播放');
    }
    final manifest = SourceManager.instance.manifest(item.source);
    if (manifest == null) throw SourceError('CONFIG', '源未加载');
    final sources = await SourceManager.instance.videos(
      item.source,
      item.id,
      cancelToken: cancel,
    );
    _check(cancel);
    if (sources.isEmpty) throw SourceError('UNSUPPORTED', '此影片暂无可用播放地址');
    final source = sources.firstWhere(
      (s) => s.preferred,
      orElse: () => sources.first,
    );
    final policy = MediaPolicy.fromManifest(
      manifest,
      initialUrl: source.format == 'hls' ? Uri.parse(source.url) : null,
    );
    var uri = Uri.parse(source.url);
    policy.validate(uri);
    final headers = policy.requestHeaders(source.headers);
    HlsPlayback? media;
    VideoPlayerController? controller;
    try {
      if (source.format == 'hls') {
        media = HlsPlayback(
          createMediaTransport(
            manifest,
            headers: headers,
            initialUrl: Uri.parse(source.url),
          ),
        );
        final opening = media;
        unawaited(cancel.whenCancel.then((_) => opening.close()));
        uri = await media.open(uri);
      }
      _check(cancel);
      controller = VideoPlayerController.networkUrl(
        uri,
        httpHeaders: media == null ? headers : const {},
        videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: false),
      );
      await awaitCancelled(
        controller.initialize().timeout(const Duration(seconds: 30)),
        cancel,
      );
      _check(cancel);
      await awaitCancelled(controller.setLooping(true), cancel);
      _check(cancel);
      return ShortVideoPlayer._(controller, media);
    } catch (error) {
      await (controller?.dispose() ?? Future<void>.value()).whenComplete(
        () async => media?.close(),
      );
      if (error is SourceError) rethrow;
      throw SourceError('NETWORK', '短视频播放失败');
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
