import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/models.dart';

typedef AlbumLoader = Future<WorkPage> Function(
  int page,
  String? cursor,
  CancelToken token,
);

class AlbumController extends ChangeNotifier {
  AlbumController({required this.source, required this.loader});
  final String source;
  AlbumLoader loader;
  final items = <WorkItem>[];
  final _byId = <String, int>{};
  final _cursors = <String>{};
  CancelToken? _request;
  String? cursor;
  bool hasNext = true, loading = false;
  Object? error;
  int page = 0;
  bool _disposed = false;
  int _generation = 0;

  Future<void> loadMore() async {
    if (_disposed || loading || !hasNext) return;
    loading = true;
    error = null;
    notifyListeners();
    final token = _request = CancelToken();
    final generation = _generation;
    try {
      final result = await loader(page + 1, cursor, token);
      if (_disposed || token.isCancelled || generation != _generation) return;
      for (final item in result.items) {
        final oldIndex = _byId[item.id];
        if (oldIndex == null) {
          final normalized = WorkItem({
            ...item.json,
            'media': _dedupeMedia(item.json['media'] as List? ?? const []),
          }, source);
          _byId[item.id] = items.length;
          items.add(normalized);
        } else {
          final old = items[oldIndex];
          final media = [
            ...?(old.json['media'] as List?),
            ...?(item.json['media'] as List?),
          ];
          items[oldIndex] = WorkItem({
            ...old.json,
            for (final field in item.json.entries)
              if (field.value != null &&
                  (field.value != '' || !old.json.containsKey(field.key)))
                field.key: field.value,
            'media': _dedupeMedia(media),
          }, source);
        }
      }
      if (result.hasNext &&
          (result.cursor == null || !_cursors.add(result.cursor!))) {
        hasNext = false;
        error = SourceError('PARSE', '分页链接无效');
      } else {
        page = result.page > page ? result.page : page + 1;
        cursor = result.cursor;
        hasNext = result.hasNext;
      }
    } catch (e) {
      if (!_disposed && !token.isCancelled && generation == _generation) {
        error = e;
      }
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() async {
    _generation++;
    _request?.cancel();
    loading = false;
    hasNext = true;
    error = null;
    cursor = null;
    page = 0;
    items.clear();
    _byId.clear();
    _cursors.clear();
    await loadMore();
  }

  static List<Map<String, dynamic>> _dedupeMedia(Iterable media) {
    final byId = <String, Map<String, dynamic>>{};
    for (final value in media) {
      if (value is! Map) continue;
      final item = value.cast<String, dynamic>();
      final key = '${item['id']}';
      byId[key] = item;
    }
    final out = byId.values.toList();
    if (out.every((m) => m['order'] is num)) {
      out.sort((a, b) => (a['order'] as num).compareTo(b['order'] as num));
    }
    return out;
  }

  @override
  void dispose() {
    _disposed = true;
    _request?.cancel();
    super.dispose();
  }
}
