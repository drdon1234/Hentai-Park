type Row=Record<string,unknown>;
export type ArticleBlock={type:'text';text:string}|{type:'image';url:string}|{type:'video';id:string;preview?:string};
export interface ArticleDocument {blocks:ArticleBlock[];tagLinks:Array<{name:string;url:string}>;}
const invalid=()=>Object.assign(new Error('PARSE'),{code:'PARSE',statusCode:502,publicError:true,causeCategory:'source'});
const safe=(value:unknown,max:number,empty=false):string=>{if(typeof value!=='string'||!empty&&!value||value.length>max||/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(value))throw invalid();return value;};
export function publicResource(value:unknown):string {const url=new URL(safe(value,8192));if(url.protocol!=='https:'||url.username||url.password||url.port||url.hostname==='localhost'||url.hostname.endsWith('.local')||!/[a-z]$/i.test(url.hostname))throw invalid();return url.href;}
export function articleDocument(raw:Row):ArticleDocument {
 if(!Array.isArray(raw.blocks)||!raw.blocks.length||raw.blocks.length>10000||Buffer.byteLength(JSON.stringify(raw.blocks))>4_000_000)throw invalid();
 const ids=new Set<string>();const blocks:ArticleBlock[]=raw.blocks.map((block:unknown)=>{if(!block||typeof block!=='object'||Array.isArray(block))throw invalid();const b=block as Row;if(b.type==='text')return {type:'text',text:safe(b.text,1_000_000,true)};if(b.type==='image')return {type:'image',url:publicResource(b.url)};if(b.type==='video'){const id=safe(b.id,512);if(ids.has(id))throw invalid();ids.add(id);return {type:'video',id,...(b.preview?{preview:publicResource(b.preview)}:{})};}throw invalid();});
 const links=raw.tagLinks??[];if(!Array.isArray(links)||links.length>1000)throw invalid();
 return {blocks,tagLinks:links.map((value:unknown)=>{if(!value||typeof value!=='object')throw invalid();const r=value as Row;return {name:safe(r.name,512),url:publicResource(r.url)};})};
}
