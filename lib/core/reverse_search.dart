import 'models.dart';

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
    );
  }

  final String title, keyword, description, url, episode;
  final double? similarity, from, to;
  final bool uncertain;
}
