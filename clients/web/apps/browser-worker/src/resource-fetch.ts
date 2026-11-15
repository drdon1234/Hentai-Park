import type {NetworkResponse} from '@hentai-park/source-host';
import {createGuardedContext} from './guarded-context.js';

/** Bounded public GET using Chromium's transport, including JSON attachment responses. */
export async function fetchBrowserResource(url:string,domains:string[],options:{signal?:AbortSignal;maxBytes?:number}={}):Promise<Response>{
  let expected=new URL(url).href,captured:NetworkResponse|undefined;
  const guard=await createGuardedContext({domains,browserNetwork:true,signal:options.signal,maxResourceBytes:options.maxBytes??512000,
    response:async(request,response)=>{if(request.url!==expected||request.method!=='GET')return;if([301,302,303,307,308].includes(response.status)&&response.headers.location)expected=new URL(response.headers.location,expected).href;else captured=response;}});
  try{
    // JSON may carry Content-Disposition: attachment. The guarded response hook
    // already read its bounded body before Chromium starts (and cancels) a download.
    await guard.page.goto(url,{waitUntil:'domcontentloaded',timeout:12000}).catch(error=>{if(!captured)throw guard.lastError??error;});
    options.signal?.throwIfAborted();if(!captured)throw guard.lastError??Object.assign(Error('Browser response unavailable'),{code:'NETWORK'});
    const result=new Response([204,205,304].includes(captured.status)?null:Buffer.from(captured.body,'base64'),{status:captured.status,headers:captured.headers});Object.defineProperty(result,'url',{value:captured.url});return result;
  }finally{await guard.close();}
}
