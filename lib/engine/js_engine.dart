import 'dart:async';
import 'dart:convert';
import 'dart:developer' show Timeline;

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/app_log.dart';
import '../core/models.dart';
import 'age_confirmation.dart';
import 'cookie_store.dart';
import 'crypto_bridge.dart';
import 'domains.dart';
import 'http_service.dart';
import 'live_chat_protocol.dart';
import 'live_chat_transport.dart';
import 'source_identity.dart';

typedef PersistCallback = Future<void> Function(
  String sourceKey,
  Map<String, dynamic> data, {
  bool flush,
});

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
  final Map<String, Future<void>> _closingRuntimes = {};
  bool _closing = false;
  bool _suspended = false;
  PersistCallback? onPersist;

  /// Enqueues a source reload after its runtime is invalidated by a crash or timeout.
  void Function(String key)? onRestarted;
  String? _runtimeCode;

  Future<String> _runtimeSource() async => _runtimeCode ??= await rootBundle
      .loadString('assets/runtime/park_runtime.js');

  String? _runtimeHash;

  /// Identifies the bundled runtime; cached manifests are only valid for the runtime that made them.
  Future<String> runtimeHash() async => _runtimeHash ??= crypto.sha256
      .convert(utf8.encode(await _runtimeSource()))
      .toString();

  SourceRuntime runtime(String key) {
    if (_closing || _suspended) throw SourceError('CANCELLED', '应用正在关闭');
    return _runtimes.putIfAbsent(key, () => SourceRuntime._(this, key));
  }

  /// 可逆地拒绝新桥接调用，等待已接受的写入完成；失败退出后仍复用原运行时。
  Future<void> suspend() async {
    _suspended = true;
    for (final runtime in _runtimes.values.toList()) {
      while (runtime._bridgeCalls.isNotEmpty) {
        await Future.wait(runtime._bridgeCalls.toList());
      }
    }
  }

  void resume() => _suspended = false;

  /// 原生引擎退出前释放 WebView，避免插件析构时访问已失效的 messenger。
  Future<void> dispose() async {
    _closing = true;
    final runtimes = _runtimes.values.toList();
    _runtimes.clear();
    await Future.wait([for (final runtime in runtimes) runtime.dispose()]);
    await Future.wait(_closingRuntimes.values.toList());
  }

  /// Evaluates an untrusted script in a throwaway runtime whose bridge refuses network, cookies and
  /// storage, and reports what it registers.
  Future<ScriptInfo> probe(String code) async {
    if (_closing || _suspended) throw SourceError('CANCELLED', '应用正在关闭');
    final r = SourceRuntime._(this, '', sandboxed: true);
    try {
      return await r.loadScript(code);
    } finally {
      await r.dispose();
    }
  }

  Future<void> disposeRuntime(String key) async {
    await _runtimes.remove(key)?.dispose();
    await _closingRuntimes[key];
  }

  // Convenience wrappers keyed by source.
  Future<void> updateSettings(String key, Map<String, dynamic> settings) =>
      runtime(key).updateSettings(settings);

  Future<Object?> invoke(
    String key,
    String method,
    List<Object?> args, {
    Duration timeout = const Duration(seconds: 90),
    CancelToken? cancelToken,
  }) =>
      runtime(key)
          .invoke(method, args, timeout: timeout, cancelToken: cancelToken);
}

class SourceRuntime {
  SourceRuntime._(this.engine, this.key, {this.sandboxed = false});

  final JsEngine engine;

  /// The source this runtime belongs to ('' while probing an unknown script).
  final String key;

  /// A probe runtime: script evaluation only, every bridge call is refused.
  final bool sandboxed;

  /// Domains the source declared; cookie mirroring and browser-mode origins must stay inside them.
  List<String> domains = [];
  List<String> chatDomains = [];
  AgeConfirmationConfig? _confirmation;

  HeadlessInAppWebView? _view;
  InAppWebViewController? _c;
  Completer<void>? _ready;
  String? _code;
  bool _disposed = false;
  bool _configured = false;
  Future<void>? _closing;
  final _requests = CancelToken();
  final Map<String, CancelToken> _invocations = {};
  int _nextInvocation = 0;
  final Set<Future<void>> _bridgeCalls = {};
  final _rendererGone = Completer<void>();
  static const _platform = MethodChannel('hentai_park/platform');

  String get _origin => 'https://${sourceHost(key)}.source.park.invalid/';

  static const _bootstrap = r'''
(function () {
  const ready = new Promise((resolve) => {
    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) return resolve();
    window.addEventListener('flutterInAppWebViewPlatformReady', () => resolve(), { once: true });
  });
  async function call(name, payload) {
    await ready;
    const r = JSON.parse(await window.flutter_inappwebview.callHandler(name, payload));
    if (r && r.__error) throw r.__error;
    return r ? r.__value : null;
  }
  function post(name, payload) { ready.then(() => window.flutter_inappwebview.callHandler(name, payload)); }
  window.Park = { __native: {
    request: (o) => call('park_request', o),
    chatRequest: (o) => call('park_chat_request', o),
    crypto: (op, args) => call('park_crypto', { op, args }),
    cookies: (op, args) => call('park_cookies', { op, args }),
    persist: (key, data, flush = false) => call('park_persist', { data, flush }),
    log: (key, level, message) => post('park_log', { level, message }),
  } };
})();
''';

  String get _tag => key.isEmpty ? 'probe' : key;

  Future<T> _bounded<T>(
    Future<T> operation,
    Duration timeout,
    String code,
    String message,
  ) => operation.timeout(
    timeout,
    onTimeout: () {
      _invalidate(timedOut: true);
      throw SourceError(code, message);
    },
  );

  Future<void> start() async {
    if (_disposed) throw SourceError('CONFIG', '站点运行环境已关闭');
    if (_ready != null) return _ready!.future;
    final ready = _ready = Completer<void>();
    await engine._closingRuntimes[key];
    final runtime = await engine._runtimeSource();
    if (_disposed) throw SourceError('CONFIG', '站点运行环境已关闭');
    var initialDocumentPending = true;
    // Each runtime gets its own origin so storage APIs are not shared between sources either.
    _view = HeadlessInAppWebView(
      initialData: InAppWebViewInitialData(
        data: '<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; script-src \'unsafe-inline\' \'unsafe-eval\'; connect-src \'none\'; img-src \'none\'; frame-src \'none\'; object-src \'none\'; worker-src \'none\'; form-action \'none\'; base-uri \'none\'"></head><body></body></html>',
        baseUrl: WebUri(_origin),
      ),
      initialSettings: InAppWebViewSettings(
        blockNetworkImage: true,
        blockNetworkLoads: true,
        useShouldOverrideUrlLoading: true,
        javaScriptHandlersForMainFrameOnly: true,
        javaScriptBridgeForMainFrameOnly: true,
      ),
      onWebViewCreated: (c) {
        _c = c;
        _registerHandlers(c);
      },
      onLoadStop: (c, _) async {
        initialDocumentPending = false;
        if (ready.isCompleted) return;
        try {
          await _bounded(
            c.evaluateJavascript(source: _bootstrap),
            const Duration(seconds: 30),
            'CONFIG',
            '站点启动超时',
          );
          final res = await _bounded(
            c.callAsyncJavaScript(
              functionBody: '(0, eval)(code); return typeof Park.invoke;',
              arguments: {'code': runtime},
            ),
            const Duration(seconds: 30),
            'CONFIG',
            '站点启动超时',
          );
          if (res?.error != null || res?.value != 'function') {
            throw StateError('runtime failed: ${res?.error}');
          }
          if (!ready.isCompleted) ready.complete();
        } catch (e) {
          if (!ready.isCompleted) ready.completeError(e);
        }
      },
      // Source code stays in the initial document, including on Windows where
      // loadData uses about:blank instead of honoring baseUrl.
      shouldOverrideUrlLoading: (c, action) {
        // WebKit 对 loadData 的初始隔离文档也触发导航策略；只放行这一次。
        if (defaultTargetPlatform == TargetPlatform.linux &&
            initialDocumentPending &&
            action.isForMainFrame == true &&
            action.request.url?.toString() == _origin) {
          initialDocumentPending = false;
          return NavigationActionPolicy.ALLOW;
        }
        return NavigationActionPolicy.CANCEL;
      },
      onRenderProcessGone: (c, detail) {
        if (!_rendererGone.isCompleted) _rendererGone.complete();
        _restart();
      },
      onRenderProcessUnresponsive: (c, url) =>
          WebViewRenderProcessAction.TERMINATE,
    );
    await _view!.run();
    return ready.future;
  }

  void _invalidate({bool timedOut = false}) {
    if (_disposed) return;
    _disposed = true;
    _requests.cancel('runtime invalidated');
    for (final token in _invocations.values) {
      token.cancel('runtime invalidated');
    }
    final closing = _closing ??= _teardown(timedOut: timedOut);
    engine._closingRuntimes[key] = closing;
    unawaited(
      closing.whenComplete(() {
        if (identical(engine._closingRuntimes[key], closing)) {
          engine._closingRuntimes.remove(key);
        }
      }),
    );
    if (!identical(engine._runtimes[key], this)) return;
    if (key.isNotEmpty &&
        _code != null &&
        _configured &&
        engine.onRestarted != null) {
      // Enqueue synchronously so SourceManager calls wait for the reload. Its loader
      // disposes this instance and drains accepted persistence before reading state.
      engine.onRestarted!(key);
    } else {
      engine._runtimes.remove(key);
    }
  }

  Future<void> _restart() async {
    AppLog.record({'event': 'runtime_restart', 'site': _tag});
    _invalidate();
  }

  Future<void> _teardown({bool timedOut = false}) async {
    final old = _view;
    final controller = _c;
    _view = null;
    _c = null;
    _ready = null;
    if (timedOut &&
        defaultTargetPlatform == TargetPlatform.android &&
        controller != null &&
        !_rendererGone.isCompleted) {
      try {
        // Network timeouts leave JS responsive; only kill a blocked renderer.
        await controller
            .evaluateJavascript(source: 'void 0')
            .timeout(const Duration(milliseconds: 250));
      } on TimeoutException {
        try {
          final terminated = await _platform.invokeMethod<bool>(
            'terminateSourceRenderer',
            old?.id,
          );
          if (terminated == true) {
            await _rendererGone.future.timeout(const Duration(seconds: 2));
          } else {
            AppLog.record({'event': 'renderer_unavailable', 'site': _tag});
          }
        } catch (e) {
          AppLog.error(e, event: 'renderer_terminate', site: _tag);
        }
      } catch (_) {}
    }
    try {
      await old?.dispose();
    } catch (_) {}
  }

  Future<void> dispose() async {
    _disposed = true;
    _requests.cancel('runtime disposed');
    for (final token in _invocations.values) {
      token.cancel('runtime disposed');
    }
    await (_closing ??= _teardown());
    // Native persistence already accepted by the bridge must settle before rollback.
    await Future.wait(_bridgeCalls.toList());
  }

  void _registerHandlers(InAppWebViewController c) {
    Future<String> guard(Future<Object?> Function() body) async {
      final finished = Completer<void>();
      _bridgeCalls.add(finished.future);
      try {
        if (_disposed) throw SourceError('CONFIG', '站点运行环境已关闭');
        if (engine._suspended || engine._closing) {
          throw SourceError('CANCELLED', '应用正在关闭');
        }
        if (sandboxed) throw SourceError('CONFIG', '安装前预览时不允许访问网络与存储');
        return jsonEncode({'__value': await body()});
      } on SourceError catch (e) {
        return jsonEncode({
          '__error': {
            'code': e.code,
            'message': e.rawMessage,
            'params': {
              for (final p in e.params.entries) p.key: '${p.value ?? ''}',
            },
            'status': e.status,
            'url': e.url,
            'diagnostics': e.diagnostics,
          },
        });
      } catch (e) {
        return jsonEncode({
          '__error': {'code': 'NETWORK', 'message': e.toString()},
        });
      } finally {
        _bridgeCalls.remove(finished.future);
        finished.complete();
      }
    }

    c.addJavaScriptHandler(
      handlerName: 'park_request',
      callback: (args) => guard(() {
        final o = (args.first as Map).cast<String, dynamic>();
        final invocation = o['invocation'];
        final token = invocation == null ? _requests : _invocations[invocation];
        if (token == null) throw SourceError('NETWORK', '请求已取消');
        return HttpService.instance.sourceRequest(
          o,
          partition: key,
          domains: domains,
          cancelToken: token,
          confirmation: _confirmation,
        );
      }),
    );
    c.addJavaScriptHandler(
      handlerName: 'park_chat_request',
      callback: (args) => guard(() {
        final options = (args.first as Map).cast<String, dynamic>();
        final invocation = options['invocation'];
        final token = invocation == null ? _requests : _invocations[invocation];
        if (token == null) throw SourceError('CANCELLED', '请求已取消');
        return liveChatRequest(
          options,
          source: key,
          domains: chatDomains,
          cancelToken: token,
        );
      }),
    );
    c.addJavaScriptHandler(
      handlerName: 'park_crypto',
      callback: (args) => guard(() async {
        final m = (args.first as Map).cast<String, dynamic>();
        return CryptoBridge.call(
          m['op'].toString(),
          (m['args'] as Map? ?? {}).cast<String, dynamic>(),
        );
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
            await cookies.set(
              uri,
              (a['cookies'] as Map? ?? {}).map(
                (k, v) => MapEntry(k.toString(), v.toString()),
              ),
              partition: key,
              mirror: mirror,
            );
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
      callback: (args) => guard(() async {
        if (sandboxed || key.isEmpty) {
          throw SourceError('CONFIG', '预览时不能保存站点数据');
        }
        final m = (args.first as Map).cast<String, dynamic>();
        final persist = engine.onPersist;
        if (persist == null) throw SourceError('CONFIG', '站点数据存储不可用');
        await persist(
          key,
          (m['data'] as Map? ?? {}).cast<String, dynamic>(),
          flush: m['flush'] == true,
        );
        return null;
      }),
    );
    c.addJavaScriptHandler(
      handlerName: 'park_log',
      callback: (args) {
        final m = (args.first as Map).cast<String, dynamic>();
        // Plugins may log structured transport facts; free text is dropped.
        if (m['message'] case final Map fields) {
          AppLog.record({...fields, 'event': 'plugin', 'site': _tag});
        }
        return null;
      },
    );
  }

  /// Evaluates a source script and returns the key it registered with its static manifest.
  Future<ScriptInfo> loadScript(String code) async {
    await _bounded(start(), const Duration(seconds: 30), 'CONFIG', '站点启动超时');
    final res = await _bounded(
      _c!.callAsyncJavaScript(
        functionBody: '''
        Park.__pending = null;
        (0, eval)(code);
        const def = Park.__pending;
        return def ? { key: def.key, manifest: Park.manifest(def.key) } : null;
      ''',
        arguments: {'code': code},
      ),
      const Duration(seconds: 30),
      'CONFIG',
      '站点脚本运行超时',
    );
    if (res?.error != null) {
      throw SourceError(
        'CONFIG',
        '脚本加载失败：{error}',
        params: {'error': res!.error},
      );
    }
    final value = res?.value;
    if (value is! Map ||
        value['key'] is! String ||
        (value['key'] as String).isEmpty) {
      throw SourceError('CONFIG', '脚本没有调用 Park.register');
    }
    final info = ScriptInfo(
      value['key'] as String,
      (value['manifest'] as Map? ?? {}).cast<String, dynamic>(),
    );
    if (key.isNotEmpty && info.key != key) {
      throw SourceError(
        'CONFIG',
        '脚本注册的标识（{script}）与安装记录（{installed}）不一致',
        params: {'script': info.key, 'installed': key},
      );
    }
    if (!isSourceKey(info.key)) {
      throw SourceError('CONFIG', '站点标识的长度或格式无效');
    }
    domains = declaredDomains(info.manifest);
    chatDomains = liveChatDomains(info.manifest);
    _confirmation = AgeConfirmationConfig.fromNetwork(
      (info.manifest['network'] as Map? ?? const {}).cast<String, dynamic>(),
    );
    _code = code;
    return info;
  }

  Future<Map<String, dynamic>> setup(
    Map<String, dynamic> state, {
    bool waitForInit = false,
  }) async {
    final res = await _bounded(
      _c!.callAsyncJavaScript(
        functionBody: 'return await Park.setup(key, state, {waitForInit});',
        arguments: {'key': key, 'state': state, 'waitForInit': waitForInit},
      ),
      const Duration(seconds: 30),
      'CONFIG',
      '站点启动超时',
    );
    if (res?.error != null) {
      throw SourceError(
        'CONFIG',
        '站点启动失败：{error}',
        params: {'error': res!.error},
      );
    }
    final manifest = (res!.value as Map).cast<String, dynamic>();
    domains = declaredDomains(manifest);
    chatDomains = liveChatDomains(manifest);
    _confirmation = AgeConfirmationConfig.fromNetwork(
      (manifest['network'] as Map? ?? const {}).cast<String, dynamic>(),
    );
    _configured = true;
    return manifest;
  }

  Future<void> updateSettings(Map<String, dynamic> settings) async {
    await _bounded(start(), const Duration(seconds: 30), 'CONFIG', '站点启动超时');
    await _bounded(
      _c!.callAsyncJavaScript(
        functionBody: 'Park.updateSettings(key, settings);',
        arguments: {'key': key, 'settings': settings},
      ),
      const Duration(seconds: 30),
      'CONFIG',
      '站点脚本运行超时',
    );
  }

  /// Calls a source method. Throws [SourceError] with the source's error code on failure.
  Future<Object?> invoke(
    String method,
    List<Object?> args, {
    Duration timeout = const Duration(seconds: 90),
    CancelToken? cancelToken,
  }) async {
    // Visible in profile timelines, so call counts can be measured per screen.
    Timeline.instantSync('js.invoke', arguments: {'method': method});
    if (cancelToken?.cancelError case final error?) throw error;
    await _bounded(start(), const Duration(seconds: 30), 'CONFIG', '站点启动超时');
    if (cancelToken?.cancelError case final error?) throw error;
    final invocation = cancelToken == null ? null : '${++_nextInvocation}';
    final token = invocation == null ? null : CancelToken();
    final settled = Completer<void>();
    if (token != null) {
      _invocations[invocation!] = token;
      unawaited(
        Future.any<DioException?>([
          cancelToken!.whenCancel,
          settled.future.then<DioException?>((_) => null),
        ]).then((error) {
          if (error != null) token.cancel(error);
        }),
      );
    }
    try {
      final operation = _c!.callAsyncJavaScript(
        functionBody:
            'return await Park.invoke(key, method, args, invocation);',
        arguments: {
          'key': key,
          'method': method,
          'args': jsonDecode(jsonEncode(args)),
          'invocation': invocation,
        },
      );
      // Cancellation releases the caller immediately, but stuck JavaScript must
      // retain its own deadline until the native evaluation actually settles.
      final bounded = _bounded(operation, timeout, 'NETWORK', '请求超时');
      final res = await Future.any([
        bounded,
        if (token != null)
          token.whenCancel.then<CallAsyncJavaScriptResult?>(
            (error) => throw error,
          ),
      ]);
      if (res?.error != null) throw SourceError('PARSE', res!.error!);
      final value = res?.value;
      if (value is! Map) throw SourceError('PARSE', '站点返回了无效结果');
      if (value['ok'] == true) return value['value'];
      throw SourceError.fromJson(value['error']);
    } finally {
      settled.complete();
      if (invocation != null) {
        _invocations.remove(invocation);
        token!.cancel('invocation finished');
      }
    }
  }
}
