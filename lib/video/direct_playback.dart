import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../core/app_log.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../engine/domains.dart';
import '../engine/http_service.dart';
import '../engine/media_transport.dart';
import '../engine/network_client.dart';
import 'playback.dart';

/// 仅登记一个远端地址的流式会话；不缓存整部影片，Range 原样交给上游。
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
  Uri? _upstream;
  bool _opened = false;
  bool _closed = false;
  Future<void>? _closing;

  void _validate(Uri url) {
    policy.validate(url);
    // MP4 的每次跳转都必须匹配静态白名单，不能借用动态 HLS 授权。
    if (!httpsDomainAddressAllowed(url, policy.domains)) {
      throw SourceError('CONFIG', '媒体地址不在站点声明的 HTTPS 域名内');
    }
  }

  @override
  Future<Uri> open(Uri url) async {
    if (_closed || _opened) throw StateError('媒体会话不可重复打开');
    _opened = true;
    try {
      _validate(url);
      _upstream = url;
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

  Future<void> _serve(HttpRequest incoming) async {
    final output = incoming.response;
    HttpClientRequest? active;
    var disconnected = false;
    void abort() {
      disconnected = true;
      active?.abort();
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
      var target = _upstream!;
      for (var hop = 0; hop < 8; hop++) {
        _validate(target);
        if (_closed || disconnected) return;
        var timedOut = false;
        final request = await _client
            .openUrl(incoming.method, target)
            .then((request) {
              if (_closed || disconnected || timedOut) {
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
        active = request;
        _requests.add(request);
        try {
          if (_closed || disconnected) return;
          request.followRedirects = false;
          request.headers.set('User-Agent', HttpService.instance.userAgent);
          request.headers.set('Referer', '${policy.origin}/');
          headers.forEach(request.headers.set);
          request.headers.set('Accept-Encoding', 'identity');
          if (range != null && incoming.method == 'GET') {
            request.headers.set('Range', range);
          }
          final response = await request.close().timeout(
            const Duration(seconds: 40),
          );
          if (const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
            final location = response.headers.value('location');
            if (location == null) throw SourceError('NETWORK', '媒体重定向地址缺失');
            target = target.resolve(location);
            _validate(target);
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
          if (incoming.method == 'GET') {
            await output.addStream(
              response.timeout(const Duration(seconds: 40)),
            );
          }
          return;
        } finally {
          request.abort();
          _requests.remove(request);
          active = null;
        }
      }
      throw SourceError('NETWORK', '媒体重定向次数过多');
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
  }();
}
