import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 仅移除指定源站的声明凭证，不加载远端页面，也不清空浏览器其他数据。
Future<void> clearBrowserLocalStorage(Uri uri, List<String> keys) async {
  if (keys.isEmpty) return;
  final completed = Completer<void>();
  var started = false;
  var closed = false;
  var initialDocumentPending = true;
  final address = WebUri('${uri.origin}/');
  final view = HeadlessInAppWebView(
    // WebView2 忽略 loadData 的 baseUrl，以本地拦截响应建立真实的同源文档。
    initialUrlRequest: Platform.isWindows ? URLRequest(url: address) : null,
    initialData: Platform.isWindows
        ? null
        : InAppWebViewInitialData(
            data: '<!doctype html><html><head></head><body></body></html>',
            baseUrl: WebUri(uri.origin),
          ),
    initialSettings: InAppWebViewSettings(
      blockNetworkLoads: true,
      useShouldOverrideUrlLoading: true,
      useShouldInterceptRequest: true,
    ),
    shouldInterceptRequest: (_, request) async => WebResourceResponse(
      contentType: 'text/html',
      statusCode: request.url == address ? 200 : 403,
      reasonPhrase: request.url == address ? 'OK' : 'Forbidden',
      headers: {'Content-Security-Policy': "default-src 'none'"},
      data: Uint8List.fromList(
        utf8.encode('<!doctype html><html><body></body></html>'),
      ),
    ),
    shouldOverrideUrlLoading: (_, action) async {
      final target = action.request.url;
      if (initialDocumentPending &&
          action.isForMainFrame == true &&
          target?.scheme == uri.scheme &&
          target?.origin == uri.origin) {
        initialDocumentPending = false;
        return NavigationActionPolicy.ALLOW;
      }
      return NavigationActionPolicy.CANCEL;
    },
    onLoadStop: (controller, _) async {
      if (started || closed || completed.isCompleted) return;
      started = true;
      try {
        final cleared = await controller.evaluateJavascript(
          source:
              '(function(){if(location.origin!==${jsonEncode(uri.origin)})return false;'
              'for(const key of ${jsonEncode(keys)})localStorage.removeItem(key);'
              'return true;})()',
        );
        if (cleared != true) {
          throw StateError('Browser storage origin mismatch');
        }
        if (!completed.isCompleted) completed.complete();
      } catch (error, stack) {
        if (!completed.isCompleted) completed.completeError(error, stack);
      }
    },
  );
  try {
    // 先安装错误处理，再启动原生视图，避免快速失败变成未捕获异常。
    final result = completed.future.timeout(const Duration(seconds: 15));
    await Future.wait([
      view.run().timeout(const Duration(seconds: 15)),
      result,
    ], eagerError: true);
  } finally {
    closed = true;
    await view.dispose();
  }
}
