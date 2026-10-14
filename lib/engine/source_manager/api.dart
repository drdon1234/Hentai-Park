part of '../source_manager.dart';

/// Typed calls into a source: feeds, search, details, chapters, media and game resources.
mixin _SourceApi on _SourceRegistry {
  Future<WorkPage> feed(
    String key,
    String feedKey, {
    int page = 1,
    String? cursor,
    Map<String, Object?> options = const {},
    bool refresh = false,
    bool background = false,
    CancelToken? cancelToken,
  }) async {
    await ready;
    if (!background) cancelBackgroundFeeds(key);
    final token = cancelToken ?? CancelToken();
    if (background) (_backgroundFeeds[key] ??= {}).add(token);
    try {
      final source = manifest(key);
      // 每次读取摘要，登录、退出及网页登录改变身份后不能命中旧账号主页。
      final cookies = await CookieStore.instance.snapshotPartition(key);
      final result = await HomeCache.instance.request(
        [
          key,
          source?.version,
          cookies,
          settingsOf(key),
          _state[key]?['data'],
          AppSettings.instance.proxy,
          source?.json['domains'],
          feedKey,
          page,
          cursor,
          options,
          HomeMetadata.fields.toList(),
        ],
        () async {
          return (await _call(key, 'feed', [
            feedKey,
            {'page': page, 'cursor': cursor, 'options': options},
          ], cancelToken: token) as Map).cast<String, dynamic>();
        },
        refresh: refresh,
        requestGroup: background ? 'background' : 'foreground',
        shouldCache: HomeMetadata.cacheable,
        serialize: HomeMetadata.serialize,
      );
      return WorkPage.fromJson({
        ...result.data,
        '_staleCache': result.stale,
      }, key);
    } finally {
      if (background) _backgroundFeeds[key]?.remove(token);
    }
  }

  void cancelBackgroundFeeds(String key) {
    for (final token in _backgroundFeeds[key]?.toList() ?? <CancelToken>[]) {
      token.cancel('foreground browsing takes priority');
    }
  }

  Future<WorkPage> search(
    String key, {
    required String keyword,
    int page = 1,
    String? cursor,
    Map<String, Object?> filters = const {},
    CancelToken? cancelToken,
  }) async {
    final res = await _call(key, 'search', [
      {'keyword': keyword, 'page': page, 'cursor': cursor, 'filters': filters},
    ], cancelToken: cancelToken);
    return WorkPage.fromJson((res as Map).cast<String, dynamic>(), key);
  }

  Future<WorkDetail> detail(String key, String id, {WorkItem? preview}) async {
    final res = await _call(key, 'detail', [
      id,
      if (preview?.source == key && preview?.id == id) preview!.toJson(),
    ]);
    return WorkDetail((res as Map).cast<String, dynamic>(), key);
  }

  Future<String> random(String key) async =>
      (await _call(key, 'random', [{}])).toString();

  Future<List<GameResource>> gameResources(String key, String id) async {
    final result = await _call(key, 'gameResources', [id]);
    if (result is! List) throw SourceError('PARSE', '游戏资源格式无效');
    return result
        .map(
          (value) =>
              GameResource.fromJson((value as Map).cast<String, dynamic>()),
        )
        .toList();
  }

  Future<GameResourceLink> resolveGameResource(
    String key,
    String id,
    String resourceId,
    String channelId, {
    CancelToken? cancelToken,
  }) async {
    final result = await _call(key, 'resolveGameResource', [
      id,
      resourceId,
      channelId,
    ], cancelToken: cancelToken);
    return GameResourceLink.fromJson((result as Map).cast<String, dynamic>());
  }

  Future<ChapterImages> chapter(
    String key,
    String id,
    String? chapterId, {
    CancelToken? cancelToken,
  }) async {
    final res = await _call(key, 'chapter', [
      id,
      chapterId,
    ], cancelToken: cancelToken);
    return ChapterImages.fromJson((res as Map).cast<String, dynamic>());
  }

  Future<TextChapter> textChapter(
    String key,
    String id,
    String? chapterId, {
    CancelToken? cancelToken,
  }) async {
    final res = await _call(key, 'textChapter', [
      id,
      chapterId,
    ], cancelToken: cancelToken);
    return TextChapter.fromJson((res as Map).cast<String, dynamic>());
  }

  Future<PageImage> resolveImage(
    String key, {
    required String id,
    String? chapterId,
    required int index,
    String? token,
    int retry = 0,
    CancelToken? cancelToken,
  }) async {
    final res = await _call(key, 'resolveImage', [
      {
        'id': id,
        'chapterId': chapterId,
        'index': index,
        'token': token,
        'retry': retry,
      },
    ], cancelToken: cancelToken);
    return PageImage((res as Map).cast<String, dynamic>());
  }

  Future<({List<PreviewThumb> thumbs, bool hasNext})> thumbnails(
    String key,
    String id,
    int page,
  ) async {
    final res = (await _call(key, 'thumbnails', [id, page]) as Map)
        .cast<String, dynamic>();
    return (
      thumbs: (res['thumbnails'] as List? ?? [])
          .whereType<Map>()
          .map((t) => PreviewThumb(t.cast<String, dynamic>()))
          .toList(),
      hasNext: res['hasNext'] == true,
    );
  }

  Future<List<VideoSource>> videos(
    String key,
    String id, {
    String? episodeId,
    CancelToken? cancelToken,
  }) async {
    final res = await _call(key, 'videos', [
      id,
      episodeId ?? '_',
    ], cancelToken: cancelToken);
    final sources = (res as List)
        .whereType<Map>()
        .map((e) => VideoSource(e.cast<String, dynamic>()))
        .toList();
    if (!sources.any((s) => s.format == 'hls')) return sources;
    final sourceManifest = manifest(key);
    if (sourceManifest == null) throw SourceError('CONFIG', '视频站点未加载');
    final resolved = <VideoSource>[];
    for (final source in sources) {
      if (source.format != 'hls') {
        resolved.add(source);
        continue;
      }
      resolved.addAll(
        await HlsSources(
          createMediaTransport(
            sourceManifest,
            headers: source.headers,
            initialUrl: Uri.parse(source.url),
          ),
        ).resolve([source], cancelToken: cancelToken),
      );
    }
    return resolved;
  }

  /// The kind that decides how [item] opens: its own, else its source's.
  MediaKind kindOf(WorkItem item) =>
      item.mediaKind ?? manifest(item.source)?.kind ?? MediaKind.comic;

  /// Finds (source, id) references in free text: links from any source, or "JM123456"-style codes.
  List<({String source, String id})> extractRefs(String text) {
    final refs = <({String source, String id})>[];
    for (final s in enabled) {
      for (final id in s.manifest!.extractIds(text)) {
        refs.add((source: s.key, id: id));
      }
    }
    return refs;
  }
}
