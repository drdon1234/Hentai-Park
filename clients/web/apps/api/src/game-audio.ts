import type {createGuardedContext} from '@hentai-park/browser-worker';
type Guarded=Awaited<ReturnType<typeof createGuardedContext>>;
type Page=Guarded['page'];type BrowserContext=Guarded['context'];
/** Capture only audio produced inside the isolated game document, never system audio. */
export async function installGameAudio(context:BrowserContext){await context.addInitScript(()=>{
 const holder=globalThis as unknown as {__parkGameAudio?:{streams:MediaStream[];recorder?:MediaRecorder;chunks:string[];failed:boolean;output?:MediaStream}};
 const state=holder.__parkGameAudio={streams:[] as MediaStream[],chunks:[] as string[],failed:false};
 const destinations=new WeakMap<BaseAudioContext,MediaStreamAudioDestinationNode>();
 const connect=AudioNode.prototype.connect;
 AudioNode.prototype.connect=function(this:AudioNode,destination:AudioNode|AudioParam,output?:number,input?:number){
  const result=Reflect.apply(connect,this,[destination,...(output===undefined?[]:[output]),...(input===undefined?[]:[input])]);
  if(destination===this.context.destination&&'createMediaStreamDestination'in this.context){let captured=destinations.get(this.context);if(!captured){captured=(this.context as AudioContext).createMediaStreamDestination();destinations.set(this.context,captured);state.streams.push(captured.stream);}Reflect.apply(connect,this,[captured,...(output===undefined?[]:[output])]);}
  return result;
 } as typeof AudioNode.prototype.connect;
 const captured=new WeakSet<HTMLMediaElement>();document.addEventListener('playing',event=>{const media=event.target as HTMLMediaElement&{captureStream?:()=>MediaStream};if(!media?.captureStream||captured.has(media))return;try{const stream=media.captureStream();if(stream.getAudioTracks().length){captured.add(media);state.streams.push(new MediaStream(stream.getAudioTracks()));}}catch{/* This game may protect its own media stream. */}},true);
});}
export async function startGameAudio(page:Page){return page.evaluate(async()=>{
 const state=(globalThis as unknown as {__parkGameAudio?:{streams:MediaStream[];recorder?:MediaRecorder;chunks:string[];failed:boolean;output?:MediaStream}}).__parkGameAudio;
 if(!state||!MediaRecorder.isTypeSupported('audio/webm;codecs=opus'))return false;
 if(state.recorder?.state==='recording')return true;const streams=state.streams.filter(stream=>stream.getAudioTracks().some(track=>track.readyState==='live'));if(!streams.length)return false;
 const mixer=new AudioContext();await mixer.resume();const destination=mixer.createMediaStreamDestination();for(const stream of streams)mixer.createMediaStreamSource(stream).connect(destination);state.output=destination.stream;state.chunks=[];state.failed=false;
 const recorder=state.recorder=new MediaRecorder(destination.stream,{mimeType:'audio/webm;codecs=opus',audioBitsPerSecond:96000});recorder.ondataavailable=event=>{void event.data.arrayBuffer().then(buffer=>{if(!buffer.byteLength)return;if(buffer.byteLength>524288||state.chunks.length>=64){state.failed=true;recorder.stop();return;}const bytes=new Uint8Array(buffer);let binary='';for(let offset=0;offset<bytes.length;offset+=32768)binary+=String.fromCharCode(...bytes.subarray(offset,offset+32768));state.chunks.push(btoa(binary));});};recorder.onstop=()=>{state.output?.getTracks().forEach(track=>track.stop());void mixer.close();};recorder.start(100);return true;
});}
export async function readGameAudio(page:Page,stop=false){return page.evaluate(stop=>{const state=(globalThis as unknown as {__parkGameAudio?:{recorder?:MediaRecorder;chunks:string[];failed:boolean}}).__parkGameAudio;if(!state)return {active:false,chunks:[] as string[]};if(stop){if(state.recorder?.state==='recording')state.recorder.stop();state.chunks=[];return {active:false,chunks:[] as string[]};}if(state.failed)throw Error('Game audio consumer exceeded the bounded queue');return {active:state.recorder?.state==='recording',chunks:state.chunks.splice(0)};},stop);}
