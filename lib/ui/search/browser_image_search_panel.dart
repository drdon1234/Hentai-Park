import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/localization.dart';
import '../../engine/browser_image_search.dart';
import '../../engine/cookie_store.dart';
import '../../engine/http_service.dart';

/// 后台上传并提取网页，只有需要手动验证时才显示同一会话的网页。
class BrowserImageSearchPanel extends StatefulWidget {
  const BrowserImageSearchPanel({
    super.key,
    required this.source,
    required this.request,
    required this.imageBase64,
    required this.cancelToken,
    required this.onComplete,
  });
  final String source, imageBase64;
  final BrowserImageSearchRequest request;
  final CancelToken cancelToken;
  final ValueChanged<BrowserImageSearchResult?> onComplete;
  @override
  State<BrowserImageSearchPanel> createState() =>
      _BrowserImageSearchPanelState();
}

class _BrowserImageSearchPanelState extends State<BrowserImageSearchPanel> {
  InAppWebViewController? _controller;
  // 显示验证区域时复用同一个平台视图，避免重建丢失上传会话。
  InAppWebView? _webView;
  Timer? _poll;
  bool _ready = false, _busy = false, _uploaded = false, _done = false;
  bool _needsRestart = false;
  bool _verification = false;
  int _browserGeneration = 0;
  int _navigation = 0, _stable = 0, _stableRows = 0;
  String _lastUrl = '', _lastResult = '';
  DateTime _deadline = DateTime.now().add(const Duration(seconds: 90));
  String? _error;
  void Function()? _unregister;

  @override
  void initState() {
    super.initState();
    widget.cancelToken.whenCancel.then((_) => _cancel());
    _unregister = CookieStore.instance.registerBrowserSession((key) async {
      if (key == widget.source) await _cancel();
    });
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    try {
      await CookieStore.instance.restoreToWebView(
        widget.request.url,
        partition: widget.source,
      );
      await CookieStore.instance.restoreToWebView(
        widget.request.uploadUrl,
        partition: widget.source,
      );
      if (!mounted || _done) return;
      setState(() {
        _webView = _createWebView();
        _ready = true;
      });
      _poll = Timer.periodic(
        const Duration(milliseconds: 1200),
        (_) => _check(),
      );
    } catch (_) {
      _fail('浏览器请求失败');
    }
  }

  Future<void> _cancel() async {
    if (!mounted || _done) return;
    _done = true;
    _poll?.cancel();
    final controller = _controller;
    widget.onComplete(null);
    try {
      await controller?.stopLoading();
    } catch (_) {}
  }

  void _fail(String message, {bool restart = false}) {
    if (!mounted || _done) return;
    _needsRestart = _needsRestart || restart;
    setState(() => _error = message);
  }

  Future<void> _retry() async {
    _deadline = DateTime.now().add(const Duration(seconds: 90));
    if (_needsRestart) {
      final controller = _controller;
      _navigation++;
      _browserGeneration++;
      _poll?.cancel();
      setState(() {
        _error = null;
        _ready = false;
        _needsRestart = false;
        _uploaded = false;
        _verification = false;
        _stable = _stableRows = 0;
        _lastUrl = _lastResult = '';
        _controller = null;
        _webView = null;
      });
      try {
        await controller?.stopLoading();
      } catch (_) {}
      if (!mounted || _done) return;
      await _prepare();
    } else {
      setState(() => _error = null);
      await (_ready ? _check() : _prepare());
    }
  }

  bool _allowed(String? value) {
    final uri = Uri.tryParse(value ?? '');
    return uri != null && widget.request.allows(uri);
  }

  Future<void> _check() async {
    final c = _controller;
    if (c == null || _busy || _done || !mounted) return;
    _busy = true;
    final generation = _navigation;
    try {
      if (DateTime.now().isAfter(_deadline) && _error == null) {
        _fail('反搜尚未完成，请在页面中完成验证或稍后重试');
      }
      final current = await c.getUrl().timeout(const Duration(seconds: 8));
      final uri = Uri.tryParse(current?.toString() ?? '');
      if (uri == null || !widget.request.allows(uri)) return;
      final response = await c
          .callAsyncJavaScript(
            functionBody: '''
          const verification = [...document.querySelectorAll(
            '#captcha-form, #challenge-form, #cf-challenge-running, form[action*="/sorry/"], form[action*="consent"], iframe[src*="recaptcha"][title], iframe[src*="hcaptcha"]'
          )].some(element => {
            const rect = element.getBoundingClientRect();
            const style = getComputedStyle(element);
            return rect.width > 100 && rect.height > 30 &&
              style.visibility !== 'hidden' && style.display !== 'none';
          });
          return {url:location.href, ready:document.readyState, verification,
            rows:document.querySelectorAll(resultSelector).length,
            empty:(document.querySelector(emptySelector)?.innerText||'').includes(emptyText)};
        ''',
            arguments: {
              'resultSelector': widget.request.resultSelector,
              'emptySelector': widget.request.emptySelector,
              'emptyText': widget.request.emptyText,
            },
          )
          .timeout(const Duration(seconds: 8));
      if (!mounted || _done || generation != _navigation) return;
      final state = response?.value;
      if (response?.error != null || state is! Map) {
        _fail('反搜服务返回无效数据');
        return;
      }
      if (state['url'] != uri.toString()) return;
      final verification = state['verification'] == true;
      if (_verification != verification) {
        setState(() => _verification = verification);
      }
      // 验证页不能被当作上传表单的宿主页；验证通过后继续原请求。
      if (verification) return;
      if (!_uploaded && state['ready'] == 'complete') {
        // 先结束桥接回调，再触发表单导航，避免页面销毁挂起回调。
        _uploaded = true;
        final upload = await c
            .callAsyncJavaScript(
              functionBody: '''
            const bytes=Uint8Array.from(atob(image),c=>c.charCodeAt(0));
            const form=document.createElement('form');form.method='POST';
            form.enctype='multipart/form-data';form.action=target;
            const input=document.createElement('input');input.type='file';input.name=field;
            const transfer=new DataTransfer();
            transfer.items.add(new File([bytes],'image.png',{type:'image/png'}));
            input.files=transfer.files;form.appendChild(input);
            document.body.appendChild(form);setTimeout(()=>HTMLFormElement.prototype.submit.call(form),100);
            return true;
          ''',
              arguments: {
                'image': widget.imageBase64,
                'target': widget.request.uploadUrl.toString(),
                'field': widget.request.fileField,
              },
            )
            .timeout(const Duration(seconds: 8));
        if (upload?.value != true && mounted && !_done) {
          _fail('浏览器请求失败', restart: true);
        }
        return;
      }
      if (widget.request.isResult(uri)) {
        final url = uri.toString();
        _stable = url == _lastUrl ? _stable + 1 : 0;
        _lastUrl = url;
        final target = widget.request.resultUrl(uri);
        if (_stable < 2) return;
        if (target != uri) {
          _stable = 0;
          await c.loadUrl(
            urlRequest: URLRequest(url: WebUri(target.toString())),
          );
          return;
        }
        final count = state['rows'];
        final signature = '$url:$count:${state['empty']}';
        _stableRows = signature == _lastResult ? _stableRows + 1 : 0;
        _lastResult = signature;
        if (count is num &&
            (count > 0 || state['empty'] == true) &&
            _stableRows >= 2) {
          final html = await c.getHtml().timeout(const Duration(seconds: 8));
          if (!mounted || _done || generation != _navigation) return;
          if (html == null || html.isEmpty || html.length > 4 * 1024 * 1024) {
            _fail('反搜服务返回无效数据');
            return;
          }
          await CookieStore.instance.importFromWebView(
            uri,
            partition: widget.source,
          );
          if (!mounted || _done || generation != _navigation) return;
          _done = true;
          _poll?.cancel();
          widget.onComplete(BrowserImageSearchResult(url, html));
          return;
        }
      }
    } catch (_) {
      if (mounted && !_done && generation == _navigation) {
        _fail('浏览器请求失败', restart: true);
      }
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _done = true;
    _poll?.cancel();
    _unregister?.call();
    unawaited(_controller?.stopLoading());
    _controller = null;
    super.dispose();
  }

  InAppWebView _createWebView() => InAppWebView(
    key: ValueKey(_browserGeneration),
    initialUrlRequest: URLRequest(url: WebUri(widget.request.url.toString())),
    initialSettings: InAppWebViewSettings(
      userAgent: HttpService.instance.userAgent,
      useShouldOverrideUrlLoading: true,
      cacheEnabled: false,
    ),
    onWebViewCreated: (c) => _controller = c,
    shouldOverrideUrlLoading: (_, action) =>
        _allowed(action.request.url?.toString())
        ? NavigationActionPolicy.ALLOW
        : NavigationActionPolicy.CANCEL,
    onLoadStart: (c, url) async {
      _navigation++;
      if (!_allowed(url?.toString())) {
        await c.stopLoading();
        _fail('浏览器页面已离开站点声明的同源地址');
      } else {
        CookieStore.instance.trackBrowserUri(
          Uri.parse(url.toString()),
          widget.source,
        );
      }
    },
    onReceivedError: (_, request, error) {
      if (request.isForMainFrame == true) {
        _fail('浏览器请求失败', restart: true);
      }
    },
    onReceivedHttpError: (_, request, _) {
      if (request.isForMainFrame == true) {
        _fail('浏览器请求失败', restart: true);
      }
    },
    onRenderProcessGone: (_, _) => _fail('浏览器请求失败', restart: true),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_error != null || _verification)
        Text(tr(_error ?? '正在反搜；如出现人机验证，请在下方页面中完成')),
      if (_error != null) TextButton(onPressed: _retry, child: Text(tr('继续'))),
      if (_ready)
        Offstage(
          offstage: !_verification,
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: _webView!,
          ),
        ),
    ],
  );
}
