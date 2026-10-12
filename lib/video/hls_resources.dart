import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/models.dart';
import '../engine/media_transport.dart';
import 'hls.dart';

/// Both playback and downloads consume the same validated plaintext resources.
/// Keys belong to this media session and are never written to disk or served.
class HlsResources {
  HlsResources(this.transport, this.cancelToken);
  final MediaTransport transport;
  final CancelToken cancelToken;
  final _keys = <Uri, Future<Uint8List>>{};

  void validate(HlsPlaylist playlist) {
    for (final segment in playlist.segments) {
      transport.validate(segment.url);
      if (segment.key case final key?) transport.validate(key);
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
    var plaintext = response.bytes;
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
        if (identical(_keys[keyUrl], pending)) _keys.remove(keyUrl);
        rethrow;
      }
      _check();
      plaintext = decryptHlsAes128(response.bytes, key, segment.iv!);
    }
    _check();
    validateTransportStream(plaintext);
    return plaintext;
  }

  void clear() => _keys.clear();
}
