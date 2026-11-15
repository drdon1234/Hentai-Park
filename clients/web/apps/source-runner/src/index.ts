import fs from 'node:fs/promises';
import path from 'node:path';
import { getQuickJS } from 'quickjs-emscripten';
import { randomUUID } from 'node:crypto';
import {cryptoOperation} from './crypto.js';
import { fileURLToPath } from 'node:url';
import { CAPABILITY_NAMES,operationCapability } from '@hentai-park/source-contract';
import { normalizeRuntimeManifest, legacyInvocation, normalizePluginError } from '@hentai-park/source-runtime';
import type { PluginManifest } from '@hentai-park/source-contract';
const argument = (name: string) => { const i = process.argv.indexOf(name); return i >= 0 ? process.argv[i + 1] : undefined; };
const pluginPath = argument('--plugin');
const runtimePath = argument('--runtime') ?? fileURLToPath(new URL('../../../assets/runtime/park_runtime.js', import.meta.url));
const engine = await getQuickJS();
const engineRuntime = engine.newRuntime();
engineRuntime.setMemoryLimit(64 * 1024 * 1024);
engineRuntime.setMaxStackSize(512 * 1024);
const startupDeadline = Date.now() + 5000;
const requestDeadlines = new Map<string, number>();
let runtimeLoaded = false;
let deadline = startupDeadline;
let executionInterrupted = false;
engineRuntime.setInterruptHandler(() => {
    if (Date.now() > deadline) executionInterrupted = true;
    return executionInterrupted;
});
function executionTimeout() { return Object.assign(new Error('isolated execution deadline exceeded'), {code:'TIMEOUT',retryable:true,details:{reason:'RECEIVE_TIMEOUT'}}); }
function prepareExecution() {
    if (executionInterrupted) throw executionTimeout();
    const active = requestDeadlines.size ? Math.min(...requestDeadlines.values()) : undefined;
    deadline = runtimeLoaded ? active ?? Date.now() + 1000 : Math.min(startupDeadline, active ?? startupDeadline);
}
const context = engineRuntime.newContext();
function engineError() { return Object.assign(new Error('isolated JavaScript execution failed'), {code:'PARSE'}); }
function run(source: string) { prepareExecution(); const result = context.evalCode(source, 'plugin.js', { type: 'global' }); if (result.error) {
    result.error.dispose();
    throw executionInterrupted ? executionTimeout() : engineError();
} try {
    if (executionInterrupted) throw executionTimeout();
    return context.typeof(result.value) === 'string' ? context.getString(result.value) : undefined;
}
finally {
    result.value.dispose();
} }
function jobs() { prepareExecution(); const result = engineRuntime.executePendingJobs(1000); if (result.error) {
    result.error.dispose();
    throw executionInterrupted ? executionTimeout() : engineError();
} if (executionInterrupted) throw executionTimeout(); }
function read<T>(source: string): T { return JSON.parse(String(run(`JSON.stringify(${source})`))) as T; }
function send(message: unknown) { const id=(message as {id?:string}).id;if(id)requestDeadlines.delete(id);process.stdout.write(JSON.stringify(message) + '\n'); }
let manifest: PluginManifest;
let loaded: Promise<void>;
const network = new Map<string, string>();
let stopped = false;
function fail(code: string, message: string) { return Object.assign(new Error(message), { code }); }
async function load() {
    if (!pluginPath)
        throw fail('CONFIG', 'plugin path missing');
    const source = await fs.readFile(pluginPath, 'utf8');
    if (Buffer.byteLength(source) > 8 * 1024 * 1024)
        throw fail('PARSE', 'plugin exceeds size limit');
    const polyfill = await fs.readFile(path.join(path.dirname(runtimePath), 'polyfills.js'), 'utf8');
    run(`globalThis.__bridge={out:[],pending:new Map(),results:new Map(),sequence:0};
    globalThis.__call=(operation,args)=>new Promise((resolve,reject)=>{const id=String(++__bridge.sequence);__bridge.pending.set(id,{resolve,reject});__bridge.out.push({id,operation,args});});
    globalThis.setTimeout=(callback,delay,...args)=>{const id=++__bridge.sequence;__call('sleep',{delay:Math.max(0,Math.min(Number(delay)||0,30000)),timer:id}).then(()=>callback(...args));return id;};globalThis.clearTimeout=id=>__bridge.out.push({id:String(++__bridge.sequence),operation:'clearTimer',args:{timer:id}});
    globalThis.console=Object.freeze({log(){},error(){},warn(){},info(){}});
    globalThis.btoa=s=>{const chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';let out='';for(let i=0;i<s.length;i+=3){const a=s.charCodeAt(i),b=s.charCodeAt(i+1),c=s.charCodeAt(i+2),v=(a<<16)|((b||0)<<8)|(c||0);out+=chars[(v>>>18)&63]+chars[(v>>>12)&63]+(i+1<s.length?chars[(v>>>6)&63]:'=')+(i+2<s.length?chars[v&63]:'=');}return out;};
    globalThis.atob=s=>{const chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';let n=0,bits=0,out='';for(const c of String(s).replace(/=+$/,'')){const v=chars.indexOf(c);if(v<0)continue;n=(n<<6)|v;bits+=6;if(bits>=8){bits-=8;out+=String.fromCharCode((n>>>bits)&255);}}return out;};`);
    run(polyfill);
    run(await fs.readFile(runtimePath, 'utf8'));
    run(`Park.__native=Object.freeze({request:args=>__call('request',args),chatRequest:args=>__call('chatRequest',args),crypto:(op,args)=>__call('crypto',{op,args}),cookies:(op,args)=>__call('cookies',{op,args}),persist:(source,data,flush)=>__call('persist',{source,data,flush}),log(){}});`);
    // Plugins are scripts evaluated in a dedicated QuickJS WASM heap. No host function, Promise,
    // process, filesystem, native fetch, require or dynamic import is injected.
    const normalized = source.replace(/^\s*export\s+default\s+/, 'globalThis.__moduleExport = ');
    run(normalized);
    run(`if(globalThis.__moduleExport){const x=__moduleExport;globalThis.__modern=!!(x.manifest||x.implementation);globalThis.__definition=x.implementation?{...x.manifest,...x.implementation}:x.manifest?{...x.manifest,...x}:x;if(__modern)Park.register(__definition);}else globalThis.__definition=Park.__pending;if(!__definition)throw Error('plugin did not register');`);
    const raw = read<Record<string, unknown>>('({...Park.manifest(__definition.key),account:__definition.account?{...Park.manifest(__definition.key).account,registerUrl:__definition.account.registerUrl}:null,navigationDomains:__definition.navigationDomains,frameDomains:__definition.frameDomains})');
    const declared = read<Record<string, unknown>>('__definition.capabilities || {}');
    const available = read<Record<string, boolean>>(`Object.fromEntries(${JSON.stringify(CAPABILITY_NAMES)}.map(k=>[k,typeof __definition[k]==='function']))`);
    manifest = normalizeRuntimeManifest(raw, declared, available);
    runtimeLoaded = true;
}

const timers = new Map<number, ReturnType<typeof setTimeout>>();
const state: Record<string, unknown> = {};
function settle(id: string, error: unknown, result?: unknown) { run(`{const pending=__bridge.pending.get(${JSON.stringify(id)});if(pending){__bridge.pending.delete(${JSON.stringify(id)});${error ? `pending.reject(Object.assign(new Error('host operation failed'),${JSON.stringify(normalizePluginError(error))}))` : `pending.resolve(${JSON.stringify(result ?? null)})`};}}`); }
function drain() { if (stopped)
    return; try {
    jobs();
    const messages = read<Array<{
        id: string;
        operation: string;
        args: Record<string, unknown>;
    }>>('(()=>{const out=__bridge.out;__bridge.out=[];return out})()');
    for (const m of messages) {
        try {
            if (m.operation === 'request') {
                const id = randomUUID();
                network.set(id, m.id);
                send({ id, type: 'network', request: m.args });
            }
            else if (m.operation === 'sleep') {
                const timer = setTimeout(() => { timers.delete(Number(m.args.timer)); settle(m.id, null); drain(); }, Number(m.args.delay));
                timers.set(Number(m.args.timer), timer);
            }
            else if (m.operation === 'clearTimer') {
                clearTimeout(timers.get(Number(m.args.timer)));
                timers.delete(Number(m.args.timer));
            }
            else if (m.operation === 'crypto') {
                settle(m.id, null, cryptoOperation(String(m.args.op), m.args.args as Record<string, unknown>));
            }
            else if (m.operation === 'persist' || m.operation === 'cookies' || m.operation === 'chatRequest') {
                const id = randomUUID();
                network.set(id, m.id);
                send({ id, type: 'native', operation: m.operation, args: m.args });
            }
            else
                settle(m.id, fail('UNSUPPORTED', 'unknown host operation'));
        }
        catch (error) {
            settle(m.id, error);
        }
    }
    const results = read<Array<unknown>>('(()=>{const out=[...__bridge.results.values()];__bridge.results.clear();return out})()');
    for (const value of results) {const result=value as {id:string;result?:unknown;error?:unknown};send(result.error?{id:result.id,error:normalizePluginError(result.error)}:result);}
}
catch (error) {
    send({ id: '__runtime__', error: normalizePluginError(error) });
    process.exit(1);
} }
let setup = false;
async function handle(line: string) { let msg: {
    id?: string;
    deadlineAt?: number;
    method?: string;
    result?: unknown;
    error?: unknown;
    params?: {
        method?: string;
        params?: unknown;
        expectedManifest?: PluginManifest;
        id?: string;
        operation?: string;
        values?: Record<string, string>;
        stateSnapshot?: Record<string, unknown>;
        page?:{url:string;html:string};
        query?:{scope:'feed'|'search';feed?:string;filter:string;values?:Record<string,string|number|boolean>;keyword?:string};
    };
}; try {
    msg = JSON.parse(line);
}
catch {
    return;
} if (!msg.id)
    return; try {
    if(msg.method && msg.method!=='cancel') {
        const now=Date.now();
        const requested=msg.deadlineAt;
        if(typeof requested!=='number'||!Number.isSafeInteger(requested)||requested<=0)throw fail('CONFIG','invalid execution deadline');
        requestDeadlines.set(msg.id,Math.min(requested,now+300000));
        if(requestDeadlines.get(msg.id)!<=now)throw executionTimeout();
    }
    await loaded;
    if (network.has(msg.id)) {
        const id = network.get(msg.id)!;
        network.delete(msg.id);
        settle(id, msg.error, msg.result);
        drain();
        return;
    }
    if (msg.method === 'cancel') {
        stopped = true;
        for (const t of timers.values())
            clearTimeout(t);
        process.exit(0);
    }
    if (msg.method === 'manifest') {
        send({ id: msg.id, result: manifest });
        return;
    }
    if(msg.method==='accountMethods') {send({id:msg.id,result:read("Object.fromEntries(['login','status','logout','enableManaged'].map(key=>[key,typeof __definition.account?.[key]==='function']))")});return;}
    const account = msg.method === 'account';
    const reverseResult=msg.method==='reverseSearchResult';
    const filterOptions=msg.method==='filterOptions';
    if (!msg.params || !account && !reverseResult && !filterOptions && (msg.method !== 'invoke' || !msg.params.method))
        throw fail('CONFIG', 'invalid invocation');
    if (account && (!manifest.account || !['login', 'status', 'logout', 'enableManaged'].includes(msg.params.operation ?? '') || msg.params.operation==='enableManaged'&&manifest.account?.managedAccount!==true))
        throw fail('UNSUPPORTED', 'account operation is unavailable');
    if(reverseResult&&(manifest.capabilities?.reverseSearch!==true||!read<boolean>("typeof __definition.reverseSearchResult==='function'")))throw fail('UNSUPPORTED','reverse search result parser is unavailable');
    if(filterOptions){const query=msg.params.query;const declarations=query?.scope==='feed'?manifest.feeds?.find(value=>value.key===query.feed)?.options:query?.scope==='search'?manifest.searchFilters:undefined;if(!declarations?.some(value=>value.dynamic===true&&value.key===query?.filter)||!read<boolean>("typeof __definition.filterOptions==='function'"))throw fail('UNSUPPORTED','dynamic filter query is unavailable');}
    if(reverseResult&&(!msg.params.page||typeof msg.params.page.url!=='string'||typeof msg.params.page.html!=='string'||Buffer.byteLength(msg.params.page.html,'utf8')>4*1024*1024))throw fail('CONFIG','invalid reverse search page');
    if (!setup)
        Object.assign(state, msg.params.stateSnapshot ?? {});
    const expected = msg.params.expectedManifest;
    if (expected && (expected.key !== manifest.key || expected.version !== manifest.version))
        throw fail('INVALID_MANIFEST', 'loaded plugin identity mismatch');
    const method = account ? 'account.' + msg.params.operation : reverseResult?'reverseSearchResult':filterOptions?'filterOptions':msg.params.method!;
    if (!account && !reverseResult && !filterOptions && (!operationCapability(method) || manifest.capabilities?.[operationCapability(method)!] !== true))
        throw fail('UNSUPPORTED', 'capability not declared');
    const invocation = account ? {path:method,args:[msg.params.values??{}]} : reverseResult?{path:'reverseSearchResult',args:[msg.params.page]}:filterOptions?{path:'filterOptions',args:[msg.params.query]}:legacyInvocation(manifest,method,msg.params.params);
    const {args,path:pathName}=invocation;
    const code = `Promise.resolve().then(async()=>{if(!globalThis.__setupPromise)globalThis.__setupPromise=Park.setup(${JSON.stringify(manifest.key)},${JSON.stringify(state)},{waitForInit:true}).catch(error=>{globalThis.__setupPromise=undefined;throw error;});await globalThis.__setupPromise;const result=globalThis.__modern&&!${JSON.stringify(account||reverseResult||filterOptions||method.includes('.'))}?{ok:true,value:await __definition[${JSON.stringify(method)}].call(__definition,${JSON.stringify(msg.params.params ?? null)})}:await Park.invoke(${JSON.stringify(manifest.key)},${JSON.stringify(pathName)},${JSON.stringify(args)},${JSON.stringify(msg.id)});if(!result.ok)throw result.error;await __definition.store?.flush?.();if(${JSON.stringify(account)}&&['login','enableManaged'].includes(${JSON.stringify(msg.params.operation)})){const status=await Park.invoke(${JSON.stringify(manifest.key)},'account.status',[],${JSON.stringify(msg.id)});if(!status.ok)throw status.error;return status.value;}return ${JSON.stringify(account && msg.params.operation === 'logout')}?{loggedIn:false}:result.value;}).then(result=>__bridge.results.set(${JSON.stringify(msg.id)},{id:${JSON.stringify(msg.id)},result}),error=>__bridge.results.set(${JSON.stringify(msg.id)},{id:${JSON.stringify(msg.id)},error:{code:error.code||'PARSE',message:'Plugin operation failed',retryable:error.retryable,diagnostics:error.diagnostics,details:error.details}}));`;
    run(code);
    setup = true;
    drain();
}
catch (error) {
    send({ id: msg.id, error: normalizePluginError(error) });
} }
process.stdin.setEncoding('utf8');
let buffer = '';
process.stdin.on('data', chunk => { buffer += chunk; if (buffer.length > 16 * 1024 * 1024) {
    process.exit(1);
} let i; while ((i = buffer.indexOf('\n')) >= 0) {
    const line = buffer.slice(0, i);
    buffer = buffer.slice(i + 1);
    void handle(line);
} });
loaded = load();
loaded.catch(error => { send({ id: '__startup__', error: normalizePluginError(error) }); process.exit(1); });
process.once('exit', () => { context.dispose(); engineRuntime.dispose(); });
const polling = setInterval(() => { if (manifest)
    drain(); }, 5);
process.stdin.on('end', () => { clearInterval(polling); for (const timer of timers.values())
    clearTimeout(timer); process.exit(0); });
