#!/usr/bin/env node
// 仅在构建期复用导航解析，最终插件不引用其他源或跨站共享目录。
import {readFile, writeFile} from 'node:fs/promises';

const root = new URL('../', import.meta.url);
const template = await readFile(new URL('tools/source-templates/navigation-catalog.js', root), 'utf8');
const check = process.argv.includes('--check');
const sites = {
  jable: {home: '/', leaf: '^/categories/[a-zA-Z0-9_%+-]+/$', index: '^/categories/?$'},
  supjav: {home: '/zh', leaf: '^/zh/category/[a-zA-Z0-9_%+-]+/?$', index: '^/zh/category/?$'},
  missav: {home: '/cn/new', leaf: '^/(?:dm\\d*/)?cn/genres/[a-zA-Z0-9_%+-]+/?$', index: '^/(?:dm\\d*/)?cn/genres/?$'},
  ixxx: {home: '/rating', leaf: '^/c/[a-zA-Z0-9_%+-]+/?$', index: '^/a-z/?$', pageMethod: 'request', absolute: true, listMethod: 'categoryListing', ranges: true},
  pornpics: {home: '/', leaf: '^/[a-z0-9][a-z0-9-]*/$', selector: '#tiles a.rel-link[href]', pageMethod: 'page', absolute: true, listMethod: 'categoryListing'},
  spankbang: {home: '/', leaf: '^/s/[a-zA-Z0-9_%+-]+/$', index: '^/tags/?$', pageMethod: 'page', absolute: true, listMethod: 'categoryListing', ranges: true},
};
for (const [key, config] of Object.entries(sites)) {
  const file = new URL('assets/sources/' + key + '.js', root);
  const code = await readFile(file, 'utf8');
  const block = template.replaceAll('__CATALOG_CONFIG__', () => JSON.stringify(config));
  const start = code.indexOf('  // __CATALOG_START__'), marker = '  // __CATALOG_END__';
  const end = code.indexOf(marker, start);
  const output = start >= 0 && end > start
    ? code.slice(0, start) + block.trimEnd() + code.slice(end + marker.length)
    : code.replace(/^.*\bBASE: 'https:\/\//m, match => block + match);
  if (output === code && start < 0) throw new Error(key + ' 缺少生成位置');
  if (check) {
    if (output !== code) throw new Error(key + ' 的分类解析需要重新生成');
  } else await writeFile(file, output);
}
console.log(check ? '站内分类解析与模板一致' : '站内分类解析已生成');
