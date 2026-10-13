import 'package:flutter/foundation.dart';

import 'dart:convert';

import '../../core/models.dart';
import '../../core/settings.dart';
import '../../core/tag_blocklist.dart';

typedef ShortVideoLoader = Future<WorkPage> Function(int page, String? cursor);

/// 分页只保留作品元数据；播放器资源由独立的有界池管理。
class ShortVideoFeed extends ChangeNotifier {
  ShortVideoFeed(this._load, {WorkItem? initial, this.allowItem}) {
    _rules = _ruleSignature;
    AppSettings.instance.addListener(_rulesChanged);
    if (initial != null) {
      _loaded.add(initial);
      if (_allows(initial)) items.add(initial);
      _seen.add(initial.uid);
    }
  }
  final ShortVideoLoader _load;
  final bool Function(WorkItem)? allowItem;
  final _loaded = <WorkItem>[];
  final _explicit = <String>{};
  late String _rules;
  String get _ruleSignature => jsonEncode([
    AppSettings.instance.blockedTags,
    AppSettings.instance.blockPresetState,
  ]);
  bool _allows(WorkItem item) =>
      _explicit.contains(item.uid) ||
      (allowItem?.call(item) ??
          (TagBlocklist.current().matchItem(item) == null));
  void _rulesChanged() {
    final rules = _ruleSignature;
    if (_disposed || rules == _rules) return;
    _rules = rules;
    _explicit.clear();
    final current = index < items.length ? items[index].uid : null;
    items
      ..clear()
      ..addAll(_loaded.where(_allows));
    final kept = items.indexWhere((i) => i.uid == current);
    index = kept >= 0
        ? kept
        : index.clamp(0, items.isEmpty ? 0 : items.length - 1);
    notifyListeners();
  }

  final List<WorkItem> items = [];
  final Set<String> _seen = {};
  int index = 0, generation = 0, _page = 1;
  String? _cursor;
  bool loading = false, hasNext = true, _disposed = false;
  Object? error;

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
      // 空页或整页重复仍可向后，但不能无限请求坏游标。
      for (var skipped = 0; skipped < 3; skipped++) {
        final result = await _load(_page, _cursor);
        if (_disposed || request != generation) return;
        final added = result.items
            .where((i) => i.id.isNotEmpty && _seen.add(i.uid))
            .toList();
        _loaded.addAll(added);
        final visible = added.where(_allows).toList();
        items.addAll(visible);
        if (result.hasNext &&
            result.cursor != null &&
            result.cursor == _cursor) {
          throw SourceError('PARSE', '短视频分页数据无效');
        }
        _cursor = result.cursor;
        _page++;
        hasNext = result.hasNext;
        if (visible.isNotEmpty || !hasNext) break;
        if (skipped == 2 && added.isEmpty) {
          throw SourceError('PARSE', '短视频分页数据无效');
        }
      }
    } catch (e) {
      if (!_disposed && request == generation) error = e;
    } finally {
      if (!_disposed && request == generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    generation++;
    items.clear();
    _loaded.clear();
    _explicit.clear();
    _seen.clear();
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
    AppSettings.instance.removeListener(_rulesChanged);
    generation++;
    super.dispose();
  }
}
