part of '../source_manager.dart';

/// Typed calls into a source: feeds, search, details, chapters, media and game resources.
mixin _SourceApi on _SourceRegistry {
  Future<List<ReverseSearchMatch>> reverseSearch(
    String key,
    String imageBase64, {
    CancelToken? cancelToken,
    BrowserImageSearch? browserSearch,
  }) async {
    if (manifest(key)?.can('reverseSearch') != true) {
      throw SourceError('UNSUPPORTED', '本站不支持反搜');
    }
    if (imageBase64.isEmpty || imageBase64.length > 2400000) {
      throw SourceError('CONFIG', '图片无法处理');
    }
    var result = await _call(key, 'reverseSearch', [
      {'base64': imageBase64, 'mimeType': 'image/png'},
    ], cancelToken: cancelToken);
    if (result is Map && result['browser'] is Map) {
      final request = BrowserImageSearchRequest.fromJson(
        (result['browser'] as Map).cast<String, dynamic>(),
        domains: declaredDomains(manifest(key)!.json),
      );
      if (browserSearch == null) {
        throw SourceError('UNSUPPORTED', '此反搜服务需要在应用内打开浏览器');
      }
      if (cancelToken?.cancelError case final error?) throw error;
      final page = await awaitCancelled(browserSearch(request), cancelToken);
      if (cancelToken?.cancelError case final error?) throw error;
      if (page == null) throw SourceError('CANCELLED', '已取消');
      final uri = Uri.tryParse(page.url);
      if (uri == null ||
          !request.isResult(uri) ||
          page.html.isEmpty ||
          page.html.length > 4 * 1024 * 1024) {
        throw SourceError('PARSE', '反搜服务返回无效数据');
      }
      result = await _call(key, 'reverseSearchResult', [
        page.toJson(),
      ], cancelToken: cancelToken);
    }
    if (result is! List ||
        result.length > 50 ||
        result.any((row) => row is! Map)) {
      throw SourceError('PARSE', '反搜服务返回无效数据');
    }
    return result
        .map(
          (row) =>
              ReverseSearchMatch.fromJson((row as Map).cast<String, dynamic>()),
        )
        .toList();
  }

  Future<List<Map<String, String>>> searchSuggestions(
    String key,
    String keyword, {
    CancelToken? cancelToken,
  }) async {
    if (manifest(key)?.can('searchSuggestions') != true ||
        keyword.trim().isEmpty) {
      return [];
    }
    final result = await _call(key, 'searchSuggestions', [
      keyword.trim(),
    ], cancelToken: cancelToken);
    if (result is! List) throw SourceError('PARSE', '媒体数据无效');
    final seen = <String>{};
    return [
      for (final entry in result.whereType<Map>())
        if (entry['keyword'] is String &&
            (entry['keyword'] as String).trim().isNotEmpty &&
            seen.add(entry['keyword'] as String))
          {
            'keyword': entry['keyword'] as String,
            'label': (entry['label'] ?? entry['keyword']).toString(),
            'subtitle': (entry['subtitle'] ?? '').toString(),
          },
    ].take(10).toList();
  }

  Future<Map<String, dynamic>> interaction(
    String key,
    String id, {
    Object? value,
  }) async {
    if (manifest(key)?.can('interaction') != true) {
      throw SourceError('UNSUPPORTED', '本站未提供原站互动');
    }
    final result = await _call(key, 'interaction', [
      id,
      {'value': ?value},
    ]);
    if (result is! Map ||
        !{'favorite', 'rating', 'like'}.contains(result['type']) ||
        (result['type'] == 'rating'
            ? result['value'] != null &&
                  (result['value'] is! num ||
                      (result['value'] as num) < 0.5 ||
                      (result['value'] as num) > 5)
            : result['value'] is! bool)) {
      throw SourceError('PARSE', '原站互动数据无效');
    }
    return result.cast<String, dynamic>();
  }

  Future<List<OptionDef>> rankingOptions(String key, RankingDef board) async {
    if (!board.options.any((option) => option.dynamicValues)) {
      return board.options;
    }
    final result = await _call(key, 'rankingOptions', [board.key]);
    return (result as List)
        .map(
          (value) => OptionDef.fromJson(
            (value as Map).cast<String, dynamic>(),
            manifest(key)?.copy,
          ),
        )
        .toList();
  }

  Future<RankingPage> ranking(
    String key,
    String board, {
    int page = 1,
    int offset = 0,
    String? cursor,
    Map<String, Object?> options = const {},
    CancelToken? cancelToken,
  }) async {
    final result = await _call(key, 'ranking', [
      board,
      {'page': page, 'offset': offset, 'cursor': cursor, 'options': options},
    ], cancelToken: cancelToken);
    return RankingPage.fromJson((result as Map).cast<String, dynamic>(), key);
  }

  Future<WorkPage> feed(
    String key,
    String feedKey, {
    int page = 1,
    String? cursor,
    Map<String, Object?> options = const {},
    bool refresh = false,
    bool background = false,
    CancelToken? cancelToken,
    void Function(WorkPage)? onCached,
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
        onCached: onCached == null
            ? null
            : (data) {
                if (!token.isCancelled) onCached(WorkPage.fromJson(data, key));
              },
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

  Future<WorkDetail> detail(
    String key,
    String id, {
    WorkItem? preview,
    CancelToken? cancelToken,
    void Function(WorkDetail)? onCached,
  }) async {
    await ready;
    final result = await HomeCache.instance.request(
      [
        'detail',
        key,
        manifest(key)?.version,
        id,
        await CookieStore.instance.snapshotPartition(key),
        settingsOf(key),
        _state[key]?['data'],
        AppSettings.instance.proxy,
        HomeMetadata.fields.toList(),
        HomeMetadata.detailFields.toList(),
      ],
      () async => (await _call(key, 'detail', [
        id,
        if (preview?.source == key && preview?.id == id) preview!.toJson(),
      ], cancelToken: cancelToken) as Map).cast<String, dynamic>(),
      refresh: true,
      serialize: HomeMetadata.detail,
      onCached: onCached == null
          ? null
          : (data) {
              if (cancelToken?.isCancelled != true) {
                onCached(WorkDetail(data, key));
              }
            },
    );
    return WorkDetail(result.data, key);
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

  /// A sandboxed web player target; it grants no HTTP or Cookie permissions.
  Future<Map<String, dynamic>> webVideo(
    String key,
    String id, {
    String? episodeId,
  }) async => (await _call(key, 'webVideo', [id, episodeId ?? '_']) as Map)
      .cast<String, dynamic>();

  Future<List<VideoSource>> videos(
    String key,
    String id, {
    String? episodeId,
    CancelToken? cancelToken,
    bool refresh = false,
  }) async {
    await ready;
    final result = await HomeCache.instance.request(
      [
        'videos',
        key,
        manifest(key)?.version,
        id,
        episodeId ?? '_',
        await CookieStore.instance.snapshotPartition(key),
        settingsOf(key),
        _state[key]?['data'],
        AppSettings.instance.proxy,
      ],
      () async => {
        'sources': await _call(key, 'videos', [
          id,
          episodeId ?? '_',
        ], cancelToken: cancelToken),
      },
      refresh: refresh,
      preferCached: true,
      shouldCache: (data) =>
          (data['sources'] as List? ?? []).isNotEmpty &&
          (data['sources'] as List).whereType<Map>().every(
            (source) => (source['headers'] as Map? ?? {}).keys.every(
              (name) => !{
                'cookie',
                'authorization',
                'proxy-authorization',
              }.contains(name.toString().toLowerCase()),
            ),
          ),
    );
    final sources = (result.data['sources'] as List)
        .whereType<Map>()
        .map((e) => VideoSource(e.cast<String, dynamic>()))
        .toList();
    if (sources.isEmpty) {
      throw SourceError('UNSUPPORTED', '此影片暂无可用播放地址');
    }
    final sourceManifest = manifest(key);
    if (sourceManifest == null) throw SourceError('CONFIG', '视频站点未加载');
    // 磁盘地址与新接口结果都必须服从当前插件的媒体权限。
    for (final source in sources) {
      final uri = Uri.parse(source.url);
      final policy = MediaPolicy.fromManifest(
        sourceManifest,
        initialUrl: source.format == 'hls' ? uri : null,
      );
      policy.validate(uri);
      policy.requestHeaders(source.headers);
    }
    if (!sources.any((s) => s.format == 'hls')) return sources;
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
