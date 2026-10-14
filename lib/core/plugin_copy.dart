import 'localization.dart';

/// A source plugin's own translations (manifest `i18n`: `{locale: {Chinese text: translation}}`).
/// Plugin copy is looked up here first and then in the app's shared vocabulary, so adding or
/// changing a site never touches the app's language files.
class PluginCopy {
  PluginCopy(Object? i18n) : _byLocale = _parse(i18n);

  /// Copy for text that does not come from a plugin.
  static final none = PluginCopy(null);

  final Map<String, Map<String, String>> _byLocale;

  static Map<String, Map<String, String>> _parse(Object? value) {
    if (value is! Map) return const {};
    return {
      for (final e in value.entries)
        if (e.key is String && e.value is Map)
          e.key as String: {
            for (final t in (e.value as Map).entries)
              if (t.key is String && t.value is String)
                t.key as String: t.value as String,
          },
    };
  }

  static final _placeholder = RegExp(r'\{([A-Za-z][A-Za-z0-9_]*)\}');

  String? _lookup(String key) {
    final locale = AppLocalizations.localeKey(AppLocalizations.instance.locale);
    return _byLocale[locale]?[key] ??
        (locale == 'zh-Hans' ? null : _byLocale['en']?[key]);
  }

  /// Whether the plugin declares copy for [key] (its fixed source text).
  bool has(String key) => _byLocale.values.any((copy) => copy.containsKey(key));

  /// Translates plugin text by its Chinese source string.
  String text(String key, [Map<String, Object?> params = const {}]) {
    final value = _lookup(key);
    if (value == null) return tr(key, params);
    if (params.isEmpty) return value;
    return value.replaceAllMapped(_placeholder, (m) {
      final name = m.group(1)!;
      return params.containsKey(name) ? '${params[name] ?? ''}' : m.group(0)!;
    });
  }
}
