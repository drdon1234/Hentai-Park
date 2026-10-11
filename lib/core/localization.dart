import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// The Chinese message is the stable key; only application copy is translated.
/// Remote titles, tags, usernames and user-authored values stay untouched.
class AppLocalizations {
  AppLocalizations._([this.locale = const Locale('en')]);
  static final instance = AppLocalizations._();
  static const supportedLocales = <Locale>[
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    Locale('ja'), Locale('ko'), Locale('en'), Locale('es'), Locale('ru'), Locale('ar'),
  ];
  static const languageNames = <String, String>{
    'zh-Hans': '简体中文', 'zh-Hant': '繁體中文', 'ja': '日本語', 'ko': '한국어',
    'en': 'English', 'es': 'Español', 'ru': 'Русский', 'ar': 'العربية',
  };
  static const delegates = <LocalizationsDelegate<dynamic>>[
    _ParkLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];
  static final _messages = <String, Map<String, String>>{};
  static final _templates = <({String key, RegExp pattern, List<String> params})>[];
  Locale locale;
  bool get isRtl => locale.languageCode == 'ar';

  static String localeKey(Locale locale) => locale.languageCode == 'zh'
      ? 'zh-${locale.scriptCode == 'Hant' ? 'Hant' : 'Hans'}'
      : locale.languageCode;

  static Locale? localeFromKey(String key) {
    for (final locale in supportedLocales) {
      if (localeKey(locale) == key) return locale;
    }
    return null;
  }

  /// Explicit script wins over country; Hong Kong, Macau and Taiwan use Hant.
  static Locale resolveLocale(Locale requested) {
    if (requested.languageCode == 'zh') {
      final traditional = requested.scriptCode == 'Hant' ||
          (requested.scriptCode == null && const {'TW', 'HK', 'MO'}.contains(requested.countryCode));
      return supportedLocales[traditional ? 1 : 0];
    }
    return supportedLocales.firstWhere(
      (locale) => locale.languageCode == requested.languageCode,
      orElse: () => const Locale('en'),
    );
  }

  static Locale resolveLocales(List<Locale>? requested) {
    for (final locale in requested ?? const <Locale>[]) {
      if (supportedLocales.any((supported) => supported.languageCode == locale.languageCode)) return resolveLocale(locale);
    }
    return const Locale('en');
  }

  Future<void> load() async {
    if (_messages.isNotEmpty) return;
    final loaded = await Future.wait(supportedLocales.map((locale) async {
      final key = localeKey(locale);
      final raw = jsonDecode(await rootBundle.loadString('assets/i18n/$key.json')) as Map<String, dynamic>;
      return MapEntry(key, raw.map((key, value) => MapEntry(key, value as String)));
    }));
    _messages.addEntries(loaded);
    for (final key in _messages['zh-Hans']!.keys) {
      final matches = RegExp(r'\{([A-Za-z][A-Za-z0-9_]*)\}').allMatches(key).toList();
      if (matches.isEmpty || RegExp(r'[㐀-鿿]').allMatches(key).length < 2) continue;
      final pattern = StringBuffer('^');
      var end = 0;
      for (final match in matches) {
        pattern.write(RegExp.escape(key.substring(end, match.start)));
        pattern.write(r'([\s\S]*?)');
        end = match.end;
      }
      pattern.write(RegExp.escape(key.substring(end)));
      pattern.write(r'$');
      _templates.add((key: key, pattern: RegExp(pattern.toString()), params: matches.map((match) => match.group(1)!).toList()));
    }
    // Prefer the most specific wording when two source error templates overlap.
    _templates.sort((a, b) => b.key.replaceAll(RegExp(r'\{[^}]+\}'), '').length.compareTo(a.key.replaceAll(RegExp(r'\{[^}]+\}'), '').length));
  }

  void setLocale(Locale value) => locale = resolveLocale(value);

  /// Used by tests to detect incomplete resources before shipping.
  Map<String, Set<String>> get missingTranslations {
    final base = _messages['zh-Hans']?.keys.toSet() ?? <String>{};
    return {
      for (final key in languageNames.keys)
        if (base.difference(_messages[key]?.keys.toSet() ?? {}).isNotEmpty)
          key: base.difference(_messages[key]?.keys.toSet() ?? {}),
    };
  }

  String translate(String message, [Map<String, Object?> params = const {}]) {
    var key = message;
    var values = params;
    // Built-in JavaScript errors arrive with interpolated values. Match only
    // application templates; callers never pass remote titles through tr().
    if (!(_messages['zh-Hans']?.containsKey(message) ?? false) && params.isEmpty) {
      for (final template in _templates) {
        final match = template.pattern.firstMatch(message);
        if (match == null) continue;
        key = template.key;
        values = {for (var i = 0; i < template.params.length; i++) template.params[i]: match.group(i + 1)};
        break;
      }
    }
    final translated = _messages[localeKey(locale)]?[key] ?? _messages['en']?[key] ?? key;
    return translated.replaceAllMapped(RegExp(r'\{([A-Za-z][A-Za-z0-9_]*)\}'), (match) {
      final key = match.group(1)!;
      return values.containsKey(key) ? '${values[key] ?? ''}' : match.group(0)!;
    });
  }

  static AppLocalizations of(BuildContext context) => Localizations.of<AppLocalizations>(context, AppLocalizations) ?? instance;
}

String tr(String message, [Map<String, Object?> params = const {}]) => AppLocalizations.instance.translate(message, params);

extension LocalizedContext on BuildContext {
  String tr(String message, [Map<String, Object?> params = const {}]) => AppLocalizations.of(this).translate(message, params);
}

class _ParkLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _ParkLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.any((supported) => supported.languageCode == locale.languageCode);
  @override
  Future<AppLocalizations> load(Locale locale) {
    final resolved = AppLocalizations.resolveLocale(locale);
    AppLocalizations.instance.setLocale(resolved);
    return SynchronousFuture(AppLocalizations._(resolved));
  }
  @override
  bool shouldReload(_ParkLocalizationsDelegate old) => false;
}
