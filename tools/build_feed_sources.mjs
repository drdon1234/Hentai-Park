#!/usr/bin/env node
import {readFile, writeFile} from 'node:fs/promises';

const root = new URL('../', import.meta.url);
const template = await readFile(new URL('tools/source-templates/feed-cms.js', root), 'utf8');
const sites = [
  {key: 'feed51cg', name: '51cg1.com', home: 'https://51cg1.com', domain: '51cg1.com', imageDomain: 'pic.gyezbp.cn',
    hostPattern: '^(?:www\\.)?51cg[0-9]+\\.com$', linkPattern: '(?:www\\.)?51cg[0-9]+\\.com'},
  {key: 'feedheiliao', name: '155.fun', homepage: 'https://155.fun', home: 'https://heiliao.com', domain: 'heiliao.com', imageDomain: 'pic.hdhwqx.cn', archive: true,
    release: 'https://www.heiliao88.com/', releaseSelector: 'a.line-long[href]', hostPattern: '^(?:www\\.)?heiliao[0-9]*\\.com$', linkPattern: '(?:www\\.)?heiliao[0-9]*\\.com'},
  {key: 'feedmrds', name: 'mrdsk.com', homepage: 'https://mrdsk.com', home: 'https://www.mrds66.com', domain: 'mrds66.com', imageDomain: 'pic.gyezbp.cn',
    release: 'https://mrdsk.com/', encodedRelease: true, releaseSelector: 'a[href]', hostPattern: '^(?:www\\.)?mrds[0-9]+\\.com$', linkPattern: '(?:www\\.)?mrds[0-9]+\\.com'},
];
for (const site of sites) {
  const file = new URL('assets/sources/' + site.key + '.js', root);
  const output = template.replace('__SITE_CONFIG__', JSON.stringify(site));
  if (process.argv.includes('--check')) {
    if (await readFile(file, 'utf8') !== output) throw new Error(site.key + ' 需要重新生成');
  } else {
    await writeFile(file, output);
  }
}
