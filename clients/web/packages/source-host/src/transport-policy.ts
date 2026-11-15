import type {PluginManifest} from '@hentai-park/source-contract';
import type {NetworkRequest} from './index.js';
const blocked=(message:string)=>Object.assign(new Error(message),{code:'BLOCKED',statusCode:400,publicError:true,causeCategory:'source',retryable:false});
const config=(message:string)=>Object.assign(new Error(message),{code:'CONFIG',statusCode:400,publicError:true,causeCategory:'source',retryable:false});
export function hostAllowed(host:string,domains:string[]){const h=host.toLowerCase().replace(/\.$/,'');return domains.some(entry=>{const d=entry.replace(/^\*\./,'').toLowerCase().replace(/\.$/,'');return entry.startsWith('*.')?h.endsWith('.'+d)&&h.split('.').length===d.split('.').length+1:h===d||h.endsWith('.'+d);});}
export const REDIRECT_STATUSES:ReadonlySet<number>=new Set([301,302,303,307,308]);
const REDIRECT_HEADERS=new Set(['user-agent','accept','accept-language','accept-encoding','range','cache-control','pragma']);
/** Applies before every redirected transfer; destination authorization still runs per hop. */
export function redirectRequest(req:NetworkRequest,from:URL,to:URL,status:number):NetworkRequest {
 if(!REDIRECT_STATUSES.has(status))throw blocked('unsupported redirect status');let method=req.method??'GET';let headers={...req.headers},body=req.body,bodyBase64=req.bodyBase64;
 if(status===303&&method!=='HEAD'||(status===301||status===302)&&method==='POST'){
  method='GET';body=undefined;bodyBase64=undefined;headers=Object.fromEntries(Object.entries(headers).filter(([name])=>!name.toLowerCase().startsWith('content-')&&!['transfer-encoding','digest'].includes(name.toLowerCase())));
 }
 const cross=from.origin!==to.origin;
 if(cross){if(body!==undefined||bodyBase64!==undefined||!['GET','HEAD'].includes(method))throw blocked('cross-origin redirect cannot replay a request body or unsafe method');headers=Object.fromEntries(Object.entries(headers).filter(([name])=>REDIRECT_HEADERS.has(name.toLowerCase())));}
 else if(!['GET','HEAD'].includes(method)&&req.followRedirects===false)throw blocked('redirect following is disabled');
 return {...req,url:to.href,method,headers,body,bodyBase64};
}
/** Native media and images never inherit source-account credentials. */
export function mediaRequestHeaders(manifest:PluginManifest,supplied:unknown={},image=false):Record<string,string>{
 const originDomains=image?[...manifest.domains,...(manifest.imageNetwork?.domains??[])]:manifest.domains;
 const referrerDomains=image?originDomains:[...manifest.domains,...(manifest.media?.referrerDomains??[])];
 const headers:Record<string,string>={};
 const value=(name:string,raw:string)=>{if(raw.length>4096||/[\r\n]/.test(raw))throw config('invalid media request header');if(name==='origin'||name==='referer'){let url:URL;try{url=new URL(raw);}catch{throw config('invalid media header URL');}if(url.protocol!=='https:'||url.username||url.password||url.port||url.hash||!hostAllowed(url.hostname,name==='origin'?originDomains:referrerDomains)||name==='origin'&&raw!==url.origin)throw config('media header origin is outside its permission');}return raw;};
 if(!supplied||typeof supplied!=='object'||Array.isArray(supplied))throw config('invalid media headers');
 for(const [key,raw]of Object.entries(supplied)){const name=key.toLowerCase();const standard=['origin','referer','accept','accept-language',...(image?['user-agent']:[])].includes(name);const scoped=!image&&manifest.media?.mode==='native'&&manifest.media.requestHeaders?.[name]?.scope==='playback-origin';if(!standard&&!scoped)continue;if(typeof raw!=='string')throw config('invalid media request header');headers[name]=value(name,raw);}
 return headers;
}
