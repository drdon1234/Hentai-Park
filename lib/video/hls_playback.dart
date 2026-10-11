import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/models.dart';
import '../engine/browser_media.dart';
import 'hls.dart';

/// A private, finite URL registry. The player never supplies an upstream URL.
class HlsPlayback {
  HlsPlayback(this.transport);
  final MediaTransport transport;
  final _cancel = CancelToken();
  final _routes = <String, Uri>{};
  final _paths = <Uri, String>{};
  final Map<String, Uint8List> _cache = {};
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

  Future<Uri> open(Uri url) async {
    if (_closed || _server != null) throw StateError('媒体会话不可重复打开');
    try {
      transport.validate(url);
      final data = await transport.fetch(
        url,
        maxBytes: 2 * 1024 * 1024,
        cancelToken: _cancel,
      );
      final list = HlsPlaylist.parse(utf8.decode(data), url);
      for (final segment in list.segments) {
        transport.validate(segment.url);
      }
      if (_closed) throw SourceError('CANCELLED', '媒体会话已关闭');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      if (_closed) {
        await server.close(force: true);
        throw SourceError('CANCELLED', '媒体会话已关闭');
      }
      _server = server;
      final root = _register(url, playlist: true);
      final rewritten = Uint8List.fromList(
        utf8.encode(list.rewrite((u) => _register(u).toString())),
      );
      _cache[root.path] = rewritten;
      _cacheBytes += rewritten.length;
      server.listen((request) => unawaited(_serve(request)));
      return root;
    } catch (_) {
      await close();
      rethrow;
    }
  }

  Uri _register(Uri url, {bool playlist = false}) {
    final path = _paths.putIfAbsent(url, () {
      final path = '/$_token/r${_routes.length}.${playlist ? 'm3u8' : 'ts'}';
      _routes[path] = url;
      return path;
    });
    return Uri.parse('http://127.0.0.1:${_server!.port}$path');
  }

  Future<Uint8List> _resource(String path) async {
    final cached = _cache.remove(path);
    if (cached != null) {
      _cache[path] = cached;
      return cached;
    }
    if (_pending[path] case final future?) return future;
    if (_pending.length >= 8) throw SourceError('NETWORK', '播放器请求过多');
    final operation = () async {
      final bytes = await transport.fetch(
        _routes[path]!,
        maxBytes: 32 * 1024 * 1024,
        cancelToken: _cancel,
      );
      validateTransportStream(bytes);
      if (_closed) throw SourceError('CANCELLED', '媒体会话已关闭');
      if (bytes.length <= _cacheLimit) {
        while (_cacheBytes + bytes.length > _cacheLimit && _cache.length > 1) {
          // Keep the rewritten manifest for retries. Segment data is a bounded LRU.
          final victim = _cache.keys.firstWhere(
            (key) => !key.endsWith('.m3u8'),
          );
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
      _pending.remove(path);
    }
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      final path = request.uri.path;
      if (_closed || request.uri.hasQuery || !_routes.containsKey(path)) {
        response.statusCode = HttpStatus.notFound;
      } else if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
      } else {
        final bytes = await _resource(path);
        response.headers.contentType = ContentType.parse(
          path.endsWith('.m3u8')
              ? 'application/vnd.apple.mpegurl'
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
    } catch (_) {
      try {
        response.statusCode = HttpStatus.badGateway;
      } catch (_) {}
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }

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
        _paths.clear();
        _pending.clear();
        _cacheBytes = 0;
      }
    }
  }();
}
