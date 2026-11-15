import { assertSupportedNode } from './node-version.mjs';
assertSupportedNode();
const {createRuntime}=await import('./runtime.mjs');
const runtime=await createRuntime();
let address;try{address=await runtime.listen();}catch(error){await runtime.close();throw error;}
console.log(`\n============================================================\nHentaiPark Web is ready\nOpen in your browser: ${address}\nListening port: ${new URL(address).port}\nKeep this console open. Closing it stops the service.\n============================================================\nData: ${runtime.data}\nLocal unlock credential: ${runtime.data}/instance.key\n`);
let closing=false;const close=async()=>{if(closing)return;closing=true;try{await runtime.close();process.exitCode=0;}catch{process.exitCode=1;}};
process.on('SIGINT',close);process.on('SIGTERM',close);
if(process.platform==='win32'&&process.argv.includes('--open-browser')){
  const {spawn}=await import('node:child_process');
  const opener=spawn('explorer.exe',[address],{stdio:'ignore',windowsHide:true});
  opener.on('error',()=>console.error(`Could not open the browser automatically. Open ${address} manually.`));
  opener.unref();
}
if(process.argv.includes('--windows-launcher')){
  const {createInterface}=await import('node:readline');
  const commands=createInterface({input:process.stdin});
  const shutdown=()=>{commands.close();process.stdin.destroy();void close();};
  commands.on('line',line=>{if(line==='shutdown')shutdown();});
  process.stdin.on('end',shutdown);
}
