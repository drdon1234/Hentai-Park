import 'package:flutter/foundation.dart';

import 'block_rule.dart';
import 'localization.dart';
import 'models.dart';
import 'settings.dart';

/// A ready-made group of tags users can switch on; all are off by default.
class BlockPreset {
  const BlockPreset(
    this.id,
    this._name,
    this.entries, {
    this.strongEntries = const [],
  });
  final String id;
  final String _name;
  String get name => tr(_name);

  /// tag: 仅匹配标签；title: 仅匹配标题；其余规则可随开关匹配标题。
  /// 英文变体正则显式限制词边界，防止缩写命中普通单词。
  final List<String> entries;
  final List<String> strongEntries;
}

const blockPresets = <BlockPreset>[
  BlockPreset('ai', 'AI 生成', [
    'tag:ai',
    r'regex:(?<![A-Za-z0-9])ai[ _-]?(?:generated|art|cg)(?![A-Za-z0-9])',
    'regex:AI[ _-]?(?:生成|绘画|繪畫|作画|作畫|イラスト)',
    'ai_generated',
    '生成AI',
  ]),
  BlockPreset('guro', '重口', [
    'guro',
    'ryona',
    'snuff',
    'vore',
    'gore',
    r'regex:(?<![A-Za-z0-9])necrophili(?:a|ac)(?![A-Za-z0-9])',
    'scat',
    'torture',
    'dismemberment',
    '重口',
    'regex:[猎獵]奇',
    'regex:死[奸姦]',
    'regex:肢[体體]切[断斷]',
    'グロ',
    'リョナ',
  ]),
  BlockPreset('loli', '未成年女孩', [
    r'regex:(?<![A-Za-z0-9])loli(?:[ _-]?con)?(?![A-Za-z0-9])',
    'toddlercon',
    'regex:[萝蘿]莉',
    'regex:ロリ(?:コン)?',
    'regex:로리(?:콘)?',
    '幼女',
  ]),
  BlockPreset('shota', '未成年男孩', [
    r'regex:(?<![A-Za-z0-9])shota(?:[ _-]?con)?(?![A-Za-z0-9])',
    'shota',
    '正太',
    'regex:ショタ(?:コン)?',
    'regex:쇼타(?:콘)?',
  ]),
  BlockPreset('futa', '扶她', [
    r'regex:(?<![A-Za-z0-9])futa(?:nari)?(?![A-Za-z0-9])',
    r'regex:(?<![A-Za-z0-9])dick[ _-]?girl(?![A-Za-z0-9])',
    'regex:扶[她他]',
    r'tag:regex:^扶[上下]扶?$',
    'regex:(?:ふたなり|フタナリ)',
    '후타나리',
    'dickgirl',
  ]),
  BlockPreset('ntr', 'NTR', [
    'netorare',
    'netori',
    'ntr',
    'cheating',
    r'regex:(?<![A-Za-z0-9])cuckold(?:ing)?(?![A-Za-z0-9])',
    '寝取られ',
    '寝取り',
    'regex:牛[头頭]人',
    'regex:[绿綠]帽',
    'regex:出[轨軌]',
    'regex:네토(?:라레|리)',
  ]),
  BlockPreset(
    'incest',
    '乱伦',
    [
      r'regex:(?<![A-Za-z0-9])incest(?:uous)?(?![A-Za-z0-9])',
      'inseki',
      'regex:[乱亂][伦倫]',
      r'tag:regex:^近[亲親]$',
      'regex:近[亲親]相[奸姦]',
      '근친',
    ],
    strongEntries: [
      '母子',
      '母女',
      '父女',
      '父子',
      '兄妹',
      '姐弟',
      '姉弟',
      '*妈',
      '*媽',
      '*母',
      '*父',
      '父亲',
      '父親',
      '兄弟姐妹',
      '母亲',
      '母親',
      '兄弟',
      '姐妹',
      '姉妹',
      'mother',
      'father',
      'brother',
      'sister',
      'siblings',
    ],
  ),
  BlockPreset(
    'gay',
    '男同性恋',
    [
      'yaoi',
      'gay',
      'bara',
      '耽美',
      'regex:男同(?:性[恋戀])?(?![学學事])',
      'ボーイズラブ',
      'ホモ',
      r"regex:(?<![A-Za-z0-9])boys?['’]?[ _-]+love(?![A-Za-z0-9])",
      '게이',
      'tag:bl',
      'tag:腐向',
    ],
    strongEntries: [
      r'regex:(?<![A-Za-z0-9])males?[ _-]+only(?![A-Za-z0-9])',
      'title:bl',
      'title:腐向',
    ],
  ),
  BlockPreset(
    'lesbian',
    '女同性恋',
    [
      'tag:yuri',
      'tag:百合',
      'lesbian',
      'regex:女同(?:性[恋戀])?(?![学學事])',
      'regex:レズ(?:ビアン)?',
      r'tag:regex:^蕾[丝絲]$',
      'ガールズラブ',
      r"regex:(?<![A-Za-z0-9])girls?['’]?[ _-]+love(?![A-Za-z0-9])",
      '레즈비언',
    ],
    strongEntries: [
      r'regex:(?<![A-Za-z0-9])females?[ _-]+only(?![A-Za-z0-9])',
      'title:百合',
      'title:yuri',
    ],
  ),
  BlockPreset('furry', 'Furry', [
    r'regex:(?<![A-Za-z0-9])furr(?:y|ies)(?![A-Za-z0-9])',
    'kemono',
    r'regex:(?<![A-Za-z0-9])anthro(?:pomorphic)?(?![A-Za-z0-9])',
    'regex:[兽獸獣][人控]',
    '福瑞',
    'ケモノ',
  ]),
];

/// A preset as configured by the user (enabled state, title matching, edited entries).
class BlockPresetConfig {
  BlockPresetConfig(
    this.preset,
    this.on,
    this.title,
    this.entries,
    this.aliases,
    this.strong, {
    this.strongEntries = const [],
  });
  final BlockPreset preset;
  final bool on;
  final bool title;
  final bool strong;
  final List<String> entries;
  final List<String> strongEntries;
  bool get hasStrongRules => strongEntries.isNotEmpty;
  List<String> get allEntries => {...entries, ...strongEntries}.toList();
  List<String> get activeEntries => !on
      ? []
      : {
          ...entries,
          if (strong) ...strongEntries,
        }.where((e) => title || !BlockRule(e).title).toList();
  List<String> get activeTagEntries =>
      activeEntries.where((e) => !BlockRule(e).title).toList();
  List<String> get activeTitleEntries =>
      title ? activeEntries.where((e) => !BlockRule(e).tagOnly).toList() : [];
  final Map<String, List<String>> aliases;
  List<String> aliasesFor(String entry) => aliases[entry] ?? const [];

  static List<BlockPresetConfig> current() {
    final state = AppSettings.instance.blockPresetState;
    return [
      for (final p in blockPresets)
        () {
          final m = (state[p.id] as Map?) ?? const {};
          final entries = m['entries'] is List
              ? (m['entries'] as List).map((e) => e.toString()).toList()
              : p.entries;
          return BlockPresetConfig(
            p,
            m['on'] == true,
            m['title'] == true,
            entries
                .where(
                  (e) =>
                      m['strongEntries'] is List ||
                      !p.strongEntries.contains(e),
                )
                .toSet()
                .toList(),
            {
              for (final e in (m['aliases'] as Map? ?? {}).entries)
                e.key as String: List<String>.from(e.value as List),
            },
            m['strong'] == true,
            strongEntries:
                (m['strongEntries'] is List
                        ? List<String>.from(m['strongEntries'] as List)
                        : p.strongEntries)
                    .toSet()
                    .toList(),
          );
        }(),
    ];
  }
}

/// Hides works carrying blocked tags (EhViewer-style tag filtering).
///
/// Entry syntax (case-insensitive):
/// - `tag` matches that tag in any namespace ("guro" matches "female:guro" and "guro")
/// - `namespace:tag` matches only within the namespace ("female:guro")
/// - `title:word` matches works whose title contains the word
class TagBlocklist {
  // 列表常省略标签；复用本次运行已读取的详情，避免逐条联网补标签。
  static final _known = <String, WorkItem>{};
  static final _metadataRevision = ValueNotifier<int>(0);
  static final Listenable changes = Listenable.merge([
    AppSettings.instance.watch(AppSettings.filterKeys),
    _metadataRevision,
  ]);
  static void remember(WorkDetail detail) {
    final item = WorkItem({
      'id': detail.id,
      'title': detail.title,
      'tags': detail.tags,
      'authors': authorsOf(detail),
    }, detail.source);
    final previous = _known[item.uid];
    if (previous?.title == item.title &&
        listEquals(previous?.tags, item.tags) &&
        listEquals(previous?.authors, item.authors)) {
      return;
    }
    _known.remove(item.uid);
    _known[item.uid] = item;
    if (_known.length > 512) _known.remove(_known.keys.first);
    _metadataRevision.value++;
  }

  static void forgetSource(String source) {
    _known.removeWhere((_, item) => item.source == source);
    _metadataRevision.value++;
  }

  TagBlocklist(Iterable<String> entries, {this._titlePatterns = const []})
    : _entries = [for (final e in entries) e.trim()]
          .where((e) => e.isNotEmpty)
          .toList() {
    for (final entry in _entries) {
      final rule = BlockRule(entry);
      _rules.add((rule, rule.pattern(forTitle: rule.title)));
    }
  }

  factory TagBlocklist.current() {
    final settings = AppSettings.instance;
    final entries = <String>[];
    for (final entry in settings.blockedTags) {
      final rule = BlockRule(entry);
      entries.add(entry);
      if (rule.translatable) {
        entries.addAll(settings.aliasesFor(entry).map(rule.aliasEntry));
      }
    }
    final patterns = <(String, RegExp)>[];
    for (final c in BlockPresetConfig.current()) {
      if (!c.on) continue;
      Iterable<String> expand(Iterable<String> rules) sync* {
        for (final entry in rules) {
          yield entry;
          yield* c.aliasesFor(entry).map(BlockRule(entry).aliasEntry);
        }
      }

      entries.addAll(expand(c.activeTagEntries));
      for (final e in expand(c.activeTitleEntries)) {
        final re = titleRegex(e);
        if (re != null) patterns.add(('${c.preset.name}：$e', re));
      }
    }

    return TagBlocklist(entries, titlePatterns: patterns);
  }

  /// Title pattern for a preset entry: plain latin words match as whole words (so "ntr" does
  /// not hit "entry"); anything else is a regular expression, or a literal if it does not parse.
  static RegExp? titleRegex(String entry) {
    return BlockRule(entry).pattern(forTitle: true, preset: true);
  }

  final List<String> _entries;
  final _rules = <(BlockRule, RegExp?)>[];
  final List<(String, RegExp)> _titlePatterns;

  bool get isEmpty => _entries.isEmpty && _titlePatterns.isEmpty;

  static bool _tagMatches(String tag, BlockRule rule, RegExp? pattern) {
    if (pattern == null) return false;
    final t = tag.trim();
    final i = t.indexOf(':');
    if (rule.scope.isNotEmpty && !rule.tagOnly) {
      return i >= 0 &&
          t.substring(0, i).trim().toLowerCase() == rule.scope &&
          pattern.hasMatch(t.substring(i + 1).trim());
    }
    return pattern.hasMatch(i < 0 ? t : t.substring(i + 1).trim());
  }

  /// The first entry matching [title] / [tags], or null.
  String? match({required String title, required Iterable<String> tags}) {
    if (isEmpty) return null;
    for (final (label, re) in _titlePatterns) {
      if (re.hasMatch(title)) return label;
    }
    for (final (rule, pattern) in _rules) {
      final label = rule.regex ? rule.original : rule.original.toLowerCase();
      if (rule.title) {
        if (pattern?.hasMatch(title) == true) return label;
        continue;
      }
      for (final t in tags) {
        if (_tagMatches(t, rule, pattern)) return label;
      }
    }
    return null;
  }

  static List<String> authorsOf(WorkItem item) => {
    ...item.authors,
    if (item.json['uploader'] is String) item.json['uploader'] as String,
    if (item.json['author'] is String) item.json['author'] as String,
    if (item is WorkDetail)
      ...item.tagGroups
          .where((g) => {'artist', 'author', 'group'}.contains(g.namespace))
          .expand((g) => g.tags.map((t) => t.name)),
  }.map((v) => v.trim()).where((v) => v.isNotEmpty).toList();

  String? matchItem(WorkItem item) {
    final known = item is WorkDetail ? null : _known[item.uid];
    final settings = AppSettings.instance;
    if (settings.blockedWorks.containsKey(item.uid)) return tr('已屏蔽作品');
    if (settings.isBlockedAuthorWork(item) ||
        {...authorsOf(item), if (known != null) ...authorsOf(known)}.any(
          (a) => settings.blockedAuthors.containsKey(
            '${item.source}:${a.toLowerCase()}',
          ),
        )) {
      return tr('已屏蔽作者');
    }
    return match(title: item.title, tags: {...item.tags, ...?known?.tags}) ??
        (known == null ? null : match(title: known.title, tags: known.tags));
  }

  /// Detail pages know namespaces, so `namespace:tag` entries can match there too.
  List<String> matchDetail(WorkDetail d) {
    final tags = [
      for (final g in d.tagGroups)
        for (final t in g.tags) ...[
          t.name,
          if (g.namespace.isNotEmpty) '${g.namespace}:${t.name}',
        ],
      ...d.tags,
    ];
    final hits = <String>{};
    final identity = matchItem(d);
    if (identity != null) hits.add(identity);
    for (final (label, re) in _titlePatterns) {
      if (re.hasMatch(d.title)) hits.add(label);
    }
    for (final e in _entries) {
      final m = TagBlocklist([e]).match(title: d.title, tags: tags);
      if (m != null) hits.add(m);
    }
    return hits.toList();
  }
}
