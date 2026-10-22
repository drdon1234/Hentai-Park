import 'package:flutter/foundation.dart';

import '../../core/app_log.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../core/tag_blocklist.dart';
import '../../engine/home_cache.dart';

typedef ShortVideoLoader = Future<WorkPage> Function(int page, String? cursor);

/// 分页只保留作品元数据；播放器资源由独立的有界池管理。
class ShortVideoFeed extends ChangeNotifier {
  ShortVideoFeed(this._load, {WorkItem? initial, this.allowItem, this.source}) {
    _filters.addListener(_rulesChanged);
    if (initial != null) {
      _loaded.add(initial);
      if (_allows(initial)) items.add(initial);
      _seen.add(initial.uid);
    }
  }
  final ShortVideoLoader _load;
  final bool Function(WorkItem)? allowItem;
  final String? source;
  String? _availability;
  final _loaded = <WorkItem>[];
  final _explicit = <String>{};
  final _filters = AppSettings.instance.watch(AppSettings.filterKeys);
  bool _allows(WorkItem item) =>
      _explicit.contains(item.uid) ||
      (allowItem?.call(item) ??
          (TagBlocklist.current().matchItem(item) == null));
  void _rulesChanged() {
    if (_disposed) return;
    _explicit.clear();
    final current = index < items.length ? items[index].uid : null;
    items
      ..clear()
      ..addAll(_loaded.where(_allows));
    final kept = items.indexWhere((i) => i.uid == current);
    index = kept >= 0
        ? kept
        : index.clamp(0, items.isEmpty ? 0 : items.length - 1);
    if (!loading) _reportAvailability();
    notifyListeners();
  }

  bool get allFiltered => items.isEmpty && _loaded.isNotEmpty;

  void _reportAvailability() {
    if (source == null || error != null) return;
    final reason = items.isNotEmpty
        ? null
        : allFiltered
        ? 'CONTENT_FILTERED'
        : 'EMPTY_RESULT';
    final state = reason ?? 'success';
    // 正常加载不记日志；空列表只记状态变化，恢复后记一次成功。
    if (state == _availability || (_availability == null && reason == null)) {
      return;
    }
    _availability = state;
    AppLog.record({
      'event': 'content',
      'site': source,
      'action': 'shortVideo',
      if (reason != null) 'reason': reason else 'outcome': 'success',
    });
  }

  final List<WorkItem> items = [];
  final Set<String> _seen = {};
  final Set<String> _cursors = {};
  int index = 0, generation = 0, _page = 1;
  String? _cursor;
  bool loading = false, hasNext = true, _disposed = false;
  Object? error;
  bool _preview = false;
  bool get refreshingCached => _preview && loading;
  void Function(WorkPage) cachedReceiver() {
    final request = generation;
    return (cached) {
      if (_disposed ||
          request != generation ||
          _page != 1 ||
          items.isNotEmpty) {
        return;
      }
      _preview = true;
      _loaded.addAll(cached.items);
      items.addAll(cached.items.where(_allows));
      notifyListeners();
    };
  }

  void seed(WorkItem item, {bool allowBlocked = false}) {
    if (_disposed || !_seen.add(item.uid)) return;
    if (allowBlocked) _explicit.add(item.uid);
    _loaded.insert(0, item);
    if (_allows(item)) items.insert(0, item);
    notifyListeners();
  }

  void select(int value) {
    if (_disposed) return;
    index = value.clamp(0, items.length);
    notifyListeners();
    if (index >= items.length - 3 && error == null) loadMore();
  }

  Future<void> loadMore() async {
    if (_disposed || loading || !hasNext) return;
    final request = generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      // 一次最多跳过三页；图片帖很多时允许继续，重复游标另行校验。
      for (var skipped = 0; skipped < 3; skipped++) {
        final result = await _load(_page, _cursor);
        if (_disposed || request != generation) return;
        if (_preview) {
          final playing = index < items.length ? items[index] : null;
          _preview = false;
          _loaded.clear();
          items.clear();
          _seen.clear();
          index = 0;
          if (playing != null) {
            _loaded.add(playing);
            items.add(playing);
            _seen.add(playing.uid);
          }
        }
        final added = result.items
            .where((i) => i.id.isNotEmpty && _seen.add(i.uid))
            .toList();
        _loaded.addAll(added);
        final visible = added.where(_allows).toList();
        items.addAll(visible);
        if (result.staleCache) {
          hasNext = false;
          throw SourceError('NETWORK', '刷新失败，请重试');
        }
        if (result.hasNext &&
            result.cursor != null &&
            !_cursors.add(result.cursor!)) {
          hasNext = false;
          throw SourceError('PARSE', '短视频分页数据无效');
        }
        _cursor = result.cursor;
        _page++;
        hasNext = result.hasNext;
        if (visible.isNotEmpty || !hasNext) break;
      }
    } catch (e) {
      if (!_disposed && request == generation) {
        if (_preview && HomeCache.invalidatesContent(e)) {
          _preview = false;
          _loaded.clear();
          items.clear();
          _seen.clear();
          index = 0;
        }
        error = e;
      }
    } finally {
      if (!_disposed && request == generation) {
        loading = false;
        _reportAvailability();
        notifyListeners();
      }
    }
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    generation++;
    _preview = false;
    items.clear();
    _loaded.clear();
    _explicit.clear();
    _seen.clear();
    _cursors.clear();
    index = 0;
    _page = 1;
    _cursor = null;
    hasNext = true;
    loading = false;
    error = null;
    return loadMore();
  }

  @override
  void dispose() {
    _disposed = true;
    _filters.removeListener(_rulesChanged);
    generation++;
    super.dispose();
  }
}
