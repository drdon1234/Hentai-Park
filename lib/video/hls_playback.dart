import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/app_log.dart';
import '../core/models.dart';
import '../engine/media_transport.dart';
import 'hls.dart';
import 'hls_resources.dart';
import 'hls_windows.dart';
import 'local_hls_media.dart';
import 'playback.dart';
import 'playback_cache.dart';
import 'rou_hls_wrapper.dart';

/// A private, finite URL registry. The player never supplies an upstream URL.
class HlsPlayback implements Playback {
  HlsPlayback(this.transport, {this.live = false, this.audio});
  HlsPlayback.local(File playlist)
    : transport = LocalHlsMedia(playlist),
      live = false,
      audio = null;

  Future<Uri> openLocal() => open(LocalHlsMedia.playlistUrl);
  final MediaTransport transport;
  final bool live;

  /// 视频与音轨分开存放时，本地生成只含此视频变体与默认音轨的主清单。
  final HlsAudioVariant? audio;
  final _cancel = CancelToken();
  final _routes = <String, HlsSegment>{};
  String? _playlistPath;
  final _playlists = <String>{};
  Uri? _upstream;
  String? _preferredCdnHost;
  final _manifestUrls = <Uri>{};
  final _segmentPaths = <String, String>{};
  Set<String> _currentPaths = {};
  Set<String> _previousPaths = {};
  int _nextRoute = 0;
  Future<Uint8List>? _refreshing;
  int _playlistRefresh = 0;
  late final _resources = HlsResources(transport, _cancel);
  final Map<String, Uint8List> _cache = {};
  HlsWindows? _windows;

  /// 点播分段在内存淘汰后仍保存在本次会话的临时文件中，往回拖动不再重新下载。
  SegmentCache? _disk;
  final _pending = <String, Future<Uint8List>>{};
  final Queue<Completer<void>> _resourceWaiters = Queue<Completer<void>>();
  static const _maxResourceLoads = 8;
  int _resourceLoads = 0;
  final _token = List.generate(
    24,
    (_) => Random.secure().nextInt(256),
  ).map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  HttpServer? _server;
  Future<void>? _closing;
  bool _closed = false;
  bool _opened = false;
  int _cacheBytes = 0;
  static const _cacheLimit = 24 * 1024 * 1024;

  @override
  Future<Uri> open(Uri url) async {
    if (_closed || _opened) throw StateError('媒体会话不可重复打开');
    _opened = true;
    try {
      transport.validate(url);
      var audio = this.audio;
      if (transport case final LocalHlsMedia local) {
        final selected = await local.variant();
        url = selected.video;
        if (selected.audio case final sound?) {
          audio = HlsAudioVariant(playlist: sound, bandwidth: 1);
        }
      }
      if (audio != null) {
        // 直播窗口刷新只跟踪单个媒体清单。
        if (live) throw SourceError('UNSUPPORTED', 'HLS 使用了不支持的媒体格式');
        authorizeMediaResource(transport, audio.playlist);
      }
      _upstream = url;
      _manifestUrls.add(url);
      final playlistUrl = live || transport is LocalHlsMedia
          ? url
          : _freshPlaylistUrl(url);
      if (playlistUrl != url) authorizeMediaResource(transport, playlistUrl);
      final list = await _mediaPlaylist(playlistUrl);
      final audioList = audio == null
          ? null
          : await _mediaPlaylist(audio.playlist);
      if (_closed) throw SourceError('CANCELLED', '媒体会话已关闭');
      if (!live) {
        final disk = await SegmentCache.open();
        if (_closed) {
          await disk?.close();
          throw SourceError('CANCELLED', '媒体会话已关闭');
        }
        _disk = disk;
      }
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      if (_closed) {
        await server.close(force: true);
        throw SourceError('CANCELLED', '媒体会话已关闭');
      }
      _server = server;
      _playlistPath = '/$_token/index.m3u8';
      final root = Uri.parse('http://127.0.0.1:${server.port}$_playlistPath');
      if (Platform.isAndroid &&
          transport is! LocalHlsMedia &&
          !live &&
          audio == null &&
          list.initialization == null &&
          list.segments.length > 120) {
        final windows = HlsWindows(list, root, _disk, (segment, token) {
          final path = _segmentPaths.putIfAbsent(
            '${segment.sequence}',
            () => _register(segment).path,
          );
          return _readSegment(path, requestToken: token);
        });
        _windows = windows;
        _publish(root.path, windows.playlist());
        server.listen((request) => unawaited(_serve(request)));
        return root;
      }
      if (audioList == null || audio == null) {
        _publish(
          root.path,
          _prepareVodPlaylist(list.rewrite((s) => _register(s).toString())),
        );
      } else {
        final video = root.resolve('video.m3u8');
        final sound = root.resolve('audio.m3u8');
        _publish(
          video.path,
          _prepareVodPlaylist(list.rewrite((s) => _register(s).toString())),
        );
        _publish(sound.path, audioList.rewrite((s) => _register(s).toString()));
        _publish(
          root.path,
          [
            '#EXTM3U',
            '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="audio",'
                'DEFAULT=YES,AUTOSELECT=YES,URI="$sound"',
            [
              '#EXT-X-STREAM-INF:BANDWIDTH=${audio.bandwidth}',
              if (audio.resolution case final value?) 'RESOLUTION=$value',
              if (audio.codecs case final value?) 'CODECS="$value"',
              'AUDIO="audio"',
            ].join(','),
            '$video',
            '',
          ].join('\n'),
        );
      }
      server.listen((request) => unawaited(_serve(request)));
      return root;
    } catch (_) {
      await close();
      rethrow;
    }
  }

  Future<HlsPlaylist> _mediaPlaylist(
    Uri url, {
    CancelToken? requestToken,
  }) async {
    final response = await transport.fetch(
      url,
      maxBytes: 2 * 1024 * 1024,
      cancelToken: requestToken ?? _cancel,
    );
    _manifestUrls.add(response.url);
    final list = HlsPlaylist.parse(
      utf8.decode(
        unwrapRouHlsIfWrapped(response.bytes, maxBytes: 2 * 1024 * 1024),
      ),
      response.url,
      live: live,
    );
    _resources.validate(list);
    return list;
  }

  Uri _freshPlaylistUrl(Uri url) => url.replace(
    // The CDN selects its edge from this value. A monotonic small counter
    // makes retries visit the known alternate edges instead of repeatedly
    // receiving the same unhealthy host.
    query: '${url.query}&__park_refresh=${_playlistRefresh++ % 3}',
  );

  void _publish(String path, String playlist) {
    final bytes = Uint8List.fromList(utf8.encode(playlist));
    _playlists.add(path);
    _cache[path] = bytes;
    _cacheBytes += bytes.length;
  }

  String _prepareVodPlaylist(String playlist) {
    if (live || playlist.contains('#EXT-X-PLAYLIST-TYPE:')) return playlist;
    final lines = playlist.split('\n');
    final index = lines.indexWhere(
      (line) => line.startsWith('#EXT-X-VERSION:'),
    );
    lines.insert(index < 0 ? 1 : index + 1, '#EXT-X-PLAYLIST-TYPE:VOD');
    return lines.join('\n');
  }

  Uri _register(HlsSegment segment) {
    // An upstream URL can be repeated with a different IV or key. Register
    // the segment occurrence so these resources can never share plaintext.
    final identity =
        '${segment.kind}|${segment.sequence}|${segment.url}|${segment.key}|${segment.iv}';
    final path = live
        ? _segmentPaths.putIfAbsent(
            identity,
            () => '/$_token/r${_nextRoute++}.${segment.extension}',
          )
        : '/$_token/r${_routes.length}.${segment.extension}';
    _routes[path] = segment;
    if (live) _currentPaths.add(path);
    return Uri.parse('http://127.0.0.1:${_server!.port}$path');
  }

  Future<Uint8List> _livePlaylist() async {
    if (_refreshing case final pending?) return pending;
    final operation = () async {
      final response = await transport.fetch(
        _upstream!,
        maxBytes: 2 * 1024 * 1024,
        cancelToken: _cancel,
      );
      if (_closed) throw SourceError('CANCELLED', '媒体会话已关闭');
      final playlist = HlsPlaylist.parse(
        utf8.decode(
          unwrapRouHlsIfWrapped(response.bytes, maxBytes: 2 * 1024 * 1024),
        ),
        response.url,
        live: true,
      );
      _resources.validate(playlist);
      final previous = _currentPaths;
      _currentPaths = {};
      final bytes = Uint8List.fromList(
        utf8.encode(playlist.rewrite((s) => _register(s).toString())),
      );
      if (previous.length != _currentPaths.length ||
          !previous.every(_currentPaths.contains)) {
        _previousPaths = previous;
      }
      final retained = {..._currentPaths, ..._previousPaths, ..._pending.keys};
      _routes.removeWhere((path, _) => !retained.contains(path));
      _segmentPaths.removeWhere((_, path) => !retained.contains(path));
      for (final path
          in _cache.keys
              .where(
                (path) => path != _playlistPath && !retained.contains(path),
              )
              .toList()) {
        _cacheBytes -= _cache.remove(path)!.length;
      }
      // 原入口仍可用于下次刷新；重定向目标只保留本次确切地址。
      _manifestUrls.removeWhere((url) => url != _upstream);
      _manifestUrls.add(response.url);
      final keys = {
        for (final segment in _routes.values)
          if (segment.key != null) segment.key!,
      };
      transport.policy.retainSessionResources({
        ..._manifestUrls,
        ...keys,
        for (final segment in _routes.values) segment.url,
      });
      _resources.retainKeys(keys);
      return bytes;
    }();
    _refreshing = operation;
    try {
      return await operation;
    } finally {
      if (identical(_refreshing, operation)) _refreshing = null;
    }
  }

  Future<Uint8List> _resource(String path) async {
    final windows = _windows;
    if (windows != null && windows.contains(path)) {
      return windows.resource(path);
    }
    if (live && path == _playlistPath) return _livePlaylist();
    final cached = _cache.remove(path);
    if (cached != null) {
      _cache[path] = cached;
      return cached;
    }
    if (_pending[path] case final future?) return future;
    final operation = () async {
      await _acquireResourceSlot();
      try {
        final stored = await _disk?.read(path);
        final bytes = stored ?? await _readSegment(path);
        final repaired = bytes;
        if (_closed) throw SourceError('CANCELLED', '媒体会话已关闭');
        await _disk?.store(path, repaired);
        if (repaired.length <= _cacheLimit) {
          while (_cacheBytes + repaired.length > _cacheLimit) {
            // Keep the rewritten manifests for retries. Segment data is a bounded LRU.
            final victim = _cache.keys
                .where((key) => !_playlists.contains(key))
                .firstOrNull;
            if (victim == null) break;
            _cacheBytes -= _cache.remove(victim)!.length;
          }
          if (_cacheBytes + repaired.length <= _cacheLimit) {
            _cache[path] = repaired;
            _cacheBytes += repaired.length;
          }
        }
        return repaired;
      } finally {
        _releaseResourceSlot();
      }
    }();
    _pending[path] = operation;
    try {
      return await operation;
    } finally {
      _pending.remove(path)?.ignore();
    }
  }

  Future<void> _acquireResourceSlot() async {
    if (_closed) throw SourceError('CANCELLED', '媒体会话已关闭');
    if (_resourceLoads < _maxResourceLoads) {
      _resourceLoads++;
      return;
    }
    final waiter = Completer<void>();
    _resourceWaiters.addLast(waiter);
    await waiter.future;
    if (_closed) throw SourceError('CANCELLED', '媒体会话已关闭');
    _resourceLoads++;
  }

  void _releaseResourceSlot() {
    if (_resourceLoads > 0) _resourceLoads--;
    while (_resourceWaiters.isNotEmpty) {
      final waiter = _resourceWaiters.removeFirst();
      if (!waiter.isCompleted) {
        waiter.complete();
        return;
      }
    }
  }

  Future<Uint8List> _readSegment(
    String path, {
    CancelToken? requestToken,
  }) async {
    void check() {
      if (_cancel.cancelError case final error?) throw error;
      if (requestToken?.cancelError case final error?) throw error;
    }

    check();
    final segment = _routes[path];
    if (segment == null) throw SourceError('NETWORK', '媒体分片不存在');
    if (live || _upstream == null) {
      return _readCandidate(path, segment, requestToken: requestToken);
    }
    Object? lastError;
    final fallbackHosts = _cdnFallbackHosts(segment.url.host);
    final preferred = _preferredCdnHost;
    final candidates = <HlsSegment>[];
    if (preferred != null && fallbackHosts.contains(preferred)) {
      candidates.add(_segmentOnHost(segment, preferred));
    }
    candidates.add(segment);
    for (final host in fallbackHosts) {
      if (host != preferred) candidates.add(_segmentOnHost(segment, host));
    }
    for (final candidate in candidates) {
      check();
      try {
        return await _readCandidate(
          path,
          candidate,
          requestToken: requestToken,
        );
      } catch (error) {
        lastError = error;
      }
    }
    // 清单刷新可将同一分片移到其他节点。请求次数有界，网络超时由传输层
    // 处理，不能把持续有进度的下载、解密或封装算成 CDN 停滞。
    for (var attempt = 0; attempt < 2; attempt++) {
      check();
      try {
        final refreshedUrl = _freshPlaylistUrl(_upstream!);
        authorizeMediaResource(transport, refreshedUrl);
        final refreshed = await _mediaPlaylist(
          refreshedUrl,
          requestToken: requestToken,
        );
        final replacement = refreshed.segments.firstWhere(
          (candidate) => candidate.sequence == segment.sequence,
          orElse: () => segment,
        );
        final candidate = _withSegmentHostKey(replacement, segment);
        return await _readCandidate(
          path,
          candidate,
          requestToken: requestToken,
        );
      } catch (error) {
        lastError = error;
      }
    }
    if (lastError != null) throw lastError;
    throw SourceError('NETWORK', '媒体分片读取失败');
  }

  Future<Uint8List> _readCandidate(
    String path,
    HlsSegment candidate, {
    CancelToken? requestToken,
  }) async {
    final previousHost = _routes[path]?.url.host;
    authorizeMediaResource(transport, candidate.url);
    if (candidate.key case final key?) authorizeMediaResource(transport, key);
    final token = CancelToken();
    var finished = false;
    void cancel(Object? reason) {
      if (!finished) token.cancel(reason);
    }

    unawaited(_cancel.whenCancel.then(cancel));
    if (requestToken != null) unawaited(requestToken.whenCancel.then(cancel));
    if (_cancel.isCancelled || (requestToken?.isCancelled ?? false)) {
      token.cancel();
    }
    try {
      final bytes = await _resources.read(candidate, requestToken: token);
      // 保留清单中的原始路由，避免缓存淘汰后把备用主机当作唯一来源，
      // 从而丢失这组分片原有的其他 CDN 候选。
      if (candidate.url.host != previousHost) {
        if (_cdnFallbackHosts(previousHost ?? '')
            .contains(candidate.url.host)) {
          _preferredCdnHost = candidate.url.host;
        }
        AppLog.debug({
          'event': 'hls_segment_fallback',
          'site': transport.policy.site,
          'sequence': candidate.sequence.toString(),
          'toHost': candidate.url.host,
        });
      }
      return bytes;
    } finally {
      finished = true;
      token.cancel('HLS CDN candidate finished');
    }
  }

  Uri? _keyForHost(HlsSegment segment, String host) {
    final key = segment.key;
    if (key == null) return null;
    return key.host == segment.url.host ? key.replace(host: host) : key;
  }

  List<String> _cdnFallbackHosts(String host) => host == 'mts.hhjd.mobi'
      ? const ['ts.zhixunkeji.xyz', 'tx.doudou520.online']
      : const [];

  HlsSegment _segmentOnHost(HlsSegment segment, String host) {
    return HlsSegment(
      segment.url.replace(host: host),
      segment.duration,
      key: _keyForHost(segment, host),
      iv: segment.iv,
      kind: segment.kind,
      sequence: segment.sequence,
    );
  }

  HlsSegment _withSegmentHostKey(HlsSegment candidate, HlsSegment original) {
    final key = candidate.key;
    final rewrittenKey = key == null
        ? null
        : key.host == original.url.host
        ? key.replace(host: candidate.url.host)
        : key;
    if (rewrittenKey == key) return candidate;
    return HlsSegment(
      candidate.url,
      candidate.duration,
      key: rewrittenKey,
      iv: candidate.iv,
      kind: candidate.kind,
      sequence: candidate.sequence,
    );
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      final path = request.uri.path;
      if (_closed ||
          request.uri.hasQuery ||
          (!_playlists.contains(path) &&
              !_routes.containsKey(path) &&
              !(_windows?.contains(path) ?? false))) {
        response.statusCode = HttpStatus.notFound;
      } else if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
      } else {
        final bytes = await _resource(path);
        response.headers.contentType = ContentType.parse(
          path.endsWith('.m3u8')
              ? 'application/vnd.apple.mpegurl'
              : (path.endsWith('.mp4') || path.endsWith('.m4s'))
              ? 'video/mp4'
              : 'video/mp2t',
        );
        response.headers.set('Accept-Ranges', 'bytes');
        response.headers.set('Cache-Control', 'no-store');
        var start = 0;
        var end = bytes.length - 1;
        final range = request.headers.value('range');
        if (range != null) {
          final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
          var valid =
              match != null && (match[1]!.isNotEmpty || match[2]!.isNotEmpty);
          if (valid) {
            if (match[1]!.isEmpty) {
              final suffix = int.tryParse(match[2]!);
              valid = suffix != null && suffix > 0;
              if (valid) start = max(0, bytes.length - suffix);
            } else {
              start = int.tryParse(match[1]!) ?? bytes.length;
              if (match[2]!.isNotEmpty) {
                end = min(end, int.tryParse(match[2]!) ?? -1);
              }
              valid = start <= end && start < bytes.length;
            }
          }
          if (!valid) {
            response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
            response.headers.set('Content-Range', 'bytes */${bytes.length}');
            await response.close();
            return;
          }
          response.statusCode = HttpStatus.partialContent;
          response.headers.set(
            'Content-Range',
            'bytes $start-$end/${bytes.length}',
          );
        }
        response.contentLength = end - start + 1;
        if (request.method != 'HEAD') {
          response.add(Uint8List.sublistView(bytes, start, end + 1));
        }
      }
    } catch (error, stack) {
      // The player only sees a 502, so record why the segment failed.
      _logSegment(error, stack);
      try {
        response.statusCode = HttpStatus.badGateway;
      } catch (_) {}
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  void _logSegment(Object error, StackTrace stack) {
    if (_closed ||
        (error is DioException && CancelToken.isCancel(error)) ||
        (error is SourceError && error.code == 'CANCELLED')) {
      return;
    }
    AppLog.error(
      error,
      event: 'media',
      site: transport.policy.site,
      action: 'segment',
      stack: error is SourceError ? null : stack,
    );
  }

  @override
  Future<void> close() => _closing ??= () async {
    _closed = true;
    _cancel.cancel('playback closed');
    try {
      await _server?.close(force: true);
    } finally {
      _server = null;
      try {
        await _windows?.close();
        await transport.close();
      } finally {
        _windows = null;
        _cache.clear();
        _routes.clear();
        _playlists.clear();
        _playlistPath = null;
        _resources.clear();
        _pending.clear();
        while (_resourceWaiters.isNotEmpty) {
          final waiter = _resourceWaiters.removeFirst();
          if (!waiter.isCompleted) waiter.complete();
        }
        _resourceLoads = 0;
        _cacheBytes = 0;
        await _disk?.close();
        _disk = null;
      }
    }
  }();
}
