import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/reverse_search.dart';
import '../../engine/browser_image_search.dart';

typedef ReverseSearchLoader = Future<List<ReverseSearchMatch>> Function(
  String source,
  CancelToken token,
  BrowserImageSearch browserSearch,
);

class ReverseSearchSiteResult {
  List<ReverseSearchMatch> matches = const [];
  Object? error;
  bool loading = true;
  bool cancelled = false;
}

/// 一个网页会话完成后才展示下一个，保持上传、验证和 Cookie 分区对应。
class ReverseSearchBrowserSession {
  ReverseSearchBrowserSession(this.source, this.request, this.token);
  final String source;
  final BrowserImageSearchRequest request;
  final CancelToken token;
  final _result = Completer<BrowserImageSearchResult?>();
  bool verification = false;
}

/// 请求不依赖结果列表的构建；每轮独立取消，站点失败互不影响。
class ReverseSearchController extends ChangeNotifier {
  final results = <String, ReverseSearchSiteResult>{};
  _ReverseSearchRun? _run;
  ReverseSearchLoader? _loader;
  bool _disposed = false;

  bool get busy => results.values.any((result) => result.loading);
  int get completed => results.values
      .where((result) => !result.loading && !result.cancelled)
      .length;
  bool get cancelled => results.values.any((result) => result.cancelled);
  List<String> get successfulSources => [
    for (final entry in results.entries)
      if (entry.value.matches.isNotEmpty) entry.key,
  ];
  List<String> get failedSources => [
    for (final entry in results.entries)
      if (entry.value.error != null) entry.key,
  ];
  ReverseSearchBrowserSession? get browser => _run?.browsers.firstOrNull;

  void start(Iterable<String> sources, ReverseSearchLoader loader) {
    if (_disposed) return;
    _cancel();
    results.clear();
    _loader = loader;
    final run = _run = _ReverseSearchRun(sources.toSet(), loader);
    for (final source in run.queue) {
      results[source] = ReverseSearchSiteResult();
    }
    notifyListeners();
    _pump(run);
  }

  void retry(String source) {
    final loader = _loader;
    if (_disposed || loader == null || results[source]?.error == null) return;
    final run = _run ??= _ReverseSearchRun(const [], loader);
    results[source] = ReverseSearchSiteResult();
    run.queue.add(source);
    notifyListeners();
    _pump(run);
  }

  /// 用户停止搜索时保留已经返回的候选，后续回调不能再改变结果。
  void cancel() {
    if (_disposed) return;
    _cancel();
    notifyListeners();
  }

  void reset() {
    if (_disposed) return;
    _cancel();
    results.clear();
    _loader = null;
    notifyListeners();
  }

  void _cancel() {
    final run = _run;
    _run = null;
    run?.token.cancel();
    for (final session in run?.browsers ?? <ReverseSearchBrowserSession>[]) {
      session._result.complete(null);
    }
    for (final result in results.values) {
      if (result.loading) result.cancelled = true;
      result.loading = false;
    }
  }

  bool _current(_ReverseSearchRun run) =>
      !_disposed && identical(_run, run) && !run.token.isCancelled;

  void _pump(_ReverseSearchRun run) {
    while (_current(run) && run.active < 4 && run.queue.isNotEmpty) {
      final source = run.queue.removeFirst();
      run.active++;
      unawaited(_load(run, source));
    }
  }

  Future<void> _load(_ReverseSearchRun run, String source) async {
    try {
      final matches = await run.loader(
        source,
        run.token,
        (request) => _requestBrowser(run, source, request),
      );
      if (_current(run)) {
        results[source]!.matches = List.unmodifiable(matches);
      }
    } catch (error) {
      if (_current(run)) results[source]!.error = error;
    } finally {
      run.active--;
      if (_current(run)) {
        results[source]!.loading = false;
        notifyListeners();
        _pump(run);
      }
    }
  }

  Future<BrowserImageSearchResult?> _requestBrowser(
    _ReverseSearchRun run,
    String source,
    BrowserImageSearchRequest request,
  ) {
    if (!_current(run)) return Future.value();
    final session = ReverseSearchBrowserSession(source, request, run.token);
    run.browsers.add(session);
    notifyListeners();
    return session._result.future;
  }

  void setVerification(ReverseSearchBrowserSession session, bool value) {
    if (!identical(browser, session) || session.verification == value) return;
    session.verification = value;
    notifyListeners();
  }

  void finishBrowser(
    ReverseSearchBrowserSession session,
    BrowserImageSearchResult? result, {
    Object? error,
  }) {
    if (!identical(browser, session)) return;
    _run!.browsers.removeFirst();
    if (error != null) {
      session._result.completeError(error);
    } else {
      session._result.complete(result);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel();
    super.dispose();
  }
}

class _ReverseSearchRun {
  _ReverseSearchRun(Iterable<String> sources, this.loader)
    : queue = Queue.of(sources);
  final ReverseSearchLoader loader;
  final Queue<String> queue;
  final browsers = Queue<ReverseSearchBrowserSession>();
  final token = CancelToken();
  int active = 0;
}
