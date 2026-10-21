import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/models.dart';
import '../engine/media_transport.dart';
import 'hls.dart';

/// 只替换本次点播清单及其引用的密钥，分片继续经过原有媒体传输与内容校验。
class PreparedHlsMedia implements MediaTransport, MediaSessionAuthority {
  PreparedHlsMedia(this.transport, this.url, HlsSourceData data) {
    if (policy.mode != 'native') throw SourceError('CONFIG', '媒体数据无效');
    transport.validate(url);
    final bytes = Uint8List.fromList(utf8.encode(data.manifest));
    if (bytes.length > 2 * 1024 * 1024) throw SourceError('PARSE', '媒体数据无效');
    final playlist = HlsPlaylist.parse(data.manifest, url);
    final referenced = playlist.resources
        .map((s) => s.key)
        .whereType<Uri>()
        .toSet();
    for (final entry in data.keys.entries) {
      final keyUrl = Uri.tryParse(entry.key);
      if (keyUrl == null || keyUrl == url || !referenced.contains(keyUrl)) {
        throw SourceError('PARSE', '媒体数据无效');
      }
      final key = base64.decode(entry.value);
      if (key.length != 16) throw SourceError('PARSE', '媒体数据无效');
      // 授权仍由清单解析后的 HlsResources.validate 执行。
      _data[keyUrl] = key;
    }
    _data[url] = bytes;
  }
  final MediaTransport transport;
  final Uri url;
  final _data = <Uri, Uint8List>{};
  bool _closed = false;

  @override
  MediaPolicy get policy => transport.policy;
  @override
  void validate(Uri url) => transport.validate(url);
  @override
  void authorize(Uri url) => authorizeMediaResource(transport, url);
  @override
  Future<MediaResponse> fetch(
    Uri url, {
    required int maxBytes,
    CancelToken? cancelToken,
  }) async {
    if (_closed) throw SourceError('CANCELLED', '媒体会话已关闭');
    if (cancelToken?.cancelError case final error?) throw error;
    validate(url);
    if (_data[url] case final bytes?) {
      if (maxBytes < 1 || bytes.length > maxBytes) {
        throw SourceError('NETWORK', '媒体数据无效');
      }
      return MediaResponse(Uint8List.fromList(bytes), url);
    }
    return transport.fetch(url, maxBytes: maxBytes, cancelToken: cancelToken);
  }

  @override
  Future<void> close() async {
    _closed = true;
    for (final bytes in _data.values) {
      bytes.fillRange(0, bytes.length, 0);
    }
    _data.clear();
    await transport.close();
  }
}
