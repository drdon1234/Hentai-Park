import 'block_rule.dart';
import 'translation_options.dart';
import 'versions.dart';

/// 所有配置入口共用当前类型与取值规则，错误发生在任何写入之前。
void validateSettings(Map<String, dynamic> values) {
  const booleans = {
    'tagDownloadReminders',
    'subscriptionNotifications',
    'subscriptionNotificationPreview',
    'albumCollapsed',
    'blurCovers',
    'secureScreen',
    'keepScreenOn',
    'volumeKeyPaging',
    'tapToPage',
    'readerCoverSingle',
    'readerSplitWide',
    'readerCrop',
    'readerGrayscale',
    'readerInvert',
    'readerTapInvertH',
    'readerTapInvertV',
    'readerShowPageNumber',
    'readerAnimate',
    'novelBold',
    'novelJustify',
    'novelShowStatus',
    'novelIndent',
    'novelKeepScreenOn',
    'novelVolumeKeys',
    'novelTapToPage',
    'novelAnimate',
    'downloadWifiOnly',
    'autoSourceUpdates',
    'autoAppUpdates',
    'autoDownloadNew',
    'deleteAfterRead',
    'autoTranslateContent',
    'incognito',
    'appLock',
    'askCategoryOnFavorite',
    'librarySortAsc',
    'libraryFilterDownloaded',
    'libraryFilterUnread',
    'badgeUnread',
    'badgeDownloaded',
    'badgeSource',
    'updateOnlyMultiChapter',
    'updateSkipUnread',
    'updateSkipNotStarted',
    'adultConfirmed',
    'onboarded',
  };
  const choices = <String, Set<Object>>{
    'logMode': {'full', 'redacted'},
    'dataSavingMode': {'off', 'standard', 'super'},
    'homeDimension': {'all', 'twoD', 'threeD'},
    'homeMedia': {'all', 'image', 'video', 'other'},
    'subscriptionUpdateHours': {0, 1, 3, 6, 12, 24},
    'themeMode': {0, 1, 2},
    'readerMode': {0, 1, 2},
    'danmakuArea': {'topQuarter', 'topHalf', 'bottomHalf', 'full'},
    'gridColumns': {0, 2, 3, 4},
    'albumColumns': {1, 2, 3, 4, 5, 6},
    'libraryUpdateHours': {0, 6, 12, 24, 48, 168},
    'appLockAfter': {0, 60, 300, 900},
    'autoBackupHours': {0, 12, 24, 72, 168},
    'autoBackupKeep': {1, 2, 3, 5, 10},
    'readerDual': {'off', 'landscape', 'always'},
    'readerBackground': {'black', 'gray', 'white'},
    'readerOrientation': {'auto', 'portrait', 'landscape'},
    'novelOrientation': {'auto', 'portrait', 'landscape'},
    'novelFont': {'system', 'serif', 'monospace'},
    'novelMode': {'scroll', 'paged'},
    'novelTheme': {'paper', 'white', 'green', 'dark', 'system'},
    'libraryFilterKind': {'all', 'comic', 'video', 'novel', 'game'},
    'librarySort': {'added', 'read', 'title', 'updated'},
    'libraryDisplay': {'grid', 'list'},
    'historyDisplay': {'grid', 'list'},
    'downloadDisplay': {'grid', 'list'},
    'translateEngine': {'google'},
    'language': {'', 'zh-Hans', 'zh-Hant', 'en', 'ja', 'ko', 'es', 'ru', 'ar'},
  };
  const ranges = <String, (num, num)>{
    'desktopScale': (75, 200),
    'seedColor': (0, 0xffffffff),
    'refreshRate': (0, 1000),
    'preloadPages': (0, 10),
    'shortVideoPreloadCount': (0, 20),
    'shortVideoRetainedCount': (0, 5),
    'readerTapLayout': (0, 5),
    'readerDim': (0, .8),
    'readerWarm': (0, .5),
    'readerGap': (0, 100),
    'novelFontSize': (12, 42),
    'novelLineHeight': (1.2, 2.8),
    'novelLetterSpacing': (0, 4),
    'novelMargin': (8, 48),
    'novelParagraphGap': (0, 36),
    'novelDim': (0, .7),
    'novelBrightness': (-1, 1),
    'novelAutoScroll': (10, 100),
    'novelSpeechRate': (.2, .8),
    'imageConcurrency': (2, 12),
    'downloadConcurrency': (1, 8),
    'pdfPagesPerFile': (0, 5000),
    'cacheLimitMb': (0, 1048576),
    'historyLimit': (0, 100000),
    'lastAutoBackup': (0, 8640000000000000),
    'lastLibraryUpdate': (0, 8640000000000000),
    'lastSourceUpdate': (0, 8640000000000000),
  };
  const decimals = {
    'readerDim',
    'readerWarm',
    'readerGap',
    'novelFontSize',
    'novelLineHeight',
    'novelLetterSpacing',
    'novelMargin',
    'novelParagraphGap',
    'novelDim',
    'novelBrightness',
    'novelAutoScroll',
    'novelSpeechRate',
  };
  const stringLists = {
    'blockedTags',
    'aggregateExcluded',
    'libraryFilterSources',
    'searchHistory',
    'homeCategories',
    'homeExpandedDomains',
    'homeHiddenSources',
    'replyWithoutAsking',
  };
  bool stringList(Object? value) =>
      value is List && value.every((e) => e is String);
  bool aliasGroups(Object? value) =>
      value is Map &&
      value.entries.every(
        (e) =>
            e.key is String &&
            stringList(e.value) &&
            (e.value as List).every(
              (value) =>
                  value.length <= 256 &&
                  BlockRule(value as String).translatable &&
                  BlockRule(value).scope.isEmpty,
            ),
      );
  for (final e in values.entries) {
    final key = e.key, value = e.value;
    var valid = true;
    if (key == 'ignoredAppUpdate') {
      valid = value == '' || isReleaseVersion(value);
    }
    if (key == 'ignoredSourceUpdates') {
      valid =
          value is Map &&
          value.entries.every(
            (entry) =>
                entry.key is String &&
                (entry.key as String).isNotEmpty &&
                isReleaseVersion(entry.value),
          );
    }
    if (booleans.contains(key)) valid = value is bool;
    if (choices.containsKey(key)) {
      final options = choices[key]!;
      valid =
          options.contains(value) &&
          (options.first is int ? value is int : value is String);
    }
    if (ranges[key] case final bounds?) {
      valid =
          value is num &&
          value.isFinite &&
          value >= bounds.$1 &&
          value <= bounds.$2 &&
          (decimals.contains(key) || value is int);
    }
    if (key == 'proxy' || key == 'downloadDirectory') valid = value is String;
    if (stringLists.contains(key)) valid = stringList(value);
    if (key == 'domainOrder') valid = value is List;
    if (key == 'translateTargets') {
      valid =
          stringList(value) &&
          (value as List).every(translateLanguages.containsKey);
    }
    if (key == 'searchHistories') {
      valid =
          value is Map &&
          value.entries.every((e) => e.key is String && stringList(e.value));
    }
    if (key == 'homeSources' || key == 'blockedWorks') {
      valid =
          value is Map &&
          value.entries.every((e) => e.key is String && e.value is String);
    }
    if (key == 'blockedTagAliases') {
      valid = aliasGroups(value);
    }
    if (key == 'blockedAuthors') {
      valid =
          value is Map &&
          value.entries.every(
            (e) =>
                e.key is String &&
                e.value is Map &&
                (e.value as Map)['name'] is String &&
                stringList((e.value as Map)['works']),
          );
    }
    if (key == 'rankingSelection') {
      valid =
          value is Map &&
          value.entries.every(
            (e) =>
                e.key is String &&
                (e.value is String ||
                    e.value is Map &&
                        (e.value as Map).values.every(
                          (v) =>
                              v is Map &&
                              v.entries.every(
                                (o) =>
                                    o.key is String &&
                                    (o.value == null ||
                                        o.value is String ||
                                        o.value is num ||
                                        o.value is bool ||
                                        o.value is List &&
                                            (o.value as List).every(
                                              (v) =>
                                                  v is String ||
                                                  v is num ||
                                                  v is bool,
                                            )),
                              ),
                        )),
          );
    }
    if (key == 'blockPresets') {
      valid =
          value is Map &&
          value.entries.every(
            (e) =>
                e.key is String &&
                e.value is Map &&
                (e.value['on'] == null || e.value['on'] is bool) &&
                (e.value['title'] == null || e.value['title'] is bool) &&
                (e.value['entries'] == null ||
                    stringList(e.value['entries'])) &&
                (e.value['aliases'] == null || aliasGroups(e.value['aliases'])),
          );
    }
    if (!valid) throw const FormatException('设置数据无效');
  }
}
