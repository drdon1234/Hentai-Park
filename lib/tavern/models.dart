import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as image;

import 'worldbook_terms.dart';

/// 只读取标准卡片数据；扩展脚本和 HTML 都作为普通文本保留。
class TavernResource {
  TavernResource({required this.kind, required this.raw});

  final String kind;
  final Map<String, dynamic> raw;

  Map<String, dynamic> get data => kind == 'character' && raw['data'] is Map
      ? Map<String, dynamic>.from(raw['data'] as Map)
      : raw;
  Map? get _lorebookData {
    if (kind != 'lorebook') return null;
    if (raw['entries'] is List || raw['entries'] is Map) return raw;
    final nested = raw['data'];
    if (nested is Map &&
        (nested['entries'] is List || nested['entries'] is Map)) {
      return nested;
    }
    return raw;
  }

  String get name =>
      (kind == 'lorebook'
              ? (_lorebookData?['name'] ?? raw['name'])
              : data['name'] ?? '')
          .toString();
  String text(String key) => data[key] is String ? data[key] as String : '';
  List<String> get greetings => [
    if (text('first_mes').trim().isNotEmpty) text('first_mes'),
    if (data['alternate_greetings'] is List)
      for (final value in data['alternate_greetings'] as List)
        if (value is String && value.trim().isNotEmpty) value,
  ];

  List<TavernLoreEntry> get entries {
    final book = kind == 'lorebook' ? _lorebookData : data['character_book'];
    if (book is! Map) return const [];
    final value = book['entries'];
    final entries = value is List
        ? value
        : value is Map
        ? value.values.toList()
        : const [];
    return [
      for (final entry in entries)
        if (entry is Map) TavernLoreEntry(Map<String, dynamic>.from(entry)),
    ];
  }

  Map get bookSettings => kind == 'lorebook'
      ? (_lorebookData ?? raw)
      : data['character_book'] is Map
      ? data['character_book'] as Map
      : const {};

  bool get hasUnsupportedLore => entries.any((entry) => entry.unsupported);

  static TavernResource parse(String kind, String format, Uint8List bytes) {
    if (!{'character', 'lorebook'}.contains(kind) ||
        bytes.isEmpty ||
        bytes.length > 12 * 1024 * 1024) {
      throw const FormatException('酒馆资源格式无效');
    }
    Object? value;
    if (format == 'png' && kind == 'character') {
      try {
        final decoder = image.PngDecoder();
        final info = decoder.startDecode(bytes);
        if (info == null ||
            info.width <= 0 ||
            info.height <= 0 ||
            info.width * info.height > 40000000) {
          throw const FormatException();
        }
        final encoded =
            decoder.info.textData['ccv3'] ?? decoder.info.textData['chara'];
        if (encoded == null || encoded.length > 8 * 1024 * 1024) {
          throw const FormatException();
        }
        value = jsonDecode(utf8.decode(base64Decode(encoded)));
      } catch (_) {
        throw const FormatException('酒馆资源格式无效');
      }
    } else if (format == 'json') {
      try {
        value = jsonDecode(utf8.decode(bytes));
      } catch (_) {
        throw const FormatException('酒馆资源格式无效');
      }
    } else {
      throw const FormatException('酒馆资源格式无效');
    }
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw const FormatException('酒馆资源格式无效');
    }
    final resource = TavernResource(
      kind: kind,
      raw: Map<String, dynamic>.from(value),
    );
    if (kind == 'character' &&
        (resource.name.trim().isEmpty ||
            (resource.text('description').trim().isEmpty &&
                resource.text('personality').trim().isEmpty &&
                resource.greetings.isEmpty))) {
      throw const FormatException('酒馆资源格式无效');
    }
    if (kind == 'lorebook' && resource.entries.isEmpty) {
      throw const FormatException('酒馆资源格式无效');
    }
    return resource;
  }
}

class TavernLoreEntry {
  TavernLoreEntry(this.raw);
  final Map<String, dynamic> raw;
  Object? option(String key) =>
      raw[key] ??
      (raw['extensions'] is Map ? (raw['extensions'] as Map)[key] : null);
  int number(String key, int fallback) =>
      option(key) is num ? (option(key) as num).toInt() : fallback;
  bool get beforeCharacter =>
      option('position') == 'before_char' || option('position') == 0;
  bool get unsupported =>
      [
        ...keys,
        ...secondaryKeys,
      ].any((key) => key.startsWith('/') && key.lastIndexOf('/') > 0) ||
      (option('position') != null &&
          !{'before_char', 'after_char', 0, 1}.contains(option('position'))) ||
      [
        'sticky',
        'cooldown',
        'delay',
        'group',
        'use_regex',
        'excludeRecursion',
        'preventRecursion',
        'delayUntilRecursion',
        'matchPersonaDescription',
        'matchCharacterDescription',
        'matchCharacterPersonality',
        'matchCharacterDepthPrompt',
        'matchScenario',
        'matchCreatorNotes',
      ].any(
        (key) =>
            option(key) != null &&
            option(key) != false &&
            option(key) != 0 &&
            option(key) != '',
      );

  List<String> _strings(Object? value) => value is List
      ? value.whereType<String>().where((s) => s.trim().isNotEmpty).toList()
      : const [];
  List<String> get keys => _strings(raw['keys'] ?? raw['key']);
  List<String> get secondaryKeys => _strings(
    raw['secondary_keys'] ?? raw['keysecondary'] ?? raw['secondaryKeys'],
  );
  String get content =>
      raw['content'] is String ? raw['content'] as String : '';
  String get label =>
      (raw['comment'] ?? raw['name'] ?? keys.join(', ')).toString();
  bool get enabled => raw['enabled'] != false && raw['disable'] != true;
  bool get constant => raw['constant'] == true;
  bool get selective => raw['selective'] == true;
  int get order =>
      (raw['insertion_order'] as num?)?.toInt() ??
      (raw['order'] as num?)?.toInt() ??
      100;

  bool matches(String context, {WorldbookTerms? terms}) {
    if (!enabled || content.trim().isEmpty) return false;
    if (constant) return true;
    final caseSensitive =
        option('case_sensitive') == true || option('caseSensitive') == true;
    final whole =
        option('match_whole_words') == true ||
        option('matchWholeWords') == true;
    bool contains(String keyword) {
      final pattern = RegExp.escape(keyword.trim());
      if (pattern.isEmpty) return false;
      return RegExp(
        whole
            ? r'(?<![\p{L}\p{N}_])' + pattern + r'(?![\p{L}\p{N}_])'
            : pattern,
        caseSensitive: caseSensitive,
        unicode: true,
      ).hasMatch(context);
    }

    final dictionary = terms ?? WorldbookTerms.instance;
    bool containsAny(String keyword) =>
        dictionary.aliasesFor(keyword).any(contains);
    if (!keys.any(containsAny)) return false;
    // Chub/SillyTavern exports commonly keep `selective: true` while leaving
    // `secondary_keys` empty. An empty refinement list adds no restriction.
    if (!selective || secondaryKeys.isEmpty) return true;
    return switch (number('selectiveLogic', 0)) {
      1 => !secondaryKeys.every(containsAny),
      2 => !secondaryKeys.any(containsAny),
      3 => secondaryKeys.every(containsAny),
      _ => secondaryKeys.any(containsAny),
    };
  }
}

/// 只扫描最近的消息；固定条目与匹配词条按顺序受统一预算限制。
List<TavernLoreEntry> matchTavernLore(
  Iterable<TavernLoreEntry> entries,
  Iterable<String> messages, {
  int scanDepth = 4,
  int maxCharacters = 8000,
  bool recursive = false,
  int? tokenBudget,
  double Function()? random,
  WorldbookTerms? terms,
}) {
  final history = messages.toList();
  final pending = entries.toList();
  final baseContext = <int, String>{};
  String contextFor(TavernLoreEntry entry, String recursiveContext) {
    final depth = entry
        .number('scanDepth', entry.number('scan_depth', scanDepth))
        .clamp(0, 1000)
        .toInt();
    final context = baseContext.putIfAbsent(depth, () {
      return history
          .skip((history.length - depth).clamp(0, history.length))
          .join('\n');
    });
    return recursiveContext.isEmpty ? context : '$context\n$recursiveContext';
  }

  final result = <TavernLoreEntry>[];
  final decided = <TavernLoreEntry>{};
  var used = 0;
  var scan = '';
  for (var pass = 0; pass < (recursive ? 32 : 1); pass++) {
    final matched =
        pending
            .where(
              (e) =>
                  !decided.contains(e) &&
                  e.matches(contextFor(e, scan), terms: terms),
            )
            .toList()
          ..sort((a, b) {
            final constant = (b.constant ? 1 : 0).compareTo(a.constant ? 1 : 0);
            if (constant != 0) return constant;
            final priority = b
                .number('priority', 0)
                .compareTo(a.number('priority', 0));
            return priority != 0 ? priority : a.order.compareTo(b.order);
          });
    if (matched.isEmpty) break;
    for (final entry in matched) {
      decided.add(entry);
      if (entry.option('useProbability') == true &&
          (random ?? Random().nextDouble)() * 100 >=
              entry.number('probability', 100).clamp(0, 100)) {
        continue;
      }
      final cost = tokenBudget == null
          ? entry.content.length
          : estimateTavernTokens(entry.content);
      if (used + cost > (tokenBudget ?? maxCharacters)) continue;
      result.add(entry);
      used += cost;
    }
    scan = result.map((e) => e.content).join('\n');
  }
  result.sort((a, b) => a.order.compareTo(b.order));
  return result;
}

/// 无统一分词器的兼容接口采用 UTF-8 字节上界，宁可少发送历史。
int estimateTavernTokens(String text) => utf8.encode(text).length + 8;
