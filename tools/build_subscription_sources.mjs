import {build} from './source-runner/node_modules/esbuild/lib/main.js';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
await build({entryPoints:[path.join(root,'assets/sources/telegram_entry.mjs')],outfile:path.join(root,'assets/sources/telegram.js'),bundle:true,platform:'browser',format:'iife',target:'es2020',minify:true,legalComments:'inline',pure:['console.log','console.warn','console.error'],nodePaths:[path.join(root,'tools/source-runner/node_modules')],define:{global:'globalThis',self:'globalThis','process.env.DEBUG':'""','process.env.NODE_ENV':'"production"'},banner:{js:'/* Telegram source; generated from telegram_entry.mjs. @mtproto/core 6.3.0 GPL-3.0; see docs/SUBSCRIPTIONS.md. */'}});
