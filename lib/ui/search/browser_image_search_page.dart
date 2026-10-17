import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/localization.dart';
import '../../engine/browser_image_search.dart';
import '../../engine/cookie_store.dart';
import '../../engine/http_service.dart';
import '../widgets/common.dart';

/// 浏览器内上传与结果页使用同一会话，站点只提供声明式导航条件。
class BrowserImageSearchPage extends StatefulWidget {
  const BrowserImageSearchPage({
    super.key,
    required this.source,
    required this.request,
    required this.imageBase64,
    required this.cancelToken,
  });
  final String source, imageBase64;
  final BrowserImageSearchRequest request;
  final CancelToken cancelToken;
  @override
  State<BrowserImageSearchPage> createState() => _BrowserImageSearchPageState();
}

class _BrowserImageSearchPageState extends State<BrowserImageSearchPage> {
  InAppWebViewController? _controller;
  Timer? _poll;
  bool _ready = false, _busy = false, _uploaded = false, _done = false;
  bool _needsRestart = false;
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
      setState(() => _ready = true);
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
    final route = ModalRoute.of(context);
    final controller = _controller;
    // 用户返回时路由可能已弹出但仍在退出动画，不能再弹出上一页。
    if (route?.isCurrent == true) {
      Navigator.pop(context);
    } else if (route?.isActive == true) {
      Navigator.of(context).removeRoute(route!);
    }
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
        _stable = _stableRows = 0;
        _lastUrl = _lastResult = '';
        _controller = null;
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
          return {url:location.href, ready:document.readyState,
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
          Navigator.pop(context, BrowserImageSearchResult(url, html));
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('图片反搜'))),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(Gap.page),
          child: Text(tr(_error ?? '正在反搜；如出现人机验证，请在下方页面中完成')),
        ),
        if (_error != null)
          TextButton(onPressed: _retry, child: Text(tr('继续'))),
        Expanded(
          child: !_ready
              ? const Center(child: CircularProgressIndicator())
              : InAppWebView(
                  key: ValueKey(_browserGeneration),
                  initialUrlRequest: URLRequest(
                    url: WebUri(widget.request.url.toString()),
                  ),
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
                  onRenderProcessGone: (_, _) =>
                      _fail('浏览器请求失败', restart: true),
                ),
        ),
      ],
    ),
  );
}
