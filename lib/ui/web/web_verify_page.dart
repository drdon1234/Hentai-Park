import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../engine/browser_fetcher.dart';
import '../../engine/challenge.dart';
import '../../engine/cookie_store.dart';
import '../../engine/domains.dart';
import '../../engine/http_service.dart';
import '../../engine/source_manager.dart';
import '../theme.dart';
import '../widgets/error_view.dart';

/// Built-in browser used for two flows:
/// - Cloudflare: load the site, wait until the challenge is gone, import clearance cookies.
/// - Web login: let the user sign in, then hand the required cookies to the source.
class WebVerifyPage extends StatefulWidget {
  const WebVerifyPage._(
    this._mode, {
    required this.source,
    required this.url,
    this.windowId,
  });

  factory WebVerifyPage.cloudflare({
    required String source,
    required String url,
  }) => WebVerifyPage._(_Mode.cloudflare, source: source, url: url);
  factory WebVerifyPage.login({required String source, required String url}) =>
      WebVerifyPage._(_Mode.login, source: source, url: url);
  factory WebVerifyPage.confirmation({
    required String source,
    required String url,
  }) => WebVerifyPage._(_Mode.confirmation, source: source, url: url);

  final String source;
  final String url;
  final _Mode _mode;
  final int? windowId;

  @override
  State<WebVerifyPage> createState() => _WebVerifyPageState();
}

enum _Mode { cloudflare, login, confirmation }

class _WebVerifyPageState extends State<WebVerifyPage> {
  InAppWebViewController? _c;
  double _progress = 0;
  bool _done = false;
  Timer? _poll;
  String _status = '';
  bool _browserFailed = false;
  int _browserGeneration = 0;
  bool _checking = false;
  bool _finishing = false;
  bool _sessionClosed = false;
  void Function()? _unregisterSession;
  int _navigationGeneration = 0;
  bool _loading = true;
  bool _popupOpen = false;

  Map get _confirmation =>
      SourceManager.instance.manifest(widget.source)?.network['confirmation']
          as Map? ??
      const {};

  bool _sourceAllowed(String? url) {
    if (_sessionClosed || url == null) return false;
    try {
      CookieStore.instance.checkBrowserUri(Uri.parse(url), widget.source);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _allowed(String? url) {
    if (_sessionClosed || url == null) return false;
    if (_sourceAllowed(url)) return true;
    if (widget._mode != _Mode.login) return false;
    // OAuth 新窗口可能先创建空白页，再进入真实授权地址。
    if (widget.windowId != null && url == 'about:blank') return true;
    final uri = Uri.tryParse(url);
    final account = SourceManager.instance.manifest(widget.source)?.account;
    return uri != null &&
        account != null &&
        loginNavigationAllowed(uri, account.loginDomains);
  }

  void _trackSourceUri(String url) {
    if (_sourceAllowed(url)) {
      CookieStore.instance.trackBrowserUri(Uri.parse(url), widget.source);
    }
  }

  Future<bool> _openWindow(CreateWindowAction action) async {
    if (widget._mode != _Mode.login ||
        _sessionClosed ||
        _popupOpen ||
        !mounted) {
      return false;
    }
    final url = action.request.url?.toString();
    if (url != null && url != 'about:blank' && !_allowed(url)) return false;
    _navigationGeneration++;
    _popupOpen = true;
    unawaited(
      Navigator.of(context)
          .push<bool>(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => WebVerifyPage._(
                _Mode.login,
                source: widget.source,
                url: widget.url,
                windowId: action.windowId,
              ),
            ),
          )
          .then((loggedIn) {
            _popupOpen = false;
            if (!mounted || _sessionClosed) return;
            if (loggedIn == true) {
              Navigator.pop(context, true);
            } else {
              _check();
            }
          }),
    );
    return true;
  }

  @override
  void initState() {
    super.initState();
    _browserFailed = !_allowed(widget.url);
    if (!_browserFailed) {
      _trackSourceUri(widget.url);
    }
    _unregisterSession = CookieStore.instance.registerBrowserSession((
      partition,
    ) async {
      if (partition != widget.source || !mounted) return;
      _sessionClosed = true;
      _done = true;
      _poll?.cancel();
      final controller = _c;
      _c = null;
      setState(() => _browserFailed = true);
      await controller?.stopLoading();
    });
    _status = widget._mode == _Mode.confirmation
        ? (_confirmation['message']?.toString() ?? '请在站点页面中完成确认后继续')
        : widget._mode == _Mode.cloudflare
        ? '正在打开站点，验证通常会自动完成；如出现勾选框请点一下'
        : '请在页面中登录；已看到账号或正常资源页时，可点击完成重新检查登录状态';
    _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _unregisterSession?.call();
    _sessionClosed = true;
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking || _sessionClosed || _popupOpen) return;
    final c = _c;
    if (c == null || _done) return;
    _checking = true;
    final generation = _navigationGeneration;
    try {
      // 停留在第三方授权页时，不导入 Cookie 或判断源站登录完成。
      final actual = (await c.getUrl())?.toString();
      if (_popupOpen ||
          generation != _navigationGeneration ||
          !_sourceAllowed(actual)) {
        return;
      }
      if (_loading || _progress < 1 || _browserFailed) return;
      final title = await c.getTitle() ?? '';
      final html =
          '${await c.evaluateJavascript(source: "document.documentElement ? document.documentElement.outerHTML.slice(0, 4000) : ''") ?? ''}';
      if (_loading ||
          generation != _navigationGeneration ||
          hasChallengeMarkers(html, title: title) ||
          html.length <= 200) {
        return;
      }
      if (widget._mode != _Mode.login) {
        if (await _confirmationReady()) {
          if (generation == _navigationGeneration) await _finish();
        }
      } else {
        final m = SourceManager.instance.manifest(widget.source)?.account;
        if (m == null) return;
        final uri = Uri.parse(
          m.cookieUrl.isNotEmpty ? m.cookieUrl : widget.url,
        );
        CookieStore.instance.checkBrowserUri(uri, widget.source);
        final values = await CookieStore.instance.importFromWebView(
          uri,
          partition: widget.source,
        );
        if (_sessionClosed ||
            !mounted ||
            _loading ||
            generation != _navigationGeneration) {
          return;
        }
        if (values.isNotEmpty &&
            m.requiredCookies.every((k) => (values[k] ?? '').isNotEmpty)) {
          _done = true;
          try {
            final ua = await c.evaluateJavascript(
              source: 'navigator.userAgent',
            );
            if (ua is String && ua.isNotEmpty) {
              HttpService.instance.userAgent = ua;
            }
            await BrowserFetcher.instance.reset(widget.url);
            if (_sessionClosed ||
                _loading ||
                generation != _navigationGeneration) {
              _done = false;
              return;
            }
            await SourceManager.instance.login(widget.source, values);
            if (mounted &&
                !_sessionClosed &&
                !_loading &&
                generation == _navigationGeneration) {
              Navigator.pop(context, true);
            } else {
              _done = false;
            }
          } catch (_) {
            _done = false;
            if (mounted && !_sessionClosed) {
              setState(() => _status = '尚未识别到登录，请确认网页显示账号后点击完成；如有验证提示，请先完成验证');
            }
          }
        }
      }
    } catch (_) {
      // 授权跳转或弹窗关闭会中断旧页面的异步调用，不能据此销毁新页面。
      if (mounted &&
          !_sessionClosed &&
          !_popupOpen &&
          !_loading &&
          identical(c, _c) &&
          generation == _navigationGeneration) {
        setState(() => _browserFailed = true);
      }
    } finally {
      _checking = false;
    }
  }

  Future<bool> _confirmationReady() async {
    final c = _c;
    if (c == null || _loading || _sessionClosed || _browserFailed) return false;
    final selector = _confirmation['selector']?.toString() ?? '';
    final readySelector = _confirmation['readySelector']?.toString() ?? '';
    if (selector.isNotEmpty) {
      final visible = await c.evaluateJavascript(
        source:
            '''
        Array.from(document.querySelectorAll(${jsonEncode(selector)})).some(el => {
          const style = getComputedStyle(el);
          return style.display !== 'none' && style.visibility !== 'hidden' && el.getClientRects().length > 0;
        })
      ''',
      );
      if (visible != false) return false;
    }
    if (readySelector.isNotEmpty) {
      final ready = await c.evaluateJavascript(
        source: '!!document.querySelector(${jsonEncode(readySelector)})',
      );
      if (ready != true) return false;
    }
    final requiredCookies =
        (_confirmation['requiredCookies'] as List? ?? const [])
            .whereType<String>();
    if (requiredCookies.isNotEmpty) {
      final uri = Uri.parse(widget.url)
          .replace(path: '/', query: '', fragment: '');
      final cookies = await CookieStore.instance.importFromWebView(
        uri,
        partition: widget.source,
      );
      if (!requiredCookies.every((key) => (cookies[key] ?? '').isNotEmpty)) {
        return false;
      }
    }
    return true;
  }

  Future<void> _finish() async {
    if (_finishing || _done || _sessionClosed || !_allowed(widget.url)) return;
    _finishing = true;
    try {
      final generation = _navigationGeneration;
      if (!await _confirmationReady() || generation != _navigationGeneration) {
        return;
      }
      final actual = (await _c?.getUrl())?.toString();
      if (!_allowed(actual) || _sessionClosed) return;
      _done = true;
      final uri = Uri.parse(widget.url);
      await CookieStore.instance.importFromWebView(
        uri.replace(path: '/', query: '', fragment: ''),
        partition: widget.source,
      );
      if (_sessionClosed || !mounted) return;
      if (_loading || generation != _navigationGeneration) {
        _done = false;
        return;
      }
      final ua = await _c?.evaluateJavascript(source: 'navigator.userAgent');
      if (ua is String && ua.isNotEmpty) HttpService.instance.userAgent = ua;
      await BrowserFetcher.instance.reset(widget.url);
      if (mounted &&
          !_sessionClosed &&
          !_loading &&
          generation == _navigationGeneration) {
        setState(() => _status = '验证通过');
        await Future.delayed(const Duration(milliseconds: 400));
        if (mounted &&
            !_sessionClosed &&
            !_loading &&
            generation == _navigationGeneration) {
          Navigator.pop(context, true);
        } else {
          _done = false;
        }
      } else {
        _done = false;
      }
    } catch (_) {
      _done = false;
      if (mounted && !_sessionClosed) setState(() => _browserFailed = true);
    } finally {
      _finishing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final name =
        SourceManager.instance.manifest(widget.source)?.name ?? widget.source;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget._mode != _Mode.login
              ? tr('验证 {value0}', {'value0': name})
              : tr('登录 {value0}', {'value0': name}),
        ),
        actions: [
          IconButton(
            tooltip: tr('刷新'),
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _c?.reload(),
          ),
          TextButton(
            onPressed: _browserFailed || _loading
                ? null
                : widget._mode == _Mode.login
                ? _check
                : _finish,
            child: Text(tr('完成')),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: _progress < 1
              ? LinearProgressIndicator(value: _progress, minHeight: 3)
              : const SizedBox(height: 3),
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: context.colors.primary.withValues(alpha: 0.12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  widget._mode != _Mode.login
                      ? Icons.verified_user_outlined
                      : Icons.login_rounded,
                  size: 18,
                  color: context.colors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(tr(_status), style: context.text.bodySmall),
                ),
              ],
            ),
          ),
          Expanded(
            child: _browserFailed
                ? SourceErrorView(
                    source: widget.source,
                    error: SourceError('NETWORK', '浏览器请求失败'),
                    onRetry: () => setState(() {
                      if (_sessionClosed || !_allowed(widget.url)) return;
                      _browserFailed = false;
                      _browserGeneration++;
                    }),
                  )
                : InAppWebView(
                    key: ValueKey(_browserGeneration),
                    windowId: _browserGeneration == 0 ? widget.windowId : null,
                    initialUrlRequest:
                        widget.windowId == null || _browserGeneration > 0
                        ? URLRequest(url: WebUri(widget.url))
                        : null,
                    initialSettings: InAppWebViewSettings(
                      userAgent: HttpService.instance.userAgent,
                      useShouldOverrideUrlLoading: true,
                      supportMultipleWindows: widget._mode == _Mode.login,
                      javaScriptCanOpenWindowsAutomatically:
                          widget._mode == _Mode.login,
                    ),
                    onWebViewCreated: (c) => _c = c,
                    onCreateWindow: (_, action) => _openWindow(action),
                    onCloseWindow: (_) {
                      if (widget.windowId != null && mounted) {
                        final route = ModalRoute.of(context);
                        if (route != null && route.isCurrent) {
                          Navigator.pop(context, false);
                        }
                      }
                    },
                    shouldOverrideUrlLoading: (_, action) {
                      final url = action.request.url?.toString();
                      if (!_allowed(url)) {
                        if (action.isForMainFrame &&
                            mounted &&
                            !_sessionClosed) {
                          setState(() => _browserFailed = true);
                        }
                        return NavigationActionPolicy.CANCEL;
                      }
                      if (action.isForMainFrame) {
                        // 在 onLoadStart 到来前就让旧页面的登录检查失效。
                        _navigationGeneration++;
                        _loading = true;
                        _progress = 0;
                      }
                      _trackSourceUri(url!);
                      return NavigationActionPolicy.ALLOW;
                    },
                    onLoadStart: (controller, url) async {
                      _navigationGeneration++;
                      _loading = true;
                      _progress = 0;
                      if (!_allowed(url?.toString())) {
                        await controller.stopLoading();
                        if (mounted) setState(() => _browserFailed = true);
                      } else {
                        _trackSourceUri(url!.toString());
                      }
                    },
                    onRenderProcessGone: (c, detail) {
                      _c = null;
                      if (mounted) setState(() => _browserFailed = true);
                    },
                    onProgressChanged: (_, p) {
                      if (mounted && !_sessionClosed) {
                        setState(() => _progress = p / 100);
                      }
                    },
                    onLoadStop: (_, url) {
                      if (_allowed(url?.toString())) {
                        _loading = false;
                        _check();
                      }
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
