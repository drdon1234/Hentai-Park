import { readFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { assertSupportedNode } from './node-version.mjs';
try{assertSupportedNode();}catch(error){console.error(error.message);process.exit(1);}
const pkg=JSON.parse(await readFile(new URL('../package.json',import.meta.url),'utf8'));
const expected=pkg.packageManager.split('@').at(-1);
const version=process.platform==='win32'?spawnSync(process.env.ComSpec??'cmd.exe',['/d','/s','/c','pnpm --version'],{encoding:'utf8',windowsHide:true}):spawnSync('pnpm',['--version'],{encoding:'utf8'});
if(version.status!==0||version.stdout.trim()!==expected){console.error(`需要 pnpm ${expected}。运行 npm install -g pnpm@${expected} 后重试。`);process.exit(1);}
console.log(`环境检查通过：Node ${process.versions.node} / pnpm ${expected}`);
