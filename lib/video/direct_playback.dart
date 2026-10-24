import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../core/app_log.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../engine/http_service.dart';
import '../engine/media_transport.dart';
import '../engine/network_client.dart';
import 'playback.dart';
import 'playback_cache.dart';

/// 仅登记一个远端地址的流式会话；已下载的区间缓存在本次会话的临时文件中，
/// 往回拖动时直接读取，其余区间再向上游请求。
class DirectPlayback implements Playback {
  factory DirectPlayback(
    MediaPolicy policy, {
    Map<String, String> headers = const {},
    HttpClient? client,
  }) {
    if (policy.mode != 'native') throw SourceError('CONFIG', '媒体数据无效');
    final allowedHeaders = policy.requestHeaders(headers);
    return DirectPlayback._(
      policy,
      allowedHeaders,
      client ?? createHttpClient(proxy: AppSettings.instance.proxy),
    );
  }

  DirectPlayback._(this.policy, this.headers, this._client) {
    _client.autoUncompress = false;
  }

  final MediaPolicy policy;
  final Map<String, String> headers;
  final HttpClient _client;
  final _requests = <HttpClientRequest>{};
  final _token = List.generate(
    24,
    (_) => Random.secure().nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  HttpServer? _server;
  ByteRangeCache? _cache;
  Uri? _upstream;
  bool _opened = false;
  bool _closed = false;
  Future<void>? _closing;

  /// 静态白名单之外，`scope: 'session'` 只放行本次接口返回的地址及其重定向。
  void _validate(Uri url) => policy.validate(url);

  @override
  Future<Uri> open(Uri url) async {
    if (_closed || _opened) throw StateError('媒体会话不可重复打开');
    _opened = true;
    try {
      _validate(url);
      _upstream = url;
      _cache = await ByteRangeCache.open();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      if (_closed) {
        await server.close(force: true);
        throw SourceError('CANCELLED', '媒体会话已关闭');
      }
      _server = server;
      server.listen((request) => unawaited(_serve(request)));
      return Uri.parse('http://127.0.0.1:${server.port}/$_token/video.mp4');
    } catch (_) {
      await close();
      rethrow;
    }
  }

  /// 打开上游请求并逐跳校验重定向；调用方用 [_release] 结束返回的请求。
  Future<(HttpClientRequest, HttpClientResponse)> _open(
    String method,
    String? range,
    bool Function() disconnected,
    void Function(HttpClientRequest) track,
  ) async {
    var target = _upstream!;
    for (var hop = 0; hop < 8; hop++) {
      _validate(target);
      if (_closed || disconnected()) {
        throw SourceError('CANCELLED', '媒体会话已关闭');
      }
      var timedOut = false;
      final request = await _client
          .openUrl(method, target)
          .then((request) {
            if (_closed || disconnected() || timedOut) {
              request.abort();
              throw SourceError('CANCELLED', '媒体会话已关闭');
            }
            return request;
          })
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              timedOut = true;
              throw TimeoutException('Media connection timeout');
            },
          );
      _requests.add(request);
      track(request);
      try {
        request.followRedirects = false;
        request.headers.set('User-Agent', HttpService.instance.userAgent);
        request.headers.set('Referer', '${policy.origin}/');
        headers.forEach(request.headers.set);
        request.headers.set('Accept-Encoding', 'identity');
        if (range != null && method == 'GET') {
          request.headers.set('Range', range);
        }
        final response = await request.close().timeout(
          const Duration(seconds: 40),
        );
        if (const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
          final location = response.headers.value('location');
          if (location == null) throw SourceError('NETWORK', '媒体重定向地址缺失');
          target = target.resolve(location);
          if (policy.session) policy.authorize(target);
          _validate(target);
          _release(request);
          continue;
        }
        if (!const {200, 206, 416}.contains(response.statusCode)) {
          throw SourceError(
            'NETWORK',
            '媒体请求失败',
            status: response.statusCode,
            diagnostics: {'host': target.host, 'transport': 'native'},
          );
        }
        final encoding = response.headers.value('content-encoding');
        if (encoding != null && encoding.toLowerCase() != 'identity') {
          throw SourceError('NETWORK', '媒体数据无效');
        }
        return (request, response);
      } catch (_) {
        _release(request);
        rethrow;
      }
    }
    throw SourceError('NETWORK', '媒体重定向次数过多');
  }

  void _release(HttpClientRequest request) {
    request.abort();
    _requests.remove(request);
  }

  /// 上游响应在完整文件中的起点与总长度；无法确定时返回 null。
  static (int, int?)? _position(HttpClientResponse response) {
    if (response.statusCode == 200) {
      final length = response.contentLength;
      return (0, length >= 0 ? length : null);
    }
    if (response.statusCode != 206) return null;
    final match = RegExp(r'^bytes (\d+)-\d+/(\d+|\*)$')
        .firstMatch(response.headers.value('content-range') ?? '');
    if (match == null) return null;
    return (int.parse(match[1]!), int.tryParse(match[2]!));
  }

  /// 请求区间 [start, end]；格式已校验，越界时返回 null。
  static (int, int)? _bounds(String? range, int length) {
    if (length == 0) return null;
    if (range == null) return (0, length - 1);
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range)!;
    if (match[1]!.isEmpty) {
      final suffix = int.parse(match[2]!);
      if (suffix == 0) return null;
      return (length - min(suffix, length), length - 1);
    }
    final start = int.parse(match[1]!);
    final end = match[2]!.isEmpty
        ? length - 1
        : min(int.parse(match[2]!), length - 1);
    return start <= end ? (start, end) : null;
  }

  Future<void> _serve(HttpRequest incoming) async {
    final output = incoming.response;
    final active = <HttpClientRequest>{};
    var disconnected = false;
    void abort() {
      disconnected = true;
      for (final request in active) {
        request.abort();
      }
    }

    unawaited(
      output.done.then<void>((_) => abort(), onError: (Object _) => abort()),
    );
    try {
      if (_closed ||
          incoming.uri.path != '/$_token/video.mp4' ||
          incoming.uri.hasQuery) {
        output.statusCode = HttpStatus.notFound;
        return;
      }
      if (incoming.method != 'GET' && incoming.method != 'HEAD') {
        output.statusCode = HttpStatus.methodNotAllowed;
        output.headers.set('Allow', 'GET, HEAD');
        return;
      }
      final range = incoming.headers.value('range');
      if (range != null &&
          (range.length > 128 ||
              !RegExp(r'^bytes=(?:\d+-\d*|-\d+)$').hasMatch(range))) {
        output.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        return;
      }
      final cache = _cache;
      final length = cache?.length;
      if (cache != null && length != null && incoming.method == 'GET') {
        final bounds = _bounds(range, length);
        if (bounds == null) {
          output.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          output.headers.set('Content-Range', 'bytes */$length');
          return;
        }
        final (start, end) = bounds;
        output.statusCode = range == null
            ? HttpStatus.ok
            : HttpStatus.partialContent;
        if (cache.contentType case final type?) {
          output.headers.set('content-type', type);
        }
        output.headers.set('accept-ranges', 'bytes');
        if (range != null) {
          output.headers.set('content-range', 'bytes $start-$end/$length');
        }
        output.headers.set('Cache-Control', 'no-store');
        output.contentLength = end - start + 1;
        await _stream(
          output,
          cache,
          start,
          end + 1,
          () => disconnected,
          active,
        );
        return;
      }
      final (request, response) = await _open(
        incoming.method,
        range,
        () => disconnected,
        active.add,
      );
      try {
        output.statusCode = response.statusCode;
        // 不转发 Set-Cookie、Location 或站点会话头。
        for (final name in const [
          'content-type',
          'content-length',
          'content-range',
          'accept-ranges',
        ]) {
          final value = response.headers.value(name);
          if (value != null) output.headers.set(name, value);
        }
        output.headers.set('Cache-Control', 'no-store');
        final position = _position(response);
        if (cache != null && position?.$2 != null) {
          cache.length ??= position!.$2;
          cache.contentType ??= response.headers.value('content-type');
        }
        if (incoming.method == 'GET') {
          var offset = position?.$1;
          await for (final chunk in response.timeout(
            const Duration(seconds: 40),
          )) {
            if (_closed || disconnected) return;
            output.add(chunk);
            if (offset != null && cache?.length != null) {
              unawaited(cache!.store(offset, Uint8List.fromList(chunk)));
            }
            if (offset != null) offset += chunk.length;
            await output.flush();
          }
        }
      } finally {
        _release(request);
      }
    } catch (error, stack) {
      if (!_closed && !disconnected) {
        AppLog.error(
          error,
          event: 'media',
          site: policy.site,
          action: 'direct',
          stack: error is SourceError ? null : stack,
        );
      }
      try {
        output.headers.clear();
        output.statusCode = HttpStatus.badGateway;
        output.contentLength = 0;
      } catch (_) {
        // 已发出部分响应时不能再返回成功的流结束标记。
        try {
          (await output.detachSocket(writeHeaders: false)).destroy();
        } catch (_) {}
      }
    } finally {
      try {
        await output.close();
      } catch (_) {}
    }
  }

  /// 输出 [start, end)：已缓存部分读本地文件，空洞向上游补齐并写入缓存。
  Future<void> _stream(
    HttpResponse output,
    ByteRangeCache cache,
    int start,
    int end,
    bool Function() disconnected,
    Set<HttpClientRequest> active,
  ) async {
    var position = start;
    while (position < end) {
      if (_closed || disconnected()) return;
      final cached = min(cache.cachedEnd(position), end);
      if (cached > position) {
        final length = min(cached - position, 256 * 1024);
        output.add(await cache.read(position, length));
        position += length;
        await output.flush();
        continue;
      }
      final gapEnd = min(cache.nextCached(position) ?? end, end);
      final (request, response) = await _open(
        'GET',
        'bytes=$position-${gapEnd - 1}',
        disconnected,
        active.add,
      );
      try {
        // 不支持区间请求的上游会返回整份文件，此时跳过前面的字节。
        var offset = _position(response)?.$1;
        if (offset == null || offset > position) {
          throw SourceError('NETWORK', '媒体数据无效');
        }
        await for (final chunk in response.timeout(
          const Duration(seconds: 40),
        )) {
          if (_closed || disconnected()) return;
          final chunkStart = offset!, chunkEnd = chunkStart + chunk.length;
          offset = chunkEnd;
          final from = max(chunkStart, position), to = min(chunkEnd, gapEnd);
          if (to > from) {
            final bytes = Uint8List.fromList(
              chunk.sublist(from - chunkStart, to - chunkStart),
            );
            output.add(bytes);
            unawaited(cache.store(from, bytes));
            position = to;
            await output.flush();
          }
          if (position >= gapEnd) break;
        }
        if (position < gapEnd) throw SourceError('NETWORK', '媒体数据不完整');
      } finally {
        _release(request);
      }
    }
  }

  @override
  Future<void> close() => _closing ??= () async {
    _closed = true;
    for (final request in _requests.toList()) {
      request.abort();
    }
    _client.close(force: true);
    policy.revokeSession();
    await _server?.close(force: true);
    _server = null;
    _upstream = null;
    await _cache?.close();
    _cache = null;
  }();
}
