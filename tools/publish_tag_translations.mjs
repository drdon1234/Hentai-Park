#!/usr/bin/env node
// 独立维护的官方标签词包：离线校验，并生成固定提交地址及 SHA-256。
import { lstat, readdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { readUtf8, isCommit, isReleaseVersion, isSourceKey, sha256, officialAssetUrl } from './publish_common.mjs';

const { values } = parseArgs({ options: {
  root: { type: 'string', default: fileURLToPath(new URL('../', import.meta.url)) },
  commit: { type: 'string' }, output: { type: 'string' },
} });
if (values.commit && !isCommit(values.commit)) throw new Error('commit 必须是完整提交摘要');
if (values.output && !values.commit) throw new Error('发布索引必须指定 commit');
const officialSources = JSON.parse(await readUtf8(path.join(values.root, 'assets/sources/index.json'))).sources.map(entry => entry.key);
if (officialSources.some(key => !isSourceKey(key)) || new Set(officialSources).size !== officialSources.length) throw new Error('源身份清单无效');
const sources = (await readdir(path.join(values.root, 'assets/tag_translations'), {withFileTypes: true}))
  .filter(entry => entry.isDirectory() || entry.isSymbolicLink()).map(entry => entry.name).sort();
if (sources.some(key => !officialSources.includes(key))) throw new Error('词包源不在官方清单中');
const locales = (await readdir(path.join(values.root, 'assets/i18n'))).filter(file => file.endsWith('.json')).map(file => file.slice(0, -5)).sort();
if (!sources.length || !locales.length) throw new Error('词包或语言资源清单为空');
if (locales.some(locale => !/^[A-Za-z-]+$/.test(locale))) throw new Error('语言资源名称无效');
const packs = [];
for (const source of sources) {
  const presentLocales = (await readdir(path.join(values.root, 'assets/tag_translations', source)))
    .filter(file => file.endsWith('.json')).map(file => file.slice(0, -5)).sort();
  if (!presentLocales.length || presentLocales.some(locale => !locales.includes(locale))) throw new Error(`词包语言无效：${source}`);
  for (const locale of presentLocales) {
    const relative = `assets/tag_translations/${source}/${locale}.json`;
    const filename = path.join(values.root, relative);
    for (const segment of [path.join(values.root,'assets/tag_translations'), path.dirname(filename), filename]) {
      if ((await lstat(segment)).isSymbolicLink()) throw new Error(`词包路径不允许符号链接：${segment}`);
    }
    const text = await readUtf8(filename);
    if (Buffer.byteLength(text, 'utf8') > 8*1024*1024) throw new Error(`词包过大：${relative}`);
    const data = JSON.parse(text);
    if (data.schema !== 1 || data.source !== source || data.locale !== locale ||
        !isReleaseVersion(data.version) ||
        !data.tags || typeof data.tags !== 'object' || Array.isArray(data.tags)) throw new Error(`词包格式无效：${relative}`);
    const entries = Object.entries(data.tags);
    if (!entries.length || entries.length > 100000) throw new Error(`词包数量无效：${relative}`);
    const upstream = ['ehentai','nhentai'].includes(source) && locale === 'zh-Hans';
    if (upstream) {
      if (!data.provenance?.some(p => p.name === 'EhTagTranslation/Database' && isCommit(p.commit) && p.license === 'CC-BY-NC-SA-3.0-CN') ||
          entries.some(([key]) => !/^(?:artist|character|cosplayer|female|group|language|location|male|mixed|other|parody|reclass|tag):.+$/.test(key))) throw new Error(`上游词包缺少来源或混入无命名空间词：${relative}`);
    } else {
      const c = data.coverage;
      const translated = entries.filter(([key,value]) => typeof value === 'string' &&
        key.toLowerCase() !== value.toLowerCase() && !key.toLowerCase().endsWith(':'+value.toLowerCase())).length;
      if (!c || typeof c.scope !== 'string' || !c.scope.trim() || c.scope.length > 1024 || c.complete !== false ||
          ['observed','translated','preserved','unchanged','unreviewed'].some(k => !Number.isSafeInteger(c[k]) || c[k] < 0) ||
          c.translated < 1 || c.translated !== translated || c.translated + c.preserved !== entries.length ||
          c.translated + c.preserved + c.unchanged + c.unreviewed !== c.observed) throw new Error(`词包缺少可信的审校译文或覆盖范围：${relative}`);
    }
    const seen = new Set();
    for (const [key,value] of entries) {
      const normalized = key.trim().toLowerCase();
      if (!normalized || key.length > 256 || typeof value !== 'string' || !value.trim() || value.length > 512 ||
          /^(?:TODO|TBD|N\/A|\?+|-+)$/i.test(value.trim()) || seen.has(normalized)) throw new Error(`无效或重复译文：${relative}:${key}`);
      seen.add(normalized);
    }
    packs.push({source,locale,version:data.version,sha256:sha256(text),
      ...(values.commit ? {url:officialAssetUrl(values.commit, relative)} : {})});
  }
}
if (values.output) await writeFile(values.output,JSON.stringify({schema:1,packs},null,2)+'\n');
console.log(`已验证 ${packs.length} 个官方标签词包。`);
