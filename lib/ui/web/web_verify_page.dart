import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../engine/browser_fetcher.dart';
import '../../engine/cookie_store.dart';
import '../../engine/http_service.dart';
import '../../engine/source_manager.dart';
import '../../core/models.dart';
import '../theme.dart';
import '../widgets/error_view.dart';
import '../../core/localization.dart';

/// Built-in browser used for two flows:
/// - Cloudflare: load the site, wait until the challenge is gone, import clearance cookies.
/// - Web login: let the user sign in, then hand the required cookies to the source.
class WebVerifyPage extends StatefulWidget {
  const WebVerifyPage._(this._mode, {required this.source, required this.url});

  factory WebVerifyPage.cloudflare({
    required String source,
    required String url,
  }) => WebVerifyPage._(_Mode.cloudflare, source: source, url: url);
  factory WebVerifyPage.login({required String source, required String url}) =>
      WebVerifyPage._(_Mode.login, source: source, url: url);

  final String source;
  final String url;
  final _Mode _mode;

  @override
  State<WebVerifyPage> createState() => _WebVerifyPageState();
}

enum _Mode { cloudflare, login }

class _WebVerifyPageState extends State<WebVerifyPage> {
  InAppWebViewController? _c;
  double _progress = 0;
  bool _done = false;
  Timer? _poll;
  String _status = '';
  bool _browserFailed = false;
  int _browserGeneration = 0;

  @override
  void initState() {
    super.initState();
    _status = widget._mode == _Mode.cloudflare
        ? '正在打开站点，验证通常会自动完成；如出现勾选框请点一下'
        : '请在页面中登录，登录成功后会自动返回';
    _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    final c = _c;
    if (c == null || _done) return;
    if (widget._mode == _Mode.cloudflare) {
      final title = await c.getTitle() ?? '';
      final html =
          '${await c.evaluateJavascript(source: "document.documentElement ? document.documentElement.outerHTML.slice(0, 4000) : ''") ?? ''}';
      final challenged =
          title.contains('Just a moment') ||
          title.contains('Attention Required') ||
          html.contains('challenge-platform') ||
          html.contains('cf-chl');
      if (!challenged && _progress >= 1 && html.length > 200) await _finish();
    } else {
      final m = SourceManager.instance.manifest(widget.source)?.account;
      if (m == null) return;
      final uri = Uri.parse(m.cookieUrl.isNotEmpty ? m.cookieUrl : widget.url);
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri(uri.toString()),
      );
      final values = {for (final ck in cookies) ck.name: ck.value.toString()};
      if (m.requiredCookies.every((k) => (values[k] ?? '').isNotEmpty)) {
        _done = true;
        try {
          await SourceManager.instance.login(widget.source, values);
          if (mounted) Navigator.pop(context, true);
        } catch (e) {
          _done = false;
          if (mounted) setState(() => _status = '登录信息无效：$e');
        }
      }
    }
  }

  Future<void> _finish() async {
    _done = true;
    final uri = Uri.parse(widget.url);
    await CookieStore.instance.importFromWebView(
      Uri.parse('${uri.scheme}://${uri.host}/'),
      partition: widget.source,
    );
    final ua = await _c?.evaluateJavascript(source: 'navigator.userAgent');
    if (ua is String && ua.isNotEmpty) HttpService.instance.userAgent = ua;
    await BrowserFetcher.instance.reset(widget.url);
    if (mounted) {
      setState(() => _status = '验证通过');
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final name =
        SourceManager.instance.manifest(widget.source)?.name ?? widget.source;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget._mode == _Mode.cloudflare
              ? tr('验证 {value0}', {'value0': name})
              : tr('登录 {value0}', {'value0': name}),
        ),
        actions: [
          IconButton(
            tooltip: tr('刷新'),
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _c?.reload(),
          ),
          if (widget._mode == _Mode.cloudflare)
            TextButton(onPressed: _finish, child: Text(tr('完成'))),
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
                  widget._mode == _Mode.cloudflare
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
                      _browserFailed = false;
                      _browserGeneration++;
                    }),
                  )
                : InAppWebView(
                    key: ValueKey(_browserGeneration),
                    initialUrlRequest: URLRequest(url: WebUri(widget.url)),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      userAgent: HttpService.instance.userAgent,
                      useShouldOverrideUrlLoading: false,
                    ),
                    onWebViewCreated: (c) => _c = c,
                    onRenderProcessGone: (c, detail) {
                      _c = null;
                      if (mounted) setState(() => _browserFailed = true);
                    },
                    onProgressChanged: (_, p) =>
                        setState(() => _progress = p / 100),
                    onLoadStop: (_, _) => _check(),
                  ),
          ),
        ],
      ),
    );
  }
}
