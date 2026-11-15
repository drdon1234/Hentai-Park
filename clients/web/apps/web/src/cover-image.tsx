import {useEffect,useReducer,useRef,useState} from 'react';
import {api,mediaUrl,type MediaTokenRequest} from './api.js';
import {t} from './i18n.js';

type Entry={source:string;url?:string;bytes:number;expiresAt:number;used:number;error?:string;controller?:AbortController;timer?:ReturnType<typeof setTimeout>};
type Listener=(reload:boolean)=>void;
const entries=new Map<string,Entry>(),listeners=new Map<string,Set<Listener>>();
let MAX_BYTES=32*1024*1024;const MAX_ENTRIES=128;let retain=true;
export function configureCoverCache(mb:number){retain=mb>0;MAX_BYTES=Math.max(1,Math.min(32,mb))*1024*1024;trim();}
let bytes=0;
const keyOf=(value:MediaTokenRequest)=>JSON.stringify([value.source,value.resourceKey,value.authorizationId]);
const notify=(key:string,reload=false)=>listeners.get(key)?.forEach(fn=>fn(reload));
function remove(key:string){const entry=entries.get(key);if(!entry)return;entry.controller?.abort();if(entry.timer)clearTimeout(entry.timer);if(entry.url)URL.revokeObjectURL(entry.url);bytes-=entry.bytes;entries.delete(key);}
function trim(required=0){
  while(entries.size>=MAX_ENTRIES||bytes+required>MAX_BYTES){
    // Prefer inactive images; keep the total bounded even on unusually dense pages.
    const candidate=[...entries].sort((a,b)=>Number(Boolean(listeners.get(a[0])?.size))-Number(Boolean(listeners.get(b[0])?.size))||a[1].used-b[1].used)[0];
    if(!candidate)break;remove(candidate[0]);notify(candidate[0]);
  }
}
/** Memory-only, tab-local covers. Never retains bytes beyond their server grant. */
export function clearCoverImages(source?:string){
  const keys=new Set([...entries.keys(),...listeners.keys()]);
  for(const key of keys){if(source!==undefined&&JSON.parse(key)[0]!==source)continue;remove(key);notify(key,true);}
}
if(typeof window!=='undefined')window.addEventListener('hp:browse-invalidated',event=>clearCoverImages((event as CustomEvent<{source?:string}>).detail?.source));
function current(key:string){const entry=entries.get(key);return entry&&(!entry.url||entry.expiresAt>Date.now())?entry:undefined;}
function load(key:string,authorization:MediaTokenRequest){
  const existing=current(key);if(existing){existing.used=Date.now();return;}
  remove(key);trim();const controller=new AbortController();
  const entry:Entry={source:authorization.source,bytes:0,expiresAt:0,used:Date.now(),controller};entries.set(key,entry);notify(key);
  const valid=()=>entries.get(key)===entry&&!controller.signal.aborted;
  void (async()=>{
    const grant=await api.mediaToken(authorization,controller.signal);if(!valid())return;
    if(!Number.isFinite(grant.expiresAt)||grant.expiresAt<=Date.now())throw new Error(t('图片授权已过期，请重试。'));
    const response=await fetch(mediaUrl(grant.token),{credentials:'include',cache:'no-store',signal:controller.signal});
    if(!response.ok)throw new Error(t('图片加载失败，请重试。'));
    // Read incrementally: a malicious/oversized cover cannot allocate an unbounded blob.
    const reader=response.body?.getReader();if(!reader)throw new Error(t('图片加载失败，请重试。'));
    const chunks:Uint8Array<ArrayBuffer>[]=[];let size=0;
    try{while(true){const next=await reader.read();if(next.done)break;size+=next.value.byteLength;if(size>MAX_BYTES)throw new Error(t('图片过大，无法显示。'));chunks.push(new Uint8Array(next.value));}}finally{await reader.cancel().catch(()=>{});reader.releaseLock();}
    if(!valid())return;if(grant.expiresAt<=Date.now())throw new Error(t('图片授权已过期，请重试。'));
    // Exclude this in-flight entry while making room for its completed blob.
    entries.delete(key);trim(size);if(controller.signal.aborted)return;entries.set(key,entry);
    entry.url=URL.createObjectURL(new Blob(chunks,{type:response.headers.get('content-type')??'application/octet-stream'}));entry.bytes=size;bytes+=size;entry.expiresAt=grant.expiresAt;entry.controller=undefined;
    entry.timer=setTimeout(()=>{if(entries.get(key)!==entry)return;remove(key);notify(key,true);},Math.min(2147483647,Math.max(0,entry.expiresAt-Date.now())));notify(key);
  })().catch(reason=>{if(!valid())return;entry.controller=undefined;entry.error=reason instanceof Error?reason.message:t('图片加载失败，请重试。');notify(key);});
}
export function CoverImage({authorization,alt,className='',retryLabel=t('重试图片')}:{authorization:MediaTokenRequest;alt:string;className?:string;retryLabel?:string}){
  const key=keyOf(authorization),root=useRef<HTMLDivElement>(null);const [near,setNear]=useState(false),[lost,setLost]=useState(false),[generation,reload]=useReducer(n=>n+1,0),[,render]=useReducer(n=>n+1,0);
  useEffect(()=>{const node=root.current;if(!node)return;let visible=false;const update=()=>setNear(visible&&!document.hidden);const check=()=>{const box=node.getBoundingClientRect();visible=node.getClientRects().length>0&&box.bottom>-300&&box.top<innerHeight+300;update();};const observer=typeof IntersectionObserver==='undefined'?undefined:new IntersectionObserver(items=>{visible=items.some(item=>item.isIntersecting);update();},{rootMargin:'300px 0px'});observer?.observe(node);if(!observer){check();window.addEventListener('scroll',check,{passive:true});window.addEventListener('resize',check);}document.addEventListener('visibilitychange',update);return()=>{observer?.disconnect();window.removeEventListener('scroll',check);window.removeEventListener('resize',check);document.removeEventListener('visibilitychange',update);};},[key]);
  useEffect(()=>{setLost(false);const listener:Listener=reset=>{setLost(!reset&&!entries.has(key));render();if(reset)reload();};let group=listeners.get(key);if(!group){group=new Set();listeners.set(key,group);}group.add(listener);return()=>{group.delete(listener);if(!group.size){listeners.delete(key);const entry=entries.get(key);if(entry?.controller||!retain)remove(key);}};},[key]);
  useEffect(()=>{if(near)load(key,authorization);},[key,near,generation]);
  const entry=current(key);if(entry)entry.used=Date.now();
  return <div ref={root} className={'authorized-image '+className}>{entry?.error||lost?<div className="image-error" role="status"><span>{entry?.error??t('图片已释放，请重新加载。')}</span><button className="chip" onClick={()=>{remove(key);notify(key,true);}}>{retryLabel}</button></div>:entry?.url?<img src={entry.url} alt={alt} loading="lazy" onError={()=>{const value=entries.get(key);if(value){if(value.url)URL.revokeObjectURL(value.url);bytes-=value.bytes;value.bytes=0;value.url=undefined;value.error=t('图片加载失败，请重试。');notify(key);}}}/>:<div className="image-placeholder" aria-hidden="true">{t('图片待加载')}</div>}</div>;
}
