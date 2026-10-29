import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/app_log.dart';
import '../../core/models.dart';
import '../../engine/browser_image_search.dart';
import '../../engine/browser_interaction.dart';
import '../../engine/challenge.dart';
import '../../engine/cookie_store.dart';
import '../../engine/http_service.dart';

/// 后台上传、验证并提取网页；用户始终在应用自建界面内操作。
class BrowserImageSearchPanel extends StatefulWidget {
  const BrowserImageSearchPanel({
    super.key,
    required this.source,
    required this.request,
    required this.imageBase64,
    required this.cancelToken,
    required this.onComplete,
    required this.onError,
  });
  final String source, imageBase64;
  final BrowserImageSearchRequest request;
  final CancelToken cancelToken;
  final ValueChanged<BrowserImageSearchResult?> onComplete;
  final ValueChanged<SourceError> onError;
  @override
  State<BrowserImageSearchPanel> createState() =>
      _BrowserImageSearchPanelState();
}

class _BrowserImageSearchPanelState extends State<BrowserImageSearchPanel> {
  InAppWebViewController? _controller;
  InAppWebView? _webView;
  Timer? _poll, _timeout;
  bool _ready = false, _busy = false, _uploaded = false, _done = false;
  DateTime? _challengeSince;
  int _clickedGeneration = -1;
  int _navigation = 0, _stableRows = 0;
  String _lastResult = '';
  Uri? _documentUri;
  String _operation = 'prepare';
  void Function()? _unregister;

  @override
  void initState() {
    super.initState();
    _documentUri = widget.request.url;
    _startTimeout();
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
        const Duration(milliseconds: 600),
        (_) => _check(),
      );
    } catch (error, stack) {
      _exception(error, stack);
    }
  }

  Future<void> _cancel() async {
    if (!mounted || _done) return;
    _done = true;
    _poll?.cancel();
    _timeout?.cancel();
    final controller = _controller;
    widget.onComplete(null);
    try {
      await controller?.stopLoading();
    } catch (_) {}
  }

  void _startTimeout() {
    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 90), () {
      _fail('请求超时', code: 'TIMEOUT', reason: 'RECEIVE_TIMEOUT');
    });
  }

  void _fail(
    String message, {
    String code = 'NETWORK',
    Uri? uri,
    String reason = 'NETWORK',
    String? type,
    int? status,
    Map<String, Object?> params = const {},
    String? action,
    StackTrace? stack,
  }) => _failError(
    SourceError(
      code,
      message,
      status: status,
      params: params,
      diagnostics: {
        'host': (uri ?? _documentUri ?? widget.request.url).host,
        'transport': 'browser',
        'reason': reason,
        'type': ?type,
      },
    ),
    action: action,
    stack: stack,
  );

  void _exception(Object error, StackTrace stack) {
    if (error is SourceError) {
      _failError(error, stack: stack);
    } else {
      _fail(
        error is TimeoutException ? '请求超时' : '浏览器请求失败',
        code: error is TimeoutException ? 'TIMEOUT' : 'NETWORK',
        reason: error is TimeoutException ? 'RECEIVE_TIMEOUT' : 'UNKNOWN',
        type: error.runtimeType.toString(),
        stack: stack,
      );
    }
  }

  void _failError(SourceError error, {String? action, StackTrace? stack}) {
    if (!mounted || _done) return;
    _done = true;
    _poll?.cancel();
    _timeout?.cancel();
    unawaited(_controller?.stopLoading().catchError((_) {}));
    AppLog.error(
      error,
      event: 'reverse_search',
      site: widget.source,
      action: action ?? _operation,
      stack: stack,
    );
    widget.onError(error);
  }

  Future<bool> _currentFailure(
    InAppWebViewController controller,
    WebResourceRequest request,
  ) async {
    if (!mounted || _done || request.isForMainFrame != true) return false;
    final generation = _navigation;
    final failed = Uri.tryParse(request.url.toString());
    if (failed == null || failed != _documentUri) return false;
    final actual = await controller.getUrl().timeout(
      const Duration(seconds: 8),
    );
    return mounted &&
        !_done &&
        generation == _navigation &&
        identical(controller, _controller) &&
        (actual == null || Uri.tryParse(actual.toString()) == failed);
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
      _operation = 'inspect';
      final current = await c.getUrl().timeout(const Duration(seconds: 8));
      if (!mounted || _done || generation != _navigation) return;
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
            title:document.title, html:document.documentElement.outerHTML.slice(0,4194304),
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
        _fail('反搜服务返回无效数据', code: 'PARSE');
        return;
      }
      if (state['url'] != uri.toString()) return;
      final cloudflare = hasChallengeMarkers(
        state['html']?.toString() ?? '',
        title: state['title']?.toString() ?? '',
      );
      if (state['verification'] == true || cloudflare) {
        _challengeSince ??= DateTime.now();
        final elapsed = DateTime.now().difference(_challengeSince!);
        if (elapsed >= const Duration(seconds: 35)) {
          _fail('站点验证未能自动完成，请稍后重试或检查网络与代理设置', code: 'CLOUDFLARE');
        } else if (cloudflare &&
            elapsed >= const Duration(seconds: 5) &&
            _clickedGeneration != generation) {
          try {
            if (await clickCloudflareCheckbox(
              c,
              documentUrl: uri.toString(),
              current: () =>
                  mounted &&
                  !_done &&
                  identical(c, _controller) &&
                  generation == _navigation,
            )) {
              _clickedGeneration = generation;
            }
          } catch (_) {
            // 输入接口不可用时继续等待站点自动验证，到期后在应用内重试。
          }
        }
        return;
      }
      _challengeSince = null;
      if (!_uploaded && state['ready'] == 'complete') {
        // 先结束桥接回调，再触发表单导航，避免页面销毁挂起回调。
        _uploaded = true;
        _operation = 'upload';
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
          _fail('浏览器请求失败', type: 'JavaScriptUploadError');
        }
        return;
      }
      if (widget.request.isResult(uri)) {
        _operation = 'result';
        final url = uri.toString();
        final target = widget.request.resultUrl(uri);
        if (target != uri) {
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
            state['ready'] == 'complete' &&
            _stableRows >= 1) {
          // 使用同次检查的快照，避免再次跨平台传输整份 HTML。
          final html = state['html'];
          if (html is! String ||
              html.isEmpty ||
              html.length > 4 * 1024 * 1024) {
            _fail('反搜服务返回无效数据', code: 'PARSE');
            return;
          }
          await CookieStore.instance.importFromWebView(
            uri,
            partition: widget.source,
          );
          if (!mounted || _done || generation != _navigation) return;
          _done = true;
          _poll?.cancel();
          _timeout?.cancel();
          widget.onComplete(BrowserImageSearchResult(url, html));
          return;
        }
      }
    } catch (error, stack) {
      if (mounted && !_done && generation == _navigation) {
        _exception(error, stack);
      }
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _done = true;
    _poll?.cancel();
    _timeout?.cancel();
    _unregister?.call();
    unawaited(_controller?.stopLoading().catchError((_) {}));
    _controller = null;
    super.dispose();
  }

  InAppWebView _createWebView() => InAppWebView(
    initialUserScripts: UnmodifiableListView([
      UserScript(
        source: challengeDocumentScript,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
    ]),
    initialUrlRequest: URLRequest(url: WebUri(widget.request.url.toString())),
    initialSettings: InAppWebViewSettings(
      userAgent: HttpService.instance.userAgent,
      useShouldOverrideUrlLoading: true,
      cacheEnabled: false,
    ),
    onWebViewCreated: (c) {
      if (_done) {
        unawaited(c.stopLoading().catchError((_) {}));
      } else {
        _controller = c;
      }
    },
    shouldOverrideUrlLoading: (_, action) {
      final uri = Uri.tryParse(action.request.url?.toString() ?? '');
      return _allowed(action.request.url?.toString()) ||
              (uri != null &&
                  challengeFrameNavigationAllowed(
                    uri,
                    isForMainFrame: action.isForMainFrame,
                  ))
          ? NavigationActionPolicy.ALLOW
          : NavigationActionPolicy.CANCEL;
    },
    onLoadStart: (c, url) async {
      _navigation++;
      _stableRows = 0;
      _lastResult = '';
      _documentUri = Uri.tryParse(url?.toString() ?? '');
      _challengeSince = null;
      if (!_allowed(url?.toString())) {
        await c.stopLoading();
        _fail('浏览器页面已离开站点声明的同源地址', code: 'CONFIG');
      } else {
        CookieStore.instance.trackBrowserUri(
          Uri.parse(url.toString()),
          widget.source,
        );
      }
    },
    onLoadStop: (_, _) => _check(),
    onReceivedError: (controller, request, error) async {
      // 主页面跳转后，Android 仍可能交付旧页面的失败；不能终止新文档。
      final nativeCode = RegExp(r'\bnet::ERR_[A-Z0-9_]+\b')
          .firstMatch(error.description)
          ?.group(0);
      if (error.type == WebResourceErrorType.CANCELLED ||
          nativeCode == 'net::ERR_ABORTED') {
        return;
      }
      final generation = _navigation;
      try {
        if (!await _currentFailure(controller, request)) return;
        final type = error.type.toString();
        final reason = error.type == WebResourceErrorType.HOST_LOOKUP
            ? 'DNS'
            : error.type == WebResourceErrorType.TIMEOUT
            ? 'RECEIVE_TIMEOUT'
            : type.contains('CERTIFICATE')
            ? 'TLS_CERTIFICATE'
            : type.contains('SSL') || type == 'SECURE_CONNECTION_FAILED'
            ? 'TLS_HANDSHAKE'
            : 'CONNECTION';
        _fail(
          '浏览器请求失败：{error}',
          uri: Uri.tryParse(request.url.toString()),
          reason: reason,
          type: type,
          params: {'error': '${request.url.host}: ${nativeCode ?? type}'},
          action: 'navigation',
        );
      } catch (error, stack) {
        if (!_done && generation == _navigation) _exception(error, stack);
      }
    },
    onReceivedHttpError: (controller, request, response) async {
      if (request.isForMainFrame == true &&
          !{403, 429, 503}.contains(response.statusCode)) {
        final generation = _navigation;
        try {
          if (!await _currentFailure(controller, request)) return;
          _fail(
            '浏览器请求失败：{error}',
            code: 'HTTP',
            status: response.statusCode,
            params: {
              'error': '${request.url.host}: HTTP ${response.statusCode}',
            },
            action: 'navigation',
          );
        } catch (error, stack) {
          if (!_done && generation == _navigation) _exception(error, stack);
        }
      }
    },
    onRenderProcessGone: (_, _) => _fail('浏览器请求失败', type: 'RenderProcessGone'),
  );

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      // 平台视图需要参与绘制才能得到真实视口；由父页面覆盖普通网页。
      child: _ready ? _webView! : const SizedBox.expand(),
    ),
  );
}
