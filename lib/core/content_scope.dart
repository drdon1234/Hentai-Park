import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'localization.dart';
import 'models.dart';

/// 内容分类与站点身份是不同的范围，序列化时保持边界。
class ContentScope {
  const ContentScope.all() : category = null, sourceKey = null, domains = null;
  const ContentScope.domain(SourceCategory domain)
    : category = domain,
      sourceKey = null,
      domains = null;
  const ContentScope.source(String source)
    : sourceKey = source,
      category = null,
      domains = null;

  /// 首页筛选后的全部分类：仍按“全部分类”记录历史，只包含筛选出的域。
  const ContentScope.domains(Set<SourceCategory> this.domains)
    : category = null,
      sourceKey = null;

  final SourceCategory? category;
  final String? sourceKey;
  final Set<SourceCategory>? domains;
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
      (category == null || domain == category) &&
      (domains?.contains(domain) ?? true);

  @override
  bool operator ==(Object other) =>
      other is ContentScope &&
      category == other.category &&
      sourceKey == other.sourceKey &&
      setEquals(domains, other.domains);
  @override
  int get hashCode => Object.hash(
    category,
    sourceKey,
    domains == null ? null : Object.hashAllUnordered(domains!),
  );
}
