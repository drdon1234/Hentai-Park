import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../core/settings.dart';
import '../core/storage.dart';
import '../engine/cookie_store.dart';
import '../engine/http_service.dart';

/// Disk-cached, concurrency-limited image downloads shared by covers, thumbnails and the reader.
class ImageStore {
  ImageStore._() {
    AppSettings.instance.addListener(() {
      final limit = AppSettings.instance.cacheLimitMb;
      if (_lastLimit == limit) return;
      _lastLimit = limit;
      unawaited(
        trim().catchError((Object e) => debugPrint('image trim failed: $e')),
      );
    });
  }
  static final ImageStore instance = ImageStore._();

  final Map<String, Future<Uint8List>> _inflight = {};
  Future<void> _diskTail = Future.value();
  final Map<String, ({int size, DateTime modified})> _files = {};
  String? _indexedPath;
  int _bytes = 0;
  int _generation = 0;
  int _temporaryId = 0;
  int? _lastLimit;

  Future<T> _disk<T>(Future<T> Function() operation) {
    final result = _diskTail.then((_) => operation());
    _diskTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> _index() async {
    if (_indexedPath == _dir.path) return;
    _files.clear();
    _bytes = 0;
    _indexedPath = _dir.path;
    if (!await _dir.exists()) return;
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
  }

  void _forget(String path) {
    _bytes -= _files.remove(path)?.size ?? 0;
  }

  static void _checkCancelled(CancelToken? token) {
    if (token?.cancelError case final error?) throw error;
  }

  /// One limiter per image host: sites never queue behind each other, and no single host gets flooded.
  final Map<String, _Limiter> _limiters = {};

  _Limiter _limiterFor(String url) =>
      _limiters.putIfAbsent(Uri.tryParse(url)?.host ?? '', _Limiter.new);

  Directory get _dir => Directory(p.join(AppPaths.cache.path, 'img'));

  File fileFor(String cacheKey) {
    final hash = sha1.convert(cacheKey.codeUnits).toString();
    return File(p.join(_dir.path, hash.substring(0, 2), hash));
  }

  Future<Uint8List?> cached(String cacheKey) => _disk(() async {
    await _index();
    final f = fileFor(cacheKey);
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

  Future<void> invalidate(String cacheKey) => _disk(() async {
    await _index();
    final file = fileFor(cacheKey);
    if (await file.exists()) await file.delete();
    _forget(file.path);
  });

  /// Returns image bytes from cache or network. Concurrent calls for the same key share one download.
  Future<Uint8List> load({
    required String url,
    Map<String, String> headers = const {},
    String? cacheKey,
    List<String> fallbacks = const [],
    bool highPriority = false,
    String partition = CookieStore.appPartition,
    CancelToken? cancelToken,
  }) {
    final key = cacheKey ?? url;
    final generation = _generation;
    Future<Uint8List> fetch() async {
      _checkCancelled(cancelToken);
      final hit = await cached(key);
      _checkCancelled(cancelToken);
      if (hit != null) return hit;
      final bytes = await _limiterFor(url).run(
        () => _download([url, ...fallbacks], headers, partition, cancelToken),
        highPriority: highPriority,
        cancelToken: cancelToken,
      );
      _checkCancelled(cancelToken);
      await _disk(() async {
        if (generation != _generation) return;
        await _index();
        final f = fileFor(key);
        await f.parent.create(recursive: true);
        final tmp = File('${f.path}.tmp-${_temporaryId++}');
        try {
          await tmp.writeAsBytes(bytes, flush: true);
          _checkCancelled(cancelToken);
          if (generation != _generation) return;
          await tmp.rename(f.path);
          _forget(f.path);
          _files[f.path] = (size: bytes.length, modified: DateTime.now());
          _bytes += bytes.length;
          await _trim();
        } finally {
          if (await tmp.exists()) await tmp.delete();
        }
      });
      return bytes;
    }

    // An individually cancellable download must never cancel a reader sharing its URL.
    if (cancelToken != null) return fetch();
    final requestKey = '$partition:$key';
    return _inflight[requestKey] ??= () async {
      try {
        return await fetch();
      } finally {
        _inflight.remove(requestKey);
      }
    }();
  }

  Future<Uint8List> _download(
    List<String> urls,
    Map<String, String> headers,
    String partition,
    CancelToken? token,
  ) async {
    Object? lastError;
    for (final url in urls) {
      for (var attempt = 0; attempt < 2; attempt++) {
        _checkCancelled(token);
        try {
          final res = await HttpService.instance.send(
            method: 'GET',
            url: url,
            headers: {
              'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
              ...headers,
            },
            timeout: const Duration(seconds: 45),
            partition: partition,
            detectCloudflare: false,
            cancelToken: token,
          );
          if (!res.ok) {
            throw SourceError(
              'HTTP',
              '图片 HTTP ${res.status}',
              status: res.status,
              url: url,
            );
          }
          if (res.bytes.length < 64 || !_looksLikeImage(res.bytes)) {
            throw SourceError('PARSE', '服务器返回的不是图片', url: url);
          }
          return res.bytes;
        } on SourceError catch (e) {
          lastError = e;
          if (e.status == 404 || e.status == 403) {
            break; // try next mirror instead of retrying
          }
          await Future.any([
            Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1))),
            if (token != null)
              token.whenCancel.then<void>((error) => throw error),
          ]);
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
    return _bytes;
  });

  Future<void> clear() {
    _generation++;
    return _disk(() async {
      if (await _dir.exists()) await _dir.delete(recursive: true);
      _files.clear();
      _bytes = 0;
      _indexedPath = _dir.path;
    });
  }

  /// Trims the cache to the configured size, oldest files first.
  Future<void> trim() => _disk(() async {
    await _index();
    await _trim();
  });

  Future<void> _trim() async {
    final limit = AppSettings.instance.cacheLimitMb * 1024 * 1024;
    if (_bytes <= limit) return;
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
  }
}

/// Bounded concurrency with a priority lane (reader pages jump ahead of cover thumbnails).
class _Limiter {
  int _running = 0;
  final _high = Queue<Completer<void>>();
  final _low = Queue<Completer<void>>();

  int get _max => AppSettings.instance.imageConcurrency.clamp(2, 16);

  Future<T> run<T>(
    Future<T> Function() task, {
    bool highPriority = false,
    CancelToken? cancelToken,
  }) async {
    if (_running >= _max) {
      final c = Completer<void>();
      final queue = highPriority ? _high : _low;
      queue.add(c);
      try {
        await Future.any([
          c.future,
          if (cancelToken != null)
            cancelToken.whenCancel.then<void>((error) => throw error),
        ]);
      } catch (_) {
        if (!queue.remove(c)) _release();
        rethrow;
      }
    } else {
      _running++;
    }
    try {
      ImageStore._checkCancelled(cancelToken);
      return await task();
    } finally {
      _release();
    }
  }

  void _release() {
    if (_high.isNotEmpty) {
      _high.removeFirst().complete();
    } else if (_low.isNotEmpty) {
      _low.removeFirst().complete();
    } else {
      _running--;
    }
  }
}
