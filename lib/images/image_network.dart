import '../core/models.dart';
import '../engine/domains.dart';
import '../engine/media_transport.dart';
import '../engine/media_transport_factory.dart';

/// 源按需声明图片浏览器传输；复用有界二进制传输，不携带账号凭据。
MediaTransport? createImageTransport(
  SourceManifest? manifest, {
  Map<String, String> headers = const {},
}) {
  final declaration = manifest?.json['imageNetwork'];
  if (declaration == null) return null;
  if (declaration is! Map || declaration['mode'] != 'browser') {
    throw SourceError('CONFIG', '源没有声明有效的媒体权限');
  }
  final domains = declaration['domains'];
  final sourceDomains = declaredDomains(manifest!.json);
  final origin = Uri.tryParse('${declaration['origin'] ?? ''}');
  if (domains is! List ||
      domains.isEmpty ||
      domains.any((d) => d is! String || !hostInDomains(d, sourceDomains)) ||
      origin == null ||
      !hostInDomains(origin.host, domains.cast<String>())) {
    throw SourceError('CONFIG', '源没有声明有效的媒体权限');
  }
  return createMediaTransport(
    SourceManifest({
      ...manifest.json,
      'media': Map<String, dynamic>.from(declaration),
    }),
    headers: headers,
  );
}
