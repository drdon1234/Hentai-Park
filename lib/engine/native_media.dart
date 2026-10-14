import 'dart:async';
import 'dart:io';

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../core/models.dart';
import '../core/settings.dart';
import 'cancellation.dart';
import 'http_service.dart';
import 'media_transport.dart';
import 'network_client.dart';
import 'public_media_address.dart';

/// A credential-free native media session. It owns a client rather than the
/// source HTTP service, so cookies, authentication and redirects stay isolated.
class NativeMedia implements MediaTransport, MediaSessionAuthority {
  NativeMedia(
    this.policy, {
    Map<String, String> headers = const {},
    Dio? client,
  }) : headers = policy.requestHeaders(headers),
       _proxy = AppSettings.instance.proxy,
       _client = client ?? _build(policy, AppSettings.instance.proxy);
  final MediaPolicy policy;
  final Map<String, String> headers;
  final Dio _client;
  final String _proxy;
  final _requests = <CancelToken>{};
  bool _closed = false;

  static Dio _build(MediaPolicy policy, String proxy) {
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15)));
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = createHttpClient(proxy: proxy);
        if (policy.session) {
          client.connectionFactory = (uri, proxyHost, proxyPort) async {
            if (proxyHost != null) {
              return Socket.startConnect(proxyHost, proxyPort!);
            }
            final addresses = await publicMediaAddresses(uri.host);
            return Socket.startConnect(addresses.first, uri.port);
          };
        }
        return client;
      },
    );
    return dio;
  }

  @override
  void authorize(Uri url) => policy.authorize(url);

  @override
  void validate(Uri url) => policy.validate(url);

  void _check(CancelToken token) {
    if (token.cancelError case final error?) throw error;
    if (_closed) throw SourceError('CANCELLED', '媒体会话已关闭');
  }

  Future<Uint8List> _read(
    ResponseBody response,
    int maxBytes,
    CancelToken token,
  ) async {
    final length = int.tryParse(
      response.headers['content-length']?.firstOrNull ?? '',
    );
    final encoding =
        response.headers['content-encoding']?.join(',').toLowerCase() ?? '';
    final result = Completer<Uint8List>();
    final bytes = BytesBuilder(copy: false);
    final subscription = response.stream.listen(
      (chunk) {
        if (result.isCompleted) return;
        if (bytes.length + chunk.length > maxBytes) {
          result.completeError(SourceError('NETWORK', '媒体资源过大'));
        } else {
          bytes.add(chunk);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      },
      onDone: () {
        if (result.isCompleted) return;
        if (bytes.isEmpty ||
            (length != null &&
                (encoding.isEmpty || encoding == 'identity') &&
                length != bytes.length)) {
          result.completeError(SourceError('NETWORK', '媒体资源为空或不完整'));
        } else {
          result.complete(bytes.takeBytes());
        }
      },
    );
    try {
      if (length != null && length > maxBytes) {
        throw SourceError('NETWORK', '媒体资源过大');
      }
      return await awaitCancelled(result.future, token);
    } finally {
      await subscription.cancel();
    }
  }

  @override
  Future<MediaResponse> fetch(
    Uri url, {
    required int maxBytes,
    CancelToken? cancelToken,
  }) async {
    validate(url);
    if (maxBytes < 1 || maxBytes > 32 * 1024 * 1024) {
      throw ArgumentError.value(maxBytes, 'maxBytes');
    }
    final token = CancelToken();
    final timeout = Timer(
      const Duration(seconds: 45),
      () => token.cancel('media timeout'),
    );
    if (_closed) token.cancel('media closed');
    if (cancelToken?.cancelError case final error?) token.cancel(error);
    final cancellation = cancelToken?.whenCancel.asStream().listen(
      token.cancel,
    );
    _requests.add(token);
    try {
      var target = url;
      for (var hop = 0; hop < 8; hop++) {
        _check(token);
        validate(target);
        if (policy.session && _proxy.isEmpty) {
          await publicMediaAddresses(target.host);
        }
        final requestToken = CancelToken();
        final requestCancellation = token.whenCancel.asStream().listen(
          requestToken.cancel,
        );
        try {
          final response = await awaitCancelled(
            _client.get<ResponseBody>(
              target.toString(),
              options: Options(
                responseType: ResponseType.stream,
                followRedirects: false,
                validateStatus: (_) => true,
                sendTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 40),
                headers: {
                  'User-Agent': HttpService.instance.userAgent,
                  'Referer': '${policy.origin}/',
                  ...headers,
                },
              ),
              cancelToken: requestToken,
            ),
            token,
          );
          _check(token);
          final body = response.data;
          if (body == null) throw SourceError('NETWORK', '媒体响应为空');
          final status = response.statusCode;
          if (const {301, 302, 303, 307, 308}.contains(status)) {
            await body.stream.listen((_) {}).cancel();
            final location = response.headers.value('location');
            if (location == null) throw SourceError('NETWORK', '媒体重定向地址缺失');
            target = target.resolve(location);
            policy.authorize(target);
            validate(target);
            continue;
          }
          if (status != 200) {
            await body.stream.listen((_) {}).cancel();
            throw SourceError('NETWORK', '媒体请求失败', status: status);
          }
          final bytes = await _read(body, maxBytes, token);
          _check(token);
          return MediaResponse(bytes, target);
        } finally {
          // Dio wraps the response stream without forwarding subscription
          // cancellation to its source. Cancel the per-hop request explicitly
          // when leaving a redirect, rejecting a body, or finishing a read.
          requestToken.cancel('media resource finished');
          await requestToken.whenCancel;
          await requestCancellation.cancel();
        }
      }
      throw SourceError('NETWORK', '媒体重定向次数过多');
    } finally {
      timeout.cancel();
      await cancellation?.cancel();
      _requests.remove(token);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final token in _requests.toList()) {
      token.cancel('media closed');
    }
    policy.revokeSession();
    _client.close(force: true);
  }
}
