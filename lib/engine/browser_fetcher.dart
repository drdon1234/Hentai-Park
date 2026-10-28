import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/app_log.dart';
import '../core/async_tasks.dart';
import '../core/models.dart';
import '../core/settings.dart';
import 'age_confirmation.dart';
import 'browser_interaction.dart';
import 'cancellation.dart';
import 'challenge.dart';
import 'domains.dart';
import 'http_service.dart';
import 'resource_pool.dart';

/// Runs requests for Cloudflare-protected sites inside a hidden browser page opened on the site's
/// origin: same-origin `fetch()` carries a genuine browser fingerprint and the clearance cookies.
class BrowserFetcher {
  BrowserFetcher._();
  static final BrowserFetcher instance = BrowserFetcher._();

  final _pages = ResourcePool<_BrowserPageKey, _OriginPage>(
    maximum: 4,
    idleTimeout: const Duration(seconds: 30),
    create: (key) => _OriginPage(
      key.origin,
      key.domains,
      partition: key.partition,
      confirmation: key.confirmation,
    ),
    destroy: (page) => page.retire(),
    onDisposeError: (error, _) => AppLog.error(error, event: 'browser_dispose'),
  );
  int get retainedPages => _pages.retained;
  int get activePages => _pages.active;
  int get closingPages => _pages.closing;
  int get waitingRequests => _pages.waiting;

  Future<void> dispose() async {
    await _pages.close();
  }

  Set<String> hostsForDomains(Iterable<String> domains) => {
    for (final page in _pages.values)
      for (final host in page.hosts)
        if (hostInDomains(host, domains)) host,
  };

  Future<Map<String, Object?>> fetch({
    required String origin,
    required Map<String, dynamic> request,
    List<String>? domains,
    String? partition,
    CancelToken? cancelToken,
    AgeConfirmationConfig? confirmation,
  }) async {
    final base = Uri.parse(
      origin.isNotEmpty ? origin : request['url'].toString(),
    );
    final allowed = (domains ?? [base.host]).toSet().toList()..sort();
    final key = _BrowserPageKey(base.origin, allowed, partition, confirmation);
    // 对外可立即取消，池内仍持有页面，直到队列中的真实操作结束。
    return await awaitCancelled(
      _pages.use(
        key,
        (page) => page.fetch(request, cancelToken: cancelToken),
        cancelToken: cancelToken,
      ),
      cancelToken,
    );
  }

  /// Drops the hidden page so the next request establishes a fresh document.
  Future<void> reset(String origin) async {
    final uri = Uri.parse(origin);
    await _pages.removeWhere((key) => key.origin == uri.origin);
  }

  /// 浏览器凭据由进程共享，同域名的运行中页面必须一起停止。
  Future<void> clearDomains(Iterable<String> domains) async {
    await _pages.removeWhere(
      (key) => key.domains.any((host) => hostInDomains(host, domains)),
    );
  }
}

class _BrowserPageKey {
  _BrowserPageKey(this.origin, this.domains, this.partition, this.confirmation);
  final String origin;
  final List<String> domains;
  final String? partition;
  final AgeConfirmationConfig? confirmation;
  (String, String, String, String) get _identity => (
    origin,
    domains.join(','),
    partition ?? '',
    confirmation?.signature ?? '',
  );

  @override
  bool operator ==(Object other) =>
      other is _BrowserPageKey && other._identity == _identity;
  @override
  int get hashCode => _identity.hashCode;
}

class _OriginPage {
  _OriginPage(this.origin, this.domains, {this.partition, this.confirmation});

  final String origin;
  final List<String> domains;
  final String? partition;
  final AgeConfirmationConfig? confirmation;
  Set<String> get hosts => {Uri.parse(origin).host, ?_documentUri?.host};

  bool _allowsDocument(Uri? uri) {
    final base = Uri.parse(origin);
    return uri != null &&
        uri.scheme == base.scheme &&
        uri.port == base.port &&
        uri.userInfo.isEmpty &&
        hostInDomains(uri.host, domains);
  }

  HeadlessInAppWebView? _view;
  InAppWebViewController? _controller;
  Completer<void>? _ready;
  void Function(Object? error)? _finishReady;
  Timer? _poll;
  bool _ageGateSeen = false;
  int _ageClickedGeneration = -1;
  int _challengeClickedGeneration = -1;
  DateTime? _challengeSince;
  int _nextRequest = 0;
  Completer<void>? _navigation;
  bool _navigationStarted = false;
  int _documentGeneration = 0;
  Uri? _documentUri;
  Uri? _documentRequest;
  bool _documentConsumed = false;
  int _documentStatus = 200;
  final _requestQueue = SerialExecutor();
  CancelToken _session = CancelToken();
  bool _retired = false;

  void _checkActive() {
    if (_retired) throw SourceError('CANCELLED', '浏览器会话已关闭');
  }

  bool _isRead(Map<String, dynamic> request) =>
      {
        'GET',
        'HEAD',
      }.contains((request['method'] ?? 'GET').toString().toUpperCase()) &&
      request['body'] == null &&
      request['bodyBase64'] == null;

  bool _canReadDocument(Map<String, dynamic> request) {
    if (!_isRead(request) ||
        (request['method'] ?? 'GET').toString().toUpperCase() != 'GET' ||
        request['responseType'] == 'base64') {
      return false;
    }
    // Navigation cannot attach API tokens, Range or content-negotiation
    // headers. Such requests must use fetch even when their URL matches.
    return (request['headers'] as Map? ?? {}).entries.every((entry) {
      final name = entry.key.toString().toLowerCase();
      return {
            'user-agent',
            'cookie',
            'referer',
            'accept-encoding',
          }.contains(name) ||
          (name == 'accept' &&
              entry.value.toString().toLowerCase().contains('text/html'));
    });
  }

  SourceError _timeout(String reason) => SourceError(
    'NETWORK',
    '{host}: 响应超时',
    params: {'host': Uri.parse(origin).host},
    diagnostics: {
      'transport': 'browser',
      'host': Uri.parse(origin).host,
      'reason': reason,
    },
  );

  String _navigationReason(WebResourceErrorType type) {
    if (type == WebResourceErrorType.HOST_LOOKUP) return 'DNS';
    if (type == WebResourceErrorType.TIMEOUT) return 'RECEIVE_TIMEOUT';
    if (type.toString().contains('CERTIFICATE')) return 'TLS_CERTIFICATE';
    if ({
      WebResourceErrorType.FAILED_SSL_HANDSHAKE,
      WebResourceErrorType.SECURE_CONNECTION_FAILED,
    }.contains(type)) {
      return 'TLS_HANDSHAKE';
    }
    if ({
      WebResourceErrorType.CANNOT_CONNECT_TO_HOST,
      WebResourceErrorType.NETWORK_CONNECTION_LOST,
      WebResourceErrorType.CONNECTION_ABORTED,
      WebResourceErrorType.RESET,
    }.contains(type)) {
      return 'CONNECTION';
    }
    return 'NETWORK';
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
    // 初始化真实页面，让后台验证和隐藏请求使用相同路径的会话。
    // 非读取请求只打开首页，绝不通过导航重复提交表单。
    final bootstrap = _canReadDocument(request) && _allowsDocument(target)
        ? target
        : Uri.parse('$origin/');
    _documentUri = bootstrap;
    _documentRequest = bootstrap;
    _documentConsumed = false;
    _documentStatus = 200;
    _ageGateSeen = false;
    _ageClickedGeneration = -1;
    _challengeClickedGeneration = -1;
    final ready = _ready = Completer<void>();
    Timer? timeout;
    var challenged = false;
    var settled = false;
    void finish([Object? error]) {
      if (settled) return;
      settled = true;
      timeout?.cancel();
      if (identical(_ready, ready)) _finishReady = null;
      error == null ? ready.complete() : ready.completeError(error);
    }

    _finishReady = (error) => finish(error);

    var inspecting = false;
    DateTime? stableSince;
    DateTime? lastChallengeScan;
    late Future<void> Function(InAppWebViewController, WebUri?) inspect;

    _view = HeadlessInAppWebView(
      initialSize: const Size(1024, 768),
      initialUrlRequest: URLRequest(url: WebUri(bootstrap.toString())),
      initialUserScripts: defaultTargetPlatform == TargetPlatform.android
          ? UnmodifiableListView([
              UserScript(
                source: challengeDocumentScript,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                allowedOriginRules: {
                  for (final domain in domains) ...{
                    'https://$domain',
                    'https://*.$domain',
                  },
                },
              ),
            ])
          : null,
      initialSettings: InAppWebViewSettings(
        userAgent: HttpService.instance.userAgent,
        // 验证页也会加载图片资源，拦截会使原生输入成功后仍无法放行。
        useShouldOverrideUrlLoading: true,
      ),
      onWebViewCreated: (c) {
        if (!identical(_ready, ready)) return;
        _controller = c;
        _poll = Timer.periodic(const Duration(milliseconds: 800), (_) {
          if (!identical(_ready, ready) ||
              (ready.isCompleted &&
                  (_navigation == null || _navigation!.isCompleted))) {
            return;
          }
          unawaited(
            inspect(
              c,
              _documentUri == null ? null : WebUri(_documentUri.toString()),
            ),
          );
        });
      },
      onLoadStart: (c, url) {
        if (identical(_ready, ready)) {
          if (_navigation != null) _navigationStarted = true;
          _documentGeneration++;
          _documentConsumed = false;
          _documentStatus = 200;
          _challengeSince = null;
          stableSince = null;
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
      onLoadStop: inspect = (c, url) async {
        if (inspecting) return;
        inspecting = true;
        try {
          if (_navigation != null && !_navigationStarted) return;
          final generation = _documentGeneration;
          final navigation = _navigation;
          final document = url == null ? null : Uri.tryParse(url.toString());
          bool sessionCurrent() =>
              identical(_ready, ready) &&
              generation == _documentGeneration &&
              identical(navigation, _navigation);
          bool current() => sessionCurrent() && document == _documentUri;
          if (!identical(_ready, ready)) return;
          // A late callback from an older document must not reject the active
          // navigation before its generation and navigation identity are checked.
          if (!sessionCurrent()) return;
          try {
            // 页面脚本可通过 history 改写地址，而不触发新的 onLoadStart。
            // 仅接受浏览器当前文档的完成事件，继续忽略上一代文档的迟到回调。
            if (document != _documentUri) {
              final actual = await c.getUrl();
              if (!sessionCurrent() ||
                  actual?.toString() != document?.toString()) {
                return;
              }
              _documentUri = document;
            }
            if (!current()) return;
            if (!_allowsDocument(document)) {
              finish(SourceError('CONFIG', '浏览器页面已离开站点声明的同源地址'));
              _finishNavigation(SourceError('CONFIG', '浏览器页面已离开站点声明的同源地址'));
              return;
            }
            // A challenge page reloads itself once solved. Ignore an old
            // document's async inspection after another navigation has begun.
            final state = await inspectAccessDocument(
              c,
              url: document.toString(),
              confirmation: confirmation,
              confirmAdult:
                  AppSettings.instance.adultConfirmed &&
                  _ageClickedGeneration != generation,
            );
            if (!current()) return;
            if (state == null) return;
            final html = state['html']?.toString() ?? '';
            if (hasFirewallBlockMarkers(html)) {
              final error = firewallBlocked(
                Uri.parse(origin).host,
                url: document.toString(),
              );
              finish(error);
              _finishNavigation(error);
              return;
            }
            challenged = hasChallengeMarkers(
              html,
              title: state['title']?.toString() ?? '',
            );
            if (challenged) {
              stableSince = null;
              _challengeSince ??= DateTime.now();
              if (_challengeClickedGeneration != generation &&
                  DateTime.now().difference(_challengeSince!) >=
                      const Duration(seconds: 5) &&
                  (lastChallengeScan == null ||
                      DateTime.now().difference(lastChallengeScan!) >=
                          const Duration(seconds: 3))) {
                // 每代文档最多一次输入，不反复点击挑战或站点控件。
                try {
                  lastChallengeScan = DateTime.now();
                  if (await clickCloudflareCheckbox(
                    c,
                    current: current,
                    headlessId: _view?.id,
                    documentUrl: document.toString(),
                  )) {
                    _challengeClickedGeneration = generation;
                  }
                } catch (_) {
                  /* 继续等待自动验证，绝不据输入结果报告通过。 */
                }
              }
              return;
            }
            _challengeSince = null;
            if (state['gate'] == true) {
              stableSince = null;
              _ageGateSeen = true;
              if (state['clicked'] == true) _ageClickedGeneration = generation;
              return;
            }
            if (confirmation != null) {
              if (state['content'] != true) {
                stableSince = null;
                return;
              }
              if (_ageGateSeen) {
                final cookies = await CookieManager.instance().getCookies(
                  url: WebUri(document.toString()),
                );
                if (!current() ||
                    !confirmation!.requiredCookies.every(
                      (name) => cookies.any(
                        (cookie) =>
                            cookie.name == name && '${cookie.value}'.isNotEmpty,
                      ),
                    )) {
                  stableSince = null;
                  return;
                }
              }
            }
            if (html.length > 200) {
              // DOM 关闭弹窗后可能立即导航；至少跨一轮检查仍稳定才交付页面。
              stableSince ??= DateTime.now();
              if (DateTime.now().difference(stableSince!) <
                  const Duration(milliseconds: 500)) {
                return;
              }
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
        } finally {
          inspecting = false;
        }
      },
      onReceivedError: (c, req, err) async {
        if (!identical(_ready, ready) || !(req.isForMainFrame ?? true)) {
          return;
        }
        // Android can deliver a main-frame error for the previous document
        // after a verification navigation has already started. Attribute an
        // error only when its URL is still the current document; otherwise it
        // must not fail the new readiness/navigation completer.
        final failed = Uri.tryParse(req.url.toString());
        final generation = _documentGeneration;
        final navigation = _navigation;
        if (failed == null || failed != _documentUri) return;
        final actual = await c.getUrl();
        if (!identical(_ready, ready) ||
            generation != _documentGeneration ||
            !identical(navigation, _navigation)) {
          return;
        }
        final current = actual == null ? null : Uri.tryParse(actual.toString());
        if (current != null && current != failed) return;
        final failure = SourceError(
          err.type == WebResourceErrorType.CANCELLED ? 'CANCELLED' : 'NETWORK',
          '${Uri.parse(origin).host}: ${err.description}',
          diagnostics: {
            'host': Uri.parse(origin).host,
            'transport': 'browser',
            'reason': _navigationReason(err.type),
          },
        );
        finish(failure);
        _finishNavigation(failure);
      },
      onReceivedHttpError: (c, request, response) {
        if (identical(_ready, ready) &&
            request.isForMainFrame == true &&
            request.url.toString() == _documentUri?.toString()) {
          _documentStatus = response.statusCode ?? 200;
        }
      },
      shouldOverrideUrlLoading: (c, action) =>
          action.isForMainFrame == false ||
              _allowsDocument(
                action.request.url == null
                    ? null
                    : Uri.tryParse(action.request.url.toString()),
              )
          ? NavigationActionPolicy.ALLOW
          : NavigationActionPolicy.CANCEL,
    );
    // The platform may call a failing load callback before run() returns.
    ready.future.ignore();
    try {
      final view = _view!;
      // Managed challenges usually pass on their own within a few seconds.
      timeout = Timer(
        const Duration(seconds: 35),
        () => finish(
          challenged
              ? SourceError(
                  'CLOUDFLARE',
                  'Cloudflare 验证未自动通过：{host}',
                  params: {'host': Uri.parse(origin).host},
                  url: bootstrap.toString(),
                )
              : _ageGateSeen
              ? SourceError(
                  'CONFIRM_REQUIRED',
                  '站点年龄确认未自动完成，请重试',
                  url: bootstrap.toString(),
                )
              : _timeout('CONNECT_TIMEOUT'),
        ),
      );
      // Native run() can itself lose its platform callback. Readiness, failure
      // and cancellation must be able to release the queue independently.
      await Future.any([view.run().then((_) => ready.future), ready.future]);
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
    return operation;
  }

  Future<Map<String, Object?>> _fetchWithRecovery(
    Map<String, dynamic> request,
    CancelToken? token,
  ) async {
    final canRetry = _isRead(request);
    var verified = false;
    bool claimVerification() {
      if (verified) return false;
      verified = true;
      return true;
    }

    if ({
          'GET',
          'HEAD',
        }.contains((request['method'] ?? 'GET').toString().toUpperCase()) &&
        !canRetry) {
      throw SourceError('CONFIG', '二进制请求参数无效');
    }
    for (var attempt = 0; ; attempt++) {
      _checkActive();
      if (token?.cancelError case final error?) throw error;
      try {
        final result = await _fetch(
          request,
          cancelToken: token,
          claimVerification: claimVerification,
        );
        final status = result['status'];
        if (!canRetry ||
            attempt >= 2 ||
            !{408, 500, 502, 503, 504}.contains(status)) {
          return result;
        }
      } on SourceError catch (error) {
        if (token?.cancelError case final cancelled?) throw cancelled;
        if (!canRetry ||
            attempt >= 2 ||
            error.code != 'NETWORK' ||
            (error.diagnostics['reason'] != null &&
                error.diagnostics['reason'] != 'CONNECTION')) {
          rethrow;
        }
        // A failed browser context must not poison the next read. Cookies
        // remain in the WebView store when the hidden page is recreated.
        await dispose();
      }
      final delay = Future<void>.delayed(
        Duration(milliseconds: 500 * (attempt + 1)),
      );
      await Future.any([
        delay,
        if (token != null) token.whenCancel.then<void>((error) => throw error),
      ]);
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
    if (!_allowsDocument(Uri.tryParse(url))) {
      throw SourceError('CONFIG', '浏览器验证地址必须同源');
    }
    _documentGeneration++;
    _ageGateSeen = false;
    _documentUri = Uri.parse(url);
    _documentRequest = Uri.parse(url);
    final ready = _navigation = Completer<void>();
    _navigationStarted = false;
    final timeout = Timer(
      const Duration(seconds: 35),
      () => _finishNavigation(
        _ageGateSeen
            ? SourceError('CONFIRM_REQUIRED', '站点年龄确认未自动完成，请重试', url: url)
            : SourceError(
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
      await Future.any([
        _controller!
            .loadUrl(urlRequest: URLRequest(url: WebUri(url)))
            .then((_) => waiting),
        waiting,
      ]);
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
    required bool Function() claimVerification,
  }) async {
    if (cancelToken?.cancelError case final error?) throw error;
    final target = Uri.parse(request['url'].toString());
    // 页面可能已跳转到语言子域。另一个入口仍请求原域名时，需要重新导航，
    // 不能从旧子域页面发起会被浏览器同源策略拒绝的 fetch。
    if (_ready?.isCompleted == true &&
        _documentUri != null &&
        _documentUri!.origin != target.origin &&
        (_documentConsumed || target != _documentRequest)) {
      await dispose();
    }
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
    if (_canReadDocument(request) && !_documentConsumed) {
      final document = await awaitCancelled(
        _readDocument(request['url'].toString(), cancelToken: cancelToken),
        cancelToken,
      );
      if (cancelToken?.cancelError case final error?) throw error;
      if (document != null) return document;
    }
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
        functionBody: r'''
        const init = { method: String(req.method || 'GET').toUpperCase(), headers: {...req.headers}, credentials: 'include', mode: 'same-origin', redirect: 'follow' };
        if (req.body != null && init.method !== 'GET') init.body = req.body;
        for (const k of Object.keys(init.headers)) {
          if (/^(user-agent|cookie|referer|accept-encoding)$/i.test(k)) delete init.headers[k];
        }
        const ctrl = new AbortController();
        const requests = window.__parkFetches ||= new Map();
        if (requests.has(id)) { requests.delete(id); return { error: 'cancelled' }; }
        requests.set(id, ctrl);
        let timedOut = false;
        const timer = setTimeout(() => { timedOut = true; ctrl.abort(); }, req.timeout > 0 ? req.timeout : 30000);
        init.signal = ctrl.signal;
        try {
          const r = await fetch(req.url, init);
          const headers = {};
          r.headers.forEach((v, k) => headers[k] = v);
          const binary = req.responseType === 'base64';
          const bytes = binary ? new Uint8Array(await r.arrayBuffer()) : null;
          let body;
          if (binary) {
            let raw = '';
            for (let i = 0; i < bytes.length; i += 32768) {
              raw += String.fromCharCode(...bytes.subarray(i, i + 32768));
            }
            body = btoa(raw);
          } else body = await r.text();
          const challengeBody = binary && [403, 429, 503].includes(r.status)
            ? new TextDecoder().decode(bytes.subarray(0, 65536)) : body;
          let ageGate = false, ageContent = true;
          if (!binary && gateSelector && (headers['content-type'] || '').includes('text/html')) {
            const doc = new DOMParser().parseFromString(body, 'text/html');
            ageGate = !!doc.querySelector(gateSelector);
            ageContent = !!doc.querySelector(readySelector);
          }
          return { status: r.status, headers, body, challengeBody, ageGate, ageContent, url: r.url };
        } catch (e) {
          return { error: String(e && e.message || e), reason: timedOut ? 'RECEIVE_TIMEOUT' : 'CONNECTION' };
        } finally { clearTimeout(timer); requests.delete(id); }
      ''',
        arguments: {
          'req': request,
          'id': id,
          'gateSelector': confirmation?.gateSelector ?? '',
          'readySelector': confirmation?.readySelector ?? '',
        },
      );
      final timeoutMs =
          request['timeout'] is num && (request['timeout'] as num) > 0
          ? (request['timeout'] as num).toInt()
          : 30000;
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
      ]).timeout(Duration(milliseconds: timeoutMs + 1000));
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
        final reason = value['reason'] == 'RECEIVE_TIMEOUT'
            ? 'RECEIVE_TIMEOUT'
            : 'CONNECTION';
        if (reason == 'RECEIVE_TIMEOUT') {
          await dispose();
          throw _timeout(reason);
        }
        throw SourceError(
          'NETWORK',
          '${Uri.parse(request['url'].toString()).host}: ${value['error']}',
          diagnostics: {
            'transport': 'browser',
            'reason': reason,
            'host': Uri.parse(origin).host,
          },
        );
      }
      final status = (value['status'] as num?)?.toInt() ?? 0;
      final body = value['body']?.toString() ?? '';
      final responseHeaders = value['headers'] as Map? ?? {};
      if (status == 403 &&
          hasFirewallBlockMarkers(value['challengeBody']?.toString() ?? body)) {
        throw firewallBlocked(
          Uri.parse(origin).host,
          url: request['url'].toString(),
        );
      }
      final challenge =
          responseHeaders['cf-mitigated'] == 'challenge' ||
          hasChallengeMarkers(value['challengeBody']?.toString() ?? body);
      var ageGate = false;
      if (!challenge && confirmation != null && value['ageGate'] == true) {
        final cookies = await CookieManager.instance().getCookies(
          url: WebUri(request['url'].toString()),
        );
        ageGate =
            value['ageContent'] == false ||
            !confirmation!.requiredCookies.every(
              (name) => cookies.any(
                (cookie) => cookie.name == name && '${cookie.value}'.isNotEmpty,
              ),
            );
      }
      if (challenge || ageGate) {
        // Cookie 失效后的年龄门和挑战响应都需要真正导航才能执行页面逻辑。
        // 仅重放读取请求，每次请求最多进行一次后台验证。
        if (_isRead(request) && claimVerification()) {
          await _verifyDocument(request['url'].toString(), cancelToken);
          final document = _canReadDocument(request)
              ? await awaitCancelled(
                  _readDocument(
                    request['url'].toString(),
                    cancelToken: cancelToken,
                  ),
                  cancelToken,
                )
              : null;
          if (cancelToken?.cancelError case final error?) throw error;
          if (document != null) return document;
          return await _fetch(
            request,
            cancelToken: cancelToken,
            claimVerification: claimVerification,
          );
        }
        throw SourceError(
          ageGate ? 'CONFIRM_REQUIRED' : 'CLOUDFLARE',
          ageGate ? '站点年龄确认未自动完成，请重试' : 'Cloudflare 验证：{host}',
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
    } on TimeoutException {
      await dispose();
      throw _timeout('RECEIVE_TIMEOUT');
    } finally {
      settled.complete();
    }
  }

  Future<Map<String, Object?>?> _readDocument(
    String requested, {
    CancelToken? cancelToken,
  }) async {
    final controller = _controller;
    if (controller == null) return null;
    final generation = _documentGeneration;
    try {
      final current = await awaitCancelled(
        controller.getUrl().timeout(const Duration(seconds: 5)),
        cancelToken,
      );
      final uri = current == null ? null : Uri.tryParse(current.toString());
      // 接受该次导航在授权域名内的重定向（如语言子域），其他资源仍使用真实请求。
      if (uri == null ||
          !_allowsDocument(uri) ||
          uri != _documentUri ||
          requested != _documentRequest?.toString()) {
        return null;
      }
      final value = await awaitCancelled(
        controller
            .evaluateJavascript(
              source: '''
        document.readyState === 'complete' && document.contentType === 'text/html'
          ? {body: document.documentElement.outerHTML, url: location.href, contentType: document.contentType}
          : null
      ''',
            )
            .timeout(const Duration(seconds: 5)),
        cancelToken,
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
        'status': _documentStatus,
        'headers': {'content-type': 'text/html'},
        'body': body,
        'url': uri.toString(),
      };
    } on TimeoutException {
      if (identical(controller, _controller) &&
          generation == _documentGeneration) {
        await dispose();
      }
      throw _timeout('RECEIVE_TIMEOUT');
    } on DioException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    _documentGeneration++;
    _documentRequest = null;
    _poll?.cancel();
    _session.cancel('browser session closed');
    _finishReady?.call(SourceError('CANCELLED', '浏览器会话已关闭'));
    _finishReady = null;
    _finishNavigation(SourceError('CANCELLED', '浏览器会话已关闭'));
    final view = _view;
    _view = null;
    _controller = null;
    _ready = null;
    try {
      await view?.dispose().timeout(const Duration(seconds: 3));
    } catch (e) {
      AppLog.error(e, event: 'browser_dispose');
    }
  }
}
