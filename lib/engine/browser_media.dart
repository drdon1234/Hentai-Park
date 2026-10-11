import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/models.dart';
import 'domains.dart';
import 'http_service.dart';

/// Separate from source HTTP: media requests never carry cross-site credentials.
class BrowserMediaPolicy {
  BrowserMediaPolicy._(this.origin, this.domains);
  final String origin;
  final List<String> domains;

  factory BrowserMediaPolicy.fromManifest(SourceManifest manifest) {
    final media = manifest.media;
    final page = Uri.tryParse('${media['origin'] ?? ''}');
    final domains = (media['domains'] as List? ?? const [])
        .map((d) => '$d'.toLowerCase())
        .toList();
    if (media['mode'] != 'browser' ||
        page == null ||
        page.scheme != 'https' ||
        page.port != 443 ||
        page.userInfo.isNotEmpty ||
        !hostInDomains(page.host, declaredDomains(manifest.json)) ||
        domains.isEmpty ||
        domains.any((d) => !_publicHost(d))) {
      throw SourceError('CONFIG', '源没有声明有效的浏览器媒体权限');
    }
    return BrowserMediaPolicy._(page.origin, List.unmodifiable(domains));
  }

  static bool _publicHost(String host) =>
      RegExp(r'^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\.[a-z]{2,}$').hasMatch(host) &&
      host != 'localhost' &&
      !host.endsWith('.localhost') &&
      !host.endsWith('.local');

  void validate(Uri url) {
    if (url.scheme != 'https' ||
        url.port != 443 ||
        url.userInfo.isNotEmpty ||
        !_publicHost(url.host) ||
        !hostInDomains(url.host, domains) ||
        url.fragment.isNotEmpty) {
      throw SourceError('CONFIG', '媒体地址不在源声明的 HTTPS 域名内');
    }
  }
}

abstract interface class MediaTransport {
  void validate(Uri url);
  Future<Uint8List> fetch(
    Uri url, {
    required int maxBytes,
    CancelToken? cancelToken,
  });
  Future<void> close();
}

/// One hidden page per playback/download. Closing it aborts and releases all requests.
class BrowserMedia implements MediaTransport {
  BrowserMedia(this.policy);
  final BrowserMediaPolicy policy;
  final _closed = Completer<void>();
  final _closingEvents = StreamController<void>.broadcast(sync: true);
  HeadlessInAppWebView? _view;
  InAppWebViewController? _controller;
  Future<void>? _ready;
  Future<void>? _starting;
  Future<void>? _viewDisposal;
  Future<void> _queue = Future.value();
  Future<void>? _closing;
  int _nextId = 0;

  @override
  void validate(Uri url) => policy.validate(url);

  Future<T> _untilClosed<T>(Future<T> work, CancelToken? token) async {
    final result = Completer<T>();
    void fail(Object error) {
      if (!result.isCompleted) result.completeError(error);
    }

    final closing = _closingEvents.stream.listen(
      (_) => fail(SourceError('CANCELLED', '媒体会话已关闭')),
    );
    final cancellation = token?.whenCancel.asStream().listen(fail);
    work.then(
      (value) {
        if (!result.isCompleted) result.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      },
    );
    if (_closed.isCompleted) fail(SourceError('CANCELLED', '媒体会话已关闭'));
    if (token?.cancelError case final error?) fail(error);
    try {
      return await result.future;
    } finally {
      await closing.cancel();
      await cancellation?.cancel();
    }
  }

  void _check(CancelToken? token) {
    if (token?.cancelError case final error?) throw error;
    if (_closed.isCompleted) throw SourceError('CANCELLED', '媒体会话已关闭');
  }

  Future<void> _start() async {
    _check(null);
    final ready = Completer<void>();
    void finish([Object? error]) {
      if (!ready.isCompleted) {
        if (error == null) {
          ready.complete();
        } else {
          ready.completeError(error);
        }
      }
    }

    final timeout = Timer(
      const Duration(seconds: 25),
      () => finish(SourceError('CLOUDFLARE', '浏览器验证未通过', url: policy.origin)),
    );
    final view = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('${policy.origin}/robots.txt')),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent: HttpService.instance.userAgent,
        blockNetworkImage: true,
        mediaPlaybackRequiresUserGesture: true,
        useShouldOverrideUrlLoading: true,
      ),
      onWebViewCreated: (controller) => _controller = controller,
      onRenderProcessGone: (controller, detail) {
        finish(SourceError('NETWORK', '浏览器请求失败'));
        _controller = null;
        unawaited(close());
      },
      onLoadStop: (controller, url) async {
        if (url == null || Uri.tryParse('$url')?.origin != policy.origin) {
          finish(SourceError('CONFIG', '媒体浏览器离开了源声明的地址'));
          return;
        }
        try {
          final title = await controller.getTitle() ?? '';
          final html = await controller.evaluateJavascript(
            source: 'document.documentElement.outerHTML.slice(0,3000)',
          );
          if (!title.contains('Just a moment') &&
              !title.contains('Attention Required') &&
              !'$html'.contains('challenge-platform')) {
            finish();
          }
        } catch (e) {
          finish(e);
        }
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame == true) {
          finish(SourceError('NETWORK', error.description));
        }
      },
      shouldOverrideUrlLoading: (controller, action) =>
          action.isForMainFrame == false ||
              Uri.tryParse('${action.request.url}')?.origin == policy.origin
          ? NavigationActionPolicy.ALLOW
          : NavigationActionPolicy.CANCEL,
    );
    _view = view;
    _viewDisposal = null;
    // Subscribe before run: onLoadStop may finish synchronously in a test host.
    final waiting = _untilClosed(ready.future, null);
    // close may settle this while the platform is still creating its view.
    waiting.ignore();
    final starting = _starting = view.run();
    try {
      await starting;
      await waiting;
    } catch (error) {
      finish(error);
      try {
        await _disposeView(view, starting);
      } finally {
        if (identical(_view, view)) {
          _view = null;
          _controller = null;
          _ready = null;
        }
      }
      rethrow;
    } finally {
      timeout.cancel();
      if (identical(_starting, starting)) _starting = null;
    }
  }

  Future<void> _disposeView(
    HeadlessInAppWebView view,
    Future<void>? starting,
  ) => _viewDisposal ??= () async {
    try {
      await starting;
    } catch (_) {}
    await view.dispose();
  }();

  @override
  Future<Uint8List> fetch(
    Uri url, {
    required int maxBytes,
    CancelToken? cancelToken,
  }) {
    validate(url);
    if (maxBytes < 1 || maxBytes > 32 * 1024 * 1024) {
      throw ArgumentError.value(maxBytes, 'maxBytes');
    }
    _check(cancelToken);
    final operation = _queue.then((_) async {
      _check(cancelToken);
      await _untilClosed(_ready ??= _start(), cancelToken);
      _check(cancelToken);
      final id = '${++_nextId}';
      var finished = false;
      final cancellation = cancelToken?.whenCancel.asStream().listen((
        error,
      ) async {
        if (!finished && !_closed.isCompleted) {
          try {
            await _controller?.evaluateJavascript(
              source:
                  '''const jobs = globalThis.__parkMedia ||= new Map();
const id = ${jsonEncode(id)};
if (jobs.has(id)) jobs.get(id)?.abort(); else jobs.set(id, null);''',
            );
          } catch (_) {}
        }
      });
      try {
        final result = await _untilClosed(
          _controller!
              .callAsyncJavaScript(
                functionBody: '''
            const jobs = globalThis.__parkMedia ||= new Map();
            if (jobs.has(id)) { jobs.delete(id); return {error: 'cancelled'}; }
            const controller = new AbortController();
            jobs.set(id, controller);
            const timer = setTimeout(() => controller.abort(), 40000);
            try {
              const response = await fetch(url, {credentials: 'omit', mode: 'cors', redirect: 'error', signal: controller.signal});
              if (response.status !== 200) return {status: response.status};
              const size = Number(response.headers.get('content-length'));
              if (size > limit) throw new Error('媒体资源过大');
              if (!response.body) throw new Error('媒体响应为空');
              const reader = response.body.getReader();
              const chunks = [];
              let length = 0;
              while (true) {
                const {done, value} = await reader.read();
                if (done) break;
                length += value.length;
                if (length > limit) { await reader.cancel(); throw new Error('媒体资源过大'); }
                chunks.push(value);
              }
              let binary = '';
              for (const chunk of chunks) {
                for (let i = 0; i < chunk.length; i += 8192) binary += String.fromCharCode(...chunk.subarray(i, i + 8192));
              }
              return {status: 200, body: btoa(binary), url: response.url};
            } catch (error) { return {error: String(error && error.message || error)}; }
            finally { clearTimeout(timer); controller.abort(); jobs.delete(id); }
          ''',
                arguments: {'id': id, 'url': url.toString(), 'limit': maxBytes},
              )
              .timeout(const Duration(seconds: 45)),
          cancelToken,
        );
        _check(cancelToken);
        if (result?.error != null) throw SourceError('NETWORK', result!.error!);
        final value = result?.value;
        if (value is! Map ||
            value['status'] != 200 ||
            value['body'] is! String) {
          throw SourceError(
            'NETWORK',
            '媒体请求失败：${value is Map ? value['error'] ?? value['status'] : '空响应'}',
          );
        }
        final finalUrl = Uri.tryParse('${value['url']}');
        if (finalUrl == null) throw SourceError('NETWORK', '媒体响应地址缺失');
        validate(finalUrl);
        if (finalUrl != url) throw SourceError('CONFIG', '媒体请求不允许重定向');
        final encoded = value['body'] as String;
        if (encoded.length > ((maxBytes + 2) ~/ 3) * 4) {
          throw SourceError('NETWORK', '媒体资源过大');
        }
        final bytes = base64Decode(encoded);
        if (bytes.isEmpty || bytes.length > maxBytes) {
          throw SourceError('NETWORK', '媒体资源为空或过大');
        }
        return bytes;
      } finally {
        finished = true;
        await cancellation?.cancel();
      }
    });
    _queue = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return _untilClosed(operation, cancelToken);
  }

  @override
  Future<void> close() => _closing ??= () async {
    if (!_closed.isCompleted) {
      _closed.complete();
      _closingEvents.add(null);
    }
    final controller = _controller;
    final view = _view;
    final starting = _starting;
    _controller = null;
    try {
      await controller?.evaluateJavascript(
        source: 'globalThis.__parkMedia?.forEach(controller => controller?.abort())',
      );
    } catch (_) {}
    try {
      if (view != null) await _disposeView(view, starting);
    } finally {
      _view = null;
      await _queue;
      await _closingEvents.close();
    }
  }();
}
