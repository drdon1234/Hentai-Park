import 'dart:async';

import '../core/models.dart';
import '../video/prepared_hls_media.dart';
import 'browser_media.dart';
import 'media_transport.dart';
import 'native_media.dart';

MediaTransport createMediaTransport(
  SourceManifest manifest, {
  Map<String, String> headers = const {},
  Uri? initialUrl,
  HlsSourceData? hls,
}) {
  final policy = MediaPolicy.fromManifest(manifest, initialUrl: initialUrl);
  if (hls != null && (initialUrl == null || policy.mode != 'native')) {
    throw SourceError('CONFIG', '媒体数据无效');
  }
  final transport = policy.mode == 'browser'
      ? BrowserMedia(policy, headers: headers)
      : NativeMedia(policy, headers: headers);
  if (hls == null) return transport;
  try {
    return PreparedHlsMedia(transport, initialUrl!, hls);
  } catch (_) {
    unawaited(transport.close());
    rethrow;
  }
}
