import {useEffect,useReducer,useRef,useState} from 'react';
import {api,mediaUrl,type MediaTokenRequest} from './api.js';
import {t} from './i18n.js';

type Entry={source:string;url?:string;bytes:number;expiresAt:number;used:number;error?:string;controller?:AbortController;timer?:ReturnType<typeof setTimeout>};
export type CoverScope='cards'|'transient';
type Listener=(reload:boolean)=>void;
const entries=new Map<string,Entry>(),listeners=new Map<string,Set<Listener>>();
let MEMORY_BYTES=64*1024*1024;const MEMORY_ENTRIES=128;let PERSIST_BYTES=256*1024*1024;let retain=true;
const coverStore='hentai-park-cover-cache-cards-v1';
if(typeof caches!=='undefined'){void caches.delete('hentai-park-cover-cache-v2');void caches.delete('hentai-park-cover-cache');}
export function configureCoverCache(mb:number){retain=mb>0;const configured=Math.max(16,Math.min(512,mb||128));MEMORY_BYTES=Math.max(16,Math.min(128,configured*.5))*1024*1024;PERSIST_BYTES=configured*1024*1024;trim();}
let bytes=0;
const keyOf=(value:MediaTokenRequest,scope:CoverScope)=>JSON.stringify([scope,value.source,value.resourceKey,value.authorizationId]);
const notify=(key:string,reload=false)=>listeners.get(key)?.forEach(fn=>fn(reload));
function remove(key:string){const entry=entries.get(key);if(!entry)return;entry.controller?.abort();if(entry.timer)clearTimeout(entry.timer);if(entry.url)URL.revokeObjectURL(entry.url);bytes-=entry.bytes;entries.delete(key);}
function trim(required=0){
  while(entries.size>=MEMORY_ENTRIES||bytes+required>MEMORY_BYTES){
    // Prefer inactive images; keep the total bounded even on unusually dense pages.
    const candidate=[...entries].sort((a,b)=>Number(Boolean(listeners.get(a[0])?.size))-Number(Boolean(listeners.get(b[0])?.size))||a[1].used-b[1].used)[0];
    if(!candidate)break;remove(candidate[0]);notify(candidate[0]);
  }
}
/** 主页和域页卡片使用持久化缓存；其他图片只在当前挂载期间保留。 */
export function clearCoverImages(source?:string){
  const keys=new Set([...entries.keys(),...listeners.keys()]);
  for(const key of keys){if(source!==undefined&&JSON.parse(key)[1]!==source)continue;remove(key);notify(key,true);}
}
if(typeof window!=='undefined')window.addEventListener('hp:browse-invalidated',event=>clearCoverImages((event as CustomEvent<{source?:string}>).detail?.source));
function current(key:string){const entry=entries.get(key);return entry&&(!entry.url||entry.expiresAt>Date.now())?entry:undefined;}
async function cachedCover(key:string,scope:CoverScope){
  if(scope!=='cards'||!retain||typeof caches==='undefined')return undefined;
  try{const cache=await caches.open(coverStore),response=await cache.match('/'+coverStore+'/'+encodeURIComponent(key));if(!response)return;const expires=Number(response.headers.get('x-hp-expires'));if(!Number.isFinite(expires)||expires<=Date.now()){await cache.delete(response.url);return;}return response;}catch{return undefined;}
}
async function trimPersistent(cache:Cache){try{const keys=await cache.keys(),entries:(Array<{request:Request;size:number;used:number}>)=[];for(const request of keys){const response=await cache.match(request);if(!response)continue;const expires=Number(response.headers.get('x-hp-expires'));if(!Number.isFinite(expires)||expires<=Date.now()){await cache.delete(request);continue;}const size=Number(response.headers.get('content-length'))||0;entries.push({request,size,used:Number(response.headers.get('x-hp-used'))||0});}let total=entries.reduce((sum,item)=>sum+item.size,0);for(const item of entries.sort((a,b)=>a.used-b.used)){if(total<=PERSIST_BYTES)break;await cache.delete(item.request);total-=item.size;}}catch{/* Optional browser cache. */}}
 function saveCover(key:string,blob:Blob,expiresAt:number,scope:CoverScope){if(scope!=='cards'||!retain||typeof caches==='undefined'||blob.size>8*1024*1024)return;void caches.open(coverStore).then(async cache=>{const now=String(Date.now());await cache.put('/'+coverStore+'/'+encodeURIComponent(key),new Response(blob,{headers:{'content-type':blob.type||'application/octet-stream','content-length':String(blob.size),'x-hp-expires':String(expiresAt),'x-hp-used':now}}));await trimPersistent(cache);}).catch(()=>{});}
function load(key:string,authorization:MediaTokenRequest,scope:CoverScope){
  const existing=current(key);if(existing){existing.used=Date.now();return;}
  remove(key);trim();const controller=new AbortController();
  const entry:Entry={source:authorization.source,bytes:0,expiresAt:0,used:Date.now(),controller};entries.set(key,entry);notify(key);
  const valid=()=>entries.get(key)===entry&&!controller.signal.aborted;
  void (async()=>{
    const stored=await cachedCover(key,scope);if(!valid())return;
    let response:Response|undefined=stored;
    let expiresAt=stored?Number(stored.headers.get('x-hp-expires')):0;
    if(!response){
      const grant=await api.mediaToken(authorization,controller.signal);if(!valid())return;
      if(!Number.isFinite(grant.expiresAt)||grant.expiresAt<=Date.now())throw new Error(t('图片授权已过期，请重试。'));
      expiresAt=grant.expiresAt;
      response=await fetch(mediaUrl(grant.token),{credentials:'include',cache:'no-store',signal:controller.signal});
    }
    if(!response.ok)throw new Error(t('图片加载失败，请重试。'));
    // Read incrementally: a malicious/oversized cover cannot allocate an unbounded blob.
    const reader=response.body?.getReader();if(!reader)throw new Error(t('图片加载失败，请重试。'));
    const chunks:Uint8Array<ArrayBuffer>[]=[];let size=0;
    try{while(true){const next=await reader.read();if(next.done)break;size+=next.value.byteLength;if(size>MEMORY_BYTES)throw new Error(t('图片过大，无法显示。'));chunks.push(new Uint8Array(next.value));}}finally{await reader.cancel().catch(()=>{});reader.releaseLock();}
    if(!valid())return;if(expiresAt<=Date.now())throw new Error(t('图片授权已过期，请重试。'));
    // Exclude this in-flight entry while making room for its completed blob.
    entries.delete(key);trim(size);if(controller.signal.aborted)return;entries.set(key,entry);
    const blob=new Blob(chunks,{type:response.headers.get('content-type')??'application/octet-stream'});entry.url=URL.createObjectURL(blob);entry.bytes=size;bytes+=size;entry.expiresAt=expiresAt;entry.controller=undefined;if(!stored)saveCover(key,blob,expiresAt,scope);
    entry.timer=setTimeout(()=>{if(entries.get(key)!==entry)return;remove(key);notify(key,true);},Math.min(2147483647,Math.max(0,entry.expiresAt-Date.now())));notify(key);
  })().catch(reason=>{if(!valid())return;entry.controller=undefined;entry.error=reason instanceof Error?reason.message:t('图片加载失败，请重试。');notify(key);});
}
export function CoverImage({authorization,alt,className='',retryLabel=t('重试图片'),scope='transient'}:{authorization:MediaTokenRequest;alt:string;className?:string;retryLabel?:string;scope?:CoverScope}){
  const key=keyOf(authorization,scope),root=useRef<HTMLDivElement>(null);const [near,setNear]=useState(false),[lost,setLost]=useState(false),[generation,reload]=useReducer(n=>n+1,0),[,render]=useReducer(n=>n+1,0);
  useEffect(()=>{const node=root.current;if(!node)return;let visible=false;const scrollRoot=node.closest<HTMLElement>('.shelf-track')??null;const update=()=>setNear(visible&&!document.hidden);const check=()=>{const box=node.getBoundingClientRect(),rootBox=scrollRoot?.getBoundingClientRect();visible=node.getClientRects().length>0&&(!rootBox||box.right>rootBox.left-300&&box.left<rootBox.right+300&&box.bottom>rootBox.top-300&&box.top<rootBox.bottom+300)&&(!rootBox||rootBox.width>0&&rootBox.height>0);update();};const observer=typeof IntersectionObserver==='undefined'?undefined:new IntersectionObserver(items=>{visible=items.some(item=>item.isIntersecting);update();},{root:scrollRoot,rootMargin:'300px'});observer?.observe(node);if(!observer){check();window.addEventListener('scroll',check,{passive:true});window.addEventListener('resize',check);}document.addEventListener('visibilitychange',update);return()=>{observer?.disconnect();window.removeEventListener('scroll',check);window.removeEventListener('resize',check);document.removeEventListener('visibilitychange',update);};},[key]);
  useEffect(()=>{setLost(false);const listener:Listener=reset=>{setLost(!reset&&!entries.has(key));render();if(reset)reload();};let group=listeners.get(key);if(!group){group=new Set();listeners.set(key,group);}group.add(listener);return()=>{group.delete(listener);if(!group.size){listeners.delete(key);const entry=entries.get(key);if(scope==='transient'||entry?.controller||!retain)remove(key);}};},[key,scope]);
  useEffect(()=>{if(near)load(key,authorization,scope);},[key,near,generation,scope]);
  const entry=current(key);if(entry)entry.used=Date.now();
  return <div ref={root} className={'authorized-image '+className}>{entry?.error||lost?<div className="image-error" role="status"><span>{entry?.error??t('图片已释放，请重新加载。')}</span><button className="chip" onClick={()=>{remove(key);notify(key,true);}}>{retryLabel}</button></div>:entry?.url?<img src={entry.url} alt={alt} loading="lazy" onError={()=>{const value=entries.get(key);if(value){if(value.url)URL.revokeObjectURL(value.url);bytes-=value.bytes;value.bytes=0;value.url=undefined;value.error=t('图片加载失败，请重试。');notify(key);}}}/>:<div className="image-placeholder" aria-hidden="true">{t('图片待加载')}</div>}</div>;
}
