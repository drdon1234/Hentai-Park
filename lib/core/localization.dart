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
  static final supportedLocales = languageNames.keys
      .map((key) {
        final parts = key.split('-');
        return Locale.fromSubtags(
          languageCode: parts.first,
          scriptCode: parts.length > 1 ? parts[1] : null,
        );
      })
      .toList(growable: false);
  static const languageNames = <String, String>{
    'zh-Hans': '简体中文',
    'zh-Hant': '繁體中文',
    'ja': '日本語',
    'ko': '한국어',
    'en': 'English',
    'es': 'Español',
    'ru': 'Русский',
    'ar': 'العربية',
  };
  static const delegates = <LocalizationsDelegate<dynamic>>[
    _ParkLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];
  static final _messages = <String, Map<String, String>>{};
  Locale locale;

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
      final traditional =
          requested.scriptCode == 'Hant' ||
          (requested.scriptCode == null &&
              const {'TW', 'HK', 'MO'}.contains(requested.countryCode));
      return supportedLocales[traditional ? 1 : 0];
    }
    return supportedLocales.firstWhere(
      (locale) => locale.languageCode == requested.languageCode,
      orElse: () => const Locale('en'),
    );
  }

  static Locale resolveLocales(List<Locale>? requested) {
    for (final locale in requested ?? const <Locale>[]) {
      if (supportedLocales.any(
        (supported) => supported.languageCode == locale.languageCode,
      )) {
        return resolveLocale(locale);
      }
    }
    return const Locale('en');
  }

  Future<void> load() async {
    if (_messages.isNotEmpty) return;
    final loaded = await Future.wait(
      supportedLocales.map((locale) async {
        final key = localeKey(locale);
        final raw = jsonDecode(
          await rootBundle.loadString('assets/i18n/$key.json'),
        ) as Map<String, dynamic>;
        return MapEntry(
          key,
          raw.map((key, value) => MapEntry(key, value as String)),
        );
      }),
    );
    _messages.addEntries(loaded);
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

  static final _placeholder = RegExp(r'\{([A-Za-z][A-Za-z0-9_]*)\}');

  /// Looks up an application message by its exact key.
  String translate(String message, [Map<String, Object?> params = const {}]) {
    final translated =
        _messages[localeKey(locale)]?[message] ??
        _messages['en']?[message] ??
        message;
    if (params.isEmpty) return translated;
    return translated.replaceAllMapped(_placeholder, (match) {
      final key = match.group(1)!;
      return params.containsKey(key) ? '${params[key] ?? ''}' : match.group(0)!;
    });
  }

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ?? instance;
}

String tr(String message, [Map<String, Object?> params = const {}]) =>
    AppLocalizations.instance.translate(message, params);

extension LocalizedContext on BuildContext {
  String tr(String message, [Map<String, Object?> params = const {}]) =>
      AppLocalizations.of(this).translate(message, params);
}

class _ParkLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _ParkLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.any(
    (supported) => supported.languageCode == locale.languageCode,
  );
  @override
  Future<AppLocalizations> load(Locale locale) {
    final resolved = AppLocalizations.resolveLocale(locale);
    AppLocalizations.instance.setLocale(resolved);
    return SynchronousFuture(AppLocalizations._(resolved));
  }

  @override
  bool shouldReload(_ParkLocalizationsDelegate old) => false;
}
