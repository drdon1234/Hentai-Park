import 'dart:convert';

import 'package:dio/dio.dart';

import 'models.dart';

typedef ReverseSearchAllLoader = Future<List<ReverseSearchMatch>> Function(
  CancelToken token,
);

/// 当前查询的预览与按需续载；只在页面会话内保留。
class ReverseSearchResults {
  ReverseSearchResults(List<ReverseSearchMatch> matches, {this.loadAll})
    : matches = List.unmodifiable(matches);

  static const previewLimit = 20;
  final List<ReverseSearchMatch> matches;
  final ReverseSearchAllLoader? loadAll;
}

/// 出处候选独立于作品，不能用于阅读、下载或订阅。
class ReverseSearchMatch {
  ReverseSearchMatch._({
    required this.title,
    required this.keyword,
    required this.description,
    required this.url,
    required this.similarity,
    required this.uncertain,
    required this.episode,
    required this.from,
    required this.to,
    required this.images,
    required this.details,
  });

  factory ReverseSearchMatch.fromJson(Map<String, dynamic> json) {
    String text(String key, {bool required = false}) {
      final value = json[key];
      if (value == null && !required) return '';
      if (value is! String ||
          value.length > 4096 ||
          (required && value.trim().isEmpty)) {
        throw SourceError('PARSE', '反搜服务返回无效数据');
      }
      return value.trim();
    }

    double? number(String key, double max) {
      final value = json[key];
      if (value == null) return null;
      if (value is! num || !value.isFinite || value < 0 || value > max) {
        throw SourceError('PARSE', '反搜服务返回无效数据');
      }
      return value.toDouble();
    }

    final url = text('url');
    final uri = Uri.tryParse(url);
    if (url.isNotEmpty &&
        (uri == null ||
            !{'http', 'https'}.contains(uri.scheme) ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty)) {
      throw SourceError('PARSE', '反搜服务返回无效数据');
    }
    if (json['uncertain'] != null && json['uncertain'] is! bool) {
      throw SourceError('PARSE', '反搜服务返回无效数据');
    }
    final episode = json['episode'];
    if (episode != null && episode is! String && episode is! num) {
      throw SourceError('PARSE', '反搜服务返回无效数据');
    }
    final keyword = text('keyword');
    if (keyword.isEmpty && url.isEmpty) {
      throw SourceError('PARSE', '反搜服务返回无效数据');
    }
    final images = json['images'] ?? const [];
    final details = json['details'] ?? const <String, dynamic>{};
    if (images is! List ||
        images.length > 50 ||
        details is! Map<String, dynamic>) {
      throw SourceError('PARSE', '反搜服务返回无效数据');
    }
    var nodes = 0;
    Object? copy(Object? value, int depth) {
      if (++nodes > 4096 || depth > 12) {
        throw SourceError('PARSE', '反搜服务返回无效数据');
      }
      if (value == null || value is bool || value is String) return value;
      if (value is num && value.isFinite) return value;
      if (value is List) {
        return List<Object?>.unmodifiable(value.map((v) => copy(v, depth + 1)));
      }
      if (value is Map<String, dynamic>) {
        return Map<String, Object?>.unmodifiable(
          value.map((k, v) => MapEntry(k, copy(v, depth + 1))),
        );
      }
      throw SourceError('PARSE', '反搜服务返回无效数据');
    }

    final copied = copy(details, 0) as Map<String, Object?>;
    if (utf8.encode(jsonEncode(copied)).length > 131072) {
      throw SourceError('PARSE', '反搜服务返回无效数据');
    }
    return ReverseSearchMatch._(
      title: text('title', required: true),
      keyword: keyword,
      description: text('description'),
      url: url,
      similarity: number('similarity', 100),
      uncertain: json['uncertain'] == true,
      episode: episode?.toString() ?? '',
      from: number('from', 864000),
      to: number('to', 864000),
      images: List.unmodifiable(
        images.map((image) {
          if (image is! Map<String, dynamic>) {
            throw SourceError('PARSE', '反搜服务返回无效数据');
          }
          return ReverseSearchImage.fromJson(image);
        }),
      ),
      details: copied,
    );
  }

  final String title, keyword, description, url, episode;
  final double? similarity, from, to;
  final bool uncertain;
  final List<ReverseSearchImage> images;
  final Map<String, Object?> details;
}

/// 服务返回的相关图片，只在当前查询会话中加载。
class ReverseSearchImage {
  ReverseSearchImage._(this.url, this.label, this.similarity);

  factory ReverseSearchImage.fromJson(Map<String, dynamic> json) {
    final url = json['url'], label = json['label'] ?? '';
    final score = json['similarity'];
    if (url is! String ||
        label is! String ||
        label.length > 4096 ||
        (score != null &&
            (score is! num || !score.isFinite || score < 0 || score > 100))) {
      throw SourceError('PARSE', '反搜服务返回无效数据');
    }
    final uri = Uri.tryParse(url);
    final inline = RegExp(
      r'^data:image/(png|jpeg|webp|gif);base64,',
      caseSensitive: false,
    ).hasMatch(url);
    if (inline) {
      try {
        if (url.length > 524288 ||
            base64Decode(url.substring(url.indexOf(',') + 1)).isEmpty) {
          throw const FormatException();
        }
      } catch (_) {
        throw SourceError('PARSE', '反搜服务返回无效数据');
      }
    } else if (url.length > 4096 ||
        uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw SourceError('PARSE', '反搜服务返回无效数据');
    }
    return ReverseSearchImage._(url, label, (score as num?)?.toDouble());
  }

  final String url, label;
  final double? similarity;
}
