import 'dart:io';

import 'models.dart';

Never _invalid() => throw SourceError('PARSE', '作品资料无效');

String _text(
  Map<String, dynamic> json,
  String key, {
  bool required = false,
  int max = 4096,
}) {
  final value = json[key];
  if (value == null && !required) return '';
  if (value is! String ||
      value.length > max ||
      (required && value.trim().isEmpty) ||
      RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]').hasMatch(value)) {
    _invalid();
  }
  return value.trim();
}

String _url(Map<String, dynamic> json, String key, {bool required = false}) {
  final value = _text(json, key, required: required);
  if (value.isEmpty) return '';
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      !RegExp(r'^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$')
          .hasMatch(uri.host) ||
      InternetAddress.tryParse(uri.host) != null ||
      uri.host.endsWith('.localhost') ||
      uri.host.endsWith('.local')) {
    _invalid();
  }
  return value;
}

List<String> _texts(Map<String, dynamic> json, String key) {
  final rows = json[key] ?? const [];
  if (rows is! List || rows.length > 100) _invalid();
  return List.unmodifiable(
    rows.map((value) => _text({'value': value}, 'value', required: true)),
  );
}

/// 资料条目不进入收藏、下载与播放链路。
class MetadataCandidate {
  MetadataCandidate.fromJson(Map<String, dynamic> json)
    : id = _text(json, 'id', required: true, max: 256),
      code = _text(json, 'code', required: true, max: 256),
      title = _text(json, 'title', required: true),
      cover = _url(json, 'cover'),
      url = _url(json, 'url', required: true);

  final String id, code, title, cover, url;
}

class WorkMetadata extends MetadataCandidate {
  WorkMetadata.fromJson(super.json)
    : description = _text(json, 'description', max: 65536),
      releaseDate = _text(json, 'releaseDate'),
      duration = _text(json, 'duration'),
      director = _text(json, 'director'),
      studio = _text(json, 'studio'),
      publisher = _text(json, 'publisher'),
      series = _text(json, 'series'),
      rating = _text(json, 'rating'),
      actors = _texts(json, 'actors'),
      tags = _texts(json, 'tags'),
      images = _images(json),
      super.fromJson();

  final String description,
      releaseDate,
      duration,
      director,
      studio,
      publisher,
      series,
      rating;
  final List<String> actors, tags, images;

  static List<String> _images(Map<String, dynamic> json) {
    final rows = json['images'] ?? const [];
    if (rows is! List || rows.length > 100) _invalid();
    return List.unmodifiable(
      rows.map((value) => _url({'url': value}, 'url', required: true)).toSet(),
    );
  }
}

class MetadataMagnet {
  MetadataMagnet.fromJson(Map<String, dynamic> json)
    : url = _text(json, 'url', required: true, max: 16384),
      name = _text(json, 'name', required: true),
      size = _text(json, 'size'),
      date = _text(json, 'date'),
      tags = _texts(json, 'tags') {
    final uri = Uri.tryParse(url);
    final topics = uri?.queryParametersAll['xt'];
    if (uri == null ||
        uri.scheme != 'magnet' ||
        uri.hasAuthority ||
        uri.path.isNotEmpty ||
        uri.hasFragment ||
        topics == null ||
        topics.length != 1 ||
        !RegExp(
          r'^urn:btih:(?:[a-f0-9]{40}|[a-z2-7]{32})$',
          caseSensitive: false,
        ).hasMatch(topics.single)) {
      _invalid();
    }
    final raw = topics.single.substring(9).toUpperCase();
    if (raw.length == 40) {
      hash = raw;
    } else {
      const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
      var bits = 0, buffer = 0;
      final bytes = <String>[];
      for (final unit in raw.split('')) {
        buffer = (buffer << 5) | alphabet.indexOf(unit);
        bits += 5;
        if (bits >= 8) {
          bits -= 8;
          bytes.add(((buffer >> bits) & 255).toRadixString(16).padLeft(2, '0'));
          buffer &= (1 << bits) - 1;
        }
      }
      hash = bytes.join().toUpperCase();
    }
  }

  final String url, name, size, date;
  final List<String> tags;
  late final String hash;
}
