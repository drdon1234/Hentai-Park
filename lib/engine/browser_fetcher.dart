import 'dart:async';

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

  Future<Map<String, Object?>> fetch({required String origin, required Map<String, dynamic> request}) async {
    final base = Uri.parse(origin.isNotEmpty ? origin : request['url'].toString());
    final key = '${base.scheme}://${base.host}';
    final page = _pages[key] ??= _OriginPage(key);
    return page.fetch(request);
  }

  /// Drops the hidden page so the next request reloads it (e.g. after a manual verification).
  Future<void> reset(String origin) async {
    final uri = Uri.parse(origin);
    final page = _pages.remove('${uri.scheme}://${uri.host}');
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

  Future<void> _ensure() async {
    if (_ready != null) return _ready!.future;
    final ready = _ready = Completer<void>();
    var settled = false;
    void finish([Object? error]) {
      if (settled) return;
      settled = true;
      error == null ? ready.complete() : ready.completeError(error);
    }

    _view = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('$origin/robots.txt')),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent: HttpService.instance.userAgent,
        blockNetworkImage: true,
        mediaPlaybackRequiresUserGesture: true,
      ),
      onWebViewCreated: (c) => _controller = c,
      onLoadStop: (c, url) async {
        // A challenge page reloads itself once solved; only settle on a real document.
        final title = await c.getTitle() ?? '';
        final html = await c.evaluateJavascript(source: 'document.documentElement.outerHTML.slice(0, 3000)') ?? '';
        final challenged = title.contains('Just a moment') || '$html'.contains('challenge-platform') || title.contains('Attention Required');
        if (!challenged) finish();
      },
      onReceivedError: (c, req, err) {
        if (req.isForMainFrame ?? true) finish(SourceError('NETWORK', '${Uri.parse(origin).host}: ${err.description}'));
      },
    );
    await _view!.run();
    // Managed challenges usually pass on their own within a few seconds.
    Future.delayed(const Duration(seconds: 15), () => finish(SourceError('CLOUDFLARE', 'Cloudflare 验证未自动通过：${Uri.parse(origin).host}', url: origin)));
    try {
      await ready.future;
    } catch (e) {
      await dispose();
      rethrow;
    }
  }

  Future<Map<String, Object?>> fetch(Map<String, dynamic> request) async {
    await _ensure();
    _idle?.cancel();
    _idle = Timer(const Duration(minutes: 3), dispose);
    final result = await _controller!.callAsyncJavaScript(
      functionBody: '''
        const init = { method: req.method || 'GET', headers: req.headers || {}, credentials: 'include', redirect: 'follow' };
        if (req.body != null && init.method !== 'GET') init.body = req.body;
        for (const k of Object.keys(init.headers)) {
          if (/^(user-agent|cookie|referer|accept-encoding)\$/i.test(k)) delete init.headers[k];
        }
        const ctrl = new AbortController();
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
        } finally { clearTimeout(timer); }
      ''',
      arguments: {'req': request},
    );
    if (result?.error != null) throw SourceError('NETWORK', result!.error!);
    final value = result?.value;
    if (value is! Map) throw SourceError('NETWORK', '浏览器请求失败：${request['url']}');
    if (value['error'] != null) {
      throw SourceError('NETWORK', '${Uri.parse(request['url'].toString()).host}: ${value['error']}');
    }
    final status = (value['status'] as num?)?.toInt() ?? 0;
    final body = value['body']?.toString() ?? '';
    if ((status == 403 || status == 503) && (body.contains('Just a moment') || body.contains('challenge-platform'))) {
      // Clearance expired: drop the page so the next attempt re-runs the challenge.
      unawaited(dispose());
      throw SourceError('CLOUDFLARE', 'Cloudflare 验证：${Uri.parse(origin).host}', url: origin);
    }
    return {'status': status, 'headers': value['headers'] ?? {}, 'body': body, 'url': value['url'] ?? request['url']};
  }

  Future<void> dispose() async {
    _idle?.cancel();
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
