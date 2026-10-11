/// Title helpers shared by duplicate detection, migration and cross-source search.
library;

/// Innermost bracket groups (no other bracket inside), removed repeatedly to handle nesting.
final _innermost = RegExp(r'[\[\(【（{「『〔][^\[\(【（{「『〔\]\)】）}」』〕]*[\]\)】）}」』〕]');

/// Removes bracketed circle / translator / tag noise: "[Circle (Artist)] Title (Comic 100) [中国翻訳]" → "Title".
String searchableTitle(String title) {
  var s = title;
  for (var i = 0; i < 4; i++) {
    final next = s.replaceAll(_innermost, ' ');
    if (next == s) break;
    s = next;
  }
  final stripped = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return stripped.isEmpty ? title.trim() : stripped;
}

/// A comparison key: bracket noise removed, lower-cased, punctuation and whitespace dropped.
String normalizeTitle(String title) {
  final key = searchableTitle(title).toLowerCase().replaceAll(RegExp(r'[\s\p{P}\p{S}]+', unicode: true), '');
  return key.isEmpty ? title.toLowerCase().trim() : key;
}

const _cnDigits = {'零': 0, '〇': 0, '一': 1, '二': 2, '两': 2, '三': 3, '四': 4, '五': 5, '六': 6, '七': 7, '八': 8, '九': 9};

/// Parses simple Chinese numerals up to 9999 ("十二" → 12, "一百零五" → 105).
int? parseChineseNumber(String s) {
  if (s.isEmpty) return null;
  const units = {'十': 10, '百': 100, '千': 1000};
  var total = 0;
  var current = 0;
  for (final ch in s.split('')) {
    final d = _cnDigits[ch];
    if (d != null) {
      current = d;
      continue;
    }
    final u = units[ch];
    if (u == null) return null;
    total += (current == 0 ? 1 : current) * u;
    current = 0;
  }
  return total + current;
}

/// Extracts a chapter number from a chapter title ("第12话", "Ch. 3.5", "Vol.2 Ep 7", "第十二回").
/// Returns null when the title carries no number.
double? parseChapterNumber(String title) {
  final t = title.toLowerCase();
  final patterns = [
    RegExp(r'第\s*(\d+(?:\.\d+)?)\s*[话話章回集篇节節部]'),
    RegExp(r'(?:chapter|chap|ch|episode|ep|#)\.?\s*(\d+(?:\.\d+)?)'),
  ];
  for (final p in patterns) {
    final m = p.firstMatch(t);
    if (m != null) return double.tryParse(m.group(1)!);
  }
  final cn = RegExp(r'第\s*([零〇一二两三四五六七八九十百千]+)\s*[话話章回集篇节節部]').firstMatch(title);
  if (cn != null) return parseChineseNumber(cn.group(1)!)?.toDouble();
  // Fall back to the last number, ignoring volume markers like "vol.2".
  final cleaned = t.replaceAll(RegExp(r'(?:vol(?:ume)?|第\s*\d+\s*[卷册冊])\.?\s*\d+'), ' ');
  final all = RegExp(r'(\d+(?:\.\d+)?)').allMatches(cleaned).toList();
  if (all.isEmpty) return null;
  return double.tryParse(all.last.group(1)!);
}
