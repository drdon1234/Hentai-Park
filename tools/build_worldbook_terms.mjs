import { readFile, writeFile, mkdir } from 'node:fs/promises';

const source = JSON.parse(await readFile('assets/tag_translations/ehentai/zh-Hans.json', 'utf8'));
const namespaces = new Set(['female', 'male', 'mixed', 'other', 'language', 'location', 'parody', 'reclass']);
const publicTerms = [
  'eldoria', 'shadowfang', 'glade', 'safe haven', 'refuge', 'beast',
  'monster', 'power', 'ability', 'magical forest', 'forest', 'magic',
];
const publicChinese = {
  eldoria: '埃尔多利亚', shadowfang: '暗影獠牙', glade: '林间空地',
  'safe haven': '安全庇护所', refuge: '避难所', beast: '野兽', monster: '怪物',
  power: '力量', ability: '能力', 'magical forest': '魔法森林', forest: '森林', magic: '魔法',
};
const locales = [
  ['zh-Hans', 'zh-CN'],
  ['zh-Hant', 'zh-TW'],
  ['ja', 'ja'],
  ['ko', 'ko'],
  ['en', 'en'],
  ['es', 'es'],
  ['ru', 'ru'],
  ['ar', 'ar'],
];

const terms = Object.entries(source.tags)
  .filter(([key]) => namespaces.has(key.split(':', 1)[0]))
  .map(([key, translation]) => ({
    key: key.slice(key.indexOf(':') + 1),
    translation,
  }))
  .filter(({ key, translation }) => key.trim() && translation.trim())
  .concat(publicTerms.map((key) => ({ key, translation: publicChinese[key] ?? key })))
  .filter((term, index, all) => all.findIndex((item) => item.key === term.key) === index)
  .sort((a, b) => b.key.length - a.key.length || a.key.localeCompare(b.key));

async function translateBatch(values, target) {
  const query = values.join('\n');
  const url = new URL('http://translate.google.com/translate_a/single');
  url.search = new URLSearchParams({ client: 'gtx', sl: 'auto', tl: target, dt: 't', q: query });
  const response = await fetch(url);
  if (!response.ok) throw new Error(`translation failed: HTTP ${response.status}`);
  const data = await response.json();
  const text = Array.isArray(data) && Array.isArray(data[0])
    ? data[0].map((part) => Array.isArray(part) ? String(part[0] ?? '') : '').join('')
    : '';
  const lines = text.split(/\\n|\r?\n/);
  if (lines.length !== values.length) {
    console.warn(`translation line count mismatch: ${lines.length}/${values.length}`, JSON.stringify(text).slice(0, 240));
    throw new Error(`translation line count mismatch: ${lines.length}/${values.length}`);
  }
  return lines;
}

async function translateAll(values, target) {
  const result = [];
  const batches = [];
  for (let i = 0; i < values.length;) {
    const batch = [];
    let size = 0;
    while (i + batch.length < values.length) {
      const value = values[i + batch.length];
      const next = size === 0 ? value.length : size + 1 + value.length;
      if (batch.length > 0 && next > 480) break;
      batch.push(value);
      size = next;
    }
    batches.push(batch);
    i += batch.length;
  }
  for (let i = 0; i < batches.length; i += 4) {
    const translated = await Promise.all(batches.slice(i, i + 4).map(async (batch) => {
      for (let attempt = 0; attempt < 3; attempt++) {
        try {
          return await translateBatch(batch, target);
        } catch (error) {
          if (attempt === 2) throw error;
          await new Promise((resolve) => setTimeout(resolve, 750 * (attempt + 1)));
        }
      }
      return [];
    }));
    result.push(...translated.flat());
    process.stdout.write(`\r${target}: ${result.length}/${values.length}`);
  }
  process.stdout.write('\n');
  return result;
}

await mkdir('assets/worldbook_terms', { recursive: true });
for (const [locale, target] of locales) {
  const translations = locale === 'zh-Hans'
    ? terms.map((term) => term.translation)
    : locale === 'en'
    ? terms.map((term) => term.key)
    : await translateAll(terms.map((term) => term.key), target);
  const output = {
    schema: 2,
    type: 'worldbook-terms',
    locale,
    version: '1.1.0',
    sources: ['EhTagTranslation/Database', 'ses-world/sillytavern-world/Eldoria.json'],
    terms: Object.fromEntries(terms.map((term, index) => [
      term.key,
      {
        translation: (translations[index] ?? term.key).trim() || term.key,
        aliases: [term.key, ...(locale === 'zh-Hans' ? [term.translation] : [])],
      },
    ])),
  };
  await writeFile(`assets/worldbook_terms/${locale}.json`, `${JSON.stringify(output)}\n`);
}
console.log(`generated ${terms.length} terms for ${locales.length} locales`);
