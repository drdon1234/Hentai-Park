import {publicResource} from './article.js';
type Row=Record<string,unknown>;
export type AlbumScope={feed:string;options?:Row;common?:Row}|{target:unknown}|{search:{keyword:string;filters?:Row;common?:Row}};
const invalid=()=>Object.assign(new Error('PARSE'),{code:'PARSE',statusCode:502,publicError:true,causeCategory:'source'});
const str=(v:unknown,max=512)=>{if(typeof v!=='string'||!v||v.length>max||/[\u0000-\u001f\u007f]/.test(v))throw invalid();return v;};
export function albumItem(input:unknown,context?:(row:unknown)=>string|undefined):Row {
 if(!input||typeof input!=='object'||Array.isArray(input))throw invalid();const row=input as Row;
 const id=str(row.id);if(!['post','work'].includes(String(row.presentation))||!Array.isArray(row.media)||row.media.length>10000)throw invalid();
 if(row.date!==undefined&&row.date!==''&&(typeof row.date!=='string'||!/^\d{4}-\d{2}-\d{2}(?:T|$)/.test(row.date)||!Number.isFinite(Date.parse(row.date))))throw invalid();
 const ids=new Set<string>();let ordered:number|undefined;
 const media=row.media.map((value:unknown)=>{if(!value||typeof value!=='object'||Array.isArray(value))throw invalid();const m=value as Row;const mid=str(m.id);if(ids.has(mid)||!['image','video'].includes(String(m.type)))throw invalid();ids.add(mid);
  const hasOrder=m.order!==undefined;if(ordered!==undefined&&Boolean(ordered)!==hasOrder)throw invalid();ordered=Number(hasOrder);if(hasOrder&&(typeof m.order!=='number'||!Number.isFinite(m.order)))throw invalid();
  const resource=(v:unknown,max:number)=>{if(!v||typeof v!=='object'||Array.isArray(v))throw invalid();const r=v as Row;if(!Number.isSafeInteger(r.size)||Number(r.size)<1||Number(r.size)>max)throw invalid();str(r.cacheKey,512);return r;};
  if(!m.url&&!m.resource)throw invalid();if(m.previewOnly!==undefined&&typeof m.previewOnly!=='boolean')throw invalid();if(row.locked===true&&m.previewOnly!==true)throw invalid();
  if(m.format!==undefined&&(typeof m.format!=='string'||m.format.length>32))throw invalid();return {id:mid,type:m.type,format:m.format,hls:m.hls,mediaContext:context?.(m),...(m.url?{url:publicResource(m.url)}:{resource:resource(m.resource,512*1024*1024)}),...(m.preview?{preview:publicResource(m.preview)}:{}),...(m.previewResource?{previewResource:resource(m.previewResource,2*1024*1024)}:{}),...(hasOrder?{order:m.order}:{}),previewOnly:m.previewOnly===true,blurred:m.blurred===true};
 });
 return {id,presentation:row.presentation,title:typeof row.title==='string'?row.title.slice(0,2048):id,text:typeof row.text==='string'?row.text.slice(0,2_000_000):'',date:row.date??'',locked:row.locked===true,coverBlurred:row.coverBlurred===true,media};
}
export function mergeAlbum(prior:Row|undefined,next:Row):Row {
 if(!prior)return next;if(prior.presentation!==next.presentation)throw invalid();const media=new Map<string,Row>((prior.media as Row[]).map(m=>[String(m.id),m]));for(const m of next.media as Row[])media.set(String(m.id),m);const values=[...media.values()];const ordered=values.every(m=>typeof m.order==='number');if(values.some(m=>m.order!==undefined)&&!ordered)throw invalid();if(ordered)values.sort((a,b)=>Number(a.order)-Number(b.order));return {...prior,...next,media:values};
}
