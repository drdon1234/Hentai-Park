import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../core/settings.dart';
import '../core/storage.dart';
import '../engine/cookie_store.dart';
import '../engine/http_service.dart';

/// Disk-cached, concurrency-limited image downloads shared by covers, thumbnails and the reader.
class ImageStore {
  ImageStore._();
  static final ImageStore instance = ImageStore._();

  final Map<String, Future<Uint8List>> _inflight = {};

  /// One limiter per image host: sites never queue behind each other, and no single host gets flooded.
  final Map<String, _Limiter> _limiters = {};

  _Limiter _limiterFor(String url) => _limiters.putIfAbsent(Uri.tryParse(url)?.host ?? '', _Limiter.new);

  Directory get _dir => Directory(p.join(AppPaths.cache.path, 'img'));

  File fileFor(String cacheKey) {
    final hash = sha1.convert(cacheKey.codeUnits).toString();
    return File(p.join(_dir.path, hash.substring(0, 2), hash));
  }

  Future<Uint8List?> cached(String cacheKey) async {
    final f = fileFor(cacheKey);
    if (await f.exists()) {
      try {
        return await f.readAsBytes();
      } catch (_) {}
    }
    return null;
  }

  /// Returns image bytes from cache or network. Concurrent calls for the same key share one download.
  Future<Uint8List> load({
    required String url,
    Map<String, String> headers = const {},
    String? cacheKey,
    List<String> fallbacks = const [],
    bool highPriority = false,
    String partition = CookieStore.appPartition,
  }) {
    final key = cacheKey ?? url;
    return _inflight[key] ??= () async {
      try {
        final hit = await cached(key);
        if (hit != null) return hit;
        final bytes = await _limiterFor(url).run(() => _download([url, ...fallbacks], headers, partition), highPriority: highPriority);
        final f = fileFor(key);
        await f.parent.create(recursive: true);
        await f.writeAsBytes(bytes, flush: false);
        return bytes;
      } finally {
        _inflight.remove(key);
      }
    }();
  }

  Future<Uint8List> _download(List<String> urls, Map<String, String> headers, String partition) async {
    Object? lastError;
    for (final url in urls) {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final res = await HttpService.instance.send(
            method: 'GET',
            url: url,
            headers: {'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8', ...headers},
            timeout: const Duration(seconds: 45),
            partition: partition,
            detectCloudflare: false,
          );
          if (!res.ok) throw SourceError('HTTP', '图片 HTTP ${res.status}', status: res.status, url: url);
          if (res.bytes.length < 64 || !_looksLikeImage(res.bytes)) {
            throw SourceError('PARSE', '服务器返回的不是图片', url: url);
          }
          return res.bytes;
        } on SourceError catch (e) {
          lastError = e;
          if (e.status == 404 || e.status == 403) break; // try next mirror instead of retrying
          await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
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
    if (b[0] == 0x52 && b[1] == 0x49 && b.length > 12 && b[8] == 0x57) return true; // webp
    if (b.length > 12 && b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) return true; // avif/heic
    if (b[0] == 0x42 && b[1] == 0x4D) return true; // bmp
    return false;
  }

  Future<int> cacheSize() async {
    if (!await _dir.exists()) return 0;
    var total = 0;
    await for (final e in _dir.list(recursive: true)) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  Future<void> clear() async {
    if (await _dir.exists()) await _dir.delete(recursive: true);
  }

  /// Trims the cache to the configured size, oldest files first.
  Future<void> trim() async {
    final limit = AppSettings.instance.cacheLimitMb * 1024 * 1024;
    if (!await _dir.exists()) return;
    final files = <(File, FileStat)>[];
    var total = 0;
    await for (final e in _dir.list(recursive: true)) {
      if (e is File) {
        final st = await e.stat();
        files.add((e, st));
        total += st.size;
      }
    }
    if (total <= limit) return;
    files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    for (final (f, st) in files) {
      if (total <= limit * 0.8) break;
      try {
        await f.delete();
        total -= st.size;
      } catch (_) {}
    }
    debugPrint('image cache trimmed to ${total ~/ 1048576} MB');
  }
}

/// Bounded concurrency with a priority lane (reader pages jump ahead of cover thumbnails).
class _Limiter {
  int _running = 0;
  final _high = Queue<Completer<void>>();
  final _low = Queue<Completer<void>>();

  int get _max => AppSettings.instance.imageConcurrency.clamp(2, 16);

  Future<T> run<T>(Future<T> Function() task, {bool highPriority = false}) async {
    if (_running >= _max) {
      final c = Completer<void>();
      (highPriority ? _high : _low).add(c);
      await c.future;
    } else {
      _running++;
    }
    try {
      return await task();
    } finally {
      if (_high.isNotEmpty) {
        _high.removeFirst().complete();
      } else if (_low.isNotEmpty) {
        _low.removeFirst().complete();
      } else {
        _running--;
      }
    }
  }
}
