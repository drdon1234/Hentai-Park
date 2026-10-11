import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../core/models.dart';
import '../core/settings.dart';
import 'browser_fetcher.dart';
import 'cookie_store.dart';
import 'domains.dart';

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
    AppSettings.instance.addListener(() {
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
      createHttpClient: () {
        final client = HttpClient()
          ..maxConnectionsPerHost = 8
          ..idleTimeout = const Duration(seconds: 30)
          ..autoUncompress = true;
        final proxy = _proxy.replaceFirst(RegExp(r'^https?://'), '');
        if (proxy.isNotEmpty) client.findProxy = (_) => 'PROXY $proxy';
        return client;
      },
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
    if (o['mode'] == 'browser') {
      final origin = (o['origin'] ?? '').toString();
      final target = _httpUri(o['url'].toString());
      final page = _httpUri(origin.isNotEmpty ? origin : target.toString());
      if (!hostInDomains(page.host, domains) ||
          !hostInDomains(target.host, domains) ||
          page.scheme != target.scheme ||
          page.host != target.host ||
          page.port != target.port) {
        throw SourceError('CONFIG', '浏览器模式只能访问源声明的同源地址');
      }
      final result = await BrowserFetcher.instance.fetch(
        origin: origin,
        request: o,
        cancelToken: cancelToken,
      );
      _throwIfCancelled(cancelToken);
      return result;
    }
    final res = await send(
      partition: partition,
      method: (o['method'] ?? 'GET').toString(),
      url: o['url'].toString(),
      headers: (o['headers'] as Map? ?? {}).map(
        (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
      ),
      body: o['body']?.toString(),
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
  }) async {
    final res = await _request(
      method: method,
      url: url,
      headers: headers,
      body: body,
      timeout: timeout,
      partition: partition,
      cancelToken: cancelToken,
    );
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in _responseStream(
      res,
      timeout,
      cancelToken,
      onProgress,
    )) {
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
        'Cloudflare 验证：${res.realUri.host}',
        status: result.status,
        url: result.url,
      );
    }
    return result;
  }

  // Both buffered requests and file downloads use the same explicit redirect policy.
  Future<Response<ResponseBody>> _request({
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
    for (var hop = 0; hop < 8; hop++) {
      _throwIfCancelled(cancelToken);
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
      h.removeWhere((k, v) => v.isEmpty && k.toLowerCase() != 'authorization');
      Response<ResponseBody> res;
      try {
        res = await _dio.requestUri<ResponseBody>(
          uri,
          data: currentBody,
          cancelToken: cancelToken,
          options: Options(
            method: currentMethod,
            headers: h,
            responseType: ResponseType.stream,
            followRedirects: false,
            receiveTimeout: timeout,
            sendTimeout: timeout,
          ),
        );
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        throw SourceError('NETWORK', _describe(e, uri.host), url: url);
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
      if ({301, 302, 303, 307, 308}.contains(status) && location != null) {
        // Close unused response bodies before dispatching the next hop.
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
            throw SourceError('NETWORK', '拒绝跨来源重定向携带请求体', url: next.toString());
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
      return res;
    }
    throw SourceError('NETWORK', '重定向次数过多：$url', url: url);
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
        '${response.realUri.host}: 响应读取失败（$error）',
        url: response.realUri.toString(),
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
    final res = await _request(
      method: 'GET',
      url: url,
      headers: headers,
      partition: partition,
      timeout: timeout,
      cancelToken: cancelToken,
    );
    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      await res.data!.stream.listen(null).cancel();
      throw SourceError('HTTP', '下载失败：HTTP $status', status: status, url: url);
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
  }

  static String _describe(DioException e, String host) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return '$host: 连接超时';
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return '$host: 响应超时';
      case DioExceptionType.connectionError:
        return '$host: 无法连接（${e.error ?? e.message}）';
      default:
        return '$host: ${e.message ?? e.error?.toString() ?? e.type.name}';
    }
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
    return head.contains('Just a moment') ||
        head.contains('cf-chl') ||
        head.contains('Attention Required') ||
        head.contains('challenge-platform');
  }
}
