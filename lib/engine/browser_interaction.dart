import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'access/browser_interaction.dart' as core;
import 'access/host.dart';
import 'age_confirmation.dart';
export 'access/browser_interaction.dart'
    show BrowserAccessState, challengeDocumentScript;

/// 客户端原生适配，服务端实现相同的能力接口。
class WebViewInteractionHost implements BrowserInteractionHost {
  WebViewInteractionHost(this.controller, {this.headlessId});
  final InAppWebViewController controller;
  final String? headlessId;
  @override
  bool get supportsCdp => defaultTargetPlatform == TargetPlatform.windows;
  @override
  bool get supportsNativeInput =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.linux;
  @override
  Future<dynamic> javascript({
    required String body,
    required Map<String, dynamic> arguments,
  }) async {
    final result = await controller.callAsyncJavaScript(
      functionBody: body,
      arguments: arguments,
    );
    return result?.error == null ? result?.value : null;
  }

  @override
  Future<dynamic> evaluate(String source) =>
      controller.evaluateJavascript(source: source);
  @override
  Future<dynamic> cdp(String method, Map<String, dynamic> parameters) =>
      controller.callDevToolsProtocolMethod(
        methodName: method,
        parameters: parameters,
      );
  @override
  Future<bool> nativeClick({required String url, required String token}) async {
    final id = headlessId ?? controller.getViewId();
    if (id == null) return false;
    final channel = defaultTargetPlatform == TargetPlatform.android
        ? const MethodChannel('hentai_park/platform')
        : MethodChannel('com.pichillilorenzo/flutter_inappwebview_$id');
    return await channel.invokeMethod<bool>('clickBrowserChallenge', {
          'id': id,
          'url': url,
          'token': token,
        }) ==
        true;
  }
}

Future<Map?> inspectAccessDocument(
  InAppWebViewController controller, {
  required String url,
  required AgeConfirmationConfig? confirmation,
  required bool confirmAdult,
}) => core.inspectAccessDocument(
  WebViewInteractionHost(controller),
  url: url,
  confirmation: confirmation,
  confirmAdult: confirmAdult,
);
Future<bool> clickCloudflareCheckbox(
  InAppWebViewController controller, {
  required bool Function() current,
  String? headlessId,
  String? documentUrl,
}) => core.clickCloudflareCheckbox(
  WebViewInteractionHost(controller, headlessId: headlessId),
  current: current,
  documentUrl: documentUrl,
);

class BrowserAccessDocument {
  final _document = core.BrowserAccessDocument();
  Future<core.BrowserAccessState> inspect(
    InAppWebViewController controller, {
    required String url,
    required bool Function() current,
    required AgeConfirmationConfig? confirmation,
    required bool confirmAdult,
    int? httpError,
  }) => _document.inspect(
    WebViewInteractionHost(controller),
    url: url,
    current: current,
    confirmation: confirmation,
    confirmAdult: confirmAdult,
    httpError: httpError,
  );
}
