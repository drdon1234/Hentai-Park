import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/comments.dart';

typedef CommentsLoader = Future<CommentPage> Function(
  int page,
  String? cursor,
  String sort,
  CancelToken token,
);

class CommentsController extends ChangeNotifier {
  CommentsController(this.loader, {List<SourceComment> initial = const []}) {
    items.addAll(initial);
  }
  final CommentsLoader loader;
  final List<SourceComment> items = [];

  /// 有些站点将回复混在时间流里；父楼后到达时也能恢复关系。
  List<SourceComment> get threads {
    final byId = {for (final item in items) item.id: item};
    final children = <String, List<SourceComment>>{};
    final roots = <SourceComment>[];
    for (final item in items) {
      var parent = item.parentId;
      final chain = <String>{item.id};
      var ancestor = parent;
      while (ancestor != null && byId.containsKey(ancestor)) {
        if (!chain.add(ancestor) || chain.length > 5) {
          parent = null;
          break;
        }
        ancestor = byId[ancestor]!.parentId;
      }
      if (parent == null || !byId.containsKey(parent)) {
        roots.add(item);
      } else {
        (children[parent] ??= []).add(item);
      }
    }
    SourceComment nest(SourceComment item, Set<String> path) {
      final seen = <String>{};
      final replies = <SourceComment>[];
      for (final reply in [...item.replies, ...?children[item.id]]) {
        if (path.contains(reply.id) || !seen.add(reply.id)) continue;
        replies.add(nest(reply, {...path, reply.id}));
      }
      return item.withReplies(replies);
    }

    return [
      for (final item in roots) nest(item, {item.id}),
    ];
  }

  List<({String value, String label})> sorts = [];
  String sort = 'default';
  bool loading = false, hasNext = true;
  int? total;
  Object? error;
  int _page = 0, _generation = 0;
  String? _cursor;
  final _cursors = <String>{};
  CancelToken? _token;
  bool _disposed = false;

  Future<void> refresh({String? order}) async {
    _generation++;
    _token?.cancel();
    sort = order ?? sort;
    _page = 0;
    _cursor = null;
    _cursors.clear();
    items.clear();
    total = null;
    hasNext = true;
    loading = false;
    await load();
  }

  Future<void> load() async {
    if (_disposed || loading || !hasNext) return;
    final generation = _generation, token = CancelToken();
    _token = token;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await loader(_page + 1, _cursor, sort, token);
      if (_disposed || generation != _generation || token.isCancelled) return;
      if (result.reset) {
        items.clear();
        _cursors.clear();
        _cursor = null;
      }
      final seen = items.map((e) => e.id).toSet();
      final fresh = result.items.where((e) => seen.add(e.id)).toList();
      items.addAll(fresh);
      final firstPage = _page == 0;
      _page = result.page ?? (result.reset ? 1 : _page + 1);
      total = result.total ?? total;
      if (result.sorts.isNotEmpty) sorts = result.sorts;
      final repeated = result.cursor != null && !_cursors.add(result.cursor!);
      _cursor = result.cursor;
      hasNext =
          result.hasNext &&
          (fresh.isNotEmpty ||
              firstPage && result.items.isNotEmpty ||
              result.items.isEmpty && result.cursor != null) &&
          !repeated;
    } catch (e) {
      if (_disposed || generation != _generation || token.isCancelled) return;
      error = e;
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _token?.cancel();
    super.dispose();
  }
}
