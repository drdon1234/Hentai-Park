import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/async_tasks.dart';
import '../core/models.dart';
import 'challenge.dart';
import 'http_service.dart';
import 'media_transport.dart';

/// One hidden page per playback/download. Closing it aborts and releases all requests.
class BrowserMedia implements MediaTransport {
  BrowserMedia(
    this.policy, {
    Map<String, String> headers = const {},
    this.concurrentRequests = false,
  }) : headers = policy.requestHeaders(headers);
  @override
  final MediaPolicy policy;
  final Map<String, String> headers;
  final bool concurrentRequests;
  bool get isClosed => _closed.isCompleted;
  final _active = <Future<void>>{};
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
  bool _resourcePhase = false;
  Timer? _startupPoll;

  // WebView2 在每次连接前触发拦截；其他内核的回调不能覆盖重定向链。
  // 没有逐跳拦截能力时让浏览器拒绝重定向，不用事后校验冒充连接边界。
  static bool get _guardedRedirects => Platform.isWindows;

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
    _resourcePhase = false;
    final ready = Completer<void>();
    var challenged = false;
    var generation = 0;
    var inspecting = false;
    Uri? document = Uri.parse('${policy.origin}/robots.txt');
    var documentStatus = 200;
    var sawChallenge = false;
    void finish([Object? error]) {
      if (!ready.isCompleted) {
        _startupPoll?.cancel();
        _startupPoll = null;
        if (error == null) {
          ready.complete();
        } else {
          ready.completeError(error);
        }
      }
    }

    Future<void> inspect(InAppWebViewController controller) async {
      if (inspecting || ready.isCompleted || _closed.isCompleted) return;
      inspecting = true;
      final inspectedGeneration = generation;
      bool current() =>
          !_closed.isCompleted &&
          !ready.isCompleted &&
          inspectedGeneration == generation &&
          _controller != null;
      try {
        // 同一快照读取实际文档地址和状态，用导航代次丢弃旧结果。
        final raw = await controller
            .evaluateJavascript(
              source:
                  '''JSON.stringify({url: location.href, title: document.title,
ready: document.readyState === 'complete',
html: document.documentElement ? document.documentElement.outerHTML.slice(0, 4194304) : ''})''',
            )
            .timeout(const Duration(seconds: 5));
        if (!current()) return;
        final state = raw is String ? jsonDecode(raw) : raw;
        if (state is! Map || state['ready'] != true) {
          return;
        }
        if (!policy.allowsDocument(Uri.tryParse('${state['url']}'))) {
          finish(SourceError('CONFIG', '媒体浏览器离开了站点声明的地址'));
          return;
        }
        document = Uri.tryParse('${state['url']}');
        challenged = hasChallengeMarkers(
          '${state['html'] ?? ''}',
          title: '${state['title'] ?? ''}',
        );
        if (challenged) {
          sawChallenge = true;
          return;
        }
        // 启动文档只用于建立来源；站点可不提供 robots.txt。
        final missingBootstrap =
            documentStatus == 404 &&
            document == Uri.parse('${policy.origin}/robots.txt');
        if (documentStatus >= 400 && !sawChallenge && !missingBootstrap) {
          finish(SourceError('HTTP', '浏览器请求失败', status: documentStatus));
          return;
        }
        finish();
      } catch (error) {
        if (current()) finish(error);
      } finally {
        inspecting = false;
      }
    }

    final timeout = Timer(
      const Duration(seconds: 25),
      () => finish(
        challenged
            ? SourceError('CLOUDFLARE', '浏览器验证未通过', url: policy.origin)
            : SourceError(
                'NETWORK',
                '浏览器请求超时',
                url: policy.origin,
                diagnostics: const {
                  'transport': 'browser',
                  'reason': 'CONNECT_TIMEOUT',
                },
              ),
      ),
    );
    final view = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('${policy.origin}/robots.txt')),
      initialSettings: InAppWebViewSettings(
        userAgent: HttpService.instance.userAgent,
        blockNetworkImage: true,
        useShouldOverrideUrlLoading: true,
        useShouldInterceptRequest: _guardedRedirects,
      ),
      shouldInterceptRequest: (controller, request) {
        if (!_resourcePhase) return null;
        try {
          final url = Uri.parse(request.url.toString());
          // WebView2 的 isForMainFrame 对子资源也可能为 true；使用浏览器
          // 生成且 fetch 不能伪造的目标类型，保持文档域与资源域各自独立。
          final destination = request.headers?.entries
              .where((entry) => entry.key.toLowerCase() == 'sec-fetch-dest')
              .firstOrNull
              ?.value;
          if (destination == 'document' || destination == 'iframe') {
            if (!policy.allowsDocument(url)) {
              throw SourceError('CONFIG', '媒体浏览器离开了站点声明的地址');
            }
          } else {
            validate(url);
          }
          return null;
        } catch (_) {
          return WebResourceResponse(
            statusCode: 403,
            reasonPhrase: 'Forbidden',
            contentType: 'text/plain',
            data: Uint8List(0),
          );
        }
      },
      onWebViewCreated: (controller) => _controller = controller,
      onLoadStart: (controller, url) {
        generation++;
        challenged = false;
        document = Uri.tryParse('$url');
        documentStatus = 200;
        sawChallenge = false;
      },
      onRenderProcessGone: (controller, detail) {
        finish(SourceError('NETWORK', '浏览器请求失败'));
        _controller = null;
        unawaited(close());
      },
      onLoadStop: (controller, url) async {
        if (ready.isCompleted || _closed.isCompleted) return;
        // 只按检查快照中的实际地址判断，迟到的 loadStop 不能替换当前文档。
        _startupPoll ??= Timer.periodic(
          const Duration(milliseconds: 800),
          (_) => unawaited(inspect(controller)),
        );
        await inspect(controller);
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame == true &&
            document == Uri.tryParse('${request.url}')) {
          finish(SourceError('NETWORK', error.description));
        }
      },
      onReceivedHttpError: (controller, request, response) {
        if (!ready.isCompleted &&
            request.isForMainFrame == true &&
            document == Uri.tryParse('${request.url}')) {
          documentStatus = response.statusCode ?? 200;
        }
      },
      shouldOverrideUrlLoading: (controller, action) =>
          action.isForMainFrame == false ||
              policy.allowsDocument(Uri.tryParse('${action.request.url}'))
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
    Future<MediaResponse> action() async {
      _check(cancelToken);
      await _untilClosed(_ready ??= _start(), cancelToken);
      _check(cancelToken);
      _resourcePhase = true;
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
              const response = await fetch(url, {credentials: credentialsMode, mode: 'cors', redirect: redirectMode, referrerPolicy: 'strict-origin-when-cross-origin', headers, signal: controller.signal});
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
                  'redirectMode': _guardedRedirects ? 'follow' : 'error',
                  'credentialsMode': policy.sameOriginCredentials
                      ? 'same-origin'
                      : 'omit',
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
    }

    final operation = concurrentRequests
        ? Future.sync(action)
        : _queue.run(action);
    final settled = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _active.add(settled);
    settled.then((_) => _active.remove(settled));
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
    _startupPoll?.cancel();
    _startupPoll = null;
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
      await Future.wait(_active.toList());
      await _closingEvents.close();
    }
  }();
}
