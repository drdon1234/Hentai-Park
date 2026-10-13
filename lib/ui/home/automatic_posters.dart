import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../core/models.dart';
import '../../core/settings.dart';
import '../../core/tag_blocklist.dart';
import '../../engine/source_manager.dart';
import '../../library/library.dart';
import '../../images/park_image.dart';
import '../../images/source_posters.dart';

/// 各站独立获取；图片持久化后，滚动与重启直接读取本机海报。
class AutomaticPosters {
  AutomaticPosters({
    SourceManager? sourceManager,
    SourcePosterStore? store,
    Future<Uint8List> Function(String source, String url)? download,
  }) : _sources = sourceManager ?? SourceManager.instance,
       _store = store ?? SourcePosterStore.instance,
       _download = download ?? _downloadImage;

  static Future<Uint8List> _downloadImage(String source, String url) async {
    final token = CancelToken();
    try {
      return await ParkImage.url(
        source,
        url,
      ).loadBytes(cancelToken: token).timeout(const Duration(seconds: 15));
    } finally {
      token.cancel();
    }
  }

  static final instance = AutomaticPosters();
  final SourceManager _sources;
  final SourcePosterStore _store;
  final Future<Uint8List> Function(String source, String url) _download;
  final _cache = <String, Future<List<String>>>{};
  final _images = <String, Future<Uint8List?>>{};
  final _generations = <String, int>{};
  final _refresh = <String>{};

  String identity(InstalledSource source) =>
      '${source.key}:${sha256.convert(utf8.encode(jsonEncode([source.version, source.account?.loggedIn == true, source.manifest?.json, _sources.settingsOf(source.key), AppSettings.instance.blockedTags, AppSettings.instance.blockPresetState])))}';

  Future<Uint8List?> image(InstalledSource source) {
    final key = identity(source);
    final pendingKey = '$key:${_store.revision(source.key)}';
    final existing = _images[pendingKey];
    if (existing != null) return existing;
    late final Future<Uint8List?> future;
    future = () async {
      try {
        final saved = await _store.readImage(source.key, key);
        if (saved != null) return saved;
        return await _choose(source, key);
      } finally {
        if (identical(_images[pendingKey], future)) _images.remove(pendingKey);
      }
    }();
    _images[pendingKey] = future;
    return future;
  }

  Future<Uint8List?> _choose(
    InstalledSource source,
    String key, {
    bool replaceManual = false,
  }) async {
    final generation = _generations[source.key] ?? 0;
    final storeRevision = _store.revision(source.key);
    bool current() =>
        generation == (_generations[source.key] ?? 0) &&
        storeRevision == _store.revision(source.key) &&
        key == identity(source);
    final previous = await _store.automaticUrl(source.key);
    final urls = List<String>.of(await load(source))..shuffle(Random());
    if (urls.length > 1 && previous != null) {
      urls.remove(previous);
    }
    if (urls.isEmpty) throw SourceError('NOT_FOUND', '未找到可用海报，请进入站点完成验证或登录后重试');
    Object? lastError;
    for (final url in urls.take(6)) {
      if (!current()) return null;
      try {
        final bytes = await _download(
          source.key,
          url,
        ).timeout(const Duration(seconds: 15));
        final stored = await _store.saveAutomatic(
          source.key,
          key,
          url,
          bytes,
          replaceManual: replaceManual,
          canCommit: current,
        );
        if (!stored) return null;
        return await _store.readImage(source.key, key);
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? SourceError('NETWORK', '海报更新失败，请重试');
  }

  Future<Uint8List?> randomize(InstalledSource source) {
    refresh(source.key);
    return _choose(source, identity(source), replaceManual: true);
  }

  Future<List<String>> load(InstalledSource source) {
    final account = source.account?.loggedIn == true;
    final manifest = source.manifest!;
    final blocklist = TagBlocklist.current();
    final key = identity(source);
    final existing = _cache[key];
    if (existing != null) return existing;
    late final Future<List<String>> future;
    future = () async {
      final refresh = _refresh.remove(source.key);
      final recent = Library.instance
          .history(source: source.key)
          .where((h) => blocklist.matchItem(h.item) == null)
          .map((h) => h.item.cover)
          .where((url) => url.isNotEmpty)
          .toSet()
          .toList();
      if (recent.isNotEmpty && !refresh) return recent;
      if (manifest.feeds.isEmpty ||
          (manifest.account?.required == true && !account)) {
        return <String>[];
      }
      final defaultFeed = manifest.feeds[manifest.defaultFeedIndex];
      for (final feed in [
        defaultFeed,
        ...manifest.feeds.where((f) => f.key != defaultFeed.key),
      ]) {
        try {
          final page = await _sources.feed(
            source.key,
            feed.key,
            options: feed.defaultOptions(),
            refresh: refresh,
          );
          return [...page.items, ...?page.sections?.expand((s) => s.items)]
              .where((item) => blocklist.matchItem(item) == null)
              .map((item) => item.cover)
              .where((url) => url.isNotEmpty)
              .toSet()
              .toList();
        } on SourceError catch (e) {
          if (e.code != 'LOGIN_REQUIRED') {
            return <String>[];
          }
        } catch (_) {
          return <String>[];
        }
      }
      return <String>[];
    }();
    _cache[key] = future;
    future.then(
      (urls) {
        if (urls.isEmpty && identical(_cache[key], future)) _cache.remove(key);
      },
      onError: (Object _) {
        if (identical(_cache[key], future)) _cache.remove(key);
      },
    );
    return future;
  }

  void refresh(String source) {
    _cache.removeWhere((key, _) => key.startsWith('$source:'));
    _images.removeWhere((key, _) => key.startsWith('$source:'));
    _generations[source] = (_generations[source] ?? 0) + 1;
    _refresh.add(source);
  }
}
