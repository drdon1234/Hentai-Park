import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/models.dart';

/// 保存用户选择的逻辑线路，不持久化签名 URL、请求头或密钥。
class DownloadSelection {
  DownloadSelection(this.json);
  final Map<String, dynamic> json;

  static String _address(VideoSource source) {
    final uri = Uri.parse(source.url);
    return sha256.convert(utf8.encode('${uri.origin}${uri.path}')).toString();
  }

  static String _origin(VideoSource source) =>
      sha256.convert(utf8.encode(Uri.parse(source.url).origin)).toString();

  static bool _same(VideoSource source, Map<String, dynamic> value) =>
      source.quality == value['quality'] &&
      source.sourceLabel == value['label'] &&
      source.format == value['format'];

  factory DownloadSelection.pick(
    List<VideoSource> sources,
    VideoSource picked, {
    String? episodeId,
  }) {
    final value = <String, dynamic>{
      'quality': picked.quality,
      'label': picked.sourceLabel,
      'format': picked.format,
      'address': _address(picked),
      'origin': _origin(picked),
      'episode': episodeId,
    };
    final matches = sources.where((s) => _same(s, value)).toList();
    value['ordinal'] = matches.indexOf(picked);
    value['count'] = matches.length;
    value['originCount'] = matches
        .where((s) => _origin(s) == value['origin'])
        .length;
    if (value['ordinal'] < 0) throw ArgumentError('Unknown download source');
    return DownloadSelection(value);
  }

  VideoSource resolve(List<VideoSource> sources, {String? episodeId}) {
    final matches = sources.where((source) => _same(source, json)).toList();
    final exact = matches.where(
      (source) => _address(source) == json['address'],
    );
    if (exact.length == 1) return exact.single;
    final origin = matches.where((s) => _origin(s) == json['origin']).toList();
    if (origin.length == 1 && json['originCount'] == 1) return origin.single;
    if (matches.length == 1 && json['count'] == 1) return matches.single;
    final ordinal = json['ordinal'];
    final sameEpisode = json['episode'] == episodeId;
    if (!sameEpisode &&
        matches.length == json['count'] &&
        ordinal is int &&
        ordinal >= 0 &&
        ordinal < matches.length) {
      return matches[ordinal];
    }
    throw SourceError('NOT_FOUND', '所选下载线路已不可用，请重新选择');
  }
}
