import 'dart:typed_data';

import '../core/models.dart';

class HlsSegment {
  const HlsSegment(this.url, this.duration);
  final Uri url;
  final double duration;
}

/// The supported download/playback format is a finite, continuous MPEG-TS VOD.
class HlsPlaylist {
  HlsPlaylist._(this.lines, this.segments);
  final List<String> lines;
  final List<HlsSegment> segments;
  double get duration => segments.fold(0, (sum, s) => sum + s.duration);

  static HlsPlaylist parse(String text, Uri base) {
    final lines = text
        .replaceFirst('\uFEFF', '')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty ||
        lines.first != '#EXTM3U' ||
        !lines.contains('#EXT-X-ENDLIST')) {
      throw SourceError('UNSUPPORTED', '只支持完整的 HLS 点播清单');
    }
    final segments = <HlsSegment>[];
    final clean = <String>[];
    double? duration;
    var ended = false;
    for (final line in lines) {
      if (ended) throw SourceError('UNSUPPORTED', 'HLS 结束标签后包含数据');
      if (line.startsWith('#EXT-X-TOKEN:')) continue;
      if (line.startsWith('#EXT-X-KEY:')) {
        if (line != '#EXT-X-KEY:METHOD=NONE') {
          throw SourceError('UNSUPPORTED', '暂不支持加密 HLS');
        }
        continue;
      }
      // Tags with their own URI would bypass the local segment registry.
      if (line.startsWith('#EXT') &&
          RegExp(r'\bURI\s*=', caseSensitive: false).hasMatch(line)) {
        throw SourceError('UNSUPPORTED', 'HLS 使用了不支持的媒体格式');
      }
      if (RegExp(
        r'^#EXT-X-(MAP:|BYTERANGE:|DISCONTINUITY(?:$|:|-)|GAP$|STREAM-INF:|I-FRAMES-ONLY$|PART:|PRELOAD-HINT:)',
      ).hasMatch(line)) {
        throw SourceError('UNSUPPORTED', 'HLS 使用了不支持的媒体格式');
      }
      if (line.startsWith('#EXTINF:')) {
        if (duration != null) throw SourceError('NETWORK', 'HLS 分段地址缺失');
        duration = double.tryParse(line.substring(8).split(',').first);
        if (duration == null || !duration.isFinite || duration <= 0) {
          throw SourceError('NETWORK', 'HLS 分段时长无效');
        }
      } else if (!line.startsWith('#')) {
        if (duration == null) throw SourceError('NETWORK', 'HLS 分段时长缺失');
        final url = base.resolve(line);
        segments.add(HlsSegment(url, duration));
        duration = null;
        if (segments.length > 30000) {
          throw SourceError('UNSUPPORTED', 'HLS 分段数量过多');
        }
      }
      if (line == '#EXT-X-ENDLIST') ended = true;
      clean.add(line);
    }
    if (duration != null || segments.isEmpty) {
      throw SourceError('NETWORK', 'HLS 分段不完整');
    }
    return HlsPlaylist._(List.unmodifiable(clean), List.unmodifiable(segments));
  }

  String rewrite(String Function(Uri) register) {
    var index = 0;
    return '${lines.map((line) => line.startsWith('#') ? line : register(segments[index++].url)).join('\n')}\n';
  }
}

void validateTransportStream(Uint8List bytes) {
  if (bytes.length < 188 * 2 || bytes.length % 188 != 0) {
    throw SourceError('NETWORK', '媒体分段不是完整的 MPEG-TS');
  }
  for (var i = 0; i < bytes.length; i += 188) {
    if (bytes[i] != 0x47) throw SourceError('NETWORK', '媒体分段已损坏');
  }
}
