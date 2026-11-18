import { blockPresets } from './block-presets.js';

export type BlockableWork = {
  source?: unknown;
  workId?: unknown;
  id?: unknown;
  title?: unknown;
  summary?: unknown;
  authors?: unknown;
  author?: unknown;
  uploader?: unknown;
  tags?: unknown;
  previewOnly?: unknown;
  media?: unknown;
};

export type BlockSettings = {
  blockedWords?: unknown;
  blockedAuthors?: unknown;
  blockedWorks?: unknown;
  hidePreviews?: unknown;
  blockedTagAliases?: unknown;
  blockPresets?: unknown;
  blockedAuthorWorks?: unknown;
};

const strings = (value: unknown) =>
  Array.isArray(value) ? value.filter((v): v is string => typeof v === 'string') : [];
const escape = (value: string) => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/** Confirmed synonym groups synchronized with lib/core/block_rule.dart. */
const SYNONYM_GROUPS: readonly (readonly string[])[] = [
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

const KNOWN_NAMESPACES = new Set([
  'artist',
  'author',
  'character',
  'circle',
  'cosplayer',
  'female',
  'general',
  'group',
  'language',
  'location',
  'male',
  'meta',
  'mixed',
  'other',
  'parody',
  'reclass',
  'series',
  'tag',
]);

export interface ParsedBlockRule {
  original: string;
  scope: string;
  text: string;
  regex: boolean;
  wildcard: boolean;
  translatable: boolean;
  test: (candidate: string, forTitle?: boolean, preset?: boolean) => boolean;
}

export function validateBlockRule(input: string): string | null {
  const trimmed = input.trim();
  if (!trimmed) return '请输入有效的屏蔽词';
  if (trimmed.length > 256) return '屏蔽规则不能超过 256 个字符';
  let value = trimmed;
  const separator = value.indexOf(':');
  if (separator >= 0 && value.slice(0, separator).toLowerCase() !== 'regex') {
    value = value.slice(separator + 1).trim();
  }
  const regex = value.toLowerCase().startsWith('regex:');
  const text = regex ? value.slice(6) : value;
  if (!text.trim()) return '请输入有效的屏蔽词';
  if (regex) {
    try {
      new RegExp(text, 'iu');
    } catch {
      return '正则表达式无效';
    }
  } else if ((text.includes('*') || text.includes('?')) && !text.replace(/[*?\s]/g, '')) {
    return '通配符规则必须包含具体文字';
  }
  return null;
}

export function parseBlockRule(input: string): ParsedBlockRule {
  const err = validateBlockRule(input);
  if (err) throw new Error('INVALID_BLOCK_RULE');
  const original = input.trim();
  let value = original;
  let scope = '';
  const colon = value.indexOf(':');
  if (colon >= 0 && value.slice(0, colon).toLowerCase() !== 'regex') {
    scope = value.slice(0, colon).trim().toLowerCase();
    value = value.slice(colon + 1).trim();
  }
  const regex = value.toLowerCase().startsWith('regex:');
  const text = regex ? value.slice(6) : value;
  const wildcard = !regex && /[?*]/.test(text);
  const translatable = !regex && !wildcard && text.length > 0;
  const glob = wildcard
    ? Array.from(text)
        .map((c) => (c === '*' ? '[\\s\\S]*' : c === '?' ? '[\\s\\S]' : escape(c)))
        .join('')
    : '';

  const buildPattern = (forTitle: boolean, preset: boolean): RegExp | null => {
    if (!text || (forTitle && scope === 'tag')) return null;
    let expression: string;
    if (regex || (forTitle && preset && /[[\]()+|\\^$]/.test(text))) {
      expression = text;
    } else if (wildcard) {
      expression = forTitle ? glob : `^(?:${glob})$`;
    } else if (forTitle && /^[A-Za-z0-9 ]+$/.test(text)) {
      expression = `(?<![A-Za-z0-9])${escape(text)}(?![A-Za-z0-9])`;
    } else if (forTitle && preset) {
      expression = text;
    } else {
      expression = forTitle ? escape(text) : `^(?:${escape(text)})$`;
    }
    try {
      return new RegExp(expression, 'iu');
    } catch {
      return regex ? null : new RegExp(escape(text), 'iu');
    }
  };

  let tagRe: RegExp | null | undefined;
  let titleRe: RegExp | null | undefined;
  let presetTitleRe: RegExp | null | undefined;

  const test = (candidate: string, forTitle = false, preset = false) => {
    const compiled = forTitle
      ? preset
        ? (presetTitleRe ??= buildPattern(true, true))
        : (titleRe ??= buildPattern(true, false))
      : (tagRe ??= buildPattern(false, false));
    return compiled ? compiled.test(candidate) : false;
  };

  return { original, scope, text, regex, wildcard, translatable, test };
}

export function knownAliasesForRule(entry: string): string[] {
  try {
    const rule = parseBlockRule(entry);
    if (!rule.translatable) return [];
    const term = rule.text.toLowerCase();
    const out: string[] = [];
    for (const group of SYNONYM_GROUPS) {
      if (group.some((word) => word.toLowerCase() === term)) {
        for (const word of group) {
          if (word.toLowerCase() !== term && !out.includes(word)) out.push(word);
        }
      }
    }
    return out;
  } catch {
    return [];
  }
}

function normalizeWorkTags(rawTags: unknown): Array<{ label: string; namespace: string }> {
  if (!Array.isArray(rawTags)) return [];
  const rawList: Array<{ label: string; namespace: string; explicitNamespace: boolean }> = [];
  for (const tag of rawTags) {
    if (typeof tag === 'string') {
      rawList.push({ label: tag.trim(), namespace: '', explicitNamespace: false });
      continue;
    }
    if (!tag || typeof tag !== 'object') continue;
    const obj = tag as Record<string, unknown>;
    if ('tags' in obj && Array.isArray(obj.tags)) {
      const groupNs = typeof obj.namespace === 'string' ? obj.namespace.trim().toLowerCase() : '';
      for (const item of obj.tags) {
        if (typeof item === 'string') {
          rawList.push({ label: item.trim(), namespace: groupNs, explicitNamespace: Boolean(groupNs) });
        } else if (item && typeof item === 'object') {
          const rec = item as Record<string, unknown>;
          const label = String(rec.name ?? rec.label ?? '').trim();
          if (label) rawList.push({ label, namespace: groupNs, explicitNamespace: Boolean(groupNs) });
        }
      }
      continue;
    }
    const ns = typeof obj.namespace === 'string' ? obj.namespace.trim().toLowerCase() : '';
    const label = String(obj.label ?? obj.name ?? '').trim();
    if (label) rawList.push({ label, namespace: ns, explicitNamespace: Boolean(ns) });
  }

  return rawList.map((entry) => {
    if (entry.explicitNamespace) return { label: entry.label, namespace: entry.namespace };
    const colon = entry.label.indexOf(':');
    if (colon > 0) {
      const prefix = entry.label.slice(0, colon).trim().toLowerCase();
      if (KNOWN_NAMESPACES.has(prefix)) {
        return { label: entry.label.slice(colon + 1).trim(), namespace: prefix };
      }
    }
    return { label: entry.label, namespace: entry.namespace };
  });
}

export function matchWorkBlockReason(work: BlockableWork, settings: BlockSettings): string | null {
  const title = typeof work.title === 'string' ? work.title : '';
  const identity = String(work.workId ?? work.id ?? '');
  const source = String(work.source ?? '');

  if (
    strings(settings.blockedWorks).some(
      (v) => v === `${source}:${identity}` || v === JSON.stringify([source, identity]),
    )
  ) {
    return 'work';
  }

  const normalizedTags = normalizeWorkTags(work.tags);
  const tagAuthors = normalizedTags
    .filter((t) => t.namespace === 'artist' || t.namespace === 'author' || t.namespace === 'group')
    .map((t) => t.label);

  const authors = [
    ...strings(work.authors),
    ...(Array.isArray(work.authors)
      ? work.authors.flatMap((a) =>
          a && typeof a === 'object'
            ? typeof (a as Record<string, unknown>).name === 'string'
              ? [(a as Record<string, unknown>).name as string]
              : typeof (a as Record<string, unknown>).label === 'string'
                ? [(a as Record<string, unknown>).label as string]
                : []
            : [],
        )
      : []),
    ...(typeof work.author === 'string' ? [work.author] : []),
    ...(typeof work.uploader === 'string' ? [work.uploader] : []),
    ...tagAuthors,
  ]
    .map((a) => a.trim())
    .filter(Boolean);

  if (
    strings(settings.blockedAuthors).some((value) => {
      const target = value.toLocaleLowerCase();
      return authors.some(
        (author) =>
          author.toLocaleLowerCase() === target || `${source}:${author}`.toLocaleLowerCase() === target,
      );
    })
  ) {
    return 'author';
  }

  const authorWorks =
    settings.blockedAuthorWorks && typeof settings.blockedAuthorWorks === 'object'
      ? (settings.blockedAuthorWorks as Record<string, unknown>)
      : {};
  if (
    strings(settings.blockedAuthors).some((author) =>
      strings(authorWorks[author]).includes(`${source}:${identity}`),
    )
  ) {
    return 'author';
  }

  if (
    settings.hidePreviews === true &&
    (work.previewOnly === true ||
      (Array.isArray(work.media) &&
        work.media.length > 0 &&
        work.media.every((item) => item && typeof item === 'object' && (item as Record<string, unknown>).previewOnly === true)))
  ) {
    return 'preview';
  }

  const aliasMap =
    settings.blockedTagAliases && typeof settings.blockedTagAliases === 'object'
      ? (settings.blockedTagAliases as Record<string, unknown>)
      : {};

  const expandRule = (entry: string, aliases: Record<string, unknown>): string[] => {
    const rule = parseBlockRule(entry);
    const prefix = rule.scope ? `${rule.scope}:` : '';
    const extra = rule.translatable ? [...knownAliasesForRule(entry), ...strings(aliases[entry])] : strings(aliases[entry]);
    return [entry, ...new Set(extra.map((alias) => `${prefix}${alias}`))];
  };

  const tagEntries: string[] = [];
  for (const raw of strings(settings.blockedWords)) {
    try {
      for (const expanded of expandRule(raw, aliasMap)) tagEntries.push(expanded);
    } catch {
      // Ignore malformed legacy rule without crashing feed evaluation
    }
  }

  const presetTitleEntries: Array<{ label: string; entry: string }> = [];
  const presets =
    settings.blockPresets && typeof settings.blockPresets === 'object'
      ? (settings.blockPresets as Record<string, Record<string, unknown>>)
      : {};

  for (const preset of blockPresets) {
    const config = presets[preset.id];
    if (config?.on !== true) continue;
    const aliases = (config.aliases as Record<string, unknown>) ?? {};
    const baseEntries = Array.isArray(config.entries) ? strings(config.entries) : [...preset.entries];
    const strongEntries = config.strong
      ? Array.isArray(config.strongEntries)
        ? strings(config.strongEntries)
        : [...preset.strongEntries]
      : [];
    const activeRules = [...new Set([...baseEntries, ...strongEntries])];

    for (const entry of activeRules) {
      try {
        const rule = parseBlockRule(entry);
        if (rule.scope === 'title' && !config.title) continue;
        for (const expanded of expandRule(entry, aliases)) {
          const parsedExpanded = parseBlockRule(expanded);
          if (parsedExpanded.scope !== 'title') {
            tagEntries.push(parsedExpanded.scope ? expanded : `tag:${expanded}`);
          }
          if (config.title && parsedExpanded.scope !== 'tag') {
            presetTitleEntries.push({ label: `${preset.name}：${expanded}`, entry: expanded });
          }
        }
      } catch {
        // Ignore invalid custom preset entry
      }
    }
  }

  for (const { label, entry } of presetTitleEntries) {
    try {
      const rule = parseBlockRule(entry);
      if (rule.test(title, true, true)) return label;
    } catch {
      // Ignore
    }
  }

  for (const value of tagEntries) {
    try {
      const rule = parseBlockRule(value);
      switch (rule.scope) {
        case 'title':
          if (rule.test(title, true, false)) return rule.original;
          break;
        case 'author':
          if (authors.some((a) => rule.test(a))) return rule.original;
          break;
        case 'work':
          if (rule.test(identity) || rule.test(`${source}:${identity}`)) return rule.original;
          break;
        case 'source':
          if (rule.test(source)) return rule.original;
          break;
        case '':
        case 'tag':
          if (normalizedTags.some((t) => rule.test(t.label))) return rule.original;
          break;
        case 'all':
          if (rule.test(title, true, false) || normalizedTags.some((t) => rule.test(t.label))) {
            return rule.original;
          }
          break;
        default:
          if (normalizedTags.some((t) => t.namespace === rule.scope && rule.test(t.label))) {
            return rule.original;
          }
          break;
      }
    } catch {
      // Ignore
    }
  }

  return null;
}

export function isWorkBlocked(work: BlockableWork, settings: BlockSettings): boolean {
  return matchWorkBlockReason(work, settings) !== null;
}
