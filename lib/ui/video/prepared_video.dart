import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:video_player/video_player.dart';

import '../../core/models.dart';
import '../../engine/cancellation.dart';
import '../../engine/media_transport_factory.dart';
import '../../engine/source_manager.dart';
import '../../library/downloads.dart';
import '../../video/hls_playback.dart';

/// 准备完成前不播放；所有过期请求都释放播放器及其独立媒体会话。
class PreparedVideo {
  PreparedVideo(
    this.controller,
    this.media,
    this.sources,
    this.source,
    this.offline,
  );
  final VideoPlayerController controller;
  final HlsPlayback? media;
  final List<VideoSource> sources;
  final VideoSource? source;
  final bool offline;
  Future<void>? _closing;

  Future<void> close() => _closing ??= controller.dispose().whenComplete(
    () async => media?.close(),
  );

  static Future<PreparedVideo> open(
    WorkDetail work,
    Chapter episode,
    CancelToken cancel, {
    File? localFile,
    List<VideoSource>? initialSources,
  }) async {
    void check() {
      if (cancel.cancelError case final error?) throw error;
    }

    VideoPlayerController? controller;
    HlsPlayback? media;
    StreamSubscription<DioException>? cancellation;
    try {
      final local =
          localFile ??
          await DownloadManager.instance.localVideo(
            work.source,
            work.id,
            episodeId: episode.id,
          );
      check();
      var sources = <VideoSource>[];
      VideoSource? source;
      if (local != null) {
        controller = VideoPlayerController.file(
          local,
          videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: true),
        );
      } else {
        sources =
            initialSources ??
            await SourceManager.instance.videos(
              work.source,
              work.id,
              episodeId: episode.id,
              cancelToken: cancel,
            );
        check();
        if (sources.isEmpty) throw SourceError('UNSUPPORTED', '此影片暂无可用播放地址');
        source = sources.firstWhere(
          (s) => s.preferred,
          orElse: () => sources.first,
        );
        var url = Uri.parse(source.url);
        if (source.format == 'hls') {
          final manifest = SourceManager.instance.manifest(work.source);
          if (manifest == null) throw SourceError('CONFIG', '视频源未加载');
          final opening = media = HlsPlayback(
            createMediaTransport(
              manifest,
              headers: source.headers,
              initialUrl: Uri.parse(source.url),
            ),
          );
          cancellation = cancel.whenCancel.asStream().listen(
            (_) => unawaited(opening.close()),
          );
          url = await awaitCancelled(opening.open(url), cancel);
        }
        check();
        controller = VideoPlayerController.networkUrl(
          url,
          httpHeaders: media == null ? source.headers : const {},
          videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: true),
        );
      }
      await awaitCancelled(
        controller.initialize().timeout(const Duration(seconds: 30)),
        cancel,
      );
      check();
      return PreparedVideo(controller, media, sources, source, local != null);
    } catch (_) {
      await (controller?.dispose() ?? Future<void>.value()).whenComplete(
        () async => media?.close(),
      );
      rethrow;
    } finally {
      await cancellation?.cancel();
    }
  }
}
