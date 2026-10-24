import '../../core/models.dart';

/// 从列表点开短视频时沿用列表的顺序与分页，而不是重新请求站点推荐。
class ShortVideoSequence {
  const ShortVideoSequence({
    required this.items,
    required this.load,
    this.page = 0,
    this.cursor,
    this.hasNext = true,
  });
  final List<WorkItem> items;
  final Future<WorkPage> Function(int page, String? cursor) load;

  /// 列表已加载到的页号与游标，下一次从其后继续。
  final int page;
  final String? cursor;
  final bool hasNext;
}
