import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/models.dart';
import '../engine/media_transport.dart';
import 'hls_syntax.dart';
import 'rou_hls_wrapper.dart';

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
        final variants = _variants(
          utf8.decode(
            unwrapRouHlsIfWrapped(response.bytes, maxBytes: 2 * 1024 * 1024),
          ),
          response.url,
        );
        if (variants.isEmpty) {
          resolved.add(source);
          continue;
        }
        for (final variant in variants) {
          authorizeMediaResource(transport, Uri.parse(variant.url));
        }
        final preferred = variants.firstWhere(
          (s) => s.quality <= source.quality,
          orElse: () => variants.first,
        );
        resolved.addAll(
          variants.map(
            (variant) => VideoSource({
              'url': variant.url,
              'quality': variant.quality,
              'label': variant.label,
              'format': 'hls',
              'headers': source.headers,
              'preferred': source.preferred && identical(variant, preferred),
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
    final lines = hlsLines(text);
    if (!lines.any((line) => line.startsWith('#EXT-X-STREAM-INF:'))) return [];
    final variants = <({VideoSource source, int bandwidth})>[];
    final seen = <String>{};
    int? quality;
    var bandwidth = 0;
    var count = 0;
    for (final line in lines) {
      if (line.startsWith('#')) {
        // Optional trick-play tracks are not playback variants. Their URIs
        // are never registered or fetched; muxed audio/video remains required.
        if (line.startsWith('#EXT-X-I-FRAME-STREAM-INF:')) continue;
        if (RegExp(r'\bURI\s*=', caseSensitive: false).hasMatch(line)) {
          throw SourceError('UNSUPPORTED', 'HLS 使用了不支持的媒体格式');
        }
        if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
        if (quality != null || ++count > 32) {
          throw SourceError('UNSUPPORTED', 'HLS 使用了不支持的媒体格式');
        }
        final attributes = hlsAttributes(
          line.substring('#EXT-X-STREAM-INF:'.length),
        );
        if (['AUDIO', 'VIDEO', 'SUBTITLES'].any(
          (key) => attributes.containsKey(key) && attributes[key] != 'NONE',
        )) {
          throw SourceError('UNSUPPORTED', 'HLS 使用了不支持的媒体格式');
        }
        final resolution = RegExp(r'^\d+x(\d+)$')
            .firstMatch(attributes['RESOLUTION'] ?? '');
        bandwidth = int.tryParse(attributes['BANDWIDTH'] ?? '') ?? 0;
        quality = attributes.containsKey('RESOLUTION')
            ? (resolution == null ? null : int.tryParse(resolution[1]!))
            : 0;
        if (quality == null ||
            quality < 0 ||
            quality > 4320 ||
            (attributes.containsKey('RESOLUTION') && quality == 0) ||
            (quality == 0 && (bandwidth <= 0 || bandwidth > 10000000000))) {
          throw SourceError('UNSUPPORTED', 'HLS 使用了不支持的媒体格式');
        }
      } else {
        if (quality == null) throw SourceError('NETWORK', 'HLS 分段不完整');
        final key = quality > 0 ? 'height:$quality' : 'bandwidth:$bandwidth';
        if (seen.add(key)) {
          variants.add((
            source: VideoSource({
              'quality': quality,
              if (quality == 0) 'label': '${(bandwidth / 1000).round()} kbps',
              'url': base.resolve(line).toString(),
              'format': 'hls',
            }),
            bandwidth: bandwidth,
          ));
        }
        quality = null;
      }
    }
    if (quality != null || variants.isEmpty) {
      throw SourceError('NETWORK', 'HLS 分段不完整');
    }
    variants.sort((a, b) {
      final height = b.source.quality.compareTo(a.source.quality);
      return height != 0 ? height : b.bandwidth.compareTo(a.bandwidth);
    });
    return variants.map((entry) => entry.source).toList();
  }
}
