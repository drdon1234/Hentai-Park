#!/usr/bin/env node
import {readFile, writeFile} from 'node:fs/promises';

const root = new URL('../', import.meta.url);
const template = await readFile(new URL('tools/source-templates/feed-cms.js', root), 'utf8');
const sites = [
  {key: 'feed51cg', name: '51吃瓜网', names: {"zh-Hant":"51吃瓜網","en":"51CG","ja":"51吃瓜網","ko":"51CG","es":"51CG","ru":"51CG","ar":"51CG"}, home: 'https://51cg1.com', domain: '51cg1.com', imageDomain: 'pic.gyezbp.cn',
    hostPattern: '^(?:www\\.)?51cg[0-9]+\\.com$', linkPattern: '(?:www\\.)?51cg[0-9]+\\.com'},
  {key: 'feedheiliao', name: '黑料网', names: {"zh-Hant":"黑料網","en":"Heiliao","ja":"黒料網","ko":"헤이랴오","es":"Heiliao","ru":"Heiliao","ar":"Heiliao"}, homepage: 'https://155.fun', home: 'https://heiliao.com', domain: 'heiliao.com', imageDomain: 'pic.hdhwqx.cn', archive: true,
    release: 'https://www.heiliao88.com/', releaseSelector: 'a.line-long[href]', hostPattern: '^(?:www\\.)?heiliao[0-9]*\\.com$', linkPattern: '(?:www\\.)?heiliao[0-9]*\\.com'},
  {key: 'feedmrds', name: '每日大赛', names: {"zh-Hant":"每日大賽","en":"MRDS","ja":"毎日大賽","ko":"매일대회","es":"MRDS","ru":"MRDS","ar":"MRDS"}, homepage: 'https://mrdsk.com', home: 'https://www.mrds66.com', domain: 'mrds66.com', imageDomain: 'pic.gyezbp.cn',
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
