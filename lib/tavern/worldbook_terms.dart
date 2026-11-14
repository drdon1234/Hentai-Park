import 'dart:convert';

import 'package:flutter/services.dart';

import '../core/content_translation.dart';
import '../core/localization.dart';
import '../core/settings.dart';
import '../core/versions.dart';

/// 世界书术语包提供固定译名和关键词别名，不改写世界书原文或原始触发规则。
class WorldbookTerm {
  const WorldbookTerm({required this.translation, required this.aliases});
  final String translation;
  final List<String> aliases;
}

class WorldbookTermPack {
  WorldbookTermPack._(this.locale, this.version, this.terms);

  final String locale;
  final String version;
  final Map<String, WorldbookTerm> terms;

  static const maxBytes = 8 * 1024 * 1024;
  static const maxTerms = 100000;
  static const maxAliasesPerTerm = 16;

  static WorldbookTermPack parse(Object? data, {required String locale}) {
    if (data is! Map ||
        data['schema'] != 2 ||
        data['type'] != 'worldbook-terms' ||
        data['locale'] != locale ||
        data['version'] is! String ||
        !isReleaseVersion(data['version']) ||
        data['terms'] is! Map) {
      throw const FormatException('世界书术语包格式或语言不匹配');
    }
    final raw = data['terms'] as Map;
    if (raw.isEmpty || raw.length > maxTerms) {
      throw const FormatException('世界书术语数量无效');
    }
    final result = <String, WorldbookTerm>{};
    for (final entry in raw.entries) {
      if (entry.key is! String ||
          (entry.value is! Map && entry.value is! List)) {
        throw const FormatException('世界书术语格式无效');
      }
      final original = (entry.key as String).trim();
      if (original.isEmpty ||
          original.length > 256 ||
          original.contains('\n')) {
        throw const FormatException('世界书原始术语无效');
      }
      final value = entry.value is Map ? entry.value as Map : const {};
      final translation = value.isEmpty
          ? ''
          : value['translation'] is String
          ? (value['translation'] as String).trim()
          : '';
      final rawAliases = entry.value is List
          ? entry.value as List
          : value['aliases'] is List
          ? value['aliases'] as List
          : const [];
      if (translation.isEmpty || translation.length > 256) {
        throw const FormatException('世界书固定译名无效');
      }
      final aliases = <String>[];
      for (final value in rawAliases) {
        if (value is! String) throw const FormatException('世界书译词无效');
        final alias = value.trim();
        if (alias.isEmpty || alias.length > 256 || alias.contains('\n')) {
          throw const FormatException('世界书译词无效');
        }
        if (!aliases.contains(alias) && alias != original) aliases.add(alias);
      }
      if (aliases.length > maxAliasesPerTerm) {
        throw const FormatException('世界书译词数量无效');
      }
      final key = original.toLowerCase();
      if (result.containsKey(key)) throw const FormatException('世界书术语重复');
      result[key] = WorldbookTerm(
        translation: translation,
        aliases: List.unmodifiable(aliases),
      );
    }
    return WorldbookTermPack._(
      locale,
      data['version'] as String,
      Map.unmodifiable(result),
    );
  }

  List<String> aliasesFor(String original) {
    final term = terms[original.trim().toLowerCase()];
    if (term == null) return const [];
    final values = <String>{original, ...term.aliases, term.translation};
    return values.toList();
  }

  String? translationFor(String original) =>
      terms[original.trim().toLowerCase()]?.translation;
}

class WorldbookTerms {
  WorldbookTerms({Future<String> Function(String)? readAsset})
    : _readAsset = readAsset ?? ((String path) => rootBundle.loadString(path));

  static final instance = WorldbookTerms();
  final Future<String> Function(String) _readAsset;
  WorldbookTermPack? _pack;
  String? _loadedLocale;
  Future<void>? _loading;
  List<({String alias, String translation})> _rules = const [];

  WorldbookTermPack? get pack => _pack;

  Future<void> init() => ensureLoaded(
    AppLocalizations.localeKey(AppLocalizations.instance.locale),
  );

  Future<void> ensureLoaded(String locale) {
    if (_loadedLocale == locale && _pack != null) return Future.value();
    return _loading ??= () async {
      try {
        final text = await _readAsset('assets/worldbook_terms/$locale.json');
        if (utf8.encode(text).length > WorldbookTermPack.maxBytes) {
          throw const FormatException('世界书术语包过大');
        }
        _pack = WorldbookTermPack.parse(jsonDecode(text), locale: locale);
        final rules = <({String alias, String translation})>[];
        for (final entry in _pack!.terms.entries) {
          for (final alias in {entry.key, ...entry.value.aliases}) {
            rules.add((alias: alias, translation: entry.value.translation));
          }
        }
        rules.sort((a, b) => b.alias.length.compareTo(a.alias.length));
        _rules = List.unmodifiable(rules);
      } catch (_) {
        _pack = null;
        _rules = const [];
      }
      _loadedLocale = locale;
    }().whenComplete(() => _loading = null);
  }

  Iterable<String> aliasesFor(String original) sync* {
    yield* _pack?.aliasesFor(original) ?? [original];
  }

  String? translationFor(String original) => _pack?.translationFor(original);

  /// 术语和宏先替换成不可翻译占位符，机器翻译完成后恢复固定译名。
  Future<String?> translateText(String text, {String? locale}) async {
    final target =
        locale ?? AppLocalizations.localeKey(AppLocalizations.instance.locale);
    final protected = <String, String>{};
    var index = 0;
    var value = text.replaceAllMapped(RegExp(r'\{\{[^{}]{1,256}\}\}'), (match) {
      final token = '__WB_MACRO_${index}__';
      protected[token] = match.group(0)!;
      index++;
      return token;
    });
    var lowerValue = value.toLowerCase();
    var checked = 0;
    // 固定本次调用的规则快照，避免用户切换界面语言时混用两套术语。
    final rules = _rules;
    for (final rule in rules) {
      final lowerAlias = rule.alias.toLowerCase();
      if (!lowerValue.contains(lowerAlias)) continue;
      final pattern = RegExp(
        r'(?<![\p{L}\p{N}_])' +
            RegExp.escape(rule.alias) +
            r'(?![\p{L}\p{N}_])',
        caseSensitive: false,
        unicode: true,
      );
      var changed = false;
      value = value.replaceAllMapped(pattern, (match) {
        changed = true;
        final token = '__WB_TERM_${index}__';
        protected[token] = rule.translation;
        index++;
        return token;
      });
      if (changed) lowerValue = value.toLowerCase();
      if (++checked % 128 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (!AppSettings.instance.autoTranslateContent ||
        !isTranslatableContent(value)) {
      var restored = value;
      for (final entry in protected.entries) {
        restored = restored.replaceAll(entry.key, entry.value);
      }
      return restored;
    }
    final chunks = <String>[];
    var remaining = value;
    while (remaining.length > ContentTranslationQueue.maxTextLength) {
      var split = remaining.lastIndexOf(
        '\n',
        ContentTranslationQueue.maxTextLength,
      );
      if (split < 128) split = ContentTranslationQueue.maxTextLength;
      for (final match in RegExp(r'__WB_[A-Z]+_\d+__').allMatches(remaining)) {
        if (match.start < split && match.end > split && match.start >= 128) {
          split = match.start;
          break;
        }
      }
      chunks.add(remaining.substring(0, split));
      remaining = remaining.substring(split);
    }
    if (remaining.isNotEmpty) chunks.add(remaining);
    final translatedChunks = <String>[];
    for (final chunk in chunks) {
      final translated = await ContentTranslationQueue.instance.request(
        chunk,
        target,
        AppSettings.instance.translateEngine,
      );
      if (translated == null || translated.trim().isEmpty) return null;
      translatedChunks.add(translated);
    }
    var restored = translatedChunks.join();
    if (protected.keys.any((token) => !restored.contains(token))) return null;
    for (final entry in protected.entries) {
      restored = restored.replaceAll(entry.key, entry.value);
    }
    return restored;
  }
}
