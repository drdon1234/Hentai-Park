import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'age_confirmation.dart';
import 'challenge.dart';

/// 保留 closed shadow root 的引用，不改变网页请求的 shadow 模式。
/// Android 没有 DOM/CDP 接口，必须在页面创建这些节点前安装。
const androidChallengeDocumentScript = r'''
(() => {
  if (window !== window.top || window.__parkChallengeInput) return;
  const roots = new WeakMap();
  const attach = Element.prototype.attachShadow;
  Element.prototype.attachShadow = function(...args) {
    const root = Reflect.apply(attach, this, args);
    roots.set(this, root);
    return root;
  };
  const token = [...crypto.getRandomValues(new Uint32Array(4))].join('-');
  let consumed = false;
  const trusted = value => {
    try {
      const u = new URL(value);
      return u.protocol === 'https:' && u.hostname === 'challenges.cloudflare.com' &&
        !u.port && !u.username && !u.password;
    } catch (_) { return false; }
  };
  const snapshot = (expected, take = false) => {
    if (consumed || (expected && expected !== token) || document.readyState !== 'complete') return null;
    const frames = [];
    let budget = 10000;
    const visit = (root, depth = 0) => {
      if (depth > 32) { budget = 0; return; }
      for (const el of root.querySelectorAll('*')) {
        if (--budget <= 0) return;
        if (el.tagName === 'IFRAME' && trusted(el.src)) frames.push(el);
        const shadow = roots.get(el) || el.shadowRoot;
        if (shadow) visit(shadow, depth + 1);
      }
    };
    visit(document);
    if (budget <= 0 || frames.length !== 1) return null;
    const frame = frames[0], r = frame.getBoundingClientRect();
    if (r.width < 290 || r.width > 310 || r.height < 60 || r.height > 85 ||
        r.x < 0 || r.y < 0 || r.right > innerWidth || r.bottom > innerHeight) return null;
    const x = r.x + 28, y = r.y + r.height / 2;
    let root = document, hit;
    for (let depth = 0; depth <= 32; depth++) {
      hit = root.elementFromPoint(x, y);
      if (!hit) return null;
      const shadow = roots.get(hit) || hit.shadowRoot;
      if (!shadow) break;
      root = shadow;
    }
    if (hit !== frame) return null;
    if (take) consumed = true;
    return {token, url: location.href, frame: frame.src, x, y,
      width: innerWidth, height: innerHeight};
  };
  Object.defineProperty(window, '__parkChallengeInput', {
    value: Object.freeze({snapshot}), configurable: false, writable: false
  });
})();
''';

/// 同一段脚本内检查页面与年龄门，避免先读状态再点击时操作了新文档。
Future<Map?> inspectAccessDocument(
  InAppWebViewController controller, {
  required String url,
  required AgeConfirmationConfig? confirmation,
  required bool confirmAdult,
}) async {
  final result = await controller
      .callAsyncJavaScript(
        functionBody: r'''
    if (location.href !== url || document.readyState !== 'complete') return null;
    const visible = el => el && el.getClientRects().length > 0 &&
      getComputedStyle(el).display !== 'none' && getComputedStyle(el).visibility !== 'hidden';
    const gates = gateSelector ? [...document.querySelectorAll(gateSelector)].filter(visible) : [];
    const ready = !readySelector || !!document.querySelector(readySelector);
    let clicked = false;
    if (confirmAdult && gates.length && clickSelector) {
      const buttons = [...document.querySelectorAll(clickSelector)].filter(el =>
        visible(el) && !el.disabled && el.getAttribute('aria-disabled') !== 'true' &&
        gates.some(gate => gate.contains(el)));
      if (buttons.length === 1) { buttons[0].click(); clicked = true; }
    }
    return {url, title: document.title, html: document.documentElement.outerHTML.slice(0, 4194304),
      gate: gates.length > 0, content: ready, clicked};
    ''',
        arguments: {
          'url': url,
          'gateSelector': confirmation?.gateSelector ?? '',
          'readySelector': confirmation?.readySelector ?? '',
          'clickSelector': confirmation?.clickSelector ?? '',
          'confirmAdult': confirmAdult,
        },
      )
      .timeout(const Duration(seconds: 5));
  if (result?.error != null) return null;
  return result?.value is Map ? result!.value as Map : null;
}

/// 仅操作当前文档上唯一的可信标准框；输入成功不代表服务端放行。
Future<bool> clickCloudflareCheckbox(
  InAppWebViewController controller, {
  required bool Function() current,
  String? headlessId,
  String? documentUrl,
}) async {
  if (!current()) return false;
  if (defaultTargetPlatform == TargetPlatform.android) {
    if (headlessId == null || documentUrl == null) return false;
    final token = await controller
        .evaluateJavascript(
          source: 'window.__parkChallengeInput?.snapshot()?.token ?? null',
        )
        .timeout(const Duration(seconds: 5));
    if (!current() || token is! String || token.isEmpty) return false;
    final clicked = await const MethodChannel('hentai_park/platform')
        .invokeMethod<bool>('clickBrowserChallenge', {
          'id': headlessId,
          'url': documentUrl,
          'token': token,
        })
        .timeout(const Duration(seconds: 5));
    return current() && clicked == true;
  }
  if (defaultTargetPlatform != TargetPlatform.windows || !current()) {
    return false;
  }
  final tree = await controller
      .callDevToolsProtocolMethod(
        methodName: 'DOM.getDocument',
        parameters: {'depth': -1, 'pierce': true},
      )
      .timeout(const Duration(seconds: 5));
  final ids = <int>[];
  void visit(dynamic node) {
    if (node is! Map) return;
    if (node['nodeName'] == 'IFRAME') {
      final attrs = node['attributes'] as List? ?? const [];
      for (var i = 0; i + 1 < attrs.length; i += 2) {
        final uri = attrs[i] == 'src' ? Uri.tryParse('${attrs[i + 1]}') : null;
        if (uri != null &&
            challengeFrameNavigationAllowed(uri, isForMainFrame: false) &&
            node['nodeId'] is num) {
          ids.add((node['nodeId'] as num).toInt());
        }
      }
    }
    for (final key in ['children', 'shadowRoots']) {
      for (final child in node[key] as List? ?? const []) {
        visit(child);
      }
    }
    visit(node['contentDocument']);
  }

  visit(tree is Map ? tree['root'] : null);
  if (!current() || ids.length != 1) return false;
  final box = await controller
      .callDevToolsProtocolMethod(
        methodName: 'DOM.getBoxModel',
        parameters: {'nodeId': ids.single},
      )
      .timeout(const Duration(seconds: 5));
  final model = box is Map ? box['model'] : null;
  final quad = model is Map ? model['border'] : null;
  if (!current() ||
      quad is! List ||
      quad.length != 8 ||
      quad.any((v) => v is! num || !v.isFinite)) {
    return false;
  }
  final x = (quad[0] as num).toDouble(), y = (quad[1] as num).toDouble();
  final width = (quad[2] as num) - x, height = (quad[5] as num) - y;
  if (x < 0 ||
      y < 0 ||
      width < 290 ||
      width > 310 ||
      height < 60 ||
      height > 85) {
    return false;
  }
  for (final type in ['mouseMoved', 'mousePressed', 'mouseReleased']) {
    if (!current()) return false;
    await controller
        .callDevToolsProtocolMethod(
          methodName: 'Input.dispatchMouseEvent',
          parameters: {
            'type': type,
            'x': x + 28,
            'y': y + height / 2,
            if (type != 'mouseMoved') 'button': 'left',
            if (type != 'mouseMoved') 'clickCount': 1,
            'buttons': type == 'mousePressed' ? 1 : 0,
          },
        )
        .timeout(const Duration(seconds: 5));
  }
  return true;
}

/// 单个可见文档的自动验证状态；导航后必须重新创建，禁止重放网页请求。
enum BrowserAccessState { waiting, ready, failed }

class BrowserAccessDocument {
  bool _ageClicked = false;
  bool _challengeClicked = false;
  bool _sawAccessGate = false;

  Future<BrowserAccessState> inspect(
    InAppWebViewController controller, {
    required String url,
    required bool Function() current,
    required AgeConfirmationConfig? confirmation,
    required bool confirmAdult,
    int? httpError,
  }) async {
    if (!current()) return BrowserAccessState.waiting;
    final snapshot = await inspectAccessDocument(
      controller,
      url: url,
      confirmation: confirmation,
      confirmAdult: confirmAdult && !_ageClicked,
    );
    if (!current() || snapshot == null || snapshot['url'] != url) {
      return BrowserAccessState.waiting;
    }
    if (snapshot['clicked'] == true) _ageClicked = true;
    final challenge = hasChallengeMarkers(
      snapshot['html']?.toString() ?? '',
      title: snapshot['title']?.toString() ?? '',
    );
    if (challenge || snapshot['gate'] == true) _sawAccessGate = true;
    if (challenge && !_challengeClicked) {
      final id = controller.getViewId();
      final clicked = await clickCloudflareCheckbox(
        controller,
        current: current,
        headlessId: id is String ? id : null,
        documentUrl: url,
      );
      if (!current()) return BrowserAccessState.waiting;
      _challengeClicked = clicked;
    }
    if (!current() ||
        challenge ||
        snapshot['gate'] == true ||
        (confirmation != null && snapshot['content'] != true)) {
      return BrowserAccessState.waiting;
    }
    return httpError != null && !_sawAccessGate
        ? BrowserAccessState.failed
        : BrowserAccessState.ready;
  }
}
