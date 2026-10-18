/// 缓存作品的展示与访问数据；账号凭据仍由独立的会话存储管理。
class HomeMetadata {
  static const detailFields = {
    'description',
    'size',
    'comments',
    'url',
    'chapters',
    'chaptersComplete',
    'singleChapterId',
    'thumbnails',
    'thumbnailsTotal',
    'authorSearch',
    'tags',
  };
  static Map<String, dynamic> detail(Map<String, dynamic> data) => {
    ...((serialize({
                      'items': [data],
                    })['items']
                    as List)
                .single
            as Map)
        .cast<String, dynamic>(),
    for (final field in detailFields)
      if (data.containsKey(field)) field: data[field],
    for (final field in ['related', 'series', 'variants'])
      if (data[field] is List)
        field: (serialize({'items': data[field]})['items'] as List),
    if (data['relatedSections'] is List)
      'relatedSections':
          (serialize({
                'items': [],
                'sections': data['relatedSections'],
              })['sections']
              as List),
  };
  static const fields = {
    'id',
    'title',
    'subtitle',
    'cover',
    'coverAspect',
    'pages',
    'rating',
    'likes',
    'views',
    'language',
    'category',
    'badge',
    'badgeColor',
    'duration',
    'uploaded',
    'tags',
    'workCode',
    'editions',
    'uploader',
    'authors',
    'author',
    'text',
    'date',
    'url',
    'locked',
    'presentation',
    'mediaKind',
    'contentDomain',
    'contentRating',
    'coverRating',
    'isNsfw',
  };

  // 帖子保留媒体地址与附件定位信息，刷新之前也能直接打开。
  static bool cacheable(Map<String, dynamic> data) =>
      data['items'] is List || data['sections'] is List;

  static Map<String, dynamic> serialize(Map<String, dynamic> data) {
    Map<String, dynamic> item(Map value) => {
      for (final field in fields)
        if (value[field] is String ||
            value[field] is num ||
            value[field] is bool)
          field: value[field],
      if (value['tags'] is List)
        'tags': (value['tags'] as List).whereType<String>().toList(),
      if (value['editions'] is List)
        'editions': (value['editions'] as List).whereType<String>().toList(),
      if (value['authors'] is List)
        'authors': (value['authors'] as List).whereType<String>().toList(),
      if (value['media'] is List)
        'media': (value['media'] as List).whereType<Map>().toList(),
    };
    return {
      for (final field in ['page', 'totalPages', 'hasNext', 'cursor', 'total'])
        if (data.containsKey(field)) field: data[field],
      'items': (data['items'] as List? ?? [])
          .whereType<Map>()
          .map(item)
          .toList(),
      if (data['sections'] is List)
        'sections': [
          for (final section in (data['sections'] as List).whereType<Map>())
            {
              'title': section['title'],
              'items': (section['items'] as List? ?? [])
                  .whereType<Map>()
                  .map(item)
                  .toList(),
            },
        ],
    };
  }
}
