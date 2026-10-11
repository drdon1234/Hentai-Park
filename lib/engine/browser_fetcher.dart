import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/models.dart';
import 'http_service.dart';

/// Runs requests for Cloudflare-protected sites inside a hidden browser page opened on the site's
/// origin: same-origin `fetch()` carries a genuine browser fingerprint and the clearance cookies.
class BrowserFetcher {
  BrowserFetcher._();
  static final BrowserFetcher instance = BrowserFetcher._();

  final Map<String, _OriginPage> _pages = {};

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
    await page?.dispose();
  }
}

class _OriginPage {
  _OriginPage(this.origin);

  final String origin;
  HeadlessInAppWebView? _view;
  InAppWebViewController? _controller;
  Completer<void>? _ready;
  Timer? _idle;
  int _nextRequest = 0;
  Completer<void>? _navigation;
  Future<void> _requestQueue = Future.value();
  CancelToken _session = CancelToken();

  Future<void> _ensure() async {
    if (_ready != null) return _ready!.future;
    _session = CancelToken();
    final ready = _ready = Completer<void>();
    Timer? timeout;
    var settled = false;
    void finish([Object? error]) {
      if (settled) return;
      settled = true;
      timeout?.cancel();
      error == null ? ready.complete() : ready.completeError(error);
    }

    _view = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('$origin/robots.txt')),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent: HttpService.instance.userAgent,
        blockNetworkImage: true,
        mediaPlaybackRequiresUserGesture: true,
        useShouldOverrideUrlLoading: true,
      ),
      onWebViewCreated: (c) => _controller = c,
      onRenderProcessGone: (c, detail) {
        final error = SourceError('NETWORK', '浏览器请求失败');
        finish(error);
        _session.cancel(error);
        unawaited(dispose());
      },
      onLoadStop: (c, url) async {
        if (url == null || Uri.parse(url.toString()).origin != origin) {
          finish(SourceError('CONFIG', '浏览器页面已离开源声明的同源地址'));
          _finishNavigation(SourceError('CONFIG', '浏览器页面已离开源声明的同源地址'));
          return;
        }
        // A challenge page reloads itself once solved; only settle on a real document.
        final title = await c.getTitle() ?? '';
        final html =
            await c.evaluateJavascript(
              source: 'document.documentElement.outerHTML.slice(0, 3000)',
            ) ??
            '';
        final challenged =
            title.contains('Just a moment') ||
            '$html'.contains('challenge-platform') ||
            title.contains('Attention Required');
        if (!challenged) {
          finish();
          _finishNavigation();
        }
      },
      onReceivedError: (c, req, err) {
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
    await _view!.run();
    // Managed challenges usually pass on their own within a few seconds.
    if (!settled) {
      timeout = Timer(
        const Duration(seconds: 15),
        () => finish(
          SourceError(
            'CLOUDFLARE',
            'Cloudflare 验证未自动通过：${Uri.parse(origin).host}',
            url: origin,
          ),
        ),
      );
    }
    try {
      await ready.future;
    } catch (e) {
      await dispose();
      rethrow;
    }
  }

  Future<Map<String, Object?>> fetch(
    Map<String, dynamic> request, {
    CancelToken? cancelToken,
  }) {
    final operation = _requestQueue.then(
      (_) => _fetch(request, cancelToken: cancelToken),
    );
    _requestQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    if (cancelToken == null) return operation;
    return Future.any([
      operation,
      cancelToken.whenCancel.then<Map<String, Object?>>((error) => throw error),
    ]);
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
    final ready = _navigation = Completer<void>();
    final timeout = Timer(
      const Duration(seconds: 25),
      () => _finishNavigation(
        SourceError(
          'CLOUDFLARE',
          'Cloudflare 验证未自动通过：${Uri.parse(origin).host}',
          url: url,
        ),
      ),
    );
    final waiting = Future.any([
      ready.future,
      if (token != null) token.whenCancel.then<void>((error) => throw error),
    ]);
    try {
      await _controller!.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      await waiting;
    } finally {
      timeout.cancel();
      _navigation = null;
    }
  }

  Future<Map<String, Object?>> _fetch(
    Map<String, dynamic> request, {
    CancelToken? cancelToken,
    bool retried = false,
  }) async {
    if (cancelToken?.cancelError case final error?) throw error;
    await Future.any([
      _ensure(),
      if (cancelToken != null)
        cancelToken.whenCancel.then<void>((error) => throw error),
    ]);
    if (cancelToken?.cancelError case final error?) throw error;
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
          if (error != null) throw error;
          return null;
        }),
      ]);
      if (cancelToken?.cancelError case final error?) throw error;
      if (result?.error != null) throw SourceError('NETWORK', result!.error!);
      final value = result?.value;
      if (value is! Map) {
        throw SourceError('NETWORK', '浏览器请求失败：${request['url']}');
      }
      if (value['error'] != null) {
        throw SourceError(
          'NETWORK',
          '${Uri.parse(request['url'].toString()).host}: ${value['error']}',
        );
      }
      final status = (value['status'] as num?)?.toInt() ?? 0;
      final body = value['body']?.toString() ?? '';
      if ((status == 403 || status == 503) &&
          (body.contains('Just a moment') ||
              body.contains('challenge-platform'))) {
        // A fetch response cannot execute a managed challenge. Load it as a
        // same-origin document, then retry the read once after it has cleared.
        if (!retried && (request['method'] ?? 'GET') == 'GET') {
          await _verifyDocument(request['url'].toString(), cancelToken);
          return await _fetch(request, cancelToken: cancelToken, retried: true);
        }
        throw SourceError(
          'CLOUDFLARE',
          'Cloudflare 验证：${Uri.parse(origin).host}',
          url: origin,
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
      _idle?.cancel();
      _idle = Timer(const Duration(minutes: 3), dispose);
    }
  }

  Future<void> dispose() async {
    _idle?.cancel();
    _session.cancel('browser session closed');
    _finishNavigation(SourceError('CANCELLED', '浏览器会话已关闭'));
    final view = _view;
    _view = null;
    _controller = null;
    _ready = null;
    try {
      await view?.dispose();
    } catch (e) {
      debugPrint('browser page dispose: $e');
    }
  }
}
