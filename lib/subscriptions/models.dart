class SubscriptionTarget {
  SubscriptionTarget(Map data)
    : id = (data['id'] ?? '').toString(),
      kind = (data['kind'] ?? '').toString(),
      label = (data['label'] ?? data['id'] ?? '').toString();
  final String id;
  final String kind;
  final String label;
}

class SubscriptionMedia {
  SubscriptionMedia(this.json)
    : type = (json['type'] ?? 'image').toString(),
      url = (json['url'] ?? '').toString(),
      preview = (json['preview'] ?? '').toString();
  final Map<String, dynamic> json;
  final String type, url, preview;
  bool get needsDownload => json['resource'] is Map;
}

class SubscriptionPost {
  SubscriptionPost(Map data)
    : json = Map<String, dynamic>.from(data),
      id = (data['id'] ?? '').toString(),
      title = (data['title'] ?? '').toString(),
      text = (data['text'] ?? '').toString(),
      url = (data['url'] ?? '').toString(),
      date = (data['date'] ?? '').toString(),
      locked = data['locked'] == true,
      media = (data['media'] as List? ?? [])
          .whereType<Map>()
          .map((m) => SubscriptionMedia(m.cast<String, dynamic>()))
          .toList();
  final Map<String, dynamic> json;
  final String id, title, text, url, date;
  final bool locked;
  final List<SubscriptionMedia> media;

  bool? get commentsAvailable => json['commentsAvailable'] is bool
      ? json['commentsAvailable'] as bool
      : null;
}

class SubscriptionPage {
  SubscriptionPage(Map data)
    : items = (data['items'] as List? ?? [])
          .whereType<Map>()
          .map(SubscriptionPost.new)
          .toList(),
      cursor = data['cursor']?.toString(),
      hasNext = data['hasNext'] == true;
  final List<SubscriptionPost> items;
  final String? cursor;
  final bool hasNext;
}
