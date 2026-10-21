#!/usr/bin/env node
// 构建期复用图集解析；每个输出插件自包含，域名与站点配置互不共享。
import {readFile, writeFile} from 'node:fs/promises';

const root = new URL('../', import.meta.url);
const template = await readFile(new URL('tools/source-templates/wordpress-gallery.js', root), 'utf8');
const sites = JSON.parse(await readFile(new URL('tools/source-templates/gallery-sites.json', root), 'utf8'));
const check = process.argv.includes('--check');
const seen = new Set();
for (const {site, i18n} of sites) {
  if (!/^[a-z0-9_-]+$/.test(site.key) || seen.has(site.key)) throw new Error('图集站点配置无效');
  seen.add(site.key);
  for (const url of [site.home, site.api]) {
    const parsed = new URL(url);
    if (parsed.protocol !== 'https:' || parsed.username || parsed.password ||
        !(parsed.hostname === site.domain || parsed.hostname.endsWith('.' + site.domain))) throw new Error('图集域名配置无效');
  }
  const output = template.replace('__SITE__', () => JSON.stringify(site, null, 2))
    .replace('__I18N__', () => JSON.stringify(i18n, null, 2));
  const path = new URL('assets/sources/' + site.key + '.js', root);
  if (check) {
    if (await readFile(path, 'utf8') !== output) throw new Error(site.key + ' 的生成插件需要更新');
  } else await writeFile(path, output);
}
console.log(check ? '图集生成插件与模板一致' : '图集插件已生成');
