#!/usr/bin/env node
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {parseArgs} from 'node:util';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const {values}=parseArgs({options:{inventory:{type:'string'}}});
if(!values.inventory) throw new Error('需提供实际请求标签记录');
const root=fileURLToPath(new URL('../',import.meta.url));
const reviewed=JSON.parse(await readFile(path.join(root,'assets/tag_translations/reviewed_terms.json'),'utf8'));
const terms=new Map(Object.entries(reviewed.terms).map(([key,value])=>[key.toLowerCase(),value]));
const sites=JSON.parse(await readFile(values.inventory,'utf8'));
const audit=[];
for(const site of sites) {
  if(['ehentai','nhentai'].includes(site.source)) continue;
  // 接口受限或需登录的带标签站点仍安装已审校概念，状态如实列入来源记录。
  if(!site.tags.length && !site.hasTags && !['pica','hanime1','missav','jable','supjav','pixiv','ixxx','tikporn','x'].includes(site.source)) continue;
  const dir=path.join(root,'assets/tag_translations',site.source);
  await mkdir(dir,{recursive:true});
  const file=path.join(dir,'zh-Hans.json');
  let pack={schema:1,source:site.source,locale:'zh-Hans',version:'1.1.0',tags:{}};
  try {pack={...JSON.parse(await readFile(file,'utf8')),version:'1.1.0'};}catch(e){if(e.code!=='ENOENT')throw e;}
  pack.tags=Object.fromEntries(Object.entries(pack.tags).map(([key,value])=>[key.toLowerCase(),value]));
  const records=[];
  for(const tag of site.tags) {
    const translated=terms.get(tag.name.toLowerCase());
    const key=((tag.namespace?tag.namespace+':':'')+tag.name).toLowerCase();
    // 中文标签原样有效；未核实专名不能给出编造译名。
    const chinese=!/[A-Za-zぁ-ゟ゠-ヿ]/.test(tag.name);
    // 艺名、厂牌和未确认角色采用原名，明确入库，防止自动翻译再次误译专名。
    pack.tags[key]=translated||tag.name;
    records.push({...tag,translation:translated||(chinese?tag.name:null),status:translated?'reviewed':chinese?'already-chinese':'original-preserved'});
  }
  // 各站仅显式采用经过审校的公共概念，不隐式套用 E 站命名空间。
  for(const [key,value] of terms) if(!pack.tags[key]) pack.tags[key]=value;
  pack.provenance=[{name:'HentaiPark',license:'AGPL-3.0-only',scope:'已审校公共概念和实际请求站点标签；未确认专名保留原文',
    homepage:site.homepage,checks:site.checks,failures:site.failures}];
  await writeFile(file,JSON.stringify(pack,null,2)+'\n');
  audit.push({source:site.source,records,checks:site.checks,failures:site.failures});
}
await writeFile(path.join(root,'test/tag_cache_subscription/tag-review.json'),JSON.stringify(audit,null,2)+'\n');
console.log(`已生成 ${audit.length} 个实际标签源的中文补充词包。`);
