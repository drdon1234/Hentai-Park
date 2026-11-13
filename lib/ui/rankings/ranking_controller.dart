import 'package:flutter/foundation.dart';

import '../../core/models.dart';
import '../../core/tag_blocklist.dart';

typedef RankingLoader = Future<RankingPage> Function(
  int page,
  String? cursor,
  int offset,
);

/// 每个榜单与选项组合持有一个会话；刷新与销毁后的响应不能覆盖当前结果。
class RankingController extends ChangeNotifier {
  RankingController(this.load) {
    _filters.addListener(_applyFilters);
  }
  final _filters = TagBlocklist.changes;
  final RankingLoader load;
  final List<RankingEntry> items = [];
  bool showBlocked = false;
  void setVisibility(bool value) {
    showBlocked = value;
    _applyFilters();
  }

  final List<RankingEntry> _loaded = [];
  int get hidden => _loaded.length - items.length;
  void _applyFilters() {
    if (_disposed) return;
    final rules = TagBlocklist.current();
    items
      ..clear()
      ..addAll(
        _loaded.where(
          (item) =>
              showBlocked ||
              item.work == null ||
              rules.matchItem(item.work!) == null,
        ),
      );
    notifyListeners();
  }

  final Set<String> _seen = {};
  final Set<String> _cursors = {};
  int _emptyPages = 0;
  bool _restartRequired = false;
  bool get canAutoLoad => hasNext && _emptyPages < 3;
  Object? error;
  bool loading = false;
  bool hasNext = true;
  int _page = 0;
  int _offset = 0;
  int _generation = 0;
  String? _cursor;
  bool _disposed = false;

  Future<void> refresh() async {
    if (_disposed) return;
    _generation++;
    items.clear();
    _loaded.clear();
    _seen.clear();
    _cursors.clear();
    _emptyPages = 0;
    _restartRequired = false;
    _page = 0;
    _offset = 0;
    _cursor = null;
    error = null;
    loading = false;
    hasNext = true;
    await loadMore();
  }

  Future<void> loadMore() async {
    if (_disposed || loading || !hasNext) return;
    final generation = _generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await load(_page + 1, _cursor, _offset);
      if (_disposed || generation != _generation) return;
      final previousLength = items.length;
      for (final item in result.items) {
        if (_seen.add(item.uid)) {
          _loaded.add(item);
        }
      }
      _offset += result.items.length;
      _page = result.page > _page ? result.page : _page + 1;
      _cursor = result.cursor;
      hasNext = result.hasNext;
      _applyFilters();
      _emptyPages = items.length == previousLength ? _emptyPages + 1 : 0;
      if (hasNext && _cursor != null && !_cursors.add(_cursor!)) {
        hasNext = false;
        _restartRequired = true;
        throw SourceError('PARSE', '分页链接无效');
      }
    } catch (failure) {
      if (_disposed || generation != _generation) return;
      error = failure;
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> retry() => _restartRequired ? refresh() : loadMore();

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _filters.removeListener(_applyFilters);
    super.dispose();
  }
}
