import type {BrowserRoute} from './index.js';
type Payload=Record<string,any>;
export interface ProtocolSession {send(method:string,params?:Payload):Promise<Payload>;on(event:string,handler:(params:Payload)=>void):void;}
export interface BrowserResponseBoundary {maxBytes:number;response?:(request:{url:string;method:string},response:{status:number;headers:Record<string,string>;body:string;url:string})=>Promise<void>;error?:(error:unknown)=>void;}
type RequestRecord={id:string;url:string;method:string;body:Buffer|null;status?:number;hops:number};
/** Chromium Fetch interception owns every redirect hop, including child targets. */
export async function interceptRequests(session:ProtocolSession,handler:(route:BrowserRoute)=>Promise<void>,cookies:(url:string)=>Promise<Array<{name:string;value:string}>>,parentFrame?:Payload,targetType?:string,browser?:BrowserResponseBoundary){
 const frames=new Map<string,Payload>();const records=new Map<string,RequestRecord>();const networks=new Map<string,RequestRecord>();
 const remember=(tree:Payload)=>{if(tree?.frame)frames.set(tree.frame.id,tree.frame);for(const child of tree?.childFrames??[])remember(child);};
 session.on('Page.frameAttached',frame=>frames.set(frame.frameId,{id:frame.frameId,parentId:frame.parentFrameId,url:'about:blank'}));session.on('Page.frameNavigated',event=>frames.set(event.frame.id,event.frame));session.on('Page.frameDetached',event=>frames.delete(event.frameId));
 // Worker requests are intercepted by their owning page; Chromium does not expose
 // Fetch on worker targets. Keep those targets alive instead of treating the
 // unsupported page-domain command as a failed network boundary.
 session.on('Target.attachedToTarget',event=>{let detached=false;session.on('Target.detachedFromTarget',removed=>{if(removed.sessionId===event.sessionId)detached=true;});const child=childSession(session,event.sessionId);void interceptRequests(child,handler,cookies,parentFrame??{url:'about:blank',child:true},event.targetInfo.type,browser).then(()=>{if(!detached)return child.send('Runtime.runIfWaitingForDebugger');}).catch(async()=>{if(!detached)await session.send('Target.closeTarget',{targetId:event.targetInfo.targetId}).catch(()=>{});});});
 session.on('Fetch.requestPaused',event=>{void (async()=>{
  const request=event.request as Payload;
  if(event.responseStatusCode!==undefined||event.responseErrorReason){
    if(!browser||event.responseErrorReason)throw Object.assign(Error('browser response failed'),{code:'NETWORK'});
    const status=Number(event.responseStatusCode),record=records.get(event.requestId);
    if(record)record.status=status;
    const responseHeaders:Record<string,string>={};for(const header of event.responseHeaders??[]){const name=String(header.name).toLowerCase();responseHeaders[name]=responseHeaders[name]?responseHeaders[name]+(name==='set-cookie'?'\n':', ')+header.value:String(header.value);}
    if(Number(responseHeaders['content-length']??0)>browser.maxBytes)throw Object.assign(Error('browser response exceeds limit'),{code:'PARSE'});
    const redirect=[301,302,303,307,308].includes(status);
    const chunks:Buffer[]=[];let size=0;
    if(!redirect&&request.method!=='HEAD'&&![204,304].includes(status)){
      const {stream}=await session.send('Fetch.takeResponseBodyAsStream',{requestId:event.requestId});
      try{for(;;){const part=await session.send('IO.read',{handle:stream,size:65536}),chunk=Buffer.from(part.data,part.base64Encoded?'base64':'utf8');size+=chunk.length;if(size>browser.maxBytes)throw Object.assign(Error('browser response exceeds limit'),{code:'PARSE'});chunks.push(chunk);if(part.eof)break;}}finally{await session.send('IO.close',{handle:stream}).catch(()=>{});}
    }
    const bytes=Buffer.concat(chunks);
    // CDP returns decoded bytes. Never label them with the wire encoding/length.
    delete responseHeaders['content-encoding'];delete responseHeaders['content-length'];
    await browser.response?.({url:request.url,method:request.method},{status,headers:responseHeaders,body:bytes.toString('base64'),url:request.url});
    if(redirect)await session.send('Fetch.continueResponse',{requestId:event.requestId});
    else await session.send('Fetch.fulfillRequest',{requestId:event.requestId,responseCode:status,responseHeaders:Object.entries(responseHeaders).flatMap(([name,value])=>name==='set-cookie'?value.split('\n').map(value=>({name,value})):[{name,value}]),body:bytes.toString('base64')});
    if(!redirect){records.delete(event.requestId);if(event.networkId)networks.delete(event.networkId);}return;
  }
  let body:Buffer|null=null;
  if(Array.isArray(request.postDataEntries)){if(request.postDataEntries.some((entry:Payload)=>typeof entry.bytes!=='string'))throw Error('request body unavailable');body=Buffer.concat(request.postDataEntries.map((entry:Payload)=>Buffer.from(entry.bytes,'base64')));}
  else if(typeof request.postData==='string')body=Buffer.from(request.postData);
  else if(request.hasPostData)throw Error('request body unavailable');
  const previous=event.redirectedRequestId?records.get(event.redirectedRequestId):event.networkId?networks.get(event.networkId):undefined;
  const redirected=previous&&[301,302,303,307,308].includes(previous.status??0)?previous:undefined;
  const record:RequestRecord={id:event.requestId,url:request.url,method:request.method,body,status:undefined,hops:redirected?redirected.hops+1:0};records.set(record.id,record);if(event.networkId)networks.set(event.networkId,record);
  const frame=frames.get(event.frameId)??parentFrame??{url:request.url};const headers=Object.fromEntries(Object.entries(request.headers??{}).map(([key,value])=>[key,String(value)]));
  const allHeaders=async()=>{const result={...headers};if(!Object.keys(result).some(key=>key.toLowerCase()==='cookie')){const values=await cookies(request.url);if(values.length)result.cookie=values.map(item=>item.name+'='+item.value).join('; ');}return result;};
  await handler({request:()=>({url:()=>request.url,resourceType:()=>String(event.resourceType).toLowerCase(),isNavigationRequest:()=>event.resourceType==='Document',frame:()=>({url:()=>frame.url??request.url,parentFrame:()=>frame.parentId?frames.get(frame.parentId)??parentFrame??{}:frame.child?parentFrame??{}:null}),headers:()=>headers,allHeaders,method:()=>request.method,postData:()=>body?.toString()??null,postDataBuffer:()=>body,redirectCount:()=>record.hops,redirectedFrom:()=>redirected?{url:()=>redirected.url,method:()=>redirected.method,postDataBuffer:()=>redirected.body,response:async()=>({status:()=>redirected.status!})}:null}),
   continueRequest:async headers=>{
    // Replacing an unchanged header block discards Chromium's generated headers.
    // Keep its native request intact unless policy or the caller actually changes it.
    const normalize=(values:Record<string,string>)=>Object.fromEntries(Object.entries(values).map(([name,value])=>[name.toLowerCase(),value]));
    const original=normalize(await allHeaders()),next=normalize(headers);
    const changed=Object.keys(original).length!==Object.keys(next).length||Object.entries(next).some(([name,value])=>original[name]!==value);
    await session.send('Fetch.continueRequest',{requestId:record.id,...(changed?{headers:Object.entries(next).map(([name,value])=>({name,value}))}:{}),interceptResponse:true});
   },
   abort:async()=>{await session.send('Fetch.failRequest',{requestId:record.id,errorReason:'BlockedByClient'});records.delete(record.id);if(event.networkId)networks.delete(event.networkId);},
   fulfill:async response=>{record.status=response.status;const responseHeaders=Object.entries(response.headers).flatMap(([name,value])=>name.toLowerCase()==='set-cookie'?value.split('\n').map(value=>({name,value})):[{name,value}]);await session.send('Fetch.fulfillRequest',{requestId:record.id,responseCode:response.status,responseHeaders,body:response.body.toString('base64')});if(![301,302,303,307,308].includes(response.status)){records.delete(record.id);if(event.networkId)networks.delete(event.networkId);}if(redirected)records.delete(redirected.id);}
  });
 })().catch(error=>{browser?.error?.(error);return session.send('Fetch.failRequest',{requestId:event.requestId,errorReason:'BlockedByClient'}).catch(()=>{});});});
 const worker=['worker','shared_worker','worklet'].includes(targetType??'');
 await session.send('Network.enable');await session.send('Network.setCacheDisabled',{cacheDisabled:true});await session.send('Network.setBypassServiceWorker',{bypass:true});if(!worker)await session.send('Fetch.enable',{patterns:[{urlPattern:'*',requestStage:'Request'}]});if(targetType!=='worklet')await session.send('Target.setAutoAttach',{autoAttach:true,waitForDebuggerOnStart:true,flatten:false});
 if(!worker){await session.send('Page.enable');remember((await session.send('Page.getFrameTree')).frameTree);}
}
function childSession(parent:ProtocolSession,sessionId:string):ProtocolSession {
 let sequence=0;const pending=new Map<number,{resolve:(result:Payload)=>void;reject:(error:Error)=>void}>();const listeners=new Map<string,Array<(event:Payload)=>void>>();
 parent.on('Target.receivedMessageFromTarget',event=>{if(event.sessionId!==sessionId)return;const message=JSON.parse(event.message);if(message.id){const call=pending.get(message.id);if(call){pending.delete(message.id);message.error?call.reject(Error('child protocol request failed')):call.resolve(message.result??{});}}else for(const listener of listeners.get(message.method)??[])listener(message.params??{});});
 parent.on('Target.detachedFromTarget',event=>{if(event.sessionId===sessionId){for(const call of pending.values())call.reject(Error('child target closed'));pending.clear();listeners.clear();}});
 return {on(event,handler){const list=listeners.get(event)??[];list.push(handler);listeners.set(event,list);},send(method,params={}){return new Promise((resolve,reject)=>{const id=++sequence;pending.set(id,{resolve,reject});void parent.send('Target.sendMessageToTarget',{sessionId,message:JSON.stringify({id,method,params})}).catch(error=>{pending.delete(id);reject(error);});});}};
}
