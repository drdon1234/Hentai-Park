import { createRequire } from 'node:module';
import { assertSupportedNode } from './node-version.mjs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
assertSupportedNode();
await import('./ensure-build.mjs');
const {createRuntime,root}=await import('./runtime.mjs');
const runtime=await createRuntime();
const require=createRequire(new URL('../apps/web/package.json',import.meta.url));
let server;try{const address=await runtime.listen();const {createServer}=await import(pathToFileURL(require.resolve('vite')).href);const target=process.env.WEB_API_PROXY??address;server=await createServer({root:join(root,'apps/web'),server:{host:'127.0.0.1',proxy:{'/api':{target,changeOrigin:false},'/health':{target,changeOrigin:false}}}});await server.listen();server.printUrls();}catch(error){await server?.close();await runtime.close();throw error;}
let closing=false;const close=async()=>{if(closing)return;closing=true;await server.close();await runtime.close();};process.on('SIGINT',close);process.on('SIGTERM',close);
