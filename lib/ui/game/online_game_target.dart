import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../engine/challenge.dart';
import '../../engine/domains.dart';

String onlineGameProfileKey(String source, String storageId) =>
    sha256.convert(utf8.encode('$source\u0000$storageId')).toString();

/// A transient player target. The site page and user data are not player permissions.
class OnlineGameTarget {
  OnlineGameTarget._(this.url, this.player, this.storageId);

  factory OnlineGameTarget.fromJson(Map<String, dynamic> value, String workId) {
    final kind = value['kind'];
    final url = Uri.tryParse(value['url']?.toString() ?? '');
    final player = Uri.tryParse(value['player']?.toString() ?? '');
    final storageId = (value['storageId'] ?? workId).toString();
    if (!{'html', 'flash'}.contains(kind) ||
        !_safe(url) ||
        storageId.isEmpty ||
        storageId.length > 256 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(storageId) ||
        (kind == 'flash' &&
            (!_safe(player) ||
                player!.host != url!.host ||
                !url.path.toLowerCase().endsWith('.swf')))) {
      throw const FormatException('Invalid online game target');
    }
    return OnlineGameTarget._(url!, kind == 'flash' ? player : null, storageId);
  }

  static bool _safe(Uri? uri) =>
      uri != null &&
      uri.scheme == 'https' &&
      uri.port == 443 &&
      uri.userInfo.isEmpty &&
      publicDomainHost(uri.host) &&
      !RegExp(r'(?:^|\.)(?:internal|test|invalid)$').hasMatch(uri.host);

  final Uri url;
  final Uri? player;
  final String storageId;
  bool get isFlash => player != null;

  Uri get launchUrl => isFlash
      ? Uri(
          scheme: 'https',
          host: url.host,
          path: '/__hentaipark__/ruffle.html',
        )
      : url;

  bool allowsDocument(Uri? uri) => _safe(uri) && uri!.host == url.host;

  bool allowsFrame(Uri? uri) =>
      allowsDocument(uri) ||
      (uri != null &&
          challengeFrameNavigationAllowed(uri, isForMainFrame: false));

  /// Android's asynchronous frame callback does not cover every subframe.
  String get blockedFramePattern =>
      '^(?!https://(?:${RegExp.escape(url.host)}|challenges\\.cloudflare\\.com)(?::443)?(?:[/?#]|\$)).*';
}
