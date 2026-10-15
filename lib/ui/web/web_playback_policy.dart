import '../../engine/domains.dart';

/// Page navigation permissions, independent of plugin HTTP and Cookie access.
class WebPlaybackPolicy {
  WebPlaybackPolicy(
    this.url, {
    Iterable<String> navigationDomains = const [],
    Iterable<String> frameDomains = const [],
  }) : navigationDomains = {registrableDomain(url.host), ...navigationDomains},
       frameDomains = {...frameDomains} {
    if (!safeUri(url) ||
        [
          ...this.navigationDomains,
          ...this.frameDomains,
        ].any((domain) => !safeUri(Uri(scheme: 'https', host: domain)))) {
      throw const FormatException('Invalid web playback target');
    }
  }

  factory WebPlaybackPolicy.fromJson(Map<String, dynamic> json) =>
      WebPlaybackPolicy(
        Uri.parse(json['url'] as String),
        navigationDomains: (json['navigationDomains'] as List? ?? const [])
            .cast<String>(),
        frameDomains: (json['frameDomains'] as List? ?? const [])
            .cast<String>(),
      );

  final Uri url;
  final Set<String> navigationDomains;
  final Set<String> frameDomains;

  static bool safeUri(Uri uri) =>
      uri.scheme == 'https' &&
      uri.port == 443 &&
      uri.userInfo.isEmpty &&
      RegExp(r'^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,63}$')
          .hasMatch(uri.host) &&
      !RegExp(r'(?:^|\.)(?:localhost|local|internal|test|invalid)$')
          .hasMatch(uri.host);

  bool allowsMainFrame(Uri uri) =>
      safeUri(uri) && hostInDomains(uri.host, navigationDomains);

  bool allowsFrame(Uri uri) =>
      safeUri(uri) &&
      hostInDomains(uri.host, {...navigationDomains, ...frameDomains});

  /// Android 的异步导航回调不会拦截子框架，必须同时使用原生正则规则。
  String get blockedFramePattern {
    final domains = {
      ...navigationDomains,
      ...frameDomains,
    }.map(RegExp.escape).join('|');
    return '^(?!https://(?:[a-z0-9-]+\\.)*(?:$domains)(?::443)?(?:[/?#]|\$)).*';
  }
}
