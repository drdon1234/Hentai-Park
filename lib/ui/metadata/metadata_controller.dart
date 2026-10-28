import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/work_metadata.dart';
import '../../engine/source_manager.dart';

/// 作品资料与磁链分开加载；切换查询、来源或关闭后丢弃旧请求。
class MetadataController extends ChangeNotifier {
  MetadataController(this.manager);
  final SourceManager manager;
  String source = '', query = '';
  List<MetadataCandidate> candidates = const [];
  WorkMetadata? detail;
  List<MetadataMagnet> magnets = const [];
  Object? error, magnetError;
  bool loading = false, magnetsLoading = false;
  CancelToken? _request, _magnetsRequest;
  bool _disposed = false;

  bool _current(CancelToken token) =>
      !_disposed && identical(token, _request) && !token.isCancelled;

  Future<void> search(String key, String keyword) async {
    reset();
    source = key;
    query = keyword.trim();
    if (query.isEmpty) return;
    final token = _request = CancelToken();
    loading = true;
    notifyListeners();
    try {
      final result = await manager.metadataSearch(
        key,
        query,
        cancelToken: token,
      );
      if (!_current(token)) return;
      candidates = result;
      String normalized(String value) =>
          value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      final exact = result
          .where((item) => normalized(item.code) == normalized(query))
          .toList();
      if (exact.length == 1) {
        await _load(exact.single.id, token);
      }
    } catch (e) {
      if (_current(token)) error = e;
    } finally {
      if (_current(token)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> select(MetadataCandidate candidate) async {
    _request?.cancel();
    _magnetsRequest?.cancel();
    final token = _request = CancelToken();
    detail = null;
    magnets = const [];
    error = magnetError = null;
    loading = true;
    magnetsLoading = false;
    notifyListeners();
    try {
      await _load(candidate.id, token);
    } catch (e) {
      if (_current(token)) error = e;
    } finally {
      if (_current(token)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _load(String id, CancelToken token) async {
    final result = await manager.metadataDetail(source, id, cancelToken: token);
    if (!_current(token)) return;
    detail = result;
    loading = false;
    notifyListeners();
    // 不阻塞资料展示，磁链失败只影响磁链区块。
    await loadMagnets();
  }

  Future<void> loadMagnets() async {
    final work = detail;
    if (_disposed || work == null) return;
    _magnetsRequest?.cancel();
    final token = _magnetsRequest = CancelToken();
    final key = source;
    magnetsLoading = true;
    magnetError = null;
    notifyListeners();
    bool current() =>
        !_disposed &&
        identical(token, _magnetsRequest) &&
        !token.isCancelled &&
        identical(detail, work);
    try {
      final result = await manager.metadataMagnets(
        key,
        work.id,
        cancelToken: token,
      );
      if (current()) magnets = result;
    } catch (e) {
      if (current()) magnetError = e;
    } finally {
      if (current()) {
        magnetsLoading = false;
        notifyListeners();
      }
    }
  }

  void reset() {
    _request?.cancel();
    _magnetsRequest?.cancel();
    _request = _magnetsRequest = null;
    candidates = const [];
    detail = null;
    magnets = const [];
    error = magnetError = null;
    loading = magnetsLoading = false;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    reset();
    super.dispose();
  }
}
