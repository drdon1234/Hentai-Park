import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../core/models.dart';
import '../engine/media_transport.dart';
import '../engine/media_transport_factory.dart';
import '../engine/native_media.dart';
import 'hls_download.dart';

String downloadMediaExtension(VideoSource source, {bool keepPlaylist = false}) {
  if (source.format == 'hls') {
    return keepPlaylist || source.audio != null || !Platform.isAndroid
        ? 'm3u8'
        : 'mp4';
  }
  const formats = {
    'mp4',
    'webm',
    'mkv',
    'mov',
    'mp3',
    'm4a',
    'aac',
    'wav',
    'flac',
    'ogg',
    'opus',
  };
  final format = source.format.toLowerCase();
  if (!formats.contains(format)) throw SourceError('UNSUPPORTED', '媒体数据无效');
  return format;
}

/// 只发布完整文件。HLS 分片保留用于取消后的继续下载。
Future<void> downloadMedia(
  SourceManifest manifest,
  VideoSource source,
  File file, {
  required CancelToken cancelToken,
  required void Function(int done, int total, int bytes) onProgress,
  bool keepPlaylist = false,
}) async {
  final part = File('${file.path}.part');
  await file.parent.create(recursive: true);
  if (source.format == 'hls') {
    MediaTransport? transport;
    MediaTransport? soundTransport;
    try {
      transport = createMediaTransport(
        manifest,
        foregroundRecovery: false,
        headers: source.headers,
        initialUrl: Uri.parse(source.url),
        hls: source.hls,
      );
      if (source.audio != null) {
        soundTransport = createMediaTransport(
          manifest,
          foregroundRecovery: false,
          headers: source.headers,
          initialUrl: Uri.parse(source.url),
        );
        authorizeMediaResource(soundTransport, source.audio!.playlist);
      }
      await HlsDownload(
        transport,
        keepPlaylist:
            keepPlaylist || source.audio != null || !Platform.isAndroid,
        audio: source.audio,
        audioTransport: soundTransport,
      ).run(
        Uri.parse(source.url),
        output: part,
        cancelToken: cancelToken,
        onProgress: onProgress,
      );
    } finally {
      await transport?.close();
      await soundTransport?.close();
    }
  } else {
    final transport = NativeMedia(
      MediaPolicy.fromManifest(manifest, initialUrl: Uri.parse(source.url)),
      headers: source.headers,
    );
    try {
      await transport.download(
        Uri.parse(source.url),
        part,
        cancelToken: cancelToken,
        onProgress: (received, total) => onProgress(received, total, received),
      );
      final prefix = await part
          .openRead(0, 64)
          .fold<List<int>>([], (a, b) => a..addAll(b));
      final text = utf8.decode(prefix, allowMalformed: true).trimLeft();
      if (prefix.isEmpty ||
          text.startsWith('<') ||
          text.startsWith('{') ||
          text.startsWith('#EXTM3U')) {
        throw SourceError('PARSE', '视频响应不是可下载的媒体文件');
      }
    } finally {
      await transport.close();
    }
  }
  if (cancelToken.cancelError case final error?) throw error;
  await part.rename(file.path);
}
