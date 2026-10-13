import { readFile, readdir } from 'node:fs/promises';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const languages = ['zh-Hans', 'zh-Hant', 'ja', 'ko', 'en', 'es', 'ru', 'ar'];
const messages = Object.fromEntries(await Promise.all(languages.map(async (language) => [
  language, JSON.parse(await readFile(join(root, 'assets/i18n', `${language}.json`), 'utf8')),
])));
const base = messages['zh-Hans'];
const failures = [];
const placeholders = (value) => [...new Set(value.match(/\{\w+\}/g) ?? [])].sort().join(',');
for (const [language, values] of Object.entries(messages)) {
  for (const key of Object.keys(base)) {
    if (typeof values[key] !== 'string' || !values[key].trim()) {
      failures.push(`${language}: 缺少有效译文 ${JSON.stringify(key)}`);
    } else if (placeholders(base[key]) !== placeholders(values[key])) {
      failures.push(`${language}: 占位符不一致 ${JSON.stringify(key)}`);
    }
  }
  for (const key of Object.keys(values)) {
    if (!Object.hasOwn(base, key)) failures.push(`${language}: 多余键 ${JSON.stringify(key)}`);
  }
}

async function* dartFiles(folder) {
  for (const entry of await readdir(folder, { withFileTypes: true })) {
    const path = join(folder, entry.name);
    if (entry.isDirectory()) yield* dartFiles(path);
    else if (entry.name.endsWith('.dart') && !entry.name.endsWith('.g.dart')) yield path;
  }
}
// 检查可静态确定的 tr 字面量；动态键由八语言同键约束覆盖。
const literals = /\btr\(\s*(r?)(['"])((?:\\[\s\S]|(?!\2)[^\\\r\n])*)\2/g;
const escapes = { n: '\n', r: '\r', t: '\t', b: '\b', f: '\f', v: '\v', '$': '$', '\\': '\\', "'": "'", '"': '"' };
for await (const path of dartFiles(join(root, 'lib'))) {
  const source = await readFile(path, 'utf8');
  for (const match of source.matchAll(literals)) {
    if (!match[1] && /(^|[^\\])\$/.test(match[3])) continue;
    if (/^\s*['"]/.test(source.slice(match.index + match[0].length))) continue;
    const key = match[1] ? match[3] : match[3].replace(/\\(u\{[\da-fA-F]+\}|u[\da-fA-F]{4}|x[\da-fA-F]{2}|[\s\S])/g, (_, code) => {
      if (code.startsWith('u{')) return String.fromCodePoint(parseInt(code.slice(2, -1), 16));
      if (code.startsWith('u') || code.startsWith('x')) return String.fromCodePoint(parseInt(code.slice(1), 16));
      return escapes[code] ?? code;
    });
    if (!Object.hasOwn(base, key)) {
      const line = source.slice(0, match.index).split('\n').length;
      failures.push(`${path}:${line}: 缺少文案 ${JSON.stringify(key)}`);
    }
  }
}
if (failures.length) {
  console.error(failures.join('\n'));
  process.exitCode = 1;
} else {
  console.log(`八语言文案检查通过：${Object.keys(base).length} 个键，静态引用与占位符一致。`);
}
