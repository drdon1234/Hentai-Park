#!/usr/bin/env node
// 仅从明确固定的 EhTagTranslation 快照提取名称列，不复制描述或远端图片。
import {readFile,writeFile} from 'node:fs/promises';
import path from 'node:path';
import {parseArgs} from 'node:util';
import {fileURLToPath} from 'node:url';
import {sha256} from './publish_common.mjs';

const {values} = parseArgs({options:{input:{type:'string'},commit:{type:'string'}}});
if (!values.input || !/^[0-9a-f]{40}$/.test(values.commit||'')) throw new Error('必须提供快照目录和完整上游提交');
const root = fileURLToPath(new URL('../',import.meta.url));
const license = await readFile(path.join(values.input,'LICENSE.md'),'utf8');
if (!license.includes('署名-非商业性使用-相同方式共享')) throw new Error('上游许可无法确认');
const namespaces = ['artist','character','cosplayer','female','group','language','location','male','mixed','other','parody','reclass'];
const tags = {};
const hashes = {};
const plain = value => value.replace(/!\[[^\]]*\]\([^)]*\)/g,'').replace(/\[([^\]]+)\]\([^)]*\)/g,'$1')
  .replace(/<[^>]*>/g,'').replace(/[*`]/g,'').replace(/&amp;/g,'&').replace(/&quot;/g,'"').trim();
for (const namespace of namespaces) {
  const text = await readFile(path.join(values.input,namespace+'.md'),'utf8');
  hashes[namespace] = sha256(text);
  for (const line of text.split('\n')) {
    if (!line.startsWith('|')) continue;
    const cells = line.split(/(?<!\\)\|/).slice(1,-1).map(v=>v.trim());
    if (cells.length < 2 || !cells[0] || cells[0]==='原始标签' || /^-+$/.test(cells[0])) continue;
    const name = plain(cells[1]);
    if (!name || name.length>512 || cells[0].length>240) continue;
    tags[namespace+':'+cells[0].toLowerCase()] = name;
  }
}
const provenance = [{name:'EhTagTranslation/Database',url:'https://github.com/EhTagTranslation/Database',
  commit:values.commit,license:'CC-BY-NC-SA-3.0-CN',licenseUrl:'https://creativecommons.org/licenses/by-nc-sa/3.0/cn/',
  attribution:'EhTagTranslation 全体编辑者',scope:'标签名称译文，不含描述或图片',sha256:hashes}];
const ehFile = path.join(root,'assets/tag_translations/ehentai/zh-Hans.json');
const existing = JSON.parse(await readFile(ehFile,'utf8'));
const nextVersion = pack => {
  const parts=pack.version.split('.').map(Number);parts[2]++;return parts.join('.');
};
// 上游快照完整重建，不沿用早期公共词或已从上游移除的旧词。
await writeFile(ehFile,JSON.stringify({...existing,version:nextVersion(existing),provenance,tags},null,2)+'\n');
// nhentai 明确共享 E 站的作者、作品、角色等标签体系；普通 tag 只借用无歧义名称。
const nhFile = path.join(root,'assets/tag_translations/nhentai/zh-Hans.json');
const nh = JSON.parse(await readFile(nhFile,'utf8'));
nh.tags={};
const terms = new Map();
for (const [key,value] of Object.entries(tags)) {
  const split = key.indexOf(':'), namespace=key.slice(0,split), label=key.slice(split+1);
  if (['artist','group','language','character','parody'].includes(namespace)) nh.tags[key]=value;
  if (['female','male','mixed','other'].includes(namespace)) {
    if (!terms.has(label)) terms.set(label,new Set());
    terms.get(label).add(value);
  }
}
for (const [key, translations] of terms) if(translations.size===1) nh.tags['tag:'+key]=[...translations][0];
const supplemental={'tag:wholesome':'温馨','tag:short-haired female':'短发女性','tag:reverse rape':'女性强迫男性','tag:story rich':'剧情丰富','tag:cousin':'堂表亲'};
Object.assign(nh.tags,supplemental);
await writeFile(nhFile,JSON.stringify({...nh,version:nextVersion(nh),provenance:[...provenance,{name:'HentaiPark',license:'AGPL-3.0-only',scope:'真实详情中的5个普通主题词补充'}]},null,2)+'\n');
await writeFile(path.join(root,'docs/licenses/ehtagtranslation.txt'),license);
console.log(`已导入 ${Object.keys(tags).length} 个有命名空间的上游译名。`);
