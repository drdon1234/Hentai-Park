import {isSourceKey} from '@hentai-park/source-contract';
import type {DatabaseSync} from 'node:sqlite';
type Row=Record<string,unknown>;
export const tagLocales=['zh-Hans','zh-Hant','en','ja','ko','es','ru','ar'];
const locales=tagLocales;
const fail=(code:string,statusCode=400)=>Object.assign(new Error(code),{code,statusCode,publicError:true,causeCategory:'validation',retryable:false});
export const isReleaseVersion=(value:unknown):value is string=>typeof value==='string'&&value.length<=128&&/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(value);
export function compareRelease(a:string,b:string){const x=a.split('.').map(BigInt),y=b.split('.').map(BigInt);for(let i=0;i<3;i++)if(x[i]!==y[i])return x[i]>y[i]?1:-1;return 0;}
export function validateTagPack(input:unknown){
  if(!input||typeof input!=='object'||Array.isArray(input))throw fail('BAD_REQUEST');const value=input as Row;
  if(Buffer.byteLength(JSON.stringify(value))>8*1024*1024||value.schema!==1||!isSourceKey(value.source)||!locales.includes(String(value.locale))||typeof value.version!=='string'||!isReleaseVersion(value.version)||!value.tags||typeof value.tags!=='object'||Array.isArray(value.tags))throw fail('BAD_REQUEST');
  const entries=Object.entries(value.tags),tags:Record<string,string>=Object.create(null),seen=new Set<string>();if(!entries.length||entries.length>100000)throw fail('BAD_REQUEST');
  for(const [raw,text]of entries){const key=raw.trim().toLowerCase();if(!key||key.length>256||typeof text!=='string'||!text.trim()||text.length>512||/[\u0000-\u001f\u007f]/.test(key+text)||/^(?:TODO|TBD|N\/A|\?+|-+)$/i.test(text.trim())||seen.has(key))throw fail('BAD_REQUEST');seen.add(key);tags[key]=text.trim();}
  if(value.provenance!==undefined&&(!Array.isArray(value.provenance)||value.provenance.length>32||value.provenance.some(item=>!item||typeof item!=='object'||Array.isArray(item))))throw fail('BAD_REQUEST');
  return {schema:1,source:String(value.source),locale:String(value.locale),version:value.version,tags,...(value.provenance?{provenance:value.provenance}:{})};
}
export function storeTagPack(db:DatabaseSync,input:unknown){const pack=validateTagPack(input),prior=db.prepare('SELECT version FROM tag_translation_packs WHERE source=? AND locale=?').get(pack.source,pack.locale);if(prior&&compareRelease(pack.version,String(prior.version))<0)throw fail('VERSION_DOWNGRADE',409);db.prepare('INSERT INTO tag_translation_packs VALUES(?,?,?,?,?) ON CONFLICT(source,locale) DO UPDATE SET version=excluded.version,payload_json=excluded.payload_json,updated_at=excluded.updated_at').run(pack.source,pack.locale,pack.version,JSON.stringify(pack),new Date().toISOString());return {source:pack.source,locale:pack.locale,version:pack.version};}
