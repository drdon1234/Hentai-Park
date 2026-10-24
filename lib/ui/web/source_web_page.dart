import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../engine/cookie_store.dart';
import '../../engine/desktop_shutdown.dart';
import '../../engine/domains.dart';
import '../../engine/http_service.dart';
import '../../engine/source_manager.dart';
import '../theme.dart';
import '../widgets/error_view.dart';

/// 在应用内浏览插件声明域内的原站页面（如排行榜商品页），使用该源的 Cookie 分区。
/// 离开声明域的链接不在此页打开，由用户选择是否交给系统浏览器。
class SourceWebPage extends StatefulWidget {
  const SourceWebPage({super.key, required this.source, required this.url});
  final String source;
  final Uri url;

  @override
  State<SourceWebPage> createState() => _SourceWebPageState();
}

class _SourceWebPageState extends State<SourceWebPage> {
  final _keepAlive = InAppWebViewKeepAlive();
  InAppWebViewController? _controller;
  void Function()? _unregister;
  double _progress = 0;
  String _title = '';
  bool _ready = false, _failed = false, _closed = false;

  bool _allowed(Uri? uri) {
    final manifest = SourceManager.instance.manifest(widget.source);
    if (_closed || uri == null || manifest == null) return false;
    if (!httpsDomainAddressAllowed(uri, declaredDomains(manifest.json))) {
      return false;
    }
    try {
      CookieStore.instance.checkBrowserUri(uri, widget.source);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _unregister = CookieStore.instance.registerBrowserSession((
      partition,
    ) async {
      if (partition != widget.source || !mounted) return;
      _closed = true;
      setState(() => _failed = true);
      await _controller?.stopLoading();
    });
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    if (!_allowed(widget.url)) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    try {
      CookieStore.instance.trackBrowserUri(widget.url, widget.source);
      await CookieStore.instance.restoreToWebView(
        widget.url,
        partition: widget.source,
      );
    } catch (_) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (mounted && !_closed) setState(() => _ready = true);
  }

  @override
  void dispose() {
    _closed = true;
    _unregister?.call();
    PendingDisposals.instance.add(
      InAppWebViewController.disposeKeepAlive(_keepAlive),
    );
    super.dispose();
  }

  Future<void> _external(Uri uri) async {
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!opened && mounted) context.toast(tr('无法打开原站'));
  }

  @override
  Widget build(BuildContext context) {
    final name =
        SourceManager.instance.manifest(widget.source)?.name ?? widget.source;
    return Scaffold(
      appBar: AppBar(
        title: Text(_title.isEmpty ? name : _title, maxLines: 1),
        actions: [
          IconButton(
            tooltip: tr('刷新'),
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _controller?.reload(),
          ),
          IconButton(
            tooltip: tr('在浏览器中打开'),
            icon: const Icon(Icons.open_in_browser_rounded),
            onPressed: () async {
              final current = await _controller?.getUrl();
              await _external(current?.uriValue ?? widget.url);
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: _progress < 1 && !_failed
              ? LinearProgressIndicator(value: _progress, minHeight: 3)
              : const SizedBox(height: 3),
        ),
      ),
      body: _failed
          ? SourceErrorView(
              source: widget.source,
              error: SourceError('NETWORK', '浏览器请求失败'),
              onRetry: () {
                if (_closed) return;
                setState(() {
                  _failed = false;
                  _ready = false;
                });
                unawaited(_prepare());
              },
            )
          : !_ready
          ? const Center(child: CircularProgressIndicator())
          : InAppWebView(
              keepAlive: _keepAlive,
              initialUrlRequest: URLRequest(url: WebUri.uri(widget.url)),
              initialSettings: InAppWebViewSettings(
                userAgent: HttpService.instance.userAgent,
                useShouldOverrideUrlLoading: true,
              ),
              onWebViewCreated: (c) => _controller = c,
              onTitleChanged: (_, title) {
                if (mounted) setState(() => _title = title ?? '');
              },
              onProgressChanged: (_, p) {
                if (mounted) setState(() => _progress = p / 100);
              },
              shouldOverrideUrlLoading: (_, action) async {
                final uri = action.request.url?.uriValue;
                if (!action.isForMainFrame || _allowed(uri)) {
                  if (uri != null && action.isForMainFrame) {
                    CookieStore.instance.trackBrowserUri(uri, widget.source);
                  }
                  return NavigationActionPolicy.ALLOW;
                }
                if (uri != null &&
                    (uri.scheme == 'https' || uri.scheme == 'http') &&
                    mounted) {
                  context.toast(
                    tr('该链接不属于此站点'),
                    action: SnackBarAction(
                      label: tr('在浏览器中打开'),
                      onPressed: () => _external(uri),
                    ),
                  );
                }
                return NavigationActionPolicy.CANCEL;
              },
              onLoadStop: (_, url) async {
                final uri = url?.uriValue;
                if (uri == null || !_allowed(uri)) return;
                await CookieStore.instance.importFromWebView(
                  uri,
                  partition: widget.source,
                );
              },
            ),
    );
  }
}
