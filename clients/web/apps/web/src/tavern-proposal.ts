type Row = Record<string, unknown>;
const object = (value: unknown): Row =>
  value && typeof value === 'object' && !Array.isArray(value) ? (value as Row) : {};
const entryKeys = (row: Row) =>
  [row.uid ?? row.id, row.comment ?? row.name].map((v, i) =>
    v === undefined || v === '' ? '' : i + ':' + String(v),
  );
export function reviewProposal(original: Row, proposed: Row, character: boolean, omitted: Set<string>) {
  const result = structuredClone(original),
    body = object(result.data ?? result),
    incoming = object(proposed.data ?? proposed);
  const changes: { key: string; label: string; value: unknown; sharedKeys?: string[] }[] = [];
  function applyFields(target: Row, source: Row, prefix: string, skip: string[]) {
    for (const [key, value] of Object.entries(source)) {
      if (skip.includes(key) || JSON.stringify(target[key]) === JSON.stringify(value)) continue;
      const next = key === 'extensions' ? { ...object(target[key]), ...object(value) } : value;
      const id = prefix + key;
      changes.push({ key: id, label: key, value: next });
      if (!omitted.has(id)) target[key] = structuredClone(next);
    }
  }
  applyFields(body, incoming, 'field:', character ? ['character_book'] : ['entries']);
  const from = character ? object(incoming.character_book) : incoming;
  if (!from.entries) return { result, changes };
  const book = character ? object(body.character_book) : body;
  if (character) applyFields(book, from, 'book:', ['entries']);
  const container = (book.entries ?? []) as Row[] | Record<string, Row>,
    existing = Object.entries(container),
    used = new Set<string>();
  for (const [index, raw] of Object.entries(from.entries)) {
    const entry = object(raw),
      keys = entryKeys(entry);
    const prior = keys
      .filter(Boolean)
      .map((key) => existing.find(([id, row]) => !used.has(id) && entryKeys(row).includes(key)))
      .find(Boolean);
    if (prior) used.add(prior[0]);
    const value = { ...prior?.[1], ...entry };
    if (prior?.[1].extensions || entry.extensions)
      value.extensions = { ...object(prior?.[1].extensions), ...object(entry.extensions) };
    if (prior && JSON.stringify(prior[1]) === JSON.stringify(value)) continue;
    const id = 'entry:' + index;
    changes.push({
      key: id,
      label: String(entry.comment ?? entry.name ?? entry.content ?? index),
      value,
    });
    if (omitted.has(id)) continue;
    if (prior) (container as Record<string, Row>)[prior[0]] = value;
    else if (Array.isArray(container)) container.push(value);
    else {
      let n = 0;
      while (String(n) in container) n++;
      container[String(n)] = value;
    }
  }
  const frequency = new Map<string, number>();
  function keywords(entry: Row) {
    const raw = entry.keys ?? entry.key;
    return new Set(
      Array.isArray(raw)
        ? raw
            .filter((k): k is string => typeof k === 'string')
            .map((k) => k.trim().toLowerCase())
            .filter(Boolean)
        : [],
    );
  }
  for (const row of Object.values(container)) {
    for (const key of keywords(row)) frequency.set(key, (frequency.get(key) ?? 0) + 1);
  }
  for (const change of changes) {
    if (change.key.startsWith('entry:') && !omitted.has(change.key))
      change.sharedKeys = [...keywords(object(change.value))].filter(
        (key) => (frequency.get(key) ?? 0) > 1,
      );
  }
  if (!character || Object.keys(container).length || body.character_book) {
    book.entries = container;
    if (character) body.character_book = book;
  }
  return { result, changes };
}
