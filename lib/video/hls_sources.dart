import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/models.dart';
import '../engine/media_transport.dart';

/// Expand a muxed HLS master into the actual qualities offered by the CDN.
class HlsSources {
  HlsSources(this.transport);
  final MediaTransport transport;

  Future<List<VideoSource>> resolve(
    List<VideoSource> sources, {
    CancelToken? cancelToken,
  }) async {
    try {
      final resolved = <VideoSource>[];
      for (final source in sources) {
        if (source.format != 'hls') {
          resolved.add(source);
          continue;
        }
        final url = Uri.parse(source.url);
        transport.validate(url);
        final response = await transport.fetch(
          url,
          maxBytes: 2 * 1024 * 1024,
          cancelToken: cancelToken,
        );
        final variants = _variants(utf8.decode(response.bytes), response.url);
        if (variants.isEmpty) {
          resolved.add(source);
          continue;
        }
        for (final variant in variants) {
          transport.validate(Uri.parse(variant.url));
        }
        final preferred = variants
            .firstWhere(
              (s) => s.quality <= source.quality,
              orElse: () => variants.first,
            )
            .quality;
        resolved.addAll(
          variants.map(
            (variant) => VideoSource({
              'url': variant.url,
              'quality': variant.quality,
              'format': 'hls',
              'headers': source.headers,
              'preferred': source.preferred && variant.quality == preferred,
            }),
          ),
        );
      }
      if (cancelToken?.cancelError case final error?) throw error;
      return resolved;
    } finally {
      await transport.close();
    }
  }

  List<VideoSource> _variants(String text, Uri base) {
    final lines = text
        .replaceFirst('\uFEFF', '')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty || lines.first != '#EXTM3U') {
      throw SourceError('NETWORK', 'HLS 分段不完整');
    }
    if (!lines.any((line) => line.startsWith('#EXT-X-STREAM-INF:'))) return [];
    final variants = <int, VideoSource>{};
    int? quality;
    for (final line in lines) {
      if (line.startsWith('#')) {
        if (RegExp(r'\bURI\s*=', caseSensitive: false).hasMatch(line)) {
          throw SourceError('UNSUPPORTED', 'HLS 使用了不支持的媒体格式');
        }
        if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
        if (quality != null || variants.length >= 32) {
          throw SourceError('UNSUPPORTED', 'HLS 使用了不支持的媒体格式');
        }
        final attributes = <String, String>{};
        for (final match in RegExp(
          r'(?:^|,)([A-Z0-9-]+)=("[^"]*"|[^,]*)',
        ).allMatches(line.substring('#EXT-X-STREAM-INF:'.length))) {
          attributes[match[1]!] = match[2]!.replaceAll('"', '');
        }
        if (['AUDIO', 'VIDEO', 'SUBTITLES'].any(
          (key) => attributes.containsKey(key) && attributes[key] != 'NONE',
        )) {
          throw SourceError('UNSUPPORTED', 'HLS 使用了不支持的媒体格式');
        }
        final resolution = RegExp(r'^\d+x(\d+)$')
            .firstMatch(attributes['RESOLUTION'] ?? '');
        quality = resolution == null ? null : int.tryParse(resolution[1]!);
        if (quality == null || quality < 1 || quality > 4320) {
          throw SourceError('UNSUPPORTED', 'HLS 使用了不支持的媒体格式');
        }
      } else {
        if (quality == null) throw SourceError('NETWORK', 'HLS 分段不完整');
        variants.putIfAbsent(
          quality,
          () => VideoSource({
            'quality': quality,
            'url': base.resolve(line).toString(),
            'format': 'hls',
          }),
        );
        quality = null;
      }
    }
    if (quality != null || variants.isEmpty) {
      throw SourceError('NETWORK', 'HLS 分段不完整');
    }
    return variants.values.toList()
      ..sort((a, b) => b.quality.compareTo(a.quality));
  }
}
