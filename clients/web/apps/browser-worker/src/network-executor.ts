import dns from 'node:dns/promises';
import {validateNetworkUrl,hostAllowed,type SourceBrowserExecutor,type SourceBrowserInput,type NetworkResponse} from '@hentai-park/source-host';
import {toPluginError,toAbortError,type PluginManifest} from '@hentai-park/source-contract';
import {createGuardedContext,type GuardedPageContext} from './guarded-context.js';
import {confirmPage,browserOperationError} from './confirmation.js';
import type {Response} from 'playwright';
import {responseChallenge} from '@hentai-park/source-host';
import {waitForChallenge,challengeFailure} from './challenge.js';
type RequestHandlers={prepare:(request:import('@hentai-park/source-host').NetworkRequest)=>Promise<Record<string,string>>;response:(request:{url:string;method?:string},response:NetworkResponse)=>Promise<void>};
type BrowserSession={guarded:GuardedPageContext;handlers:RequestHandlers;signature:string;cookies:string;idle?:ReturnType<typeof setTimeout>;busy:boolean};
const cookieKey=(cookies:SourceBrowserInput['cookies'])=>JSON.stringify(cookies.map(c=>[c.domain,c.path,c.name,c.value,Math.floor(c.expires),c.httpOnly,c.secure,c.sameSite??'Lax']).sort((a,b)=>JSON.stringify(a).localeCompare(JSON.stringify(b))));

const failure=(code:string)=>Object.assign(new Error('Browser network request failed'),{code,retryable:['NETWORK','TIMEOUT'].includes(code)});
const operationError=(error:unknown,guarded?:GuardedPageContext)=>{
  // A failed optional subresource must not replace a positively identified gate/block.
  const code=error&&typeof error==='object'&&'code'in error?String(error.code):'';
  return ['CLOUDFLARE','VERIFICATION_REQUIRED','BLOCKED','HTTP','CANCELLED','TIMEOUT'].includes(code)?browserOperationError(error):guarded?.lastError??browserOperationError(error);
};
export class BrowserNetworkExecutor implements SourceBrowserExecutor {
  private readonly contexts=new Map<GuardedPageContext,string>();
  private readonly pending=new Map<AbortController,string>();
  private readonly sessions=new Map<string,BrowserSession>();
  private readonly queues=new Map<string,Promise<void>>();
  private creatingSessions=0;
  constructor(private readonly options:{executablePath?:string;adultConfirmed?:()=>boolean;lookup?:typeof dns.lookup;transport?:(request:import('@hentai-park/source-host').NetworkRequest,domains:string[])=>Promise<NetworkResponse>}={}){}
  async request(input:SourceBrowserInput):Promise<NetworkResponse&{cookies?:SourceBrowserInput['cookies']}> {
    const abort=new AbortController(),signal=AbortSignal.any([abort.signal,AbortSignal.timeout(30000),...(input.request.signal?[input.request.signal]:[])]);
    this.pending.set(abort,input.source);
    const previous=input.resource?undefined:this.queues.get(input.source);
    let unlock:()=>void=()=>{};const turn=new Promise<void>(resolve=>{unlock=resolve;});
    const tail=(previous??Promise.resolve()).then(()=>turn);
    if(!input.resource)this.queues.set(input.source,tail);
    try{
      if(previous)await new Promise<void>((resolve,reject)=>{const cancel=()=>{signal.removeEventListener('abort',cancel);reject(toAbortError(signal));};signal.addEventListener('abort',cancel,{once:true});previous.then(()=>{signal.removeEventListener('abort',cancel);resolve();});if(signal.aborted)cancel();});
      signal.throwIfAborted();return await this.execute(input,signal);
    }finally{unlock();void tail.then(()=>{if(this.queues.get(input.source)===tail)this.queues.delete(input.source);});this.pending.delete(abort);}
  }
  private async retire(source:string,session:BrowserSession){if(this.sessions.get(source)===session)this.sessions.delete(source);clearTimeout(session.idle);await session.guarded.close();}
  private async execute(input:SourceBrowserInput,signal:AbortSignal):Promise<NetworkResponse&{cookies?:SourceBrowserInput['cookies']}> {
    const {manifest,request}=input;const lookup=this.options.lookup??dns.lookup;
    const target=(await validateNetworkUrl(request.url,input.resource&&(input.image||input.session===true)?undefined:input.resource?[...manifest.domains,...(manifest.media?.domains??[]),...(manifest.imageNetwork?.domains??[])]:manifest.domains,lookup)).target;
    const homepage=new URL(manifest.homepage),fallbackOrigin=hostAllowed(homepage.hostname,manifest.domains)?homepage.href:'https://'+manifest.domains[0]!.replace(/^\*\./,'')+'/';
    const originDomains=input.image?[...manifest.domains,...(manifest.imageNetwork?.domains??[])]:manifest.domains;
    const origin=(await validateNetworkUrl(request.origin??(input.image?manifest.imageNetwork?.origin:input.resource?manifest.media?.origin:manifest.network?.origin)??fallbackOrigin,originDomains,lookup)).target;
    const imageSession=input.resource===true&&input.image===true&&manifest.imageNetwork?.mode==='browser'&&typeof manifest.imageNetwork.origin==='string'&&new URL(manifest.imageNetwork.origin).origin===origin.origin&&target.origin===origin.origin&&hostAllowed(origin.hostname,manifest.domains);
    // Only an ordinary same-origin document GET may be consumed as a navigation.
    // API tokens, negotiated data, ranges, media and mutations retain fetch semantics.
    const confirmation=manifest.network?.confirmation;
    const documentRequest=!input.resource&&target.origin===origin.origin&&(request.method??'GET').toUpperCase()==='GET'&&request.body===undefined&&request.bodyBase64===undefined&&request.responseType!=='base64'&&Object.entries(request.headers??{}).every(([name,value])=>['user-agent','cookie','referer','accept-encoding'].includes(name.toLowerCase())||name.toLowerCase()==='accept'&&value.toLowerCase().includes('text/html'));
    if(request.followRedirects===false&&!input.resource)throw failure('CONFIG');
    if(request.bodyBase64!==undefined||request.body!==undefined&&Buffer.byteLength(request.body)>2*1024*1024)throw failure('CONFIG');
    const resourceUrls=new Set(input.resource?[target.href]:[]);let guarded:GuardedPageContext|undefined,fetching=false,applied=false,expected=target.href,expectedMethod=(request.method??'GET').toUpperCase(),captured:NetworkResponse|undefined;
    let session:BrowserSession|undefined,succeeded=false,reserved=false,onResponse:((response:Response)=>void)|undefined;
    const cancel=()=>{if(session)void this.retire(input.source,session).catch(()=>{});else void guarded?.close().catch(()=>{});};
    try {
      const prepareRequest=async(raw:import('@hentai-park/source-host').NetworkRequest)=>{
          const active=(fetching||documentRequest)&&raw.url===expected&&(raw.method??'GET')===expectedMethod;
          const headers={...raw.headers};
          if(active&&!applied){Object.assign(headers,request.headers??{});applied=true;}
          if(input.resource){const same=imageSession&&new URL(raw.url).origin===origin.origin;for(const name of Object.keys(headers))if(['authorization','proxy-authorization'].includes(name.toLowerCase())||name.toLowerCase()==='cookie'&&!same||name.toLowerCase().startsWith('x-')&&!same)delete headers[name];}
          return headers;
        };
      const responseReceived=async(raw:{url:string;method?:string},response:NetworkResponse)=>{if((fetching||documentRequest)&&raw.url===expected&&(raw.method??'GET')===expectedMethod){
          if([301,302,303,307,308].includes(response.status)&&response.headers.location){const next=new URL(response.headers.location,response.url||raw.url);await validateNetworkUrl(next.href,input.resource&&(input.image||input.session===true)?undefined:input.resource?[...manifest.domains,...(manifest.media?.domains??[]),...(manifest.imageNetwork?.domains??[])]:manifest.domains,lookup);expected=next.href;if(response.status===303&&expectedMethod!=='HEAD'||[301,302].includes(response.status)&&expectedMethod==='POST')expectedMethod='GET';if(input.resource)resourceUrls.add(expected);}else captured=response;
        }};
      const signature=JSON.stringify([manifest,origin.href]),handlers:RequestHandlers={prepare:prepareRequest,response:responseReceived};
      let reuseDocument=false;
      if(!input.resource){
        session=this.sessions.get(input.source);
        if(session&&(session.signature!==signature||session.cookies!==cookieKey(input.cookies)||session.guarded.page.isClosed())){await this.retire(input.source,session);session=undefined;}
        if(session){clearTimeout(session.idle);session.busy=true;session.handlers.prepare=prepareRequest;session.handlers.response=responseReceived;guarded=session.guarded;guarded.resetError();reuseDocument=!confirmation&&new URL(guarded.page.url()).origin===origin.origin;}
        else if(this.sessions.size+this.creatingSessions>=4){const idle=[...this.sessions].find(([,value])=>!value.busy);if(!idle)throw failure('RATE_LIMITED');await this.retire(...idle);}
        if(!session){this.creatingSessions++;reserved=true;}
      }
      if(!guarded)guarded=await createGuardedContext({domains:manifest.domains,navigationDomains:originDomains,frameDomains:[...(manifest.frameDomains??[]),'challenges.cloudflare.com'],resourceDomains:input.resource?[...(manifest.media?.domains??[]),...(manifest.imageNetwork?.domains??[])]:undefined,resourceUrls,cookies:input.resource&&!imageSession?[]:input.cookies,executablePath:this.options.executablePath,signal:input.resource?signal:undefined,lookup,
        browserNetwork:!this.options.transport,
        prepareRequest:raw=>handlers.prepare(raw),response:(raw,response)=>handlers.response(raw,response),
        ...(this.options.transport?{transport:async(raw:import('@hentai-park/source-host').NetworkRequest,domains:string[])=>{const response=await this.options.transport!({...raw,headers:await handlers.prepare(raw)},domains);await handlers.response(raw,response);return response;}}:{})});
      if(!input.resource&&!session){session={guarded,handlers,signature,cookies:cookieKey(input.cookies),busy:true};this.sessions.set(input.source,session);}
      if(reserved){this.creatingSessions--;reserved=false;}
      signal.addEventListener('abort',cancel,{once:true});signal.throwIfAborted();
      this.contexts.set(guarded,input.source);
      let documentResponse:Response|undefined;
      onResponse=response=>{if(response.request().isNavigationRequest()&&response.frame()===guarded!.page.mainFrame())documentResponse=response;};guarded.page.on('response',onResponse);
      // Like the Android document path, bootstrap a plain document at its actual
      // address. An unrelated homepage challenge must not prevent reading it.
      const bootstrap=documentRequest&&!confirmation?target:origin;
      let documentContext=!reuseDocument&&documentRequest&&target.href===bootstrap.href;
      fetching=documentContext;
      // Leave room to report a recognised challenge within the catalog's 20s read budget.
      const deadline=Date.now()+15000;
      if(!reuseDocument){await guarded!.page.goto(bootstrap.href,{waitUntil:'domcontentloaded',timeout:Math.max(1,deadline-Date.now())});
      await waitForChallenge(guarded!.page,()=>documentResponse,signal,'bootstrap',deadline);}
      let confirmedOrigin=false;
      const confirmDocument=async()=>{if(confirmation){let acted=false,gateSeen=false;for(;;){
        await waitForChallenge(guarded!.page,()=>documentResponse,signal,'confirmation',deadline);
        const state=await confirmPage(guarded!.page,confirmation,!acted&&(!confirmation.auto?.birthDate||this.options.adultConfirmed?.()===true),Math.max(1,deadline-Date.now()));gateSeen=gateSeen||state.gate;
        if(!state.gate){
          if(documentContext){const html=await guarded!.page.evaluate(()=>document.contentType==='text/html');if(state.ready||confirmedOrigin||!html||(documentResponse?.status()??200)>=400)break;}
          else if(state.ready||!gateSeen){
            if(!documentRequest)break;
            // readySelector proves completion of the declared confirmation page,
            // not the DOM shape of every later document (genres, search, downloads).
            // The target still passes challenge/gate checks and required cookies below.
            if(state.ready){const cookies=await guarded!.context.cookies([guarded!.page.url()]);confirmedOrigin=(confirmation.requiredCookies??[]).every(name=>cookies.some(cookie=>cookie.name===name&&cookie.value));}
            // The origin is only a session bootstrap. Its lack of a content marker
            // must not block a safe target document, nor cause an API/mutation replay.
            documentContext=true;fetching=true;acted=false;gateSeen=false;
            if(guarded!.page.url()!==target.href)await guarded!.page.goto(target.href,{waitUntil:'domcontentloaded',timeout:Math.max(1,deadline-Date.now())});
            await waitForChallenge(guarded!.page,()=>documentResponse,signal,'target-document',deadline);continue;
          }
        }
        if(state.gate&&!state.acted&&!acted||Date.now()>=deadline)throw failure('VERIFICATION_REQUIRED');acted=state.navigated?false:acted||state.acted;await new Promise(resolve=>setTimeout(resolve,100));
      }
      if(documentContext||gateSeen){const cookies=await guarded!.context.cookies([guarded!.page.url()]);if((confirmation.requiredCookies??[]).some(name=>!cookies.some(cookie=>cookie.name===name&&cookie.value)))throw failure('VERIFICATION_REQUIRED');}
      }};
      if(documentRequest&&!confirmation&&!reuseDocument){documentContext=true;fetching=true;if(guarded.page.url()!==target.href)await guarded.page.goto(target.href,{waitUntil:'domcontentloaded',timeout:Math.max(1,deadline-Date.now())});await waitForChallenge(guarded.page,()=>documentResponse,signal,'target-document',deadline);}
      await confirmDocument();
      const readDocument=async():Promise<NetworkResponse>=>{
        if(!documentResponse)throw guarded!.lastError??failure('NETWORK');
        const current=await guarded!.page.evaluate(()=>({url:location.href,type:document.contentType,body:document.documentElement.outerHTML}));
        if(current.url!==documentResponse.url())throw guarded!.lastError??failure('NETWORK');
        const headers=await documentResponse.allHeaders();delete headers['content-length'];delete headers['content-encoding'];
        const body=current.type==='text/html'?Buffer.from(current.body):await documentResponse.body();
        if(body.length>32*1024*1024)throw failure('PARSE');
        return {status:documentResponse.status(),headers,body:body.toString('base64'),url:current.url};
      };
      let response:NetworkResponse|undefined;
      if(documentContext)response=await readDocument();else try {
        fetching=true;
        const fetchTarget=()=>guarded!.page.evaluate(async data=>{
          const result=await fetch(data.url,{method:data.method,headers:data.headers,body:data.body,credentials:data.resource?(data.imageSession?'same-origin':'omit'):'include',redirect:'follow'});
          const bytes=new Uint8Array(await result.arrayBuffer());if(bytes.length>32*1024*1024)throw Error('response exceeds limit');let body='';for(let i=0;i<bytes.length;i+=16384)body+=String.fromCharCode(...bytes.subarray(i,i+16384));
          const gate=Boolean(data.confirmationSelector&&result.headers.get('content-type')?.includes('text/html')&&new DOMParser().parseFromString(new TextDecoder().decode(bytes),'text/html').querySelector(data.confirmationSelector));
          return {status:result.status,headers:Object.fromEntries(result.headers.entries()),body:btoa(body),url:result.url,gate};
        },{url:target.href,method:request.method??'GET',headers:request.headers,body:request.body,resource:input.resource===true,imageSession,confirmationSelector:input.resource?undefined:confirmation?.selector});
        response=await fetchTarget();
        const classify=()=>responseChallenge({...response!,body:Buffer.from(response!.body,'base64').toString('utf8')});
        const challenge=classify(),gate=(response as NetworkResponse&{gate?:boolean}).gate;
        if(challenge||gate){
          const method=(request.method??'GET').toUpperCase();
          const safe=!input.resource&&request.bodyBase64===undefined&&(['GET','HEAD'].includes(method)&&request.body===undefined||method==='POST'&&request.readOnly===true&&typeof request.body==='string'&&Buffer.byteLength(request.body)<=2*1024*1024);
          if(challenge==='BLOCKED'||!safe)throw challengeFailure(challenge??'VERIFICATION_REQUIRED','target-response');
          await guarded!.page.goto(target.href,{waitUntil:'domcontentloaded',timeout:Math.max(1,deadline-Date.now())});
          await waitForChallenge(guarded!.page,()=>documentResponse,signal,'target-recovery',deadline);
          documentContext=true;await confirmDocument();
          if(signal.aborted)throw toAbortError(signal);
          // A recovered HTML navigation already is the requested document.
          // Re-fetching it discards that success and may start another challenge.
          response=documentRequest?await readDocument():await fetchTarget();
          const repeated=classify();if(repeated)throw challengeFailure(repeated,'target-replay');
        }
        // A fetched gate is not permission to navigate or repeat a mutation.
        if((response as NetworkResponse&{gate?:boolean}).gate)throw failure('VERIFICATION_REQUIRED');
      }catch(error){if(!input.resource||!captured||error&&typeof error==='object'&&'code'in error&&['CLOUDFLARE','BLOCKED'].includes(String(error.code)))throw operationError(error,guarded);response=captured;}
      if(!response)throw guarded.lastError??failure('NETWORK');
      const remaining=responseChallenge({...response,body:Buffer.from(response.body,'base64').toString('utf8')});if(remaining)throw challengeFailure(remaining,'completed-document');
      await validateNetworkUrl(response.url,input.resource&&(input.image||input.session===true)?undefined:input.resource?[...manifest.domains,...(manifest.media?.domains??[]),...(manifest.imageNetwork?.domains??[])]:manifest.domains,lookup);
      const cookies=input.resource&&!imageSession?undefined:(await guarded.context.cookies(imageSession?[origin.href]:undefined)).filter(cookie=>hostAllowed(cookie.domain.replace(/^\./,''),manifest.domains));
      if(session)session.cookies=cookieKey(cookies??[]);succeeded=true;
      return {...response,body:request.responseType==='base64'?response.body:Buffer.from(response.body,'base64').toString('utf8'),...(cookies?{cookies}:{})};
    }catch(error){throw signal.aborted?toAbortError(signal):operationError(error,guarded);}
    finally{if(reserved)this.creatingSessions--;signal.removeEventListener('abort',cancel);if(guarded){if(onResponse)guarded.page.off('response',onResponse);this.contexts.delete(guarded);if(session&&succeeded&&!signal.aborted){session.busy=false;session.idle=setTimeout(()=>{void this.retire(input.source,session!).catch(()=>{});},30000);session.idle.unref();}else if(session)await this.retire(input.source,session);else await guarded.close();}}
  }
  async dispose(source?:string){for(const [controller,owner]of this.pending)if(source===undefined||owner===source)controller.abort();await Promise.all([...this.sessions].filter(([owner])=>source===undefined||owner===source).map(([owner,session])=>this.retire(owner,session)));await Promise.all([...this.contexts].filter(([,owner])=>source===undefined||owner===source).map(async([context])=>{this.contexts.delete(context);await context.close();}));}
}
