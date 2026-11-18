import { readdir, readFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const windowsRoot = resolve(scriptDir, '..');
const repoRoot = resolve(windowsRoot, '../..');
const languages = ['zh-Hans', 'zh-Hant', 'ja', 'ko', 'en', 'es', 'ru', 'ar'];

const placeholders = (value) => [...new Set(String(value).match(/\{\w+\}/g) ?? [])].sort().join(',');

const sharedBase = JSON.parse(await readFile(join(repoRoot, 'assets/i18n/zh-Hans.json'), 'utf8'));
const winMessages = Object.fromEntries(await Promise.all(languages.map(async (lang) => [
  lang,
  JSON.parse(await readFile(join(windowsRoot, 'locales', `${lang}.json`), 'utf8')),
])));

const winBase = winMessages['zh-Hans'];
const failures = [];

for (const [lang, values] of Object.entries(winMessages)) {
  for (const key of Object.keys(winBase)) {
    if (typeof values[key] !== 'string' || !values[key].trim()) {
      failures.push(`windows/${lang}: 缺少有效译文 ${JSON.stringify(key)}`);
    } else if (placeholders(winBase[key]) !== placeholders(values[key])) {
      failures.push(`windows/${lang}: 占位符不一致 ${JSON.stringify(key)}`);
    }
  }
  for (const key of Object.keys(values)) {
    if (!Object.hasOwn(winBase, key)) {
      failures.push(`windows/${lang}: 多余键 ${JSON.stringify(key)}`);
    }
  }
}

async function* csFiles(folder) {
  for (const entry of await readdir(folder, { withFileTypes: true })) {
    if (entry.name === 'bin' || entry.name === 'obj' || entry.name === 'Generated') continue;
    const full = join(folder, entry.name);
    if (entry.isDirectory()) yield* csFiles(full);
    else if (entry.name.endsWith('.cs')) yield full;
  }
}

const csLiteral = /\bL\.Tr\(\s*"((?:\\.|[^"\\\r\n])*)"/g;
const escapes = { n: '\n', r: '\r', t: '\t', '\\': '\\', '"': '"' };

for await (const file of csFiles(join(windowsRoot, 'src'))) {
  const source = await readFile(file, 'utf8');
  for (const match of source.matchAll(csLiteral)) {
    const key = match[1].replace(/\\(u[\da-fA-F]{4}|[\s\S])/g, (_, code) => {
      if (code.startsWith('u')) return String.fromCodePoint(parseInt(code.slice(1), 16));
      return escapes[code] ?? code;
    });
    if (!Object.hasOwn(sharedBase, key) && !Object.hasOwn(winBase, key)) {
      const line = source.slice(0, match.index).split('\n').length;
      failures.push(`${file}:${line}: 缺少文案键 ${JSON.stringify(key)}`);
    }
  }
}

if (failures.length > 0) {
  for (const failure of failures) console.error(failure);
  process.exit(1);
}
console.log(`Checked Windows localizations across ${languages.length} languages: OK`);
