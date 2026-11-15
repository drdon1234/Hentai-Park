import {isApplicationRoute} from './web-routes.mjs';
import {loadWebAssets} from './web-assets.mjs';
import { mkdir,readFile,writeFile,stat } from 'node:fs/promises';
import { resolve,join,relative,isAbsolute,extname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomBytes } from 'node:crypto';
import { EventEmitter } from 'node:events';
import { AppDatabase } from '../apps/api/dist/database.js';
import { buildApp } from '../apps/api/dist/index.js';
import { SourceCatalog } from '../apps/api/dist/catalog.js';
import { SourceOperations,readSourcePackages } from '../apps/api/dist/source-operations.js';
import { SourceHost,SourceRegistry,InstallationJournal,configureHttpProxy } from '../packages/source-host/dist/index.js';
import { BrowserWorker,BrowserNetworkExecutor,playwrightFactory,checkPlaywrightEnvironment } from '../apps/browser-worker/dist/index.js';
import { WorkerScheduler,SourceHostDownloadAdapter,SourceHostSubscriptionAdapter } from '../apps/task-worker/dist/index.js';
export const root=fileURLToPath(new URL('../',import.meta.url));
export async function createRuntime(config={}) {
  configureHttpProxy(process.env.WEB_HTTP_PROXY,{allowLocal:process.env.WEB_HTTP_PROXY_ALLOW_LOCAL==='true'});
  const mode=config.mode??process.env.WEB_SESSION_MODE??'local';if(!['local','server'].includes(mode))throw Error('WEB_SESSION_MODE must be local or server');
  const hostAddress=config.host??process.env.HOST??'127.0.0.1';const origin=config.origin??process.env.WEB_ALLOWED_ORIGIN;
  if(mode==='local'&&!['127.0.0.1','localhost','::1'].includes(hostAddress))throw Error('Local mode requires a loopback HOST; use server mode for remote access');
  if(mode==='server'&&(!(config.host??process.env.HOST)||!(config.authToken??process.env.AUTH_TOKEN)||!origin?.startsWith('https://')))throw Error('Server mode requires explicit HOST, AUTH_TOKEN and HTTPS WEB_ALLOWED_ORIGIN through a trusted reverse proxy');
  const data=resolve(config.dataDir??process.env.DATA_DIR??join(root,'data'));const downloads=resolve(config.downloadDir??process.env.DOWNLOAD_DIR??join(data,'downloads'));
  for(const path of [data,downloads,join(data,'plugins'),join(data,'private'),join(data,'logs'),join(data,'cache')])await mkdir(path,{recursive:true});
  const keyFile=join(data,'instance.key');try{await writeFile(keyFile,randomBytes(32).toString('base64url'),{flag:'wx',mode:0o600});}catch(error){if(error.code!=='EEXIST')throw error;}
  const secret=config.authToken??process.env.AUTH_TOKEN??(await readFile(keyFile,'utf8')).trim();if(secret.length<16)throw Error('Instance credential must contain at least 16 characters');
  const registry=new SourceRegistry(join(data,'source-registry.json'),join(data,'plugins'));const journal=new InstallationJournal(join(data,'source-installations.json'),join(data,'plugins'));await registry.load();await journal.load();
  let lastRuntimeError;
  const host=new SourceHost(join(root,'apps/source-runner/dist/index.js'),'0.14.3',{registry,journal,runtimePath:join(root,'assets/runtime/park_runtime.js'),pluginDirectory:join(data,'plugins'),stateDirectory:join(data,'private'),onError:()=>{lastRuntimeError={code:'SOURCE_REAP_FAILED',at:new Date().toISOString()};}});
  let browser,db,scheduler,disposed=false;
  const dispose=async()=>{if(disposed)return;disposed=true;let failure;for(const close of [()=>scheduler?.stop(),()=>browser?.close(),()=>host.dispose(),()=>db?.close()]){try{await close();}catch(error){failure??=error;}}if(failure)throw failure;};
  try {
  await host.recover();
  browser=new BrowserWorker(()=>playwrightFactory({executablePath:process.env.PLAYWRIGHT_EXECUTABLE_PATH,headless:true}));
  let browserState='ready';try{await checkPlaywrightEnvironment({executablePath:process.env.PLAYWRIGHT_EXECUTABLE_PATH});}catch{browserState='unavailable';}
  db=new AppDatabase(config.dbPath??process.env.WEB_DB_PATH??join(data,'web.sqlite'));
  const readSetting=(key,fallback)=>{const row=db.db.prepare('SELECT value_json FROM app_settings WHERE key=?').get(key);return row?JSON.parse(String(row.value_json)):fallback;};
  host.setBrowserExecutor(new BrowserNetworkExecutor({executablePath:process.env.PLAYWRIGHT_EXECUTABLE_PATH,adultConfirmed:()=>readSetting('ageConfirmed',false)===true}));
  const packages=await readSourcePackages(config.sourceIndex??join(root,'assets/source-index.json'));
  const sourceOperations=new SourceOperations(host,browser,packages,join(root,'assets/sources'));
  const missingPackages=packages.filter(item=>!host.registry.get(item.source));
  if(missingPackages.length)console.log(`Initializing ${missingPackages.length} bundled official plugins...`);
  for(const item of missingPackages){
    await sourceOperations.execute(item.source,'update',{action:'install',expectedSha256:item.sha256,expectedVersion:item.version,expectedCurrentVersion:null});
  }
  if(missingPackages.length)console.log('Bundled official plugins are ready.');
  for(const record of host.registry.list()){const saved=db.db.prepare('SELECT enabled FROM source_registry WHERE source=?').get(record.source);if(saved&&Boolean(saved.enabled)!==record.enabled)await host.setEnabled(record.source,Boolean(saved.enabled));}
  const catalog=new SourceCatalog(db,host,browser);catalog.syncRegistry();
  const resolveSource=source=>{const record=host.registry.get(source);const saved=db.db.prepare('SELECT enabled FROM source_registry WHERE source=?').get(source);if(!record?.enabled||saved?.enabled===0)return undefined;return {manifest:record.manifest,artifact:record.sha256,invoke:async(method,params,options)=>{await catalog.restorePrivate(source);return host.invoke(record.manifest,record.packagePath,method,params,options);},fetchResource:(url,options)=>host.fetchResource(source,url,options),mediaContext:row=>host.mediaContext(source,row),subscriptionContext:async()=>{await catalog.restorePrivate(source);return host.subscriptionContext(source);},downloadPlan:(workId,nodeId,options)=>catalog.downloadPlan(source,workId,nodeId,options)};};
  const downloadSettings=()=>({siteConcurrency:Number(readSetting('siteConcurrency',3)),taskConcurrency:Number(readSetting('taskConcurrency',1)),pageConcurrency:Number(readSetting('pageConcurrency',3))});
  const events=new EventEmitter();events.setMaxListeners(100);let lastWorkerError;
  scheduler=new WorkerScheduler(db.db,{downloadAdapter:new SourceHostDownloadAdapter(resolveSource,{db:db.db,downloadDir:downloads,pageConcurrency:()=>downloadSettings().pageConcurrency}),subscriptionAdapter:new SourceHostSubscriptionAdapter(resolveSource),downloadDir:downloads,downloadSettings,subscriptionSettings:()=>({enabled:readSetting('subscriptionsEnabled',true)!==false,intervalMs:Number(readSetting('subscriptionIntervalMs',21600000))}),publishEvent:event=>events.emit('domain-event',event),onError:error=>{lastWorkerError={code:typeof error?.code==='string'?error.code:'WORKER_ERROR',at:new Date().toISOString()};}});
  const unsupportedSources=JSON.parse(await readFile(join(root,'assets/source-rejections.json'),'utf8'));
  const app=buildApp(db,undefined,{catalog,sourceOperations,dataDirectory:data,downloadDir:downloads,sessionMode:mode,authToken:secret,allowedOrigin:origin,notifyControl:id=>scheduler.notifyControl(id),subscriptionIntervalMs:()=>scheduler.subscriptionIntervalMs,workerStatus:()=>scheduler.isRunning?'ready':'stopped',events,runtimeDiagnostics:()=>({browser:browserState,sourceHost:'ready',workerError:lastWorkerError,runtimeError:lastRuntimeError,unsupportedSources})});
  const webRoot=join(root,'apps/web/dist'),webAssets=await loadWebAssets(webRoot);
  const types={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.svg':'image/svg+xml','.png':'image/png','.ico':'image/x-icon','.woff2':'font/woff2'};
  app.setNotFoundHandler(async(request,reply)=>{
    if(request.url.startsWith('/api/')||!['GET','HEAD'].includes(request.method))return reply.code(404).send({error:{code:'NOT_FOUND',messageKey:'error.not_found',retryable:false,requestId:request.id,operation:request.url.split('?')[0],causeCategory:'not_found'}});
    let pathname;try{pathname=decodeURIComponent(request.url.split('?')[0]);}catch{return reply.code(400).send({error:{code:'BAD_REQUEST',requestId:request.id}});}
    const file=resolve(webRoot,'.'+pathname);const rel=relative(webRoot,file);if(rel.startsWith('..')||isAbsolute(rel))return reply.code(403).send({error:{code:'BLOCKED',requestId:request.id}});
    const application=isApplicationRoute(pathname),body=webAssets.get(application?'index.html':rel.replaceAll('\\','/'));
    if(!body)return reply.code(404).send({error:{code:'NOT_FOUND',requestId:request.id}});
    return reply.type(application?'text/html; charset=utf-8':types[extname(file)]??'application/octet-stream').header('cache-control',application||extname(file)==='.html'?'no-store':'public, max-age=31536000, immutable').send(body);
  });
  app.addHook('onClose',dispose);
  await scheduler.start();
  return {app,db,host,browser,scheduler,data,downloads,hostAddress,async listen(port=config.port??Number(process.env.PORT??8787)){return app.listen({host:hostAddress,port});},async close(){await app.close();}};
  } catch(error) {try{await dispose();}catch(cleanupError){throw new AggregateError([error,cleanupError],'Runtime startup failed and cleanup reported an error');}throw error;}
}
