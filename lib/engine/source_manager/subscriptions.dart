part of '../source_manager.dart';

WorkPage _downloadScopedPage(WorkPage page, Map<String, Object?> scope) {
  for (final item in [
    ...page.items,
    for (final section in page.sections ?? <WorkSection>[]) ...section.items,
  ]) {
    if (item.isSubscriptionPost) {
      item.json['downloadScope'] = Map<String, Object?>.from(scope);
    }
  }
  return page;
}

/// Update subscriptions and their attachments.
mixin _SubscriptionApi on _SourceRegistry {
  Future<Map<String, dynamic>> subscriptionQuery(
    String key,
    String dimension,
    String target,
  ) async {
    final result = await _call(key, 'updateSubscriptions.query', [
      {'dimension': dimension, 'target': target},
    ]);
    if (result is! Map ||
        result['keyword'] is! String ||
        result['filters'] is! Map) {
      throw SourceError('PARSE', '订阅筛选无效');
    }
    return result.cast<String, dynamic>();
  }

  Future<String> subscriptionContext(String key) async => sha256Hex(
    jsonEncode([
      manifest(key)?.version,
      settingsOf(key),
      (_state[key]?['data'] as Map?)?.entries
          .where(
            (e) => RegExp(
              'credential|account|user|session',
              caseSensitive: false,
            ).hasMatch(e.key),
          )
          .map((e) => [e.key, subscriptionAccountIdentity(e.value)])
          .toList(),
      await CookieStore.instance.authenticationValues(
        key,
        ((manifest(key)?.json['account'] as Map?)?['requiredCookies']
                    as List? ??
                [])
            .map((v) => v.toString())
            .toList(),
      ),
      AppSettings.instance.proxy,
    ]),
  );

  Future<SubscriptionTarget> normalizeSubscription(
    String key,
    String input, {
    String dimension = 'posts',
  }) async {
    final result = await _call(key, 'updateSubscriptions.normalize', [
      dimension,
      input,
    ]);
    final target = SubscriptionTarget(result as Map);
    if (target.id.isEmpty) throw SourceError('CONFIG', '订阅目标无效');
    return target;
  }

  Future<SubscriptionTarget> resolveSubscription(
    String key,
    String input, {
    String dimension = 'posts',
  }) async {
    if (dimension != 'posts') {
      return normalizeSubscription(key, input, dimension: dimension);
    }
    final result = await _call(key, 'subscription.resolve', [input]);
    final target = SubscriptionTarget(result as Map);
    if (target.id.isEmpty) throw SourceError('CONFIG', '订阅目标无效');
    return target;
  }

  Future<Map<String, dynamic>> checkSubscription(
    String key,
    String dimension,
    String target, {
    String? cursor,
    CancelToken? cancelToken,
  }) async => (await _call(key, 'updateSubscriptions.check', [
    {'dimension': dimension, 'target': target},
    {'cursor': cursor},
  ], cancelToken: cancelToken) as Map).cast<String, dynamic>();

  Future<List<SubscriptionTarget>> subscriptionTargets(
    String key, {
    String? kind,
  }) async => ((await _call(key, 'subscription.targets', [
    if (kind != null) {'kind': kind},
  ])) as List).whereType<Map>().map(SubscriptionTarget.new).toList();

  Future<SubscriptionTargetPage> subscriptionTargetPage(
    String key, {
    String? kind,
    String? cursor,
    String? query,
    CancelToken? cancelToken,
  }) async => SubscriptionTargetPage(
    (await _call(key, 'subscription.targets', [
      {
        'mode': 'page',
        'kind': ?kind,
        'cursor': ?cursor,
        if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
      },
    ], cancelToken: cancelToken)) as Map,
  );

  Future<SubscriptionPage> subscriptionPosts(
    String key,
    String target, {
    String? cursor,
    CancelToken? cancelToken,
  }) async {
    final result = SubscriptionPage(
      (await _call(key, 'subscription.posts', [
        target,
        {'cursor': cursor},
      ], cancelToken: cancelToken)) as Map,
    );
    for (final post in result.items) {
      post.json['downloadScope'] = {'target': target};
    }
    return result;
  }

  Future<WorkPage> subscriptionAlbum(
    String key,
    Map<String, Object?> scope, {
    int page = 1,
    String? cursor,
    CancelToken? cancelToken,
  }) async {
    final result = await _call(key, 'subscription.media', [
      scope,
      {'page': page, 'cursor': cursor},
    ], cancelToken: cancelToken);
    final parsed = parseAlbumPage(result, key, page);
    for (final item in parsed.items) {
      item.json['downloadScope'] = Map<String, Object?>.from(scope);
    }
    return parsed;
  }

  /// 没有独立详情的帖子从原浏览范围重新定位，任务不保存临时媒体地址。
  Future<WorkDetail> downloadPost(
    WorkItem item, {
    CancelToken? cancelToken,
  }) async {
    final scope = item.json['downloadScope'];
    if (scope is! Map) throw SourceError('NOT_FOUND', '内容不存在或已被删除');
    String? cursor;
    final cursors = <String>{};
    for (var page = 1; page <= 1000; page++) {
      if (cancelToken?.cancelError case final error?) throw error;
      final WorkPage result;
      if (manifest(item.source)?.can('album') == true) {
        result = await subscriptionAlbum(
          item.source,
          scope.cast<String, Object?>(),
          page: page,
          cursor: cursor,
          cancelToken: cancelToken,
        );
      } else {
        final target = scope['target'];
        if (target is! String) throw SourceError('PARSE', '媒体数据无效');
        final posts = await subscriptionPosts(
          item.source,
          target,
          cursor: cursor,
          cancelToken: cancelToken,
        );
        result = WorkPage(
          items: [
            for (final post in posts.items) WorkItem(post.json, item.source),
          ],
          page: page,
          cursor: posts.cursor,
          hasNext: posts.hasNext,
        );
      }
      final found = result.items
          .where((post) => post.id == item.id)
          .firstOrNull;
      if (found != null) return WorkDetail(found.json, item.source);
      if (!result.hasNext) break;
      cursor = result.cursor;
      if (cursor != null && !cursors.add(cursor)) {
        throw SourceError('PARSE', '媒体数据无效');
      }
    }
    throw SourceError('NOT_FOUND', '内容不存在或已被删除');
  }

  /// 源插件只返回附件块；由框架控制本地路径、大小与原子完成，取消不会留下假完整文件。
  Future<File> subscriptionMediaFile(
    String key,
    SubscriptionMedia media, {
    CancelToken? cancelToken,
    void Function(int, int)? onProgress,
  }) async {
    final resource = media.json['resource'];
    final size = resource is Map ? resource['size'] : null;
    if (resource is! Map || size is! int || size < 1 || size > 536870912) {
      throw SourceError('UNSUPPORTED', '该媒体暂不支持，请在原站打开');
    }
    final directory = SubscriptionCache.instance.directory;
    await directory.create(recursive: true);
    // 可变授权信息不应进入身份；稳定标识由插件提供，框架不识别站点私有字段。
    final cacheKey = resource['cacheKey'];
    if (cacheKey is! String || cacheKey.isEmpty || cacheKey.length > 512) {
      throw SourceError('CONFIG', '媒体数据无效');
    }
    final identity = safeFileName('$key:$cacheKey');
    final file = File(
      p.join(
        directory.path,
        '$identity.${media.type == 'video' ? 'mp4' : 'jpg'}',
      ),
    );
    SubscriptionCache.instance.retain(file);
    final queue = _attachmentWrites[file.path] ??= SerialExecutor();
    final result = queue.run(
      () => _downloadSubscriptionMedia(
        key,
        resource,
        size,
        file,
        cancelToken,
        onProgress,
      ),
    );
    final tail = queue.settled;
    try {
      return await result;
    } catch (_) {
      SubscriptionCache.instance.release(file);
      rethrow;
    } finally {
      if (identical(queue.settled, tail)) _attachmentWrites.remove(file.path);
    }
  }

  Future<File> _downloadSubscriptionMedia(
    String key,
    Map resource,
    int size,
    File file,
    CancelToken? cancelToken,
    void Function(int, int)? onProgress,
  ) async {
    final temporary = File(
      '${file.path}.part-${DateTime.now().microsecondsSinceEpoch}',
    );
    var offset = 0;
    SubscriptionCache.instance.retain(temporary);
    try {
      if (cancelToken?.cancelError case final error?) throw error;
      if (await file.exists() && await file.length() == size) {
        await file.setLastModified(DateTime.now());
        await SubscriptionCache.instance.record(file);
        return file;
      }
      final output = await temporary.open(mode: FileMode.write);
      try {
        while (offset < size) {
          if (cancelToken?.cancelError case final error?) throw error;
          final chunk = await _call(key, 'subscription.mediaChunk', [
            resource,
            offset,
          ], cancelToken: cancelToken) as Map;
          final encoded = chunk['base64'];
          if (encoded is! String || encoded.length > 174764) {
            throw SourceError('PARSE', '媒体数据无效');
          }
          final bytes = base64Decode(encoded);
          if (bytes.isEmpty ||
              bytes.length > 131072 ||
              offset + bytes.length > size ||
              (offset + bytes.length < size && bytes.length != 131072)) {
            throw SourceError('PARSE', '媒体数据无效');
          }
          await output.writeFrom(bytes);
          offset += bytes.length;
          onProgress?.call(offset, size);
        }
        await output.flush();
      } finally {
        await output.close();
      }
      if (cancelToken?.cancelError case final error?) throw error;
      await temporary.rename(file.path);
      await SubscriptionCache.instance.record(file);
      await ImageStore.instance.trim();
      return file;
    } finally {
      SubscriptionCache.instance.release(temporary);
      if (await temporary.exists()) await temporary.delete();
      await SubscriptionCache.instance.record(temporary);
    }
  }
}
