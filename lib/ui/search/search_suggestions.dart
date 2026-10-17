import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 联想失败不打断搜索；取消与序号共同防止旧输入覆盖新输入。
class SearchSuggestions extends ChangeNotifier {
  SearchSuggestions(this.load);
  final Future<List<Map<String, String>>> Function(String, CancelToken) load;
  List<Map<String, String>> items = const [];
  Timer? _timer;
  CancelToken? _request;
  int _generation = 0;
  bool _disposed = false;

  void update(String text) {
    clear();
    final keyword = text.trim();
    if (keyword.isEmpty) return;
    final generation = _generation;
    _timer = Timer(const Duration(milliseconds: 300), () async {
      final token = CancelToken();
      _request = token;
      try {
        final result = await load(keyword, token);
        if (!_disposed && generation == _generation && !token.isCancelled) {
          items = result;
          notifyListeners();
        }
      } catch (_) {
        /* 可选提示不可阻止正常搜索。 */
      }
    });
  }

  void clear() {
    _generation++;
    _timer?.cancel();
    _request?.cancel();
    items = const [];
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    clear();
    super.dispose();
  }
}
