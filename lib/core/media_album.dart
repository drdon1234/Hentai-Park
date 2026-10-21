import 'models.dart';

/// 相册要求稳定身份、完整媒体和明确的作品打开方式，错误数据不能静默丢弃。
WorkPage parseAlbumPage(Object? value, String source, int page) {
  Never invalid() => throw SourceError('PARSE', '相册数据无效');
  void resource(Object? value, int limit) {
    if (value is! Map ||
        value['size'] is! int ||
        value['size'] < 1 ||
        value['size'] > limit ||
        value['cacheKey'] is! String ||
        value['cacheKey'].isEmpty ||
        value['cacheKey'].length > 512) {
      invalid();
    }
  }

  if (value is! Map || value['items'] is! List || value['hasNext'] is! bool) {
    invalid();
  }
  final result = value;
  final cursor = result['cursor'];
  if ((cursor != null && (cursor is! String || cursor.isEmpty)) ||
      (result['hasNext'] == true && cursor == null)) {
    invalid();
  }
  final items = <Map<String, dynamic>>[];
  for (final raw in result['items'] as List) {
    if (raw is! Map ||
        raw['id'] is! String ||
        raw['id'].isEmpty ||
        !const ['post', 'work'].contains(raw['presentation']) ||
        raw['media'] is! List) {
      invalid();
    }
    final item = raw.cast<String, dynamic>();
    final date = item['date'];
    if (date != null &&
        (date is! String ||
            (date.isNotEmpty && DateTime.tryParse(date) == null))) {
      invalid();
    }
    final ids = <String>{};
    for (final media in item['media'] as List) {
      if (media is! Map ||
          media['id'] is! String ||
          (media['id'] as String).isEmpty ||
          !ids.add(media['id'] as String) ||
          !const ['image', 'video'].contains(media['type'])) {
        invalid();
      }
      final url = media['url'];
      if (!(url is String && url.isNotEmpty) && media['resource'] is! Map) {
        invalid();
      }
      if (media['resource'] != null) resource(media['resource'], 536870912);
      if (media['preview'] != null && media['preview'] is! String) invalid();
      if (media['previewResource'] != null) {
        resource(media['previewResource'], 2097152);
      }
      if (media['order'] != null &&
          (media['order'] is! num || !(media['order'] as num).isFinite)) {
        invalid();
      }
    }
    items.add(item);
  }
  return WorkPage.fromJson({
    'items': items,
    'cursor': cursor,
    'hasNext': result['hasNext'],
    'page': page,
  }, source);
}
