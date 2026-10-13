/// 主页实时协议与磁盘缓存分离；只保存显示所需的元数据。
class HomeMetadata {
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
    'uploader',
    'mediaKind',
    'contentDomain',
    'contentRating',
    'coverRating',
    'isNsfw',
  };

  static bool cacheable(Map<String, dynamic> data) =>
      ![
        ...(data['items'] as List? ?? []),
        for (final section
            in (data['sections'] as List? ?? []).whereType<Map>())
          ...(section['items'] as List? ?? []),
      ].whereType<Map>().any(
        (item) => item['media'] is List || item['presentation'] != null,
      );

  static Map<String, dynamic> serialize(Map<String, dynamic> data) {
    Map<String, dynamic> item(Map value) => {
      for (final field in fields)
        if (value[field] is String ||
            value[field] is num ||
            value[field] is bool)
          field: value[field],
      if (value['tags'] is List)
        'tags': (value['tags'] as List).whereType<String>().toList(),
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
