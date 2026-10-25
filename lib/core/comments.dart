import 'models.dart';

/// 评论是只读的结构化内容；远端 HTML 不进入界面。
String? commentUrl(Object? value) {
  if (value is! String ||
      value.length > 8192 ||
      RegExp(r'[\x00-\x20\x7f\\]').hasMatch(value)) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !{'https', 'http'}.contains(uri.scheme) ||
      uri.userInfo.isNotEmpty ||
      !uri.host.contains('.') ||
      uri.host.endsWith('.local') ||
      uri.host.endsWith('.localhost')) {
    return null;
  }
  return uri.toString();
}

String _text(Object? value, [int limit = 65536]) {
  final text = value is String ? value : '';
  return text.length > limit ? text.substring(0, limit) : text;
}

int? _count(Object? value) =>
    value is num && value.isFinite && value >= 0 ? value.toInt() : null;

class CommentPart {
  const CommentPart(this.type, this.text, [this.url]);
  final String type;
  final String text;
  final String? url;
  static CommentPart? parse(Object? value) {
    if (value is! Map) return null;
    final type = value['type'];
    final text = _text(value['text']);
    final url = commentUrl(value['url']);
    if (type == 'image') {
      return url == null ? null : CommentPart('image', text, url);
    }
    if (type == 'link' && url != null) {
      return CommentPart('link', text.isEmpty ? url : text, url);
    }
    if (text.isEmpty) return null;
    return CommentPart(type == 'quote' ? 'quote' : 'text', text);
  }
}

class SourceComment {
  SourceComment._({
    required this.id,
    required this.author,
    required this.body,
    this.avatar,
    this.authorUrl,
    this.badges = const [],
    this.date = '',
    this.likes,
    this.rating,
    this.spoiler = false,
    this.replyCount = 0,
    this.repliesAvailable = false,
    this.replies = const [],
    this.parentId,
  });
  final String id, author, date;
  final String? avatar, authorUrl, parentId;
  final List<String> badges;
  final List<CommentPart> body;
  final int? likes;
  final double? rating;
  final bool spoiler;
  final bool repliesAvailable;
  final int replyCount;
  final List<SourceComment> replies;

  SourceComment withReplies(List<SourceComment> children) => SourceComment._(
    id: id,
    author: author,
    body: body,
    avatar: avatar,
    authorUrl: authorUrl,
    badges: badges,
    date: date,
    likes: likes,
    rating: rating,
    spoiler: spoiler,
    replyCount: replyCount > children.length ? replyCount : children.length,
    repliesAvailable: repliesAvailable,
    replies: children,
    parentId: parentId,
  );

  static SourceComment? parse(Object? value, [int depth = 0]) {
    if (value is! Map || depth > 4) return null;
    if (value['id'] is! String || (value['id'] as String).length > 512) {
      return null;
    }
    final id = value['id'] as String;
    if (id.trim().isEmpty || value['body'] is! List) return null;
    var remaining = 65536;
    final body = <CommentPart>[];
    for (final raw in (value['body'] as List).take(500)) {
      final part = CommentPart.parse(raw);
      if (part == null || remaining <= 0) continue;
      final text = part.text.length > remaining
          ? part.text.substring(0, remaining)
          : part.text;
      remaining -= text.length;
      body.add(CommentPart(part.type, text, part.url));
    }
    if (!body.any(
      (part) => part.type == 'image' || part.text.trim().isNotEmpty,
    )) {
      return null;
    }
    final author = value['author'] is Map ? value['author'] as Map : const {};
    final rating = value['rating'];
    return SourceComment._(
      id: id,
      author: _text(author['name'], 256),
      body: body,
      avatar: commentUrl(author['avatar']),
      authorUrl: commentUrl(author['url']),
      badges: author['badges'] is List
          ? (author['badges'] as List)
                .whereType<String>()
                .take(8)
                .map((s) => _text(s, 128))
                .toList()
          : const [],
      date: _text(value['date'], 128),
      likes: _count(value['likes']),
      rating: rating is num && rating.isFinite && rating >= 0 && rating <= 5
          ? rating.toDouble()
          : null,
      spoiler: value['spoiler'] == true,
      replyCount: _count(value['replyCount']) ?? 0,
      repliesAvailable: value['repliesAvailable'] == true,
      parentId: value['parentId'] is String
          ? _text(value['parentId'], 512)
          : null,
      replies: depth < 4 && value['replies'] is List
          ? (value['replies'] as List)
                .take(100)
                .map((v) => parse(v, depth + 1))
                .whereType<SourceComment>()
                .toList()
          : const [],
    );
  }
}

class CommentPage {
  const CommentPage({
    required this.items,
    required this.hasNext,
    this.cursor,
    this.total,
    this.sorts = const [],
    this.reset = false,
    this.page,
  });
  final List<SourceComment> items;
  final bool hasNext, reset;
  final String? cursor;
  final int? total, page;
  final List<({String value, String label})> sorts;

  factory CommentPage.fromJson(Map<String, dynamic> json) {
    if (json['items'] is! List ||
        (json['items'] as List).length > 200 ||
        json['hasNext'] is! bool) {
      throw SourceError('PARSE', '评论数据无效');
    }
    final rows = json['items'] as List;
    final items = rows
        .map(SourceComment.parse)
        .whereType<SourceComment>()
        .toList();
    if (rows.isNotEmpty && items.isEmpty) throw SourceError('PARSE', '评论数据无效');
    final cursor = json['cursor'];
    if (cursor != null && (cursor is! String || cursor.length > 65536)) {
      throw SourceError('PARSE', '评论数据无效');
    }
    return CommentPage(
      items: items,
      hasNext: json['hasNext'] == true,
      cursor: cursor as String?,
      total: _count(json['total']),
      reset: json['reset'] == true,
      page: _count(json['page']),
      sorts: json['sorts'] is List
          ? [
              for (final entry in (json['sorts'] as List).whereType<Map>().take(
                20,
              ))
                if (entry['value'] is String && entry['label'] is String)
                  (
                    value: _text(entry['value'], 128),
                    label: _text(entry['label'], 128),
                  ),
            ]
          : const [],
    );
  }
}

class ContentLink {
  const ContentLink(this.type, this.value, {this.source});
  final String type, value;
  final String? source;
}
