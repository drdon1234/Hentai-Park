import 'models.dart';
import 'localization.dart';
import 'settings.dart';

/// A ready-made group of tags users can switch on; all are off by default.
class BlockPreset {
  const BlockPreset(this.id, this._name, this.entries);
  final String id;
  final String _name;
  String get name => tr(_name);

  /// Matched against tags like ordinary blocklist entries; with title matching on, each entry is
  /// also a case-insensitive regular expression tested on the title (plain words match whole words).
  final List<String> entries;
}

const blockPresets = <BlockPreset>[
  BlockPreset('guro', '重口', ['guro', 'ryona', 'snuff', 'vore', 'necrophilia', 'scat', 'torture', '重口', '猎奇', '獵奇', 'グロ', 'リョナ']),
  BlockPreset('loli', '未成年女孩', ['lolicon', 'loli', 'toddlercon', '萝莉', '蘿莉', 'ロリ', '幼女']),
  BlockPreset('shota', '未成年男孩', ['shotacon', 'shota', '正太', 'ショタ']),
  BlockPreset('futa', '扶她', [
    'futanari',
    'futa',
    'dickgirl',
    'dickgirl on male',
    'male on dickgirl',
    'dickgirl on dickgirl',
    'dickgirl on female',
    'newhalf',
    '扶她',
    '扶他',
    '扶[上下]扶?',
    'ふたなり',
    'フタナリ',
  ]),
  BlockPreset('ntr', 'NTR', ['netorare', 'ntr', 'cheating', '寝取られ', '寝取り', '牛头人', '绿帽', '綠帽']),
  BlockPreset('incest', '乱伦', ['incest', 'inseki', '乱伦', '亂倫', '近親相姦', '近亲相奸', '近亲']),
  BlockPreset('gay', '男同性恋', ['yaoi', 'males only', 'gay', 'bara', 'bl', '耽美', '男同', '腐向', 'ボーイズラブ', 'ホモ']),
  BlockPreset('lesbian', '女同性恋', ['yuri', 'females only', 'lesbian', '百合', '女同', 'レズ', '蕾丝']),
  BlockPreset('furry', 'Furry', ['furry', 'kemono', 'anthro', '兽人', '獸人', '福瑞', 'ケモノ']),
];

/// A preset as configured by the user (enabled state, title matching, edited entries).
class BlockPresetConfig {
  BlockPresetConfig(this.preset, this.on, this.title, this.entries);
  final BlockPreset preset;
  final bool on;
  final bool title;
  final List<String> entries;

  static List<BlockPresetConfig> current() {
    final state = AppSettings.instance.blockPresetState;
    return [
      for (final p in blockPresets)
        () {
          final m = (state[p.id] as Map?) ?? const {};
          final entries = m['entries'] is List ? (m['entries'] as List).map((e) => e.toString()).toList() : p.entries;
          return BlockPresetConfig(p, m['on'] == true, m['title'] == true, entries);
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
  TagBlocklist(Iterable<String> entries, {this._titlePatterns = const []})
    : _entries = [for (final e in entries) e.trim().toLowerCase()].where((e) => e.isNotEmpty).toList();

  factory TagBlocklist.current() {
    final entries = [...AppSettings.instance.blockedTags];
    final patterns = <(String, RegExp)>[];
    for (final c in BlockPresetConfig.current()) {
      if (!c.on) continue;
      entries.addAll(c.entries.where((e) => !e.startsWith('title:')));
      if (c.title) {
        for (final e in c.entries) {
          final re = titleRegex(e);
          if (re != null) patterns.add(('${c.preset.name}：$e', re));
        }
      }
    }
    return TagBlocklist(entries, titlePatterns: patterns);
  }

  /// Title pattern for a preset entry: plain latin words match as whole words (so "ntr" does
  /// not hit "entry"); anything else is a regular expression, or a literal if it does not parse.
  static RegExp? titleRegex(String entry) {
    final e = entry.trim();
    if (e.isEmpty) return null;
    if (RegExp(r'^[A-Za-z0-9 ]+$').hasMatch(e)) return RegExp('(?<![A-Za-z0-9])${RegExp.escape(e)}(?![A-Za-z0-9])', caseSensitive: false);
    try {
      return RegExp(e, caseSensitive: false);
    } on FormatException {
      return RegExp(RegExp.escape(e), caseSensitive: false);
    }
  }

  final List<String> _entries;
  final List<(String, RegExp)> _titlePatterns;

  bool get isEmpty => _entries.isEmpty && _titlePatterns.isEmpty;

  static bool _tagMatches(String tag, String entry) {
    final t = tag.trim().toLowerCase();
    if (t == entry) return true;
    // Entry without namespace matches the tag part of a namespaced tag.
    if (!entry.contains(':')) {
      final i = t.lastIndexOf(':');
      return i >= 0 && t.substring(i + 1).trim() == entry;
    }
    return false;
  }

  /// The first entry matching [title] / [tags], or null.
  String? match({required String title, required Iterable<String> tags}) {
    if (isEmpty) return null;
    for (final (label, re) in _titlePatterns) {
      if (re.hasMatch(title)) return label;
    }
    final lowerTitle = title.toLowerCase();
    for (final e in _entries) {
      if (e.startsWith('title:')) {
        final word = e.substring(6).trim();
        if (word.isNotEmpty && lowerTitle.contains(word)) return e;
        continue;
      }
      for (final t in tags) {
        if (_tagMatches(t, e)) return e;
      }
    }
    return null;
  }

  String? matchItem(WorkItem item) => match(title: item.title, tags: item.tags);

  /// Detail pages know namespaces, so `namespace:tag` entries can match there too.
  List<String> matchDetail(WorkDetail d) {
    final tags = [
      for (final g in d.tagGroups)
        for (final t in g.tags) ...[t.name, if (g.namespace.isNotEmpty) '${g.namespace}:${t.name}'],
      ...d.tags,
    ];
    final hits = <String>{};
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
