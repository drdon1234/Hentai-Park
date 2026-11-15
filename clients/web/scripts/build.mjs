import { spawnSync } from 'node:child_process';
import { assertSupportedNode } from './node-version.mjs';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { mkdir, rm } from 'node:fs/promises';
assertSupportedNode();
const root=fileURLToPath(new URL('../',import.meta.url));
const require=createRequire(import.meta.url);
function run(path,args){const result=spawnSync(process.execPath,[path,...args],{cwd:root,stdio:'inherit',windowsHide:true});if(result.error)throw result.error;if(result.status!==0)process.exit(result.status??1);}
const typesOnly=process.argv.includes('--types-only');
const projects=['packages/source-contract','packages/domain-model','packages/source-runtime','packages/source-host','apps/browser-worker','apps/task-worker','apps/source-runner','apps/api'];
if(!typesOnly){
  for(const project of projects)await rm(join(root,project,'dist'),{recursive:true,force:true});
  const sourceRequire=createRequire(new URL('../apps/source-runner/package.json',import.meta.url));
  const {build}=sourceRequire('esbuild');
  await mkdir(join(root,'assets/runtime'),{recursive:true});
  await build({stdin:{contents:"import URL from 'core-js-pure/actual/url/index.js'; import URLSearchParams from 'core-js-pure/actual/url-search-params/index.js'; import 'fast-text-encoding'; import {DOMParser} from 'linkedom/worker'; Object.assign(globalThis,{URL,URLSearchParams,DOMParser});",resolveDir:join(root,'apps/source-runner'),sourcefile:'runtime-polyfills.js'},bundle:true,platform:'browser',format:'iife',outfile:join(root,'assets/runtime/polyfills.js'),logLevel:'warning'});
}
for(const project of projects)run(require.resolve('typescript/bin/tsc'),['-b',project,'--noEmit','false','--force','--pretty','false',...(typesOnly?['--emitDeclarationOnly']:[])]);
if(typesOnly){run(require.resolve('typescript/bin/tsc'),['-b','--pretty','false']);process.exit(0);}
const webRequire=createRequire(new URL('../apps/web/package.json',import.meta.url));
run(join(dirname(webRequire.resolve('vite/package.json')),'bin/vite.js'),['build','apps/web']);
