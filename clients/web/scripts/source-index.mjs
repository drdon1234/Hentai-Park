import { readFile,readdir,writeFile,rename } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { resolve,join,dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SourceHost } from '../packages/source-host/dist/index.js';
import { assertSupportedNode } from './node-version.mjs';
import {prepareSharedAssets,applicationVersion} from './shared-assets.mjs';
assertSupportedNode();
const root=fileURLToPath(new URL('../',import.meta.url));
await prepareSharedAssets();
const host=new SourceHost(join(root,'apps/source-runner/dist/index.js'),await applicationVersion(),{runtimePath:join(root,'assets/runtime/park_runtime.js')});
const entries=[],rejected=[],seen=new Set();
try {
 for(const file of (await readdir(join(root,'assets/sources'))).filter(name=>name.endsWith('.js')).sort()){
  try{const path=join(root,'assets/sources',file);const manifest=await host.inspect(path);if(seen.has(manifest.key))throw Object.assign(Error('duplicate source identity'),{code:'INVALID_MANIFEST'});seen.add(manifest.key);entries.push({source:manifest.key,version:manifest.version,sha256:createHash('sha256').update(await readFile(path)).digest('hex'),file,manifest});}
  catch(error){rejected.push({source:file.slice(0,-3),file,code:error.code??'INVALID_MANIFEST',reason:String(error.message).slice(0,256)});}
 }
 if(!entries.length)throw Error('No compatible sources; index was not replaced');
 for(const [name,value]of [['source-index.json',entries],['source-rejections.json',rejected]]){const path=join(root,'assets',name);const temporary=path+'.'+process.pid+'.tmp';await writeFile(temporary,JSON.stringify(value,null,2)+'\n','utf8');await rename(temporary,path);}
 console.log(JSON.stringify({compatible:entries.length,rejected:rejected.length,rejections:'assets/source-rejections.json'}));
}finally{await host.dispose();}
