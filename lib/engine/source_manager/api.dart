part of '../source_manager.dart';

/// Typed calls into a source: feeds, search, details, chapters, media and game resources.
mixin _SourceApi on _SourceRegistry {
  @override
  Future<void> _probeDisplayOrder(String key, CancelToken token) async {
    final source = manifest(key);
    if (source == null ||
        source.rankingOnly ||
        source.reverseSearchOnly ||
        source.feeds.isEmpty) {
      throw SourceError('UNSUPPORTED', '站点没有可测速的列表入口');
    }
    // 不使用 HomeCache，确保计时来自真实列表加载；也不加载封面与媒体。
    // 前台进入同一站点时可取消这次后台读取。
    (_backgroundFeeds[key] ??= {}).add(token);
    try {
      await _requireAccount(key, cancelToken: token);
      final entry = source.feeds[entryFeedIndex(key)];
      final result = await _call(key, 'feed', [
        entry.key,
        {'page': 1, 'options': entry.defaultOptions()},
      ], cancelToken: token);
      if (result is! Map || result['items'] is! List) {
        throw SourceError('PARSE', '媒体数据无效');
      }
      WorkPage.fromJson(result.cast<String, dynamic>(), key);
    } finally {
      _backgroundFeeds[key]?.remove(token);
    }
  }

  Future<ReverseSearchResults> reverseSearch(
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
    if (result is Map) {
      final matches = result['matches'];
      final continuation = result['continuation'];
      if (matches is! List ||
          matches.isEmpty ||
          matches.length > ReverseSearchResults.previewLimit ||
          continuation is! Map<String, dynamic> ||
          utf8.encode(jsonEncode(continuation)).length > 4 * 1024 * 1024) {
        throw SourceError('PARSE', '反搜服务返回无效数据');
      }
      return ReverseSearchResults(
        _reverseSearchMatches(matches),
        loadAll: (token) async {
          final all = await _call(key, 'reverseSearchMore', [
            continuation,
          ], cancelToken: token);
          if (token.cancelError case final error?) throw error;
          return _reverseSearchMatches(all);
        },
      );
    }
    final rows = _reverseSearchRows(result);
    return ReverseSearchResults(
      _reverseSearchMatches(
        rows.take(ReverseSearchResults.previewLimit).toList(),
      ),
      loadAll: rows.length > ReverseSearchResults.previewLimit
          ? (token) async {
              if (token.cancelError case final error?) throw error;
              return _reverseSearchMatches(rows);
            }
          : null,
    );
  }

  List _reverseSearchRows(Object? result) {
    if (result is! List ||
        result.length > 1000 ||
        result.any((row) => row is! Map)) {
      throw SourceError('PARSE', '反搜服务返回无效数据');
    }
    return result;
  }

  List<ReverseSearchMatch> _reverseSearchMatches(Object? result) =>
      _reverseSearchRows(result)
          .map(
            (row) => ReverseSearchMatch.fromJson(
              (row as Map).cast<String, dynamic>(),
            ),
          )
          .toList();

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

  Future<List<Map<String, dynamic>>> interaction(
    String key,
    String id, {
    String? type,
    Object? value,
  }) async {
    if (manifest(key)?.can('interaction') != true) {
      throw SourceError('UNSUPPORTED', '本站未提供原站互动');
    }
    final result = await _call(key, 'interaction', [
      id,
      {'type': ?type, 'value': ?value},
    ]);
    final seen = <String>{};
    if (result is! List ||
        result.isEmpty ||
        result.any((entry) {
          if (entry is! Map ||
              !{'favorite', 'rating', 'like'}.contains(entry['type']) ||
              !seen.add(entry['type'] as String)) {
            return true;
          }
          final v = entry['value'];
          return entry['type'] == 'rating'
              ? v != null &&
                    (v is! num ||
                        !v.isFinite ||
                        v < 0.5 ||
                        v > 5 ||
                        v * 2 != (v * 2).roundToDouble())
              : v is! bool ||
                    (entry.containsKey('canUnset') &&
                        entry['canUnset'] is! bool);
        })) {
      throw SourceError('PARSE', '原站互动数据无效');
    }
    return result
        .map((entry) => (entry as Map).cast<String, dynamic>())
        .toList();
  }

  Future<WorkPage> related(
    String key,
    String id, {
    int page = 1,
    String? cursor,
    CancelToken? cancelToken,
  }) async {
    final result = await _call(key, 'related', [
      id,
      {'page': page, 'cursor': cursor},
    ], cancelToken: cancelToken);
    return WorkPage.fromJson((result as Map).cast<String, dynamic>(), key);
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

  /// Loads the values for a manifest-declared dynamic feed or search option.
  Future<List<Choice>> filterOptions(
    String key, {
    required String scope,
    required String filter,
    String? feed,
    String? keyword,
    Map<String, Object?> values = const {},
    CancelToken? cancelToken,
  }) async {
    final source = manifest(key);
    if (source?.can('filterOptions') != true) {
      throw SourceError('UNSUPPORTED', '本站不支持动态筛选');
    }
    if (scope != 'feed' && scope != 'search') {
      throw SourceError('CONFIG', '动态筛选请求无效');
    }
    final definitions = scope == 'search'
        ? source!.searchFilters
        : source!.feeds
              .where((candidate) => candidate.key == feed)
              .firstOrNull
              ?.options;
    final selected = definitions
        ?.where((candidate) => candidate.key == filter)
        .firstOrNull;
    if (selected?.dynamicValues != true ||
        (scope == 'feed' && (feed == null || feed.isEmpty)) ||
        (scope == 'search' && feed != null) ||
        values.keys.any((parent) => !selected!.dependsOn.contains(parent))) {
      throw SourceError('CONFIG', '未知动态筛选');
    }
    for (final parentKey in selected!.dependsOn) {
      final parent = definitions!
          .where((candidate) => candidate.key == parentKey)
          .firstOrNull;
      final value = values[parentKey];
      if (parent == null ||
          value == null ||
          value == '' ||
          value is List ||
          value is Map ||
          (parent.values.isNotEmpty &&
              (!parent.dynamicValues &&
                  !parent.values.any((choice) => choice.value == value)))) {
        throw SourceError('CONFIG', '筛选条件无效');
      }
    }
    if (values.keys.any((name) => name.isEmpty || name.length > 64)) {
      throw SourceError('CONFIG', '筛选条件无效');
    }
    final result = await _call(key, 'filterOptions', [
      {
        'scope': scope,
        'filter': filter,
        'feed': ?feed,
        'keyword': ?keyword,
        'values': values,
      },
    ], cancelToken: cancelToken);
    if (result is! List || result.length > 500) {
      throw SourceError('PARSE', '动态筛选选项无效');
    }
    final seen = <Object?>{};
    return result.map((entry) {
      if (entry is! Map ||
          !entry.containsKey('value') ||
          entry['label'] is! String ||
          (entry['label'] as String).trim().isEmpty ||
          (entry['label'] as String).length > 256 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(entry['label'] as String) ||
          (entry['color'] != null &&
              (entry['color'] is! String ||
                  !RegExp(r'^#[0-9a-fA-F]{6}$')
                      .hasMatch(entry['color'] as String)))) {
        throw SourceError('PARSE', '动态筛选选项无效');
      }
      final value = entry['value'];
      if (value == null ||
          (value is! String && value is! num) ||
          (value is num && !value.isFinite) ||
          !seen.add(value)) {
        throw SourceError('PARSE', '动态筛选选项无效');
      }
      return Choice.fromJson(entry.cast<String, dynamic>());
    }).toList();
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
    Map<String, Object?> common = const {},
    bool refresh = false,
    bool background = false,
    CancelToken? cancelToken,
    void Function(WorkPage)? onCached,
  }) async {
    await ready;
    if (!background) cancelBackgroundFeeds(key);
    final token = cancelToken ?? CancelToken();
    final source = manifest(key);
    final feed = source?.feeds.where((value) => value.key == feedKey).firstOrNull;
    if (feed == null) throw SourceError('CONFIG', '未知列表');
    final normalizedCommon = _normalizeCommonFilters(feed.commonFilters, common);
    if (background) (_backgroundFeeds[key] ??= {}).add(token);
    try {
      await _requireAccount(key, cancelToken: token);
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
          normalizedCommon,
          HomeMetadata.fields.toList(),
        ],
        () async {
          return (await _call(key, 'feed', [
            feedKey,
            {
              'page': page,
              'cursor': cursor,
              'options': options,
              'common': normalizedCommon,
            },
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
    Map<String, Object?> common = const {},
    CancelToken? cancelToken,
  }) async {
    final normalizedCommon = _normalizeCommonFilters(
      manifest(key)?.searchCommonFilters ?? const [],
      common,
    );
    final res = await _call(key, 'search', [
      {
        'keyword': keyword,
        'page': page,
        'cursor': cursor,
        'filters': filters,
        'common': normalizedCommon,
      },
    ], cancelToken: cancelToken);
    return WorkPage.fromJson((res as Map).cast<String, dynamic>(), key);
  }

  Map<String, Object?> _normalizeCommonFilters(
    List<CommonFilterDef> definitions,
    Map<String, Object?> input,
  ) {
    try {
      return normalizeCommonFilters(definitions, input);
    } on FormatException catch (error) {
      throw SourceError('CONFIG', error.message);
    }
  }

  Future<WorkDetail> detail(
    String key,
    String id, {
    WorkItem? preview,
    CancelToken? cancelToken,
    void Function(WorkDetail)? onCached,
  }) async {
    await ready;
    await _requireAccount(key, cancelToken: cancelToken);
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
    await _requireAccount(key, cancelToken: cancelToken);
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
            (source) =>
                source['hls'] == null &&
                (source['headers'] as Map? ?? {}).keys.every(
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
    return resolveVideoSources(key, sources, cancelToken: cancelToken);
  }

  /// 普通作品与订阅附件共用地址校验和 HLS 清晰度解析。
  Future<List<VideoSource>> resolveVideoSources(
    String key,
    List<VideoSource> sources, {
    CancelToken? cancelToken,
  }) async {
    if (cancelToken?.cancelError case final error?) throw error;
    if (sources.isEmpty) return sources;
    final sourceManifest = manifest(key);
    if (sourceManifest == null) throw SourceError('CONFIG', '视频站点未加载');
    // 磁盘地址与新接口结果都必须服从当前插件的媒体权限。
    for (final source in sources) {
      final uri = Uri.parse(source.url);
      // 会话授权覆盖本次接口返回的确切地址，CDN 换域名不需要更新插件白名单。
      final policy = MediaPolicy.fromManifest(sourceManifest, initialUrl: uri);
      policy.validate(uri);
      policy.requestHeaders(source.headers);
    }
    if (!sources.any((s) => s.format == 'hls')) return sources;
    final resolved = <VideoSource>[];
    final mirrors = <String>{};
    Object? failure;
    for (final source in sources) {
      if (source.format != 'hls') {
        resolved.add(source);
        continue;
      }
      // 同名同清晰度的多个地址是同一线路的镜像（如备用 CDN），按顺序取第一个可用的；
      // 单个线路不可达时保留其他线路，全部失败才报告第一个错误。
      final line = '${source.label}|${source.quality}';
      if (mirrors.contains(line)) continue;
      try {
        resolved.addAll(
          await HlsSources(
            createMediaTransport(
              sourceManifest,
              headers: source.headers,
              initialUrl: Uri.parse(source.url),
              hls: source.hls,
            ),
          ).resolve([source], cancelToken: cancelToken),
        );
        mirrors.add(line);
      } catch (error) {
        if (cancelToken?.cancelError case final cancelled?) throw cancelled;
        failure ??= error;
      }
    }
    if (resolved.isEmpty && failure != null) throw failure;
    return resolved;
  }

  /// The kind that decides how [item] opens: its own, else its source's.
  MediaKind kindOf(WorkItem item) =>
      item.mediaKind ?? manifest(item.source)?.kind ?? MediaKind.comic;

  /// Finds (source, id) references in free text: links from any source, or "JM123456"-style codes.
  Future<String> resolveLink(String key, String id) async {
    if (manifest(key)?.can('resolveLink') != true) return id;
    final result = await _call(key, 'resolveLink', [id]);
    if (result is! String ||
        result.isEmpty ||
        result.length > 4096 ||
        result.contains(RegExp(r'[\x00-\x1f]'))) {
      throw SourceError('PARSE', '媒体数据无效');
    }
    return result;
  }

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
