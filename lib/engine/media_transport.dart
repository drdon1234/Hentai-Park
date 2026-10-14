import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/models.dart';
import 'domains.dart';

/// Media domains are independent of source cookie domains. Both transports use
/// HTTPS rules; native HLS may explicitly authorize resources within a single session.
/// Neither transport sends application/source credentials.
class MediaPolicy {
  MediaPolicy._(this.mode, this.origin, this.domains, this.session);
  final bool session;
  final Set<Uri> _authorized = {};
  final String mode;
  final String origin;
  final List<String> domains;

  factory MediaPolicy.fromManifest(SourceManifest manifest, {Uri? initialUrl}) {
    final media = manifest.media;
    final mode = media['mode'];
    final session = media['scope'] == 'session';
    final page = Uri.tryParse('${media['origin'] ?? ''}');
    final domains = (media['domains'] as List? ?? const [])
        .map((domain) => '$domain'.toLowerCase())
        .toList();
    if ((mode != 'browser' && mode != 'native') ||
        page == null ||
        page.scheme != 'https' ||
        page.port != 443 ||
        page.userInfo.isNotEmpty ||
        page.hasQuery ||
        page.hasFragment ||
        !_publicHost(page.host) ||
        !hostInDomains(page.host, declaredDomains(manifest.json)) ||
        (domains.isEmpty && !session) ||
        (session && mode != 'native') ||
        domains.any((domain) => !_publicHost(domain))) {
      throw SourceError('CONFIG', '站点没有声明有效的媒体权限');
    }
    final policy = MediaPolicy._(
      '$mode',
      page.origin,
      List.unmodifiable(domains),
      session,
    );
    if (session && initialUrl != null) policy.authorize(initialUrl);
    return policy;
  }

  static bool _publicHost(String host) =>
      RegExp(r'^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\.[a-z]{2,}$').hasMatch(host) &&
      !host
          .split('.')
          .any(
            (label) =>
                label.isEmpty || label.startsWith('-') || label.endsWith('-'),
          ) &&
      host != 'localhost' &&
      !host.endsWith('.localhost') &&
      !host.endsWith('.local');

  void revokeSession() => _authorized.clear();

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
        !_publicHost(url.host) ||
        url.hasFragment) {
      throw SourceError('CONFIG', '媒体地址必须是有效的公网 HTTPS 地址');
    }
  }

  void validate(Uri url) {
    _validateAddress(url);
    if (session
        ? !_authorized.contains(url)
        : !hostInDomains(url.host, domains)) {
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
            url.scheme != 'https' ||
            !url.hasAuthority ||
            url.origin != origin ||
            url.userInfo.isNotEmpty ||
            url.hasFragment ||
            (name == 'origin' && entry.value != origin)) {
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
