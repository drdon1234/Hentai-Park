import type {MediaAttachment} from './album-resource.js';
import { randomBytes } from 'node:crypto';
import dns from 'node:dns/promises';
import { fetchPinnedResource,isPrivateAddress,hostAllowed,decodeImage } from '@hentai-park/source-host';
import type { ImageDecrypt } from '@hentai-park/source-contract';
import {unwrapMediaResponse} from './hls-resource.js';

export interface InlineHls { manifest: string; keys: Record<string,string>; }
export interface MediaGrant { playlist?:boolean; attachment?:MediaAttachment; source: string; resourceKey: string; sessionId?: string; url: string; resources: string[]; domains: string[]; scope?: 'session'; expiresAt: number; revokedAt?: number; hls?: InlineHls;image?:boolean;imageDecrypt?:ImageDecrypt; inlineImage?: {mime:string;bytes:Uint8Array};inlineCaption?:string; fetchResource?: (url:string,options:{signal?:AbortSignal;range?:string;method?:'GET'|'HEAD'})=>Promise<Response>; }
export interface MediaFetch { status: number; headers: Headers; body: ReadableStream<Uint8Array> | null; signal?: AbortSignal; }
export interface MediaGrant {resolve?:(signal?:AbortSignal)=>Promise<Omit<MediaGrant,'expiresAt'|'resources'>>;}

export class MediaProxy {
  // Covers are independent, bounded image requests. Six slots made a busy
  // homepage serialize the tail of the first visible shelves; keep a larger
  // fixed bound while retaining back-pressure for the upstream service.
  imageConcurrency=()=>12;
  private imageActive=0;
  private imageWaiters=new Set<()=>void>();
  private async imageSlot(signal?:AbortSignal){
    while(this.imageActive>=this.imageConcurrency()){
      await new Promise<void>((resolve,reject)=>{const done=()=>{this.imageWaiters.delete(done);signal?.removeEventListener('abort',cancel);resolve();};const cancel=()=>{this.imageWaiters.delete(done);signal?.removeEventListener('abort',cancel);reject(signal?.reason);};this.imageWaiters.add(done);signal?.addEventListener('abort',cancel,{once:true});if(signal?.aborted)cancel();});
    }
    signal?.throwIfAborted();this.imageActive++;
    return ()=>{this.imageActive--;for(const wake of [...this.imageWaiters])wake();};
  }
  private readonly controllers=new Map<string,AbortController>();
  private readonly sessionEpochs=new Map<string,number>();
  private readonly sourceEpochs=new Map<string,number>();
  private readonly grants = new Map<string, MediaGrant>();
  private readonly playlists=new Map<string,Set<string>>();
  private readonly resourceIds = new Map<string, Map<string, string>>();
  private readonly fetchImpl: typeof fetch;
  private readonly now: () => number;
  private readonly lookup: typeof dns.lookup;
  // DNS validation is required both when issuing a grant and when consuming it.
  // Keep only short-lived, policy-scoped results so the security check remains
  // effective without making every cover pay for two DNS lookups.
  private readonly validated = new Map<string,{url: URL; expires: number}>();
  private readonly validationLifetime = 60_000;
  private readonly imageCache = new Map<string,{bytes: Buffer; mime: string; expires: number; used: number}>();
  private readonly imageCacheLifetime = 300_000;
  private readonly imageCacheLimit = 128;
  constructor(fetchImpl: typeof fetch = fetch, now = () => Date.now(), lookup: typeof dns.lookup = dns.lookup) { this.fetchImpl = fetchImpl; this.now = now; this.lookup = lookup; }
  private async validate(input: string, domains: string[] | undefined, allowPort=false) {
    // A rejected source URL is not a malformed client authorization descriptor.
    const blocked=(reason:string)=>Object.assign(new Error('media upstream is blocked'),{statusCode:403,code:'MEDIA_SOURCE_BLOCKED',publicError:true,causeCategory:'source',retryable:false,details:{reason}});
    let u:URL;try{u=new URL(input);}catch{throw blocked('URL_INVALID');}
    if(u.protocol!=='https:'||u.username||u.password||!allowPort&&Boolean(u.port)||domains!==undefined&&!hostAllowed(u.hostname,domains))throw blocked('URL_POLICY');
    const policy=JSON.stringify([u.protocol,u.hostname,u.port,allowPort,domains?.slice().sort()??null]);
    const cached=this.validated.get(policy);
    if(cached&&cached.expires>this.now())return new URL(cached.url.href);
    const records=await this.lookup(u.hostname,{all:true});if(!records.length||records.some(r=>isPrivateAddress(r.address)))throw blocked('DNS_PRIVATE');
    this.validated.set(policy,{url:new URL(u.href),expires:this.now()+this.validationLifetime});
    if(this.validated.size>4096){const cutoff=this.now();for(const [key,value] of this.validated)if(value.expires<=cutoff)this.validated.delete(key);}
    return u;
  }
  async issue(input: Omit<MediaGrant, 'expiresAt' | 'resources'> & { resources?: string[]; ttlMs?: number }) { const epoch=input.sessionId?this.sessionEpochs.get(input.sessionId)??0:0,sourceEpoch=this.sourceEpochs.get(input.source)??0;if(input.hls){if(typeof input.hls.manifest!=='string'||Buffer.byteLength(input.hls.manifest)>2_000_000||!input.hls.keys||Object.keys(input.hls.keys).length>32)throw Object.assign(new Error('invalid inline HLS'),{statusCode:400});for(const [url,key]of Object.entries(input.hls.keys)){await this.validate(url,input.scope==='session'||input.image?undefined:input.domains);if(typeof key!=='string'||Buffer.from(key,'base64').length!==16)throw Object.assign(new Error('invalid HLS key'),{statusCode:400});}} const urls = [...new Set([input.url, ...(input.resources ?? [])])]; const resources: string[] = []; for (const resource of urls) resources.push(input.attachment||input.inlineImage||input.inlineCaption!==undefined ? 'inline' : (await this.validate(resource,input.scope==='session'||input.image?undefined:input.domains,input.image===true)).toString());if(input.inlineImage&&(!['image/png','image/jpeg','image/gif','image/webp'].includes(input.inlineImage.mime)||input.inlineImage.bytes.length>512*1024))throw Object.assign(new Error('invalid inline image'),{statusCode:400}); if((this.sourceEpochs.get(input.source)??0)!==sourceEpoch||input.sessionId&&(this.sessionEpochs.get(input.sessionId)??0)!==epoch)throw Object.assign(new Error('media session was revoked'),{code:'CANCELLED',statusCode:499,publicError:true});const url = resources[0]; const token = randomBytes(32).toString('base64url'); const expiresAt = this.now() + Math.min(Math.max(input.ttlMs ?? 60_000, 1_000), 300_000); this.purgeExpired(); this.grants.set(token, { ...input, url, resources, expiresAt }); this.controllers.set(token,new AbortController()); this.resourceIds.set(token, new Map());this.playlists.set(token,new Set(input.playlist?[url]:[])); return { token, expiresAt }; }
  close(){for(const token of this.grants.keys())this.revoke(token);}
  async renew(token:string,sessionId:string,signal?:AbortSignal){const grant=this.grants.get(token);if(!grant||grant.sessionId!==sessionId||grant.expiresAt<=this.now()||!grant.resolve)throw Object.assign(new Error('media token expired'),{code:'NOT_FOUND',statusCode:404,publicError:true});let next:Omit<MediaGrant,'expiresAt'|'resources'>;try{next=await grant.resolve(signal);}catch(error){if(['AUTH','CONFIG','BLOCKED','NOT_FOUND'].includes(String((error as {code?:string}).code)))this.revokeResource(grant.source,grant.resourceKey);throw error;}if(this.grants.get(token)!==grant)throw Object.assign(new Error('media session was revoked'),{code:'CANCELLED',statusCode:499,publicError:true});if(next.source!==grant.source||next.resourceKey!==grant.resourceKey||next.sessionId!==sessionId){this.revokeResource(grant.source,grant.resourceKey);throw Object.assign(new Error('media identity changed'),{code:'BLOCKED',statusCode:403,publicError:true});}const inspected=await this.issue({...next,ttlMs:60_000});const fresh=this.grants.get(inspected.token)!;const changed=fresh.url!==grant.url||JSON.stringify(fresh.hls)!==JSON.stringify(grant.hls);if(changed)return {...inspected,changed:true};this.grants.set(token,{...fresh,resources:grant.resources});this.revoke(inspected.token);if(!this.controllers.has(token))this.controllers.set(token,new AbortController());return {token,expiresAt:fresh.expiresAt,changed:false};}
  revoke(token: string) { this.controllers.get(token)?.abort();this.controllers.delete(token);this.grants.delete(token); this.resourceIds.delete(token);this.playlists.delete(token); }
  revokeSession(sessionId: string) { this.sessionEpochs.set(sessionId,(this.sessionEpochs.get(sessionId)??0)+1);for (const [token, grant] of this.grants) if (grant.sessionId === sessionId) this.revoke(token); }
  revokeResource(source: string, resourceKey: string) { for (const [token, grant] of this.grants) if (grant.source === source && grant.resourceKey === resourceKey) this.revoke(token); }
  revokeSource(source:string){this.sourceEpochs.set(source,(this.sourceEpochs.get(source)??0)+1);for(const [token,grant]of this.grants)if(grant.source===source)this.revoke(token);}
  purgeExpired() { const now = this.now(); for (const [token, grant] of this.grants) if (grant.expiresAt <= now || grant.revokedAt) this.revoke(token); }
  async fetch(token: string, headers: HeadersInit = {}, method = 'GET', resourceId?: string, sessionId?: string,signal?:AbortSignal): Promise<MediaFetch> {
    const grantSignal=this.controllers.get(token)?.signal;
    const readSignal=signal&&grantSignal?AbortSignal.any([signal,grantSignal]):signal??grantSignal;
    const release=this.grants.get(token)?.image?await this.imageSlot(readSignal):undefined;
    try{const result=await this.fetchContent(token,headers,method,resourceId,sessionId,readSignal);
    return {...result,signal:grantSignal};}finally{release?.();}
  }
  private async fetchContent(token: string, headers: HeadersInit = {}, method = 'GET', resourceId?: string, sessionId?: string,signal?:AbortSignal): Promise<MediaFetch> { const grant = this.grants.get(token); if (!grant || grant.revokedAt || grant.expiresAt <= this.now() || (grant.sessionId && grant.sessionId !== sessionId)) { throw Object.assign(new Error('media token expired'), { statusCode: 404 }); } const raw = resourceId ? this.resourceIds.get(token)?.get(resourceId) : grant.url; if (!raw) throw Object.assign(new Error('media resource is outside authorization chain'), { statusCode: 403 }); const canonical = (grant.attachment||grant.inlineImage||grant.inlineCaption!==undefined)&&raw==='inline'?'inline':(await this.validate(raw,grant.scope==='session'||grant.image?undefined:grant.domains,grant.image===true)).toString(); if (!grant.resources.includes(canonical)) throw Object.assign(new Error('media resource is outside authorization chain'), { statusCode: 403 }); const requestHeaders = new Headers(headers); const init: RequestInit = { method:grant.image?'GET':method, redirect: 'manual', signal: AbortSignal.any([AbortSignal.timeout(30_000),...(signal?[signal]:[]),...(this.controllers.has(token)?[this.controllers.get(token)!.signal]:[])]) }; const range = requestHeaders.get('range'); if (range&&!grant.image) init.headers = { range }; const inline = grant.inlineCaption!==undefined?new Response(init.method==='HEAD'?null:grant.inlineCaption,{headers:{'content-type':'text/vtt; charset=utf-8'}}):grant.inlineImage ? new Response(init.method==='HEAD'?null:Buffer.from(grant.inlineImage.bytes),{headers:{'content-type':grant.inlineImage.mime}}) : grant.hls && canonical===grant.url ? new Response(init.method==='HEAD'?null:grant.hls.manifest,{headers:{'content-type':'application/vnd.apple.mpegurl'}}) : grant.hls?.keys[canonical] ? new Response(init.method==='HEAD'?null:Buffer.from(grant.hls.keys[canonical],'base64'),{headers:{'content-type':'application/octet-stream'}}) : undefined; const response = grant.attachment?await grant.attachment.read({signal:init.signal??undefined,range:grant.image?undefined:range??undefined,method:init.method==='HEAD'?'HEAD':'GET'}):inline ?? (this.fetchImpl !== fetch ? await this.fetchImpl(canonical,init) : grant.fetchResource ? await grant.fetchResource(canonical,{signal:init.signal??undefined,range:grant.image?undefined:range??undefined,method:init.method==='HEAD'?'HEAD':'GET'}) : await fetchPinnedResource(canonical, grant.scope==='session'||grant.image?undefined:grant.domains, {signal:init.signal ?? undefined, headers:range&&!grant.image?{range}:undefined,method:init.method==='HEAD'?'HEAD':'GET',allowPort:grant.image===true})); if (response.status >= 300 && response.status < 400) throw Object.assign(new Error('media redirect blocked'), { statusCode: 502 });
    if(!response.ok&&response.status!==416){await response.body?.cancel();throw Object.assign(new Error('Upstream media failed'),{statusCode:response.status,code:response.status===401||response.status===403?'AUTH':response.status===404?'NOT_FOUND':'NETWORK',causeCategory:'source',publicError:true,retryable:response.status>=500||response.status===404});}
    if(grant.image&&response.ok){const reader=response.body?.getReader();const chunks:Uint8Array[]=[];let size=0;try{if(reader)for(;;){const next=await reader.read();if(next.done)break;size+=next.value.length;if(size>20*1024*1024)throw Object.assign(new Error('image too large'),{statusCode:502});chunks.push(next.value);}}finally{await reader?.cancel().catch(()=>{});}let decoded;try{decoded=decodeImage(Buffer.concat(chunks),grant.imageDecrypt);}catch(error){throw Object.assign(error as Error,{statusCode:502,publicError:true,causeCategory:'source'});}const {bytes,mime:type}=decoded;const headers=new Headers({'content-type':type,'content-length':String(bytes.length),'cache-control':'private, no-store','accept-ranges':'bytes'});let status=200,body=bytes;
      if(range&&method!=='HEAD'){const match=/^bytes=(\d*)-(\d*)$/.exec(range);const start=match?.[1]?Number(match[1]):match?.[2]?Math.max(0,bytes.length-Number(match[2])):NaN;const end=match?.[1]&&match[2]?Math.min(bytes.length-1,Number(match[2])):bytes.length-1;if(!Number.isSafeInteger(start)||!Number.isSafeInteger(end)||start<0||start>=bytes.length||end<start){headers.set('content-range','bytes */'+bytes.length);headers.set('content-length','0');return {status:416,headers,body:null};}body=bytes.subarray(start,end+1);status=206;headers.set('content-range','bytes '+start+'-'+end+'/'+bytes.length);headers.set('content-length',String(body.length));}
      if(bytes.length<=4*1024*1024){const cacheKey=JSON.stringify([canonical,grant.imageDecrypt??null]);this.imageCache.set(cacheKey,{bytes:Buffer.from(bytes),mime:type,expires:this.now()+this.imageCacheLifetime,used:this.now()});if(this.imageCache.size>this.imageCacheLimit){const oldest=[...this.imageCache.entries()].sort((a,b)=>a[1].used-b[1].used)[0];if(oldest)this.imageCache.delete(oldest[0]);}}
      return {status,headers,body:method==='HEAD'?null:new ReadableStream({start(controller){controller.enqueue(body);controller.close();}})};}
    const playlistBase=this.fetchImpl===fetch&&response.url?(await this.validate(response.url,grant.scope==='session'||grant.image?undefined:grant.domains)).href:canonical;
    const decodedResponse=method==='HEAD'?response:await unwrapMediaResponse(response,this.playlists.get(token)?.has(canonical)?2_000_000:32*1024*1024,Boolean(resourceId&&!this.playlists.get(token)?.has(canonical))); 
    const type = (decodedResponse.headers.get('content-type') ?? '').replace(/^binary\/octet-stream\b/i,'application/octet-stream');
    const playlist=this.playlists.get(token)?.has(canonical)||/mpegurl/i.test(type)||/\.m3u8(?:\?|$)/i.test(canonical);
    if (response.ok && !playlist && !/^(?:image\/|video\/|audio\/|text\/vtt|application\/(?:vnd\.apple\.mpegurl|x-mpegurl|octet-stream))/i.test(type)) { await decodedResponse.body?.cancel(); throw Object.assign(new Error('media content type blocked'), { statusCode: 502 }); }
    const outHeaders = new Headers(decodedResponse.headers); if(type)outHeaders.set('content-type',type); outHeaders.set('cache-control', 'private, no-store');
    if(playlist){outHeaders.set('content-type','application/vnd.apple.mpegurl');outHeaders.delete('content-length');}
    if (method !== 'HEAD' && response.ok && playlist) {
      const reader=decodedResponse.body?.getReader();const chunks:Uint8Array[]=[];let size=0;if(reader)try{for(;;){const next=await reader.read();if(next.done)break;size+=next.value.length;if(size>2_000_000)throw Object.assign(new Error('playlist too large'),{statusCode:502});chunks.push(next.value);}}finally{await reader.cancel().catch(()=>{});reader.releaseLock();}const text=Buffer.concat(chunks).toString('utf8'); if (!text.trimStart().startsWith('#EXTM3U') || text.length > 2_000_000) throw Object.assign(new Error('playlist too large'), { statusCode: 502 });
      const authorize = async (uri: string,childPlaylist=false) => { const url = (await this.validate(new URL(uri, playlistBase).toString(),grant.scope==='session'?undefined:grant.domains)).toString(); if(childPlaylist)this.playlists.get(token)?.add(url);if (!grant.resources.includes(url)){if(grant.resources.length>=10000)throw Object.assign(new Error('playlist resource limit'),{statusCode:502});grant.resources.push(url);} const ids = this.resourceIds.get(token)!; let id = [...ids].find(([, value]) => value === url)?.[0]; if (!id) { id = randomBytes(16).toString('base64url'); ids.set(id, url); } return `/api/v1/media/${token}?resource=${id}`; };
      const lines: string[] = []; let nextPlaylist=false;for (const line of text.split(/\r?\n/)) { if (!line || line.startsWith('#') && !line.includes('URI="')) { if(line.startsWith('#EXT-X-STREAM-INF:'))nextPlaylist=true;lines.push(line); continue; } if (line.startsWith('#')) { let rewritten = line; for (const match of line.matchAll(/URI="([^"]+)"/g)) rewritten = rewritten.replace(match[0], `URI="${await authorize(match[1]!,/^#EXT-X-(?:MEDIA|I-FRAME-STREAM-INF):/.test(line))}"`); lines.push(rewritten); } else  {lines.push(await authorize(line.trim(),nextPlaylist));nextPlaylist=false;} }
      const body = new TextEncoder().encode(lines.join('\n')); outHeaders.delete('content-length'); outHeaders.set('content-type', 'application/vnd.apple.mpegurl'); return { status: response.status, headers: outHeaders, body: new ReadableStream({ start(controller) { controller.enqueue(body); controller.close(); } }) };
    }
    return { status: response.status, headers: outHeaders, body: decodedResponse.body };
  }
}
