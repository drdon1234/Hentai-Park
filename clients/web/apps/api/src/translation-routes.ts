import type {FastifyInstance,FastifyRequest} from 'fastify';
import type {DatabaseSync} from 'node:sqlite';
import {fetchBrowserResource} from '@hentai-park/browser-worker';
import {tagLocales,storeTagPack} from './tag-packs.js';
import {TagPackRepository} from './tag-repository.js';
import {languages} from '@hentai-park/domain-model';
type Row=Record<string,unknown>;
const locales=tagLocales;
const targetCode=(locale:string)=>languages[locale as keyof typeof languages]?.translationId??locale;
const fail=(code:string,statusCode=400)=>Object.assign(new Error(code),{code,statusCode,publicError:true,causeCategory:['NETWORK','RATE_LIMITED'].includes(code)?'network':'validation',retryable:['NETWORK','RATE_LIMITED'].includes(code)});
type TranslationWaiter={resolve:(text:string)=>void;reject:(error:unknown)=>void;cleanup:()=>void};
type TranslationJob={key:string;text:string;locale:string;controller:AbortController;waiters:Set<TranslationWaiter>};
export class ContentTranslator {
  private active=0;private jobs:TranslationJob[]=[];private pending=new Map<string,TranslationJob>();private cache=new Map<string,{text:string;at:number}>();private rateLimitedUntil=0;
  constructor(private readonly transfer:(url:string,domains:string[],options:{signal:AbortSignal})=>Promise<Response>=fetchBrowserResource){}
  async translate(text:string,locale:string,signal?:AbortSignal):Promise<string>{
    if(!text||text.length>1000||!locales.includes(locale)||/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(text))throw fail('BAD_REQUEST');signal?.throwIfAborted();
    const key=JSON.stringify([text,locale]),cached=this.cache.get(key);if(cached&&cached.at>Date.now()-900000)return cached.text;
    if(Date.now()<this.rateLimitedUntil)throw this.cooldownError();
    let job=this.pending.get(key);
    if(!job){if(this.jobs.length>=32)throw fail('RATE_LIMITED',429);job={key,text,locale,controller:new AbortController(),waiters:new Set()};this.pending.set(key,job);this.jobs.push(job);}
    const shared=job;
    return new Promise((resolve,reject)=>{const waiter:TranslationWaiter={resolve,reject,cleanup:()=>signal?.removeEventListener('abort',abort)};
      const abort=()=>{if(!shared.waiters.delete(waiter))return;waiter.cleanup();reject(fail('CANCELLED',499));if(!shared.waiters.size){shared.controller.abort();if(this.pending.get(key)===shared)this.pending.delete(key);const at=this.jobs.indexOf(shared);if(at>=0)this.jobs.splice(at,1);}};
      shared.waiters.add(waiter);signal?.addEventListener('abort',abort,{once:true});if(signal?.aborted)abort();this.pump();});
  }
  private cooldownError(){return Object.assign(fail('RATE_LIMITED',429),{details:{reason:'TRANSLATION_COOLDOWN',retryAfterSeconds:Math.max(1,Math.ceil((this.rateLimitedUntil-Date.now())/1000))}});}
  private finish(job:TranslationJob,text?:string,error?:unknown){if(this.pending.get(job.key)===job)this.pending.delete(job.key);for(const waiter of job.waiters){waiter.cleanup();error===undefined?waiter.resolve(text!):waiter.reject(error);}job.waiters.clear();}
  private pump(){while(Date.now()>=this.rateLimitedUntil&&this.active<2&&this.jobs.length){const job=this.jobs.shift()!;if(!job.waiters.size)continue;this.active++;
    void this.load(job.text,job.locale,job.controller.signal).then(text=>{job.controller.signal.throwIfAborted();if(this.cache.size>=512)this.cache.delete(this.cache.keys().next().value!);this.cache.set(job.key,{text,at:Date.now()});this.finish(job,text);}).catch(error=>{
      if((error as {details?:{upstreamStatus?:number}})?.details?.upstreamStatus===429){this.rateLimitedUntil=Date.now()+30000;for(const queued of this.jobs.splice(0))this.finish(queued,undefined,this.cooldownError());}
      this.finish(job,undefined,error);
    }).finally(()=>{this.active--;this.pump();});}}
  private async load(text:string,locale:string,signal?:AbortSignal){
    const target=new URL('https://translate.googleapis.com/translate_a/single');for(const [key,value]of Object.entries({client:'gtx',sl:'auto',tl:targetCode(locale),dt:'t',q:text}))target.searchParams.set(key,value);
    const response=await this.transfer(target.href,['translate.googleapis.com'],{signal:AbortSignal.any([AbortSignal.timeout(12000),...(signal?[signal]:[])])});if(!response.ok){await response.body?.cancel();throw Object.assign(fail(response.status===429?'RATE_LIMITED':'NETWORK',response.status===429?429:502),{details:{upstreamStatus:response.status,reason:response.status===429?'UPSTREAM_RATE_LIMITED':'UPSTREAM_HTTP'}});}
    const reader=response.body?.getReader(),chunks:Uint8Array[]=[];let size=0;try{if(reader)for(;;){const result=await reader.read();if(result.done)break;size+=result.value.length;if(size>512000)throw fail('PARSE',502);chunks.push(result.value);}}finally{await reader?.cancel().catch(()=>{});}
    let data:unknown;try{data=JSON.parse(Buffer.concat(chunks).toString('utf8'));}catch{throw fail('PARSE',502);}if(!Array.isArray(data)||!Array.isArray(data[0]))throw fail('PARSE',502);
    const translated=data[0].map(part=>Array.isArray(part)&&typeof part[0]==='string'?part[0]:'').join('').trim();if(!translated)throw fail('PARSE',502);return translated;
  }
}
export function registerTranslationRoutes(router:FastifyInstance,db:DatabaseSync,signal:(request:FastifyRequest)=>AbortSignal|undefined){
  const repository=new TagPackRepository(db);router.get('/tag-packs/available',async request=>({...await repository.available(signal(request)),requestId:request.id}));router.post('/tag-packs/download',async request=>({...await repository.install(request.body,signal(request)),requestId:request.id}));
  const translator=new ContentTranslator();const enabled=()=>{const row=db.prepare("SELECT value_json FROM app_settings WHERE key='contentTranslationEnabled'").get();return row&&JSON.parse(String(row.value_json))===true;};
  router.post('/translate',async request=>{const body=request.body as Row;if(!enabled()||body?.confirmed!==true)throw fail('CONFIRM_REQUIRED',409);if(typeof body.text!=='string'||typeof body.locale!=='string')throw fail('BAD_REQUEST');return {text:await translator.translate(body.text,body.locale,signal(request)),locale:body.locale,requestId:request.id};});
  router.post('/search/translate',async request=>{const body=request.body as Row;if(!enabled()||body?.confirmed!==true)throw fail('CONFIRM_REQUIRED',409);if(typeof body.text!=='string'||!Array.isArray(body.locales)||!body.locales.length||body.locales.length>8||body.locales.some(value=>typeof value!=='string'||!locales.includes(value)))throw fail('BAD_REQUEST');const text=body.text;const results=await Promise.allSettled((body.locales as string[]).map(locale=>translator.translate(text,locale,signal(request))));return {translations:Object.fromEntries(results.flatMap((result,index)=>result.status==='fulfilled'?[[String((body.locales as string[])[index]),result.value]]:[])),failed:results.filter(result=>result.status==='rejected').length,requestId:request.id};});
  router.get('/tag-packs',async request=>({items:db.prepare('SELECT source,locale,version,updated_at FROM tag_translation_packs ORDER BY source,locale').all(),requestId:request.id}));
  router.get('/tag-packs/:source/:locale',async request=>{const p=request.params as Row;const row=db.prepare('SELECT payload_json FROM tag_translation_packs WHERE source=? AND locale=?').get(String(p.source),String(p.locale));if(!row)throw fail('NOT_FOUND',404);return {...JSON.parse(String(row.payload_json)),requestId:request.id};});
  router.post('/tag-packs',async request=>({...storeTagPack(db,request.body),requestId:request.id}));
  router.delete('/tag-packs/:source/:locale',async request=>{const p=request.params as Row;db.prepare('DELETE FROM tag_translation_packs WHERE source=? AND locale=?').run(String(p.source),String(p.locale));return {deleted:true,requestId:request.id};});
}
