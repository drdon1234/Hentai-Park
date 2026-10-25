import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import '../../core/models.dart';
import '../../engine/source_manager.dart';

/// 一条帖子可以有多个视频；播放池按附件区分，原站操作仍使用帖子 ID。
class PostVideoItem extends WorkItem {
  PostVideoItem(super.json, super.source);
  @override
  String get uid => '${super.uid}:video:${json['postVideoIndex']}';
  WorkItem get post => WorkItem(json, source);
}

WorkItem videoPost(WorkItem item) => item is PostVideoItem ? item.post : item;

bool isPostVideoAttachment(Object? value) =>
    value is Map &&
    value['type'] == 'video' &&
    ((value['url'] is String && (value['url'] as String).isNotEmpty) ||
        (value['episodeId'] is String &&
            (value['episodeId'] as String).isNotEmpty) ||
        value['resource'] is Map);

WorkPage postVideoPage(WorkPage page) => WorkPage(
  items: [
    for (final post in page.items)
      if (post is PostVideoItem)
        post
      else if (post.json['media'] case final List media)
        for (var index = 0; index < media.length; index++)
          if (media[index] case final Map attachment
              when isPostVideoAttachment(attachment))
            PostVideoItem({
              ...post.json,
              'postVideoIndex':
                  post.json['postVideoIndex'] ??
                  media
                      .take(index)
                      .whereType<Map>()
                      .where((m) => m['type'] == 'video')
                      .length,
              'mediaKind': 'video',
              'cover': attachment['preview'] ?? post.cover,
              'media': [Map<String, dynamic>.from(attachment)],
            }, post.source),
  ],
  page: page.page,
  cursor: page.cursor,
  hasNext: page.hasNext,
);

/// 浏览上下文显式携带 feed/目标，不根据站点名推断请求。
class PostVideoScope {
  const PostVideoScope({
    required this.source,
    required this.title,
    this.feed,
    this.options = const {},
    this.target,
    this.keyword,
    this.filters = const {},
    this.common = const {},
  }) : assert(feed != null || target != null || keyword != null);
  final String source, title;
  final String? feed, target;
  final String? keyword;
  final Map<String, Object?> filters;
  final Map<String, Object?> common;
  final Map<String, Object?> options;

  Future<WorkPage> load(
    int page,
    String? cursor, {
    bool refresh = false,
    CancelToken? cancelToken,
    SourceManager? sourceManager,
  }) async {
    final manager = sourceManager ?? SourceManager.instance;
    if (keyword case final keyword?) {
      return manager.search(
        source,
        keyword: keyword,
        filters: filters,
        common: common,
        page: page,
        cursor: cursor,
        cancelToken: cancelToken,
      );
    }
    if (target case final target?) {
      final result = await manager.subscriptionPosts(
        source,
        target,
        cursor: cursor,
        cancelToken: cancelToken,
      );
      return WorkPage(
        items: result.items.map((post) => WorkItem(post.json, source)).toList(),
        page: page,
        cursor: result.cursor,
        hasNext: result.hasNext,
      );
    }
    return manager.feed(
      source,
      feed!,
      page: page,
      cursor: cursor,
      options: options,
      common: common,
      refresh: refresh,
      cancelToken: cancelToken,
    );
  }
}

class PostVideoContext extends InheritedWidget {
  const PostVideoContext({
    super.key,
    required this.scope,
    required super.child,
  });
  final PostVideoScope scope;
  static PostVideoScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PostVideoContext>()?.scope;
  @override
  bool updateShouldNotify(PostVideoContext oldWidget) =>
      scope != oldWidget.scope;
}
