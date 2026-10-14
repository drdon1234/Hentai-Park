import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/app_log.dart';
import '../core/async_tasks.dart';
import '../core/models.dart';
import 'cancellation.dart';
import 'challenge.dart';
import 'domains.dart';
import 'http_service.dart';

/// Runs requests for Cloudflare-protected sites inside a hidden browser page opened on the site's
/// origin: same-origin `fetch()` carries a genuine browser fingerprint and the clearance cookies.
class BrowserFetcher {
  BrowserFetcher._();
  static final BrowserFetcher instance = BrowserFetcher._();

  final Map<String, _OriginPage> _pages = {};

  Set<String> hostsForDomains(Iterable<String> domains) => {
    for (final origin in _pages.keys)
      if (hostInDomains(Uri.parse(origin).host, domains))
        Uri.parse(origin).host,
  };

  Future<Map<String, Object?>> fetch({
    required String origin,
    required Map<String, dynamic> request,
    CancelToken? cancelToken,
  }) async {
    final base = Uri.parse(
      origin.isNotEmpty ? origin : request['url'].toString(),
    );
    final key = base.origin;
    final page = _pages[key] ??= _OriginPage(key);
    return page.fetch(request, cancelToken: cancelToken);
  }

  /// Drops the hidden page so the next request reloads it (e.g. after a manual verification).
  Future<void> reset(String origin) async {
    final uri = Uri.parse(origin);
    final page = _pages.remove(uri.origin);
    await page?.retire();
  }

  /// 浏览器凭据由进程共享，同域名的运行中页面必须一起停止。
  Future<void> clearDomains(Iterable<String> domains) async {
    final keys = _pages.keys
        .where((origin) => hostInDomains(Uri.parse(origin).host, domains))
        .toList();
    await Future.wait([for (final key in keys) _pages.remove(key)!.retire()]);
  }
}

class _OriginPage {
  _OriginPage(this.origin);

  final String origin;
  HeadlessInAppWebView? _view;
  InAppWebViewController? _controller;
  Completer<void>? _ready;
  void Function(Object? error)? _finishReady;
  Timer? _idle;
  int _nextRequest = 0;
  Completer<void>? _navigation;
  bool _navigationStarted = false;
  int _documentGeneration = 0;
  Uri? _documentUri;
  Uri? _documentRequest;
  bool _documentConsumed = false;
  final _requestQueue = SerialExecutor();
  CancelToken _session = CancelToken();
  bool _retired = false;

  void _checkActive() {
    if (_retired) throw SourceError('CANCELLED', '浏览器会话已关闭');
  }

  Future<void> retire() async {
    _retired = true;
    await dispose();
  }

  Future<void> _ensure(Map<String, dynamic> request) async {
    _checkActive();
    if (_ready != null) return _ready!.future;
    _session = CancelToken();
    final target = Uri.parse(request['url'].toString());
    final method = (request['method'] ?? 'GET').toString().toUpperCase();
    // 初始化真实页面，让手动验证和隐藏请求使用相同路径的会话。
    // 非读取请求只打开首页，绝不通过导航重复提交表单。
    final bootstrap = method == 'GET' && target.origin == origin
        ? target
        : Uri.parse('$origin/');
    _documentUri = bootstrap;
    _documentRequest = bootstrap;
    final ready = _ready = Completer<void>();
    Timer? timeout;
    var settled = false;
    void finish([Object? error]) {
      if (settled) return;
      settled = true;
      timeout?.cancel();
      if (identical(_ready, ready)) _finishReady = null;
      error == null ? ready.complete() : ready.completeError(error);
    }

    _finishReady = (error) => finish(error);

    _view = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(bootstrap.toString())),
      initialSettings: InAppWebViewSettings(
        userAgent: HttpService.instance.userAgent,
        blockNetworkImage: true,
        useShouldOverrideUrlLoading: true,
      ),
      onWebViewCreated: (c) {
        if (identical(_ready, ready)) _controller = c;
      },
      onLoadStart: (c, url) {
        if (identical(_ready, ready)) {
          if (_navigation != null) _navigationStarted = true;
          _documentGeneration++;
          _documentConsumed = false;
          _documentUri = url == null ? null : Uri.tryParse(url.toString());
        }
      },
      onRenderProcessGone: (c, detail) {
        if (!identical(_ready, ready)) return;
        final error = SourceError('NETWORK', '浏览器请求失败');
        finish(error);
        _finishNavigation(error);
        _session.cancel(error);
        unawaited(dispose());
      },
      onLoadStop: (c, url) async {
        if (_navigation != null && !_navigationStarted) return;
        final generation = _documentGeneration;
        final navigation = _navigation;
        final document = url == null ? null : Uri.tryParse(url.toString());
        bool current() =>
            identical(_ready, ready) &&
            generation == _documentGeneration &&
            document == _documentUri &&
            identical(navigation, _navigation);
        if (!identical(_ready, ready)) return;
        if (url == null || Uri.parse(url.toString()).origin != origin) {
          finish(SourceError('CONFIG', '浏览器页面已离开站点声明的同源地址'));
          _finishNavigation(SourceError('CONFIG', '浏览器页面已离开站点声明的同源地址'));
          return;
        }
        if (!current()) return;
        try {
          // A challenge page reloads itself once solved. Ignore an old
          // document's async inspection after another navigation has begun.
          final title = await c.getTitle() ?? '';
          if (!current()) return;
          final html =
              await c.evaluateJavascript(
                source: 'document.documentElement.outerHTML.slice(0, 4 * 1024 * 1024)',
              ) ??
              '';
          if (!current()) return;
          final challenged = hasChallengeMarkers('$html', title: title);
          if (!challenged) {
            finish();
            _finishNavigation();
          }
        } catch (error) {
          if (!current()) return;
          final failure = SourceError(
            'NETWORK',
            '浏览器请求失败：{error}',
            params: {'error': '$error'},
          );
          finish(failure);
          _finishNavigation(failure);
        }
      },
      onReceivedError: (c, req, err) {
        if (!identical(_ready, ready)) return;
        if (req.isForMainFrame ?? true) {
          finish(
            SourceError(
              'NETWORK',
              '${Uri.parse(origin).host}: ${err.description}',
            ),
          );
          _finishNavigation(SourceError('NETWORK', err.description));
        }
      },
      shouldOverrideUrlLoading: (c, action) =>
          action.isForMainFrame == false ||
              (action.request.url != null &&
                  Uri.parse(action.request.url.toString()).origin == origin)
          ? NavigationActionPolicy.ALLOW
          : NavigationActionPolicy.CANCEL,
    );
    // The platform may call a failing load callback before run() returns.
    ready.future.ignore();
    try {
      final view = _view!;
      await view.run();
      // Managed challenges usually pass on their own within a few seconds.
      if (!settled) {
        timeout = Timer(
          const Duration(seconds: 15),
          () => finish(
            SourceError(
              'CLOUDFLARE',
              'Cloudflare 验证未自动通过：{host}',
              params: {'host': Uri.parse(origin).host},
              url: bootstrap.toString(),
            ),
          ),
        );
      }
      await ready.future;
    } catch (e) {
      if (identical(_ready, ready)) await dispose();
      if (e is! SourceError && e is! DioException) {
        throw SourceError(
          'NETWORK',
          '浏览器请求失败：{error}',
          params: {'error': '$e'},
        );
      }
      rethrow;
    }
  }

  Future<Map<String, Object?>> fetch(
    Map<String, dynamic> request, {
    CancelToken? cancelToken,
  }) {
    final operation = _requestQueue.run(
      () => _fetchWithRecovery(request, cancelToken),
    );
    return awaitCancelled(operation, cancelToken);
  }

  Future<Map<String, Object?>> _fetchWithRecovery(
    Map<String, dynamic> request,
    CancelToken? token,
  ) async {
    final canRetry =
        (request['method'] ?? 'GET').toString().toUpperCase() == 'GET';
    _idle?.cancel();
    try {
      for (var attempt = 0; ; attempt++) {
        _checkActive();
        if (token?.cancelError case final error?) throw error;
        try {
          final result = await _fetch(request, cancelToken: token);
          final status = result['status'];
          if (!canRetry ||
              attempt >= 2 ||
              !{408, 429, 500, 502, 503, 504}.contains(status)) {
            return result;
          }
        } on SourceError catch (error) {
          if (token?.cancelError case final cancelled?) throw cancelled;
          if (!canRetry || attempt >= 2 || error.code != 'NETWORK') rethrow;
          // A failed browser context must not poison the next read. Cookies
          // remain in the WebView store when the hidden page is recreated.
          await dispose();
        }
        final delay = Future<void>.delayed(
          Duration(milliseconds: 500 * (attempt + 1)),
        );
        await Future.any([
          delay,
          if (token != null)
            token.whenCancel.then<void>((error) => throw error),
        ]);
      }
    } finally {
      _idle?.cancel();
      if (!_retired) _idle = Timer(const Duration(minutes: 3), dispose);
    }
  }

  void _finishNavigation([Object? error]) {
    final navigation = _navigation;
    if (navigation == null || navigation.isCompleted) return;
    if (error == null) {
      navigation.complete();
    } else {
      navigation.completeError(error);
    }
  }

  Future<void> _verifyDocument(String url, CancelToken? token) async {
    if (Uri.tryParse(url)?.origin != origin) {
      throw SourceError('CONFIG', '浏览器验证地址必须同源');
    }
    _documentGeneration++;
    _documentUri = Uri.parse(url);
    _documentRequest = Uri.parse(url);
    final ready = _navigation = Completer<void>();
    _navigationStarted = false;
    final timeout = Timer(
      const Duration(seconds: 25),
      () => _finishNavigation(
        SourceError(
          'CLOUDFLARE',
          'Cloudflare 验证未自动通过：{host}',
          params: {'host': Uri.parse(origin).host},
          url: url,
        ),
      ),
    );
    final waiting = Future.any([
      ready.future,
      if (token != null) token.whenCancel.then<void>((error) => throw error),
    ]);
    // A native load callback may fail before loadUrl's future completes.
    waiting.ignore();
    try {
      await _controller!.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      await waiting;
    } catch (_) {
      // A cancelled/failed navigation must not leave the next request using
      // a context that is still replacing its document.
      await dispose();
      rethrow;
    } finally {
      timeout.cancel();
      if (identical(_navigation, ready)) _navigation = null;
    }
  }

  Future<Map<String, Object?>> _fetch(
    Map<String, dynamic> request, {
    CancelToken? cancelToken,
    bool retried = false,
  }) async {
    if (cancelToken?.cancelError case final error?) throw error;
    try {
      await awaitCancelled(_ensure(request), cancelToken);
    } catch (_) {
      // 取消初始化中的海报请求时释放旧页面，前台可立即导航到自己的目标。
      if (cancelToken?.isCancelled == true && _ready?.isCompleted == false) {
        await dispose();
      }
      rethrow;
    }
    if (cancelToken?.cancelError case final error?) throw error;
    if ((request['method'] ?? 'GET').toString().toUpperCase() == 'GET' &&
        !_documentConsumed &&
        request['body'] == null &&
        request['responseType'] != 'base64') {
      final document = await awaitCancelled(
        _readDocument(request['url'].toString()),
        cancelToken,
      );
      if (cancelToken?.cancelError case final error?) throw error;
      if (document != null) return document;
    }
    _idle?.cancel();
    final controller = _controller!;
    final session = _session;
    final id = '${++_nextRequest}';
    final settled = Completer<void>();
    final cancellation = cancelToken == null
        ? null
        : Future.any<DioException?>([
            cancelToken.whenCancel,
            settled.future.then<DioException?>((_) => null),
          ]).then<CallAsyncJavaScriptResult?>((error) async {
            if (error == null) return null;
            // Abort only this request. The origin page may also be serving a reader.
            unawaited(
              controller
                  .callAsyncJavaScript(
                    functionBody: '''
          const requests = window.__parkFetches ||= new Map();
          const active = requests.get(id);
          if (active) active.abort(); else requests.set(id, null);
          return true;
        ''',
                    arguments: {'id': id},
                  )
                  .catchError((Object _) => null),
            );
            throw error;
          });
    try {
      final operation = controller.callAsyncJavaScript(
        functionBody: '''
        const init = { method: req.method || 'GET', headers: req.headers || {}, credentials: 'include', mode: 'same-origin', redirect: 'follow' };
        if (req.body != null && init.method !== 'GET') init.body = req.body;
        for (const k of Object.keys(init.headers)) {
          if (/^(user-agent|cookie|referer|accept-encoding)\$/i.test(k)) delete init.headers[k];
        }
        const ctrl = new AbortController();
        const requests = window.__parkFetches ||= new Map();
        if (requests.has(id)) { requests.delete(id); return { error: 'cancelled' }; }
        requests.set(id, ctrl);
        const timer = setTimeout(() => ctrl.abort(), req.timeout || 30000);
        init.signal = ctrl.signal;
        try {
          const r = await fetch(req.url, init);
          const headers = {};
          r.headers.forEach((v, k) => headers[k] = v);
          const body = await r.text();
          return { status: r.status, headers, body, url: r.url };
        } catch (e) {
          return { error: String(e && e.message || e) };
        } finally { clearTimeout(timer); requests.delete(id); }
      ''',
        arguments: {'req': request, 'id': id},
      );
      final result = await Future.any([
        operation,
        ?cancellation,
        Future.any<DioException?>([
          session.whenCancel,
          settled.future.then<DioException?>((_) => null),
        ]).then<CallAsyncJavaScriptResult?>((error) {
          if (error != null) {
            if (error.error case final SourceError cause) throw cause;
            throw error;
          }
          return null;
        }),
      ]);
      if (cancelToken?.cancelError case final error?) throw error;
      if (result?.error != null) throw SourceError('NETWORK', result!.error!);
      final value = result?.value;
      if (value is! Map) {
        throw SourceError(
          'NETWORK',
          '浏览器请求失败：{error}',
          params: {'error': '${request['url']}'},
        );
      }
      if (value['error'] != null) {
        throw SourceError(
          'NETWORK',
          '${Uri.parse(request['url'].toString()).host}: ${value['error']}',
        );
      }
      final status = (value['status'] as num?)?.toInt() ?? 0;
      final body = value['body']?.toString() ?? '';
      if ((status == 403 || status == 503) && hasChallengeMarkers(body)) {
        // A fetch response cannot execute a managed challenge. Load it as a
        // same-origin document, then retry the read once after it has cleared.
        if (!retried &&
            (request['method'] ?? 'GET').toString().toUpperCase() == 'GET') {
          await _verifyDocument(request['url'].toString(), cancelToken);
          final document = await awaitCancelled(
            _readDocument(request['url'].toString()),
            cancelToken,
          );
          if (cancelToken?.cancelError case final error?) throw error;
          if (document != null) return document;
          return await _fetch(request, cancelToken: cancelToken, retried: true);
        }
        throw SourceError(
          'CLOUDFLARE',
          'Cloudflare 验证：{host}',
          params: {'host': Uri.parse(origin).host},
          url: request['url'].toString(),
        );
      }
      return {
        'status': status,
        'headers': value['headers'] ?? {},
        'body': body,
        'url': value['url'] ?? request['url'],
      };
    } finally {
      settled.complete();
    }
  }

  Future<Map<String, Object?>?> _readDocument(String requested) async {
    final controller = _controller;
    if (controller == null) return null;
    final generation = _documentGeneration;
    try {
      final current = await controller.getUrl();
      final uri = current == null ? null : Uri.tryParse(current.toString());
      // 接受该次导航的同源重定向（如语言首页），其他资源仍使用真实请求。
      if (uri == null ||
          uri.origin != origin ||
          uri != _documentUri ||
          requested != _documentRequest?.toString()) {
        return null;
      }
      final value = await controller.evaluateJavascript(
        source: '''
        document.readyState === 'complete' && document.contentType === 'text/html'
          ? {body: document.documentElement.outerHTML, url: location.href, contentType: document.contentType}
          : null
      ''',
      );
      if (!identical(controller, _controller) ||
          generation != _documentGeneration ||
          value is! Map ||
          value['url'] != uri.toString() ||
          value['contentType'] != 'text/html') {
        return null;
      }
      final body = value['body'];
      if (body is! String ||
          body.length < 200 ||
          body.length > 4 * 1024 * 1024 ||
          hasChallengeMarkers(body)) {
        return null;
      }
      _documentConsumed = true;
      return {
        'status': 200,
        'headers': {'content-type': 'text/html'},
        'body': body,
        'url': uri.toString(),
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    _documentGeneration++;
    _documentRequest = null;
    _idle?.cancel();
    _session.cancel('browser session closed');
    _finishReady?.call(SourceError('CANCELLED', '浏览器会话已关闭'));
    _finishReady = null;
    _finishNavigation(SourceError('CANCELLED', '浏览器会话已关闭'));
    final view = _view;
    _view = null;
    _controller = null;
    _ready = null;
    try {
      await view?.dispose();
    } catch (e) {
      AppLog.error(e, event: 'browser_dispose');
    }
  }
}
