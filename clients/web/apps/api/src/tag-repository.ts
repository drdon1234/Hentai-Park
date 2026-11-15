import {createHash} from 'node:crypto';
import {gunzipSync,inflateSync,brotliDecompressSync} from 'node:zlib';
import type {DatabaseSync} from 'node:sqlite';
import {fetchPinnedResource} from '@hentai-park/source-host';
import {officialRepositories} from '@hentai-park/domain-model';
import {isSourceKey} from '@hentai-park/source-contract';
import {compareRelease,isReleaseVersion,tagLocales,validateTagPack,storeTagPack} from './tag-packs.js';
type Entry={source:string;locale:string;version:string;url:string;sha256:string};
const base=officialRepositories.base;
const fail=(code:string,statusCode=400)=>Object.assign(new Error('Tag repository '+code),{code,statusCode,publicError:true,retryable:false});
export function parseTagRepository(value:unknown):Entry[]{
  if(!value||typeof value!=='object'||Array.isArray(value)||!('schema'in value)||value.schema!==1||!('packs'in value)||!Array.isArray(value.packs)||value.packs.length>10000)throw fail('INVALID_MANIFEST');
  const seen=new Set<string>();return value.packs.map(item=>{if(!item||typeof item!=='object'||Array.isArray(item))throw fail('INVALID_MANIFEST');const row=item as Record<string,unknown>;
    if(!isSourceKey(row.source)||!tagLocales.includes(String(row.locale))||!isReleaseVersion(row.version)||typeof row.sha256!=='string'||!/^[a-f0-9]{64}$/i.test(row.sha256)||typeof row.url!=='string')throw fail('INVALID_MANIFEST');
    const entry={source:String(row.source),locale:String(row.locale),version:row.version,url:row.url,sha256:row.sha256.toLowerCase()},key=JSON.stringify([entry.source,entry.locale]);let url:URL;try{url=new URL(entry.url);}catch{throw fail('INVALID_MANIFEST');}
    const commit=url.pathname.split('/')[3];if(!commit||!/^[a-f0-9]{40}$/i.test(commit)||entry.url!==base+'/'+commit+'/assets/tag_translations/'+entry.source+'/'+entry.locale+'.json'||seen.has(key))throw fail('INVALID_MANIFEST');seen.add(key);return entry;
  });
}
/** A pinned official index selects immutable assets; clients never supply a download URL. */
export class TagPackRepository {
  constructor(private readonly db:DatabaseSync,private readonly transfer:typeof fetchPinnedResource=fetchPinnedResource){}
  private async read(url:string,limit:number,signal?:AbortSignal){const response=await this.transfer(url,['raw.githubusercontent.com'],{followRedirects:false,signal:AbortSignal.any([AbortSignal.timeout(15000),...(signal?[signal]:[])])});
    if(!response.ok){await response.body?.cancel();throw fail('NETWORK',502);}const chunks:Uint8Array[]=[];let size=0;const reader=response.body?.getReader();try{if(reader)for(;;){const next=await reader.read();if(next.done)break;size+=next.value.length;if(size>limit)throw fail('RESOURCE_LIMIT',413);chunks.push(next.value);}}finally{await reader?.cancel().catch(()=>{});}
    let bytes=Buffer.concat(chunks);try{switch(response.headers.get('content-encoding')?.toLowerCase()){case undefined:case null:case 'identity':break;case 'gzip':bytes=gunzipSync(bytes,{maxOutputLength:limit});break;case 'deflate':bytes=inflateSync(bytes,{maxOutputLength:limit});break;case 'br':bytes=brotliDecompressSync(bytes,{maxOutputLength:limit});break;default:throw fail('PARSE',502);}}catch{throw fail('PARSE',502);}if(bytes.length>limit)throw fail('RESOURCE_LIMIT',413);return bytes;
  }
  private async entries(signal?:AbortSignal){const bytes=await this.read(base+'/tag-translations/index.json',1024*1024,signal);let value:unknown;try{value=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));}catch(error){if(error&&typeof error==='object'&&'publicError'in error)throw error;throw fail('PARSE',502);}return parseTagRepository(value);}
  async available(signal?:AbortSignal){const entries=await this.entries(signal);return {items:entries.map(entry=>{const row=this.db.prepare('SELECT version FROM tag_translation_packs WHERE source=? AND locale=?').get(entry.source,entry.locale);return {...entry,installedVersion:row?.version??null,updateAvailable:!row||compareRelease(entry.version,String(row.version))>0};})};}
  async install(input:unknown,signal?:AbortSignal){if(!input||typeof input!=='object'||Array.isArray(input))throw fail('BAD_REQUEST');const body=input as Record<string,unknown>;
    if(body.confirmed!==true||Object.keys(body).some(key=>!['source','locale','expectedVersion','expectedSha256','confirmed'].includes(key)))throw fail('CONFIRM_REQUIRED',409);
    const entries=await this.entries(signal),entry=entries.find(row=>row.source===body.source&&row.locale===body.locale);if(!entry)throw fail('NOT_FOUND',404);if(entry.version!==body.expectedVersion||entry.sha256!==body.expectedSha256)throw fail('CONFLICT',409);
    const bytes=await this.read(entry.url,8*1024*1024,signal);if(createHash('sha256').update(bytes).digest('hex')!==entry.sha256)throw fail('CHECKSUM_MISMATCH',409);let pack:ReturnType<typeof validateTagPack>;try{pack=validateTagPack(JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes)));}catch{throw fail('INVALID_MANIFEST');}
    if(pack.source!==entry.source||pack.locale!==entry.locale||pack.version!==entry.version)throw fail('INVALID_MANIFEST');signal?.throwIfAborted();return storeTagPack(this.db,pack);
  }
}
