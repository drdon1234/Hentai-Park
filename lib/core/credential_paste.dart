/// Parses pasted login text into a source's account fields.
///
/// Accepts the formats people actually paste:
/// - key/value text for cookie logins, with any separators or none at all:
///   `ipb_member_id: 123 ipb_pass_hash=abc; igneous: x` and even `ipb_member_id: 123ipb_pass_hash: abc`
/// - a raw `Cookie:` header (`a=1; b=2`)
/// - `user/password`, `user:password`, `user password` or two lines for password logins
Map<String, String> parsePastedCredentials(String text, List<String> fieldKeys, {required bool cookies}) {
  final input = text.trim();
  if (input.isEmpty || fieldKeys.isEmpty) return {};
  final keyed = _parseKeyed(input, fieldKeys);
  if (keyed.isNotEmpty || cookies) return keyed;
  return _parsePair(input, fieldKeys);
}

/// Finds every `key[:=]` occurrence; a value runs until a separator or the next known key.
Map<String, String> _parseKeyed(String input, List<String> keys) {
  final hits = <(int start, int valueStart, String key)>[];
  for (final key in keys) {
    final m = RegExp('${RegExp.escape(key)}\\s*[:=]\\s*', caseSensitive: false).firstMatch(input);
    if (m != null) hits.add((m.start, m.end, key));
  }
  hits.sort((a, b) => a.$1.compareTo(b.$1));
  final out = <String, String>{};
  for (var i = 0; i < hits.length; i++) {
    final end = i + 1 < hits.length ? hits[i + 1].$1 : input.length;
    final raw = input.substring(hits[i].$2, end);
    final value = raw.split(RegExp(r'[\s;,]')).firstWhere((s) => s.isNotEmpty, orElse: () => '').replaceAll(RegExp('^["\']|["\']\$'), '');
    if (value.isNotEmpty) out[hits[i].$3] = value;
  }
  return out;
}

/// `user/pass`, `user:pass`, `user pass` or two lines → the first two fields, split at the first separator
/// (passwords may themselves contain separators).
Map<String, String> _parsePair(String input, List<String> keys) {
  if (keys.length < 2) return {keys.first: input};
  final lines = input.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.length >= 2) return {keys[0]: lines[0], keys[1]: lines[1]};
  final m = RegExp(r'^(\S+?)\s*[/:：\s]\s*(\S.*)$').firstMatch(input);
  if (m == null) return {};
  return {keys[0]: m.group(1)!, keys[1]: m.group(2)!.trim()};
}
