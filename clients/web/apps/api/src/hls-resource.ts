import {unwrapHlsResource} from '@hentai-park/source-host';
export {unwrapHlsResource} from '@hentai-park/source-host';
const invalid=()=>Object.assign(new Error('Invalid media envelope'),{code:'PARSE',statusCode:502,publicError:true,causeCategory:'source',retryable:false});

/** Inspect a bounded prefix without buffering ordinary MP4/Range streams. */
export async function unwrapMediaResponse(response:Response,maxBytes:number,hlsBinary=false):Promise<Response>{
 if(!response.body||!response.ok)return response;const reader=response.body.getReader(),prefix:Uint8Array[]=[];let length=0;
 try{while(length<8){const next=await reader.read();if(next.done)break;prefix.push(next.value);length+=next.value.length;}
  if(Buffer.concat(prefix).subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))){let bytes=length;const chunks=[...prefix];for(;;){const next=await reader.read();if(next.done)break;bytes+=next.value.length;if(bytes>64*1024*1024+1024)throw invalid();chunks.push(next.value);}const decoded=unwrapHlsResource(Buffer.concat(chunks),maxBytes),headers=new Headers(response.headers);headers.set('content-length',String(decoded.length));headers.set('content-type','application/octet-stream');const result=new Response(new Uint8Array(decoded),{status:response.status,headers});Object.defineProperty(result,'url',{value:response.url});reader.releaseLock();return result;}
  const headers=new Headers(response.headers);if(hlsBinary&&/^(?:text\/html|text\/plain)/i.test(headers.get('content-type')??'')){const sample=Buffer.concat(prefix).subarray(0,512);let binary=sample.some(byte=>byte<32&&![9,10,13].includes(byte));try{new TextDecoder('utf-8',{fatal:true}).decode(sample,{stream:true});}catch{binary=true;}if(binary)headers.set('content-type','application/octet-stream');}const result=new Response(new ReadableStream<Uint8Array>({start(controller){for(const chunk of prefix)controller.enqueue(chunk);},async pull(controller){try{const next=await reader.read();if(next.done){reader.releaseLock();controller.close();}else controller.enqueue(next.value);}catch(error){controller.error(error);}},async cancel(reason){await reader.cancel(reason);reader.releaseLock();}}),{status:response.status,headers});Object.defineProperty(result,'url',{value:response.url});return result;
 }catch(error){await reader.cancel().catch(()=>{});reader.releaseLock();throw error;}
}
