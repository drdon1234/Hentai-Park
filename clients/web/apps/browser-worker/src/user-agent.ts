import {createRequire} from 'node:module';
import {readFileSync} from 'node:fs';
import {dirname,join} from 'node:path';
import {configureSourceUserAgent,getSourceUserAgent} from '@hentai-park/source-host';

// Resolve metadata through Playwright's own dependency graph, including bundled
// test modules and pnpm's isolated package layout. A broken install must be visible.
const metadataRequire=createRequire(import.meta.url);
const playwrightRequire=createRequire(metadataRequire.resolve('playwright/package.json'));
const coreDirectory=dirname(playwrightRequire.resolve('playwright-core/package.json'));
const metadata=JSON.parse(readFileSync(join(coreDirectory,'browsers.json'),'utf8')) as {browsers?:Array<{name?:string;browserVersion?:string}>};
const version=metadata.browsers?.find(browser=>browser.name==='chromium')?.browserVersion;
if(typeof version!=='string'||!/^\d+\.\d+\.\d+\.\d+$/.test(version))throw new Error('Installed Playwright Chromium browserVersion is missing or invalid');
const platform=process.platform==='win32'?'Windows NT 10.0; Win64; x64':process.platform==='darwin'?'Macintosh; Intel Mac OS X 10_15_7':'X11; Linux x86_64';
configureSourceUserAgent(`Mozilla/5.0 (${platform}) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${version} Safari/537.36`);
export {getSourceUserAgent};
