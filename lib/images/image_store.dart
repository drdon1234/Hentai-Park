import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/app_log.dart';
import '../core/async_tasks.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../core/storage.dart';
import '../engine/cancellation.dart';
import '../engine/cookie_store.dart';
import '../engine/http_service.dart';
import 'image_decryption.dart';
import 'image_network.dart';
import 'image_tasks.dart';
import 'subscription_cache.dart';

/// Disk-cached, concurrency-limited image downloads shared by covers, thumbnails and the reader.
class ImageStore {
  ImageStore._() {
    AppSettings.instance.watch(const {'cacheLimitMb'}).addListener(() {
      final limit = AppSettings.instance.cacheLimitMb;
      if (_lastLimit == limit) return;
      _lastLimit = limit;
      unawaited(
        trim().catchError((Object e) => AppLog.error(e, event: 'image_cache')),
      );
    });
  }
  static final ImageStore instance = ImageStore._();

  final _inflight = ImageTasks<Uint8List>();
  final _diskQueue = SerialExecutor();
  final Map<String, ({int size, DateTime modified})> _files = {};
  String? _indexedPath;
  int _bytes = 0;
  int _generation = 0;
  int? _lastLimit;

  Future<T> _disk<T>(Future<T> Function() operation) =>
      _diskQueue.run(operation);

  Future<void> _index() async {
    if (_indexedPath == _dir.path) return;
    _files.clear();
    _bytes = 0;
    _indexedPath = null;
    if (!await _dir.exists()) {
      _indexedPath = _dir.path;
      return;
    }
    await for (final entity in _dir.list(recursive: true)) {
      if (entity is! File) continue;
      if (p.basename(entity.path).contains('.tmp-')) {
        await entity.delete();
        continue;
      }
      final stat = await entity.stat();
      _files[entity.path] = (size: stat.size, modified: stat.modified);
      _bytes += stat.size;
    }
    _indexedPath = _dir.path;
  }

  void _forget(String path) {
    _bytes -= _files.remove(path)?.size ?? 0;
  }

  static void _checkCancelled(CancelToken? token) {
    if (token?.cancelError case final error?) throw error;
  }

  final _scheduler = ImageScheduler(
    hostLimit: () => AppSettings.instance.imageConcurrency.clamp(2, 16),
  );

  void refreshPriorities() => _scheduler.refresh();

  Directory get _dir => Directory(p.join(AppPaths.cache.path, 'img'));

  File fileFor(String cacheKey, {String partition = CookieStore.appPartition}) {
    final hash = sha256
        .convert(utf8.encode(jsonEncode([partition, cacheKey])))
        .toString();
    return File(p.join(_dir.path, hash.substring(0, 2), hash));
  }

  Future<Uint8List?> cached(
    String cacheKey, {
    String partition = CookieStore.appPartition,
  }) => _disk(() async {
    await _index();
    final f = fileFor(cacheKey, partition: partition);
    if (await f.exists()) {
      try {
        final bytes = await f.readAsBytes();
        if (bytes.length >= 64 && _looksLikeImage(bytes)) return bytes;
        await f.delete();
        _forget(f.path);
      } catch (_) {}
    }
    return null;
  });

  Future<void> invalidate(
    String cacheKey, {
    String partition = CookieStore.appPartition,
  }) => _disk(() async {
    await _index();
    final file = fileFor(cacheKey, partition: partition);
    if (await file.exists()) await file.delete();
    _forget(file.path);
  });

  /// Returns image bytes from cache or network. Concurrent calls for the same key share one download.
  Future<Uint8List> load({
    required String url,
    Map<String, String> headers = const {},
    String? cacheKey,
    List<String> fallbacks = const [],
    ImageDecryption? decryption,
    bool highPriority = false,
    String partition = CookieStore.appPartition,
    CancelToken? cancelToken,
    SourceManifest? manifest,
    ImagePriority? priority,
    ImagePriority Function()? priorityOf,
  }) {
    final key = decryption?.cacheKey(cacheKey ?? url) ?? cacheKey ?? url;
    final generation = _generation;
    final source = manifest?.key ?? partition;
    final sourceGeneration = imageTransportGeneration(source);
    Future<Uint8List> fetch(
      CancelToken cancelToken,
      ImagePriority Function() priority,
    ) async {
      _checkCancelled(cancelToken);
      final hit = await cached(key, partition: partition);
      _checkCancelled(cancelToken);
      if (hit != null) return hit;
      final bytes = await _download(
        [url, ...fallbacks],
        headers,
        partition,
        cancelToken,
        decryption,
        manifest,
        () {
          final inherited = priorityOf?.call();
          return inherited != null && inherited.index < priority().index
              ? inherited
              : priority();
        },
        () => sourceGeneration == imageTransportGeneration(source),
      );
      _checkCancelled(cancelToken);
      await _disk(() async {
        if (generation != _generation ||
            sourceGeneration != imageTransportGeneration(source)) {
          return;
        }
        await _index();
        final f = fileFor(key, partition: partition);
        await f.parent.create(recursive: true);
        final committed = await writeFileAtomic(
          f,
          bytes,
          canCommit: () {
            _checkCancelled(cancelToken);
            return generation == _generation &&
                sourceGeneration == imageTransportGeneration(source);
          },
        );
        if (!committed) return;
        _forget(f.path);
        _files[f.path] = (size: bytes.length, modified: DateTime.now());
        _bytes += bytes.length;
        await _trim();
      });
      return bytes;
    }

    return _inflight.run(
      jsonEncode([
        partition,
        key,
        generation,
        sourceGeneration,
        manifest?.json['imageNetwork'],
      ]),
      fetch,
      priority:
          priority ??
          (highPriority ? ImagePriority.visible : ImagePriority.background),
      cancelToken: cancelToken,
      onPromoted: _scheduler.refresh,
    );
  }

  Future<Uint8List> _download(
    List<String> urls,
    Map<String, String> headers,
    String partition,
    CancelToken token,
    ImageDecryption? decryption,
    SourceManifest? manifest,
    ImagePriority Function() priority,
    bool Function() isCurrent,
  ) async {
    Object? lastError;
    for (final url in urls) {
      for (var attempt = 0; attempt < 2; attempt++) {
        _checkCancelled(token);
        if (!isCurrent()) throw SourceError('CANCELLED', '媒体会话已关闭');
        void Function()? release;
        try {
          final browser = createImageTransport(
            manifest,
            headers: headers,
            partition: partition,
          );
          Future<void> acquire(Uri uri) async {
            release?.call();
            release = null;
            release = await _scheduler.acquire(
              uri.host,
              priority: priority,
              token: token,
              browserSession: browser == null
                  ? null
                  : imageTransportIdentity(manifest!, headers, partition),
            );
          }

          late Uint8List encrypted;
          late String finalUrl;
          if (browser != null) {
            try {
              await acquire(Uri.parse(url));
              final result = await browser.fetch(
                Uri.parse(url),
                maxBytes: 20 * 1024 * 1024,
                cancelToken: token,
              );
              encrypted = result.bytes;
              finalUrl = result.url.toString();
            } finally {
              await browser.close();
            }
          } else {
            final res = await HttpService.instance.send(
              method: 'GET',
              url: url,
              headers: {
                'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
                ...headers,
              },
              timeout: const Duration(seconds: 45),
              maxBytes: 20 * 1024 * 1024,
              partition: partition,
              detectCloudflare: false,
              cancelToken: token,
              beforeRequest: acquire,
            );
            if (!res.ok) {
              throw SourceError(
                'HTTP',
                '图片 HTTP {status}',
                params: {'status': res.status},
                status: res.status,
                url: url,
              );
            }
            encrypted = res.bytes;
            finalUrl = res.url;
          }
          final bytes = decryption?.decode(encrypted, finalUrl) ?? encrypted;
          if (bytes.length < 64 || !_looksLikeImage(bytes)) {
            throw SourceError('PARSE', '服务器返回的不是图片', url: url);
          }
          return bytes;
        } on SourceError catch (e) {
          release?.call();
          release = null;
          if (e.code == 'CANCELLED' || e.code == 'CONFIG') rethrow;
          lastError = e;
          if (e.status == 404 || e.status == 403) {
            break; // try next mirror instead of retrying
          }
          await awaitCancelled(
            Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1))),
            token,
          );
        } finally {
          release?.call();
        }
      }
    }
    throw lastError ?? SourceError('NETWORK', '图片加载失败');
  }

  static bool _looksLikeImage(Uint8List b) {
    if (b.length < 4) return false;
    if (b[0] == 0xFF && b[1] == 0xD8) return true; // jpeg
    if (b[0] == 0x89 && b[1] == 0x50) return true; // png
    if (b[0] == 0x47 && b[1] == 0x49) return true; // gif
    if (b[0] == 0x52 && b[1] == 0x49 && b.length > 12 && b[8] == 0x57) {
      return true; // webp
    }
    if (b.length > 12 &&
        b[4] == 0x66 &&
        b[5] == 0x74 &&
        b[6] == 0x79 &&
        b[7] == 0x70) {
      return true; // avif/heic
    }
    if (b[0] == 0x42 && b[1] == 0x4D) return true; // bmp
    return false;
  }

  Future<int> cacheSize() => _disk(() async {
    await _index();
    await _trim();
    return _bytes + await SubscriptionCache.instance.size();
  });

  Future<void> clear() {
    _generation++;
    return _disk(() async {
      if (await _dir.exists()) await _dir.delete(recursive: true);
      _files.clear();
      _bytes = 0;
      _indexedPath = _dir.path;
      await invalidateImageTransports();
      await SubscriptionCache.instance.clear();
    });
  }

  /// Trims the cache to the configured size, oldest files first.
  Future<void> trim() => _disk(() async {
    await _index();
    await _trim();
  });

  Future<void> _trim() async {
    final totalLimit = AppSettings.instance.cacheLimitMb * 1024 * 1024;
    final mediaSize = await SubscriptionCache.instance.size();
    final limit = (totalLimit - mediaSize).clamp(0, totalLimit);
    if (_bytes + mediaSize <= totalLimit) return;
    final files = _files.entries.toList()
      ..sort((a, b) => a.value.modified.compareTo(b.value.modified));
    for (final file in files) {
      if (_bytes <= limit * 0.8) break;
      try {
        final f = File(file.key);
        if (await f.exists()) await f.delete();
        _forget(file.key);
      } catch (_) {}
    }
    debugPrint('image cache trimmed to ${_bytes ~/ 1048576} MB');
    await SubscriptionCache.instance.trim(
      (totalLimit - _bytes).clamp(0, totalLimit),
    );
  }
}
