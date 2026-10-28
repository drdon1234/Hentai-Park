import 'age_confirmation.dart';
import 'challenge.dart';
import 'host.dart';

/// 保留 closed shadow root 的引用，不改变网页请求的 shadow 模式。
/// Android 没有 CDP 接口，必须在节点创建前安装。
const challengeDocumentScript = r'''
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
    for (let node = frame; node; node = node.parentElement || node.getRootNode().host) {
      const style = getComputedStyle(node);
      if (style.visibility !== 'visible' || style.display === 'none' || Number(style.opacity) === 0) return null;
    }
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
  BrowserInteractionHost controller, {
  required String url,
  required AgeConfirmationConfig? confirmation,
  required bool confirmAdult,
}) async {
  final result = await controller
      .javascript(
        body: r'''
    // Cloudflare 验证页会用 history.replaceState 追加 __cf_chl_* 参数；忽略它们，
    // 否则验证页永远无法被识别，只能等到启动超时。
    const clean = value => {
      try {
        const address = new URL(value);
        for (const key of [...address.searchParams.keys()]) {
          if (key.startsWith('__cf_chl_')) address.searchParams.delete(key);
        }
        return address.href;
      } catch (_) { return value; }
    };
    if (clean(location.href) !== clean(url) || document.readyState !== 'complete') return null;
    const visible = el => el && el.getClientRects().length > 0 &&
      getComputedStyle(el).display !== 'none' && getComputedStyle(el).visibility !== 'hidden';
    const gates = gateSelector ? [...document.querySelectorAll(gateSelector)].filter(visible) : [];
    const ready = !readySelector || !!document.querySelector(readySelector);
    let clicked = false;
    if (confirmAdult && gates.length && clickSelector) {
      // 仅接受年龄门内唯一的复选框；不填写问答、账号或其他表单。
      let checked = !checkSelector;
      if (checkSelector) {
        const checks = [...document.querySelectorAll(checkSelector)].filter(el =>
          visible(el) && el instanceof HTMLInputElement && el.type === 'checkbox' &&
          !el.disabled && gates.some(gate => gate.contains(el)));
        if (checks.length === 1) {
          if (!checks[0].checked) checks[0].click();
          checked = checks[0].checked;
        }
      }
      const buttons = [...document.querySelectorAll(clickSelector)].filter(el =>
        visible(el) && !el.disabled && el.getAttribute('aria-disabled') !== 'true' &&
        gates.some(gate => gate.contains(el)));
      if (checked && buttons.length === 1) { buttons[0].click(); clicked = true; }
    }
    return {url, title: document.title, html: document.documentElement.outerHTML.slice(0, 4194304),
      gate: gates.length > 0, content: ready, clicked};
    ''',
        arguments: {
          'url': url,
          'gateSelector': confirmation?.gateSelector ?? '',
          'readySelector': confirmation?.readySelector ?? '',
          'clickSelector': confirmation?.clickSelector ?? '',
          'checkSelector': confirmation?.checkSelector ?? '',
          'confirmAdult': confirmAdult,
        },
      )
      .timeout(const Duration(seconds: 5));
  return result is Map ? result : null;
}

/// 仅操作当前文档上唯一的可信标准框；输入成功不代表服务端放行。
Future<bool> clickCloudflareCheckbox(
  BrowserInteractionHost controller, {
  required bool Function() current,
  String? documentUrl,
}) async {
  if (!current() || documentUrl == null) return false;
  if (controller.supportsNativeInput) {
    final token = await controller
        .evaluate('window.__parkChallengeInput?.snapshot()?.token ?? null')
        .timeout(const Duration(seconds: 5));
    if (!current() || token is! String || token.isEmpty) return false;
    final clicked = await controller
        .nativeClick(url: documentUrl, token: token)
        .timeout(const Duration(seconds: 5));
    return current() && clicked;
  }
  if (!controller.supportsCdp) return false;
  Future<dynamic> call(String method, Map<String, dynamic> parameters) =>
      controller.cdp(method, parameters).timeout(const Duration(seconds: 5));
  final tree = await call('DOM.getDocument', {'depth': -1, 'pierce': true});
  final ids = <int>[];
  var budget = 20000;
  void visit(dynamic node, [int depth = 0]) {
    if (node is! Map || --budget < 0 || depth > 64) return;
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
        visit(child, depth + 1);
      }
    }
    visit(node['contentDocument'], depth + 1);
  }

  visit(tree is Map ? tree['root'] : null);
  if (!current() || budget < 0 || ids.length != 1) return false;
  final resolved = await call('DOM.resolveNode', {'nodeId': ids.single});
  final object = resolved is Map ? resolved['object'] : null;
  final objectId = object is Map ? object['objectId'] : null;
  if (!current() || objectId is! String) return false;
  // 由目标节点所属文档进行命中检查，穿过 closed shadow root；旧文档的
  // objectId 不能在新页面取得成功。移动后再次检查，避免 hover 弹层误点击。
  Future<Map?> check(bool take) async {
    if (!current()) return null;
    final result = await call('Runtime.callFunctionOn', {
      'objectId': objectId,
      'functionDeclaration': r'''function(expected, take) {
        if (!this.isConnected || this.ownerDocument !== document || location.href !== expected ||
            document.readyState !== 'complete' || window.__parkCdpInputConsumed) return null;
        const u = new URL(this.src);
        if (u.protocol !== 'https:' || u.hostname !== 'challenges.cloudflare.com' ||
            u.port || u.username || u.password) return null;
        const r = this.getBoundingClientRect(), x = r.x + 28, y = r.y + r.height / 2;
        for (let node = this; node; node = node.parentElement || node.getRootNode().host) {
          const style = getComputedStyle(node);
          if (style.visibility !== 'visible' || style.display === 'none' || Number(style.opacity) === 0) return null;
        }
        if (r.width < 290 || r.width > 310 || r.height < 60 || r.height > 85 ||
            r.x < 0 || r.y < 0 || r.right > innerWidth || r.bottom > innerHeight) return null;
        let node = this;
        for (let depth = 0; depth < 64; depth++) {
          const style = getComputedStyle(node);
          if (style.visibility !== 'visible' || style.display === 'none' || Number(style.opacity) === 0) return null;
          const root = node.getRootNode();
          if (!root.elementFromPoint || root.elementFromPoint(x,y) !== node) return null;
          if (root === document) {
            if (take) Object.defineProperty(window, '__parkCdpInputConsumed', {value:true});
            return {x,y,width:innerWidth,height:innerHeight};
          }
          node = root.host;
          if (!node) return null;
        }
        return null;
      }''',
      'arguments': [
        {'value': documentUrl},
        {'value': take},
      ],
      'returnByValue': true,
    });
    final remote = result is Map ? result['result'] : null;
    final value = remote is Map ? remote['value'] : null;
    return current() && value is Map ? value : null;
  }

  var pressed = false;
  Map? point;
  try {
    point = await check(false);
    if (point == null) return false;
    await call('Input.dispatchMouseEvent', {
      'type': 'mouseMoved',
      'x': point['x'],
      'y': point['y'],
      'buttons': 0,
    });
    final finalPoint = await check(true);
    if (finalPoint == null ||
        !current() ||
        [
          'x',
          'y',
          'width',
          'height',
        ].any((key) => point![key] != finalPoint[key])) {
      return false;
    }
    pressed = true;
    await call('Input.dispatchMouseEvent', {
      'type': 'mousePressed',
      'x': point['x'],
      'y': point['y'],
      'button': 'left',
      'clickCount': 1,
      'buttons': 1,
    });
    final active = current();
    await call('Input.dispatchMouseEvent', {
      'type': 'mouseReleased',
      'x': active ? point['x'] : -1,
      'y': active ? point['y'] : -1,
      'button': 'left',
      'clickCount': 1,
      'buttons': 0,
    });
    pressed = false;
    return current();
  } finally {
    if (pressed) {
      try {
        await call('Input.dispatchMouseEvent', {
          'type': 'mouseReleased',
          'x': -1,
          'y': -1,
          'button': 'left',
          'buttons': 0,
        });
      } catch (_) {}
    }
    try {
      await call('Runtime.releaseObject', {'objectId': objectId});
    } catch (_) {}
  }
}

/// 单个可见文档的自动验证状态；导航后必须重新创建，禁止重放网页请求。
enum BrowserAccessState { waiting, ready, failed }

class BrowserAccessDocument {
  bool _ageClicked = false;
  bool _challengeClicked = false;
  bool _sawAccessGate = false;

  Future<BrowserAccessState> inspect(
    BrowserInteractionHost controller, {
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
      final clicked = await clickCloudflareCheckbox(
        controller,
        current: current,
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
