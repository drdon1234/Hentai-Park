import {randomBytes,randomUUID,createHash} from 'node:crypto';
import {readTavernPng,writeTavernPng} from './tavern-png.js';
import {buildTavernPrompt,buildWritingPrompt,tavernSettings,selectTavernLore} from './tavern-prompt.js';
import {readTavernStream} from './tavern-stream.js';
import {TavernConnections,normalizeConnectionEndpoint} from './tavern-connections.js';
import {WorldbookTerms} from './worldbook-terms.js';
import type {DatabaseSync} from 'node:sqlite';
import type {FastifyInstance,FastifyRequest} from 'fastify';
import {requestPinnedStream} from '@hentai-park/source-host';
import {toPluginError,type PluginManifest} from '@hentai-park/source-contract';
import type {SourceCatalog} from './catalog.js';
import type {ContentRouteOptions} from './content-routes.js';
import {contentError,contentObject,contentText,contentUrl} from './content-model.js';
import {GameSessions} from './game-sessions.js';
import {join,resolve} from 'node:path';
import {once} from 'node:events';
type Row=Record<string,unknown>;
const LIMIT=12*1024*1024;
function boundedJson(value:unknown):Row{const text=JSON.stringify(value);if(Buffer.byteLength(text)>LIMIT)throw contentError();let nodes=0;const visit=(v:unknown,depth=0)=>{if(depth>32||++nodes>100000)throw contentError();if(v&&typeof v==='object'){if(Array.isArray(v))v.forEach(x=>visit(x,depth+1));else for(const [key,item]of Object.entries(v)){if(['__proto__','constructor','prototype'].includes(key))throw contentError();visit(item,depth+1);}}else if(typeof v==='string')contentText(v,LIMIT,true);else if(v!==null&&typeof v!=='boolean'&&typeof v!=='number')throw contentError();};visit(value);return contentObject(value);}
export function parseTavernAsset(input:unknown,png?:Uint8Array):{kind:string;format:string;data:Row}{const asset=contentObject(input);if(!['character','lorebook'].includes(String(asset.kind))||!['json','png'].includes(String(asset.format)))throw contentError();if(asset.format==='png'&&(asset.kind!=='character'||!png))throw contentError();const data=boundedJson(asset.format==='json'?asset.data:readTavernPng(png!));
 if(asset.kind==='character'){const card=contentObject(data.data??data),greetings=[card.first_mes,...(Array.isArray(card.alternate_greetings)?card.alternate_greetings:[])];if(typeof card.name!=='string'||!card.name.trim()||card.name.length>256||!['description','personality'].some(key=>typeof card[key]==='string'&&card[key].trim())&&!greetings.some(value=>typeof value==='string'&&value.trim()))throw contentError();}
 else{const book=data.entries?data:data.data&&typeof data.data==='object'?contentObject(data.data):data,entries=Array.isArray(book.entries)?book.entries:book.entries&&typeof book.entries==='object'?Object.values(book.entries):[];if(!entries.length||!entries.some(value=>value&&typeof value==='object'&&!Array.isArray(value)))throw contentError();}return {kind:String(asset.kind),format:String(asset.format),data};}
function messages(input:unknown){if(!Array.isArray(input)||input.length>1000||Buffer.byteLength(JSON.stringify(input))>2_000_000)throw contentError('BAD_REQUEST',400);return input.map(value=>{const m=contentObject(value);if(!['system','user','assistant'].includes(String(m.role)))throw contentError('BAD_REQUEST',400);const result:Row={role:String(m.role),content:contentText(m.content,100000,true)};if(m.name!==undefined)result.name=contentText(m.name,256,true);if(m.status!==undefined){if(typeof m.status!=='string'||m.status.length>64)throw contentError('BAD_REQUEST',400);result.status=m.status;}if(m.alternatives!==undefined){if(!Array.isArray(m.alternatives)||m.alternatives.length>8)throw contentError('BAD_REQUEST',400);result.alternatives=m.alternatives.map(value=>{const alternative=contentObject(value);if(alternative.role!=='assistant')throw contentError('BAD_REQUEST',400);return {role:'assistant',content:contentText(alternative.content,100000,true),...(alternative.name!==undefined?{name:contentText(alternative.name,256,true)}:{}),...(alternative.status!==undefined?{status:contentText(alternative.status,64,true)}:{})};});}return result;});}
export class TavernLibrary {
 constructor(private readonly db:DatabaseSync,private readonly catalog:SourceCatalog,private readonly allowLoopbackAi=false,private readonly terms?:WorldbookTerms,private readonly connections?:TavernConnections){}
 list(){return this.db.prepare('SELECT asset_id,source,work_id,kind,format,updated_at,version,data_json FROM tavern_assets ORDER BY updated_at DESC').all().map(row=>{const data=JSON.parse(String(row.data_json));return {assetId:row.asset_id,source:row.source,workId:row.work_id,kind:row.kind,format:row.format,updatedAt:row.updated_at,version:row.version,name:data.data?.name??data.name??row.work_id,tags:Array.isArray((data.data??data).tags)?(data.data??data).tags.filter((tag:unknown)=>typeof tag==='string'):[]};});}
 get(id:string){const row=this.db.prepare('SELECT * FROM tavern_assets WHERE asset_id=?').get(id);if(!row)throw contentError('NOT_FOUND',404);const stored=JSON.parse(String(row.data_json)),originalPng=stored.originalPng;delete stored.originalPng;return {assetId:row.asset_id,source:row.source,workId:row.work_id,kind:row.kind,format:row.format,data:stored,originalPng,updatedAt:row.updated_at,version:row.version};}
 async acquire(source:string,workId:string,signal?:AbortSignal){const raw=contentObject(await this.catalog.invoke(source,'tavernAsset',{id:workId},signal));let bytes:Uint8Array|undefined;if(raw.format==='png')bytes=await this.catalog.readAsset(source,contentUrl(raw.url),LIMIT,signal);return {...parseTavernAsset(raw,bytes),...(bytes?{originalPng:Buffer.from(bytes).toString('base64')}:{})};}
 save(source:string,workId:string,asset:{kind:string;format:string;data:Row;originalPng?:string},version?:number){const prior=this.db.prepare('SELECT asset_id,version FROM tavern_assets WHERE source=? AND work_id=?').get(source,workId);if(prior&&version!==undefined&&Number(prior.version)!==version)throw contentError('CONFLICT',409);const id=String(prior?.asset_id??randomUUID()),now=new Date().toISOString();const data=boundedJson(asset.data);if(asset.originalPng){if(!/^[A-Za-z0-9+/]+={0,2}$/.test(asset.originalPng)||Buffer.from(asset.originalPng,'base64').length>LIMIT)throw contentError();data.originalPng=asset.originalPng;}this.db.prepare('INSERT INTO tavern_assets(asset_id,source,work_id,kind,format,data_json,updated_at,version) VALUES(?,?,?,?,?,?,?,1) ON CONFLICT(source,work_id) DO UPDATE SET kind=excluded.kind,format=excluded.format,data_json=excluded.data_json,updated_at=excluded.updated_at,version=tavern_assets.version+1').run(id,source,workId,asset.kind,asset.format,JSON.stringify(data),now);return this.get(id);}
 update(assetId:string, data:Row, version:number,copy=false,portrait?:unknown){
  const prior=this.get(assetId);
  if(!Number.isSafeInteger(version)||version!==Number(prior.version))throw contentError('CONFLICT',409);
  const parsed=parseTavernAsset({kind:prior.kind,format:'json',data});
  const image=portrait??prior.originalPng;
  if(image && prior.kind!=='character')throw contentError();
  const png=image?writeTavernPng(Buffer.from(contentText(image,LIMIT*2),'base64'),parsed.data):undefined;
  return this.save(copy?'local':String(prior.source),copy?randomUUID():String(prior.workId),{...parsed,...(png?{format:'png',originalPng:png.toString('base64')}:{})},version);
 }
 conversations(assetId:string){this.get(assetId);return this.db.prepare('SELECT conversation_id,messages_json,settings_json,updated_at,version FROM tavern_conversations WHERE asset_id=? ORDER BY updated_at DESC').all(assetId).map(row=>({conversationId:row.conversation_id,messages:JSON.parse(String(row.messages_json)),settings:JSON.parse(String(row.settings_json??'{}')),updatedAt:row.updated_at,version:row.version}));}
 saveConversation(assetId:string,input:Row){this.get(assetId);const id=input.conversationId===undefined?randomUUID():contentText(input.conversationId,128),prior=this.db.prepare('SELECT version,asset_id,settings_json FROM tavern_conversations WHERE conversation_id=?').get(id);if(prior&&(prior.asset_id!==assetId||Number(input.version)!==Number(prior.version)))throw contentError('CONFLICT',409);const rows=messages(input.messages),settings=input.settings===undefined?JSON.parse(String(prior?.settings_json??'{}')):tavernSettings(contentObject(input.settings)),now=new Date().toISOString();this.db.prepare('INSERT INTO tavern_conversations(conversation_id,asset_id,messages_json,settings_json,updated_at,version) VALUES(?,?,?,?,?,1) ON CONFLICT(conversation_id) DO UPDATE SET messages_json=excluded.messages_json,settings_json=excluded.settings_json,updated_at=excluded.updated_at,version=tavern_conversations.version+1').run(id,assetId,JSON.stringify(rows),JSON.stringify(settings),now);return {conversationId:id,messages:rows,settings,updatedAt:now,version:Number(prior?.version??0)+1};}
 removeAsset(assetId:string,version?:number){const row=this.get(assetId);if(version!==undefined&&Number(row.version)!==version)throw contentError('CONFLICT',409);const used=this.db.prepare(`SELECT 1 FROM tavern_conversations c WHERE c.asset_id<>? AND (
   EXISTS(SELECT 1 FROM json_each(c.settings_json,'$.castIds') WHERE value=?) OR
   EXISTS(SELECT 1 FROM json_each(c.settings_json,'$.worldbookIds') WHERE value=?)) LIMIT 1`).get(assetId,assetId,assetId);
  if(used)throw contentError('TAVERN_RESOURCE_IN_USE',409);
  this.db.exec('SAVEPOINT tavern_asset_del');try{this.db.prepare('DELETE FROM tavern_conversations WHERE asset_id=?').run(assetId);this.db.prepare('DELETE FROM tavern_assets WHERE asset_id=?').run(assetId);this.db.exec('RELEASE tavern_asset_del');}catch(error){this.db.exec('ROLLBACK TO tavern_asset_del;RELEASE tavern_asset_del');throw error;}return {deleted:true};}
 removeConversation(assetId:string,conversationId:string,version?:number){const prior=this.db.prepare('SELECT version,asset_id FROM tavern_conversations WHERE conversation_id=?').get(conversationId);if(!prior||prior.asset_id!==assetId)throw contentError('NOT_FOUND',404);if(version!==undefined&&Number(prior.version)!==version)throw contentError('CONFLICT',409);this.db.prepare('DELETE FROM tavern_conversations WHERE conversation_id=?').run(conversationId);return {deleted:true};}
 async listModels(input:Row,signal?:AbortSignal){
  if(input.connectionId!==undefined){if(!this.connections)throw contentError('CONFIG',503);const stored=await this.connections.credentials(contentText(input.connectionId,128));input={...stored,...input,endpoint:input.endpoint??stored.endpoint,apiKey:input.apiKey||stored.apiKey};}
  const url=new URL(normalizeConnectionEndpoint(input.endpoint)),local=url.protocol==='http:';if(local&&!this.allowLoopbackAi)throw contentError('LOCAL_AI_DISABLED',403);
  const key=contentText(input.apiKey??'',16384,true);if(local&&key)throw contentError('INSECURE_KEY',400);
  const isAnthropic=url.hostname==='api.anthropic.com'||/\/anthropic\b/i.test(url.pathname);
  const modelsPath=url.pathname.replace(/\/$/,'')+(isAnthropic&&!url.pathname.endsWith('/v1')?'/v1/models':'/models');
  const headers:Record<string,string>=isAnthropic?{'anthropic-version':'2023-06-01',...(key?{'x-api-key':key}:{})}:(key?{authorization:'Bearer '+key}:{});
  const response=await requestPinnedStream(new URL(modelsPath,url.origin).href,{method:'GET',headers,followRedirects:false,allowLoopback:this.allowLoopbackAi,allowHttpsPort:true,signal});
  if(!response.ok){await response.body?.cancel();throw contentError('HTTP',502);}
  const reader=response.body?.getReader(),chunks:Uint8Array[]=[];let size=0;try{if(reader)for(;;){const next=await reader.read();if(next.done)break;size+=next.value.length;if(size>2*1024*1024)throw contentError('PARSE');chunks.push(next.value);}}finally{await reader?.cancel().catch(()=>{});}
  let parsed:Row;try{parsed=contentObject(JSON.parse(Buffer.concat(chunks).toString('utf8')));}catch{throw contentError('PARSE');}
  const rawList=Array.isArray(parsed.data)?parsed.data:Array.isArray(parsed.models)?parsed.models:[];
  const models=rawList.flatMap(item=>typeof item==='string'?[item]:item&&typeof item==='object'&&typeof (item as Row).id==='string'?[String((item as Row).id)]:item&&typeof item==='object'&&typeof (item as Row).name==='string'?[String((item as Row).name)]:[]).slice(0,500);
  return {items:[...new Set(models)]};
 }
 loreEntries(assetId:string,bookIds:string[]=[]){const asset=this.get(assetId),raw=contentObject(asset.data),card=asset.kind==='character'?contentObject(raw.data??raw):raw,books:Array<{id:string;book:Row}>=[];const own=asset.kind==='lorebook'?(raw.entries?raw:contentObject(raw.data)):card.character_book;if(own&&typeof own==='object')books.push({id:assetId,book:contentObject(own)});for(const id of bookIds){const value=this.get(id);if(value.kind!=='lorebook')throw contentError('BAD_REQUEST',400);const data=contentObject(value.data);books.push({id,book:data.entries?data:contentObject(data.data)});}return books.flatMap(({id,book})=>{const entries=Array.isArray(book.entries)?book.entries:book.entries&&typeof book.entries==='object'?Object.values(book.entries):[];return entries.flatMap((value,index)=>{const entry=contentObject(value);if(typeof entry.content!=='string'||!entry.content)return [];return [{key:id+':'+index,label:String(entry.comment??entry.name??index+1),content:entry.content,keys:entry.keys??entry.key??[],enabled:entry.enabled!==false&&entry.disable!==true}];});});}
 async reply(assetId:string|undefined,input:Row,signal?:AbortSignal,onDelta?:(value:string)=>void|Promise<void>,translated?:(content:string)=>string|undefined){
  if(input.connectionId!==undefined){if(!this.connections)throw contentError('CONFIG',503);const stored=await this.connections.credentials(contentText(input.connectionId,128));input={...stored,...input,endpoint:stored.endpoint,model:stored.model,apiKey:stored.apiKey,systemPrompt:input.systemPrompt??stored.systemPrompt};}
  const baseAsset=assetId===undefined?{kind:'character',data:{}}:this.get(assetId);
  const actorSettings=tavernSettings(input);
  const cast=(actorSettings.castIds as string[]??[]).map(id=>this.get(id));
  if(cast.some(actor=>actor.kind!=='character'))throw contentError('BAD_REQUEST',400);
  const asset=cast.find(actor=>actor.assetId===actorSettings.speakerId)??baseAsset;
  const url=new URL(normalizeConnectionEndpoint(input.endpoint)),local=url.protocol==='http:';if(local&&!this.allowLoopbackAi)throw contentError('LOCAL_AI_DISABLED',403);
  const key=contentText(input.apiKey??'',16384,true),model=contentText(input.model,256),history=messages(input.messages) as Array<{role:string;content:string}>,settings=tavernSettings(input),books=(settings.worldbookIds as string[]??[]).map(id=>{const book=this.get(id);if(book.kind!=='lorebook')throw contentError('BAD_REQUEST',400);const data=contentObject(book.data);return data.entries?data:contentObject(data.data);}),data=contentObject(asset.data);
  if(cast.length){
    const others=[baseAsset,...cast].filter(actor=>actor!==asset).map(actor=>{const raw=contentObject(actor.data),card=contentObject(raw.data??raw);return String(card.name)+': '+String(card.description??'');});
    input={...input,memory:[settings.memory,...others].filter(Boolean).join('\n')};
    for(const message of history){const name=(message as Row).name;if(name)message.content=String(name)+': '+message.content;}
  }
  if(local&&key)throw contentError('INSECURE_KEY',400);const locale=contentText(input.locale??'zh-Hans',32),snapshot=this.terms?.snapshot(locale),aliases=(keyword:string)=>{const term=snapshot?.lookup.get(keyword.trim().toLowerCase());return term?[...new Set([keyword,...term.aliases,term.translation])]:[keyword];},prompt=assetId===undefined?buildWritingPrompt(history,settings):buildTavernPrompt(asset.kind==='character'?data:{name:String(data.name??''),character_book:data.entries?data:data.data},history,input,books,{aliases,translated});
  const isAnthropic=url.hostname==='api.anthropic.com'||url.pathname.endsWith('/messages');
  let response:Response;
  if(isAnthropic){
   const systemText=prompt.messages.filter(m=>m.role==='system').map(m=>m.content).join('\n\n');
   const chatMsgs=prompt.messages.filter(m=>m.role!=='system').map(m=>({role:m.role==='assistant'?'assistant':'user',content:m.content}));
   const msgPath=url.pathname.endsWith('/messages')?url.pathname:url.pathname.replace(/\/$/,'')+(url.pathname.endsWith('/v1')?'/messages':'/v1/messages');
   response=await requestPinnedStream(new URL(msgPath,url.origin).href,{method:'POST',headers:{'content-type':'application/json',accept:'text/event-stream','anthropic-version':'2023-06-01',...(key?{'x-api-key':key}:{})},body:JSON.stringify({model,system:systemText,messages:chatMsgs,stream:true,temperature:Math.min(1,prompt.temperature),max_tokens:prompt.maxTokens}),followRedirects:false,allowLoopback:this.allowLoopbackAi,allowHttpsPort:true,signal});
  }else{
   response=await requestPinnedStream(new URL(url.pathname.replace(/\/$/,'')+'/chat/completions',url.origin).href,{method:'POST',headers:{'content-type':'application/json',accept:'text/event-stream',...(key?{authorization:'Bearer '+key}:{})},body:JSON.stringify({model,messages:prompt.messages,stream:true,temperature:prompt.temperature,max_tokens:prompt.maxTokens}),followRedirects:false,allowLoopback:this.allowLoopbackAi,allowHttpsPort:true,signal});
  }
  const result=await readTavernStream(response,onDelta,signal);
  return {...result,inspection:assetId===undefined?undefined:prompt.messages,matchedEntries:prompt.matchedEntries,unsupportedEntries:prompt.unsupportedEntries,trimmedHistory:prompt.trimmedHistory};
 }
}
export function registerSpecialRoutes(app:FastifyInstance,catalog:SourceCatalog,db:DatabaseSync,options:ContentRouteOptions&{dataDirectory?:string}){
 const configured=options.dataDirectory??process.env.DATA_DIR??'test/special-content',memory=!db.prepare('PRAGMA database_list').all().some(row=>row.name==='main'&&row.file),directory=memory&&resolve(configured)===process.cwd()?join('test','tavern-memory-'+randomUUID()):configured,terms=new WorldbookTerms(db),connections=new TavernConnections(db,join(directory,'tavern-private'),options.allowLoopbackAi===true),library=new TavernLibrary(db,catalog,options.allowLoopbackAi===true,terms,connections),games=new GameSessions(catalog,join(directory,'game-state')),files=new Map<string,{source:string;url:string;filename:string;owner:string;expires:number}>();app.addHook('onReady',()=>connections.ready());app.addHook('onClose',()=>games.closeAll());
 const generations=new Map<string,Set<AbortController>>();app.addHook('preClose',async()=>{for(const controllers of generations.values())for(const controller of controllers)controller.abort();await games.closeAll();});
 const generationConnections=new Map<AbortController,string>(),plans=new Map<string,{owner:string;assetId:string;locale:string;content:string;markers:Record<string,string>;revision:number;expires:number}>(),translations=new Map<string,{text:string;expires:number}>(),digest=(text:string)=>createHash('sha256').update(text).digest('hex'),translationKey=(owner:string,assetId:string,locale:string,revision:number,content:string)=>JSON.stringify([owner,assetId,locale,revision,digest(content)]),translationEnabled=()=>JSON.parse(String(db.prepare("SELECT value_json FROM app_settings WHERE key='contentTranslationEnabled'").get()?.value_json??'false'))===true;
 const p=(r:FastifyRequest)=>contentObject(r.params),body=(r:FastifyRequest)=>contentObject(r.body??{}),sig=(r:FastifyRequest)=>options.signal?.(r),source=(r:FastifyRequest)=>contentText(p(r).source,100),work=(r:FastifyRequest)=>contentText(p(r).workId,512);
 const stopConnection=(id:string)=>{for(const [controller,connection]of generationConnections)if(connection===id)controller.abort();};
 app.get('/api/v1/tavern/connections',async()=>({items:connections.list()}));
 app.post('/api/v1/tavern/connections',async r=>{const input=body(r),result=await connections.save(input);stopConnection(String(result.connectionId));return result;});
 app.post('/api/v1/tavern/connections/models',async r=>library.listModels(body(r),sig(r)));
 app.delete('/api/v1/tavern/connections/:connectionId',async r=>{const id=contentText(p(r).connectionId,128),result=connections.remove(id,Number(body(r).version));stopConnection(id);return result;});
 app.get('/api/v1/worldbook-term-packs',async()=>({items:terms.list()}));
 app.get('/api/v1/worldbook-term-packs/:locale',async r=>terms.get(contentText(p(r).locale,32)));
 app.post('/api/v1/worldbook-term-packs/:locale',async r=>{const input=body(r),pack=contentObject(input.pack);if(pack.locale!==p(r).locale)throw contentError('BAD_REQUEST',400);return terms.install(pack,Number(input.revision));});
 app.delete('/api/v1/worldbook-term-packs/:locale',async r=>terms.remove(contentText(p(r).locale,32),Number(body(r).revision)));
 const bookIds=(input:unknown)=>(tavernSettings({worldbookIds:input??[]}).worldbookIds??[]) as string[];
 app.get('/api/v1/tavern/assets/:assetId/entries',async r=>{const query=contentObject(r.query??{}),locale=contentText(query.locale??'zh-Hans',32),books=query.books===undefined?[]:JSON.parse(contentText(query.books,20000));return {items:library.loreEntries(contentText(p(r).assetId,128),bookIds(books)).map(entry=>({...entry,triggers:(Array.isArray(entry.keys)?entry.keys:[]).filter((key):key is string=>typeof key==='string').map(original=>({original,translation:terms.translationFor(locale,original),aliases:terms.aliasesFor(locale,original)}))})),translationEnabled:translationEnabled()};});
 app.post('/api/v1/tavern/assets/:assetId/translation-plan',async r=>{const input=body(r),owner=options.sessionId(r),assetId=contentText(p(r).assetId,128),locale=contentText(input.locale,32);if(!translationEnabled()||input.confirmed!==true)throw contentError('CONFIRM_REQUIRED',409);const entry=library.loreEntries(assetId,bookIds(input.bookIds)).find(row=>row.key===input.entryKey);if(!entry)throw contentError('NOT_FOUND',404);for(const [id,plan]of plans)if(plan.expires<Date.now())plans.delete(id);if(plans.size>=256)throw contentError('RATE_LIMITED',429);const protectedText=await terms.protect(locale,entry.content,sig(r)),planId=randomBytes(24).toString('base64url');plans.set(planId,{owner,assetId,locale,content:entry.content,markers:protectedText.markers,revision:protectedText.revision,expires:Date.now()+600000});return {planId,chunks:protectedText.chunks,original:entry.content};});
 app.post('/api/v1/tavern/assets/:assetId/translation-restore',async r=>{const input=body(r),id=contentText(input.planId,128),plan=plans.get(id),owner=options.sessionId(r),assetId=contentText(p(r).assetId,128);if(!translationEnabled()||input.confirmed!==true)throw contentError('CONFIRM_REQUIRED',409);if(!plan||plan.owner!==owner||plan.assetId!==assetId||plan.expires<Date.now())throw contentError('NOT_FOUND',404);if((terms.snapshot(plan.locale)?.revision??0)!==plan.revision)throw contentError('CONFLICT',409);const text=terms.restore(contentText(input.text,1000000,true),plan.markers);plans.delete(id);for(const [key,value]of translations)if(value.expires<Date.now())translations.delete(key);if(translations.size>=1000)throw contentError('RATE_LIMITED',429);translations.set(translationKey(owner,assetId,plan.locale,plan.revision,plan.content),{text,expires:Date.now()+900000});return {text,original:plan.content};});
 app.get('/api/v1/games/:source/:workId/resources',async r=>({...await catalog.gameResources(source(r),work(r),sig(r)),requestId:r.id}));
 app.post('/api/v1/games/:source/:workId/resolve',async r=>{const input=body(r);if(input.confirmed!==true)throw contentError('CONFIRM_REQUIRED',409);const result=await catalog.resolveGameResource(source(r),work(r),contentText(input.resourceId,512),contentText(input.channelId,512),sig(r));if(result.kind==='direct'){for(const [id,value]of files)if(value.expires<Date.now())files.delete(id);if(files.size>=1000)throw contentError('RATE_LIMITED',429);const token=randomBytes(32).toString('base64url');files.set(token,{source:source(r),url:String(result.url),filename:String(result.filename??'game-resource'),owner:options.sessionId(r),expires:Date.now()+60000});return {...result,url:undefined,downloadUrl:'/api/v1/game-files/'+token,requestId:r.id};}return {...result,requestId:r.id};});
 app.get('/api/v1/game-files/:token',async(r,reply)=>{const token=contentText(p(r).token,128),entry=files.get(token);if(!entry||entry.owner!==options.sessionId(r)||entry.expires<Date.now())throw contentError('NOT_FOUND',404);files.delete(token);const response=await catalog.fetchAsset(entry.source,entry.url,sig(r));if(!response.ok)throw contentError('HTTP',502);let bytes=0;const stream=response.body?.pipeThrough(new TransformStream<Uint8Array,Uint8Array>({transform(chunk,controller){bytes+=chunk.length;if(bytes>8*1024*1024*1024)throw contentError('RESOURCE_LIMIT',413);controller.enqueue(chunk);}}));reply.header('content-type','application/octet-stream').header('cache-control','private, no-store').header('content-disposition',"attachment; filename*=UTF-8''"+encodeURIComponent(entry.filename.replace(/[\r\n/\\]/g,'_')));return reply.send(stream);});
 app.post('/api/v1/games/:source/:workId/play',async r=>({...await games.open(source(r),work(r),options.sessionId(r),await catalog.onlineGame(source(r),work(r),options.sessionId(r),sig(r)),sig(r)),requestId:r.id}));
 app.get('/api/v1/game-sessions/:gameId/frame',async(r,reply)=>reply.type('image/jpeg').header('cache-control','private, no-store').send(await games.frame(contentText(p(r).gameId,128),options.sessionId(r))));
 app.get('/api/v1/game-sessions/:gameId/audio',async(r,reply)=>games.audio(contentText(p(r).gameId,128),options.sessionId(r),reply));
 app.post('/api/v1/game-sessions/:gameId/input',async r=>games.input(contentText(p(r).gameId,128),options.sessionId(r),body(r)));
 app.get('/api/v1/game-sessions/:gameId/saves',async r=>games.exportSaves(contentText(p(r).gameId,128),options.sessionId(r)));
 app.post('/api/v1/game-sessions/:gameId/saves',async r=>games.importSaves(contentText(p(r).gameId,128),options.sessionId(r),body(r)));
 app.post('/api/v1/game-sessions/:gameId/close',async r=>{await games.closeOwned(contentText(p(r).gameId,128),options.sessionId(r));return {closed:true};});
 app.get('/api/v1/tavern/assets',async()=>({items:library.list()}));
 app.get('/api/v1/tavern/assets/:assetId',async r=>library.get(contentText(p(r).assetId,128)));
 app.get('/api/v1/tavern/assets/:assetId/revisions',async r=>{
  const assetId=contentText(p(r).assetId,128);
  const rows=db.prepare('SELECT revision,updated_at,content_json FROM tavern_edits WHERE asset_id=? ORDER BY updated_at DESC,rowid DESC LIMIT 8').all(assetId);
  return {items:rows.map(row=>({revision:row.revision,date:row.updated_at,data:JSON.parse(String(row.content_json))}))};
 });
 app.post('/api/v1/tavern/assets/:assetId',async r=>{
  const input=body(r);
  return library.update(contentText(p(r).assetId,128),contentObject(input.data),Number(input.version),input.copy===true,input.portrait);
 });
 app.delete('/api/v1/tavern/assets/:assetId',async r=>{const input=body(r);return library.removeAsset(contentText(p(r).assetId,128),input.version===undefined?undefined:Number(input.version));});
 app.get('/api/v1/tavern/source/:source/:workId',async r=>library.acquire(source(r),work(r),sig(r)));
 app.post('/api/v1/tavern/source/:source/:workId',async r=>{const input=body(r);return library.save(source(r),work(r),await library.acquire(source(r),work(r),sig(r)),input.version===undefined?undefined:Number(input.version));});
 app.post('/api/v1/tavern/import',async r=>{const input=body(r);if(input.portrait!==undefined){
  const parsed=parseTavernAsset(input);if(parsed.kind!=='character')throw contentError();
  const png=writeTavernPng(Buffer.from(contentText(input.portrait,LIMIT*2),'base64'),parsed.data);
  return library.save('local',randomUUID(),{...parsed,format:'png',originalPng:png.toString('base64')});
 }const png=input.pngBase64?Buffer.from(contentText(input.pngBase64,LIMIT*2),'base64'):undefined,asset=parseTavernAsset(input,png);return library.save('local',contentText(input.workId??randomUUID(),512),{...asset,...(png?{originalPng:png.toString('base64')}:{})});});
 app.get('/api/v1/tavern/assets/:assetId/conversations',async r=>({items:library.conversations(contentText(p(r).assetId,128))}));
 app.post('/api/v1/tavern/assets/:assetId/conversations',async r=>library.saveConversation(contentText(p(r).assetId,128),body(r)));
 app.delete('/api/v1/tavern/assets/:assetId/conversations/:conversationId',async r=>{const input=body(r);return library.removeConversation(contentText(p(r).assetId,128),contentText(p(r).conversationId,128),input.version===undefined?undefined:Number(input.version));});
 function trackGeneration(r:FastifyRequest, raw:import('node:http').ServerResponse, connectionId:unknown){
  const owner=options.sessionId(r),owned=generations.get(owner)??new Set<AbortController>();
  if(owned.size>=2)throw contentError('RATE_LIMITED',429);
  const controller=new AbortController(),closed=()=>controller.abort(),upstream=sig(r);
  owned.add(controller);generations.set(owner,owned);
  if(typeof connectionId==='string')generationConnections.set(controller,connectionId);
  raw.once('close',closed);
  return {owner,controller,signal:upstream?AbortSignal.any([controller.signal,upstream]):controller.signal,
   release(){raw.removeListener('close',closed);controller.abort();owned.delete(controller);generationConnections.delete(controller);if(!owned.size)generations.delete(owner);}
  };
 }
 app.post('/api/v1/tavern/assets/:assetId/reply',async(r,reply)=>{
  const input=body(r),raw=reply.raw;
  if(input.useTranslatedLore===true&&!translationEnabled())throw contentError('CONFIRM_REQUIRED',409);
  const {owner,controller,signal,release}=trackGeneration(r,raw,input.connectionId);
  reply.hijack();raw.writeHead(200,{'content-type':'text/event-stream; charset=utf-8','cache-control':'private, no-store','x-content-type-options':'nosniff'});
  const event=async(value:unknown)=>{if(controller.signal.aborted||raw.destroyed)throw contentError('CANCELLED',499);if(!raw.write('data: '+JSON.stringify(value)+'\n\n'))await once(raw,'drain',{signal});};
  try{const assetId=contentText(p(r).assetId,128),locale=contentText(input.locale??'zh-Hans',32),revision=terms.snapshot(locale)?.revision??0,translated=input.useTranslatedLore===true?(content:string)=>{const value=translations.get(translationKey(owner,assetId,locale,revision,content));return value&&value.expires>Date.now()?value.text:undefined;}:undefined,result=await library.reply(assetId,input,signal,value=>event({type:'delta',content:value}),translated);await event({type:'done',...result});}
  catch(error){if(!raw.destroyed&&!controller.signal.aborted){const value=toPluginError(error),publicInfo=error as {publicError?:boolean;code?:unknown;retryable?:boolean},own=publicInfo?.publicError===true&&typeof publicInfo.code==='string'&&/^[A-Z_]{1,64}$/.test(publicInfo.code);raw.write('data: '+JSON.stringify({type:'error',code:own?publicInfo.code:value.code,retryable:own?publicInfo.retryable===true:value.retryable,...(value.details?{details:value.details}:{})})+'\n\n');}}
  finally{if(!raw.destroyed)raw.end();release();}
 });
 app.post('/api/v1/tavern/preview-lore',async r=>{
  const input=body(r),book=boundedJson(input.book),text=contentText(input.text,20000,true),locale=contentText(input.locale,32);
  const trace=new Map<Row,{name:string;reason:string;key?:string}>();
  const result=selectTavernLore(book,[{role:'user',content:text}],32768,key=>terms.aliasesFor(locale,key),(entry,reason,key)=>trace.set(entry,{name:String(entry.comment??entry.name??entry.content),reason,key}));
  return {trace:[...trace.values()],items:result.entries.map(entry=>String(entry.comment??entry.name??entry.content)),ignored:result.ignored};
 });
 async function writeDraft(r:FastifyRequest,raw:import('node:http').ServerResponse,connectionId:string,prompt:string){
  const generation=trackGeneration(r,raw,connectionId);
  try{return await library.reply(undefined,{connectionId,messages:[{role:'user',content:prompt}]},generation.signal);}
  finally{generation.release();}
 }
 app.post('/api/v1/tavern/revise',async (r,reply)=>{
  const input=body(r),connectionId=contentText(input.connectionId,128);
  const task=input.outline===true?'Create an editable world book outline. Group entries into batches, with titles, scope and distinct trigger keywords. Preserve the language of the brief.':input.summary===true?'Summarize established events, relationships and outstanding goals.':'Revise this field according to the accompanying instructions.';
  const prompt=task+' Return only the resulting text.\n'+contentText(input.text,100000,true)+'\n'+contentText(input.brief??'',4000,true);
  const result=await writeDraft(r,reply.raw,connectionId,prompt);
  if(result.finishReason==='length')throw contentError('INCOMPLETE',422);
  return {text:result.content};
 });
 app.post('/api/v1/tavern/generate',async (r,reply)=>{
  const input=body(r),kind=contentText(input.kind,32),connectionId=contentText(input.connectionId,128);
  if(!['character','lorebook'].includes(kind))throw contentError('BAD_REQUEST',400);
  const brief=contentText(input.prompt,20000);
  const shape=kind==='character'?'Character Card V2 {spec:"chara_card_v2",spec_version:"2.0",data:{name,description,personality,scenario,first_mes,mes_example,creator_notes,system_prompt,post_history_instructions,alternate_greetings,tags,creator,character_version,extensions}}':'a world book {name,entries:[{comment,keys,content,enabled}]}';
  const requestText='Return only JSON for '+shape+'. Write in '+contentText(input.locale,32)+'.\n'+brief;
  const result=await writeDraft(r,reply.raw,connectionId,requestText);
  if(result.finishReason==='length')throw contentError('INCOMPLETE',422);
  let data:unknown;
  try{data=JSON.parse(result.content.trim().replace(/^```(?:json)?\s*|\s*```$/gi,''));}catch{throw contentError('PARSE',422);}
  const parsed=parseTavernAsset({kind,format:'json',data});
  if(kind==='character'){
    const fields=contentObject(parsed.data.data??parsed.data);
    for(const key of ['name','description','personality','scenario','first_mes','mes_example','creator_notes','system_prompt','post_history_instructions','creator','character_version']){
      fields[key]??='';
      if(typeof fields[key]!=='string')throw contentError('PARSE',422);
    }
    for(const key of ['alternate_greetings','tags']){
      fields[key]??=[];
      if(!Array.isArray(fields[key])||fields[key].some(value=>typeof value!=='string'))throw contentError('PARSE',422);
    }
    fields.extensions=contentObject(fields.extensions??{});
    parsed.data={spec:'chara_card_v2',spec_version:'2.0',data:fields};
  }
  const book=kind==='lorebook'?contentObject(parsed.data.entries?parsed.data:parsed.data.data):contentObject(parsed.data.data).character_book;
  if(book!==undefined){
    const world=contentObject(book);
    world.extensions=contentObject(world.extensions??{});
    if(!Array.isArray(world.entries))throw contentError('PARSE',422);
    for(const raw of world.entries){
      const entry=contentObject(raw);
      if(!Array.isArray(entry.keys)||!entry.keys.every(key=>typeof key==='string')||typeof entry.content!=='string'||!entry.content.trim())throw contentError('PARSE',422);
      entry.enabled??=true;entry.insertion_order??=100;entry.extensions=contentObject(entry.extensions??{});
      if(typeof entry.enabled!=='boolean'||!Number.isSafeInteger(entry.insertion_order))throw contentError('PARSE',422);
    }
  }
  return parsed;
 });
 return {library,games,connections,terms,async revokeSession(owner:string){for(const controller of generations.get(owner)??[])controller.abort();generations.delete(owner);for(const [id,plan]of plans)if(plan.owner===owner)plans.delete(id);for(const key of translations.keys())if(JSON.parse(key)[0]===owner)translations.delete(key);for(const [id,value]of files)if(value.owner===owner)files.delete(id);await games.revoke(owner);},async revokeSource(source:string){for(const [id,value]of files)if(value.source===source)files.delete(id);await games.revokeSource(source);}};
}
