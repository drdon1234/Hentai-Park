import 'package:flutter/material.dart';

import 'content_scope.dart';
import 'diagnostic_entry.dart';
import 'localization.dart';
import 'models.dart';
import 'settings_validation.dart';
import 'storage.dart';
import 'translation_options.dart';

enum ReaderMode { vertical, leftToRight, rightToLeft }

extension ReaderModeLabel on ReaderMode {
  String get label => switch (this) {
    ReaderMode.vertical => tr('上下滚动（条漫）'),
    ReaderMode.leftToRight => tr('左右翻页（从左到右）'),
    ReaderMode.rightToLeft => tr('左右翻页（日漫，从右到左）'),
  };
  IconData get icon => switch (this) {
    ReaderMode.vertical => Icons.swap_vert_rounded,
    ReaderMode.leftToRight => Icons.arrow_forward_rounded,
    ReaderMode.rightToLeft => Icons.arrow_back_rounded,
  };
}

/// Settings grouped by what they affect. Each domain notifies only for its own keys,
/// while all values stay in one settings.json, so the stored format and backups are
/// unchanged. Every stored key belongs to exactly one domain.
enum SettingsDomain {
  appearance({
    'themeMode',
    'seedColor',
    'language',
    'refreshRate',
    'gridColumns',
    'desktopScale',
    'domainOrder',
    'homeCategories',
  }),
  reader({
    'readerMode',
    'preloadPages',
    'keepScreenOn',
    'volumeKeyPaging',
    'tapToPage',
    'readerDual',
    'readerCoverSingle',
    'readerSplitWide',
    'readerCrop',
    'readerDim',
    'readerWarm',
    'readerGrayscale',
    'readerInvert',
    'readerTapLayout',
    'readerTapInvertH',
    'readerTapInvertV',
    'readerBackground',
    'readerShowPageNumber',
    'readerOrientation',
    'readerAnimate',
    'readerGap',
  }),
  novel({
    'novelAnimate',
    'novelAutoScroll',
    'novelBold',
    'novelBrightness',
    'novelDim',
    'novelFont',
    'novelFontSize',
    'novelIndent',
    'novelJustify',
    'novelKeepScreenOn',
    'novelLetterSpacing',
    'novelLineHeight',
    'novelMargin',
    'novelMode',
    'novelOrientation',
    'novelParagraphGap',
    'novelShowStatus',
    'novelSpeechRate',
    'novelTapToPage',
    'novelTheme',
    'novelVolumeKeys',
  }),
  shortVideo({'shortVideoPreloadCount', 'shortVideoRetainedCount'}),
  network({
    'dataSavingMode',
    'proxy',
    'imageConcurrency',
    'cacheLimitMb',
    'downloadConcurrency',
    'downloadWifiOnly',
    'downloadDirectory',
  }),
  privacy({
    'blurCovers',
    'secureScreen',
    'incognito',
    'appLock',
    'appLockAfter',
    'adultConfirmed',
    'onboarded',
    'replyWithoutAsking',
  }),
  library({
    'askCategoryOnFavorite',
    'librarySort',
    'librarySortAsc',
    'libraryDisplay',
    'libraryFilterDownloaded',
    'libraryFilterUnread',
    'libraryFilterSources',
    'libraryFilterKind',
    'badgeUnread',
    'badgeDownloaded',
    'badgeSource',
    'libraryUpdateHours',
    'lastLibraryUpdate',
    'updateOnlyMultiChapter',
    'updateSkipUnread',
    'updateSkipNotStarted',
    'autoDownloadNew',
    'deleteAfterRead',
  }),
  subscriptions({
    'subscriptionUpdateHours',
    'subscriptionNotifications',
    'subscriptionNotificationPreview',
  }),
  search({
    'rankingSelection',
    'searchHistories',
    'tagDownloadReminders',
    'aggregateExcluded',
    'autoTranslateContent',
    'translateEngine',
    'translateTargets',
  }),
  filter({'blockedTags', 'blockPresets', 'blockedWorks', 'blockedAuthors'}),
  maintenance({
    'logMode',
    'autoSourceUpdates',
    'autoAppUpdates',
    'lastSourceUpdate',
    'autoBackupHours',
    'autoBackupKeep',
    'lastAutoBackup',
  });

  const SettingsDomain(this.keys);
  final Set<String> keys;

  static SettingsDomain? of(String key) {
    for (final domain in values) {
      if (domain.keys.contains(key)) return domain;
    }
    return null;
  }
}

/// User preferences. Every setter persists immediately (debounced) and notifies listeners
/// of its key and domain; prefer [AppSettings.domain] or [AppSettings.watch] over listening
/// to the whole object.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  final _store = JsonStore('settings.json');
  Map<String, dynamic> _v = {};

  /// No settings were stored before this launch: a new install, which gets the full first-run
  /// flow. Existing users only confirm their age once.
  bool get freshInstall => _freshInstall;
  bool _freshInstall = false;

  Future<void> load() async {
    final data = await _store.load();
    _v = data is Map ? data.cast<String, dynamic>() : {};
    _freshInstall = _v.isEmpty;
    final invalidKeys = <String>[];
    for (final e in _v.entries) {
      try {
        validateSettings({e.key: e.value});
      } on FormatException {
        invalidKeys.add(e.key);
      }
    }
    if (invalidKeys.isNotEmpty) {
      final file = AppPaths.dataFile('settings.json');
      // 只保留将被修正的原配置，不动账号、书库或下载。
      if (await file.exists()) {
        await file.copy(
          '${file.path}.invalid-${DateTime.now().microsecondsSinceEpoch}',
        );
      }
      for (final key in invalidKeys) {
        _v.remove(key);
      }
      _store.save(_v);
      await _store.flush();
    }
    if (_v.containsKey('searchHistory')) {
      final migrated = _migrateSearchHistory(_v);
      _store.save(migrated);
      await _store.flush();
      _v = migrated;
    }
  }

  static Map<String, dynamic> _migrateSearchHistory(
    Map<String, dynamic> values,
  ) {
    if (!values.containsKey('searchHistory')) return values;
    final buckets = {
      ...?(values['searchHistories'] as Map?)?.cast<String, dynamic>(),
    };
    final key = const ContentScope.all().historyKey;
    final seen = <String>{};
    buckets[key] =
        [
              if (buckets[key] is List)
                ...(buckets[key] as List).whereType<String>(),
              if (values['searchHistory'] is List)
                ...(values['searchHistory'] as List).whereType<String>(),
            ]
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty && seen.add(s))
            .take(30)
            .toList();
    return {...values, 'searchHistories': buckets}..remove('searchHistory');
  }

  T _get<T>(String key, T fallback) {
    final value = _v[key];
    return value is T ? value : fallback;
  }

  void _set(String key, Object? value) {
    assert(SettingsDomain.of(key) != null, 'Settings key $key has no domain');
    validateSettings({key: value});
    _v[key] = value;
    _store.save(_v);
    _keyed[key]?.notify();
    notifyListeners();
  }

  final _keyed = <String, _KeyNotifier>{};

  /// Notifies only when one of [keys] changes (or settings are reloaded wholesale). Prefer this
  /// over listening to the whole object: search history writes, for example, must not rebuild
  /// the app theme or a reader.
  Listenable watch(Iterable<String> keys) => Listenable.merge([
    for (final key in keys) _keyed[key] ??= _KeyNotifier(),
  ]);

  /// Notifies when any setting of [domain] changes.
  Listenable domain(SettingsDomain domain) =>
      _domains[domain] ??= watch(domain.keys);
  final _domains = <SettingsDomain, Listenable>{};

  void _notifyAll() {
    for (final notifier in _keyed.values) {
      notifier.notify();
    }
    notifyListeners();
  }

  /// Keys that change the app-wide theme or language.
  static const appearanceKeys = {
    'themeMode',
    'seedColor',
    'language',
    'desktopScale',
  };

  /// Keys that change which works are hidden by the content filter.
  static const filterKeys = {
    'blockedTags',
    'blockPresets',
    'blockedWorks',
    'blockedAuthors',
  };

  /// Keys the comic reader renders from.
  static const readerKeys = {
    'keepScreenOn',
    'preloadPages',
    'readerAnimate',
    'readerBackground',
    'readerCoverSingle',
    'readerCrop',
    'readerDim',
    'readerDual',
    'readerGap',
    'readerGrayscale',
    'readerInvert',
    'readerMode',
    'readerOrientation',
    'readerShowPageNumber',
    'readerSplitWide',
    'readerTapInvertH',
    'readerTapInvertV',
    'readerTapLayout',
    'readerWarm',
    'seedColor',
    'tapToPage',
    'volumeKeyPaging',
  };

  /// Keys the novel reader renders from.
  static const novelKeys = {
    'novelAnimate',
    'novelAutoScroll',
    'novelBold',
    'novelBrightness',
    'novelDim',
    'novelFont',
    'novelFontSize',
    'novelIndent',
    'novelJustify',
    'novelKeepScreenOn',
    'novelLetterSpacing',
    'novelLineHeight',
    'novelMargin',
    'novelMode',
    'novelOrientation',
    'novelParagraphGap',
    'novelShowStatus',
    'novelSpeechRate',
    'novelTapToPage',
    'novelTheme',
    'novelVolumeKeys',
    'seedColor',
  };

  /// Empty language code follows the system language.
  String get language => _get('language', '');
  set language(String value) {
    final selected = AppLocalizations.localeFromKey(value);
    AppLocalizations.instance.setLocale(
      selected ??
          AppLocalizations.resolveLocales(
            WidgetsBinding.instance.platformDispatcher.locales,
          ),
    );
    _set('language', selected == null ? '' : value);
  }

  Locale? get locale => AppLocalizations.localeFromKey(language);

  // ── Appearance ──
  ThemeMode get themeMode =>
      ThemeMode.values[_get('themeMode', ThemeMode.dark.index).clamp(0, 2)];
  set themeMode(ThemeMode m) => _set('themeMode', m.index);

  int get seedColor => _get('seedColor', 0xFFC96442);
  set seedColor(int c) => _set('seedColor', c);

  bool get blurCovers => _get('blurCovers', false);
  set blurCovers(bool v) => _set('blurCovers', v);

  bool get secureScreen => _get('secureScreen', false);
  set secureScreen(bool v) => _set('secureScreen', v);

  /// Preferred display refresh rate in Hz; 0 = follow the display's highest rate.
  int get refreshRate => _get('refreshRate', 0);
  set refreshRate(int v) => _set('refreshRate', v);

  int get desktopScale => _get('desktopScale', 100);
  set desktopScale(int v) => _set('desktopScale', v.clamp(75, 200));

  int get gridColumns => _get('gridColumns', 0); // 0 = adaptive
  set gridColumns(int v) => _set('gridColumns', v);

  /// Default display order for content domains; source ranking is independent.
  static const defaultDomainOrder = [
    SourceCategory.doujin,
    SourceCategory.gallery,
    SourceCategory.anime,
    SourceCategory.jav,
    SourceCategory.adult,
    SourceCategory.shortvideo,
    SourceCategory.aiDrama,
    SourceCategory.novel,
    SourceCategory.game,
    SourceCategory.other,
  ];

  List<SourceCategory> get domainOrder {
    final raw = _v['domainOrder'];
    final categories = {for (final c in SourceCategory.values) c.name: c};
    return {
      if (raw is List)
        for (final name in raw)
          if (categories.containsKey(name)) categories[name]!,
      ...defaultDomainOrder,
    }.toList();
  }

  set domainOrder(List<SourceCategory> value) => _set('domainOrder', [
    for (final category in {...value, ...defaultDomainOrder}) category.name,
  ]);

  // ── Reader ──
  ReaderMode get readerMode =>
      ReaderMode.values[_get(
        'readerMode',
        0,
      ).clamp(0, ReaderMode.values.length - 1)];
  set readerMode(ReaderMode m) => _set('readerMode', m.index);

  int get preloadPages => _get('preloadPages', 4);
  set preloadPages(int v) => _set('preloadPages', v);

  static const maxShortVideoPreloadCount = 3;
  static const maxShortVideoRetainedCount = 5;

  int get shortVideoPreloadCount => _get('shortVideoPreloadCount', 2);
  set shortVideoPreloadCount(int v) => _set('shortVideoPreloadCount', v);

  int get shortVideoRetainedCount => _get('shortVideoRetainedCount', 2);
  set shortVideoRetainedCount(int v) => _set('shortVideoRetainedCount', v);

  bool get keepScreenOn => _get('keepScreenOn', true);
  set keepScreenOn(bool v) => _set('keepScreenOn', v);

  bool get volumeKeyPaging => _get('volumeKeyPaging', true);
  set volumeKeyPaging(bool v) => _set('volumeKeyPaging', v);

  bool get tapToPage => _get('tapToPage', true);
  set tapToPage(bool v) => _set('tapToPage', v);

  double _getDouble(String key, double fallback) =>
      _v[key] is num ? (_v[key] as num).toDouble() : fallback;

  /// Two pages side by side in paged modes: off | landscape | always.
  String get readerDual => _get('readerDual', 'off');
  set readerDual(String v) => _set('readerDual', v);

  /// In dual mode, show the first page (cover) on its own.
  bool get readerCoverSingle => _get('readerCoverSingle', true);
  set readerCoverSingle(bool v) => _set('readerCoverSingle', v);

  /// Cut double-page spreads into two screens in single-page paged mode.
  bool get readerSplitWide => _get('readerSplitWide', false);
  set readerSplitWide(bool v) => _set('readerSplitWide', v);

  bool get readerCrop => _get('readerCrop', false);
  set readerCrop(bool v) => _set('readerCrop', v);

  /// Darkening overlay, 0 (off) … 0.8.
  double get readerDim => _getDouble('readerDim', 0);
  set readerDim(double v) => _set('readerDim', v);

  /// Warm (night light) overlay, 0 (off) … 0.5.
  double get readerWarm => _getDouble('readerWarm', 0);
  set readerWarm(double v) => _set('readerWarm', v);

  bool get readerGrayscale => _get('readerGrayscale', false);
  set readerGrayscale(bool v) => _set('readerGrayscale', v);

  bool get readerInvert => _get('readerInvert', false);
  set readerInvert(bool v) => _set('readerInvert', v);

  /// Index into TapLayout (ui/reader/reader_layout.dart).
  int get readerTapLayout => _get('readerTapLayout', 0);
  set readerTapLayout(int v) => _set('readerTapLayout', v);

  bool get readerTapInvertH => _get('readerTapInvertH', false);
  set readerTapInvertH(bool v) => _set('readerTapInvertH', v);

  bool get readerTapInvertV => _get('readerTapInvertV', false);
  set readerTapInvertV(bool v) => _set('readerTapInvertV', v);

  /// black | gray | white
  String get readerBackground => _get('readerBackground', 'black');
  set readerBackground(String v) => _set('readerBackground', v);

  bool get readerShowPageNumber => _get('readerShowPageNumber', true);
  set readerShowPageNumber(bool v) => _set('readerShowPageNumber', v);

  /// auto | portrait | landscape
  String get readerOrientation => _get('readerOrientation', 'auto');
  set readerOrientation(String v) => _set('readerOrientation', v);

  bool get readerAnimate => _get('readerAnimate', true);
  set readerAnimate(bool v) => _set('readerAnimate', v);

  /// Gap between pages in vertical mode, logical pixels.
  double get readerGap => _getDouble('readerGap', 0);
  set readerGap(double v) => _set('readerGap', v);

  double get novelFontSize => _getDouble('novelFontSize', 22).clamp(12, 42);
  set novelFontSize(double v) => _set('novelFontSize', v.clamp(12, 42));
  double get novelLineHeight =>
      _getDouble('novelLineHeight', 1.8).clamp(1.2, 2.8);
  set novelLineHeight(double v) => _set('novelLineHeight', v.clamp(1.2, 2.8));
  double get novelLetterSpacing =>
      _getDouble('novelLetterSpacing', 0).clamp(0, 4);
  set novelLetterSpacing(double v) => _set('novelLetterSpacing', v.clamp(0, 4));
  double get novelMargin => _getDouble('novelMargin', 20).clamp(8, 48);
  set novelMargin(double v) => _set('novelMargin', v.clamp(8, 48));
  double get novelParagraphGap =>
      _getDouble('novelParagraphGap', 12).clamp(0, 36);
  set novelParagraphGap(double v) => _set('novelParagraphGap', v.clamp(0, 36));
  String get novelFont => _get('novelFont', 'serif');
  set novelFont(String v) => _set('novelFont', v);
  bool get novelBold => _get('novelBold', false);
  set novelBold(bool v) => _set('novelBold', v);
  bool get novelJustify => _get('novelJustify', false);
  set novelJustify(bool v) => _set('novelJustify', v);
  String get novelMode => _get('novelMode', 'scroll');
  set novelMode(String v) => _set('novelMode', v);
  String get novelTheme => _get('novelTheme', 'paper');
  set novelTheme(String v) => _set('novelTheme', v);
  double get novelDim => _getDouble('novelDim', 0).clamp(0, 0.7);
  set novelDim(double v) => _set('novelDim', v.clamp(0, 0.7));
  double get novelBrightness => _getDouble('novelBrightness', -1).clamp(-1, 1);
  set novelBrightness(double v) =>
      _set('novelBrightness', v < 0 ? -1.0 : v.clamp(0, 1));
  double get novelAutoScroll =>
      _getDouble('novelAutoScroll', 30).clamp(10, 100);
  set novelAutoScroll(double v) => _set('novelAutoScroll', v.clamp(10, 100));
  bool get novelShowStatus => _get('novelShowStatus', true);
  set novelShowStatus(bool v) => _set('novelShowStatus', v);
  bool get novelIndent => _get('novelIndent', true);
  set novelIndent(bool v) => _set('novelIndent', v);
  bool get novelKeepScreenOn => _get('novelKeepScreenOn', true);
  set novelKeepScreenOn(bool v) => _set('novelKeepScreenOn', v);
  bool get novelVolumeKeys => _get('novelVolumeKeys', false);
  set novelVolumeKeys(bool v) => _set('novelVolumeKeys', v);
  bool get novelTapToPage => _get('novelTapToPage', true);
  set novelTapToPage(bool v) => _set('novelTapToPage', v);
  bool get novelAnimate => _get('novelAnimate', true);
  set novelAnimate(bool v) => _set('novelAnimate', v);
  String get novelOrientation => _get('novelOrientation', 'auto');
  set novelOrientation(String v) => _set('novelOrientation', v);
  double get novelSpeechRate => _getDouble('novelSpeechRate', .5).clamp(.2, .8);
  set novelSpeechRate(double v) => _set('novelSpeechRate', v.clamp(.2, .8));
  String get libraryFilterKind => _get('libraryFilterKind', 'all');
  set libraryFilterKind(String v) => _set('libraryFilterKind', v);

  // ── Network ──
  String get proxy => _get('proxy', '');
  set proxy(String v) => _set('proxy', v.trim());

  String get dataSavingMode => _get('dataSavingMode', 'off');
  set dataSavingMode(String v) => _set('dataSavingMode', v);
  bool get dataSaver => dataSavingMode != 'off';
  bool get searchOnlySources => dataSavingMode == 'super';

  int get imageConcurrency => _get('imageConcurrency', 6);
  set imageConcurrency(int v) => _set('imageConcurrency', v);

  int get cacheLimitMb => _get('cacheLimitMb', 1024);
  set cacheLimitMb(int v) => _set('cacheLimitMb', v);

  bool get tagDownloadReminders => _get('tagDownloadReminders', true);
  set tagDownloadReminders(bool v) => _set('tagDownloadReminders', v);

  int get subscriptionUpdateHours => _get('subscriptionUpdateHours', 6);
  set subscriptionUpdateHours(int v) => _set('subscriptionUpdateHours', v);
  bool get subscriptionNotifications =>
      _get('subscriptionNotifications', false);
  set subscriptionNotifications(bool v) => _set('subscriptionNotifications', v);
  bool get subscriptionNotificationPreview =>
      _get('subscriptionNotificationPreview', false);
  set subscriptionNotificationPreview(bool v) =>
      _set('subscriptionNotificationPreview', v);

  int get downloadConcurrency => _get('downloadConcurrency', 3);
  set downloadConcurrency(int v) => _set('downloadConcurrency', v);

  bool get downloadWifiOnly => _get('downloadWifiOnly', false);
  set downloadWifiOnly(bool v) => _set('downloadWifiOnly', v);

  String get downloadDirectory => _get('downloadDirectory', '');
  set downloadDirectory(String v) => _set('downloadDirectory', v);

  LogMode get logMode => LogMode.values.byName(_get('logMode', 'full'));
  set logMode(LogMode v) => _set('logMode', v.name);

  /// Check official plugins at launch; installing requires user confirmation.
  bool get autoSourceUpdates => _get('autoSourceUpdates', true);
  set autoSourceUpdates(bool v) => _set('autoSourceUpdates', v);

  /// Check the installed application's version at launch without downloading it.
  bool get autoAppUpdates => _get('autoAppUpdates', true);
  set autoAppUpdates(bool v) => _set('autoAppUpdates', v);

  int get lastSourceUpdate => _get('lastSourceUpdate', 0);
  set lastSourceUpdate(int v) => _set('lastSourceUpdate', v);

  /// Queue new chapters found by library updates.
  bool get autoDownloadNew => _get('autoDownloadNew', false);
  set autoDownloadNew(bool v) => _set('autoDownloadNew', v);

  /// Delete a downloaded chapter once it is marked read.
  bool get deleteAfterRead => _get('deleteAfterRead', false);
  set deleteAfterRead(bool v) => _set('deleteAfterRead', v);

  // ── Content filter ──
  /// Tag blocklist entries (see core/tag_blocklist.dart for the syntax).
  List<String> get blockedTags =>
      ((_v['blockedTags'] as List?) ?? []).map((e) => e.toString()).toList();
  set blockedTags(List<String> v) => _set('blockedTags', v);

  Map<String, String> get blockedWorks =>
      Map<String, String>.from(_v['blockedWorks'] as Map? ?? {});
  Map<String, dynamic> get _blockedAuthorRules =>
      Map<String, dynamic>.from(_v['blockedAuthors'] as Map? ?? {});
  Map<String, String> get blockedAuthors => {
    for (final entry in _blockedAuthorRules.entries)
      entry.key: (entry.value as Map)['name'] as String,
  };
  bool isBlockedAuthorWork(WorkItem item) => _blockedAuthorRules.values.any(
    (rule) => ((rule as Map)['works'] as List).contains(item.uid),
  );
  void blockWork(WorkItem item) =>
      _set('blockedWorks', {...blockedWorks, item.uid: item.title});
  void unblockWork(String uid) =>
      _set('blockedWorks', {...blockedWorks}..remove(uid));
  void blockAuthor(String source, String author, {WorkItem? work}) {
    final name = author.trim();
    if (name.isNotEmpty) {
      final identity = '$source:${name.toLowerCase()}';
      final rules = _blockedAuthorRules;
      _set('blockedAuthors', {
        ...rules,
        identity: {
          'name': name,
          // 列表可能不含作者；记录已核实作品与规则的关系，重启后仍能隐藏。
          'works': {
            ...?((rules[identity] as Map?)?['works'] as List?),
            if (work?.source == source) work!.uid,
          }.toList(),
        },
      });
    }
  }

  void unblockAuthor(String identity) =>
      _set('blockedAuthors', _blockedAuthorRules..remove(identity));

  Map<String, dynamic> get rankingSelection =>
      Map<String, dynamic>.from(_v['rankingSelection'] as Map? ?? {});
  set rankingSelection(Map<String, dynamic> value) =>
      _set('rankingSelection', value);

  void addBlockedTag(String entry) {
    final e = entry.trim();
    if (e.isEmpty) return;
    final list = blockedTags;
    if (list.any((x) => x.toLowerCase() == e.toLowerCase())) return;
    blockedTags = [...list, e];
  }

  /// Preset block groups (core/tag_blocklist.dart: blockPresets), keyed by preset id:
  /// {on: bool, title: bool, entries: [String]}. Missing values fall back to the preset's defaults.
  Map<String, dynamic> get blockPresetState =>
      ((_v['blockPresets'] as Map?) ?? {}).cast<String, dynamic>();

  void setBlockPreset(
    String id, {
    bool? on,
    bool? title,
    List<String>? entries,
    bool reset = false,
  }) {
    final all = {...blockPresetState};
    final cur = reset
        ? <String, dynamic>{}
        : {...((all[id] as Map?) ?? {}).cast<String, dynamic>()};
    if (on != null) cur['on'] = on;
    if (title != null) cur['title'] = title;
    if (entries != null) cur['entries'] = entries;
    if (reset) {
      final old = (all[id] as Map?) ?? {};
      cur['on'] = old['on'] ?? false;
      cur['title'] = old['title'] ?? false;
    }
    all[id] = cur;
    _set('blockPresets', all);
  }

  // ── Search ──
  Map<String, dynamic> get _searchHistories =>
      (_v['searchHistories'] as Map?)?.cast<String, dynamic>() ?? {};
  List<String> searchHistoryFor(ContentScope scope) =>
      (_searchHistories[scope.historyKey] as List?)
          ?.whereType<String>()
          .toList() ??
      [];
  void _saveSearchHistory(ContentScope scope, List<String> history) {
    final buckets = {..._searchHistories};
    if (history.isEmpty) {
      buckets.remove(scope.historyKey);
    } else {
      buckets[scope.historyKey] = history;
    }
    _set('searchHistories', buckets);
  }

  void addSearchHistory(String keyword, {required ContentScope scope}) {
    final k = keyword.trim();
    if (k.isEmpty || incognito) return;
    final list = searchHistoryFor(scope)..remove(k);
    list.insert(0, k);
    _saveSearchHistory(scope, list.take(30).toList());
  }

  void removeSearchHistory(String keyword, {required ContentScope scope}) =>
      _saveSearchHistory(scope, searchHistoryFor(scope)..remove(keyword));
  void clearSearchHistory({required ContentScope scope}) =>
      _saveSearchHistory(scope, []);

  /// Sources excluded from aggregated search (enabled sources are included by default).
  Set<String> get aggregateExcluded =>
      ((_v['aggregateExcluded'] as List?) ?? [])
          .map((e) => e.toString())
          .toSet();
  void setAggregateIncluded(String key, bool included) {
    final s = aggregateExcluded;
    included ? s.remove(key) : s.add(key);
    _set('aggregateExcluded', s.toList());
  }

  /// Translation service used by multi-language search (see core/translation_options.dart).
  bool get autoTranslateContent => _get('autoTranslateContent', false);
  set autoTranslateContent(bool value) => _set('autoTranslateContent', value);

  String get translateEngine => _get('translateEngine', 'google');
  set translateEngine(String v) => _set('translateEngine', v);

  /// Languages a keyword is translated into for multi-language search, in display order.
  List<String> get translateTargets {
    final raw = _v['translateTargets'];
    if (raw is! List) return translateLanguages.keys.toList();
    final picked = raw.map((e) => e.toString()).toSet();
    return translateLanguages.keys.where(picked.contains).toList();
  }

  set translateTargets(List<String> v) => _set('translateTargets', v);

  // ── First run ──
  /// The user confirmed being an adult on this device.
  bool get adultConfirmed => _get('adultConfirmed', false);
  set adultConfirmed(bool v) => _set('adultConfirmed', v);

  /// The first-run flow (privacy and interests) is finished or skipped.
  bool get onboarded => _get('onboarded', false);
  set onboarded(bool v) => _set('onboarded', v);

  /// Categories with a shelf on the home page; empty shows every category.
  List<SourceCategory> get homeCategories {
    final raw = _v['homeCategories'];
    if (raw is! List) return const [];
    final names = raw.whereType<String>().toSet();
    return SourceCategory.values.where((c) => names.contains(c.name)).toList();
  }

  set homeCategories(List<SourceCategory> value) =>
      _set('homeCategories', [for (final c in value) c.name]);

  String? homeSource(SourceCategory category) =>
      (_v['homeSources'] as Map?)?[category.name] as String? ??
      (category == SourceCategory.shortvideo ? 'shorties' : null);

  void setHomeSource(SourceCategory category, String source) => _set(
    'homeSources',
    {...?(_v['homeSources'] as Map?), category.name: source},
  );

  /// Sites where posting a reply to unlock a resource no longer asks first.
  Set<String> get replyWithoutAsking =>
      ((_v['replyWithoutAsking'] as List?) ?? []).whereType<String>().toSet();
  void allowReplyWithoutAsking(String source) =>
      _set('replyWithoutAsking', {...replyWithoutAsking, source}.toList());

  // ── Privacy ──
  /// Incognito: no history, progress or read marks are recorded.
  bool get incognito => _get('incognito', false);
  set incognito(bool v) => _set('incognito', v);

  /// Require biometrics / device credentials to open the app.
  bool get appLock => _get('appLock', false);
  set appLock(bool v) => _set('appLock', v);

  /// Seconds in the background before the lock engages again (0 = immediately).
  int get appLockAfter => _get('appLockAfter', 0);
  set appLockAfter(int v) => _set('appLockAfter', v);

  // ── Library ──
  /// Ask which categories to use every time a work is favorited.
  bool get askCategoryOnFavorite => _get('askCategoryOnFavorite', false);
  set askCategoryOnFavorite(bool v) => _set('askCategoryOnFavorite', v);

  /// added | read | title | updated | unread
  String get librarySort => _get('librarySort', 'added');
  set librarySort(String v) => _set('librarySort', v);

  bool get librarySortAsc => _get('librarySortAsc', false);
  set librarySortAsc(bool v) => _set('librarySortAsc', v);

  /// grid | list
  String get libraryDisplay => _get('libraryDisplay', 'grid');
  set libraryDisplay(String v) => _set('libraryDisplay', v);

  bool get libraryFilterDownloaded => _get('libraryFilterDownloaded', false);
  set libraryFilterDownloaded(bool v) => _set('libraryFilterDownloaded', v);

  bool get libraryFilterUnread => _get('libraryFilterUnread', false);
  set libraryFilterUnread(bool v) => _set('libraryFilterUnread', v);

  /// Sources to show; empty = all.
  Set<String> get libraryFilterSources =>
      ((_v['libraryFilterSources'] as List?) ?? [])
          .map((e) => e.toString())
          .toSet();
  set libraryFilterSources(Set<String> v) =>
      _set('libraryFilterSources', v.toList());

  bool get badgeUnread => _get('badgeUnread', true);
  set badgeUnread(bool v) => _set('badgeUnread', v);

  bool get badgeDownloaded => _get('badgeDownloaded', true);
  set badgeDownloaded(bool v) => _set('badgeDownloaded', v);

  bool get badgeSource => _get('badgeSource', true);
  set badgeSource(bool v) => _set('badgeSource', v);

  // ── Library updates ──
  /// Hours between automatic library updates (checked at launch and on resume); 0 disables them.
  int get libraryUpdateHours => _get('libraryUpdateHours', 0);
  set libraryUpdateHours(int v) => _set('libraryUpdateHours', v);

  int get lastLibraryUpdate => _get('lastLibraryUpdate', 0);
  set lastLibraryUpdate(int v) => _set('lastLibraryUpdate', v);

  /// One-shot galleries never get new chapters; skipping them saves most requests.
  bool get updateOnlyMultiChapter => _get('updateOnlyMultiChapter', true);
  set updateOnlyMultiChapter(bool v) => _set('updateOnlyMultiChapter', v);

  bool get updateSkipUnread => _get('updateSkipUnread', false);
  set updateSkipUnread(bool v) => _set('updateSkipUnread', v);

  bool get updateSkipNotStarted => _get('updateSkipNotStarted', false);
  set updateSkipNotStarted(bool v) => _set('updateSkipNotStarted', v);

  // ── Backup ──
  /// Hours between automatic backups; 0 disables them.
  int get autoBackupHours => _get('autoBackupHours', 24);
  set autoBackupHours(int v) => _set('autoBackupHours', v);

  int get autoBackupKeep => _get('autoBackupKeep', 3);
  set autoBackupKeep(int v) => _set('autoBackupKeep', v);

  int get lastAutoBackup => _get('lastAutoBackup', 0);
  set lastAutoBackup(int v) => _set('lastAutoBackup', v);

  /// Keys that describe this device or transient state and are never exported in backups.
  static const _localOnly = {
    'downloadDirectory',
    'adultConfirmed',
    'appLock',
    'appLockAfter',
    'lastAutoBackup',
    'lastLibraryUpdate',
    'lastSourceUpdate',
  };

  Map<String, dynamic> exportJson() => {
    for (final e in _v.entries)
      if (!_localOnly.contains(e.key)) e.key: e.value,
  };

  void importJson(Map<String, dynamic> values) {
    _v = prepareImport(values);
    _store.save(_v);
    _notifyAll();
  }

  Future<void> flush() => _store.flush();

  Map<String, dynamic> prepareImport(Map<String, dynamic> values) {
    validateSettings(values);
    return _migrateSearchHistory({
      ..._v,
      for (final e in values.entries)
        if (!_localOnly.contains(e.key)) e.key: e.value,
    });
  }

  Future<void> reload() async {
    await load();
    AppLocalizations.instance.setLocale(
      locale ??
          AppLocalizations.resolveLocales(
            WidgetsBinding.instance.platformDispatcher.locales,
          ),
    );
    _notifyAll();
  }
}

class _KeyNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}
