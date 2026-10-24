import '../core/models.dart';
import '../engine/media_transport.dart';
import '../engine/media_transport_factory.dart';
import 'direct_playback.dart';
import 'hls_playback.dart';

/// 播放器只访问本地会话；远端请求由应用传输层负责。
abstract interface class Playback {
  factory Playback.network(
    SourceManifest manifest,
    VideoSource source, {
    bool live = false,
  }) {
    if (source.format == 'hls') {
      return HlsPlayback(
        createMediaTransport(
          manifest,
          headers: source.headers,
          initialUrl: Uri.parse(source.url),
          hls: source.hls,
        ),
        live: live,
        audio: source.audio,
      );
    }
    return DirectPlayback(
      MediaPolicy.fromManifest(manifest, initialUrl: Uri.parse(source.url)),
      headers: source.headers,
    );
  }

  Future<Uri> open(Uri url);
  Future<void> close();
}
