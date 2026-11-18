import {randomBytes} from 'node:crypto';
import {once} from 'node:events';
import type {FastifyInstance,FastifyRequest,FastifyReply} from 'fastify';
import type {PluginManifest} from '@hentai-park/source-contract';
import type {BrowserWorker,WebVideoCommand,WebVideoState} from '@hentai-park/browser-worker';
import type {CatalogHost} from './catalog.js';

const failure=(code:string,statusCode=502)=>Object.assign(new Error(code),{code,statusCode,publicError:true,causeCategory:'source',retryable:['NETWORK','TIMEOUT'].includes(code)});
type Identity={source:string;workId:string;chapterId:string};
type Player=Identity&{id:string;owner:string;browserId:string;version:string;expiresAt:number;controller:AbortController;audioGeneration:number;audioOpen:boolean;audioQueue:Promise<void>;framesOpen:boolean;claimTimer?:ReturnType<typeof setTimeout>;error?:string;commands:Map<string,{fingerprint:string;result:Promise<WebVideoState>}>};
export class ControlledWebPlayers {
  private players=new Map<string,Player>();
  private timer:ReturnType<typeof setInterval>;
  constructor(private readonly browser:BrowserWorker,private readonly host:CatalogHost){this.timer=setInterval(()=>{for(const player of this.players.values())if(player.expiresAt<=Date.now())this.background(this.close(player.id));},15000);this.timer.unref();}
  private background(result:Promise<unknown>){void result.catch(error=>console.error('web-player cleanup failed',{code:(error as {code?:string}).code??'BROWSER_ERROR'}));}
  private async failed(player:Player,error:unknown){player.error=(error as {code?:string}).code??'BROWSER_ERROR';player.controller.abort();await this.browser.cancel(player.browserId);}
  async open(identity:Identity,owner:string,manifest:PluginManifest,value:unknown,signal?:AbortSignal){
    if(!manifest.capabilities?.webVideo)throw failure('UNSUPPORTED',422);
    if(!value||typeof value!=='object'||Array.isArray(value))throw failure('PARSE');const descriptor=value as Record<string,unknown>;if(typeof descriptor.url!=='string'||descriptor.url.length>8192)throw failure('PARSE');
    let url:URL;try{url=new URL(descriptor.url);}catch{throw failure('PARSE');}if(url.protocol!=='https:'||url.username||url.password||url.port)throw failure('BLOCKED',403);
    const subset=(input:unknown,declared:string[]|undefined)=>{const domains=input===undefined?declared??[url.hostname]:input;if(!Array.isArray(domains)||domains.length>64||domains.some(domain=>typeof domain!=='string'||!/^(?:\*\.)?(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/i.test(domain)))throw failure('BLOCKED',403);return domains as string[];};
    const navigationDomains=subset(descriptor.navigationDomains,manifest.navigationDomains);const frameDomains=[...new Set([...navigationDomains,...subset(descriptor.frameDomains,manifest.frameDomains??[])])];
    const browserId=this.browser.create({domains:[],navigationDomains,frameDomains,mediaDomains:manifest.media?.domains,imageNetworkDomains:manifest.imageNetwork?.domains,sessionMedia:manifest.media?.scope==='session'});
    const player:Player={...identity,id:randomBytes(24).toString('base64url'),owner,browserId,version:manifest.version,expiresAt:Date.now()+90000,controller:new AbortController(),audioGeneration:0,audioOpen:false,audioQueue:Promise.resolve(),framesOpen:false,commands:new Map()};this.players.set(player.id,player);
    try{await this.browser.get(browserId).webVideo(url.href,signal);if(signal?.aborted)throw failure('CANCELLED',499);player.expiresAt=Date.now()+5000;player.claimTimer=setTimeout(()=>this.background(this.close(player.id)),5000);player.claimTimer.unref();return this.describe(player);}catch(error){await this.close(player.id);throw failure((error as {code?:string}).code??'NETWORK');}
  }
  private describe(player:Player){const prefix='/api/v1/web-player/'+player.id;return {playerId:player.id,frameUrl:prefix+'/frames',audioUrl:prefix+'/audio',controlUrl:prefix+'/control',statusUrl:prefix+'/status',expiresAt:player.expiresAt};}
  private get(id:string,owner:string){const player=this.players.get(id);if(!player||player.owner!==owner)throw failure('NOT_FOUND',404);if(player.expiresAt<=Date.now()){this.background(this.close(id));throw failure('NOT_FOUND',404);}const source=this.host.registry.get(player.source);if(!source?.enabled||source.manifest.version!==player.version){this.background(this.close(id));throw failure('CONFIG',409);}clearTimeout(player.claimTimer);player.claimTimer=undefined;player.expiresAt=Date.now()+90000;return player;}
  async status(id:string,owner:string){const player=this.get(id,owner);if(player.error)return {state:'failed',error:player.error,paused:true,position:0,duration:null,rate:1,muted:false,hasAudio:false,viewport:{width:960,height:540},expiresAt:player.expiresAt};try{return {...await this.browser.get(player.browserId).webPlayback(),expiresAt:player.expiresAt};}catch(error){await this.failed(player,error);throw failure(player.error!);}}
  async control(id:string,owner:string,input:unknown){
    const player=this.get(id,owner);if(!input||typeof input!=='object'||Array.isArray(input))throw failure('BAD_REQUEST',400);const value=input as Record<string,unknown>;
    if(typeof value.requestKey!=='string'||!value.requestKey||value.requestKey.length>256)throw failure('BAD_REQUEST',400);
    if(value.action==='close'){await this.close(id);return {closed:true};}if(player.error)throw failure(player.error);
    if(!['play','pause','seek','rate','click','move','key'].includes(String(value.action)))throw failure('BAD_REQUEST',400);
    const command={action:value.action,position:value.position,rate:value.rate,x:value.x,y:value.y,key:value.key} as WebVideoCommand;const fingerprint=JSON.stringify(command);const prior=player.commands.get(value.requestKey);if(prior){if(prior.fingerprint!==fingerprint)throw failure('CONFLICT',409);return prior.result;}
    if(player.commands.size>=128)player.commands.delete(player.commands.keys().next().value!);
    const result=(async()=>{try{return await this.browser.get(player.browserId).webPlayback(command);}catch(error){const code=(error as {code?:string}).code??'NETWORK';if(code!=='BLOCKED')await this.failed(player,error);throw failure(code,code==='BLOCKED'?400:502);}})();player.commands.set(value.requestKey,{fingerprint,result});return result;
  }
  async frames(id:string,owner:string,reply:FastifyReply,valid:()=>boolean){
    const player=this.get(id,owner);if(player.framesOpen)throw failure('CONFLICT',409);if(player.error)throw failure(player.error);player.framesOpen=true;reply.hijack();const raw=reply.raw;
    const streamAbort=new AbortController();
    const disconnected=()=>{streamAbort.abort();};raw.once('close',disconnected);
    raw.writeHead(200,{'content-type':'multipart/x-mixed-replace; boundary=hp-frame','cache-control':'private, no-store','x-content-type-options':'nosniff'});
    const signal=AbortSignal.any([player.controller.signal,streamAbort.signal]);
    try{while(!raw.destroyed&&!signal.aborted){if(!valid()){await this.close(id);break;}this.get(id,owner);const started=Date.now();const frame=await this.browser.get(player.browserId).webFrame(player.controller.signal);if(frame.length>4*1024*1024)throw failure('PARSE');if(!raw.write(Buffer.concat([Buffer.from('--hp-frame\r\nContent-Type: image/jpeg\r\nContent-Length: '+frame.length+'\r\n\r\n'),frame,Buffer.from('\r\n')])))await once(raw,'drain',{signal});const wait=Math.max(16,50-(Date.now()-started));await new Promise(resolve=>setTimeout(resolve,wait));}}
    catch(error){if(!raw.destroyed&&!signal.aborted)await this.failed(player,error);}
    finally{player.framesOpen=false;raw.removeListener('close',disconnected);if(!raw.destroyed)raw.end();if(!player.error&&this.players.has(id)){player.expiresAt=Math.min(player.expiresAt,Date.now()+15000);player.claimTimer=setTimeout(()=>{if(!player.framesOpen)this.background(this.close(id));},15000);player.claimTimer.unref();}}
  }
  async audio(id:string,owner:string,reply:FastifyReply,valid:()=>boolean){
    const player=this.get(id,owner);if(player.error)throw failure(player.error);const generation=++player.audioGeneration;const start=player.audioQueue.then(async()=>{if(generation===player.audioGeneration)await this.browser.get(player.browserId).webAudio('start',player.controller.signal);});player.audioQueue=start.catch(()=>{});try{await start;}catch(error){await this.failed(player,error);throw failure(player.error!);}if(generation!==player.audioGeneration)throw failure('CONFLICT',409);
    player.audioOpen=true;reply.hijack();const raw=reply.raw;const disconnected=new AbortController();const signal=AbortSignal.any([player.controller.signal,disconnected.signal]);const onClose=()=>disconnected.abort();raw.once('close',onClose);
    raw.writeHead(200,{'content-type':'audio/webm; codecs=opus','cache-control':'private, no-store','x-content-type-options':'nosniff'});
    try{while(!raw.destroyed&&!signal.aborted&&generation===player.audioGeneration){if(!valid()){await this.close(id);break;}this.get(id,owner);const next=await this.browser.get(player.browserId).webAudio('read',player.controller.signal);if(generation!==player.audioGeneration)break;if(!next||typeof next.active!=='boolean'||!Array.isArray(next.chunks)||next.chunks.length>64||next.chunks.some(chunk=>typeof chunk!=='string'||chunk.length>524288||!/^[A-Za-z0-9+/]*={0,2}$/.test(chunk))||next.chunks.reduce((sum,chunk)=>sum+chunk.length,0)>2097152)throw failure('PARSE');for(const chunk of next.chunks){const bytes=Buffer.from(chunk,'base64');if(!raw.write(bytes))await once(raw,'drain',{signal});}if(!next.active)break;await new Promise(resolve=>setTimeout(resolve,50));}}
    catch(error){if(!signal.aborted&&!raw.destroyed)await this.failed(player,error);}
    finally{raw.removeListener('close',onClose);raw.end();if(generation===player.audioGeneration){player.audioOpen=false;try{await this.browser.get(player.browserId).webAudio('stop');}catch(error){if(!player.controller.signal.aborted)await this.failed(player,error);}}}
  }
  async close(id:string){const player=this.players.get(id);if(!player)return;this.players.delete(id);clearTimeout(player.claimTimer);player.controller.abort();await this.browser.cancel(player.browserId);}
  revoke(owner:string){for(const player of this.players.values())if(player.owner===owner)this.background(this.close(player.id));}
  async revokeSource(source:string){await Promise.all([...this.players.values()].filter(player=>player.source===source).map(player=>this.close(player.id)));}
  async closeAll(){clearInterval(this.timer);await Promise.all([...this.players.keys()].map(id=>this.close(id)));}
}
export function registerWebPlayerRoutes(app:FastifyInstance,pool:ControlledWebPlayers,session:{id(request:FastifyRequest):string;valid(request:FastifyRequest):boolean}){
  const identity=(request:FastifyRequest)=>{const id=(request.params as {id?:string}).id;if(!id||!/^[A-Za-z0-9_-]{32}$/.test(id))throw failure('NOT_FOUND',404);return {id,owner:session.id(request)};};
  app.get('/api/v1/web-player/:id/status',async request=>{const {id,owner}=identity(request);return {...await pool.status(id,owner),requestId:request.id};});
  app.post('/api/v1/web-player/:id/control',async request=>{const {id,owner}=identity(request);return {...await pool.control(id,owner,request.body),requestId:request.id};});
  app.get('/api/v1/web-player/:id/frames',async(request,reply)=>{const {id,owner}=identity(request);await pool.frames(id,owner,reply,()=>session.valid(request));});
  app.get('/api/v1/web-player/:id/audio',async(request,reply)=>{const {id,owner}=identity(request);await pool.audio(id,owner,reply,()=>session.valid(request));});
  app.addHook('preClose',()=>pool.closeAll());
  app.addHook('onSend',async(request,reply,payload)=>{if(request.url.startsWith('/api/v1/reader/')&&typeof payload==='string'){let id:string|undefined;try{id=JSON.parse(payload).webPlayer?.playerId;}catch{}if(id){const playerId=id;reply.raw.once('close',()=>{if(!reply.raw.writableFinished)void pool.close(playerId).catch(error=>request.log.error({code:(error as {code?:string}).code??'BROWSER_ERROR'},'web-player undelivered response cleanup failed'));});}}return payload;});
}
