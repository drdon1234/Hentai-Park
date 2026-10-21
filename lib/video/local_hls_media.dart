import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../engine/media_transport.dart';

/// 只读取一个离线下载包；不发起网络请求，不接受播放器指定的文件路径。
class LocalHlsMedia implements MediaTransport {
  LocalHlsMedia(this.playlist);
  final File playlist;
  bool _closed = false;
  static final playlistUrl = Uri.parse(
    'https://offline.park.invalid/index.m3u8',
  );
  String get _segments => '${p.basename(playlist.path)}.part.hls';

  @override
  final policy = MediaPolicy.fromManifest(
    SourceManifest({
      'key': 'offline',
      'name': 'Offline',
      'version': '1.0.0',
      'domains': ['offline.park.invalid'],
      'media': {
        'mode': 'native',
        'origin': 'https://offline.park.invalid',
        'domains': ['offline.park.invalid'],
      },
    }),
  );

  @override
  void validate(Uri url) {
    final segment = RegExp(
      '^/${RegExp.escape(_segments)}/[0-9]+\\.(?:ts|mp4)\$',
    ).hasMatch(url.path);
    if (url.scheme != 'https' ||
        url.origin != playlistUrl.origin ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment ||
        (url.path != playlistUrl.path && !segment)) {
      throw SourceError('CONFIG', '离线媒体地址无效');
    }
  }

  @override
  Future<MediaResponse> fetch(
    Uri url, {
    required int maxBytes,
    CancelToken? cancelToken,
  }) async {
    validate(url);
    if (_closed) throw SourceError('CANCELLED', '媒体会话已关闭');
    if (cancelToken?.cancelError case final error?) throw error;
    final file = url == playlistUrl
        ? playlist
        : File(
            p.join(playlist.parent.path, _segments, p.posix.basename(url.path)),
          );
    try {
      final root = await playlist.parent.resolveSymbolicLinks();
      final actual = await file.resolveSymbolicLinks();
      if (!p.isWithin(root, actual) ||
          maxBytes < 1 ||
          maxBytes > 32 * 1024 * 1024) {
        throw SourceError('CONFIG', '离线媒体地址无效');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in file.openRead(0, maxBytes + 1)) {
        if (cancelToken?.cancelError case final error?) throw error;
        if (_closed) throw SourceError('CANCELLED', '媒体会话已关闭');
        bytes.add(chunk);
        if (bytes.length > maxBytes) throw SourceError('NETWORK', '媒体资源过大');
      }
      if (bytes.isEmpty) throw SourceError('NETWORK', '媒体资源为空或不完整');
      return MediaResponse(bytes.takeBytes(), url);
    } on FileSystemException {
      throw SourceError('NOT_FOUND', '离线媒体文件缺失或不可读');
    }
  }

  @override
  Future<void> close() async => _closed = true;
}
