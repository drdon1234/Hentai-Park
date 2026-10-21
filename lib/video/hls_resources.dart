import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/models.dart';
import '../engine/media_transport.dart';
import 'hls.dart';
import 'rou_hls_wrapper.dart';

Uint8List _decodeSegment(
  (Uint8List, Uint8List?, Uint8List?, HlsResourceKind) payload,
) {
  var bytes = unwrapRouHlsIfWrapped(payload.$1);
  if (payload.$2 case final key?) {
    bytes = decryptHlsAes128(bytes, key, payload.$3!);
  }
  validateHlsResource(bytes, payload.$4);
  return bytes;
}

/// Both playback and downloads consume the same validated plaintext resources.
/// Keys belong to this media session and are never written to disk or served.
class HlsResources {
  HlsResources(this.transport, this.cancelToken);
  final MediaTransport transport;
  final CancelToken cancelToken;
  final _keys = <Uri, Future<Uint8List>>{};

  void validate(HlsPlaylist playlist) {
    for (final segment in playlist.resources) {
      authorizeMediaResource(transport, segment.url);
      if (segment.key case final key?) authorizeMediaResource(transport, key);
    }
  }

  void _check() {
    if (cancelToken.cancelError case final error?) throw error;
  }

  Future<Uint8List> read(HlsSegment segment) async {
    _check();
    final response = await transport.fetch(
      segment.url,
      maxBytes: 32 * 1024 * 1024,
      cancelToken: cancelToken,
    );
    _check();
    if (segment.key case final keyUrl?) {
      final pending = _keys.putIfAbsent(keyUrl, () async {
        final response = await transport.fetch(
          keyUrl,
          maxBytes: 16,
          cancelToken: cancelToken,
        );
        _check();
        if (response.bytes.length != 16) {
          throw SourceError('NETWORK', 'HLS 加密密钥无效');
        }
        return response.bytes;
      });
      Uint8List key;
      try {
        key = await pending;
      } catch (_) {
        if (identical(_keys[keyUrl], pending)) _keys.remove(keyUrl)?.ignore();
        rethrow;
      }
      _check();
      // AES 分段可能达到数 MB，同步纯 Dart 解密会阻塞手势与每一帧渲染。
      final plaintext = await compute(_decodeSegment, (
        response.bytes,
        key,
        segment.iv!,
        segment.kind,
      ), debugLabel: 'HLS segment decrypt');
      _check();
      return plaintext;
    }
    if (isRouHlsWrapped(response.bytes)) {
      final plaintext = await compute(_decodeSegment, (
        response.bytes,
        null,
        null,
        segment.kind,
      ), debugLabel: 'HLS segment unwrap');
      _check();
      return plaintext;
    }
    validateHlsResource(response.bytes, segment.kind);
    return response.bytes;
  }

  void clear() => _keys.clear();

  void retainKeys(Set<Uri> keys) {
    _keys.removeWhere((url, _) => !keys.contains(url));
  }
}
