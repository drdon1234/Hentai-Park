import 'package:flutter/material.dart';

import 'storage.dart';
import 'localization.dart';
import 'translator.dart';

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

/// User preferences. Every setter persists immediately (debounced) and notifies listeners.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  final _store = JsonStore('settings.json');
  Map<String, dynamic> _v = {};

  Future<void> load() async {
    final data = await _store.load();
    if (data is Map) _v = data.cast<String, dynamic>();
  }

  T _get<T>(String key, T fallback) {
    final value = _v[key];
    return value is T ? value : fallback;
  }

  void _set(String key, Object? value) {
    _v[key] = value;
    _store.save(_v);
    notifyListeners();
  }

  /// Empty language code follows the system language.
  String get language => _get('language', '');
  set language(String value) {
    final selected = AppLocalizations.localeFromKey(value);
    AppLocalizations.instance.setLocale(selected ?? AppLocalizations.resolveLocales(WidgetsBinding.instance.platformDispatcher.locales));
    _set('language', selected == null ? '' : value);
  }
  Locale? get locale => AppLocalizations.localeFromKey(language);

  // ── Appearance ──
  ThemeMode get themeMode => ThemeMode.values[_get('themeMode', ThemeMode.dark.index).clamp(0, 2)];
  set themeMode(ThemeMode m) => _set('themeMode', m.index);

  int get seedColor => _get('seedColor', 0xFFE5355F);
  set seedColor(int c) => _set('seedColor', c);

  bool get blurCovers => _get('blurCovers', false);
  set blurCovers(bool v) => _set('blurCovers', v);

  bool get secureScreen => _get('secureScreen', false);
  set secureScreen(bool v) => _set('secureScreen', v);

  /// Preferred display refresh rate in Hz; 0 = follow the display's highest rate.
  int get refreshRate => _get('refreshRate', 0);
  set refreshRate(int v) => _set('refreshRate', v);

  int get gridColumns => _get('gridColumns', 0); // 0 = adaptive
  set gridColumns(int v) => _set('gridColumns', v);

  // ── Reader ──
  ReaderMode get readerMode => ReaderMode.values[_get('readerMode', 0).clamp(0, ReaderMode.values.length - 1)];
  set readerMode(ReaderMode m) => _set('readerMode', m.index);

  int get preloadPages => _get('preloadPages', 4);
  set preloadPages(int v) => _set('preloadPages', v);

  bool get keepScreenOn => _get('keepScreenOn', true);
  set keepScreenOn(bool v) => _set('keepScreenOn', v);

  bool get volumeKeyPaging => _get('volumeKeyPaging', true);
  set volumeKeyPaging(bool v) => _set('volumeKeyPaging', v);

  bool get tapToPage => _get('tapToPage', true);
  set tapToPage(bool v) => _set('tapToPage', v);

  double _getDouble(String key, double fallback) => (_v[key] as num?)?.toDouble() ?? fallback;

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

  // ── Network ──
  String get proxy => _get('proxy', '');
  set proxy(String v) => _set('proxy', v.trim());

  int get imageConcurrency => _get('imageConcurrency', 6);
  set imageConcurrency(int v) => _set('imageConcurrency', v);

  int get cacheLimitMb => _get('cacheLimitMb', 1024);
  set cacheLimitMb(int v) => _set('cacheLimitMb', v);

  int get downloadConcurrency => _get('downloadConcurrency', 3);
  set downloadConcurrency(int v) => _set('downloadConcurrency', v);

  bool get downloadWifiOnly => _get('downloadWifiOnly', false);
  set downloadWifiOnly(bool v) => _set('downloadWifiOnly', v);

  /// Queue new chapters found by library updates.
  bool get autoDownloadNew => _get('autoDownloadNew', false);
  set autoDownloadNew(bool v) => _set('autoDownloadNew', v);

  /// Delete a downloaded chapter once it is marked read.
  bool get deleteAfterRead => _get('deleteAfterRead', false);
  set deleteAfterRead(bool v) => _set('deleteAfterRead', v);

  // ── Content filter ──
  /// Tag blocklist entries (see core/tag_blocklist.dart for the syntax).
  List<String> get blockedTags => ((_v['blockedTags'] as List?) ?? []).map((e) => e.toString()).toList();
  set blockedTags(List<String> v) => _set('blockedTags', v);

  void addBlockedTag(String entry) {
    final e = entry.trim();
    if (e.isEmpty) return;
    final list = blockedTags;
    if (list.any((x) => x.toLowerCase() == e.toLowerCase())) return;
    blockedTags = [...list, e];
  }

  /// Preset block groups (core/tag_blocklist.dart: blockPresets), keyed by preset id:
  /// {on: bool, title: bool, entries: [String]}. Missing values fall back to the preset's defaults.
  Map<String, dynamic> get blockPresetState => ((_v['blockPresets'] as Map?) ?? {}).cast<String, dynamic>();

  void setBlockPreset(String id, {bool? on, bool? title, List<String>? entries, bool reset = false}) {
    final all = {...blockPresetState};
    final cur = reset ? <String, dynamic>{} : {...((all[id] as Map?) ?? {}).cast<String, dynamic>()};
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
  List<String> get searchHistory => (_v['searchHistory'] as List?)?.map((e) => e.toString()).toList() ?? [];
  void addSearchHistory(String keyword) {
    final k = keyword.trim();
    if (k.isEmpty) return;
    final list = searchHistory..remove(k);
    list.insert(0, k);
    _set('searchHistory', list.take(30).toList());
  }

  void removeSearchHistory(String keyword) => _set('searchHistory', searchHistory..remove(keyword));
  void clearSearchHistory() => _set('searchHistory', <String>[]);

  /// Sources excluded from aggregated search (enabled sources are included by default).
  Set<String> get aggregateExcluded => ((_v['aggregateExcluded'] as List?) ?? []).map((e) => e.toString()).toSet();
  void setAggregateIncluded(String key, bool included) {
    final s = aggregateExcluded;
    included ? s.remove(key) : s.add(key);
    _set('aggregateExcluded', s.toList());
  }

  /// Translation service used by multi-language search (see core/translator.dart).
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

  bool get onboarded => _get('onboarded', false);
  set onboarded(bool v) => _set('onboarded', v);

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
  Set<String> get libraryFilterSources => ((_v['libraryFilterSources'] as List?) ?? []).map((e) => e.toString()).toSet();
  set libraryFilterSources(Set<String> v) => _set('libraryFilterSources', v.toList());

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
  static const _localOnly = {'lastAutoBackup', 'lastLibraryUpdate', 'onboarded'};

  Map<String, dynamic> exportJson() => {
    for (final e in _v.entries)
      if (!_localOnly.contains(e.key)) e.key: e.value,
  };

  void importJson(Map<String, dynamic> values) {
    for (final e in values.entries) {
      if (!_localOnly.contains(e.key)) _v[e.key] = e.value;
    }
    _store.save(_v);
    notifyListeners();
  }

  Future<void> flush() => _store.flush();
}
