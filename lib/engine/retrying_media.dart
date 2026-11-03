import 'dart:async';

import 'package:dio/dio.dart';

import '../core/app_log.dart';
import '../core/models.dart';
import 'cancellation.dart';
import 'media_transport.dart';
import 'request_lifecycle.dart';

/// 媒体缓冲读取与站点文本请求使用相同的有限重试边界；下载可在后台继续。
class RetryingMedia implements MediaTransport, MediaSessionAuthority {
  RetryingMedia(this.inner, {this.foregroundRecovery = true});
  final MediaTransport inner;
  final bool foregroundRecovery;
  final _closed = CancelToken();
  @override
  MediaPolicy get policy => inner.policy;
  @override
  void validate(Uri url) => inner.validate(url);
  @override
  void authorize(Uri url) => authorizeMediaResource(inner, url);

  static bool transient(Object error) =>
      error is SourceError &&
      const {'NETWORK', 'HTTP', 'TIMEOUT'}.contains(error.code) &&
      (const {408, 500, 502, 503, 504}.contains(error.status) ||
          (const {'NETWORK', 'TIMEOUT'}.contains(error.code) &&
              const {
                'CONNECTION',
                'RESPONSE_STREAM',
                'CONNECT_TIMEOUT',
                'RECEIVE_TIMEOUT',
                'TLS_HANDSHAKE_TERMINATED',
              }.contains(error.diagnostics['reason'])));

  @override
  Future<MediaResponse> fetch(
    Uri url, {
    required int maxBytes,
    CancelToken? cancelToken,
  }) async {
    final token = CancelToken();
    final cancellation = cancelToken?.whenCancel.asStream().listen(
      token.cancel,
    );
    final closing = _closed.whenCancel.asStream().listen(token.cancel);
    if (_closed.cancelError case final error?) token.cancel(error);
    if (cancelToken?.cancelError case final error?) token.cancel(error);
    try {
      for (var attempt = 0; ; attempt++) {
        if (token.cancelError case final error?) throw error;
        final trace = AppLog.nextRequestId();
        final watch = Stopwatch()..start();
        AppLog.debug({
          'event': 'media_read',
          'site': policy.site,
          'transport': policy.mode,
          'host': url.host,
          'requestId': trace,
          'attempt': attempt,
          'outcome': 'started',
        });
        try {
          final response = await inner.fetch(
            url,
            maxBytes: maxBytes,
            cancelToken: token,
          );
          AppLog.debug({
            'event': 'media_read',
            'site': policy.site,
            'requestId': trace,
            'elapsedMs': watch.elapsedMilliseconds,
            'bytes': response.bytes.length,
            'outcome': 'success',
          });
          return response;
        } catch (error) {
          if (token.cancelError case final cancelled?) throw cancelled;
          if (attempt >= 2 || !transient(error)) rethrow;
          AppLog.record({
            'event': 'media_retry',
            'site': policy.site,
            'transport': policy.mode,
            'host': url.host,
            'attempt': attempt + 1,
            ...errorFields(error),
          });
          final delay = Duration(milliseconds: 400 * (attempt + 1));
          if (foregroundRecovery) {
            await RequestLifecycle.instance.retryDelay(delay, token);
          } else {
            await awaitCancelled(Future<void>.delayed(delay), token);
          }
        }
      }
    } finally {
      await cancellation?.cancel();
      await closing.cancel();
    }
  }

  static Map<String, Object?> errorFields(Object error) => error is SourceError
      ? {'code': error.code, 'status': error.status, ...error.diagnostics}
      : {};

  @override
  Future<void> close() {
    _closed.cancel('media closed');
    return inner.close();
  }
}
