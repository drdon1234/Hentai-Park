import 'package:dio/dio.dart';

/// 窗口内只保留一份任务；反向阅读和跳页会撤销离开窗口的使用者。
class PagePreloader {
  PagePreloader(this.load);
  final Future<void> Function(int, CancelToken) load;
  final _requests = <int, CancelToken>{};
  int? _page;
  int _direction = 1;

  void update({required int page, required int count, required int window}) {
    if (_page != null && page != _page) _direction = page > _page! ? 1 : -1;
    _page = page;
    final wanted = <int>{
      if (window > 0 && _requests.containsKey(page)) page,
      for (var offset = 1; offset <= window; offset++)
        if (page + offset * _direction >= 0 &&
            page + offset * _direction < count)
          page + offset * _direction,
    };
    for (final index in _requests.keys.toList()) {
      if (!wanted.contains(index)) _requests.remove(index)!.cancel();
    }
    for (final index in wanted) {
      if (_requests.containsKey(index)) continue;
      final token = _requests[index] = CancelToken();
      // 预加载失败交由可见页面的正常重试入口处理。
      load(index, token).ignore();
    }
  }

  void clear() {
    for (final token in _requests.values) {
      token.cancel();
    }
    _requests.clear();
    _page = null;
    _direction = 1;
  }
}
