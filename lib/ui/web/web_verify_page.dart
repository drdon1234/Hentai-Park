import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../engine/browser_fetcher.dart';
import '../../engine/challenge.dart';
import '../../engine/cookie_store.dart';
import '../../engine/desktop_shutdown.dart';
import '../../engine/domains.dart';
import '../../engine/http_service.dart';
import '../../engine/source_manager.dart';
import '../theme.dart';
import '../widgets/error_view.dart';

/// 共享源分区的登录、OAuth 授权与需要用户处理的站点验证。
class WebVerifyPage extends StatefulWidget {
  const WebVerifyPage._({
    required this.source,
    required this.url,
    this.windowId,
    this.confirmation = false,
    this.message,
  });

  factory WebVerifyPage.login({required String source, required String url}) =>
      WebVerifyPage._(source: source, url: url);

  factory WebVerifyPage.confirmation({
    required String source,
    required String url,
    String? message,
  }) => WebVerifyPage._(
    source: source,
    url: url,
    confirmation: true,
    message: message,
  );

  final bool confirmation;
  final String? message;
  final String source;
  final String url;
  final int? windowId;

  @override
  State<WebVerifyPage> createState() => _WebVerifyPageState();
}

class _WebVerifyPageState extends State<WebVerifyPage> {
  InAppWebViewController? _c;
  InAppWebViewKeepAlive _keepAlive = InAppWebViewKeepAlive();
  double _progress = 0;
  bool _done = false;
  Timer? _poll;
  String _status = '';
  bool _browserFailed = false;
  int _browserGeneration = 0;
  bool _checking = false;
  bool _sessionClosed = false;
  void Function()? _unregisterSession;
  int _navigationGeneration = 0;
  bool _loading = true;
  bool _popupOpen = false;
  bool _browserReady = false;

  bool _sourceAllowed(String? url) {
    if (_sessionClosed || url == null) return false;
    try {
      final uri = Uri.parse(url);
      if (!widget.confirmation) {
        final manifest = SourceManager.instance.manifest(widget.source);
        if (manifest == null ||
            !httpsDomainAddressAllowed(uri, declaredDomains(manifest.json))) {
          return false;
        }
      }
      CookieStore.instance.checkBrowserUri(uri, widget.source);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _allowed(String? url) {
    if (_sessionClosed || url == null) return false;
    if (_sourceAllowed(url)) return true;
    if (widget.confirmation) return false;
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

  Future<void> _refreshBrowserSessions() async {
    final manifest = SourceManager.instance.manifest(widget.source);
    if (manifest == null) return;
    await BrowserFetcher.instance.clearDomains(declaredDomains(manifest.json));
  }

  Future<bool> _openWindow(CreateWindowAction action) async {
    if (widget.confirmation || _sessionClosed || _popupOpen || !mounted) {
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
    _status = widget.confirmation
        ? (widget.message ?? tr('站点验证暂未完成'))
        : '请在页面中登录；已看到账号或正常资源页时，可点击完成重新检查登录状态';
    _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) => _check());
    unawaited(_prepareBrowser());
  }

  Future<void> _prepareBrowser() async {
    try {
      // 弹窗继承已恢复的浏览器会话，第三方 OAuth 地址不参与源 Cookie 同步。
      if (widget.windowId == null && !_browserFailed) {
        final account = SourceManager.instance.manifest(widget.source)?.account;
        final urls = <String>{
          widget.url,
          if (account?.cookieUrl.isNotEmpty == true) account!.cookieUrl,
        };
        for (final url in urls) {
          if (!_sourceAllowed(url)) continue;
          await CookieStore.instance.restoreToWebView(
            Uri.parse(url),
            partition: widget.source,
          );
          if (!mounted || _sessionClosed) return;
        }
      }
    } catch (_) {
      if (!mounted || _sessionClosed) return;
      _browserFailed = true;
    }
    if (mounted && !_sessionClosed) setState(() => _browserReady = true);
  }

  void _retryBrowser() {
    if (_sessionClosed || !_allowed(widget.url)) return;
    final old = _keepAlive;
    _keepAlive = InAppWebViewKeepAlive();
    PendingDisposals.instance.add(InAppWebViewController.disposeKeepAlive(old));
    setState(() {
      _c = null;
      _browserFailed = false;
      _browserReady = false;
      _loading = true;
      _progress = 0;
      _done = false;
      _navigationGeneration++;
      _browserGeneration++;
    });
    unawaited(_prepareBrowser());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _unregisterSession?.call();
    _sessionClosed = true;
    PendingDisposals.instance.add(
      InAppWebViewController.disposeKeepAlive(_keepAlive),
    );
    super.dispose();
  }

  Future<void> _check({bool manual = false}) async {
    if (widget.confirmation && !manual) return;
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
          '${await c.evaluateJavascript(source: "document.documentElement ? document.documentElement.outerHTML.slice(0, 4 * 1024 * 1024) : ''") ?? ''}';
      if (_loading ||
          generation != _navigationGeneration ||
          hasChallengeMarkers(html, title: title) ||
          html.length <= 200) {
        return;
      }
      if (widget.confirmation) {
        if (_sessionClosed || !mounted || !identical(c, _c)) return;
        await CookieStore.instance.importFromWebView(
          Uri.parse(actual!),
          partition: widget.source,
          authoritative: true,
        );
        if (_sessionClosed ||
            !mounted ||
            _loading ||
            generation != _navigationGeneration) {
          return;
        }
        await _refreshBrowserSessions();
        if (_sessionClosed ||
            !mounted ||
            _loading ||
            generation != _navigationGeneration) {
          return;
        }
        _done = true;
        Navigator.pop(context, true);
        return;
      }
      {
        final m = SourceManager.instance.manifest(widget.source)?.account;
        if (m == null) return;
        final uri = Uri.parse(
          m.cookieUrl.isNotEmpty ? m.cookieUrl : widget.url,
        );
        if (!_sourceAllowed(uri.toString())) return;
        CookieStore.instance.checkBrowserUri(uri, widget.source);
        final values = await CookieStore.instance.importFromWebView(
          uri,
          partition: widget.source,
          authoritative: true,
        );
        if (_sessionClosed ||
            !mounted ||
            _loading ||
            generation != _navigationGeneration) {
          return;
        }
        if (m.localStorageKeys.isNotEmpty) {
          final keys = jsonEncode(m.localStorageKeys);
          final origin = jsonEncode(uri.origin);
          final rawStorage = await c.evaluateJavascript(
            source:
                '(function(){const out={};if(location.origin!==$origin)return JSON.stringify(out);for(const key of $keys){const value=localStorage.getItem(key);if(value!==null)out[key]=value;}return JSON.stringify(out);})()',
          );
          Object? decodedStorage = rawStorage;
          if (rawStorage is String) {
            try {
              decodedStorage = jsonDecode(rawStorage);
            } catch (_) {
              decodedStorage = null;
            }
          }
          if (decodedStorage is Map) {
            for (final entry in decodedStorage.entries) {
              final key = entry.key.toString();
              if (m.localStorageKeys.contains(key) && entry.value is String) {
                values[key] = entry.value as String;
              }
            }
          }
        }
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
            await _refreshBrowserSessions();
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

  @override
  Widget build(BuildContext context) {
    final name =
        SourceManager.instance.manifest(widget.source)?.name ?? widget.source;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.confirmation ? tr('去确认') : tr('登录 {value0}', {'value0': name}),
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
                : () => _check(manual: true),
            child: SelectionContainer.disabled(child: Text(tr('完成'))),
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
                  Icons.login_rounded,
                  size: 18,
                  color: context.colors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.confirmation ? _status : tr(_status),
                    style: context.text.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _browserFailed
                ? SourceErrorView(
                    source: widget.source,
                    error: SourceError('NETWORK', '浏览器请求失败'),
                    onRetry: _retryBrowser,
                  )
                : !_browserReady
                ? const Center(child: CircularProgressIndicator())
                : InAppWebView(
                    key: ValueKey(_browserGeneration),
                    keepAlive: _keepAlive,
                    windowId: _browserGeneration == 0 ? widget.windowId : null,
                    initialUrlRequest:
                        widget.windowId == null || _browserGeneration > 0
                        ? URLRequest(url: WebUri(widget.url))
                        : null,
                    initialSettings: InAppWebViewSettings(
                      userAgent: HttpService.instance.userAgent,
                      useShouldOverrideUrlLoading: true,
                      supportMultipleWindows: true,
                      javaScriptCanOpenWindowsAutomatically: true,
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
                      final uri = Uri.tryParse(url ?? '');
                      if (!_sessionClosed &&
                          uri != null &&
                          challengeFrameNavigationAllowed(
                            uri,
                            isForMainFrame: action.isForMainFrame,
                          )) {
                        return NavigationActionPolicy.ALLOW;
                      }
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
