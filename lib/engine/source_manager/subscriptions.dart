part of '../source_manager.dart';

/// Update subscriptions and their attachments.
mixin _SubscriptionApi on _SourceRegistry {
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

  Future<List<SubscriptionTarget>> subscriptionTargets(String key) async =>
      ((await _call(key, 'subscription.targets', [])) as List)
          .whereType<Map>()
          .map(SubscriptionTarget.new)
          .toList();

  Future<SubscriptionPage> subscriptionPosts(
    String key,
    String target, {
    String? cursor,
    CancelToken? cancelToken,
  }) async => SubscriptionPage(
    (await _call(key, 'subscription.posts', [
      target,
      {'cursor': cursor},
    ], cancelToken: cancelToken)) as Map,
  );

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
      await ImageStore.instance.trim();
      return file;
    } finally {
      SubscriptionCache.instance.release(temporary);
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
