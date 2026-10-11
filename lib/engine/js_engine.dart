import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/models.dart';
import 'cookie_store.dart';
import 'crypto_bridge.dart';
import 'domains.dart';
import 'http_service.dart';

typedef PersistCallback = void Function(String sourceKey, Map<String, dynamic> data);

/// Result of evaluating a source script: the key it registered and its static manifest.
class ScriptInfo {
  ScriptInfo(this.key, this.manifest);
  final String key;
  final Map<String, dynamic> manifest;
}

/// Hosts each source in its own headless WebView (a separate JS realm with modern JS and DOMParser).
/// Sources cannot see each other's globals, and every native bridge call is attributed to the runtime
/// it came from, never to a key the script claims.
class JsEngine {
  JsEngine._();
  static final JsEngine instance = JsEngine._();

  final Map<String, SourceRuntime> _runtimes = {};
  PersistCallback? onPersist;

  /// Called after a runtime was recreated (renderer crash) so the source can be loaded again.
  void Function(String key)? onRestarted;
  final List<String> logs = [];
  String? _runtimeCode;

  Future<String> _runtimeSource() async => _runtimeCode ??= await rootBundle.loadString('assets/runtime/park_runtime.js');

  SourceRuntime runtime(String key) => _runtimes.putIfAbsent(key, () => SourceRuntime._(this, key));

  /// Evaluates an untrusted script in a throwaway runtime whose bridge refuses network, cookies and
  /// storage, and reports what it registers.
  Future<ScriptInfo> probe(String code) async {
    final r = SourceRuntime._(this, '', sandboxed: true);
    try {
      return await r.loadScript(code);
    } finally {
      await r.dispose();
    }
  }

  Future<void> disposeRuntime(String key) async => _runtimes.remove(key)?.dispose();

  void log(String tag, String message) {
    final line = '${DateTime.now().toIso8601String().substring(11, 19)} [$tag] $message';
    logs.add(line);
    if (logs.length > 500) logs.removeRange(0, logs.length - 500);
    if (kDebugMode) debugPrint(line);
  }

  // Convenience wrappers keyed by source.
  Future<void> updateSettings(String key, Map<String, dynamic> settings) => runtime(key).updateSettings(settings);

  Future<Object?> invoke(String key, String method, List<Object?> args, {Duration timeout = const Duration(seconds: 90)}) =>
      runtime(key).invoke(method, args, timeout: timeout);
}

class SourceRuntime {
  SourceRuntime._(this.engine, this.key, {this.sandboxed = false});

  final JsEngine engine;

  /// The source this runtime belongs to ('' while probing an unknown script).
  final String key;

  /// A probe runtime: script evaluation only, every bridge call is refused.
  final bool sandboxed;

  /// Domains the source declared; cookie mirroring and browser-mode origins must stay inside them.
  List<String> domains = const [];

  HeadlessInAppWebView? _view;
  InAppWebViewController? _c;
  Completer<void>? _ready;
  String? _code;
  bool _disposed = false;

  static const _bootstrap = r'''
(function () {
  const ready = new Promise((resolve) => {
    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) return resolve();
    window.addEventListener('flutterInAppWebViewPlatformReady', () => resolve(), { once: true });
  });
  async function call(name, payload) {
    await ready;
    const r = await window.flutter_inappwebview.callHandler(name, payload);
    if (r && r.__error) throw r.__error;
    return r ? r.__value : null;
  }
  function post(name, payload) { ready.then(() => window.flutter_inappwebview.callHandler(name, payload)); }
  window.Park = { __native: {
    request: (o) => call('park_request', o),
    crypto: (op, args) => call('park_crypto', { op, args }),
    cookies: (op, args) => call('park_cookies', { op, args }),
    persist: (key, data) => post('park_persist', { data }),
    log: (key, level, message) => post('park_log', { level, message }),
  } };
})();
''';

  String get _tag => key.isEmpty ? 'probe' : key;

  Future<void> start() async {
    if (_ready != null) return _ready!.future;
    final ready = _ready = Completer<void>();
    final runtime = await engine._runtimeSource();
    // Each runtime gets its own origin so storage APIs are not shared between sources either.
    final host = key.isEmpty ? 'probe' : safeHostLabel(key);
    _view = HeadlessInAppWebView(
      initialData: InAppWebViewInitialData(
        data: '<!doctype html><html><head><meta charset="utf-8"></head><body></body></html>',
        baseUrl: WebUri('https://$host.source.park.invalid/'),
      ),
      initialSettings: InAppWebViewSettings(javaScriptEnabled: true, blockNetworkImage: true, blockNetworkLoads: true),
      onWebViewCreated: (c) {
        _c = c;
        _registerHandlers(c);
      },
      onLoadStop: (c, _) async {
        if (ready.isCompleted) return;
        try {
          await c.evaluateJavascript(source: _bootstrap);
          final res = await c.callAsyncJavaScript(functionBody: '(0, eval)(code); return typeof Park.invoke;', arguments: {'code': runtime});
          if (res?.error != null || res?.value != 'function') throw StateError('runtime failed: ${res?.error}');
          ready.complete();
        } catch (e) {
          ready.completeError(e);
        }
      },
      onConsoleMessage: (c, m) => engine.log(_tag, m.message),
      onRenderProcessGone: (c, detail) => _restart(),
    );
    await _view!.run();
    return ready.future;
  }

  Future<void> _restart() async {
    if (_disposed) return;
    engine.log(_tag, 'runtime crashed, restarting');
    await _teardown();
    if (key.isNotEmpty && _code != null) engine.onRestarted?.call(key);
  }

  Future<void> _teardown() async {
    final old = _view;
    _view = null;
    _c = null;
    _ready = null;
    try {
      await old?.dispose();
    } catch (_) {}
  }

  Future<void> dispose() async {
    _disposed = true;
    await _teardown();
  }

  void _registerHandlers(InAppWebViewController c) {
    Future<Map<String, Object?>> guard(Future<Object?> Function() body) async {
      try {
        if (sandboxed) throw SourceError('CONFIG', '安装前预览时不允许访问网络与存储');
        return {'__value': await body()};
      } on SourceError catch (e) {
        return {
          '__error': {'code': e.code, 'message': e.message, 'status': e.status, 'url': e.url},
        };
      } catch (e) {
        return {
          '__error': {'code': 'NETWORK', 'message': e.toString()},
        };
      }
    }

    c.addJavaScriptHandler(
      handlerName: 'park_request',
      callback: (args) => guard(() {
        final o = (args.first as Map).cast<String, dynamic>();
        return HttpService.instance.sourceRequest(o, partition: key, domains: domains);
      }),
    );
    c.addJavaScriptHandler(
      handlerName: 'park_crypto',
      callback: (args) => guard(() async {
        final m = (args.first as Map).cast<String, dynamic>();
        return CryptoBridge.call(m['op'].toString(), (m['args'] as Map? ?? {}).cast<String, dynamic>());
      }),
    );
    c.addJavaScriptHandler(
      handlerName: 'park_cookies',
      callback: (args) => guard(() async {
        final m = (args.first as Map).cast<String, dynamic>();
        final a = (m['args'] as Map? ?? {}).cast<String, dynamic>();
        final uri = Uri.parse(a['url'].toString());
        // The jar is private to this source; only its own sites are mirrored into the shared WebView store.
        final mirror = hostInDomains(uri.host, domains);
        final cookies = CookieStore.instance;
        switch (m['op']) {
          case 'get':
            return cookies.get(uri, partition: key);
          case 'set':
            await cookies.set(uri, (a['cookies'] as Map? ?? {}).map((k, v) => MapEntry(k.toString(), v.toString())), partition: key, mirror: mirror);
            return true;
          case 'clear':
            await cookies.clear(uri, partition: key, mirror: mirror);
            return true;
        }
        return null;
      }),
    );
    c.addJavaScriptHandler(
      handlerName: 'park_persist',
      callback: (args) {
        if (sandboxed || key.isEmpty) return null;
        final m = (args.first as Map).cast<String, dynamic>();
        engine.onPersist?.call(key, (m['data'] as Map? ?? {}).cast<String, dynamic>());
        return null;
      },
    );
    c.addJavaScriptHandler(
      handlerName: 'park_log',
      callback: (args) {
        final m = (args.first as Map).cast<String, dynamic>();
        engine.log(_tag, m['message'].toString());
        return null;
      },
    );
  }

  /// Evaluates a source script and returns the key it registered with its static manifest.
  Future<ScriptInfo> loadScript(String code) async {
    await start();
    final res = await _c!.callAsyncJavaScript(
      functionBody: '''
        Park.__pending = null;
        (0, eval)(code);
        const def = Park.__pending;
        return def ? { key: def.key, manifest: Park.manifest(def.key) } : null;
      ''',
      arguments: {'code': code},
    );
    if (res?.error != null) throw SourceError('CONFIG', '脚本加载失败：${res!.error}');
    final value = res?.value;
    if (value is! Map || value['key'] is! String || (value['key'] as String).isEmpty) throw SourceError('CONFIG', '脚本没有调用 Park.register');
    final info = ScriptInfo(value['key'] as String, (value['manifest'] as Map? ?? {}).cast<String, dynamic>());
    if (key.isNotEmpty && info.key != key) throw SourceError('CONFIG', '脚本注册的 key（${info.key}）与安装记录（$key）不一致');
    domains = declaredDomains(info.manifest);
    _code = code;
    return info;
  }

  Future<Map<String, dynamic>> setup(Map<String, dynamic> state) async {
    final res = await _c!.callAsyncJavaScript(functionBody: 'return await Park.setup(key, state);', arguments: {'key': key, 'state': state});
    if (res?.error != null) throw SourceError('CONFIG', '源初始化失败：${res!.error}');
    final manifest = (res!.value as Map).cast<String, dynamic>();
    domains = declaredDomains(manifest);
    return manifest;
  }

  Future<void> updateSettings(Map<String, dynamic> settings) async {
    await start();
    await _c!.callAsyncJavaScript(functionBody: 'Park.updateSettings(key, settings);', arguments: {'key': key, 'settings': settings});
  }

  /// Calls a source method. Throws [SourceError] with the source's error code on failure.
  Future<Object?> invoke(String method, List<Object?> args, {Duration timeout = const Duration(seconds: 90)}) async {
    await start();
    final res = await _c!
        .callAsyncJavaScript(
          functionBody: 'return await Park.invoke(key, method, args);',
          arguments: {'key': key, 'method': method, 'args': jsonDecode(jsonEncode(args))},
        )
        .timeout(timeout, onTimeout: () => throw SourceError('NETWORK', '请求超时'));
    if (res?.error != null) throw SourceError('PARSE', res!.error!);
    final value = res?.value;
    if (value is! Map) throw SourceError('PARSE', '源返回了无效结果');
    if (value['ok'] == true) return value['value'];
    throw SourceError.fromJson(value['error']);
  }
}

/// A DNS-safe label derived from a source key.
String safeHostLabel(String key) {
  final s = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]'), '-');
  return s.isEmpty ? 'source' : s;
}
