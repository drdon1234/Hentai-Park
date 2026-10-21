import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/models.dart';
import 'domains.dart';

/// Media domains are independent of source cookie domains. Both transports use
/// HTTPS rules; native HLS may explicitly authorize resources within a single session.
/// 浏览器图片仅在源内同源地址使用站点会话；视频和跨域请求不携带凭据。
class MediaPolicy {
  MediaPolicy._(
    this.site,
    this.mode,
    this.origin,
    this.domains,
    this.session,
    this.sourceDomains,
    this.documentDomains,
    this.sameOriginCredentials,
    this.referrerDomains,
  );

  /// The source key, for diagnostics.
  final String site;
  final bool session;
  final Set<Uri> _authorized = {};
  final String mode;
  final String origin;
  final List<String> domains;
  final List<String> sourceDomains;
  final List<String> documentDomains;
  final bool sameOriginCredentials;
  final List<String> referrerDomains;

  bool allowsDocument(Uri? url) =>
      httpsDomainAddressAllowed(url, documentDomains);

  factory MediaPolicy.fromManifest(
    SourceManifest manifest, {
    Uri? initialUrl,
    bool image = false,
  }) {
    final declaration = image ? manifest.json['imageNetwork'] : manifest.media;
    if (declaration is! Map) {
      throw SourceError('CONFIG', '站点没有声明有效的媒体权限');
    }
    final media = declaration;
    final mode = media['mode'];
    final session = media['scope'] == 'session';
    final rawDomains = media['domains'];
    final rawReferrers = media['referrerDomains'];
    if ((rawDomains != null && rawDomains is! List) ||
        (rawDomains is List && rawDomains.any((domain) => domain is! String)) ||
        (rawReferrers != null &&
            (rawReferrers is! List ||
                mode != 'native' ||
                image ||
                rawReferrers.length > 16 ||
                rawReferrers.any(
                  (domain) => domain is! String || !publicDomainHost(domain),
                ))) ||
        (media['scope'] != null && !session) ||
        media['origin'] is! String) {
      throw SourceError('CONFIG', '站点没有声明有效的媒体权限');
    }
    final page = Uri.tryParse(media['origin'] as String);
    final sourceDomains = declaredDomains(manifest.json);
    final domains = (rawDomains as List? ?? const [])
        .cast<String>()
        .map((domain) => domain.toLowerCase())
        .toList();
    if ((mode != 'browser' && mode != 'native') ||
        page == null ||
        page.scheme != 'https' ||
        page.port != 443 ||
        page.userInfo.isNotEmpty ||
        page.hasQuery ||
        page.hasFragment ||
        !publicDomainHost(page.host) ||
        !(hostInDomains(page.host, sourceDomains) ||
            (image && hostInDomains(page.host, domains))) ||
        (domains.isEmpty && !session) ||
        (session && mode != 'native') ||
        (image && (mode != 'browser' || session)) ||
        domains.any((domain) => !publicDomainHost(domain))) {
      throw SourceError('CONFIG', '站点没有声明有效的媒体权限');
    }
    final policy = MediaPolicy._(
      manifest.key,
      '$mode',
      page.origin,
      List.unmodifiable(domains),
      session,
      List.unmodifiable(sourceDomains),
      List.unmodifiable(
        hostInDomains(page.host, sourceDomains) ? sourceDomains : domains,
      ),
      image && hostInDomains(page.host, sourceDomains),
      List.unmodifiable((rawReferrers as List? ?? const []).cast<String>()),
    );
    if (session && initialUrl != null) policy.authorize(initialUrl);
    return policy;
  }

  void revokeSession() => _authorized.clear();

  /// 直播窗口移出后撤销旧资源，避免长时间播放积累无限授权。
  void retainSessionResources(Set<Uri> resources) {
    _authorized.removeWhere((url) => !resources.contains(url));
  }

  void authorize(Uri url) {
    if (!session) {
      validate(url);
      return;
    }
    _validateAddress(url);
    _authorized.add(url);
  }

  void _validateAddress(Uri url) {
    if (url.scheme != 'https' ||
        url.port != 443 ||
        url.userInfo.isNotEmpty ||
        !publicDomainHost(url.host) ||
        url.hasFragment) {
      throw SourceError('CONFIG', '媒体地址必须是有效的公网 HTTPS 地址');
    }
  }

  void validate(Uri url) {
    _validateAddress(url);
    if (!hostInDomains(url.host, domains) &&
        !(session && _authorized.contains(url))) {
      throw SourceError(
        'CONFIG',
        session ? '媒体地址未由当前播放接口或清单授权' : '媒体地址不在站点声明的 HTTPS 域名内',
      );
    }
  }

  Map<String, String> requestHeaders(Map<String, String> supplied) {
    final result = <String, String>{};
    for (final entry in supplied.entries) {
      final name = entry.key.toLowerCase();
      if (!const {
            'referer',
            'origin',
            'accept',
            'accept-language',
          }.contains(name) ||
          entry.value.contains('\r') ||
          entry.value.contains('\n') ||
          result.keys.any((existing) => existing.toLowerCase() == name)) {
        throw SourceError('CONFIG', '媒体请求包含不允许的请求头');
      }
      if (name == 'referer' || name == 'origin') {
        final url = Uri.tryParse(entry.value);
        if (url == null ||
            !httpsDomainAddressAllowed(url, {
              ...sourceDomains,
              ...documentDomains,
              if (name == 'referer') ...referrerDomains,
            }) ||
            url.hasFragment ||
            (name == 'origin' && entry.value != url.origin)) {
          throw SourceError('CONFIG', '媒体请求头不在站点声明的地址内');
        }
      }
      result[entry.key] = entry.value;
    }
    return Map.unmodifiable(result);
  }
}

class MediaResponse {
  const MediaResponse(this.bytes, this.url);
  final Uint8List bytes;
  final Uri url;
}

abstract interface class MediaTransport {
  MediaPolicy get policy;
  void validate(Uri url);
  Future<MediaResponse> fetch(
    Uri url, {
    required int maxBytes,
    CancelToken? cancelToken,
  });
  Future<void> close();
}

/// Only native dynamic sessions implement this authority; static transports retain validation.
abstract interface class MediaSessionAuthority {
  void authorize(Uri url);
}

void authorizeMediaResource(MediaTransport transport, Uri url) {
  if (transport is MediaSessionAuthority) {
    (transport as MediaSessionAuthority).authorize(url);
  } else {
    transport.validate(url);
  }
}
