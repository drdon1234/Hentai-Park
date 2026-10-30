import 'dart:async';
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
  final _manifestUrls = <Uri>{};
  final _segmentPaths = <String, String>{};
  Set<String> _currentPaths = {};
  Set<String> _previousPaths = {};
  int _nextRoute = 0;
  Future<Uint8List>? _refreshing;
  late final _resources = HlsResources(transport, _cancel);
  final Map<String, Uint8List> _cache = {};

  /// 点播分段在内存淘汰后仍保存在本次会话的临时文件中，往回拖动不再重新下载。
  SegmentCache? _disk;
  final _pending = <String, Future<Uint8List>>{};
  final _token = List.generate(
    24,
    (_) => Random.secure().nextInt(256),
  ).map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  HttpServer? _server;
  Future<void>? _closing;
  bool _closed = false;
  int _cacheBytes = 0;
  static const _cacheLimit = 24 * 1024 * 1024;

  @override
  Future<Uri> open(Uri url) async {
    if (_closed || _server != null) throw StateError('媒体会话不可重复打开');
    try {
      transport.validate(url);
      final audio = this.audio;
      if (audio != null) {
        // 直播窗口刷新只跟踪单个媒体清单。
        if (live) throw SourceError('UNSUPPORTED', 'HLS 使用了不支持的媒体格式');
        authorizeMediaResource(transport, audio.playlist);
      }
      _upstream = url;
      _manifestUrls.add(url);
      final list = await _mediaPlaylist(url);
      final audioList = audio == null
          ? null
          : await _mediaPlaylist(audio.playlist);
      if (!live) _disk = await SegmentCache.open();
      if (_closed) throw SourceError('CANCELLED', '媒体会话已关闭');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      if (_closed) {
        await server.close(force: true);
        throw SourceError('CANCELLED', '媒体会话已关闭');
      }
      _server = server;
      _playlistPath = '/$_token/index.m3u8';
      final root = Uri.parse('http://127.0.0.1:${server.port}$_playlistPath');
      if (audioList == null || audio == null) {
        _publish(root.path, list.rewrite((s) => _register(s).toString()));
      } else {
        final video = root.resolve('video.m3u8');
        final sound = root.resolve('audio.m3u8');
        _publish(video.path, list.rewrite((s) => _register(s).toString()));
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

  Future<HlsPlaylist> _mediaPlaylist(Uri url) async {
    final response = await transport.fetch(
      url,
      maxBytes: 2 * 1024 * 1024,
      cancelToken: _cancel,
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

  void _publish(String path, String playlist) {
    final bytes = Uint8List.fromList(utf8.encode(playlist));
    _playlists.add(path);
    _cache[path] = bytes;
    _cacheBytes += bytes.length;
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
    if (live && path == _playlistPath) return _livePlaylist();
    final cached = _cache.remove(path);
    if (cached != null) {
      _cache[path] = cached;
      return cached;
    }
    if (_pending[path] case final future?) return future;
    if (_pending.length >= 8) throw SourceError('NETWORK', '播放器请求过多');
    final operation = () async {
      final bytes =
          await _disk?.read(path) ?? await _resources.read(_routes[path]!);
      if (_closed) throw SourceError('CANCELLED', '媒体会话已关闭');
      await _disk?.store(path, bytes);
      if (bytes.length <= _cacheLimit) {
        while (_cacheBytes + bytes.length > _cacheLimit) {
          // Keep the rewritten manifests for retries. Segment data is a bounded LRU.
          final victim = _cache.keys
              .where((key) => !_playlists.contains(key))
              .firstOrNull;
          if (victim == null) break;
          _cacheBytes -= _cache.remove(victim)!.length;
        }
        if (_cacheBytes + bytes.length <= _cacheLimit) {
          _cache[path] = bytes;
          _cacheBytes += bytes.length;
        }
      }
      return bytes;
    }();
    _pending[path] = operation;
    try {
      return await operation;
    } finally {
      _pending.remove(path)?.ignore();
    }
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      final path = request.uri.path;
      if (_closed ||
          request.uri.hasQuery ||
          (!_playlists.contains(path) && !_routes.containsKey(path))) {
        response.statusCode = HttpStatus.notFound;
      } else if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
      } else {
        final bytes = await _resource(path);
        response.headers.contentType = ContentType.parse(
          path.endsWith('.m3u8')
              ? 'application/vnd.apple.mpegurl'
              : path.endsWith('.mp4')
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
    if (_closed || (error is DioException && CancelToken.isCancel(error))) {
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
        await transport.close();
      } finally {
        _cache.clear();
        _routes.clear();
        _playlists.clear();
        _playlistPath = null;
        _resources.clear();
        _pending.clear();
        _cacheBytes = 0;
        await _disk?.close();
        _disk = null;
      }
    }
  }();
}
