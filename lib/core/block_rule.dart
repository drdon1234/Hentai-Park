/// 屏蔽规则的本地语法；不依赖翻译服务和界面语言。
class BlockRule {
  BlockRule(String entry) : original = entry.trim() {
    var value = original;
    final separator = value.indexOf(':');
    if (separator >= 0 &&
        value.substring(0, separator).toLowerCase() != 'regex') {
      scope = value.substring(0, separator).trim().toLowerCase();
      value = value.substring(separator + 1).trim();
    }
    regex = value.toLowerCase().startsWith('regex:');
    text = regex ? value.substring(6) : value;
    wildcard = !regex && (text.contains('*') || text.contains('?'));
  }

  final String original;
  String scope = '';
  late final String text;
  late final bool regex;
  late final bool wildcard;
  bool get title => scope == 'title';
  bool get translatable => !regex && !wildcard && text.isNotEmpty;

  static String? error(String entry) {
    final rule = BlockRule(entry);
    if (rule.text.trim().isEmpty) return '请输入有效的屏蔽词';
    if (rule.original.length > 256) return '屏蔽规则不能超过 256 个字符';
    if (rule.regex) {
      try {
        RegExp(rule.text, caseSensitive: false);
      } on FormatException {
        return '正则表达式无效';
      }
    }
    if (rule.wildcard && rule.text.replaceAll(RegExp(r'[*?\s]'), '').isEmpty) {
      return '通配符规则必须包含具体文字';
    }
    return null;
  }

  String get _glob => text
      .split('')
      .map(
        (character) => switch (character) {
          '*' => r'[\s\S]*',
          '?' => r'[\s\S]',
          _ => RegExp.escape(character),
        },
      )
      .join();

  RegExp? pattern({required bool forTitle, bool preset = false}) {
    if (text.isEmpty) return null;
    final String expression;
    if (regex ||
        forTitle && preset && RegExp(r'[\[\]()+|\\^$]').hasMatch(text)) {
      expression = text;
    } else if (wildcard) {
      expression = forTitle ? _glob : '^$_glob\$';
    } else if (forTitle && RegExp(r'^[A-Za-z0-9 ]+$').hasMatch(text)) {
      expression = '(?<![A-Za-z0-9])${RegExp.escape(text)}(?![A-Za-z0-9])';
    } else if (forTitle && preset) {
      // 预设标题项本来允许直接填写正则；显式 regex: 同时适用于标签。
      expression = text;
    } else {
      expression = forTitle ? RegExp.escape(text) : '^${RegExp.escape(text)}\$';
    }
    try {
      return RegExp(expression, caseSensitive: false);
    } on FormatException {
      return regex ? null : RegExp(RegExp.escape(text), caseSensitive: false);
    }
  }

  String aliasEntry(String alias) => scope.isEmpty ? alias : '$scope:$alias';

  /// 仅合并已确认的同义词，不把一整个内容分组当作同义词。
  static const _synonyms = [
    ['incest', '乱伦', '亂倫', '近親相姦', '近亲相奸'],
    ['netorare', 'ntr', '寝取られ', '牛头人', '牛頭人'],
    ['futanari', 'futa', '扶她', '扶他', 'ふたなり', 'フタナリ'],
    ['yuri', '百合', 'ユリ'],
    ['lesbian', '女同', 'レズ', '蕾丝', '蕾絲'],
    ['yaoi', '耽美', 'やおい'],
    ['gay', '男同', 'ホモ'],
    ['furry', '福瑞'],
    ['kemono', '兽人', '獸人', 'ケモノ'],
    ['guro', 'グロ'],
    ['ryona', 'リョナ'],
    ['lolicon', 'loli', '萝莉', '蘿莉', 'ロリ'],
    ['shotacon', 'shota', '正太', 'ショタ'],
  ];

  List<String> get knownAliases {
    if (!translatable) return const [];
    final term = text.toLowerCase();
    return [
      for (final group in _synonyms)
        if (group.any((word) => word.toLowerCase() == term))
          for (final word in group)
            if (word.toLowerCase() != term) word,
    ];
  }
}
