import { readFile,readdir,writeFile,rename } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { resolve,join,dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SourceHost } from '../packages/source-host/dist/index.js';
import { assertSupportedNode } from './node-version.mjs';
assertSupportedNode();
const root=fileURLToPath(new URL('../',import.meta.url));
const repositoryRoot=fileURLToPath(new URL('../../../',import.meta.url));
const host=new SourceHost(join(root,'apps/source-runner/dist/index.js'),'0.14.3',{runtimePath:join(root,'assets/runtime/park_runtime.js')});
const entries=[],rejected=[],seen=new Set();
try {
 const publicIndex=JSON.parse(await readFile(join(repositoryRoot,'assets/sources/index.json'),'utf8'));
 const publicOrder=new Map(publicIndex.sources.map((entry,index)=>[String(entry.key),index]));
 const files=(await readdir(join(root,'assets/sources'))).filter(name=>name.endsWith('.js'));
 files.sort((a,b)=>{
  const aOrder=publicOrder.get(a.slice(0,-3))??Number.MAX_SAFE_INTEGER;
  const bOrder=publicOrder.get(b.slice(0,-3))??Number.MAX_SAFE_INTEGER;
  return aOrder-bOrder||a.localeCompare(b);
 });
 for(const file of files){
  try{const path=join(root,'assets/sources',file);const manifest=await host.inspect(path);if(seen.has(manifest.key))throw Object.assign(Error('duplicate source identity'),{code:'INVALID_MANIFEST'});seen.add(manifest.key);entries.push({source:manifest.key,version:manifest.version,sha256:createHash('sha256').update(await readFile(path)).digest('hex'),file,manifest});}
  catch(error){rejected.push({source:file.slice(0,-3),file,code:error.code??'INVALID_MANIFEST',reason:String(error.message).slice(0,256)});}
 }
 if(!entries.length)throw Error('No compatible sources; index was not replaced');
 for(const [name,value]of [['source-index.json',entries],['source-rejections.json',rejected]]){const path=join(root,'assets',name);const temporary=path+'.'+process.pid+'.tmp';await writeFile(temporary,JSON.stringify(value,null,2)+'\n','utf8');await rename(temporary,path);}
 console.log(JSON.stringify({compatible:entries.length,rejected:rejected.length,rejections:'assets/source-rejections.json'}));
}finally{await host.dispose();}
