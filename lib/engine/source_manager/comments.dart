part of '../source_manager.dart';

mixin _SourceComments on _SourceRegistry {
  Future<CommentPage> comments(
    String key,
    String id, {
    int page = 1,
    String? cursor,
    String? parentId,
    String sort = 'default',
    Map<String, dynamic> context = const {},
    CancelToken? cancelToken,
  }) async {
    if (manifest(key)?.can('comments') != true) {
      throw SourceError('UNSUPPORTED', '此内容暂不支持评论');
    }
    await _requireAccount(key, cancelToken: cancelToken);
    final result = await _call(key, 'comments', [
      id,
      {
        'page': page,
        'cursor': cursor,
        'parentId': parentId,
        'sort': sort,
        'context': context,
      },
    ], cancelToken: cancelToken);
    if (result is! Map) throw SourceError('PARSE', '评论数据无效');
    return CommentPage.fromJson(result.cast<String, dynamic>());
  }

  Future<ContentLink> resolveContentLink(
    String current,
    String value, {
    CancelToken? cancelToken,
  }) async {
    final url = commentUrl(value);
    if (url == null) throw SourceError('CONFIG', '链接无效');
    final uri = Uri.parse(url);
    final candidates = enabled.toList()
      ..sort(
        (a, b) => a.key == current
            ? -1
            : b.key == current
            ? 1
            : 0,
      );
    for (final record in candidates) {
      final source = record.manifest!;
      if (!contentLinkDomainAllowed(uri, declaredDomains(source.json))) {
        continue;
      }
      if (source.can('resolveContentLink')) {
        final result = await _call(record.key, 'resolveContentLink', [
          url,
        ], cancelToken: cancelToken);
        if (result is! Map) continue;
        if (result['type'] == 'work' &&
            result['id'] is String &&
            (result['id'] as String).isNotEmpty &&
            (result['id'] as String).length <= 8192) {
          return ContentLink(
            'work',
            result['id'] as String,
            source: record.key,
          );
        }
        final target = commentUrl(result['url']);
        if (result['type'] == 'external' &&
            target != null &&
            contentLinkDomainAllowed(
              Uri.parse(target),
              declaredDomains(source.json),
            )) {
          return ContentLink('external', target);
        }
        if (result['type'] == 'search' &&
            source.can('searchLink') &&
            target != null &&
            httpsDomainAddressAllowed(
              Uri.parse(target),
              declaredDomains(source.json),
            )) {
          return ContentLink('search', target, source: record.key);
        }
      } else {
        final ids = source.extractIds(url);
        if (ids.isNotEmpty && source.can('detail')) {
          return ContentLink('work', ids.first, source: record.key);
        }
      }
    }
    return ContentLink('external', url);
  }

  Future<WorkPage> searchLink(
    String key,
    String url, {
    int page = 1,
    String? cursor,
    CancelToken? cancelToken,
  }) async {
    final source = manifest(key);
    if (source?.can('searchLink') != true ||
        !httpsDomainAddressAllowed(
          Uri.tryParse(url),
          declaredDomains(source!.json),
        )) {
      throw SourceError('CONFIG', '链接无效');
    }
    await _requireAccount(key, cancelToken: cancelToken);
    final result = await _call(key, 'searchLink', [
      url,
      {'page': page, 'cursor': cursor},
    ], cancelToken: cancelToken);
    if (result is! Map) throw SourceError('PARSE', '媒体数据无效');
    return WorkPage.fromJson(result.cast<String, dynamic>(), key);
  }

  Future<Map<String, dynamic>> liveChat(
    String key,
    String id, {
    CancelToken? cancelToken,
  }) async {
    await _requireAccount(key, cancelToken: cancelToken);
    final result = await _call(key, 'liveChat', [id], cancelToken: cancelToken);
    if (result is! Map) throw SourceError('PARSE', '弹幕连接失败');
    return result.cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> liveChatEvent(
    String key,
    Map<String, dynamic> state,
    Map<String, dynamic> event, {
    CancelToken? cancelToken,
  }) async {
    final result = await _call(key, 'liveChatEvent', [
      state,
      event,
    ], cancelToken: cancelToken);
    if (result is! Map) throw SourceError('PARSE', '弹幕连接失败');
    return result.cast<String, dynamic>();
  }
}
