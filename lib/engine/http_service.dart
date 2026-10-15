import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../core/models.dart';
import '../core/settings.dart';
import 'browser_fetcher.dart';
import 'challenge.dart';
import 'cookie_store.dart';
import 'domains.dart';
import 'network_client.dart';

/// 二进制传输仍通过同一域名隔离、TLS 和重定向策略。
Object? decodeSourceBody(Map<String, dynamic> request) {
  if (request['bodyBase64'] == null) return request['body']?.toString();
  if (request['body'] != null || request['mode'] == 'browser') {
    throw SourceError('CONFIG', '二进制请求参数无效');
  }
  final encoded = request['bodyBase64'];
  if (encoded is! String || encoded.length > 2796204) {
    throw SourceError('CONFIG', '二进制请求过大');
  }
  try {
    final bytes = base64Decode(encoded);
    if (bytes.length > 2097152) throw const FormatException();
    return bytes;
  } catch (_) {
    throw SourceError('CONFIG', '二进制请求参数无效');
  }
}

/// Native HTTP for sources and images: proxy, persistent cookies (redirect-aware),
/// Cloudflare challenge detection, and the browser-engine path for protected sites.
class HttpService {
  HttpService._();
  static final HttpService instance = HttpService._();

  /// Defaults to a current mobile Chrome UA; replaced with the WebView UA at startup so that
  /// Cloudflare clearance cookies obtained in the WebView stay valid for native requests.
  String userAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';

  late Dio _dio;
  String _proxy = '';

  void init() {
    _proxy = AppSettings.instance.proxy;
    _dio = _build();
    AppSettings.instance.watch(const {'proxy'}).addListener(() {
      if (AppSettings.instance.proxy != _proxy) {
        _proxy = AppSettings.instance.proxy;
        _dio.close();
        _dio = _build();
      }
    });
  }

  Dio _build() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 60),
        followRedirects: false,
        validateStatus: (_) => true,
        responseType: ResponseType.bytes,
      ),
    );
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => createHttpClient(proxy: _proxy),
    );
    return dio;
  }

  /// Executes a request issued by a source script. Returns {status, headers, body, url}.
  /// [partition] is the source the request is attributed to (its cookie jar); browser-mode requests
  /// are only allowed on the source's own [domains] because the WebView cookie store is shared.
  Future<Map<String, Object?>> sourceRequest(
    Map<String, dynamic> o, {
    required String partition,
    required List<String> domains,
    CancelToken? cancelToken,
  }) async {
    _throwIfCancelled(cancelToken);
    if (o['bodyBase64'] != null && o['mode'] == 'browser') {
      throw SourceError('CONFIG', '二进制请求参数无效');
    }
    if (o['mode'] == 'browser') {
      if (o['followRedirects'] == false) {
        throw SourceError('CONFIG', '浏览器请求不支持禁止重定向');
      }
      final origin = (o['origin'] ?? '').toString();
      final target = _httpUri(o['url'].toString());
      final page = _httpUri(origin.isNotEmpty ? origin : target.toString());
      if (!hostInDomains(page.host, domains) ||
          !hostInDomains(target.host, domains) ||
          page.scheme != target.scheme ||
          page.host != target.host ||
          page.port != target.port) {
        throw SourceError('CONFIG', '浏览器模式只能访问站点声明的同源地址');
      }
      await CookieStore.instance.restoreToWebView(target, partition: partition);
      _throwIfCancelled(cancelToken);
      final result = await BrowserFetcher.instance.fetch(
        origin: origin,
        request: o,
        cancelToken: cancelToken,
      );
      _throwIfCancelled(cancelToken);
      await CookieStore.instance.importFromWebView(
        target,
        partition: partition,
        authoritative: true,
      );
      return result;
    }
    final res = await send(
      followRedirects: o['followRedirects'] != false,
      partition: partition,
      method: (o['method'] ?? 'GET').toString(),
      url: o['url'].toString(),
      headers: (o['headers'] as Map? ?? {}).map(
        (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
      ),
      body: decodeSourceBody(o),
      timeout: o['timeout'] is num
          ? Duration(milliseconds: (o['timeout'] as num).toInt())
          : null,
      cancelToken: cancelToken,
    );
    final body = o['responseType'] == 'base64'
        ? base64Encode(res.bytes)
        : res.text;
    return {
      'status': res.status,
      'headers': res.headers,
      'body': body,
      'url': res.url,
    };
  }

  Future<HttpResult> send({
    required String method,
    required String url,
    Map<String, String> headers = const {},
    Object? body,
    Duration? timeout,
    String partition = CookieStore.appPartition,
    bool detectCloudflare = true,
    CancelToken? cancelToken,
    void Function(int received, int total)? onProgress,
    int? maxBytes,
    bool followRedirects = true,
    Future<void> Function(Uri)? beforeRequest,
  }) async {
    final resource = await _request(
      followRedirects: followRedirects,
      beforeRequest: beforeRequest,
      method: method,
      url: url,
      headers: headers,
      body: body,
      timeout: timeout,
      partition: partition,
      cancelToken: cancelToken,
    );
    final res = resource.response;
    try {
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in _responseStream(
        res,
        timeout,
        cancelToken,
        onProgress,
      )) {
        if (maxBytes != null && bytes.length + chunk.length > maxBytes) {
          throw SourceError('NETWORK', '媒体资源过大');
        }
        bytes.add(chunk);
      }
      final result = HttpResult(
        status: res.statusCode ?? 0,
        headers: {
          for (final e in res.headers.map.entries)
            e.key.toLowerCase(): e.value.join(', '),
        },
        bytes: bytes.takeBytes(),
        url: res.realUri.toString(),
      );
      if (detectCloudflare && result.isCloudflareChallenge) {
        throw SourceError(
          'CLOUDFLARE',
          'Cloudflare 验证：{host}',
          params: {'host': res.realUri.host},
          status: result.status,
          url: result.url,
        );
      }
      return result;
    } finally {
      await resource.close();
    }
  }

  // Both buffered requests and file downloads use the same explicit redirect policy.
  Future<_HttpResponse> _request({
    Future<void> Function(Uri)? beforeRequest,
    bool followRedirects = true,
    required String method,
    required String url,
    required Map<String, String> headers,
    required String partition,
    Object? body,
    Duration? timeout,
    CancelToken? cancelToken,
  }) async {
    var uri = _httpUri(url);
    var currentMethod = method.toUpperCase();
    Object? currentBody = body;
    final currentHeaders = Map<String, String>.of(headers);
    var handshakeRetried = false;
    for (var hop = 0; hop < 8; hop++) {
      _throwIfCancelled(cancelToken);
      await beforeRequest?.call(uri);
      _throwIfCancelled(cancelToken);
      final requestToken = CancelToken();
      final cancellation = cancelToken?.whenCancel.asStream().listen(
        requestToken.cancel,
      );
      var transferred = false;
      try {
        // dart:io can only inflate gzip/deflate, so never advertise br/zstd even if a source asks for it.
        final h = <String, String>{'User-Agent': userAgent, ...currentHeaders}
          ..removeWhere((k, _) => k.toLowerCase() == 'accept-encoding');
        h['Accept-Encoding'] = 'gzip, deflate';
        if (!h.keys.any((k) => k.toLowerCase() == 'cookie')) {
          final cookie = await CookieStore.instance.headerFor(
            uri,
            partition: partition,
          );
          if (cookie.isNotEmpty) h['Cookie'] = cookie;
        }
        h.removeWhere(
          (k, v) => v.isEmpty && k.toLowerCase() != 'authorization',
        );
        late Response<ResponseBody> res;
        while (true) {
          _throwIfCancelled(cancelToken);
          try {
            res = await _dio.requestUri<ResponseBody>(
              uri,
              data: currentBody,
              cancelToken: requestToken,
              options: Options(
                method: currentMethod,
                headers: h,
                responseType: ResponseType.stream,
                followRedirects: false,
                receiveTimeout: timeout,
                sendTimeout: timeout,
              ),
            );
            break;
          } on DioException catch (e) {
            if (CancelToken.isCancel(e)) rethrow;
            _throwIfCancelled(cancelToken);
            // This exact dart:io error occurs before HTTP is sent. Recover only
            // replayable reads, once per logical request, at the failed hop.
            if (!handshakeRetried &&
                uri.scheme == 'https' &&
                {'GET', 'HEAD'}.contains(currentMethod) &&
                currentBody == null &&
                _isHandshakeTerminated(e)) {
              handshakeRetried = true;
              final delay = Future<void>.delayed(
                const Duration(milliseconds: 250),
              );
              if (cancelToken == null) {
                await delay;
              } else {
                await Future.any<void>([
                  delay,
                  cancelToken.whenCancel.then<void>((error) => throw error),
                ]);
              }
              continue;
            }
            throw transportError(e, uri);
          }
        }
        _throwIfCancelled(cancelToken);
        final setCookies = res.headers.map['set-cookie'] ?? const [];
        if (setCookies.isNotEmpty) {
          await CookieStore.instance.saveFromResponse(
            uri,
            setCookies,
            partition: partition,
          );
        }
        _throwIfCancelled(cancelToken);
        final status = res.statusCode ?? 0;
        final location = res.headers.value('location');
        if (followRedirects &&
            {301, 302, 303, 307, 308}.contains(status) &&
            location != null) {
          // Close unused response bodies before dispatching the next hop.
          requestToken.cancel('redirect response discarded');
          await res.data!.stream.listen(null).cancel();
          final next = _httpUri(uri.resolve(location).toString());
          if (uri.scheme == 'https' && next.scheme != 'https') {
            throw SourceError(
              'NETWORK',
              '拒绝从 HTTPS 重定向到不安全的 HTTP 地址',
              url: next.toString(),
            );
          }
          if (status == 303 ||
              ((status == 301 || status == 302) && currentMethod == 'POST')) {
            currentMethod = 'GET';
            currentBody = null;
            currentHeaders.removeWhere(
              (name, _) => {
                'content-type',
                'content-length',
                'transfer-encoding',
              }.contains(name.toLowerCase()),
            );
          }
          if (uri.scheme != next.scheme ||
              uri.host != next.host ||
              uri.port != next.port) {
            if (currentBody != null) {
              throw SourceError(
                'NETWORK',
                '拒绝跨来源重定向携带请求体',
                url: next.toString(),
              );
            }
            // Custom source headers can contain arbitrary credentials. Carry only known
            // non-secret HTTP headers across origins; destination cookies are loaded afresh.
            currentHeaders.removeWhere(
              (name, _) => !_redirectHeaders.contains(name.toLowerCase()),
            );
          }
          uri = next;
          continue;
        }
        transferred = true;
        return _HttpResponse(res, requestToken, cancellation);
      } finally {
        if (!transferred) {
          requestToken.cancel('HTTP request finished');
          await cancellation?.cancel();
        }
      }
    }
    throw SourceError(
      'NETWORK',
      '重定向次数过多：{url}',
      params: {'url': url},
      url: url,
    );
  }

  static const _redirectHeaders = {
    'user-agent',
    'accept',
    'accept-language',
    'accept-encoding',
    'range',
    'cache-control',
    'pragma',
    'content-type',
  };

  static Uri _httpUri(String value) {
    final uri = Uri.parse(value);
    if (!{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw SourceError('CONFIG', '请求地址必须是有效的 HTTP 或 HTTPS 地址', url: value);
    }
    return uri;
  }

  Stream<Uint8List> _responseStream(
    Response<ResponseBody> response,
    Duration? timeout,
    CancelToken? cancelToken,
    void Function(int, int)? onProgress,
  ) async* {
    var received = 0;
    final total =
        int.tryParse(response.headers.value('content-length') ?? '') ?? -1;
    try {
      await for (final chunk in response.data!.stream.timeout(
        timeout ?? const Duration(seconds: 60),
      )) {
        _throwIfCancelled(cancelToken);
        received += chunk.length;
        onProgress?.call(received, total);
        yield chunk;
      }
      _throwIfCancelled(cancelToken);
    } catch (error) {
      _throwIfCancelled(cancelToken);
      if (error is SourceError) rethrow;
      throw SourceError(
        'NETWORK',
        '{host}: 响应读取失败（{error}）',
        params: {'host': response.realUri.host, 'error': '$error'},
        url: response.realUri.toString(),
        diagnostics: {
          'host': response.realUri.host,
          'transport': 'native',
          'reason': 'RESPONSE_STREAM',
        },
      );
    }
  }

  static void _throwIfCancelled(CancelToken? token) {
    final error = token?.cancelError;
    if (error != null) throw error;
  }

  /// Streams a (large) response straight to [savePath].
  Future<void> download({
    required String url,
    required String savePath,
    Map<String, String> headers = const {},
    String partition = CookieStore.appPartition,
    CancelToken? cancelToken,
    void Function(int received, int total)? onProgress,
  }) async {
    const timeout = Duration(minutes: 5);
    final resource = await _request(
      method: 'GET',
      url: url,
      headers: headers,
      partition: partition,
      timeout: timeout,
      cancelToken: cancelToken,
    );
    final res = resource.response;
    try {
      final status = res.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        await resource.close();
        throw SourceError(
          'HTTP',
          '下载失败：HTTP {status}',
          params: {'status': status},
          status: status,
          url: url,
        );
      }
      final file = File(savePath);
      final sink = file.openWrite();
      try {
        await sink.addStream(
          _responseStream(res, timeout, cancelToken, onProgress),
        );
        await sink.flush();
        _throwIfCancelled(cancelToken);
      } catch (_) {
        await sink.close().catchError((Object _) {});
        if (await file.exists()) await file.delete();
        rethrow;
      } finally {
        await sink.close();
      }
    } finally {
      await resource.close();
    }
  }

  /// The error for a request that failed before a response arrived.
  static SourceError transportError(DioException e, Uri uri) {
    final (message, params) = _describe(e, uri.host);
    return SourceError(
      'NETWORK',
      message,
      params: params,
      url: uri.toString(),
      diagnostics: {
        'host': uri.host,
        'transport': 'native',
        'reason': _failureReason(e),
      },
    );
  }

  /// A message template and its values for a failed request.
  static (String, Map<String, Object?>) _describe(DioException e, String host) {
    if (_isHandshakeTerminated(e)) {
      return ('{host}: TLS 握手期间连接中断，请检查 VPN 或代理线路后重试', {'host': host});
    }
    if (e.error is HandshakeException || e.error is TlsException) {
      return (
        '{host}: TLS 握手失败（{error}）',
        {'host': host, 'error': '${e.error}'},
      );
    }
    return switch (e.type) {
      DioExceptionType.connectionTimeout => ('{host}: 连接超时', {'host': host}),
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout => ('{host}: 响应超时', {'host': host}),
      DioExceptionType.connectionError => (
        '{host}: 无法连接（{error}）',
        {'host': host, 'error': '${e.error ?? e.message}'},
      ),
      _ => (
        '{host}: {error}',
        {
          'host': host,
          'error': e.error?.toString() ?? e.message ?? e.type.name,
        },
      ),
    };
  }

  static String _failureReason(DioException e) {
    final cause = e.error;
    if (e.type == DioExceptionType.badCertificate ||
        (cause is TlsException &&
            RegExp(
              'CERTIFICATE_VERIFY_FAILED|certificate verify failed',
              caseSensitive: false,
            ).hasMatch(cause.toString()))) {
      return 'TLS_CERTIFICATE';
    }
    if (_isHandshakeTerminated(e)) return 'TLS_HANDSHAKE_TERMINATED';
    if (cause is TlsException) return 'TLS_HANDSHAKE';
    if (cause is SocketException) {
      return RegExp(
            'host lookup|name.*resolution|name.*known',
            caseSensitive: false,
          ).hasMatch(cause.message)
          ? 'DNS'
          : 'CONNECTION';
    }
    return switch (e.type) {
      DioExceptionType.connectionTimeout => 'CONNECT_TIMEOUT',
      DioExceptionType.receiveTimeout => 'RECEIVE_TIMEOUT',
      DioExceptionType.sendTimeout => 'SEND_TIMEOUT',
      DioExceptionType.connectionError => 'CONNECTION',
      _ => 'NETWORK',
    };
  }

  static bool _isHandshakeTerminated(DioException e) {
    final cause = e.error;
    return e.type != DioExceptionType.badCertificate &&
        cause is HandshakeException &&
        cause.message == 'Connection terminated during handshake';
  }
}

/// Owns the adapter request for as long as its response body is in use.
/// Dio's exposed stream does not propagate subscription cancellation to the
/// adapter, so release the request token explicitly on every exit path.
class _HttpResponse {
  _HttpResponse(this.response, this.token, this.cancellation);
  final Response<ResponseBody> response;
  final CancelToken token;
  final StreamSubscription<DioException>? cancellation;
  bool _closed = false;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    token.cancel('HTTP response released');
    await cancellation?.cancel();
  }
}

class HttpResult {
  HttpResult({
    required this.status,
    required this.headers,
    required this.bytes,
    required this.url,
  });
  final int status;
  final Map<String, String> headers;
  final Uint8List bytes;
  final String url;

  bool get ok => status >= 200 && status < 300;

  String get text {
    final type = headers['content-type'] ?? '';
    final charset = RegExp(
      r'charset=([\w-]+)',
      caseSensitive: false,
    ).firstMatch(type)?.group(1)?.toLowerCase();
    if (charset != null && charset != 'utf-8' && charset != 'utf8') {
      final enc = Encoding.getByName(charset);
      if (enc != null) return enc.decode(bytes);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  bool get isCloudflareChallenge {
    if (status != 403 && status != 503 && status != 429) return false;
    if (headers['cf-mitigated'] == 'challenge') return true;
    if (!(headers['server'] ?? '').toLowerCase().contains('cloudflare')) {
      return false;
    }
    final head = utf8.decode(
      bytes.length > 4096 ? bytes.sublist(0, 4096) : bytes,
      allowMalformed: true,
    );
    return hasChallengeMarkers(head);
  }
}
