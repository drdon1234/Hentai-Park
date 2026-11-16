export {unwrapHlsResource} from './hls-envelope.js';
import {responseChallenge} from './challenge.js';
export {responseChallenge,challengePage,firewallPage} from './challenge.js';
import {withDefaultUserAgent} from './user-agent.js';
export {getSourceUserAgent,configureSourceUserAgent,withDefaultUserAgent} from './user-agent.js';
export {requestPinnedStream} from './stream.js';
import {pinnedProxyAgent} from './proxy.js';
export {configureHttpProxy,connectPinnedTunnel} from './proxy.js';
import {chatRequest} from './chat-network.js';
export {chatRequest,connectChat,validateChatUrl,type ChatEvent,type ChatConnection} from './chat-network.js';
import {hostAllowed,redirectRequest,REDIRECT_STATUSES,mediaRequestHeaders} from './transport-policy.js';
export {hostAllowed,redirectRequest,REDIRECT_STATUSES,mediaRequestHeaders} from './transport-policy.js';
import {validatePrivateState,validateSourceSettings,type PrivateStateOptions} from './private-state.js';
export {validatePrivateState,validateSourceSettings,type PrivateStateOptions} from './private-state.js';
import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process';
import {decodeImage} from './image.js';
export { decodeImage } from './image.js';
import { createHash, randomUUID } from 'node:crypto';
import dns from 'node:dns/promises';
import net from 'node:net';
import https from 'node:https';
import { Readable } from 'node:stream';
import { gunzipSync, inflateSync, brotliDecompressSync } from 'node:zlib';
import { mkdir, readFile, writeFile, rename,stat,unlink } from 'node:fs/promises';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { isDeepStrictEqual } from 'node:util';
import { CookieJar, Cookie } from 'tough-cookie';
import type { PluginError, PluginManifest } from '@hentai-park/source-contract';
import { validateManifest, toPluginError, toAbortError, operationCapability } from '@hentai-park/source-contract';
export class HostError extends Error {
    constructor(readonly code: PluginError['code'], message: string, readonly details?: Record<string, unknown>) { super(message); }
}
function runnerError(error:PluginError) {const value=toPluginError(error);return Object.assign(new HostError(value.code,value.message,value.details as Record<string,unknown>|undefined),{retryable:value.retryable,diagnostics:value.diagnostics});}
export interface NetworkRequest {
    url: string;
    method?: string;
    headers?: Record<string, string>;
    body?: string;
    bodyBase64?: string;
    responseType?: string;
    followRedirects?: boolean;
    signal?: AbortSignal;
    mode?:'native'|'browser'|'auto';
    origin?:string;
    readOnly?:boolean;
}
export interface NetworkResponse {
    status: number;
    headers: Record<string, string>;
    body: string;
    url: string;
}
export interface SourceBrowserCookie {name:string;value:string;domain:string;path:string;expires:number;httpOnly:boolean;secure:boolean;sameSite?:'Strict'|'Lax'|'None';}
export interface SourceBrowserInput {source:string;manifest:PluginManifest;request:NetworkRequest;cookies:SourceBrowserCookie[];resource?:boolean;image?:boolean;session?:boolean;}
export interface SourceBrowserExecutor {request(input:SourceBrowserInput):Promise<NetworkResponse&{cookies?:SourceBrowserCookie[]}>;dispose?(source?:string):Promise<void>;}
function ipv6Bits(address: string): bigint {
    let value=address;
    if(value.includes('.')) {const at=value.lastIndexOf(':');const p=value.slice(at+1).split('.').map(Number);value=value.slice(0,at+1)+(p[0]*256+p[1]).toString(16)+':'+(p[2]*256+p[3]).toString(16);}
    const halves=value.split('::');const left=halves[0]?halves[0].split(':'):[];const right=halves[1]?halves[1].split(':'):[];
    const parts=halves.length===1?left:[...left,...Array(8-left.length-right.length).fill('0'),...right];
    return parts.reduce((bits,part)=>(bits<<16n)|BigInt(parseInt(part,16)),0n);
}
const IPV6_SPECIAL_PUBLIC:readonly [bigint,number][]=[['2001:1::1',128],['2001:1::2',128],['2001:1::3',128],['2001:3::',32],['2001:4:112::',48],['2001:20::',28],['2001:30::',28]].map(([value,length])=>[ipv6Bits(String(value)),Number(length)]);
const prefixContains=(value:bigint,prefix:bigint,length:number)=>value>>BigInt(128-length)===prefix>>BigInt(128-length);
// The shared outbound boundary requires globally reachable addresses, including
// embedded IPv4 destinations. IANA special-purpose registries are the baseline.
export function isPrivateAddress(address: string): boolean {
    const v=address.toLowerCase().replace(/^\[|\]$/g,'');const family=net.isIP(v);
    if(family===4){const [a,b,c,d]=v.split('.').map(Number);return a===0||a===10||a===127||a===100&&b>=64&&b<=127||a===169&&b===254||a===172&&b>=16&&b<=31||a===192&&(b===168||b===0&&c===0&&d!==9&&d!==10||b===0&&c===2||b===88&&c===99)||a===198&&(b===18||b===19||b===51&&c===100)||a===203&&b===0&&c===113||a>=224;}
    if(family!==6||v.includes('%'))return true;
    const bits=ipv6Bits(v);const embedded=()=>{const value=Number(bits&0xffffffffn);return isPrivateAddress([value>>>24,value>>>16&255,value>>>8&255,value&255].join('.'));};
    if(bits>>32n===0xffffn||bits>>32n===0x64ff9b0000000000000000n)return embedded();
    if(v==='::'||v==='::1'||/^f[cd]/.test(v)||/^fe[89ab]/.test(v)||v.startsWith('2001:db8:')||v.startsWith('3fff:'))return true;
    return false;
}
export async function validateNetworkUrl(raw: string, domains: string[] | undefined, lookup: typeof dns.lookup = dns.lookup, allowPort=false) { let target: URL; try {
    target = new URL(raw);
}
catch {
    throw new HostError('BLOCKED', 'invalid URL');
} if (target.protocol !== 'https:' || target.username || target.password || !allowPort && Boolean(target.port) || domains !== undefined && !hostAllowed(target.hostname, domains))
    throw new HostError('BLOCKED', 'network target is outside declared domains'); let addresses; try {
    addresses = await lookup(target.hostname, { all: true });
}
catch {
    throw new HostError('NETWORK', 'host resolution failed',{reason:'DNS',transport:'native'});
} if (!addresses.length || addresses.some((a) => isPrivateAddress(a.address)))
    throw new HostError('BLOCKED', 'private address is blocked'); return { target, addresses }; }
async function pinnedRequest(target: URL, req: NetworkRequest, addresses: Awaited<ReturnType<typeof validateNetworkUrl>>['addresses'],maxResponseBytes:number): Promise<Response> { const payload=req.bodyBase64!==undefined?Buffer.from(req.bodyBase64,'base64'):req.body!==undefined?Buffer.from(req.body,'utf8'):undefined;const requestHeaders={...req.headers,...(payload===undefined?{}:{'content-length':String(payload.length)})};return new Promise((done, reject) => { const request = https.request(target, { method: req.method ?? 'GET', headers: requestHeaders, signal: req.signal, timeout: 30000, agent:pinnedProxyAgent(target,addresses[0]!,req.signal), lookup: (_host, options, callback) => { const record = addresses[0]; callback(null, options.all ? addresses : record.address, record.family); } }, response => { const chunks: Buffer[] = []; let bytes = 0; response.on('data', (chunk: Buffer) => { bytes += chunk.length; if (bytes > maxResponseBytes) {
    response.destroy(new HostError('PARSE', 'upstream response exceeds limit'));
    return;
} chunks.push(chunk); }); response.on('error', reject); response.on('end', () => { const headers = new Headers(); for (let i = 0; i < response.rawHeaders.length; i += 2)
    headers.append(response.rawHeaders[i], response.rawHeaders[i + 1]); const status = response.statusCode ?? 502; try {
    let body = Buffer.concat(chunks);
    const encoding = headers.get('content-encoding');
    const options = { maxOutputLength: maxResponseBytes };
    if (encoding === 'gzip')
        body = gunzipSync(body, options);
    else if (encoding === 'deflate')
        body = inflateSync(body, options);
    else if (encoding === 'br')
        body = brotliDecompressSync(body, options);
    if (encoding) {
        headers.delete('content-encoding');
        headers.delete('content-length');
    }
    done(new Response(req.method === 'HEAD' || [204, 205, 304].includes(status) ? null : body, { status, headers }));
}
catch (error) {
    reject(error);
} }); }); request.on('timeout', () => request.destroy(new HostError('TIMEOUT', 'upstream timed out'))); request.on('error', reject); request.end(payload); }); }
export async function fetchPinnedResource(url: string, domains: string[] | undefined, options: {signal?:AbortSignal;headers?:Record<string,string>;method?:'GET'|'HEAD';followRedirects?:false;allowPort?:boolean} = {}): Promise<Response> {
    let raw=url;let headers=withDefaultUserAgent(options.headers);
    for(let hop=0;;hop++){
        const {target,addresses}=await validateNetworkUrl(raw,domains,dns.lookup,options.allowPort===true);
        const response=await new Promise<Response>((done,reject)=>{
            const request=https.request(target,{method:options.method??'GET',headers,signal:options.signal,timeout:30000,agent:pinnedProxyAgent(target,addresses[0]!,options.signal),lookup:(_host,value,callback)=>callback(null,value.all?addresses:addresses[0].address,addresses[0].family)},response=>{
                const headers=new Headers();for(let i=0;i<response.rawHeaders.length;i+=2)headers.append(response.rawHeaders[i],response.rawHeaders[i+1]);
                const status=response.statusCode??502;
                done(new Response(options.method==='HEAD'||[204,205,304].includes(status)?null:Readable.toWeb(response) as ReadableStream<Uint8Array>,{status,headers}));
            });request.on('timeout',()=>request.destroy(new HostError('TIMEOUT','media request timed out')));request.on('error',error=>reject(options.signal?.aborted?runnerError(toAbortError(options.signal)):error));request.end();
        });
        if(!REDIRECT_STATUSES.has(response.status)||options.followRedirects===false){Object.defineProperty(response,'url',{value:target.href});return response;}
        const location=response.headers.get('location');await response.body?.cancel();if(!location||hop>=5)throw new HostError('BLOCKED','invalid media redirect');
        const next=new URL(location,target);const redirected=redirectRequest({url:target.href,method:options.method??'GET',headers,followRedirects:true},target,next,response.status);headers=withDefaultUserAgent(redirected.headers);raw=next.href;
    }
}
export class NetworkBroker {
    constructor(private readonly manifest: PluginManifest, private readonly fetchImpl: typeof fetch = fetch, private readonly lookup: typeof dns.lookup = dns.lookup, private readonly jar?: CookieJar, private readonly persistCookies?: () => Promise<void>,private readonly maxResponseBytes=32*1024*1024) { }
    async request(req: NetworkRequest): Promise<NetworkResponse> { if (!['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'].includes(req.method ?? 'GET'))
        throw new HostError('BLOCKED', 'HTTP method is blocked'); req = { ...req, headers: withDefaultUserAgent(Object.fromEntries(Object.entries(req.headers ?? {}).filter(([key, value]) => !['host', 'connection', 'proxy-authorization', 'proxy-connection', 'transfer-encoding', 'upgrade', 'te', 'trailer', 'content-length'].includes(key.toLowerCase()) && !/[\r\n]/.test(key + value)))) }; let raw = req.url; let siteCredentials = true; for (let hops = 0;; hops++) {
        if (req.signal?.aborted)
            throw runnerError(toAbortError(req.signal));
        const { target, addresses } = await validateNetworkUrl(raw, undefined, this.lookup);
        const sourceTarget=hostAllowed(target.hostname,this.manifest.domains);
        if(!sourceTarget)req={...req,headers:Object.fromEntries(Object.entries(req.headers??{}).filter(([key])=>!['cookie','proxy-authorization'].includes(key.toLowerCase())))};
        if (siteCredentials && sourceTarget && this.jar && !Object.keys(req.headers ?? {}).some(k => k.toLowerCase() === 'cookie')) {
            const cookie = await this.jar.getCookieString(target.href);
            if (cookie)
                req = { ...req, headers: { ...req.headers, cookie } };
        }
        const response = this.fetchImpl === fetch ? await pinnedRequest(target, req, addresses,this.maxResponseBytes).catch(error=>{throw req.signal?.aborted?runnerError(toAbortError(req.signal)):error;}) : await this.fetchImpl(target, { method: req.method ?? 'GET', headers: req.headers, body: req.bodyBase64?Buffer.from(req.bodyBase64,'base64'):req.body, redirect: 'manual', signal: req.signal }).catch(error=>{throw req.signal?.aborted?runnerError(toAbortError(req.signal)):error;});
        if (sourceTarget && this.jar) {
            for (const cookie of response.headers.getSetCookie())
                await this.jar.setCookie(cookie, target.href, { ignoreError: true });
            await this.persistCookies?.();
        }
        if (REDIRECT_STATUSES.has(response.status) && req.followRedirects !== false) {
            const location = response.headers.get('location');
            await response.body?.cancel();
            if (!location || hops >= 5)
                throw new HostError('BLOCKED', 'invalid redirect');
            const next = new URL(location, target);
            req=redirectRequest(req,target,next,response.status);
            if (next.origin !== target.origin) siteCredentials = false;
            raw = next.href;
            continue;
        }
        const bytes = new Uint8Array(await response.arrayBuffer());
        if (bytes.length > this.maxResponseBytes)
            throw new HostError('PARSE', 'upstream response exceeds limit');
        const headers=Object.fromEntries(response.headers.entries());const cookies=response.headers.getSetCookie();if(cookies.length)headers['set-cookie']=cookies.join('\n');
        return { status: response.status, headers, body: req.responseType === 'base64' ? Buffer.from(bytes).toString('base64') : new TextDecoder().decode(bytes), url: target.href };
    } }
}
export class IsolatedStore {
    private readonly cookies = new Map<string, Map<string, string>>();
    private readonly state = new Map<string, Map<string, unknown>>();
    private map<T>(source: string, root: Map<string, Map<string, T>>) { let m = root.get(source); if (!m) {
        m = new Map();
        root.set(source, m);
    } return m; }
    getCookie(source: string, key: string) { return this.map(source, this.cookies).get(key); }
    setCookie(source: string, key: string, value: string) { this.map(source, this.cookies).set(key, value); }
    getState(source: string, key: string) { return this.map(source, this.state).get(key); }
    setState(source: string, key: string, value: unknown) { this.map(source, this.state).set(key, value); }
    clear(source: string) { this.cookies.delete(source); this.state.delete(source); }
    clearAll() { this.cookies.clear(); this.state.clear(); }
}
interface Pending {
    resolve: (v: unknown) => void;
    reject: (e: unknown) => void;
    timer: ReturnType<typeof setTimeout>;
    signal?: AbortSignal;
    cancel: () => void;
}
export class SourceRunnerClient {
    private child?: ChildProcessWithoutNullStreams;
    private buffer = '';
    private pending = new Map<string, Pending>();
    private network = new Map<string, AbortController>();
    private closed = false;
    get isClosed() { return this.closed; }
    constructor(private readonly runnerPath: string, private readonly sourcePath: string, private readonly broker?: Pick<NetworkBroker,'request'>, private readonly runtimePath?: string, private readonly native?: (operation: string, args: Record<string, unknown>) => Promise<unknown>) { }
    start() { if (this.closed)throw new HostError('CANCELLED','runner is closed');if(this.child)
        return; this.buffer = ''; const runtime = this.runtimePath ?? resolve(dirname(this.runnerPath), '../../../assets/runtime/park_runtime.js'); const contractDirectory = dirname(fileURLToPath(import.meta.resolve('@hentai-park/source-contract'))); const adapterDirectory=dirname(createRequire(this.runnerPath).resolve('@hentai-park/source-runtime')); const readPaths = new Set([dirname(this.runnerPath), contractDirectory, adapterDirectory,join(dirname(adapterDirectory),'node_modules'), this.sourcePath, runtime, join(dirname(runtime), 'polyfills.js'), join(resolve(dirname(runtime), '../..'), 'node_modules'), join(resolve(dirname(runtime), '../..'), 'apps/source-runner/node_modules')]); for (const base of [dirname(this.runnerPath), contractDirectory, adapterDirectory]) {
        let directory = base;
        for (let depth = 0; depth < 5; depth++) {
            readPaths.add(join(directory, 'package.json'));
            const parent = dirname(directory);
            if (parent === directory)
                break;
            directory = parent;
        }
    } const child = spawn(process.execPath, ['--permission', ...[...readPaths].map(value => '--allow-fs-read=' + resolve(value)), '--max-old-space-size=128', this.runnerPath, '--plugin', this.sourcePath, '--runtime', runtime], { stdio: ['pipe', 'pipe', 'pipe'], env: { NODE_ENV: 'production' }, windowsHide: true }); this.child = child; child.stdin.on('error', () => this.pipeFailed(child)); child.stdout.setEncoding('utf8'); child.stdout.on('data', d => this.onData(d)); child.stderr.on('data', () => { }); child.on('exit', () => { if (this.child === child)
        this.failAll(new HostError('NETWORK', 'source-runner exited')); }); child.on('error', () => this.failAll(new HostError('NETWORK', 'source-runner failed'))); }
    private pipeFailed(child: ChildProcessWithoutNullStreams) {
        if (this.closed || this.child !== child) return;
        this.failAll(new HostError('NETWORK', 'source-runner input failed'));
        child.kill();
    }
    private write(child: ChildProcessWithoutNullStreams, message: string) {
        if (this.closed || this.child !== child) return;
        if (child.killed || child.stdin.destroyed || !child.stdin.writable) { this.pipeFailed(child); return; }
        try { child.stdin.write(message, error => { if (error) this.pipeFailed(child); }); }
        catch { this.pipeFailed(child); }
    }
    private finish(id: string, error?: unknown, result?: unknown) { const p = this.pending.get(id); if (!p)
        return; this.pending.delete(id); clearTimeout(p.timer); p.signal?.removeEventListener('abort', p.cancel); error ? p.reject(error) : p.resolve(result); }
    private onData(data: string) { if (this.closed) return; this.buffer += data; if (this.buffer.length > 16 * 1024 * 1024) {
        this.failAll(new HostError('PARSE', 'runner message exceeds limit'));
        this.child?.kill();
        return;
    } let i; while ((i = this.buffer.indexOf('\n')) >= 0) {
        const line = this.buffer.slice(0, i);
        this.buffer = this.buffer.slice(i + 1);
        try {
            const msg = JSON.parse(line) as {
                id: string;
                result?: unknown;
                error?: PluginError;
                type?: string;
                request?: NetworkRequest;
                operation?: string;
                args?: Record<string, unknown>;
            };
            if ((msg.id === '__startup__' || msg.id === '__runtime__') && msg.error) {
                this.failAll(runnerError(msg.error));
                this.child?.kill();
                continue;
            }
            if (msg.type === 'native' && this.child && this.native) {
                const child = this.child;
                void this.native(msg.operation ?? '', msg.args ?? {}).then(result => { if (!this.closed)
                    this.write(child, JSON.stringify({ id: msg.id, result }) + '\n'); }, error => { if (!this.closed)
                    this.write(child, JSON.stringify({ id: msg.id, error: toPluginError(error) }) + '\n'); });
                continue;
            }
            if (msg.type === 'network' && this.child && this.broker && msg.request) {
                const child = this.child;
                const controller = new AbortController();
                this.network.set(msg.id, controller);
                void this.broker.request({ ...msg.request, signal: controller.signal }).then(result => { if (!this.closed)
                    this.write(child, JSON.stringify({ id: msg.id, result }) + '\n'); }, error => { if (!this.closed)
                    this.write(child, JSON.stringify({ id: msg.id, error: toPluginError(error) }) + '\n'); }).finally(() => this.network.delete(msg.id));
                continue;
            }
            this.finish(msg.id, msg.error ? runnerError(msg.error) : undefined, msg.result);
        }
        catch {
            this.failAll(new HostError('PARSE', 'invalid runner response'));
            this.child?.kill();
        }
    } }
    private failAll(error: Error) { this.closed = true; for (const id of this.pending.keys())
        this.finish(id, error); for (const c of this.network.values())
        c.abort(error); this.network.clear(); }
    request(method: string, params: unknown, timeoutMs = 30000, signal?: AbortSignal): Promise<unknown> { if (signal?.aborted)
        return Promise.reject(runnerError(toAbortError(signal)));if(this.closed)return Promise.reject(runnerError(toPluginError({code:'CANCELLED'}))); this.start(); const child = this.child; if (!child || this.closed)
        return Promise.reject(new HostError('NETWORK', 'runner unavailable')); const id = randomUUID(); return new Promise((done, reject) => { const stop = (code: 'TIMEOUT' | 'CANCELLED') => { if (!this.pending.has(id)) return; const interruption=runnerError(toPluginError({code,details:{reason:code==='TIMEOUT'?'RECEIVE_TIMEOUT':'CANCELLED'}}));this.finish(id,interruption);for(const controller of this.network.values())controller.abort(interruption); this.failAll(new HostError('CANCELLED', 'runner recycled after interrupted operation')); child.kill(); }; const cancel = () => stop(toAbortError(signal!).code==='TIMEOUT'?'TIMEOUT':'CANCELLED'); const budgetMs = Math.min(Math.max(Number.isFinite(timeoutMs)?timeoutMs:30000, 1), 300000); const deadlineAt = Date.now() + Math.ceil(budgetMs); const timer = setTimeout(() => stop('TIMEOUT'), budgetMs); this.pending.set(id, { resolve: done, reject, timer, signal, cancel }); signal?.addEventListener('abort', cancel, { once: true }); this.write(child, JSON.stringify({ id, method, params, deadlineAt }) + '\n'); }); }
    async close() { this.failAll(new HostError('CANCELLED', 'runner closed')); const child = this.child; this.child = undefined; if (child && child.exitCode === null && child.signalCode === null)
        await new Promise<void>(done => { child.once('exit', () => done()); child.kill(); setTimeout(done, 2000).unref(); }); }
}
export interface SourceHostOptions {
    index?: PluginIndex;
    journal?: InstallationJournal;
    registry?: SourceRegistry;
    idleMs?: number;
    maxSources?: number;
    runtimePath?: string;
    pluginDirectory?: string;
    stateDirectory?: string;
    onError?: (error: unknown) => void;
    browserExecutor?:SourceBrowserExecutor;
}
interface PrivateSourceState {jar:CookieJar;data:unknown;settings:Record<string,unknown>;settingsVersion:number;settingsUpdatedAt:string}
interface RunnerEntry {client:SourceRunnerClient;lastUsed:number;active:number;}
export class SourceHost {
    private readonly challengeTargets=new Map<string,string>();
    verificationTarget(source:string){return this.challengeTargets.get(source)??this.registry.get(source)?.manifest.homepage;}
    private idleTimer?: ReturnType<typeof setInterval>;
    private mutation: Promise<unknown> = Promise.resolve();
    private browserExecutor?:SourceBrowserExecutor;
    setBrowserExecutor(executor:SourceBrowserExecutor){this.browserExecutor=executor;}
    private async syncBrowserCookies(manifest:PluginManifest,state:PrivateSourceState,cookies:SourceBrowserCookie[],initial:SourceBrowserCookie[]=[],signal?:AbortSignal){
        if(signal?.aborted)throw runnerError(toAbortError(signal));
        const jar=CookieJar.deserializeSync(state.jar.serializeSync()!),key=(c:SourceBrowserCookie)=>[c.domain.replace(/^\./,''),c.path??'/',c.name].join('\n');
        const final=new Map(cookies.map(c=>[key(c),c]));
        for(const c of initial)if(!final.has(key(c))){const domain=c.domain.replace(/^\./,''),current=jar.serializeSync()!.cookies.find(v=>v.domain===domain&&v.path===(c.path??'/')&&v.key===c.name);if(current?.value===c.value)jar.setCookieSync(new Cookie({key:c.name,value:'',domain,path:c.path??'/',maxAge:0}),'https://'+domain+'/');}
        for(const c of cookies){const domain=c.domain.replace(/^\./,'');if(!hostAllowed(domain,manifest.domains))throw new HostError('BLOCKED','browser cookie is outside source');jar.setCookieSync(new Cookie({key:c.name,value:c.value,domain,hostOnly:!c.domain.startsWith('.'),path:c.path??'/',secure:true,httpOnly:c.httpOnly,sameSite:c.sameSite?.toLowerCase(),expires:c.expires>0?new Date(c.expires*1000):'Infinity'}),'https://'+domain+'/');}
        if(signal?.aborted)throw runnerError(toAbortError(signal));const previous=state.jar;state.jar=jar;try{await this.persistState(manifest.key);}catch(error){if(state.jar===jar)state.jar=previous;throw error;}
    }
    async completeVerification(source:string,cookies:SourceBrowserCookie[],initial:SourceBrowserCookie[],signal:AbortSignal){const record=this.registry.get(source);if(!record?.enabled)throw new HostError('CONFIG','source disabled');const state=await this.privateState(source);await this.syncBrowserCookies(record.manifest,state,cookies,initial,signal);}
    private sourceBroker(manifest:PluginManifest,state:PrivateSourceState):Pick<NetworkBroker,'request'> {
        return {request:async request=>{
            if(request.mode!=='browser'){
                const result=await new NetworkBroker(manifest,fetch,dns.lookup,state.jar,()=>this.persistState(manifest.key)).request(request);
                const code=responseChallenge({...result,body:request.responseType==='base64'?Buffer.from(result.body,'base64').toString('utf8'):result.body},true);
                if(code){if(code==='CLOUDFLARE'&&hostAllowed(new URL(request.url).hostname,manifest.domains))this.challengeTargets.set(manifest.key,request.url);throw Object.assign(new HostError(code,'Site verification required'),{details:{reason:code==='BLOCKED'?'FIREWALL_BLOCKED':'SITE_CHALLENGE',stage:'native'}});}
                return result;
            }
            if(!this.browserExecutor)throw new HostError('UNSUPPORTED','browser request executor is unavailable');
            await validateNetworkUrl(request.url,manifest.domains);
            const initial=await this.browserCookies(manifest.key);
            const result=await this.browserExecutor.request({source:manifest.key,manifest,request,cookies:initial}).catch(error=>{if(!request.signal?.aborted&&['CLOUDFLARE','VERIFICATION_REQUIRED'].includes(toPluginError(error).code))this.challengeTargets.set(manifest.key,request.url);throw error;});
            if(request.signal?.aborted)throw runnerError(toAbortError(request.signal));
            if(result.cookies)await this.syncBrowserCookies(manifest,state,result.cookies,initial,request.signal);
            return {status:result.status,headers:result.headers,body:result.body,url:result.url};
        }};
    }
    private mediaResources = new Map<string, {
        source: string;
        url: string;
        headers: Record<string, string>;
        session:boolean;
        image:boolean;
        expiresAt: number;
    }>();
    private mediaContexts = new WeakMap<object,string>();
    private rememberMedia(source: string, manifest: PluginManifest, value: unknown, depth = 0, session=false, image=false) { if(depth===0){for(const [key,resource]of this.mediaResources)if(resource.expiresAt<=Date.now())this.mediaResources.delete(key);while(this.mediaResources.size>4096)this.mediaResources.delete(this.mediaResources.keys().next().value!);} if (depth > 8 || !value || typeof value !== 'object')
        return; if (Array.isArray(value)) {
        for (const item of value)
            this.rememberMedia(source, manifest, item, depth + 1,session,image);
        return;
    } const row = value as Record<string, unknown>; if (typeof row.url === 'string') {
        try {
            const target = new URL(row.url);
            if (target.protocol === 'https:' && !target.username && !target.password && !target.port) {
                const imageNode=image||row.type==='image';const headers=mediaRequestHeaders(manifest,row.headers??{},imageNode);
                const context=randomUUID();this.mediaResources.set(context, { source, url: target.href, headers,image:imageNode, session:session||manifest.media?.scope==='session', expiresAt: Date.now() + 300000 });this.mediaContexts.set(row,context);
            }
        }
        catch(error) { if(error&&typeof error==='object'&&'code'in error)throw error; }
    } for (const [key, item] of Object.entries(row))
        if (key !== 'headers')
            this.rememberMedia(source, manifest, item, depth + 1,session,image); }
    private privateStates = new Map<string, PrivateSourceState>();
    private readonly accountTransactions=new Set<string>();
    private readonly stagedPrivateWrites=new Set<string>();
    private loadingStates = new Map<string,Promise<PrivateSourceState>>();
    private async privateState(source: string):Promise<PrivateSourceState> { const current=this.privateStates.get(source);if(current)return current;const loading=this.loadingStates.get(source);if(loading)return loading;const action=(async()=>{let state:PrivateSourceState = { jar: new CookieJar(), data: {}, settings: {},settingsVersion:0,settingsUpdatedAt:this.registry.get(source)?.updatedAt??new Date(0).toISOString() };
        if (this.options.stateDirectory) {
            try {
                const saved = JSON.parse(await readFile(resolve(this.options.stateDirectory, source + '.json'), 'utf8'));
                state = { jar: CookieJar.deserializeSync(saved.cookies), data: saved.data ?? {}, settings: saved.settings ?? {},settingsVersion:Number.isSafeInteger(saved.settingsVersion)&&saved.settingsVersion>=0?saved.settingsVersion:0,settingsUpdatedAt:typeof saved.settingsUpdatedAt==='string'&&Number.isFinite(Date.parse(saved.settingsUpdatedAt))?saved.settingsUpdatedAt:(await stat(resolve(this.options.stateDirectory,source+'.json'))).mtime.toISOString() };
            }
            catch (error) {
                if ((error as NodeJS.ErrnoException).code !== 'ENOENT')
                    throw error;
            }
        }
        this.privateStates.set(source, state);return state;
    })();this.loadingStates.set(source,action);try{return await action;}finally{this.loadingStates.delete(source);} }
    private stateWriting: Promise<unknown> = Promise.resolve();
    private async persistState(source: string) { if (this.stagedPrivateWrites.has(source)||!this.options.stateDirectory)
        return; const state = await this.privateState(source); const data = JSON.stringify({ cookies: state.jar.serializeSync(), data: state.data, settings: state.settings,settingsVersion:state.settingsVersion,settingsUpdatedAt:state.settingsUpdatedAt }); const destination = resolve(this.options.stateDirectory, source + '.json'); const action = this.stateWriting.then(() => atomicWrite(destination, data)); this.stateWriting = action.catch(() => { }); await action; }
    private async native(source: string, manifest: PluginManifest, operation: string, args: Record<string, unknown>) { const state = await this.privateState(source); if (operation === 'persist') {
        state.data = args.data;
        await this.persistState(source);
        return null;
    } if (operation === 'cookies') {
        const values = args.args as Record<string, unknown>;
        const url = new URL(String(values.url));
        await validateNetworkUrl(url.href, manifest.domains);
        if (args.op === 'clear') {
            for (const cookie of await state.jar.getCookies(url.href))
                await state.jar.setCookie(`${cookie.key}=; Path=${cookie.path}; Max-Age=0`, url.href);
            await this.persistState(source);
        }
        if (args.op === 'set') {
            const cookies = values.cookies as Record<string, unknown>;
            for (const [key, value] of Object.entries(cookies ?? {})) {
                if (!/^[A-Za-z0-9_.-]{1,128}$/.test(key) || typeof value !== 'string' || /[\r\n;]/.test(value))
                    throw new HostError('CONFIG', 'invalid cookie');
                await state.jar.setCookie(`${key}=${value}; Secure; Path=/`, url.href);
            }
            await this.persistState(source);
        }
        return Object.fromEntries((await state.jar.getCookies(url.href)).map(cookie => [cookie.key, cookie.value]));
    } if(operation==='chatRequest')return chatRequest(manifest,args as unknown as NetworkRequest);throw new HostError('UNSUPPORTED', 'unsupported private state operation'); }
    private readonly clients = new Map<string,RunnerEntry>();
    private readonly sourceExecutions = new Map<string,{running:boolean;controller:AbortController;jobs:Array<{run:()=>Promise<void>;cancel:()=>void}>}>();
    private withSourceExecution<T>(source:string,options:{signal?:AbortSignal;timeoutMs?:number},action:(signal:AbortSignal)=>Promise<T>):Promise<T>{
        if(options.signal?.aborted)return Promise.reject(runnerError(toAbortError(options.signal)));
        let queue=this.sourceExecutions.get(source);
        if(!queue){queue={running:false,controller:new AbortController(),jobs:[]};this.sourceExecutions.set(source,queue);}
        const current=queue;
        if(current.jobs.length+Number(current.running)>=8)return Promise.reject(new HostError('RATE_LIMITED','operation limit'));
        const budget=Math.min(Math.max(Number.isFinite(options.timeoutMs)?options.timeoutMs!:30000,1),300000);
        const signal=AbortSignal.any([current.controller.signal,AbortSignal.timeout(Math.ceil(budget)),...(options.signal?[options.signal]:[])]);
        const drain=()=>{
            if(current.running)return;
            const job=current.jobs.shift();
            if(!job){if(this.sourceExecutions.get(source)===current)this.sourceExecutions.delete(source);return;}
            current.running=true;
            void job.run().finally(()=>{current.running=false;drain();});
        };
        return new Promise<T>((resolve,reject)=>{
            const job={run:async()=>{signal.removeEventListener('abort',job.cancel);try{if(signal.aborted)throw runnerError(toAbortError(signal));resolve(await action(signal));}catch(error){reject(error);}},cancel:()=>{const index=current.jobs.indexOf(job);if(index<0)return;current.jobs.splice(index,1);signal.removeEventListener('abort',job.cancel);reject(runnerError(toAbortError(signal)));drain();}};
            current.jobs.push(job);signal.addEventListener('abort',job.cancel,{once:true});drain();
        });
    }
    private poolMutation:Promise<unknown>=Promise.resolve();
    private withPool<T>(action:()=>Promise<T>|T):Promise<T>{const pending=this.poolMutation.then(action);this.poolMutation=pending.then(()=>undefined,()=>undefined);return pending;}
    private async closeEntry(source:string,entry:RunnerEntry){if(this.clients.get(source)===entry)this.clients.delete(source);await entry.client.close();}
    private async reserveClient(manifest:PluginManifest,pluginPath:string,state:PrivateSourceState):Promise<RunnerEntry>{return this.withPool(async()=>{
        if(this.accountTransactions.has(manifest.key))throw new HostError('RATE_LIMITED','account update is in progress');
        const registered=this.registry.get(manifest.key);
        if(registered&&!registered.enabled)throw new HostError('CONFIG','source disabled');
        if(registered&&(resolve(pluginPath)!==resolve(registered.packagePath)||registered.manifest.version!==manifest.version))throw new HostError('INVALID_MANIFEST','installed plugin identity mismatch');
        let entry=this.clients.get(manifest.key);
        if(entry?.client.isClosed){await this.closeEntry(manifest.key,entry);entry=undefined;}
        if(!entry){
            if(registered?.sha256&&sha256(await readFile(pluginPath))!==registered.sha256)throw new HostError('INVALID_MANIFEST','installed plugin integrity mismatch');
            if(this.clients.size>=this.maxSources){
                const candidate=[...this.clients.entries()].filter(([,value])=>value.active===0).sort((a,b)=>a[1].lastUsed-b[1].lastUsed)[0];
                if(!candidate)throw new HostError('RATE_LIMITED','all source runners are active');
                await this.closeEntry(candidate[0],candidate[1]);
            }
            entry={client:new SourceRunnerClient(this.runnerPath,pluginPath,this.sourceBroker(manifest,state),this.options.runtimePath,(operation,args)=>this.native(manifest.key,manifest,operation,args)),lastUsed:Date.now(),active:0};
            this.clients.set(manifest.key,entry);
        }
        if(entry.active>=8)throw new HostError('RATE_LIMITED','operation limit');
        entry.active++;entry.lastUsed=Date.now();return entry;
    });}
    readonly stores = new IsolatedStore();
    readonly index: PluginIndex;
    readonly journal: InstallationJournal;
    readonly registry: SourceRegistry;
    private readonly idleMs: number;
    private readonly maxSources: number;
    constructor(private readonly runnerPath: string, private readonly appVersion = '0.1.0', private readonly options: SourceHostOptions = {}) { this.browserExecutor=options.browserExecutor; this.index = options.index ?? new PluginIndex(); this.journal = options.journal ?? new InstallationJournal(); this.registry = options.registry ?? new SourceRegistry();if(options.pluginDirectory){this.registry.bindPluginDirectory(options.pluginDirectory);this.journal.bindPluginDirectory(options.pluginDirectory);} this.idleMs = options.idleMs ?? 300000; this.maxSources = options.maxSources ?? 6; this.idleTimer=setInterval(()=>{void this.reapIdle().catch(error=>{if(this.options.onError)this.options.onError(error);else console.error('[source-host] SOURCE_REAP_FAILED');});},30000);this.idleTimer.unref(); }
    loadManifest(input: unknown): PluginManifest { validateManifest(input); const m = input as PluginManifest; if (!compatible(this.appVersion, m.minAppVersion))
        throw new HostError('INCOMPATIBLE', 'plugin requires newer app'); return m; }
    async inspect(pluginPath: string, options: {
        signal?: AbortSignal;
        timeoutMs?: number;
    } = {}) { const client = new SourceRunnerClient(this.runnerPath, pluginPath, undefined, this.options.runtimePath); try {
        const manifest = await client.request('manifest', undefined, options.timeoutMs ?? 30000, options.signal);
        return this.loadManifest(manifest);
    }
    finally {
        await client.close();
    } }
    async invoke(manifest: PluginManifest, pluginPath: string, method: string, params?: unknown, options: {
        timeoutMs?: number;
        signal?: AbortSignal;
    } = {}) { return this.withSourceExecution(manifest.key,options,async signal=>{const m = this.loadManifest(manifest); const state = await this.privateState(m.key); if(signal.aborted)throw runnerError(toAbortError(signal));const registered = this.registry.get(m.key); if (registered && !registered.enabled)
        throw new HostError('CONFIG', 'source disabled'); if (!operationCapability(method) || m.capabilities?.[operationCapability(method)!] !== true)
        throw new HostError('UNSUPPORTED', 'capability is not declared'); const entry=await this.reserveClient(m,pluginPath,state);try {
        const result = await entry.client.request('invoke', { method, params, expectedManifest: m, stateSnapshot: { data: state.data, settings: state.settings } }, options.timeoutMs, signal);
        if (['chapter', 'videos', 'voiceResource', 'resolveImage','album'].includes(method))
            this.rememberMedia(m.key, m, result,0,['album','subscription.posts'].includes(method),['chapter','resolveImage'].includes(method));
        return result;
    }
    catch (error) {
        throw toPluginError(error);
    }
    finally {
        entry.active--;
        entry.lastUsed = Date.now();
    } }); }
    async install(source: string, packagePath: string, manifestInput: unknown, expectedSha256?: string,origin?:SourceRegistryRecord['origin']) { const action = this.mutation.then(() => this.installNow(source, packagePath, manifestInput, expectedSha256,origin)); this.mutation = action.catch(() => { }); return action; }
    private async installNow(source: string, packagePath: string, manifestInput: unknown, expectedSha256?: string,origin?:SourceRegistryRecord['origin']) { const m = this.loadManifest(manifestInput); if (m.key !== source)
        throw new HostError('INVALID_MANIFEST', 'source key mismatch'); if (!expectedSha256 || !/^[a-f0-9]{64}$/.test(expectedSha256))
        throw new HostError('INVALID_MANIFEST', 'trusted checksum required'); const bytes = await readFile(packagePath); const digest = sha256(bytes); if (digest !== expectedSha256)
        throw new HostError('INVALID_MANIFEST', 'checksum mismatch'); const directory = this.options.pluginDirectory ?? this.registry.pluginDirectory ?? this.journal.pluginDirectory ?? resolve(dirname(packagePath), '.installed');this.registry.bindPluginDirectory(directory);this.journal.bindPluginDirectory(directory); await mkdir(directory, { recursive: true }); packagePath = resolve(directory, digest + '.js'); await immutableArtifact(packagePath,bytes,digest);const actual=await this.inspect(packagePath);if(!isDeepStrictEqual(actual,m))throw new HostError('INVALID_MANIFEST','installed script manifest does not match trusted manifest'); const previous = this.registry.get(source); const record = this.journal.begin(source, m.version, previous?.version, { sha256: digest, permissions: permissionChanges(previous?.manifest, m), previous, next: { source, version: m.version, packagePath: resolve(packagePath), manifest: m, sha256: digest, enabled: true, updatedAt: new Date().toISOString() } }); await this.journal.flush(); try {
        await this.dispose(source);
        if(origin)record.next!.origin=structuredClone(origin);
        this.registry.upsert(record.next!);
        await this.registry.flush();
        this.index.add({ source, version: m.version, minAppVersion: m.minAppVersion, sha256: digest, manifest: m, packagePath: resolve(packagePath) });
        this.journal.commit(record);
        await this.journal.flush();
        return record;
    }
    catch (error) {
        this.registry.rollbackWrite(source, previous);
        await this.registry.flush();
        this.journal.rollback(record);
        await this.journal.flush();
        throw error;
    } }
    async rollback(source: string) { const previous = this.registry.previous(source); if (!previous)
        throw new HostError('CONFIG', 'no previous plugin version'); return this.install(source, previous.packagePath, previous.manifest, sha256(await readFile(previous.packagePath)),previous.origin); }
    async setEnabled(source: string, enabled: boolean) { if (!enabled)
        await this.dispose(source); const result = this.registry.setEnabled(source, enabled); await this.registry.flush(); return result; }
    mediaContext(source:string,row:unknown):string|undefined{const registered=this.registry.get(source);if(!registered?.enabled)throw new HostError('CONFIG','source disabled');const key=row&&typeof row==='object'?this.mediaContexts.get(row):undefined;if(!key)return undefined;const resource=this.mediaResources.get(key);if(!resource||resource.source!==source)throw new HostError('BLOCKED','media context is not an authorized invocation result');if(resource.expiresAt<=Date.now()){this.mediaResources.delete(key);throw new HostError('TIMEOUT','media context expired');}return key;}
    async fetchResource(source: string, url: string, options: {
        signal?: AbortSignal;
        range?: string;
        method?: 'GET' | 'HEAD';
        mediaContext?:string;
        image?:boolean;
    } = {}): Promise<Response> { const r = this.registry.get(source); if (!r?.enabled)
        throw new HostError('CONFIG', 'source disabled'); const target = new URL(url); const resource = options.mediaContext ? this.mediaResources.get(options.mediaContext) : undefined;if(options.mediaContext&&(!resource||resource.source!==source))throw new HostError('BLOCKED','media context is invalid');if(resource&&resource.expiresAt<=Date.now()){this.mediaResources.delete(options.mediaContext!);throw new HostError('TIMEOUT','media context expired');} const sameOrigin=resource&&new URL(resource.url).origin===target.origin;
    const domains=!options.image?[...r.manifest.domains,...(r.manifest.media?.domains??[]),...(r.manifest.imageNetwork?.domains??[])]:undefined;
    const supplied=options.image?r.manifest.imageHeaders??{}:resource?.image?{}:resource?.headers??{};
    const headers=mediaRequestHeaders(r.manifest,supplied,options.image===true);
    for(const key of Object.keys(headers))if(key.startsWith('x-')&&!sameOrigin)delete headers[key];
    if(options.range)headers.range=options.range;
    const browser=async()=>{try{if(!this.browserExecutor)throw new HostError('UNSUPPORTED','browser resource executor is unavailable');await validateNetworkUrl(url,resource?.session||options.image?undefined:domains);const imageOrigin=r.manifest.imageNetwork?.origin?new URL(r.manifest.imageNetwork.origin):undefined;const imageSession=options.image===true&&r.manifest.imageNetwork?.mode==='browser'&&imageOrigin?.origin===target.origin&&hostAllowed(imageOrigin.hostname,r.manifest.domains);const result=await this.browserExecutor.request({source,manifest:r.manifest,request:{url,method:options.method??'GET',headers,responseType:'base64',signal:options.signal,mode:'browser'},cookies:imageSession?await this.browserCookies(source):[],resource:true,image:options.image===true,session:resource?.session===true});if(imageSession&&result.cookies)await this.syncBrowserCookies(r.manifest,await this.privateState(source),result.cookies);await validateNetworkUrl(result.url,resource?.session||options.image?undefined:domains);const bytes=Buffer.from(result.body,'base64');if(options.image&&result.status>=200&&result.status<300&&options.method!=='HEAD')decodeImage(bytes,r.manifest.imageDecrypt);const response=new Response(options.method==='HEAD'||[204,205,304].includes(result.status)?null:bytes,{status:result.status,headers:result.headers});Object.defineProperty(response,'url',{value:result.url});return response;}catch(error){throw runnerError(options.signal?.aborted?toAbortError(options.signal):toPluginError(error));}};
    // Resource transports deliberately never read or write the source-account jar.
    if(!options.image&&r.manifest.media?.mode==='browser')return browser();
    const fallback=options.image&&r.manifest.imageNetwork?.mode==='browser'&&this.browserExecutor!==undefined;
    try{const response=await fetchPinnedResource(url,resource?.session?undefined:domains,{signal:options.signal,method:options.method,headers,allowPort:options.image===true});if(!options.image)return response;if(!response.ok){if(!fallback)return response;await response.body?.cancel();return browser();}if(options.method==='HEAD')return response;const reader=response.body?.getReader(),parts:Uint8Array[]=[];let size=0;try{if(reader)for(;;){const next=await reader.read();if(next.done)break;size+=next.value.length;if(size>20*1024*1024)throw new HostError('PARSE','image response limit');parts.push(next.value);}}finally{await reader?.cancel().catch(()=>{});}const bytes=Buffer.concat(parts);decodeImage(bytes,r.manifest.imageDecrypt);const result=new Response(bytes,{status:response.status,headers:response.headers});Object.defineProperty(result,'url',{value:response.url});return result;}catch(error){if(!fallback||options.signal?.aborted||['BLOCKED','CONFIG'].includes(toPluginError(error).code))throw runnerError(options.signal?.aborted?toAbortError(options.signal):toPluginError(error));return browser();} }
    async setCookies(source: string, cookies: Array<{
        name: string;
        value: string;
        domain: string;
        path?: string;
        expires?: number;
        secure?: boolean;
        httpOnly?: boolean;
        sameSite?:'Strict'|'Lax'|'None';
    }>) { const r = this.registry.get(source); if (!r)
        throw new HostError('CONFIG', 'source not registered'); const state = await this.privateState(source); for (const c of cookies) {
        const domain = c.domain.replace(/^\./, '');
        if (!hostAllowed(domain, r.manifest.domains))
            throw new HostError('BLOCKED', 'cookie domain outside source');
        const cookie = new Cookie({ key: c.name, value: c.value, domain,hostOnly:!c.domain.startsWith('.'), path: c.path ?? '/', secure: true, httpOnly: c.httpOnly,sameSite:c.sameSite?.toLowerCase(), expires: c.expires && c.expires > 0 ? new Date(c.expires * 1000) : 'Infinity' });
        await state.jar.setCookie(cookie, 'https://' + domain + '/');
    } await this.persistState(source); await this.dispose(source); }
    async browserCookies(source:string){const record=this.registry.get(source);if(!record?.enabled)throw new HostError('CONFIG','source disabled');const state=await this.privateState(source);const cookies:Array<{name:string;value:string;domain:string;path:string;expires:number;httpOnly:boolean;secure:boolean;sameSite?:'Strict'|'Lax'|'None'}>=[];for(const value of state.jar.serializeSync()!.cookies){const cookie=Cookie.fromJSON(value);if(!cookie?.domain||!hostAllowed(cookie.domain,record.manifest.domains))continue;const expires=cookie.expiryTime()??Infinity;if(expires<=Date.now())continue;cookies.push({name:cookie.key,value:cookie.value,domain:cookie.hostOnly?cookie.domain:'.'+cookie.domain,path:cookie.path??'/',expires:Number.isFinite(expires)?expires/1000:-1,httpOnly:cookie.httpOnly,secure:true,...(cookie.sameSite?{sameSite:({strict:'Strict',lax:'Lax',none:'None'} as const)[cookie.sameSite as 'strict'|'lax'|'none']}: {})});}return cookies;}
    async finishReverseSearch(source:string,page:{url:string;html:string},options:{signal?:AbortSignal;timeoutMs?:number}={}){
        return this.withSourceExecution(source,options,async signal=>{
        const record=this.registry.get(source);if(!record?.enabled||record.manifest.capabilities?.reverseSearch!==true)throw new HostError('UNSUPPORTED','reverse search is unavailable');
        if(!page||typeof page.url!=='string'||page.url.length>8192||typeof page.html!=='string'||!page.html.length||Buffer.byteLength(page.html,'utf8')>4*1024*1024)throw new HostError('CONFIG','invalid reverse search page');
        await validateNetworkUrl(page.url,record.manifest.domains);const state=await this.privateState(source);if(signal.aborted)throw runnerError(toAbortError(signal));const entry=await this.reserveClient(record.manifest,record.packagePath,state);
        try{return await entry.client.request('reverseSearchResult',{page,expectedManifest:record.manifest,stateSnapshot:{data:state.data,settings:state.settings}},options.timeoutMs,signal);}catch(error){throw toPluginError(error);}finally{entry.active--;entry.lastUsed=Date.now();}
        });
    }
    async filterOptions(source:string,input:Record<string,unknown>,options:{signal?:AbortSignal;timeoutMs?:number}={}){
        return this.withSourceExecution(source,options,async signal=>{
        const record=this.registry.get(source);if(!record?.enabled)throw new HostError('CONFIG','source disabled');
        if(!input||typeof input!=='object'||Array.isArray(input)||Object.keys(input).some(key=>!['scope','feed','filter','keyword','values'].includes(key))||!['feed','search'].includes(String(input.scope))||typeof input.filter!=='string')throw new HostError('CONFIG','invalid filter query');
        const manifest=record.manifest;
        const feed=input.scope==='feed'&&typeof input.feed==='string'?manifest.feeds?.find(value=>value.key===input.feed):undefined;
        if(input.scope==='feed'?(!feed||manifest.capabilities?.feed!==true||input.keyword!==undefined):input.feed!==undefined||!(manifest.capabilities?.search||manifest.capabilities?.metadataSearch))throw new HostError('UNSUPPORTED','filter scope is not declared');
        const declarations=input.scope==='feed'?feed?.options:manifest.searchFilters;const setting=declarations?.find(value=>value.key===input.filter&&value.dynamic===true);
        if(!setting)throw new HostError('UNSUPPORTED','dynamic filter is not declared');
        if(input.keyword!==undefined&&(typeof input.keyword!=='string'||input.keyword.length>512||/[\u0000-\u001f\u007f]/.test(input.keyword))||setting.keywordDependent&&(!input.keyword||typeof input.keyword!=='string'))throw new HostError('CONFIG','invalid filter keyword');
        const values=input.values??{};if(!values||typeof values!=='object'||Array.isArray(values))throw new HostError('CONFIG','invalid filter dependencies');const dependencies=setting.dependsOn??[];
        if(Object.keys(values).some(key=>!dependencies.includes(key))||dependencies.some(key=>!Object.hasOwn(values,key)))throw new HostError('CONFIG','filter dependencies mismatch');
        for(const value of Object.values(values)){if(typeof value==='string'?(!value||value.length>512||/[\u0000-\u001f\u007f]/.test(value)):typeof value==='number'?!Number.isFinite(value):typeof value!=='boolean')throw new HostError('CONFIG','invalid filter dependency');}
        const state=await this.privateState(source);if(signal.aborted)throw runnerError(toAbortError(signal));const entry=await this.reserveClient(manifest,record.packagePath,state);
        try{return await entry.client.request('filterOptions',{query:{scope:input.scope,filter:setting.key,values,...(feed?{feed:feed.key}:{}),...(input.keyword===undefined?{}:{keyword:input.keyword})},expectedManifest:manifest,stateSnapshot:{data:state.data,settings:state.settings}},options.timeoutMs,signal);}catch(error){throw toPluginError(error);}finally{entry.active--;entry.lastUsed=Date.now();}
        });
    }
    async getSettings(source:string):Promise<{settings:Record<string,unknown>;version:number;updatedAt:string}> {
        if(this.accountTransactions.has(source))throw new HostError('RATE_LIMITED','account update is in progress');
        const record=this.registry.get(source);if(!record)throw new HostError('CONFIG','source not registered');const state=await this.privateState(source);
        const defaults=Object.fromEntries((record.manifest.settings??[]).filter(setting=>setting.default!==undefined).map(setting=>[setting.key,setting.default]));
        return {settings:structuredClone({...defaults,...state.settings}),version:state.settingsVersion,updatedAt:state.settingsUpdatedAt};
    }
    async updateSettings(source:string,settings:Record<string,unknown>,version:number):Promise<{settings:Record<string,unknown>;version:number;updatedAt:string}> {
        const action=this.mutation.then(async()=>{
            const record=this.registry.get(source);if(!record)throw new HostError('CONFIG','source not registered');validateSourceSettings(record.manifest,settings);
            const current=await this.privateState(source);if(!Number.isSafeInteger(version)||version!==current.settingsVersion)throw new HostError('CONFIG','source settings version conflict',{reason:'SETTINGS_CONFLICT'});
            await this.dispose(source);const next={...current,settings:structuredClone(settings),settingsVersion:current.settingsVersion+1,settingsUpdatedAt:isDeepStrictEqual(current.settings,settings)?current.settingsUpdatedAt:new Date().toISOString()};this.privateStates.set(source,next);
            try{await this.persistState(source);}catch(error){this.privateStates.set(source,current);throw error;}
            return this.getSettings(source);
        });this.mutation=action.catch(()=>{});return action;
    }
    async account(source: string, operation: 'login' | 'status' | 'logout' | 'enableManaged', values: Record<string, string> = {}, options: {
        signal?: AbortSignal;
        timeoutMs?: number;
        internalTransaction?:boolean;
    } = {}) { if(this.accountTransactions.has(source)&&!options.internalTransaction)throw new HostError('RATE_LIMITED','account update is in progress');const r = this.registry.get(source); if (!r?.enabled || !r.manifest.account)
        throw new HostError('UNSUPPORTED', 'source account is unavailable'); if(operation==='enableManaged'&&r.manifest.account.managedAccount!==true)throw new HostError('UNSUPPORTED','managed account is not declared'); const state = await this.privateState(source); if(operation!=='status')await this.dispose(source); let client = new SourceRunnerClient(this.runnerPath, r.packagePath, this.sourceBroker(r.manifest,state), this.options.runtimePath, (op, args) => this.native(source, r.manifest, op, args)); try {
        const methods=await client.request('accountMethods',{},options.timeoutMs,options.signal) as Record<string,boolean>;
        if(!methods[operation]&&operation==='login'&&r.manifest.account.type==='cookies'&&r.manifest.account.cookieUrl){
            const cookieUrl=(await validateNetworkUrl(r.manifest.account.cookieUrl,r.manifest.domains)).target;
            if(!Object.keys(values).length||Object.keys(values).length>100)throw new HostError('CONFIG','invalid cookie account');
            const next=CookieJar.deserializeSync(state.jar.serializeSync()!);
            for(const [key,value]of Object.entries(values)){if(!/^[!#$%&'*+.^_`|~0-9A-Za-z-]{1,128}$/.test(key)||typeof value!=='string'||value.length>16384||/[\u0000-\u0020\u007f;,]/.test(value))throw new HostError('CONFIG','invalid cookie account');await next.setCookie(new Cookie({key,value,domain:cookieUrl.hostname,path:'/',secure:true}),cookieUrl.href);}
            const previous=state.jar;state.jar=next;try{await this.persistState(source);}catch(error){state.jar=previous;throw error;}await client.close();client=new SourceRunnerClient(this.runnerPath,r.packagePath,this.sourceBroker(r.manifest,state),this.options.runtimePath,(op,args)=>this.native(source,r.manifest,op,args));
        }
        let result:Record<string,unknown>;
        if(!methods[operation]){
            if(operation==='enableManaged'||operation==='login'&&!(r.manifest.account.type==='cookies'&&r.manifest.account.cookieUrl))throw new HostError('UNSUPPORTED','account method is not implemented');
            if(operation!=='logout'&&methods.status)result=await client.request('account',{operation:'status',values:{},stateSnapshot:{data:state.data,settings:state.settings},expectedManifest:r.manifest},options.timeoutMs,options.signal) as Record<string,unknown>;
            else {const cookies=state.jar.serializeSync()!.cookies;const required=r.manifest.account.requiredCookies??[];result={loggedIn:false,configured:required.length?required.every(name=>cookies.some(cookie=>cookie.key===name&&cookie.value)):cookies.length>0,verified:false};}
        }else result = await client.request('account', { operation, values, stateSnapshot: { data: state.data, settings: state.settings }, expectedManifest: r.manifest }, options.timeoutMs, options.signal) as Record<string, unknown>;
        if (operation === 'logout') {
            state.jar.removeAllCookiesSync();
            const accountData=state.data as Record<string,unknown>;
            state.data = r.manifest.account.managedAccount&&accountData.managedAccount?{managedAccount:{...(accountData.managedAccount as Record<string,unknown>),token:null}}:{};
            if(r.manifest.account.managedAccount&&state.settings.managedAccount===true){state.settings={...state.settings,managedAccount:false};state.settingsVersion++;state.settingsUpdatedAt=new Date().toISOString();}
            await this.persistState(source);
        }
        return { loggedIn: result?.loggedIn === true, verified:result?.verified!==false,...(typeof result?.configured==='boolean'?{configured:operation==='logout'?false:result.configured}:{}),...(typeof result?.name === 'string' ? { name: result.name.slice(0, 256) } : {}) };
    }
    finally {
        await client.close();
    } }
    async loginBrowser(source:string,cookies:SourceBrowserCookie[],values:Record<string,string>,options:{signal?:AbortSignal;timeoutMs?:number}={}){
        const action=this.mutation.then(async()=>{const record=this.registry.get(source);if(!record?.enabled||!record.manifest.account)throw new HostError('UNSUPPORTED','account is unavailable');await this.dispose(source);await this.stateWriting;const previous=await this.privateState(source);const staged={jar:new CookieJar(),data:structuredClone(previous.data),settings:structuredClone(previous.settings),settingsVersion:previous.settingsVersion,settingsUpdatedAt:previous.settingsUpdatedAt};this.accountTransactions.add(source);this.stagedPrivateWrites.add(source);this.privateStates.set(source,staged);
            try{await this.setCookies(source,cookies);const result=await this.account(source,'login',values,{...options,internalTransaction:true});if(!result.loggedIn&&!(result.verified===false&&result.configured===true))throw new HostError('LOGIN_REQUIRED','browser account was not verified');this.stagedPrivateWrites.delete(source);await this.persistState(source);return result;}
            catch(error){this.privateStates.set(source,previous);await this.dispose(source);throw error;}
            finally{this.stagedPrivateWrites.delete(source);this.accountTransactions.delete(source);}
        });this.mutation=action.catch(()=>{});return action;
    }
    async exportPrivateState(source: string, options: {
        includeAccounts?: boolean;
        includeCookies?: boolean;
    } = {}) {if(this.accountTransactions.has(source))throw new HostError('RATE_LIMITED','account update is in progress'); if (!this.registry.get(source))
        throw new HostError('CONFIG', 'source not registered'); const state = await this.privateState(source); return { source, ...(options.includeAccounts ? { data: structuredClone(state.data), settings: structuredClone(state.settings) } : {}), ...(options.includeCookies ? { cookies: state.jar.serializeSync() } : {}) }; }
    async subscriptionContext(source:string):Promise<string> {
        if(this.accountTransactions.has(source))throw new HostError('RATE_LIMITED','account update is in progress');
        const record=this.registry.get(source);if(!record)throw new HostError('CONFIG','source not registered');
        const state=await this.privateState(source);
        const transient=new Set(['expires','expiresat','expiry','retryat','failures','ratelimited','updatedat']);
        const canonical=(value:unknown):unknown=>Array.isArray(value)?value.map(canonical):value&&typeof value==='object'?Object.fromEntries(Object.entries(value).filter(([key])=>!transient.has(key.toLowerCase().replace(/_/g,''))).sort(([a],[b])=>a.localeCompare(b)).map(([key,item])=>[key,canonical(item)])):value;
        const stableKeys=new Set(['id','uid','userid','accountid','email','username','handle']);
        const principal=(value:unknown,depth=0):Record<string,unknown>=>{const out:Record<string,unknown>={};if(!value||typeof value!=='object'||Array.isArray(value)||depth>3)return out;for(const [key,item]of Object.entries(value).sort(([a],[b])=>a.localeCompare(b))){const normalized=key.toLowerCase().replace(/_/g,'');if(stableKeys.has(normalized)&&(typeof item==='string'&&item.length>0||typeof item==='number'&&Number.isFinite(item)))out[key]=item;else if(['user','account','profile','identity'].includes(normalized)){const nested=principal(item,depth+1);if(Object.keys(nested).length)out[key]=nested;}}return out;};
        const data=state.data&&typeof state.data==='object'&&!Array.isArray(state.data)?state.data as Record<string,unknown>:{};
        const credentials=Object.entries(data).filter(([key])=>/credential|account|user|session|token|auth/i.test(key)).sort(([a],[b])=>a.localeCompare(b));
        const identities=Object.fromEntries(credentials.map(([key,value])=>[key,principal(value)]).filter(([,value])=>Object.keys(value).length));
        const reliable=Object.keys(identities).length>0;
        const cookies=reliable?[]:state.jar.serializeSync()!.cookies.filter(cookie=>(record.manifest.account?.requiredCookies?.length?record.manifest.account.requiredCookies.includes(String(cookie.key)):Boolean(record.manifest.account)||credentials.length>0)).map(cookie=>[cookie.domain,cookie.path,cookie.key,cookie.value]).sort((a,b)=>JSON.stringify(a).localeCompare(JSON.stringify(b)));
        const authorization=reliable?identities:Object.fromEntries(credentials.map(([key,value])=>[key,canonical(value)]));
        const settings=Object.fromEntries(Object.entries(state.settings).sort(([a],[b])=>a.localeCompare(b)));
        return sha256(JSON.stringify([record.manifest.version,settings,authorization,cookies]));
    }
    async preparePrivateState(source:string,payload:unknown,options:PrivateStateOptions={}) { const record=this.registry.get(source);if(!record)throw new HostError('CONFIG','source not registered');validatePrivateState(record.manifest,payload,options); }
    async importPrivateState(source: string, payload: unknown, options: {
        includeAccounts?: boolean;
        includeCookies?: boolean;
    } = {}) { const record = this.registry.get(source); if (!record)
        throw new HostError('CONFIG', 'source not registered'); validatePrivateState(record.manifest,payload,options); const value = payload as Record<string, unknown>; const current = await this.privateState(source); const changed=options.includeAccounts&&value.settings!==undefined&&!isDeepStrictEqual(current.settings,value.settings); const next = { jar: CookieJar.deserializeSync(current.jar.serializeSync()!), data: structuredClone(current.data), settings: structuredClone(current.settings),settingsVersion:current.settingsVersion+(changed?1:0),settingsUpdatedAt:changed?new Date().toISOString():current.settingsUpdatedAt }; if (options.includeAccounts) {
        if (value.data !== undefined)
            next.data = structuredClone(value.data);
        if (value.settings !== undefined) {
            if (!value.settings || typeof value.settings !== 'object' || Array.isArray(value.settings))
                throw new HostError('CONFIG', 'invalid private settings');
            next.settings = structuredClone(value.settings) as Record<string, unknown>;
        }
    } if (options.includeCookies && value.cookies !== undefined) {
        next.jar = CookieJar.deserializeSync(value.cookies as Parameters<typeof CookieJar.deserializeSync>[0]);
        for (const cookie of next.jar.serializeSync()!.cookies) {
            if (typeof cookie.domain !== 'string' || !hostAllowed(cookie.domain.replace(/^\./, ''), record.manifest.domains))
                throw new HostError('BLOCKED', 'private backup contains out of source cookies');
        }
    } await this.dispose(source); this.privateStates.set(source, next); try {
        await this.persistState(source);
    }
    catch (error) {
        this.privateStates.set(source, current);
        throw error;
    } return { source, restored: true }; }
    async recover() { const pending = this.journal.pending();for(const record of pending)if(record.from!==undefined&&!record.previous)throw new HostError('CONFIG','prepared installation is missing its previous registry snapshot'); for (const r of pending) {
        this.registry.rollbackWrite(r.source, r.previous);
        await this.registry.flush();
        this.journal.rollback(r);
    } await this.journal.flush(); return pending; }
    async reapIdle(now = Date.now()) {return this.withPool(async()=>{const removed:string[]=[];for(const [source,entry]of this.clients)if(!entry.active&&now-entry.lastUsed>=this.idleMs){await this.closeEntry(source,entry);removed.push(source);}return removed;});}
    async dispose(source?: string) {for(const [key,queue] of this.sourceExecutions)if(source===undefined||key===source)queue.controller.abort(new HostError('CANCELLED','source disposed'));await this.browserExecutor?.dispose?.(source);return this.withPool(async()=>{if(source){for(const [key,resource]of this.mediaResources)if(resource.source===source)this.mediaResources.delete(key);const entry=this.clients.get(source);if(entry)await this.closeEntry(source,entry);this.stores.clear(source);return;}clearInterval(this.idleTimer);this.idleTimer=undefined;await Promise.all([...this.clients.entries()].map(([key,entry])=>this.closeEntry(key,entry)));this.mediaResources.clear();this.stores.clearAll();});}
}
function compatible(actual: string, required: string) { const a = actual.split(/[.-]/).slice(0, 3).map(Number), r = required.split(/[.-]/).slice(0, 3).map(Number); for (let i = 0; i < 3; i++) {
    if (a[i] > r[i])
        return true;
    if (a[i] < r[i])
        return false;
} return true; }
export const isCompatibleVersion = compatible;
export function sha256(value: Uint8Array | string) { return createHash('sha256').update(value).digest('hex'); }
export interface PluginIndexEntry {
    source: string;
    version: string;
    minAppVersion: string;
    sha256: string;
    manifest: PluginManifest;
    packagePath?: string;
}
export class PluginIndex {
    private readonly entries = new Map<string, PluginIndexEntry>();
    add(e: PluginIndexEntry) { validateManifest(e.manifest); if (e.source !== e.manifest.key || e.version !== e.manifest.version || e.minAppVersion !== e.manifest.minAppVersion || !/^[a-f0-9]{64}$/.test(e.sha256))
        throw new HostError('INVALID_MANIFEST', 'invalid index'); this.entries.set(e.source, e); return e; }
    get(source: string) { return this.entries.get(source); }
    list() { return [...this.entries.values()]; }
    remove(source: string) { this.entries.delete(source); }
    async verify(source: string, bytes: Uint8Array | string) { const e = this.entries.get(source); if (!e || sha256(bytes) !== e.sha256)
        throw new HostError('INVALID_MANIFEST', 'checksum mismatch'); return true; }
}
export function permissionChanges(previous: PluginManifest | undefined, next: PluginManifest) { const permissions = (m?: PluginManifest) => m ? [...m.domains.map(v => `network:${v}`), ...(m.media?.domains ?? []).map(v => `media:${v}`), ...(m.imageNetwork?.domains ?? []).map(v => `image:${v}`), ...(m.navigationDomains ?? []).map(v => `navigation:${v}`), ...(m.frameDomains ?? []).map(v => `frame:${v}`), ...(m.account?.loginDomains ?? []).map(v => `login:${v}`), ...(m.chat?.domains ?? []).map(v => `chat:${v}`),...(m.media?.referrerDomains??[]).map(v=>`media-referrer:${v}`),...(m.media?.requestHeaders?Object.entries(m.media.requestHeaders).map(([name,rule])=>`media-header:${name}:${rule.scope}`):[]),...(m.network?.mode?[`network-mode:${m.network.mode}`]:[]),...(m.media?[`media-mode:${m.media.mode}`,`media-scope:${m.media.scope??'domains'}`]:[]),...(m.imageNetwork?[`image-mode:${m.imageNetwork.mode}`]:[]),...(m.account?[`account:${m.account.type}`,...(m.account.managedAccount?['account:managed']:[]),...(m.account.localStorageKeys??[]).map(v=>`account-storage:${v}`)]:[]), ...Object.keys(m.capabilities ?? {}).filter(k => m.capabilities?.[k as keyof typeof m.capabilities] === true)] : []; const before = new Set(permissions(previous)), after = new Set(permissions(next)); return { added: [...after].filter(v => !before.has(v)).sort(), removed: [...before].filter(v => !after.has(v)).sort() }; }
export interface SourceRegistryRecord {
    source: string;
    version: string;
    packagePath: string;
    manifest: PluginManifest;
    enabled: boolean;
    updatedAt: string;
    crashed?: boolean;
    sha256?: string;
    origin?: {url:string;repository?:string;official?:boolean};
}
export interface InstallRecord {
    id: string;
    source: string;
    from?: string;
    to: string;
    status: 'prepared' | 'committed' | 'rolled_back';
    sha256?: string;
    permissions?: {
        added: string[];
        removed: string[];
    };
    previous?: SourceRegistryRecord;
    next?: SourceRegistryRecord;
    at: string;
}
async function atomicWrite(path: string, data: string|Uint8Array) { await mkdir(dirname(path), { recursive: true }); const temporary = `${path}.${randomUUID()}.tmp`; try{await writeFile(temporary, data, { encoding: 'utf8', flush: true }); await rename(temporary, path);}catch(error){await unlink(temporary).catch(()=>{});throw error;} }
async function immutableArtifact(path:string,bytes:Uint8Array,digest:string){let existing:Buffer|undefined;try{existing=await readFile(path);}catch(error){if((error as NodeJS.ErrnoException).code!=='ENOENT')throw error;}if(existing){if(sha256(existing)!==digest)throw new HostError('INVALID_MANIFEST','existing immutable plugin artifact checksum mismatch');return;}await atomicWrite(path,bytes);}
function artifactReference(record:SourceRegistryRecord):{file:string;digest:string}{
    if(!record||typeof record.packagePath!=='string')throw new HostError('CONFIG','installed plugin reference is invalid');
    const file=record.packagePath.replace(/\\/g,'/').split('/').at(-1)!;
    if(!/^[a-f0-9]{64}\.js$/.test(file))throw new HostError('INVALID_MANIFEST','installed plugin reference must be an immutable SHA-256 filename');
    const digest=file.slice(0,-3);if(record.sha256!==undefined&&record.sha256!==digest)throw new HostError('INVALID_MANIFEST','installed plugin reference checksum mismatch');
    return {file,digest};
}
function storedRecord(record:SourceRegistryRecord):SourceRegistryRecord{const {file,digest}=artifactReference(record);return {...record,packagePath:file,sha256:digest};}
async function relocatedRecord(value:unknown,directory:string|undefined):Promise<SourceRegistryRecord>{
    if(!value||typeof value!=='object'||Array.isArray(value))throw new HostError('CONFIG','invalid source registry record');
    const record=value as SourceRegistryRecord;validateManifest(record.manifest);
    if(record.source!==record.manifest.key||record.version!==record.manifest.version||typeof record.enabled!=='boolean')throw new HostError('INVALID_MANIFEST','source registry identity is invalid');
    const {file,digest}=artifactReference(record);if(!directory)throw new HostError('CONFIG','plugin directory must be configured before loading state');
    const packagePath=resolve(directory,file);let bytes:Buffer;try{bytes=await readFile(packagePath);}catch{throw new HostError('CONFIG','installed plugin artifact is missing or unreadable: '+file,{source:record.source,reason:'MISSING_ARTIFACT'});}
    if(sha256(bytes)!==digest)throw new HostError('INVALID_MANIFEST','installed plugin artifact checksum mismatch: '+file,{source:record.source,reason:'CHECKSUM_MISMATCH'});
    return {...record,packagePath,sha256:digest};
}
async function readStateFile(filePath:string):Promise<unknown|undefined>{let raw:string;try{raw=await readFile(filePath,'utf8');}catch(error){if((error as NodeJS.ErrnoException).code==='ENOENT')return undefined;throw error;}return JSON.parse(raw);}
class DurableState {
    protected dirty=false;protected loaded=false;protected artifactDirectory?:string;
    private writing:Promise<unknown>=Promise.resolve();
    constructor(protected readonly filePath?:string,pluginDirectory?:string){this.artifactDirectory=pluginDirectory?resolve(pluginDirectory):filePath?resolve(dirname(filePath),'plugins'):undefined;}
    get pluginDirectory(){return this.artifactDirectory;}
    bindPluginDirectory(directory:string){const target=resolve(directory);if(this.loaded&&this.artifactDirectory&&this.artifactDirectory!==target)throw new HostError('CONFIG','plugin directory must be configured before loading state');this.artifactDirectory=target;}
    protected snapshot():unknown{return null;}
    async flush(){if(!this.filePath)return;const path=this.filePath,data=JSON.stringify(this.snapshot());const action=this.writing.then(()=>atomicWrite(path,data));this.writing=action.catch(()=>{});await action;this.dirty=false;}
}
export class InstallationJournal extends DurableState {
    readonly records:InstallRecord[]=[];
    protected override snapshot(){return this.records.map(record=>({...record,...(record.previous?{previous:storedRecord(record.previous)}:{}),...(record.next?{next:storedRecord(record.next)}:{})}));}
    async load(){if(!this.filePath)return;const data=await readStateFile(this.filePath);if(data===undefined){this.loaded=true;return;}if(!Array.isArray(data))throw new HostError('CONFIG','invalid installation journal');const records:InstallRecord[]=[];
        for(const value of data){if(!value||typeof value!=='object'||!['prepared','committed','rolled_back'].includes(value.status)||typeof value.id!=='string'||typeof value.source!=='string')throw new HostError('CONFIG','invalid installation journal');
            const previous=value.previous===undefined?undefined:await relocatedRecord(value.previous,this.artifactDirectory);const next=value.next===undefined?undefined:await relocatedRecord(value.next,this.artifactDirectory);
            if(previous&&(previous.source!==value.source||value.from!==previous.version)||next&&(next.source!==value.source||value.to!==next.version||value.sha256!==undefined&&value.sha256!==next.sha256))throw new HostError('INVALID_MANIFEST','installation journal identity mismatch');
            records.push({...value,...(previous?{previous}:{}),...(next?{next}:{})});
        }
        this.records.splice(0,this.records.length,...records);this.loaded=true;if(JSON.stringify(data)!==JSON.stringify(this.snapshot()))await this.flush();
    }
    begin(source:string,to:string,from?:string,metadata:Pick<InstallRecord,'sha256'|'permissions'|'previous'|'next'>={}){const record:InstallRecord={id:randomUUID(),source,from,to,status:'prepared',at:new Date().toISOString(),...metadata};this.records.push(record);this.dirty=true;return record;}
    commit(record:InstallRecord){record.status='committed';this.dirty=true;}
    rollback(record:InstallRecord){record.status='rolled_back';this.dirty=true;}
    pending(){return this.records.filter(record=>record.status==='prepared');}
    recover(){const pending=this.pending();for(const record of pending)this.rollback(record);return pending;}
}
export class SourceRegistry extends DurableState {
    private readonly records=new Map<string,SourceRegistryRecord>();private readonly history=new Map<string,SourceRegistryRecord[]>();
    protected override snapshot(){return {records:[...this.records.values()].map(storedRecord),history:[...this.history.entries()].map(([source,records])=>[source,records.map(storedRecord)])};}
    async load(){if(!this.filePath)return;const data=await readStateFile(this.filePath);if(data===undefined){this.loaded=true;return;}if(!data||typeof data!=='object'||!('records'in data)||!Array.isArray(data.records))throw new HostError('CONFIG','invalid source registry');const records=new Map<string,SourceRegistryRecord>(),history=new Map<string,SourceRegistryRecord[]>();
        for(const value of data.records){const record=await relocatedRecord(value,this.artifactDirectory);if(records.has(record.source))throw new HostError('CONFIG','duplicate source registry identity');records.set(record.source,record);}
        const prior=(data as {history?:unknown}).history;if(prior!==undefined&&!Array.isArray(prior))throw new HostError('CONFIG','invalid source registry history');
        if(Array.isArray(prior))for(const item of prior){if(!Array.isArray(item)||item.length!==2||typeof item[0]!=='string'||!Array.isArray(item[1])||history.has(item[0]))throw new HostError('CONFIG','invalid source registry history');const values:SourceRegistryRecord[]=[];for(const value of item[1]){const record=await relocatedRecord(value,this.artifactDirectory);if(record.source!==item[0])throw new HostError('INVALID_MANIFEST','source registry history identity mismatch');values.push(record);}history.set(item[0],values);}
        this.records.clear();this.history.clear();for(const [source,record]of records)this.records.set(source,record);for(const [source,values]of history)this.history.set(source,values);this.loaded=true;
        if(JSON.stringify(data)!==JSON.stringify(this.snapshot()))await this.flush();
    }
    upsert(record:SourceRegistryRecord){validateManifest(record.manifest);const current=this.records.get(record.source);if(current){const history=this.history.get(record.source)??[];history.push(structuredClone(current));this.history.set(record.source,history);}const next={...record,updatedAt:new Date().toISOString(),crashed:false};this.records.set(record.source,next);this.dirty=true;return next;}
    restore(source:string,record?:SourceRegistryRecord){if(record)this.records.set(source,structuredClone(record));else this.records.delete(source);this.dirty=true;}
    rollbackWrite(source:string,previous?:SourceRegistryRecord){const history=this.history.get(source);if(previous&&history?.length&&isDeepStrictEqual(history.at(-1),previous))history.pop();this.restore(source,previous);}
    get(source:string){return this.records.get(source);}
    previous(source:string){return this.history.get(source)?.at(-1);}
    restorePrevious(source:string){const previous=this.history.get(source)?.pop();if(!previous)throw new HostError('CONFIG','no previous plugin version');this.restore(source,previous);return previous;}
    list(){return [...this.records.values()];}
    setEnabled(source:string,enabled:boolean){const record=this.records.get(source);if(!record)throw new HostError('CONFIG','source not registered');record.enabled=enabled;record.updatedAt=new Date().toISOString();this.dirty=true;return record;}
    markCrashed(source:string){const record=this.records.get(source);if(record){record.crashed=true;this.dirty=true;}}
}

export interface ResourceLease {
    source: string;
    id: string;
    expiresAt: number;
    release: () => void;
}
export class ResourceLimiter {
    private readonly active = new Map<string, Set<string>>();
    constructor(private readonly maxPerSource = 8, private readonly ttlMs = 300000) { }
    acquire(source: string, now = Date.now()): ResourceLease { const set = this.active.get(source) ?? new Set<string>(); if (set.size >= this.maxPerSource)
        throw new HostError('RATE_LIMITED', 'resource limit'); const id = randomUUID(); set.add(id); this.active.set(source, set); let released = false; return { source, id, expiresAt: now + this.ttlMs, release: () => { if (released)
            return; released = true; set.delete(id); if (!set.size)
            this.active.delete(source); } }; }
    count(source: string) { return this.active.get(source)?.size ?? 0; }
    clear(source?: string) { if (source)
        this.active.delete(source);
    else
        this.active.clear(); }
}
