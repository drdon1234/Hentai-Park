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
class NativeMedia
    implements MediaTransport, MediaSessionAuthority, MediaConnectionRecovery {
  NativeMedia(
    this.policy, {
    Map<String, String> headers = const {},
    Dio? client,
  }) : headers = policy.requestHeaders(headers),
       _proxy = AppSettings.instance.proxy,
       _client = client ?? _build(policy, AppSettings.instance.proxy);
  @override
  final MediaPolicy policy;
  final Map<String, String> headers;
  Dio _client;
  final String _proxy;
  final _requests = <CancelToken>{};
  bool _closed = false;
  static const _readIdleTimeout = Duration(seconds: 8);

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
            final task = await Socket.startConnect(addresses.first, uri.port);
            if (uri.scheme != 'https') return task;
            Socket? connected;
            var cancelled = false;
            final secured = task.socket.then((socket) async {
              connected = socket;
              if (cancelled) {
                socket.destroy();
                throw const SocketException('Media connection cancelled');
              }
              try {
                // Keep the checked IP while using the original host for SNI
                // and certificate validation. A custom factory owns TLS.
                final secure = await SecureSocket.secure(
                  socket,
                  host: uri.host,
                );
                connected = secure;
                if (cancelled) {
                  secure.destroy();
                  throw const SocketException('Media connection cancelled');
                }
                return secure;
              } catch (_) {
                socket.destroy();
                rethrow;
              }
            });
            return ConnectionTask.fromSocket(secured, () {
              cancelled = true;
              task.cancel();
              connected?.destroy();
            });
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
    Timer? idleTimer;
    void expectProgress() {
      idleTimer?.cancel();
      idleTimer = Timer(_readIdleTimeout, () {
        if (!result.isCompleted) {
          result.completeError(
            SourceError(
              'TIMEOUT',
              '请求超时',
              diagnostics: {'reason': 'RECEIVE_TIMEOUT'},
            ),
          );
        }
      });
    }

    expectProgress();
    final subscription = response.stream.listen(
      (chunk) {
        if (result.isCompleted) return;
        if (chunk.isNotEmpty) expectProgress();
        if (bytes.length + chunk.length > maxBytes) {
          result.completeError(SourceError('NETWORK', '媒体资源过大'));
        } else {
          bytes.add(chunk);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!result.isCompleted) {
          result.completeError(
            SourceError(
              'NETWORK',
              '媒体资源为空或不完整',
              diagnostics: {'reason': 'RESPONSE_STREAM'},
            ),
            stack,
          );
        }
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
      idleTimer?.cancel();
      await subscription.cancel();
    }
  }

  @override
  Future<MediaResponse> fetch(
    Uri url, {
    required int maxBytes,
    CancelToken? cancelToken,
  }) {
    if (maxBytes < 1 || maxBytes > 32 * 1024 * 1024) {
      throw ArgumentError.value(maxBytes, 'maxBytes');
    }
    return _request(url, maxBytes: maxBytes, cancelToken: cancelToken);
  }

  /// 大文件按流写入，沿用播放的地址、请求头和重定向隔离策略。
  Future<void> download(
    Uri url,
    File output, {
    required CancelToken cancelToken,
    required void Function(int received, int total) onProgress,
  }) async {
    if (policy.mode != 'native') throw SourceError('CONFIG', '媒体数据无效');
    await _request(
      url,
      output: output,
      cancelToken: cancelToken,
      onProgress: onProgress,
    );
  }

  Future<MediaResponse> _request(
    Uri url, {
    int maxBytes = 0,
    File? output,
    CancelToken? cancelToken,
    void Function(int, int)? onProgress,
  }) async {
    validate(url);
    final token = CancelToken();
    final timeout = output != null
        ? null
        : Timer(
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
          final Response<ResponseBody> response;
          try {
            response = await awaitCancelled(
              _client.get<ResponseBody>(
                target.toString(),
                options: Options(
                  responseType: ResponseType.stream,
                  followRedirects: false,
                  validateStatus: (_) => true,
                  sendTimeout: const Duration(seconds: 15),
                  receiveTimeout: _readIdleTimeout,
                  headers: {
                    'User-Agent': HttpService.instance.userAgent,
                    'Referer': '${policy.origin}/',
                    // Media segments are validated against Content-Length.
                    // Prevent transparent gzip negotiation from making the
                    // advertised length differ from the bytes delivered by
                    // Dio, which leaves Android HLS buffering indefinitely.
                    'Accept-Encoding': 'identity',
                    ...policy.headersFor(target, headers),
                  },
                ),
                cancelToken: requestToken,
              ),
              token,
            );
          } on DioException catch (e) {
            _check(token);
            if (CancelToken.isCancel(e)) rethrow;
            // The checked-address connection raises its own source error.
            if (e.error case final SourceError error) throw error;
            throw HttpService.transportError(e, target);
          }
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
            throw SourceError(
              'NETWORK',
              '媒体请求失败',
              status: status,
              diagnostics: {'host': target.host, 'transport': 'native'},
            );
          }
          final Uint8List bytes;
          if (output == null) {
            bytes = await _read(body, maxBytes, token);
          } else {
            final length = int.tryParse(
              response.headers.value('content-length') ?? '',
            );
            final encoding = response.headers.value('content-encoding');
            if (encoding != null && encoding != 'identity') {
              throw SourceError('NETWORK', '媒体资源为空或不完整');
            }
            final sink = await output.open(mode: FileMode.write);
            var received = 0;
            try {
              await for (final chunk in body.stream.timeout(_readIdleTimeout)) {
                _check(token);
                await sink.writeFrom(chunk);
                received += chunk.length;
                if (length != null && received > length) {
                  throw SourceError('NETWORK', '媒体资源为空或不完整');
                }
                onProgress?.call(received, length ?? 0);
              }
              await sink.flush();
              if (received == 0 || (length != null && length != received)) {
                throw SourceError('NETWORK', '媒体资源为空或不完整');
              }
            } finally {
              await sink.close();
            }
            bytes = Uint8List(0);
          }
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
      timeout?.cancel();
      await cancellation?.cancel();
      _requests.remove(token);
    }
  }

  @override
  void resetConnection() {
    if (_closed) return;
    final previous = _client;
    _client = _build(policy, _proxy);
    // 关闭旧池的空闲连接；进行中的并发分段继续完成。
    previous.close();
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
