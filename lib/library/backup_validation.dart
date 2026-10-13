import '../core/settings_validation.dart';
import '../engine/source_manager.dart';
import '../novel/reading_notes.dart';
import '../subscriptions/subscription_store.dart';

/// 恢复输入在任何持久化前完整校验；不静默跳过损坏的用户资产。
void validateBackup(Map<String, dynamic> json) {
  Never invalid() => throw const FormatException('备份数据无效');
  for (final name in ['library', 'settings', 'sources']) {
    if (json[name] != null && json[name] is! Map) invalid();
  }
  if (json['settings'] case final Map values) {
    validateSettings(values.cast<String, dynamic>());
  }
  if (json['sources'] case final Map values) {
    SourceManager.validateImport(values.cast<String, dynamic>());
  }
  if (json['subscriptions'] case final data?) SubscriptionStore.parse(data);
  if (json['readingNotes'] case final data?) {
    if (data is! List || data.any((e) => ReadingNote.parse(e) == null)) {
      invalid();
    }
  }
  final library = json['library'];
  if (library is! Map) return;
  const integerFields = {
    'sort',
    'favoritedAt',
    'readerMode',
    'lastPage',
    'pageCount',
    'dateRead',
    'progressUpdatedAt',
    'position',
    'duration',
    'positionUpdatedAt',
    'time',
    'page',
  };
  for (final section in ['categories', 'works', 'chapters', 'history']) {
    final rows = library[section];
    if (rows == null) continue;
    if (rows is! List) invalid();
    for (final row in rows) {
      if (row is! Map || row.keys.any((e) => e is! String)) invalid();
      final identities = switch (section) {
        'categories' => ['name'],
        'works' => ['source', 'id'],
        'chapters' => ['source', 'workId', 'chapterId'],
        _ => ['source', 'workId'],
      };
      for (final field in identities) {
        if (row[field] is! String || (row[field] as String).isEmpty) invalid();
      }
      for (final field in integerFields) {
        final value = row[field];
        if (value != null &&
            (value is! int || value < 0 || value > 8640000000000000)) {
          invalid();
        }
      }
      if (row['readerMode'] != null && !{0, 1, 2}.contains(row['readerMode'])) {
        invalid();
      }
      for (final field in ['read', 'favorite']) {
        if (row[field] != null && row[field] is! bool) invalid();
      }
      if (row['item'] != null &&
          (row['item'] is! Map ||
              (row['item'] as Map).keys.any((e) => e is! String))) {
        invalid();
      }
      if (row['categories'] != null &&
          (row['categories'] is! List ||
              (row['categories'] as List).any((e) => e is! String))) {
        invalid();
      }
      for (final field in ['chapterId', 'chapterTitle']) {
        if (row[field] != null && row[field] is! String) invalid();
      }
    }
  }
}
