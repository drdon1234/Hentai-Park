import type {FastifyInstance,FastifyRequest} from 'fastify';
import type {SourceCatalog} from './catalog.js';
import {contentError,contentObject,contentText} from './content-model.js';
import type {MediaProxy} from './media.js';
type Row=Record<string,unknown>;
export interface ContentRouteOptions {sessionId:(request:FastifyRequest)=>string;signal?:(request:FastifyRequest)=>AbortSignal|undefined;media?:MediaProxy;isBlocked?:(row:Record<string,unknown>)=>boolean;allowLoopbackAi?:boolean;}
/** Registers authenticated product operations; global instance session/CSRF hooks remain authoritative. */
export function registerContentRoutes(app:FastifyInstance,catalog:SourceCatalog,options:ContentRouteOptions){
 const p=(request:FastifyRequest)=>contentObject(request.params),q=(request:FastifyRequest)=>contentObject(request.query??{}),s=(request:FastifyRequest)=>options.signal?.(request);
 const source=(request:FastifyRequest)=>contentText(p(request).source,100),id=(request:FastifyRequest)=>contentText(p(request).workId,512);
 const page=(value:unknown)=>{const number=value===undefined?1:Number(value);if(!Number.isSafeInteger(number)||number<1||number>100000)throw contentError('BAD_REQUEST',400);return number;};
 const payload=(request:FastifyRequest)=>{const body=contentObject(request.body??{});if(Buffer.byteLength(JSON.stringify(body))>128000)throw contentError('BAD_REQUEST',400);return body;};
 const markPost=(row:Row)=>({...row,blocked:options.isBlocked?.(row)??false,media:(Array.isArray(row.media)?row.media:[]).map(value=>{const item=contentObject(value);return {...item,hiddenByPreferences:options.isBlocked?.({source:row.source,previewOnly:item.previewOnly})??false};})});
 const params=(request:FastifyRequest)=>{const query=q(request);let context:Row={};if(query.context!==undefined){try{context=contentObject(JSON.parse(contentText(query.context,16000)));}catch{throw contentError('BAD_REQUEST',400);}}return {page:page(query.page),...(query.cursor===undefined?{}:{cursor:contentText(query.cursor,16384)}),...(query.parentId===undefined?{}:{parentId:contentText(query.parentId,512)}),...(query.sort===undefined?{}:{sort:contentText(query.sort,128)}),context};};
 app.get('/api/v1/sources/:source/suggestions',async request=>({...await catalog.suggestions(source(request),contentText(q(request).keyword,512),s(request)),requestId:request.id}));
 app.post('/api/v1/sources/:source/random',async request=>({...await catalog.random(source(request),contentObject(payload(request).filters??{}),options.sessionId(request),s(request)),requestId:request.id}));
 app.post('/api/v1/search/resolve',async request=>{const body=payload(request);return {...await catalog.resolveInput(contentText(body.input,4096),body.source===undefined?undefined:contentText(body.source,100),s(request)),requestId:request.id};});
 if(options.media)app.post('/api/v1/media/:token/renew',async request=>({...await options.media!.renew(contentText(p(request).token,128),options.sessionId(request),s(request)),requestId:request.id}));
 app.get('/api/v1/works/:source/:workId/content',async request=>({...catalog.contentDetails(source(request),id(request),options.sessionId(request)),requestId:request.id}));
 app.get('/api/v1/works/:source/:workId/navigation/:chapterId',async request=>({...catalog.readingNavigation(source(request),id(request),contentText(p(request).chapterId,512),q(request).cursor===undefined?undefined:contentText(q(request).cursor,16)),requestId:request.id}));
 app.get('/api/v1/works/:source/:workId/comments',async request=>({...await catalog.comments(source(request),id(request),params(request),options.sessionId(request),s(request)),requestId:request.id}));
 app.get('/api/v1/works/:source/:workId/related',async request=>({...await catalog.related(source(request),id(request),params(request),options.sessionId(request),s(request)),requestId:request.id}));
 app.get('/api/v1/works/:source/:workId/thumbnails',async request=>({...await catalog.thumbnails(source(request),id(request),page(q(request).page),options.sessionId(request),s(request)),requestId:request.id}));
 app.get('/api/v1/works/:source/:workId/magnets',async request=>({...await catalog.magnets(source(request),id(request),s(request)),requestId:request.id}));
 app.get('/api/v1/works/:source/:workId/interaction',async request=>({...await catalog.interact(source(request),id(request),{},s(request)),requestId:request.id}));
 app.post('/api/v1/works/:source/:workId/interaction',async request=>{const body=payload(request);if(body.confirmed!==true)throw contentError('CONFIRM_REQUIRED',409);return {...await catalog.interact(source(request),id(request),contentObject(body.request),s(request)),requestId:request.id};});
 app.get('/api/v1/works/:source/:workId/media-choices/:chapterId',async request=>({...await catalog.mediaChoices(source(request),id(request),contentText(p(request).chapterId,512),options.sessionId(request),s(request)),requestId:request.id}));
 app.post('/api/v1/channels/:source/normalize',async request=>{const body=payload(request);return {...await catalog.channelNormalize(source(request),contentText(body.input,4096),body.resolve===true,s(request)),requestId:request.id};});
 app.get('/api/v1/channels/:source/targets',async request=>{const query=q(request);return {...await catalog.channelTargets(source(request),{mode:'page',...(query.kind===undefined?{}:{kind:contentText(query.kind,128)}),...(query.query===undefined?{}:{query:contentText(query.query,512,true)}),...(query.cursor===undefined?{}:{cursor:contentText(query.cursor,16384)})},s(request)),requestId:request.id};});
 app.get('/api/v1/channels/:source/saved',async request=>({...catalog.savedChannels(source(request)),requestId:request.id}));
 app.post('/api/v1/channels/:source/saved',async request=>{const body=payload(request);if(!Number.isSafeInteger(body.version)||Number(body.version)<0)throw contentError('BAD_REQUEST',400);return {...await catalog.saveChannel(source(request),contentText(body.input,4096),Number(body.version),s(request)),requestId:request.id};});
 app.delete('/api/v1/channels/:source/saved',async request=>{const body=payload(request);if(!Number.isSafeInteger(body.version)||Number(body.version)<0)throw contentError('BAD_REQUEST',400);return {...catalog.removeChannel(source(request),contentText(body.id,4096),Number(body.version)),requestId:request.id};});
 app.get('/api/v1/channels/:source/posts',async request=>{const query=q(request),result=await catalog.channelPosts(source(request),contentText(query.target,4096),{page:page(query.page),...(query.cursor===undefined?{}:{cursor:contentText(query.cursor,16384)})},options.sessionId(request),s(request));return {...result,items:result.items.map(markPost),requestId:request.id};});
 app.get('/api/v1/posts/:source/:workId',async request=>({...markPost(await catalog.freshPost(source(request),id(request),options.sessionId(request),s(request))),requestId:request.id}));
 app.get('/api/v1/posts/:source/:workId/media/:mediaId',async request=>({...await catalog.postMedia(source(request),id(request),contentText(p(request).mediaId,512),options.sessionId(request),s(request)),requestId:request.id}));
}
