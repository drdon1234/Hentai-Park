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
          if (variant.audio case final audio?) {
            authorizeMediaResource(transport, audio.playlist);
          }
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
            }, audio: variant.audio),
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
    final audio = _audioGroups(lines, base);
    final variants = <({VideoSource source, int bandwidth})>[];
    final seen = <String>{};
    int? quality;
    HlsAudioVariant? separate;
    var bandwidth = 0;
    var count = 0;
    for (final line in lines) {
      if (line.startsWith('#')) {
        // Optional trick-play tracks, renditions and session metadata are not
        // playback variants. Only the selected audio rendition is registered.
        if (line.startsWith('#EXT-X-I-FRAME-STREAM-INF:') ||
            line.startsWith('#EXT-X-MEDIA:') ||
            line.startsWith('#EXT-X-SESSION-DATA:')) {
          continue;
        }
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
        // 字幕与隐藏字幕不加载；视频分组的独立地址已在解析分组时拒绝。
        final group = attributes['AUDIO'];
        if (group != null && !audio.containsKey(group)) {
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
        final codecs = attributes['CODECS'];
        separate = switch (audio[group]) {
          final playlist? => HlsAudioVariant(
            playlist: playlist,
            bandwidth: bandwidth > 0 ? bandwidth : 1,
            codecs:
                codecs != null &&
                    RegExp(r'^[A-Za-z0-9.+-]+(?:,[A-Za-z0-9.+-]+)*$')
                        .hasMatch(codecs) &&
                    codecs.length <= 256
                ? codecs
                : null,
            resolution: resolution == null ? null : attributes['RESOLUTION'],
          ),
          null => null,
        };
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
            }, audio: separate),
            bandwidth: bandwidth,
          ));
        }
        quality = null;
        separate = null;
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

  /// 每个音轨分组选出默认音轨：DEFAULT 优先，其次 AUTOSELECT，最后取第一条。
  /// 值为 null 表示默认音轨已混入视频变体，无需单独加载。
  static Map<String, Uri?> _audioGroups(List<String> lines, Uri base) {
    final groups = <String, List<({Uri? uri, int rank})>>{};
    var count = 0;
    for (final line in lines) {
      if (!line.startsWith('#EXT-X-MEDIA:')) continue;
      if (++count > 256) {
        throw SourceError('UNSUPPORTED', 'HLS 使用了不支持的媒体格式');
      }
      final attributes = hlsAttributes(line.substring('#EXT-X-MEDIA:'.length));
      final address = attributes['URI'];
      switch (attributes['TYPE']) {
        case 'SUBTITLES' || 'CLOSED-CAPTIONS':
          break;
        case 'AUDIO':
          final group = attributes['GROUP-ID'];
          if (group == null ||
              group.isEmpty ||
              (address != null &&
                  (address.isEmpty || address.contains(r'{$')))) {
            throw SourceError('UNSUPPORTED', 'HLS 使用了不支持的媒体格式');
          }
          groups.putIfAbsent(group, () => []).add((
            uri: address == null ? null : base.resolve(address),
            rank: attributes['DEFAULT'] == 'YES'
                ? 0
                : attributes['AUTOSELECT'] == 'YES'
                ? 1
                : 2,
          ));
        case 'VIDEO' when address == null:
          break;
        default:
          throw SourceError('UNSUPPORTED', 'HLS 使用了不支持的媒体格式');
      }
    }
    return {
      for (final entry in groups.entries)
        entry.key: entry.value.reduce((a, b) => b.rank < a.rank ? b : a).uri,
    };
  }
}
