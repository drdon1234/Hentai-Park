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
  String userAgent = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';

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
  Future<Map<String, Object?>> sourceRequest(Map<String, dynamic> o, {required String partition, required List<String> domains}) async {
    if (o['mode'] == 'browser') {
      final origin = (o['origin'] ?? '').toString();
      final host = Uri.tryParse(origin.isNotEmpty ? origin : o['url'].toString())?.host ?? '';
      if (!hostInDomains(host, domains)) {
        throw SourceError('CONFIG', '浏览器模式只能访问源声明的域名（$host 不在 ${domains.join(', ')} 中）');
      }
      return BrowserFetcher.instance.fetch(origin: origin, request: o);
    }
    final res = await send(
      partition: partition,
      method: (o['method'] ?? 'GET').toString(),
      url: o['url'].toString(),
      headers: (o['headers'] as Map? ?? {}).map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')),
      body: o['body']?.toString(),
      timeout: o['timeout'] is num ? Duration(milliseconds: (o['timeout'] as num).toInt()) : null,
    );
    final body = o['responseType'] == 'base64' ? base64Encode(res.bytes) : res.text;
    return {'status': res.status, 'headers': res.headers, 'body': body, 'url': res.url};
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
    var uri = Uri.parse(url);
    var currentMethod = method.toUpperCase();
    Object? currentBody = body;
    for (var hop = 0; hop < 8; hop++) {
      // dart:io can only inflate gzip/deflate, so never advertise br/zstd even if a source asks for it.
      final h = <String, String>{'User-Agent': userAgent, ...headers}..removeWhere((k, _) => k.toLowerCase() == 'accept-encoding');
      h['Accept-Encoding'] = 'gzip, deflate';
      if (!h.keys.any((k) => k.toLowerCase() == 'cookie')) {
        final cookie = await CookieStore.instance.headerFor(uri, partition: partition);
        if (cookie.isNotEmpty) h['Cookie'] = cookie;
      }
      h.removeWhere((k, v) => v.isEmpty && k.toLowerCase() != 'authorization');
      Response<List<int>> res;
      try {
        res = await _dio.requestUri<List<int>>(
          uri,
          data: currentBody,
          cancelToken: cancelToken,
          onReceiveProgress: onProgress,
          options: Options(method: currentMethod, headers: h, receiveTimeout: timeout, sendTimeout: timeout),
        );
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        throw SourceError('NETWORK', '${uri.host}: ${_describe(e)}', url: url);
      }
      final setCookies = res.headers.map['set-cookie'] ?? const [];
      if (setCookies.isNotEmpty) await CookieStore.instance.saveFromResponse(uri, setCookies, partition: partition);
      final status = res.statusCode ?? 0;
      final location = res.headers.value('location');
      if (status >= 300 && status < 400 && location != null) {
        uri = uri.resolve(location);
        if (status == 303 || ((status == 301 || status == 302) && currentMethod == 'POST')) {
          currentMethod = 'GET';
          currentBody = null;
        }
        continue;
      }
      final result = HttpResult(
        status: status,
        headers: {for (final e in res.headers.map.entries) e.key.toLowerCase(): e.value.join(', ')},
        bytes: Uint8List.fromList(res.data ?? const []),
        url: uri.toString(),
      );
      if (detectCloudflare && result.isCloudflareChallenge) {
        throw SourceError('CLOUDFLARE', 'Cloudflare 验证：${uri.host}', status: status, url: uri.toString());
      }
      return result;
    }
    throw SourceError('NETWORK', '重定向次数过多：$url', url: url);
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
    final uri = Uri.parse(url);
    final h = <String, String>{'User-Agent': userAgent, ...headers};
    final cookie = await CookieStore.instance.headerFor(uri, partition: partition);
    if (cookie.isNotEmpty) h['Cookie'] = cookie;
    try {
      final res = await _dio.downloadUri(
        uri,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: onProgress,
        options: Options(headers: h, followRedirects: true, receiveTimeout: const Duration(minutes: 5)),
      );
      final status = res.statusCode ?? 0;
      if (status < 200 || status >= 300) throw SourceError('HTTP', '下载失败：HTTP $status', status: status, url: url);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      throw SourceError('NETWORK', '${uri.host}: ${_describe(e)}', url: url);
    }
  }

  static String _describe(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return '连接超时';
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return '响应超时';
      case DioExceptionType.connectionError:
        return '无法连接（${e.error ?? e.message}）';
      default:
        return e.message ?? e.error?.toString() ?? e.type.name;
    }
  }
}

class HttpResult {
  HttpResult({required this.status, required this.headers, required this.bytes, required this.url});
  final int status;
  final Map<String, String> headers;
  final Uint8List bytes;
  final String url;

  bool get ok => status >= 200 && status < 300;

  String get text {
    final type = headers['content-type'] ?? '';
    final charset = RegExp(r'charset=([\w-]+)', caseSensitive: false).firstMatch(type)?.group(1)?.toLowerCase();
    if (charset != null && charset != 'utf-8' && charset != 'utf8') {
      final enc = Encoding.getByName(charset);
      if (enc != null) return enc.decode(bytes);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  bool get isCloudflareChallenge {
    if (status != 403 && status != 503 && status != 429) return false;
    if (headers['cf-mitigated'] == 'challenge') return true;
    if (!(headers['server'] ?? '').toLowerCase().contains('cloudflare')) return false;
    final head = utf8.decode(bytes.length > 4096 ? bytes.sublist(0, 4096) : bytes, allowMalformed: true);
    return head.contains('Just a moment') || head.contains('cf-chl') || head.contains('Attention Required') || head.contains('challenge-platform');
  }
}
