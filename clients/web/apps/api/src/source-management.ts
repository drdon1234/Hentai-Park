import type {FastifyInstance,FastifyReply,FastifyRequest} from 'fastify';
import type {SourceOperations} from './source-operations.js';
import {isSourceKey} from '@hentai-park/source-contract';
import type {SourcePackages} from './source-packages.js';
type Row=Record<string,unknown>;
export interface SourceManagementOptions {
  restorePrivate?:(source:string)=>Promise<void>;
  signal?:(request:FastifyRequest)=>AbortSignal|undefined;
  write?:(request:FastifyRequest,reply:FastifyReply,operation:string,body:Row,source:string,action:()=>Promise<Row>)=>Promise<unknown>;
  packages?:SourcePackages;
}
const invalid=()=>Object.assign(new Error('Invalid source management request'),{code:'BAD_REQUEST',statusCode:400,publicError:true});
function sourceKey(request:FastifyRequest){const key=(request.params as Row).key;if(!isSourceKey(key))throw invalid();return key;}
function bodyObject(value:unknown):Row{if(!value||typeof value!=='object'||Array.isArray(value))throw invalid();return value as Row;}
/** Register inside the authenticated /api/v1 router. */
export function registerSourceManagementRoutes(router:FastifyInstance,operations:SourceOperations,options:SourceManagementOptions={}){
  const restore=async(source:string)=>{await options.restorePrivate?.(source);};
  const write=async(request:FastifyRequest,reply:FastifyReply,operation:string,body:Row,source:string,action:()=>Promise<Row>)=>{const prepared=async()=>{await restore(source);return action();};return options.write?options.write(request,reply,operation,body,source,prepared):prepared();};
  router.get('/sources/:key/settings',async request=>{const source=sourceKey(request);await restore(source);return operations.settings(source);});
  router.patch('/sources/:key/settings',async(request,reply)=>{const source=sourceKey(request),body=bodyObject(request.body);return write(request,reply,'sources.settings',body,source,()=>operations.updateSettings(source,body));});
  router.get('/sources/:key/account',async request=>{const source=sourceKey(request);await restore(source);return operations.accountStatus(source,options.signal?.(request));});
  for(const operation of ['logout','managed'] as const)router.post('/sources/:key/'+operation,async(request,reply)=>{const source=sourceKey(request),body=bodyObject(request.body??{});return write(request,reply,'sources.'+operation,body,source,()=>operations.execute(source,operation,body,options.signal?.(request)));});
  router.delete('/sources/:key',async(request,reply)=>{const source=sourceKey(request),body=bodyObject(request.body??{});return write(request,reply,'sources.uninstall',body,source,()=>operations.uninstall(source));});
  const packages=options.packages;if(packages){
    router.addHook('onClose',()=>packages.close());
    router.post('/source-packages/preview',async request=>{const body=bodyObject(request.body);if(Object.keys(body).some(key=>!['url','sha256'].includes(key))||typeof body.url!=='string'||body.sha256!==undefined&&(typeof body.sha256!=='string'||!/^[a-f0-9]{64}$/i.test(body.sha256)))throw invalid();return packages.preview({url:body.url,sha256:body.sha256 as string|undefined},options.signal?.(request));});
    router.post('/source-packages/install',async(request,reply)=>{const body=bodyObject(request.body);if(Object.keys(body).some(key=>!['candidateId','expectedSha256','expectedVersion','expectedCurrentVersion','expectedCurrentSha256','confirmed','requestKey','source'].includes(key))||typeof body.candidateId!=='string'||typeof body.expectedSha256!=='string'||typeof body.expectedVersion!=='string'||!(body.expectedCurrentVersion===null||typeof body.expectedCurrentVersion==='string')||typeof body.source!=='string')throw invalid();const source=sourceKey({params:{key:body.source}} as unknown as FastifyRequest);return write(request,reply,'sources.install',body,source,()=>packages.install(body as unknown as Parameters<SourcePackages['install']>[0]));});
    router.post('/source-packages/repository',async request=>{const body=bodyObject(request.body);if(Object.keys(body).some(key=>!['url','official'].includes(key))||typeof body.url!=='string'||body.official!==undefined&&typeof body.official!=='boolean')throw invalid();return packages.repository(body.url,options.signal?.(request),body.official===true);});
    router.post('/source-packages/repository-preview',async request=>{const body=bodyObject(request.body);if(Object.keys(body).some(key=>!['url','key','official'].includes(key))||typeof body.url!=='string'||typeof body.key!=='string'||body.official!==undefined&&typeof body.official!=='boolean')throw invalid();return packages.previewRepository(body.url,body.key,options.signal?.(request),body.official===true);});
    router.post('/source-packages/check',async request=>{const body=bodyObject(request.body??{});if(Object.keys(body).length)throw invalid();return packages.checkOfficial(options.signal?.(request));});
    router.post('/sources/:key/check-update',async request=>{const source=sourceKey(request),body=bodyObject(request.body??{});if(Object.keys(body).some(key=>key!=='sha256')||body.sha256!==undefined&&(typeof body.sha256!=='string'||!/^[a-f0-9]{64}$/i.test(body.sha256)))throw invalid();await restore(source);return packages.checkSource(source,options.signal?.(request),body.sha256 as string|undefined);});
  }
}
