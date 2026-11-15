import {access,readdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
const root=fileURLToPath(new URL('../',import.meta.url));
const projects=['packages/source-contract','packages/domain-model','packages/source-runtime','packages/source-host','apps/browser-worker','apps/task-worker','apps/source-runner','apps/api'];
async function missingOutputs(){
  const expected=['apps/web/dist/index.html','assets/runtime/polyfills.js'];
  for(const project of projects){
    for(const file of await readdir(join(root,project,'src'),{recursive:true})){
      if(file.endsWith('.ts')&&!file.endsWith('.d.ts'))expected.push(join(project,'dist',file.slice(0,-3)+'.js'));
    }
  }
  const missing=[];
  for(const file of expected){try{await access(join(root,file));}catch{missing.push(file);}}
  return missing;
}
const missing=await missingOutputs();
if(missing.length){
  console.log(`Build output is incomplete (${missing.length} missing files). Building the application...`);
  const result=spawnSync(process.execPath,[join(root,'scripts/build.mjs')],{cwd:root,stdio:'inherit',windowsHide:true});
  if(result.error)throw result.error;
  if(result.status!==0)process.exit(result.status??1);
  const remaining=await missingOutputs();
  if(remaining.length)throw Error(`Build output is still missing: ${remaining.join(', ')}`);
}
