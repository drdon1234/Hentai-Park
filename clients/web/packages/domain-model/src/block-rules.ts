import {blockPresets} from './block-presets.js';
export type BlockableWork={source?:unknown;workId?:unknown;id?:unknown;title?:unknown;summary?:unknown;authors?:unknown;uploader?:unknown;tags?:unknown;previewOnly?:unknown;media?:unknown};
export type BlockSettings={blockedWords?:unknown;blockedAuthors?:unknown;blockedWorks?:unknown;hidePreviews?:unknown;blockedTagAliases?:unknown;blockPresets?:unknown;blockedAuthorWorks?:unknown};
const strings=(value:unknown)=>Array.isArray(value)?value.filter((v):v is string=>typeof v==='string'):[];
const escape=(value:string)=>value.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
export function parseBlockRule(input:string){
  if(!input.trim()||input.length>256)throw new Error('INVALID_BLOCK_RULE');
  let value=input.trim(),scope='all';const colon=value.indexOf(':');
  if(colon>=0&&value.slice(0,colon).toLowerCase()!=='regex'){scope=value.slice(0,colon).toLowerCase();value=value.slice(colon+1);}
  const regex=value.toLowerCase().startsWith('regex:');if(regex)value=value.slice(6);
  if(!value.trim())throw new Error('INVALID_BLOCK_RULE');
  const wildcard=!regex&&/[?*]/.test(value);if(wildcard&&!value.replace(/[?*\s]/g,''))throw new Error('INVALID_BLOCK_RULE');
  const pattern=regex?value:wildcard?Array.from(value).map(c=>c==='*'?'[\\s\\S]*':c==='?'?'[\\s\\S]':escape(c)).join(''):escape(value);
  // Exact tag/namespace/identity matching and word-aware natural-title matching
  // share one parser; original strings remain available for temporary display.
  const test=(text:string,title=false)=>new RegExp(regex?pattern:title?wildcard?pattern:/^[A-Za-z0-9 ]+$/.test(value)?'(?<![A-Za-z0-9])'+pattern+'(?![A-Za-z0-9])':pattern:'^(?:'+pattern+')$','iu').test(text);
  new RegExp(pattern,'iu');return {scope,test};
}
export function isWorkBlocked(work:BlockableWork,settings:BlockSettings){
  const title=typeof work.title==='string'?work.title:'';
  const authors=[...strings(work.authors),...(Array.isArray(work.authors)?work.authors.flatMap(a=>a&&typeof a==='object'?typeof (a as Record<string,unknown>).name==='string'?[(a as Record<string,unknown>).name as string]:typeof (a as Record<string,unknown>).label==='string'?[(a as Record<string,unknown>).label as string]:[]:[]):[]),...(typeof work.uploader==='string'?[work.uploader]:[])];
  const tags=Array.isArray(work.tags)?work.tags.flatMap(tag=>typeof tag==='string'?[{label:tag,namespace:tag.includes(':')?tag.split(':')[0]:''}]:tag&&typeof tag==='object'?'tags'in tag&&Array.isArray(tag.tags)?tag.tags.flatMap((item:unknown)=>typeof item==='string'?[{label:item,namespace:String(tag.namespace??'')}]:item&&typeof item==='object'?[{label:String((item as Record<string,unknown>).name??(item as Record<string,unknown>).label??''),namespace:String(tag.namespace??'')}]:[]):[{label:String(tag.label??tag.name??''),namespace:String(tag.namespace??'')}]:[]):[];
  const normalizedTags=tags.map(tag=>{const colon=tag.label.indexOf(':');return colon>=0?{label:tag.label.slice(colon+1),namespace:tag.namespace||tag.label.slice(0,colon)}:tag;});
  const identity=String(work.workId??work.id??''),source=String(work.source??'');
  if(strings(settings.blockedWorks).some(v=>v===source+':'+identity||v===JSON.stringify([source,identity])))return true;
  if(strings(settings.blockedAuthors).some(value=>authors.some(author=>author.toLocaleLowerCase()===value.toLocaleLowerCase()||(source+':'+author).toLocaleLowerCase()===value.toLocaleLowerCase())))return true;
  if(settings.hidePreviews===true&&(work.previewOnly===true||Array.isArray(work.media)&&work.media.length>0&&work.media.every(item=>item&&typeof item==='object'&&item.previewOnly===true)))return true;
  const aliasMap=settings.blockedTagAliases&&typeof settings.blockedTagAliases==='object'?settings.blockedTagAliases as Record<string,unknown>:{};
  const expand=(entry:string,aliases:Record<string,unknown>)=>{const scope=parseBlockRule(entry).scope;return [entry,...strings(aliases[entry]).map(alias=>scope==='all'?alias:scope+':'+alias)];};
  const entries=strings(settings.blockedWords).flatMap(entry=>expand(entry,aliasMap));
  const presets=settings.blockPresets&&typeof settings.blockPresets==='object'?settings.blockPresets as Record<string,Record<string,unknown>>:{};
  for(const preset of blockPresets){const config=presets[preset.id];if(config?.on!==true)continue;const aliases=config.aliases as Record<string,unknown>??{};const rules=[...strings(config.entries??preset.entries),...(config.strong?strings(config.strongEntries??preset.strongEntries):[])];for(const entry of rules){const rule=parseBlockRule(entry);if(rule.scope==='title'&&!config.title)continue;for(const expanded of expand(entry,aliases)){entries.push(rule.scope==='all'?'tag:'+expanded:expanded);if(config.title&&rule.scope!=='tag'&&rule.scope!=='title')entries.push('title:'+expanded);}}}
  const authorWorks=settings.blockedAuthorWorks&&typeof settings.blockedAuthorWorks==='object'?settings.blockedAuthorWorks as Record<string,unknown>:{};if(strings(settings.blockedAuthors).some(author=>strings(authorWorks[author]).includes(source+':'+identity)))return true;
  return entries.some(value=>{try{const rule=parseBlockRule(value);switch(rule.scope){case 'title':return rule.test(title,true);case 'author':return authors.some(a=>rule.test(a));case 'work':return rule.test(identity)||rule.test(source+':'+identity);case 'source':return rule.test(source);case 'tag':return normalizedTags.some(t=>rule.test(t.label)||rule.test(t.namespace+':'+t.label));case 'all':return rule.test(title,true)||normalizedTags.some(t=>rule.test(t.label)||rule.test(t.namespace+':'+t.label));default:return normalizedTags.some(t=>t.namespace.toLocaleLowerCase()===rule.scope&&rule.test(t.label));}}catch{return false;}});
}
