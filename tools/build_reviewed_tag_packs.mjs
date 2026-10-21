#!/usr/bin/env node
// 只对真实观察到的标签应用审校译文；不把公共术语批量灌入各站。
import {readFile,writeFile,mkdir,unlink} from 'node:fs/promises';
import {parseArgs} from 'node:util';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {isSourceKey,isReleaseVersion} from './publish_common.mjs';
const {values}=parseArgs({options:{inventory:{type:'string'},report:{type:'string'}}});
if(!values.inventory) throw new Error('需提供实际请求标签记录');
const root=fileURLToPath(new URL('../',import.meta.url));
const reviewed=JSON.parse(await readFile(path.join(root,'assets/tag_translations/reviewed_terms.json'),'utf8'));
const terms=new Map(Object.entries(reviewed.terms).map(([key,value])=>[key.trim().toLowerCase(),value]));
const sites=JSON.parse(await readFile(values.inventory,'utf8'));
if(!Array.isArray(sites)) throw new Error('标签记录必须是站点数组');
const official=new Set(JSON.parse(await readFile(path.join(root,'assets/sources/index.json'),'utf8')).sources.map(s=>s.key));
const concepts=new Set(['','tag','tags','标签','categories','genre']);
const properNames=new Set(['artist','group','cosplayer','author','authors','model','models','maker','actor','actress','作者','厂商','女优']);
const audit=[],seenSources=new Set();
for(const site of sites) {
  if(!isSourceKey(site.source)||!official.has(site.source)||seenSources.has(site.source)) throw new Error('标签记录站点身份无效或重复');
  seenSources.add(site.source);
  if(['ehentai','nhentai'].includes(site.source)) continue;
  if(!Array.isArray(site.tags)) throw new Error(`${site.source} 缺少实际标签数组`);
  const file=path.join(root,'assets/tag_translations',site.source,'zh-Hans.json');
  let existing;
  try {existing=JSON.parse(await readFile(file,'utf8'));}catch(e){if(e.code!=='ENOENT')throw e;}
  const tags=Object.create(null),records=[],seen=new Map();
  for(const tag of site.tags) {
    if(typeof tag.name!=='string'||!tag.name.trim()||tag.name.length>240||tag.namespace!=null&&typeof tag.namespace!=='string') throw new Error('实际标签无效');
    const name=tag.name.trim(),ns=(tag.namespace||'').trim().toLowerCase();
    const key=(ns?ns+':':'')+name.toLowerCase();
    if(key.length>256) throw new Error('实际标签过长');
    let translation=null,status='unreviewed';
    if(tag.reviewed===true) {
      if(typeof tag.translation!=='string'||!tag.translation.trim()||tag.translation.length>512) throw new Error('审校译文无效');
      translation=tag.translation.trim();status=translation===name?'unchanged':'translated';
    } else if(tag.preserve===true||properNames.has(ns)) {
      translation=name;status='preserved';
    } else if(existing?.coverage?.translated>0&&Object.hasOwn(existing.tags,key)) {
      translation=existing.tags[key];status=translation===name?'preserved':'translated';
    } else if(concepts.has(ns)&&terms.has(name.toLowerCase())) {
      translation=terms.get(name.toLowerCase());status=translation===name?'unchanged':'translated';
    }
    if(seen.has(key)) {
      const previous=seen.get(key);
      if(previous.translation!==translation||previous.status!==status) throw new Error(`${site.source} 的同名标签审校结果冲突`);
      continue;
    }
    const record={namespace:ns,name,translation,status};seen.set(key,record);records.push(record);
    if(status==='translated'||status==='preserved') tags[key]=translation;
  }
  const counts=Object.fromEntries(['translated','preserved','unchanged','unreviewed'].map(s=>[s,records.filter(r=>r.status===s).length]));
  // 没有实际译文的站点不再分发空壳包；显式原名只用于保护已确认专名。
  if(!counts.translated) {
    await unlink(file).catch(e=>{if(e.code!=='ENOENT')throw e;});
    audit.push({source:site.source,published:false,records,...counts});continue;
  }
  const coverage={scope:typeof site.scope==='string'&&site.scope.trim()?site.scope.trim():'实际标签样本，非全站目录',complete:false,observed:records.length,...counts};
  const provenance=[{name:'HentaiPark',license:'AGPL-3.0-only',scope:coverage.scope,...(site.homepage?{homepage:site.homepage}:{})}];
  let version='1.0.0';
  if(existing) {
    if(!isReleaseVersion(existing.version)) throw new Error('现有词包版本无效');
    const unchanged=JSON.stringify(existing.tags)===JSON.stringify(tags)&&JSON.stringify(existing.coverage)===JSON.stringify(coverage)&&JSON.stringify(existing.provenance)===JSON.stringify(provenance);
    const parts=existing.version.split('.').map(Number);parts[2]++;
    version=unchanged?existing.version:parts.join('.');
  }
  const pack={schema:1,source:site.source,locale:'zh-Hans',version,tags,coverage,provenance};
  await mkdir(path.dirname(file),{recursive:true});
  await writeFile(file,JSON.stringify(pack,null,2)+'\n');
  audit.push({source:site.source,published:true,records,...counts});
}
const report=values.report||path.join(root,'test/tag_cache_subscription/tag-review.json');
await mkdir(path.dirname(report),{recursive:true});
await writeFile(report,JSON.stringify(audit,null,2)+'\n');
console.log(`已生成 ${audit.filter(s=>s.published).length} 个有实际审校译文的站点词包。`);
