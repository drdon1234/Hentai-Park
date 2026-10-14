import 'dart:convert';

import 'localization.dart';
import 'models.dart';

/// 内容分类与站点身份是不同的范围，序列化时保持边界。
class ContentScope {
  const ContentScope.all() : category = null, sourceKey = null;
  const ContentScope.domain(SourceCategory domain)
    : category = domain,
      sourceKey = null;
  const ContentScope.source(String source)
    : sourceKey = source,
      category = null;

  final SourceCategory? category;
  final String? sourceKey;
  bool get isAll => category == null && sourceKey == null;
  String get historyKey => jsonEncode([
    if (sourceKey != null) ...[
      'source',
      sourceKey,
    ] else if (category != null) ...[
      'domain',
      category!.name,
    ] else
      'all',
  ]);
  String get label => sourceKey ?? category?.label ?? tr('全部分类');
  bool contains(String source, SourceCategory domain) =>
      (sourceKey == null || source == sourceKey) &&
      (category == null || domain == category);

  @override
  bool operator ==(Object other) =>
      other is ContentScope &&
      category == other.category &&
      sourceKey == other.sourceKey;
  @override
  int get hashCode => Object.hash(category, sourceKey);
}
