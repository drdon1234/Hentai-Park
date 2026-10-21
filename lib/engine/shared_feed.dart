import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/models.dart';
import 'home_cache.dart';

typedef SharedFeedLoader = Future<WorkPage> Function(
  int page,
  String? cursor, {
  required bool refresh,
  required CancelToken cancelToken,
  void Function(WorkPage)? onCached,
});

/// 一个推荐入口的分页会话。请求属于会话，订阅它的视图共享内容和分页进度。
class SharedFeedSession extends ChangeNotifier {
  SharedFeedSession(this._load);

  SharedFeedLoader _load;
  final _items = <WorkItem>[];
  final _seen = <String>{};
  final _cursors = <String>{};
  List<WorkItem> get items => List.unmodifiable(_items);
  int _page = 1;
  String? _cursor;
  int revision = 0;
  bool initialized = false;
  bool hasNext = true;
  bool restartRequired = false;
  bool _refresh = false;
  bool _preview = false;
  bool _disposed = false;
  Object? error;
  Future<void>? _pending;
  CancelToken? _request;
  bool get loading => _pending != null;

  Iterable<WorkItem> _flatten(WorkPage page) sync* {
    for (final section in page.sections ?? <WorkSection>[]) {
      yield* section.items;
    }
    yield* page.items;
  }

  void _replace(WorkPage page) {
    _items.clear();
    _seen.clear();
    _append(page);
  }

  int _append(WorkPage page) {
    final before = _items.length;
    _items.addAll(
      _flatten(page).where((item) => item.id.isNotEmpty && _seen.add(item.uid)),
    );
    return _items.length - before;
  }

  Future<void> loadMore() {
    if (_disposed || !hasNext || restartRequired) return Future.value();
    if (_pending case final pending?) return pending;
    final done = Completer<void>();
    final generation = revision;
    final request = _request = CancelToken();
    _pending = done.future;
    error = null;
    notifyListeners();
    unawaited(
      _run(generation, request).whenComplete(() {
        if (!_disposed && generation == revision) {
          _pending = null;
          _request = null;
          notifyListeners();
        }
        done.complete();
      }),
    );
    return done.future;
  }

  Future<void> _run(int generation, CancelToken request) async {
    try {
      // 空页、整页重复都可继续，但一次加载不能无限请求。
      for (var skipped = 0; skipped < 3; skipped++) {
        final result = await _load(
          _page,
          _cursor,
          refresh: _refresh,
          cancelToken: request,
          onCached: _page != 1 || _refresh
              ? null
              : (cached) {
                  if (_disposed || generation != revision || initialized) {
                    return;
                  }
                  _preview = true;
                  _replace(cached);
                  notifyListeners();
                },
        );
        if (_disposed || generation != revision) return;
        if (_preview) {
          _preview = false;
          _items.clear();
          _seen.clear();
        }
        initialized = true;
        final added = _append(result);
        if (result.staleCache) {
          // 磁盘中的会话游标可能属于已经销毁的 JS 实例，不能继续分页。
          restartRequired = true;
          throw SourceError('NETWORK', '刷新失败，请重试');
        }
        if (result.hasNext &&
            result.cursor != null &&
            !_cursors.add(result.cursor!)) {
          restartRequired = true;
          throw SourceError('PARSE', '分页链接无效');
        }
        _cursor = result.cursor;
        _page++;
        _refresh = false;
        hasNext = result.hasNext;
        if (added > 0 || !hasNext) return;
      }
      restartRequired = true;
      throw SourceError('PARSE', '分页链接无效');
    } catch (failure) {
      if (_disposed || generation != revision) return;
      if (HomeCache.invalidatesContent(failure)) {
        _items.clear();
        _seen.clear();
        initialized = false;
        restartRequired = true;
      }
      if (_page > 1 && failure is SourceError && failure.code == 'CONFIG') {
        restartRequired = true;
      }
      error = failure;
    }
  }

  Future<void> retry() {
    if (restartRequired) reset();
    return loadMore();
  }

  /// 只使会话失效；可见视图决定何时发起新的请求。
  void reset({SharedFeedLoader? loader}) {
    if (_disposed) return;
    revision++;
    _request?.cancel();
    _request = null;
    _pending = null;
    if (loader != null) _load = loader;
    _items.clear();
    _seen.clear();
    _cursors.clear();
    _cursor = null;
    _page = 1;
    initialized = false;
    hasNext = true;
    restartRequired = false;
    _preview = false;
    _refresh = true;
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    revision++;
    _request?.cancel();
    super.dispose();
  }
}
