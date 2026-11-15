import {chromium,type Browser,type BrowserContext,type Page} from 'playwright';
import dns from 'node:dns/promises';
import {isAbsolute} from 'node:path';
import {NetworkBroker,validateNetworkUrl,redirectRequest,hostAllowed,type NetworkRequest,type NetworkResponse} from '@hentai-park/source-host';
import {toPluginError,toAbortError,type PluginManifest,type PluginError} from '@hentai-park/source-contract';
import {interceptRequests} from './interception.js';
import type {BrowserCookie} from './index.js';
import {createBrowserTunnel} from './browser-tunnel.js';
import {getSourceUserAgent} from './user-agent.js';

export interface GuardedContextOptions {
  domains:string[];
  browserNetwork?:boolean;
  prepareRequest?:(request:NetworkRequest)=>Promise<Record<string,string>>;
  response?:(request:{url:string;method:string},response:NetworkResponse)=>Promise<void>;
  navigationDomains?:string[];
  frameDomains?:string[];
  resourceDomains?:string[];
  maxResourceBytes?:number;
  resourceUrls?:Set<string>;
  cookies?:BrowserCookie[];
  storageState?:Awaited<ReturnType<BrowserContext['storageState']>>;
  /** Server-derived per-game profile path; never accepted from a client request. */
  userDataDirectory?:string;
  executablePath?:string;
  signal?:AbortSignal;
  allowPopups?:boolean;
  lookup?:typeof dns.lookup;
  transport?:(request:NetworkRequest,domains:string[])=>Promise<NetworkResponse>;
}
export interface GuardedPageContext {context:BrowserContext;page:Page;readonly lastError?:PluginError;resetError():void;close():Promise<void>;}
const failure=(code:string)=>Object.assign(new Error('Controlled browser operation failed'),{code,retryable:['NETWORK','TIMEOUT'].includes(code)});
let active=0;

/** A browser process with no network path outside the shared checked HTTP boundary. */
export async function createGuardedContext(options:GuardedContextOptions):Promise<GuardedPageContext> {
  options.signal?.throwIfAborted();if(active>=6)throw failure('RATE_LIMITED');active++;
  let tunnel:Awaited<ReturnType<typeof createBrowserTunnel>>|undefined;
  let browser:Browser|undefined,context:BrowserContext|undefined,closed=false,lastError:PluginError|undefined,closing:Promise<void>|undefined;
  const controllers=new Set<AbortController>();
  const close=()=>{if(closing)return closing;closed=true;active--;for(const controller of controllers)controller.abort(options.signal?.aborted?options.signal.reason:undefined);controllers.clear();options.signal?.removeEventListener('abort',cancel);closing=(async()=>{try{await context?.close();}finally{try{await browser?.close();}finally{await tunnel?.close();}}})();return closing;};
  const cancel=()=>{void close().catch(()=>{});};options.signal?.addEventListener('abort',cancel,{once:true});
  try {
    if(options.maxResourceBytes!==undefined&&(!Number.isSafeInteger(options.maxResourceBytes)||options.maxResourceBytes<1||options.maxResourceBytes>128*1024*1024))throw failure('CONFIG');if(options.userDataDirectory!==undefined&&(typeof options.userDataDirectory!=='string'||!isAbsolute(options.userDataDirectory)||options.storageState!==undefined))throw failure('CONFIG');
    if(options.browserNetwork){if(options.transport)throw failure('CONFIG');tunnel=await createBrowserTunnel();}
    const launchNetwork=tunnel?{channel:'chromium',proxy:{server:tunnel.server,bypass:'<-loopback>'},args:['--autoplay-policy=no-user-gesture-required','--disable-quic','--force-webrtc-ip-handling-policy=disable_non_proxied_udp','--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1']}:{args:['--autoplay-policy=no-user-gesture-required']};
    if(!options.userDataDirectory){browser=await chromium.launch({headless:true,executablePath:options.executablePath??process.env.PLAYWRIGHT_EXECUTABLE_PATH,...launchNetwork});if(closed){await browser.close();throw options.signal?.aborted?toAbortError(options.signal):failure('CANCELLED');}}
    const storage=options.storageState;
    const storageDomains=[...options.domains,...(options.navigationDomains??[])];
    if(storage){if(typeof storage!=='object'||Buffer.byteLength(JSON.stringify(storage))>1024*1024||storage.cookies.length>1000||storage.origins.length>64)throw failure('CONFIG');for(const cookie of storage.cookies)if(!hostAllowed(cookie.domain.replace(/^\./,''),storageDomains))throw failure('BLOCKED');for(const item of storage.origins){const url=new URL(item.origin);if(url.origin!==item.origin||url.protocol!=='https:'||url.username||url.password||url.port||!hostAllowed(url.hostname,storageDomains)||item.localStorage.length>1000)throw failure('BLOCKED');}}
    if(options.cookies?.some(cookie=>!hostAllowed(cookie.domain.replace(/^\./,''),options.domains)))throw failure('BLOCKED');
    context=options.userDataDirectory?await chromium.launchPersistentContext(options.userDataDirectory,{headless:true,executablePath:options.executablePath??process.env.PLAYWRIGHT_EXECUTABLE_PATH,...launchNetwork,serviceWorkers:'block',acceptDownloads:false,viewport:{width:960,height:540},deviceScaleFactor:1,userAgent:getSourceUserAgent()}):await browser!.newContext({serviceWorkers:'block',acceptDownloads:false,viewport:{width:960,height:540},deviceScaleFactor:1,storageState:storage,userAgent:getSourceUserAgent()});
    if(closed){await context.close();throw options.signal?.aborted?toAbortError(options.signal):failure('CANCELLED');}
    if(options.cookies?.length)await context.addCookies(options.cookies);
    await context.routeWebSocket('**/*',socket=>socket.close());
    const page=await context.newPage();
    page.on('popup',popup=>{if(!options.allowPopups)void popup.close();});page.on('download',download=>{void download.cancel();});page.on('dialog',dialog=>{void dialog.dismiss();});
    await interceptRequests(await context.newCDPSession(page),async route=>{
      const controller=new AbortController();controllers.add(controller);const request=route.request();
      try {
        if(closed)throw options.signal?.aborted?toAbortError(options.signal):failure('CANCELLED');if((request.redirectCount?.()??0)>5)throw failure('BLOCKED');
        const nested=Boolean(request.frame().parentFrame());
        const domains=!request.isNavigationRequest()&&options.resourceUrls?.has(request.url())?[new URL(request.url()).hostname]:request.isNavigationRequest()?(nested?[...options.domains,...(options.navigationDomains??[]),...(options.frameDomains??[])]:options.navigationDomains??options.domains)
          :[...options.domains,...(options.navigationDomains??[]),...(options.frameDomains??[]),...(options.resourceDomains??[])];
        const pinned=await validateNetworkUrl(request.url(),domains,options.lookup??dns.lookup);
        let headers=await request.allHeaders(),body=request.postDataBuffer();
        if(body&&body.length>2*1024*1024)throw failure('BLOCKED');
        const previous=request.redirectedFrom?.();
        if(previous){const response=await previous.response();if(!response)throw failure('BLOCKED');const next=redirectRequest({url:previous.url(),method:previous.method(),headers,bodyBase64:previous.postDataBuffer()?.toString('base64'),followRedirects:true},new URL(previous.url()),new URL(request.url()),response.status());if(next.method!==request.method())throw failure('BLOCKED');headers=next.headers??{};body=next.bodyBase64===undefined?null:Buffer.from(next.bodyBase64,'base64');}
        const input:NetworkRequest={url:request.url(),method:request.method(),headers,bodyBase64:body?.toString('base64'),responseType:'base64',followRedirects:false,signal:AbortSignal.any([controller.signal,AbortSignal.timeout(30000),...(options.signal?[options.signal]:[])])};
        if(tunnel){tunnel.approve(pinned.target,pinned.addresses);await route.continueRequest!(options.prepareRequest?await options.prepareRequest(input):headers);return;}
        const result=options.transport?await options.transport(input,domains):await new NetworkBroker({domains} as PluginManifest,undefined,undefined,undefined,undefined,options.maxResourceBytes??32*1024*1024).request(input);
        const bytes=Buffer.from(result.body,'base64');if(bytes.length>(options.maxResourceBytes??32*1024*1024))throw failure('PARSE');
        await route.fulfill({status:result.status,headers:result.headers,body:bytes});
      }catch(error){lastError=toPluginError(error);await route.abort().catch(()=>{});}finally{controllers.delete(controller);}
    },url=>context!.cookies([url]),undefined,undefined,tunnel?{maxBytes:options.maxResourceBytes??32*1024*1024,response:options.response,error:error=>{lastError=toPluginError(error);}}:undefined);
    options.signal?.throwIfAborted();return {context,page,get lastError(){return lastError;},resetError(){lastError=undefined;},close};
  }catch(error){await close();throw options.signal?.aborted?toAbortError(options.signal):error;}
}
