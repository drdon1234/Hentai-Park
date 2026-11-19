import 'dart:convert';

import 'models.dart';

(TavernResource, Map<String, (String, Object?)>) reviewTavernProposal(
  TavernResource generated,
  TavernResource? baseline,
  Set<String> omitted,
) {
  final raw = jsonDecode(
    jsonEncode(baseline?.raw ?? TavernResource.blank(generated.kind)),
  ) as Map<String, dynamic>;
  final target = (raw['data'] ?? raw) as Map<String, dynamic>;
  final next = generated.data;
  final changes = <String, (String, Object?)>{};
  void fields(Map target, Map source, String prefix, Set<String> skip) {
    for (final e in source.entries) {
      if (skip.contains(e.key) ||
          jsonEncode(target[e.key]) == jsonEncode(e.value)) {
        continue;
      }
      final id = '$prefix${e.key}';
      final value = e.key == 'extensions'
          ? {...?target[e.key] as Map?, ...?e.value as Map?}
          : e.value;
      changes[id] = (e.key.toString(), value);
      if (!omitted.contains(id)) target[e.key] = value;
    }
  }

  final character = generated.kind == 'character';
  fields(target, next, 'field:', {character ? 'character_book' : 'entries'});
  final incoming = character ? next['character_book'] : next;
  if (incoming is Map) {
    final book = character
        ? Map<String, dynamic>.from(target['character_book'] as Map? ?? {})
        : target;
    if (character) fields(book, incoming, 'book:', {'entries'});
    final rows = List.of(book['entries'] as List? ?? []), old = List.of(rows);
    final used = <int>{};
    for (final (i, value) in (incoming['entries'] as List).indexed) {
      final entry = value as Map;
      int? prior;
      for (final key in ['uid', 'id', 'comment', 'name']) {
        if (entry[key] == null || entry[key] == '') continue;
        prior = old.indexed
            .where(
              (pair) => !used.contains(pair.$1) && pair.$2[key] == entry[key],
            )
            .firstOrNull
            ?.$1;
        if (prior != null) break;
      }
      if (prior != null) used.add(prior);
      final previous = prior == null ? <dynamic, dynamic>{} : old[prior] as Map;
      final merged = {
        ...previous,
        ...entry,
        'extensions': {
          ...?previous['extensions'] as Map?,
          ...?entry['extensions'] as Map?,
        },
      };
      if (jsonEncode(previous) == jsonEncode(merged)) continue;
      final id = 'entry:$i';
      changes[id] = (
        (entry['comment'] ?? entry['name'] ?? entry['content'] ?? i).toString(),
        merged,
      );
      if (omitted.contains(id)) continue;
      if (prior == null) {
        rows.add(merged);
      } else {
        rows[prior] = merged;
      }
    }
    if (!character || rows.isNotEmpty || target.containsKey('character_book')) {
      book['entries'] = rows;
      if (character) target['character_book'] = book;
    }
  }
  return (TavernResource(kind: generated.kind, raw: raw), changes);
}
