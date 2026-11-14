import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../engine/media_transport.dart';
import 'hls.dart';
import 'hls_syntax.dart';

bool isLocalHlsPackageResource(String path, String playlist) {
  if (isLocalHlsResource(path, '$playlist.part.hls')) return true;
  final tracks = RegExp.escape('$playlist.part.tracks');
  return RegExp(
    '^$tracks/(?:video|audio)\\.m3u8(?:\\.part\\.hls/(?:[0-9]+\\.(?:ts|mp4)|init\\.mp4))?\$',
  ).hasMatch(path);
}

/// 下载和录制共用的包内资源命名，禁止任意路径或外部引用。
bool isLocalHlsResource(String path, String segments) =>
    RegExp('^${RegExp.escape(segments)}/(?:[0-9]+\\.(?:ts|mp4)|init\\.mp4)\$')
        .hasMatch(path);

Future<int> offlineMediaBytes(File file) async {
  final files = file.path.endsWith('.m3u8')
      ? await LocalHlsMedia(file).files()
      : [file];
  var bytes = 0;
  for (final entry in files) {
    bytes += await entry.length();
  }
  return bytes;
}

/// 只读取一个离线下载包；不发起网络请求，不接受播放器指定的文件路径。
class LocalHlsMedia implements MediaTransport {
  LocalHlsMedia(this.playlist);
  final File playlist;
  bool _closed = false;
  static final playlistUrl = Uri.parse(
    'https://offline.park.invalid/index.m3u8',
  );
  String get _name => p.basename(playlist.path);

  /// 校验包内每个引用，供恢复、完整性检查和导出共用。
  Future<List<File>> files() async {
    final root = await playlist.parent.resolveSymbolicLinks();
    final found = <String>{playlistUrl.path};
    final pending = <Uri>[playlistUrl];
    final files = <File>[];
    for (var index = 0; index < pending.length; index++) {
      final url = pending[index];
      validate(url);
      final file = url == playlistUrl
          ? playlist
          : File(p.joinAll([playlist.parent.path, ...url.pathSegments]));
      final actual = await file.resolveSymbolicLinks();
      if (!p.isWithin(root, actual) || await file.length() == 0) {
        throw SourceError('NOT_FOUND', '离线媒体文件缺失或不可读');
      }
      files.add(file);
      if (!url.path.endsWith('.m3u8')) continue;
      final response = await fetch(url, maxBytes: 2 * 1024 * 1024);
      final text = String.fromCharCodes(response.bytes);
      if (hlsLines(text).any((line) => line.startsWith('#EXT-X-STREAM-INF:'))) {
        if (url != playlistUrl) throw SourceError('CONFIG', '离线媒体地址无效');
        await variant();
      } else {
        HlsPlaylist.parse(text, url);
      }
      for (final line in hlsLines(text)) {
        String address;
        if (line.startsWith('#EXT-X-MAP:') ||
            line.startsWith('#EXT-X-MEDIA:')) {
          address =
              hlsAttributes(line.substring(line.indexOf(':') + 1))['URI'] ?? '';
        } else if (line.startsWith('#')) {
          if (RegExp(r'\bURI\s*=', caseSensitive: false).hasMatch(line)) {
            throw SourceError('CONFIG', '离线媒体地址无效');
          }
          continue;
        } else {
          address = line;
        }
        final relative = Uri.tryParse(address);
        if (address.isEmpty ||
            address.startsWith('/') ||
            relative == null ||
            relative.hasScheme ||
            relative.hasQuery ||
            relative.hasFragment ||
            relative.pathSegments.any((s) => s == '..' || s == '.')) {
          throw SourceError('CONFIG', '离线媒体地址无效');
        }
        final resource = url.resolve(address);
        validate(resource);
        if (found.add(resource.path)) pending.add(resource);
        if (pending.length > 100000) throw SourceError('CONFIG', '离线媒体地址无效');
      }
    }
    return files;
  }

  /// 分离音轨包只允许固定的两路本地媒体清单。
  Future<({Uri video, Uri? audio})> variant() async {
    final response = await fetch(playlistUrl, maxBytes: 2 * 1024 * 1024);
    final lines = hlsLines(String.fromCharCodes(response.bytes));
    if (!lines.any((line) => line.startsWith('#EXT-X-STREAM-INF:'))) {
      return (video: playlistUrl, audio: null);
    }
    final directory = '$_name.part.tracks';
    final video = playlistUrl.resolve('$directory/video.m3u8');
    final audio = playlistUrl.resolve('$directory/audio.m3u8');
    final addresses = lines.where((line) => !line.startsWith('#')).toList();
    final groups = lines
        .where((line) => line.startsWith('#EXT-X-MEDIA:'))
        .toList();
    if (addresses.length != 1 ||
        playlistUrl.resolve(addresses.single) != video ||
        groups.length != 1 ||
        playlistUrl.resolve(
              hlsAttributes(
                    groups.single.substring('#EXT-X-MEDIA:'.length),
                  )['URI'] ??
                  '',
            ) !=
            audio) {
      throw SourceError('CONFIG', '离线媒体地址无效');
    }
    validate(video);
    validate(audio);
    return (video: video, audio: audio);
  }

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
    final segment =
        url.path.startsWith('/') &&
        isLocalHlsPackageResource(url.path.substring(1), _name);
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
        : File(p.joinAll([playlist.parent.path, ...url.pathSegments]));
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
