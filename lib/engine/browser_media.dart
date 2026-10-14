import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/async_tasks.dart';
import '../core/models.dart';
import 'challenge.dart';
import 'http_service.dart';
import 'media_transport.dart';

/// One hidden page per playback/download. Closing it aborts and releases all requests.
class BrowserMedia implements MediaTransport {
  BrowserMedia(this.policy, {Map<String, String> headers = const {}})
    : headers = policy.requestHeaders(headers);
  final MediaPolicy policy;
  final Map<String, String> headers;
  final _closed = Completer<void>();
  final _closingEvents = StreamController<void>.broadcast(sync: true);
  HeadlessInAppWebView? _view;
  InAppWebViewController? _controller;
  Future<void>? _ready;
  Future<void>? _starting;
  Future<void>? _viewDisposal;
  final _queue = SerialExecutor();
  Future<void>? _closing;
  int _nextId = 0;

  @override
  void validate(Uri url) => policy.validate(url);

  Future<T> _untilClosed<T>(Future<T> work, CancelToken? token) async {
    final result = Completer<T>();
    void fail(Object error) {
      if (!result.isCompleted) result.completeError(error);
    }

    final closing = _closingEvents.stream.listen(
      (_) => fail(SourceError('CANCELLED', '媒体会话已关闭')),
    );
    final cancellation = token?.whenCancel.asStream().listen(fail);
    unawaited(
      work.then(
        (value) {
          if (!result.isCompleted) result.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          if (!result.isCompleted) result.completeError(error, stack);
        },
      ),
    );
    if (_closed.isCompleted) fail(SourceError('CANCELLED', '媒体会话已关闭'));
    if (token?.cancelError case final error?) fail(error);
    try {
      return await result.future;
    } finally {
      await closing.cancel();
      await cancellation?.cancel();
    }
  }

  void _check(CancelToken? token) {
    if (token?.cancelError case final error?) throw error;
    if (_closed.isCompleted) throw SourceError('CANCELLED', '媒体会话已关闭');
  }

  Future<void> _start() async {
    _check(null);
    final ready = Completer<void>();
    void finish([Object? error]) {
      if (!ready.isCompleted) {
        if (error == null) {
          ready.complete();
        } else {
          ready.completeError(error);
        }
      }
    }

    final timeout = Timer(
      const Duration(seconds: 25),
      () => finish(SourceError('CLOUDFLARE', '浏览器验证未通过', url: policy.origin)),
    );
    final view = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('${policy.origin}/robots.txt')),
      initialSettings: InAppWebViewSettings(
        userAgent: HttpService.instance.userAgent,
        blockNetworkImage: true,
        useShouldOverrideUrlLoading: true,
      ),
      onWebViewCreated: (controller) => _controller = controller,
      onRenderProcessGone: (controller, detail) {
        finish(SourceError('NETWORK', '浏览器请求失败'));
        _controller = null;
        unawaited(close());
      },
      onLoadStop: (controller, url) async {
        if (url == null || Uri.tryParse('$url')?.origin != policy.origin) {
          finish(SourceError('CONFIG', '媒体浏览器离开了站点声明的地址'));
          return;
        }
        try {
          final title = await controller.getTitle() ?? '';
          final html = await controller.evaluateJavascript(
            source: 'document.documentElement.outerHTML.slice(0,3000)',
          );
          if (!hasChallengeMarkers('$html', title: title)) {
            finish();
          }
        } catch (e) {
          finish(e);
        }
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame == true) {
          finish(SourceError('NETWORK', error.description));
        }
      },
      shouldOverrideUrlLoading: (controller, action) =>
          action.isForMainFrame == false ||
              Uri.tryParse('${action.request.url}')?.origin == policy.origin
          ? NavigationActionPolicy.ALLOW
          : NavigationActionPolicy.CANCEL,
    );
    _view = view;
    _viewDisposal = null;
    // Subscribe before run: onLoadStop may finish synchronously in a test host.
    final waiting = _untilClosed(ready.future, null);
    // close may settle this while the platform is still creating its view.
    waiting.ignore();
    final starting = _starting = view.run();
    try {
      await starting;
      await waiting;
    } catch (error) {
      finish(error);
      try {
        await _disposeView(view, starting);
      } finally {
        if (identical(_view, view)) {
          _view = null;
          _controller = null;
          _ready = null;
        }
      }
      rethrow;
    } finally {
      timeout.cancel();
      if (identical(_starting, starting)) _starting = null;
    }
  }

  Future<void> _disposeView(
    HeadlessInAppWebView view,
    Future<void>? starting,
  ) => _viewDisposal ??= () async {
    try {
      await starting;
    } catch (_) {}
    await view.dispose();
  }();

  @override
  Future<MediaResponse> fetch(
    Uri url, {
    required int maxBytes,
    CancelToken? cancelToken,
  }) {
    validate(url);
    if (maxBytes < 1 || maxBytes > 32 * 1024 * 1024) {
      throw ArgumentError.value(maxBytes, 'maxBytes');
    }
    _check(cancelToken);
    final operation = _queue.run(() async {
      _check(cancelToken);
      await _untilClosed(_ready ??= _start(), cancelToken);
      _check(cancelToken);
      final id = '${++_nextId}';
      var finished = false;
      final cancellation = cancelToken?.whenCancel.asStream().listen((
        error,
      ) async {
        if (!finished && !_closed.isCompleted) {
          try {
            await _controller?.evaluateJavascript(
              source:
                  '''const jobs = globalThis.__parkMedia ||= new Map();
const id = ${jsonEncode(id)};
if (jobs.has(id)) jobs.get(id)?.abort(); else jobs.set(id, null);''',
            );
          } catch (_) {}
        }
      });
      try {
        final result = await _untilClosed(
          _controller!
              .callAsyncJavaScript(
                functionBody: '''
            const jobs = globalThis.__parkMedia ||= new Map();
            if (jobs.has(id)) { jobs.delete(id); return {error: 'cancelled'}; }
            const controller = new AbortController();
            jobs.set(id, controller);
            const timer = setTimeout(() => controller.abort(), 40000);
            try {
              const response = await fetch(url, {credentials: 'omit', mode: 'cors', redirect: 'error', headers, signal: controller.signal});
              if (response.status !== 200) return {status: response.status};
              const size = Number(response.headers.get('content-length'));
              if (size > limit) throw new Error('媒体资源过大');
              if (!response.body) throw new Error('媒体响应为空');
              const reader = response.body.getReader();
              const chunks = [];
              let length = 0;
              while (true) {
                const {done, value} = await reader.read();
                if (done) break;
                length += value.length;
                if (length > limit) { await reader.cancel(); throw new Error('媒体资源过大'); }
                chunks.push(value);
              }
              let binary = '';
              for (const chunk of chunks) {
                for (let i = 0; i < chunk.length; i += 8192) binary += String.fromCharCode(...chunk.subarray(i, i + 8192));
              }
              return {status: 200, body: btoa(binary), url: response.url};
            } catch (error) { return {error: String(error && error.message || error)}; }
            finally { clearTimeout(timer); controller.abort(); jobs.delete(id); }
          ''',
                arguments: {
                  'id': id,
                  'url': url.toString(),
                  'limit': maxBytes,
                  'headers': Map.of(headers)
                    ..removeWhere(
                      (name, _) => const {
                        'referer',
                        'origin',
                      }.contains(name.toLowerCase()),
                    ),
                },
              )
              .timeout(const Duration(seconds: 45)),
          cancelToken,
        );
        _check(cancelToken);
        if (result?.error != null) throw SourceError('NETWORK', result!.error!);
        final value = result?.value;
        if (value is! Map ||
            value['status'] != 200 ||
            value['body'] is! String) {
          throw SourceError(
            'NETWORK',
            '媒体请求失败：{error}',
            params: {
              'error':
                  '${value is Map ? value['error'] ?? value['status'] : 'empty'}',
            },
          );
        }
        final finalUrl = Uri.tryParse('${value['url']}');
        if (finalUrl == null) throw SourceError('NETWORK', '媒体响应地址缺失');
        validate(finalUrl);
        if (finalUrl != url) throw SourceError('CONFIG', '媒体请求不允许重定向');
        final encoded = value['body'] as String;
        if (encoded.length > ((maxBytes + 2) ~/ 3) * 4) {
          throw SourceError('NETWORK', '媒体资源过大');
        }
        final bytes = base64Decode(encoded);
        if (bytes.isEmpty || bytes.length > maxBytes) {
          throw SourceError('NETWORK', '媒体资源为空或过大');
        }
        return MediaResponse(bytes, finalUrl);
      } finally {
        finished = true;
        await cancellation?.cancel();
      }
    });
    return _untilClosed(operation, cancelToken);
  }

  @override
  Future<void> close() => _closing ??= () async {
    if (!_closed.isCompleted) {
      _closed.complete();
      _closingEvents.add(null);
    }
    final controller = _controller;
    final view = _view;
    final starting = _starting;
    _controller = null;
    try {
      await controller?.evaluateJavascript(
        source: 'globalThis.__parkMedia?.forEach(controller => controller?.abort())',
      );
    } catch (_) {}
    try {
      if (view != null) await _disposeView(view, starting);
    } finally {
      _view = null;
      await _queue.settled;
      await _closingEvents.close();
    }
  }();
}
