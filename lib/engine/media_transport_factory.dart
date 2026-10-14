import '../core/models.dart';
import 'browser_media.dart';
import 'media_transport.dart';
import 'native_media.dart';

MediaTransport createMediaTransport(
  SourceManifest manifest, {
  Map<String, String> headers = const {},
  Uri? initialUrl,
}) {
  final policy = MediaPolicy.fromManifest(manifest, initialUrl: initialUrl);
  return policy.mode == 'browser'
      ? BrowserMedia(policy, headers: headers)
      : NativeMedia(policy, headers: headers);
}
