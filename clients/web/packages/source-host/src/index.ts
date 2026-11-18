import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import dns from 'node:dns/promises';
import { mkdir, readFile, rename, rm, stat, unlink, writeFile } from 'node:fs/promises';
import https from 'node:https';
import { createRequire } from 'node:module';
import net from 'node:net';
import { dirname, isAbsolute, join, relative, resolve } from 'node:path';
import { Readable } from 'node:stream';
import { fileURLToPath } from 'node:url';
import { isDeepStrictEqual, TextDecoder as HostTextDecoder } from 'node:util';
import { brotliDecompressSync, gunzipSync, inflateSync } from 'node:zlib';
import { Cookie, CookieJar } from 'tough-cookie';
import {
  operationCapability,
  toAbortError,
  toPluginError,
  validateManifest,
  type PluginError,
  type PluginManifest,
} from '@hentai-park/source-contract';
import { chatRequest, connectChat, validateChatUrl, type ChatConnection, type ChatEvent } from './chat-network.js';
import { challengePage, firewallPage, responseChallenge } from './challenge.js';
import { unwrapHlsResource } from './hls-envelope.js';
import { decodeImage } from './image.js';
import { validatePrivateState, validateSourceSettings, type PrivateStateOptions } from './private-state.js';
import { configureHttpProxy, connectPinnedTunnel, hasHttpProxy, pinnedProxyAgent } from './proxy.js';
import { requestPinnedStream } from './stream.js';
import { hostAllowed, mediaRequestHeaders, redirectRequest, REDIRECT_STATUSES } from './transport-policy.js';
import { configureSourceUserAgent, getSourceUserAgent, withDefaultUserAgent } from './user-agent.js';

export {
  challengePage,
  chatRequest,
  configureHttpProxy,
  configureSourceUserAgent,
  connectChat,
  connectPinnedTunnel,
  decodeImage,
  firewallPage,
  getSourceUserAgent,
  hasHttpProxy,
  hostAllowed,
  mediaRequestHeaders,
  redirectRequest,
  REDIRECT_STATUSES,
  requestPinnedStream,
  responseChallenge,
  unwrapHlsResource,
  validateChatUrl,
  validatePrivateState,
  validateSourceSettings,
  withDefaultUserAgent,
};
export type { ChatConnection, ChatEvent, PrivateStateOptions };

export class HostError extends Error {
  readonly code: string;
  readonly details?: Record<string, unknown>;
  readonly status?: number;
  constructor(code: string, message: string, details?: Record<string, unknown>) {
    super(message);
    this.name = 'HostError';
    this.code = code;
    this.details = details;
    if (typeof details?.status === 'number') this.status = details.status;
  }
}

export interface NetworkRequest {
  url: string;
  method?: string;
  headers?: Record<string, string>;
  body?: string;
  bodyBase64?: string;
  responseType?: 'text' | 'base64';
  followRedirects?: boolean;
  mode?: 'auto' | 'browser' | 'native';
  origin?: string;
  readOnly?: boolean;
  connectAddress?: string;
  timeout?: number;
  invocation?: string;
  signal?: AbortSignal;
}

export interface NetworkResponse {
  status: number;
  headers: Record<string, string>;
  body: string;
  url: string;
}

export interface SourceBrowserCookie {
  name: string;
  value: string;
  domain: string;
  path: string;
  expires: number;
  httpOnly: boolean;
  secure: boolean;
  sameSite?: 'Strict' | 'Lax' | 'None';
}

export interface SourceBrowserInput {
  source: string;
  manifest: PluginManifest;
  request: NetworkRequest;
  cookies: SourceBrowserCookie[];
  resource?: boolean;
  image?: boolean;
  session?: boolean;
}

export interface SourceBrowserExecutor {
  request(input: SourceBrowserInput): Promise<NetworkResponse & { cookies?: SourceBrowserCookie[] }>;
  dispose?(source?: string): Promise<void>;
}

function runnerError(error: PluginError): HostError {
  return Object.assign(
    new HostError(error.code, error.message, error.details as Record<string, unknown> | undefined),
    error,
  );
}

function ipv6Bits(input: string): bigint {
  let value = input.toLowerCase();
  if (value.includes('.')) {
    const at = value.lastIndexOf(':');
    const p = value.slice(at + 1).split('.').map(Number);
    value =
      value.slice(0, at + 1) +
      (p[0]! * 256 + p[1]!).toString(16) +
      ':' +
      (p[2]! * 256 + p[3]!).toString(16);
  }
  const halves = value.split('::');
  const left = halves[0] ? halves[0].split(':') : [];
  const right = halves[1] ? halves[1].split(':') : [];
  const parts =
    halves.length === 1 ? left : [...left, ...Array(8 - left.length - right.length).fill('0'), ...right];
  return parts.reduce((bits, part) => (bits << 16n) | BigInt(parseInt(part, 16)), 0n);
}

const BENCHMARK_IPV6_PREFIX = ipv6Bits('2001:2::');
const prefixContains = (value: bigint, prefix: bigint, length: number) =>
  value >> BigInt(128 - length) === prefix >> BigInt(128 - length);

let allowFakeIpRanges = false;
/**
 * Align with lib/engine/public_media_address.dart: Clash / Mihomo / sing-box / Surge map domains
 * into RFC 2544 (198.18.0.0/15) and RFC 5180 (2001:2::/48) in TUN fake-ip mode while TLS still
 * verifies the original hostname and certificate chain.
 */
export function configureFakeIpAllowed(allowed: boolean) {
  allowFakeIpRanges = allowed;
}

export function isFakeIpAllowed(): boolean {
  return allowFakeIpRanges;
}

export function isPrivateAddress(address: string, permitFakeIp = allowFakeIpRanges): boolean {
  const v = address.toLowerCase().replace(/^\[|\]$/g, '');
  const family = net.isIP(v);
  if (family === 4) {
    const [a, b, c, d] = v.split('.').map(Number) as [number, number, number, number];
    if (permitFakeIp && a === 198 && (b === 18 || b === 19)) return false;
    return (
      a === 0 ||
      a === 10 ||
      a === 127 ||
      (a === 100 && b >= 64 && b <= 127) ||
      (a === 169 && b === 254) ||
      (a === 172 && b >= 16 && b <= 31) ||
      (a === 192 && (b === 168 || (b === 0 && c === 0 && d !== 9 && d !== 10) || (b === 0 && c === 2) || (b === 88 && c === 99))) ||
      (a === 198 && (b === 18 || b === 19 || (b === 51 && c === 100))) ||
      (a === 203 && b === 0 && c === 113) ||
      a >= 224
    );
  }
  if (family !== 6 || v.includes('%')) return true;
  const bits = ipv6Bits(v);
  const embedded = () => {
    const value = Number(bits & 0xffffffffn);
    return isPrivateAddress(
      [(value >>> 24) & 255, (value >>> 16) & 255, (value >>> 8) & 255, value & 255].join('.'),
      permitFakeIp,
    );
  };
  if (bits >> 32n === 0xffffn || bits >> 32n === 0x64ff9b0000000000000000n) return embedded();
  if (permitFakeIp && prefixContains(bits, BENCHMARK_IPV6_PREFIX, 48)) return false;
  if (
    v === '::' ||
    v === '::1' ||
    /^f[cd]/.test(v) ||
    /^fe[89ab]/.test(v) ||
    v.startsWith('2001:db8:') ||
    v.startsWith('3fff:')
  ) {
    return true;
  }
  return false;
}

export async function validateNetworkUrl(
  raw: string,
  domains: string[] | undefined,
  lookup: typeof dns.lookup = dns.lookup,
  allowPort = false,
  connectAddress?: string,
) {
  let target: URL;
  try {
    target = new URL(raw);
  } catch {
    throw new HostError('BLOCKED', 'invalid URL');
  }
  if (
    target.protocol !== 'https:' ||
    target.username ||
    target.password ||
    target.hostname === 'localhost' ||
    target.hostname.endsWith('.local') ||
    (!allowPort && Boolean(target.port)) ||
    (domains !== undefined && !hostAllowed(target.hostname, domains))
  ) {
    throw new HostError('BLOCKED', 'network target is outside declared domains');
  }

  // Explicit direct route IP (e.g., pica.js route probing): validate public IP while preserving original target hostname for TLS SNI
  if (connectAddress !== undefined) {
    const ipFamily = net.isIP(connectAddress);
    if (!ipFamily || isPrivateAddress(connectAddress, false)) {
      throw new HostError('BLOCKED', 'connectAddress must be a public IP literal');
    }
    return { target, addresses: [{ address: connectAddress, family: ipFamily }] };
  }

  // When an instance HTTP/HTTPS CONNECT proxy is configured and default lookup is used,
  // avoid poisoned local DNS resolution and let the proxy resolve the public hostname remotely.
  const ipLiteralFamily = net.isIP(target.hostname.replace(/^\[|\]$/g, ''));
  if (ipLiteralFamily) {
    if (isPrivateAddress(target.hostname)) throw new HostError('BLOCKED', 'private address is blocked');
    return { target, addresses: [{ address: target.hostname.replace(/^\[|\]$/g, ''), family: ipLiteralFamily }] };
  }
  if (hasHttpProxy() && lookup === dns.lookup) {
    return { target, addresses: [{ address: 'proxy-remote', family: 4 }] };
  }

  let addresses;
  try {
    addresses = await lookup(target.hostname, { all: true });
  } catch {
    throw new HostError('NETWORK', 'host resolution failed', {
      reason: 'DNS',
      transport: 'native',
      host: target.hostname,
    });
  }
  if (!addresses.length || addresses.some((a) => isPrivateAddress(a.address))) {
    throw new HostError('BLOCKED', 'private address is blocked', {
      reason: 'PRIVATE_ADDRESS',
      transport: 'native',
      host: target.hostname,
    });
  }
  return { target, addresses };
}

function decodeBodyText(bytes: Uint8Array, contentType?: string | null): string {
  const charsetMatch = contentType ? /charset\s*=\s*["']?([A-Za-z0-9._-]+)["']?/i.exec(contentType) : null;
  const requested = charsetMatch?.[1]?.trim().toLowerCase();
  if (requested && requested !== 'utf-8' && requested !== 'utf8') {
    try {
      return new HostTextDecoder(requested).decode(bytes);
    } catch {
      // Fallback to UTF-8 if server returned an unrecognized charset token
    }
  }
  return new HostTextDecoder('utf-8').decode(bytes);
}

function clampTimeout(timeout?: number, fallback = 30000): number {
  if (typeof timeout !== 'number' || !Number.isFinite(timeout)) return fallback;
  return Math.min(Math.max(Math.ceil(timeout), 1000), 120000);
}

async function pinnedRequest(
  target: URL,
  req: NetworkRequest,
  addresses: Awaited<ReturnType<typeof validateNetworkUrl>>['addresses'],
  maxResponseBytes: number,
): Promise<Response> {
  const payload =
    req.bodyBase64 !== undefined
      ? Buffer.from(req.bodyBase64, 'base64')
      : req.body !== undefined
        ? Buffer.from(req.body, 'utf8')
        : undefined;
  const requestHeaders = {
    ...req.headers,
    ...(payload === undefined ? {} : { 'content-length': String(payload.length) }),
  };
  const timeoutMs = clampTimeout(req.timeout, 30000);
  const proxyRemote = addresses[0]?.address === 'proxy-remote';

  return new Promise((done, reject) => {
    const request = https.request(
      target,
      {
        method: req.method ?? 'GET',
        headers: requestHeaders,
        servername: target.hostname,
        signal: req.signal,
        timeout: timeoutMs,
        agent: pinnedProxyAgent(target, proxyRemote ? undefined : addresses[0], req.signal, timeoutMs),
        ...(proxyRemote
          ? {}
          : {
              lookup: (_host, options, callback) => {
                const record = addresses[0]!;
                callback(null, options.all ? addresses : record.address, record.family);
              },
            }),
      },
      (response) => {
        const chunks: Buffer[] = [];
        let bytes = 0;
        response.on('data', (chunk: Buffer) => {
          bytes += chunk.length;
          if (bytes > maxResponseBytes) {
            response.destroy(new HostError('PARSE', 'upstream response exceeds limit'));
            return;
          }
          chunks.push(chunk);
        });
        response.on('error', reject);
        response.on('end', () => {
          const headers = new Headers();
          for (let i = 0; i < response.rawHeaders.length; i += 2) {
            headers.append(response.rawHeaders[i]!, response.rawHeaders[i + 1]!);
          }
          const status = response.statusCode ?? 502;
          try {
            let body: Buffer<ArrayBufferLike> = Buffer.concat(chunks);
            const encoding = headers.get('content-encoding')?.toLowerCase();
            const options = { maxOutputLength: maxResponseBytes };
            if (encoding === 'gzip' || encoding === 'x-gzip') body = gunzipSync(body, options);
            else if (encoding === 'deflate') body = inflateSync(body, options);
            else if (encoding === 'br') body = brotliDecompressSync(body, options);
            if (encoding) {
              headers.delete('content-encoding');
              headers.delete('content-length');
            }
            done(new Response(req.method === 'HEAD' || [204, 205, 304].includes(status) ? null : new Uint8Array(body), { status, headers }));
          } catch (error) {
            reject(error);
          }
        });
      },
    );
    request.on('timeout', () => request.destroy(new HostError('TIMEOUT', 'upstream timed out')));
    request.on('error', reject);
    request.end(payload);
  });
}

export async function fetchPinnedResource(
  url: string,
  domains: string[] | undefined,
  options: {
    signal?: AbortSignal;
    headers?: Record<string, string>;
    method?: 'GET' | 'HEAD';
    followRedirects?: false;
    allowPort?: boolean;
    timeoutMs?: number;
  } = {},
): Promise<Response> {
  let raw = url;
  let headers = withDefaultUserAgent(options.headers);
  const timeoutMs = clampTimeout(options.timeoutMs, 30000);

  for (let hop = 0; ; hop++) {
    const { target, addresses } = await validateNetworkUrl(raw, domains, dns.lookup, options.allowPort === true);
    const proxyRemote = addresses[0]?.address === 'proxy-remote';
    const response = await new Promise<Response>((done, reject) => {
      const request = https.request(
        target,
        {
          method: options.method ?? 'GET',
          headers,
          servername: target.hostname,
          signal: options.signal,
          timeout: timeoutMs,
          agent: pinnedProxyAgent(target, proxyRemote ? undefined : addresses[0], options.signal, timeoutMs),
          ...(proxyRemote
            ? {}
            : {
                lookup: (_host, value, callback) =>
                  callback(null, value.all ? addresses : addresses[0]!.address, addresses[0]!.family),
              }),
        },
        (res) => {
          const resHeaders = new Headers();
          for (let i = 0; i < res.rawHeaders.length; i += 2) {
            resHeaders.append(res.rawHeaders[i]!, res.rawHeaders[i + 1]!);
          }
          const status = res.statusCode ?? 502;
          done(
            new Response(
              options.method === 'HEAD' || [204, 205, 304].includes(status)
                ? null
                : (Readable.toWeb(res) as ReadableStream<Uint8Array>),
              { status, headers: resHeaders },
            ),
          );
        },
      );
      request.on('timeout', () => request.destroy(new HostError('TIMEOUT', 'media request timed out')));
      request.on('error', (error) =>
        reject(options.signal?.aborted ? runnerError(toAbortError(options.signal)) : error),
      );
      request.end();
    });

    if (!REDIRECT_STATUSES.has(response.status) || options.followRedirects === false) {
      Object.defineProperty(response, 'url', { value: target.href });
      return response;
    }
    const location = response.headers.get('location');
    await response.body?.cancel();
    if (!location || hop >= 5) throw new HostError('BLOCKED', 'invalid media redirect');
    const next = new URL(location, target);
    const redirected = redirectRequest(
      { url: target.href, method: options.method ?? 'GET', headers, followRedirects: true },
      target,
      next,
      response.status,
    );
    headers = withDefaultUserAgent(redirected.headers);
    raw = next.href;
  }
}

function isSafeRetryableRead(req: NetworkRequest): boolean {
  const method = (req.method ?? 'GET').toUpperCase();
  if (req.bodyBase64 !== undefined) return false;
  if (method === 'GET' || method === 'HEAD') return req.body === undefined;
  return method === 'POST' && req.readOnly === true && typeof req.body === 'string' && Buffer.byteLength(req.body) <= 2 * 1024 * 1024;
}

async function delayWithSignal(ms: number, signal?: AbortSignal): Promise<void> {
  if (signal?.aborted) throw runnerError(toAbortError(signal));
  await new Promise<void>((resolve, reject) => {
    const onAbort = () => {
      clearTimeout(timer);
      reject(runnerError(toAbortError(signal!)));
    };
    const timer = setTimeout(() => {
      signal?.removeEventListener('abort', onAbort);
      resolve();
    }, ms);
    signal?.addEventListener('abort', onAbort, { once: true });
  });
}

export class NetworkBroker {
  constructor(
    private readonly manifest: PluginManifest,
    private readonly fetchImpl: typeof fetch = fetch,
    private readonly lookup: typeof dns.lookup = dns.lookup,
    private readonly jar?: CookieJar,
    private readonly persistCookies?: () => Promise<void>,
    private readonly maxResponseBytes = 32 * 1024 * 1024,
  ) {}

  async request(req: NetworkRequest): Promise<NetworkResponse> {
    const canRetry = this.fetchImpl === fetch && isSafeRetryableRead(req);
    const maxAttempts = canRetry ? 3 : 1;
    let lastError: unknown;

    for (let attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt > 0) {
        await delayWithSignal(attempt === 1 ? 300 : 600, req.signal);
      }
      try {
        const res = await this.executeOnce(req);
        if (canRetry && attempt + 1 < maxAttempts && [408, 502, 503, 504].includes(res.status)) {
          continue;
        }
        return res;
      } catch (error) {
        lastError = error;
        if (!canRetry || req.signal?.aborted) throw error;
        const classified = toPluginError(error);
        const reason = classified.details?.reason;
        const transient =
          (classified.code === 'NETWORK' && ['CONNECTION', 'TLS_HANDSHAKE_TERMINATED'].includes(reason ?? '')) ||
          classified.code === 'TIMEOUT';
        if (!transient) throw error;
      }
    }
    throw lastError;
  }

  private async executeOnce(req: NetworkRequest): Promise<NetworkResponse> {
    if (!['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'].includes((req.method ?? 'GET').toUpperCase())) {
      throw new HostError('BLOCKED', 'HTTP method is blocked');
    }
    req = {
      ...req,
      headers: withDefaultUserAgent(
        Object.fromEntries(
          Object.entries(req.headers ?? {}).filter(
            ([key, value]) =>
              ![
                'host',
                'connection',
                'proxy-authorization',
                'proxy-connection',
                'transfer-encoding',
                'upgrade',
                'te',
                'trailer',
                'content-length',
              ].includes(key.toLowerCase()) && !/[\r\n]/.test(key + value),
          ),
        ),
      ),
    };
    if (req.connectAddress !== undefined) {
      const targetUrl = new URL(req.url);
      if (!hostAllowed(targetUrl.hostname, this.manifest.domains)) {
        throw new HostError('BLOCKED', 'connectAddress is only allowed for declared source domains');
      }
    }

    let raw = req.url;
    let connectAddr = req.connectAddress;
    let siteCredentials = true;

    for (let hops = 0; ; hops++) {
      if (req.signal?.aborted) throw runnerError(toAbortError(req.signal));
      const { target, addresses } = await validateNetworkUrl(raw, undefined, this.lookup, false, connectAddr);
      const sourceTarget = hostAllowed(target.hostname, this.manifest.domains);
      if (!sourceTarget) {
        req = {
          ...req,
          headers: Object.fromEntries(
            Object.entries(req.headers ?? {}).filter(([key]) => !['cookie', 'proxy-authorization'].includes(key.toLowerCase())),
          ),
        };
      }
      if (siteCredentials && sourceTarget && this.jar && !Object.keys(req.headers ?? {}).some((k) => k.toLowerCase() === 'cookie')) {
        const cookie = await this.jar.getCookieString(target.href);
        if (cookie) req = { ...req, headers: { ...req.headers, cookie } };
      }

      const response =
        this.fetchImpl === fetch
          ? await pinnedRequest(target, req, addresses, this.maxResponseBytes).catch((error) => {
              throw req.signal?.aborted ? runnerError(toAbortError(req.signal)) : error;
            })
          : await this.fetchImpl(target, {
              method: req.method ?? 'GET',
              headers: req.headers,
              body: req.bodyBase64 ? Buffer.from(req.bodyBase64, 'base64') : req.body,
              redirect: 'manual',
              signal: req.signal,
            }).catch((error) => {
              throw req.signal?.aborted ? runnerError(toAbortError(req.signal)) : error;
            });

      if (sourceTarget && this.jar) {
        for (const cookie of response.headers.getSetCookie()) {
          await this.jar.setCookie(cookie, target.href, { ignoreError: true });
        }
        await this.persistCookies?.();
      }

      if (REDIRECT_STATUSES.has(response.status) && req.followRedirects !== false) {
        const location = response.headers.get('location');
        await response.body?.cancel();
        if (!location || hops >= 5) throw new HostError('BLOCKED', 'invalid redirect');
        const next = new URL(location, target);
        req = redirectRequest(req, target, next, response.status);
        if (next.origin !== target.origin) {
          siteCredentials = false;
          connectAddr = undefined;
        }
        raw = next.href;
        continue;
      }

      const bytes = new Uint8Array(await response.arrayBuffer());
      if (bytes.length > this.maxResponseBytes) throw new HostError('PARSE', 'upstream response exceeds limit');
      const headers = Object.fromEntries(response.headers.entries());
      const cookies = response.headers.getSetCookie();
      if (cookies.length) headers['set-cookie'] = cookies.join('\n');
      return {
        status: response.status,
        headers,
        body:
          req.responseType === 'base64'
            ? Buffer.from(bytes).toString('base64')
            : decodeBodyText(bytes, response.headers.get('content-type')),
        url: target.href,
      };
    }
  }
}

export class IsolatedStore {
  private readonly cookies = new Map<string, Map<string, string>>();
  private readonly state = new Map<string, Map<string, unknown>>();
  private map<T>(source: string, root: Map<string, Map<string, T>>) {
    let m = root.get(source);
    if (!m) {
      m = new Map();
      root.set(source, m);
    }
    return m;
  }
  getCookie(source: string, key: string) {
    return this.map(source, this.cookies).get(key);
  }
  setCookie(source: string, key: string, value: string) {
    this.map(source, this.cookies).set(key, value);
  }
  getState(source: string, key: string) {
    return this.map(source, this.state).get(key);
  }
  setState(source: string, key: string, value: unknown) {
    this.map(source, this.state).set(key, value);
  }
  clear(source: string) {
    this.cookies.delete(source);
    this.state.delete(source);
  }
  clearAll() {
    this.cookies.clear();
    this.state.clear();
  }
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
  private network = new Map<string, { controller: AbortController; invocationId?: string }>();
  private closed = false;
  get isClosed() {
    return this.closed;
  }
  constructor(
    private readonly runnerPath: string,
    private readonly sourcePath: string,
    private readonly broker?: Pick<NetworkBroker, 'request'>,
    private readonly runtimePath?: string,
    private readonly native?: (operation: string, args: Record<string, unknown>) => Promise<unknown>,
  ) {}

  start() {
    if (this.closed) throw new HostError('CANCELLED', 'runner is closed');
    if (this.child) return;
    this.buffer = '';
    const runtime = this.runtimePath ?? resolve(dirname(this.runnerPath), '../../../assets/runtime/park_runtime.js');
    const contractDirectory = dirname(fileURLToPath(import.meta.resolve('@hentai-park/source-contract')));
    const adapterDirectory = dirname(createRequire(this.runnerPath).resolve('@hentai-park/source-runtime'));
    const readPaths = new Set([
      dirname(this.runnerPath),
      contractDirectory,
      adapterDirectory,
      join(dirname(adapterDirectory), 'node_modules'),
      this.sourcePath,
      runtime,
      join(dirname(runtime), 'polyfills.js'),
      join(resolve(dirname(runtime), '../..'), 'node_modules'),
      join(resolve(dirname(runtime), '../..'), 'apps/source-runner/node_modules'),
    ]);
    for (const base of [dirname(this.runnerPath), contractDirectory, adapterDirectory]) {
      let directory = base;
      for (let depth = 0; depth < 5; depth++) {
        readPaths.add(join(directory, 'package.json'));
        const parent = dirname(directory);
        if (parent === directory) break;
        directory = parent;
      }
    }
    const child = spawn(
      process.execPath,
      [
        '--permission',
        ...[...readPaths].map((value) => '--allow-fs-read=' + resolve(value)),
        '--max-old-space-size=384',
        this.runnerPath,
        '--plugin',
        this.sourcePath,
        '--runtime',
        runtime,
      ],
      { stdio: ['pipe', 'pipe', 'pipe'], env: { NODE_ENV: 'production' }, windowsHide: true },
    );
    this.child = child;
    child.stdin.on('error', () => this.pipeFailed(child));
    child.stdout.setEncoding('utf8');
    child.stdout.on('data', (d) => this.onData(d));
    child.stderr.on('data', () => {});
    child.on('exit', () => {
      if (this.child === child) this.failAll(new HostError('NETWORK', 'source-runner exited'));
    });
    child.on('error', () => this.failAll(new HostError('NETWORK', 'source-runner failed')));
  }

  private pipeFailed(child: ChildProcessWithoutNullStreams) {
    if (this.closed || this.child !== child) return;
    this.failAll(new HostError('NETWORK', 'source-runner input failed'));
    child.kill();
  }

  private write(child: ChildProcessWithoutNullStreams, message: string) {
    if (this.closed || this.child !== child) return;
    if (child.killed || child.stdin.destroyed || !child.stdin.writable) {
      this.pipeFailed(child);
      return;
    }
    try {
      child.stdin.write(message, (error) => {
        if (error) this.pipeFailed(child);
      });
    } catch {
      this.pipeFailed(child);
    }
  }

  private finish(id: string, error?: unknown, result?: unknown) {
    const p = this.pending.get(id);
    if (!p) return;
    this.pending.delete(id);
    clearTimeout(p.timer);
    p.signal?.removeEventListener('abort', p.cancel);
    error ? p.reject(error) : p.resolve(result);
  }

  private onData(data: string) {
    if (this.closed) return;
    this.buffer += data;
    if (this.buffer.length > 32 * 1024 * 1024) {
      this.failAll(new HostError('PARSE', 'runner message exceeds limit'));
      this.child?.kill();
      return;
    }
    let i;
    while ((i = this.buffer.indexOf('\n')) >= 0) {
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
          void this.native(msg.operation ?? '', msg.args ?? {}).then(
            (result) => {
              if (!this.closed) this.write(child, JSON.stringify({ id: msg.id, result }) + '\n');
            },
            (error) => {
              if (!this.closed) this.write(child, JSON.stringify({ id: msg.id, error: toPluginError(error) }) + '\n');
            },
          );
          continue;
        }
        if (msg.type === 'network' && this.child && this.broker && msg.request) {
          const child = this.child;
          const controller = new AbortController();
          const invocationId = typeof msg.request.invocation === 'string' ? msg.request.invocation : undefined;
          this.network.set(msg.id, { controller, invocationId });
          void this.broker
            .request({ ...msg.request, signal: controller.signal })
            .then(
              (result) => {
                if (!this.closed) this.write(child, JSON.stringify({ id: msg.id, result }) + '\n');
              },
              (error) => {
                if (!this.closed) this.write(child, JSON.stringify({ id: msg.id, error: toPluginError(error) }) + '\n');
              },
            )
            .finally(() => this.network.delete(msg.id));
          continue;
        }
        this.finish(msg.id, msg.error ? runnerError(msg.error) : undefined, msg.result);
      } catch {
        this.failAll(new HostError('PARSE', 'invalid runner response'));
        this.child?.kill();
      }
    }
  }

  private failAll(error: Error) {
    this.closed = true;
    for (const id of this.pending.keys()) this.finish(id, error);
    for (const entry of this.network.values()) entry.controller.abort(error);
    this.network.clear();
  }

  request(method: string, params: unknown, timeoutMs = 45000, signal?: AbortSignal): Promise<unknown> {
    if (signal?.aborted) return Promise.reject(runnerError(toAbortError(signal)));
    if (this.closed) return Promise.reject(runnerError(toPluginError({ code: 'CANCELLED' })));
    this.start();
    const child = this.child;
    if (!child || this.closed) return Promise.reject(new HostError('NETWORK', 'runner unavailable'));
    const id = randomUUID();

    return new Promise((done, reject) => {
      const stop = (code: 'TIMEOUT' | 'CANCELLED') => {
        if (!this.pending.has(id)) return;
        const interruption = runnerError(
          toPluginError({
            code,
            details: { reason: code === 'TIMEOUT' ? 'RECEIVE_TIMEOUT' : 'CANCELLED' },
          }),
        );
        this.finish(id, interruption);
        // Fine-grained per-invocation cancellation: abort only this invocation's in-flight network requests
        // and keep the healthy source-runner process alive for other concurrent invocations!
        for (const [netId, entry] of this.network.entries()) {
          if (entry.invocationId === id) {
            entry.controller.abort(interruption);
            this.network.delete(netId);
          }
        }
        if (code === 'CANCELLED' && !this.closed) {
          this.write(child, JSON.stringify({ id, method: 'abortInvocation' }) + '\n');
        } else if (code === 'TIMEOUT' && this.pending.size === 0) {
          // If the runner timed out with no other active requests (possible synchronous spin), recycle cleanly
          this.failAll(new HostError('CANCELLED', 'runner recycled after timeout'));
          child.kill();
        } else if (!this.closed) {
          this.write(child, JSON.stringify({ id, method: 'abortInvocation' }) + '\n');
        }
      };

      const cancel = () => stop(toAbortError(signal!).code === 'TIMEOUT' ? 'TIMEOUT' : 'CANCELLED');
      const budgetMs = Math.min(Math.max(Number.isFinite(timeoutMs) ? timeoutMs : 45000, 1), 300000);
      const deadlineAt = Date.now() + Math.ceil(budgetMs);
      const timer = setTimeout(() => stop('TIMEOUT'), budgetMs);
      this.pending.set(id, { resolve: done, reject, timer, signal, cancel });
      signal?.addEventListener('abort', cancel, { once: true });
      this.write(child, JSON.stringify({ id, method, params, deadlineAt }) + '\n');
    });
  }

  async close() {
    this.failAll(new HostError('CANCELLED', 'runner closed'));
    const child = this.child;
    this.child = undefined;
    if (child && child.exitCode === null && child.signalCode === null) {
      await new Promise<void>((done) => {
        child.once('exit', () => done());
        child.kill();
        setTimeout(done, 2000).unref();
      });
    }
  }
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
  browserExecutor?: SourceBrowserExecutor;
}

interface PrivateSourceState {
  jar: CookieJar;
  data: unknown;
  settings: Record<string, unknown>;
  settingsVersion: number;
  settingsUpdatedAt: string;
}

interface RunnerEntry {
  client: SourceRunnerClient;
  lastUsed: number;
  active: number;
}

export class SourceHost {
  private readonly challengeTargets = new Map<string, string>();
  verificationTarget(source: string) {
    return this.challengeTargets.get(source) ?? this.registry.get(source)?.manifest.homepage;
  }
  private idleTimer?: ReturnType<typeof setInterval>;
  private mutation: Promise<unknown> = Promise.resolve();
  private browserExecutor?: SourceBrowserExecutor;
  // Remember hosts where native image fetch failed and browser image fetch succeeded during this runtime
  private readonly browserImageRoutes = new Set<string>();

  setBrowserExecutor(executor: SourceBrowserExecutor) {
    this.browserExecutor = executor;
  }

  private async syncBrowserCookies(
    manifest: PluginManifest,
    state: PrivateSourceState,
    cookies: SourceBrowserCookie[],
    initial: SourceBrowserCookie[] = [],
    signal?: AbortSignal,
  ) {
    if (signal?.aborted) throw runnerError(toAbortError(signal));
    const jar = CookieJar.deserializeSync(state.jar.serializeSync()!);
    const key = (c: SourceBrowserCookie) => [c.domain.replace(/^\./, ''), c.path ?? '/', c.name].join('\n');
    const final = new Map(cookies.map((c) => [key(c), c]));
    for (const c of initial) {
      if (!final.has(key(c))) {
        const domain = c.domain.replace(/^\./, '');
        const current = jar
          .serializeSync()!
          .cookies.find((v) => v.domain === domain && v.path === (c.path ?? '/') && v.key === c.name);
        if (current?.value === c.value) {
          jar.setCookieSync(
            new Cookie({ key: c.name, value: '', domain, path: c.path ?? '/', maxAge: 0 }),
            'https://' + domain + '/',
          );
        }
      }
    }
    for (const c of cookies) {
      const domain = c.domain.replace(/^\./, '');
      if (!hostAllowed(domain, manifest.domains)) continue;
      jar.setCookieSync(
        new Cookie({
          key: c.name,
          value: c.value,
          domain,
          hostOnly: !c.domain.startsWith('.'),
          path: c.path ?? '/',
          secure: true,
          httpOnly: c.httpOnly,
          sameSite: c.sameSite?.toLowerCase(),
          expires: c.expires > 0 ? new Date(c.expires * 1000) : 'Infinity',
        }),
        'https://' + domain + '/',
      );
    }
    if (signal?.aborted) throw runnerError(toAbortError(signal));
    const previous = state.jar;
    state.jar = jar;
    try {
      await this.persistState(manifest.key);
    } catch (error) {
      if (state.jar === jar) state.jar = previous;
      throw error;
    }
  }

  async completeVerification(
    source: string,
    cookies: SourceBrowserCookie[],
    initial: SourceBrowserCookie[],
    signal: AbortSignal,
  ) {
    const record = this.registry.get(source);
    if (!record?.enabled) throw new HostError('CONFIG', 'source disabled');
    const state = await this.privateState(source);
    await this.syncBrowserCookies(record.manifest, state, cookies, initial, signal);
  }

  private sourceBroker(manifest: PluginManifest, state: PrivateSourceState): Pick<NetworkBroker, 'request'> {
    return {
      request: async (request) => {
        if (request.mode !== 'browser') {
          const result = await new NetworkBroker(
            manifest,
            fetch,
            dns.lookup,
            state.jar,
            () => this.persistState(manifest.key),
          ).request(request);
          const code = responseChallenge(
            {
              ...result,
              body: request.responseType === 'base64' ? Buffer.from(result.body, 'base64').toString('utf8') : result.body,
            },
            true,
          );
          if (code) {
            if (code === 'CLOUDFLARE' && hostAllowed(new URL(request.url).hostname, manifest.domains)) {
              this.challengeTargets.set(manifest.key, request.url);
            }
            // Preserve result.status so Park.createDomainResolver can detect 403 CLOUDFLARE and switch domains!
            throw new HostError(code, 'Site verification required', {
              reason: code === 'BLOCKED' ? 'FIREWALL_BLOCKED' : 'SITE_CHALLENGE',
              transport: 'native',
              status: result.status,
              host: new URL(request.url).hostname,
            });
          }
          return result;
        }
        if (!this.browserExecutor) throw new HostError('UNSUPPORTED', 'browser request executor is unavailable');
        await validateNetworkUrl(request.url, manifest.domains);
        const initial = await this.browserCookies(manifest.key);
        const result = await this.browserExecutor
          .request({ source: manifest.key, manifest, request, cookies: initial })
          .catch((error) => {
            if (!request.signal?.aborted && ['CLOUDFLARE', 'VERIFICATION_REQUIRED'].includes(toPluginError(error).code)) {
              this.challengeTargets.set(manifest.key, request.url);
            }
            throw error;
          });
        if (request.signal?.aborted) throw runnerError(toAbortError(request.signal));
        if (result.cookies) await this.syncBrowserCookies(manifest, state, result.cookies, initial, request.signal);
        return { status: result.status, headers: result.headers, body: result.body, url: result.url };
      },
    };
  }

  private mediaResources = new Map<
    string,
    {
      source: string;
      url: string;
      headers: Record<string, string>;
      session: boolean;
      image: boolean;
      expiresAt: number;
    }
  >();
  private mediaContexts = new WeakMap<object, string>();

  private rememberMedia(
    source: string,
    manifest: PluginManifest,
    value: unknown,
    depth = 0,
    session = false,
    image = false,
  ) {
    if (depth === 0) {
      const now = Date.now();
      for (const [key, resource] of this.mediaResources) {
        if (resource.expiresAt <= now) this.mediaResources.delete(key);
      }
      while (this.mediaResources.size > 16384) {
        this.mediaResources.delete(this.mediaResources.keys().next().value!);
      }
    }
    if (depth > 8 || !value || typeof value !== 'object') return;
    if (Array.isArray(value)) {
      for (const item of value) this.rememberMedia(source, manifest, item, depth + 1, session, image);
      return;
    }
    const row = value as Record<string, unknown>;
    if (typeof row.url === 'string') {
      try {
        const target = new URL(row.url);
        if (target.protocol === 'https:' && !target.username && !target.password && !target.port) {
          const imageNode = image || row.type === 'image';
          const headers = mediaRequestHeaders(manifest, row.headers ?? {}, imageNode);
          const context = randomUUID();
          // Keep media contexts valid for 2 hours to match long-lived playback sessions without premature 5m expiry
          this.mediaResources.set(context, {
            source,
            url: target.href,
            headers,
            image: imageNode,
            session: session || manifest.media?.scope === 'session',
            expiresAt: Date.now() + 2 * 3600 * 1000,
          });
          this.mediaContexts.set(row, context);
        }
      } catch (error) {
        if (error && typeof error === 'object' && 'code' in error) throw error;
      }
    }
    for (const [key, item] of Object.entries(row)) {
      if (key !== 'headers') this.rememberMedia(source, manifest, item, depth + 1, session, image);
    }
  }

  private privateStates = new Map<string, PrivateSourceState>();
  private readonly accountTransactions = new Set<string>();
  private readonly stagedPrivateWrites = new Set<string>();
  private loadingStates = new Map<string, Promise<PrivateSourceState>>();

  private async privateState(source: string): Promise<PrivateSourceState> {
    const current = this.privateStates.get(source);
    if (current) return current;
    const loading = this.loadingStates.get(source);
    if (loading) return loading;
    const action = (async () => {
      let state: PrivateSourceState = {
        jar: new CookieJar(),
        data: {},
        settings: {},
        settingsVersion: 0,
        settingsUpdatedAt: this.registry.get(source)?.updatedAt ?? new Date(0).toISOString(),
      };
      if (this.options.stateDirectory) {
        try {
          const saved = JSON.parse(await readFile(resolve(this.options.stateDirectory, source + '.json'), 'utf8'));
          state = {
            jar: CookieJar.deserializeSync(saved.cookies),
            data: saved.data ?? {},
            settings: saved.settings ?? {},
            settingsVersion:
              Number.isSafeInteger(saved.settingsVersion) && saved.settingsVersion >= 0 ? saved.settingsVersion : 0,
            settingsUpdatedAt:
              typeof saved.settingsUpdatedAt === 'string' && Number.isFinite(Date.parse(saved.settingsUpdatedAt))
                ? saved.settingsUpdatedAt
                : (await stat(resolve(this.options.stateDirectory, source + '.json'))).mtime.toISOString(),
          };
        } catch (error) {
          if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
        }
      }
      this.privateStates.set(source, state);
      return state;
    })();
    this.loadingStates.set(source, action);
    try {
      return await action;
    } finally {
      this.loadingStates.delete(source);
    }
  }

  private stateWriting: Promise<unknown> = Promise.resolve();
  private async persistState(source: string) {
    if (this.stagedPrivateWrites.has(source) || !this.options.stateDirectory) return;
    const state = await this.privateState(source);
    const data = JSON.stringify({
      cookies: state.jar.serializeSync(),
      data: state.data,
      settings: state.settings,
      settingsVersion: state.settingsVersion,
      settingsUpdatedAt: state.settingsUpdatedAt,
    });
    const destination = resolve(this.options.stateDirectory, source + '.json');
    const action = this.stateWriting.then(() => atomicWrite(destination, data));
    this.stateWriting = action.catch(() => {});
    await action;
  }

  private async native(source: string, manifest: PluginManifest, operation: string, args: Record<string, unknown>) {
    const state = await this.privateState(source);
    if (operation === 'persist') {
      state.data = args.data;
      await this.persistState(source);
      return null;
    }
    if (operation === 'cookies') {
      const values = args.args as Record<string, unknown>;
      const url = new URL(String(values.url));
      await validateNetworkUrl(url.href, manifest.domains);
      if (args.op === 'clear') {
        for (const cookie of await state.jar.getCookies(url.href)) {
          await state.jar.setCookie(`${cookie.key}=; Path=${cookie.path}; Max-Age=0`, url.href, { ignoreError: true });
        }
        await this.persistState(source);
      }
      if (args.op === 'set') {
        const cookies = values.cookies as Record<string, unknown>;
        for (const [key, value] of Object.entries(cookies ?? {})) {
          if (!/^[!#$%&'*+.^_`|~0-9A-Za-z-]{1,128}$/.test(key) || typeof value !== 'string' || /[\r\n;]/.test(value)) {
            throw new HostError('CONFIG', 'invalid cookie');
          }
          // Align with lib/engine/cookie_store.dart: domain cookie covering declared subdomains + 1-year persistence
          const cookie = new Cookie({
            key,
            value,
            domain: url.hostname,
            hostOnly: false,
            path: '/',
            secure: true,
            maxAge: 31536000,
          });
          await state.jar.setCookie(cookie, url.href, { ignoreError: true });
        }
        await this.persistState(source);
      }
      return Object.fromEntries((await state.jar.getCookies(url.href)).map((cookie) => [cookie.key, cookie.value]));
    }
    if (operation === 'chatRequest') return chatRequest(manifest, args as unknown as NetworkRequest);
    throw new HostError('UNSUPPORTED', 'unsupported private state operation');
  }

  private readonly clients = new Map<string, RunnerEntry>();
  private readonly sourceExecutions = new Map<
    string,
    { active: number; controller: AbortController; jobs: Array<{ run: () => Promise<void>; cancel: () => void }> }
  >();
  private readonly poolWaiters: Array<{ wake: () => void; cancel: () => void }> = [];

  /**
   * Concurrent per-source execution (up to 6 concurrent calls per source, queue up to 64)
   * matching Android WebView's non-blocking async invocation model instead of a global boolean lock.
   */
  private withSourceExecution<T>(
    source: string,
    options: { signal?: AbortSignal; timeoutMs?: number },
    action: (signal: AbortSignal) => Promise<T>,
  ): Promise<T> {
    if (options.signal?.aborted) return Promise.reject(runnerError(toAbortError(options.signal)));
    let queue = this.sourceExecutions.get(source);
    if (!queue) {
      queue = { active: 0, controller: new AbortController(), jobs: [] };
      this.sourceExecutions.set(source, queue);
    }
    const current = queue;
    if (current.jobs.length + current.active >= 64) {
      return Promise.reject(new HostError('RATE_LIMITED', 'operation limit'));
    }
    const budget = Math.min(Math.max(Number.isFinite(options.timeoutMs) ? options.timeoutMs! : 45000, 1), 300000);
    const signal = AbortSignal.any([
      current.controller.signal,
      AbortSignal.timeout(Math.ceil(budget)),
      ...(options.signal ? [options.signal] : []),
    ]);

    const perSourceConcurrency = 6;
    const drain = () => {
      while (current.active < perSourceConcurrency && current.jobs.length > 0) {
        const job = current.jobs.shift()!;
        current.active++;
        void job.run().finally(() => {
          current.active--;
          if (current.active === 0 && current.jobs.length === 0 && this.sourceExecutions.get(source) === current) {
            this.sourceExecutions.delete(source);
          } else {
            drain();
          }
        });
      }
    };

    return new Promise<T>((resolve, reject) => {
      const job = {
        run: async () => {
          signal.removeEventListener('abort', job.cancel);
          try {
            if (signal.aborted) throw runnerError(toAbortError(signal));
            resolve(await action(signal));
          } catch (error) {
            reject(error);
          }
        },
        cancel: () => {
          const index = current.jobs.indexOf(job);
          if (index < 0) return;
          current.jobs.splice(index, 1);
          signal.removeEventListener('abort', job.cancel);
          reject(runnerError(toAbortError(signal)));
          drain();
        },
      };
      current.jobs.push(job);
      signal.addEventListener('abort', job.cancel, { once: true });
      drain();
    });
  }

  private poolMutation: Promise<unknown> = Promise.resolve();
  private withPool<T>(action: () => Promise<T> | T): Promise<T> {
    const pending = this.poolMutation.then(action);
    this.poolMutation = pending.then(
      () => undefined,
      () => undefined,
    );
    return pending;
  }

  private releaseRunnerSlot(entry: RunnerEntry) {
    entry.active = Math.max(0, entry.active - 1);
    entry.lastUsed = Date.now();
    if (entry.active === 0) {
      const next = this.poolWaiters.shift();
      next?.wake();
    }
  }

  private async closeEntry(source: string, entry: RunnerEntry) {
    if (this.clients.get(source) === entry) this.clients.delete(source);
    await entry.client.close();
  }

  private async reserveClient(
    manifest: PluginManifest,
    pluginPath: string,
    state: PrivateSourceState,
    signal?: AbortSignal,
  ): Promise<RunnerEntry> {
    for (;;) {
      signal?.throwIfAborted();
      let waitPromise: Promise<void> | undefined;
      const reserved = await this.withPool(async () => {
        if (this.accountTransactions.has(manifest.key)) {
          throw new HostError('RATE_LIMITED', 'account update is in progress');
        }
        const registered = this.registry.get(manifest.key);
        if (registered && !registered.enabled) throw new HostError('CONFIG', 'source disabled');
        if (
          registered &&
          (resolve(pluginPath) !== resolve(registered.packagePath) || registered.manifest.version !== manifest.version)
        ) {
          throw new HostError('INVALID_MANIFEST', 'installed plugin identity mismatch');
        }
        let entry = this.clients.get(manifest.key);
        if (entry?.client.isClosed) {
          await this.closeEntry(manifest.key, entry);
          entry = undefined;
        }
        if (!entry) {
          if (registered?.sha256 && sha256(await readFile(pluginPath)) !== registered.sha256) {
            throw new HostError('INVALID_MANIFEST', 'installed plugin integrity mismatch');
          }
          // Soft idle water-level (maxSources default 8) + elastic hard ceiling (maxSources * 3) with async queueing
          const hardLimit = Math.max(this.maxSources * 3, 16);
          if (this.clients.size >= this.maxSources) {
            const candidate = [...this.clients.entries()]
              .filter(([, value]) => value.active === 0)
              .sort((a, b) => a[1].lastUsed - b[1].lastUsed)[0];
            if (candidate) {
              await this.closeEntry(candidate[0], candidate[1]);
            } else if (this.clients.size >= hardLimit) {
              if (this.poolWaiters.length >= 64) {
                throw new HostError('RATE_LIMITED', 'all source runners are active');
              }
              waitPromise = new Promise<void>((resolveWait, rejectWait) => {
                const waiter = {
                  wake: () => {
                    signal?.removeEventListener('abort', waiter.cancel);
                    resolveWait();
                  },
                  cancel: () => {
                    const idx = this.poolWaiters.indexOf(waiter);
                    if (idx >= 0) this.poolWaiters.splice(idx, 1);
                    rejectWait(runnerError(toAbortError(signal!)));
                  },
                };
                this.poolWaiters.push(waiter);
                signal?.addEventListener('abort', waiter.cancel, { once: true });
              });
              return undefined;
            }
          }
          entry = {
            client: new SourceRunnerClient(
              this.runnerPath,
              pluginPath,
              this.sourceBroker(manifest, state),
              this.options.runtimePath,
              (operation, args) => this.native(manifest.key, manifest, operation, args),
            ),
            lastUsed: Date.now(),
            active: 0,
          };
          this.clients.set(manifest.key, entry);
        }
        entry.active++;
        entry.lastUsed = Date.now();
        return entry;
      });

      if (reserved) return reserved;
      if (waitPromise) await waitPromise;
    }
  }

  readonly stores = new IsolatedStore();
  readonly index: PluginIndex;
  readonly journal: InstallationJournal;
  readonly registry: SourceRegistry;
  private readonly idleMs: number;
  private readonly maxSources: number;

  constructor(
    private readonly runnerPath: string,
    private readonly appVersion = '0.14.8',
    private readonly options: SourceHostOptions = {},
  ) {
    this.browserExecutor = options.browserExecutor;
    this.index = options.index ?? new PluginIndex();
    this.journal = options.journal ?? new InstallationJournal();
    this.registry = options.registry ?? new SourceRegistry();
    if (options.pluginDirectory) {
      this.registry.bindPluginDirectory(options.pluginDirectory);
      this.journal.bindPluginDirectory(options.pluginDirectory);
    }
    this.idleMs = options.idleMs ?? 300000;
    this.maxSources = options.maxSources ?? 8;
    this.idleTimer = setInterval(() => {
      void this.reapIdle().catch((error) => {
        if (this.options.onError) this.options.onError(error);
        else console.error('[source-host] SOURCE_REAP_FAILED');
      });
    }, 30000);
    this.idleTimer.unref();
  }

  loadManifest(input: unknown): PluginManifest {
    validateManifest(input);
    const m = input as PluginManifest;
    if (!compatible(this.appVersion, m.minAppVersion)) {
      throw new HostError('INCOMPATIBLE', 'plugin requires newer app');
    }
    return m;
  }

  async inspect(pluginPath: string, options: { signal?: AbortSignal; timeoutMs?: number } = {}) {
    const client = new SourceRunnerClient(this.runnerPath, pluginPath, undefined, this.options.runtimePath);
    try {
      const manifest = await client.request('manifest', undefined, options.timeoutMs ?? 30000, options.signal);
      return this.loadManifest(manifest);
    } finally {
      await client.close();
    }
  }

  async invoke(
    manifest: PluginManifest,
    pluginPath: string,
    method: string,
    params?: unknown,
    options: { timeoutMs?: number; signal?: AbortSignal } = {},
  ) {
    return this.withSourceExecution(manifest.key, options, async (signal) => {
      const m = this.loadManifest(manifest);
      const state = await this.privateState(m.key);
      if (signal.aborted) throw runnerError(toAbortError(signal));
      const registered = this.registry.get(m.key);
      if (registered && !registered.enabled) throw new HostError('CONFIG', 'source disabled');
      if (!operationCapability(method) || m.capabilities?.[operationCapability(method)!] !== true) {
        throw new HostError('UNSUPPORTED', 'capability is not declared');
      }
      const entry = await this.reserveClient(m, pluginPath, state, signal);
      try {
        const result = await entry.client.request(
          'invoke',
          { method, params, expectedManifest: m, stateSnapshot: { data: state.data, settings: state.settings } },
          options.timeoutMs,
          signal,
        );
        if (['chapter', 'videos', 'voiceResource', 'resolveImage', 'album'].includes(method)) {
          this.rememberMedia(
            m.key,
            m,
            result,
            0,
            ['album', 'subscription.posts'].includes(method),
            ['chapter', 'resolveImage'].includes(method),
          );
        }
        return result;
      } catch (error) {
        throw toPluginError(error);
      } finally {
        this.releaseRunnerSlot(entry);
      }
    });
  }

  /**
   * Fast startup registration for build-verified bundled official plugins:
   * verifies exact SHA-256 against the pre-inspected source-index.json and flushes registry once,
   * reducing cold start from 100+ subprocess spawns (~60s) to <150ms.
   */
  async bootstrapBundled(
    packages: Array<{
      source: string;
      version: string;
      sha256: string;
      packagePath?: string;
      file?: string;
      manifest: PluginManifest;
      origin?: SourceRegistryRecord['origin'];
    }>,
    sourcesDirectory?: string,
  ): Promise<number> {
    if (!packages.length) return 0;
    const action = this.mutation.then(async () => {
      const directory =
        this.options.pluginDirectory ??
        this.registry.pluginDirectory ??
        this.journal.pluginDirectory;
      if (!directory) throw new HostError('CONFIG', 'plugin directory must be configured');
      this.registry.bindPluginDirectory(directory);
      this.journal.bindPluginDirectory(directory);
      await mkdir(directory, { recursive: true });
      const baseDir = sourcesDirectory ? resolve(sourcesDirectory) : undefined;

      let bootstrapped = 0;
      for (const item of packages) {
        if (this.registry.get(item.source)) continue;
        const m = this.loadManifest(item.manifest);
        if (m.key !== item.source || m.version !== item.version || !/^[a-f0-9]{64}$/.test(item.sha256)) {
          throw new HostError('INVALID_MANIFEST', `invalid bundled entry: ${item.source}`);
        }
        let resolvedSourcePath = item.packagePath;
        if (!resolvedSourcePath && item.file && baseDir) {
          const candidate = resolve(baseDir, item.file);
          const rel = relative(baseDir, candidate);
          if (rel.startsWith('..') || isAbsolute(rel)) {
            throw new HostError('BLOCKED', `invalid bundled file path: ${item.source}`);
          }
          resolvedSourcePath = candidate;
        }
        if (!resolvedSourcePath) {
          throw new HostError('INVALID_MANIFEST', `missing bundled file path: ${item.source}`);
        }
        const bytes = await readFile(resolvedSourcePath);
        const digest = sha256(bytes);
        if (digest !== item.sha256) {
          throw new HostError('INVALID_MANIFEST', `bundled plugin checksum mismatch: ${item.source}`);
        }
        const targetPath = resolve(directory, digest + '.js');
        await immutableArtifact(targetPath, bytes, digest);
        const record: SourceRegistryRecord = {
          source: m.key,
          version: m.version,
          packagePath: targetPath,
          manifest: m,
          sha256: digest,
          enabled: true,
          updatedAt: new Date().toISOString(),
          ...(item.origin ? { origin: structuredClone(item.origin) } : {}),
        };
        const journalEntry = this.journal.begin(m.key, m.version, undefined, {
          sha256: digest,
          permissions: permissionChanges(undefined, m),
          next: record,
        });
        this.registry.upsert(record);
        this.index.add({
          source: m.key,
          version: m.version,
          minAppVersion: m.minAppVersion,
          sha256: digest,
          manifest: m,
          packagePath: targetPath,
        });
        this.journal.commit(journalEntry);
        bootstrapped++;
      }
      if (bootstrapped > 0) {
        await this.journal.flush();
        await this.registry.flush();
      }
      return bootstrapped;
    });
    this.mutation = action.catch(() => {});
    return action;
  }

  async install(
    source: string,
    packagePath: string,
    manifestInput: unknown,
    expectedSha256?: string,
    origin?: SourceRegistryRecord['origin'],
  ) {
    const action = this.mutation.then(() =>
      this.installNow(source, packagePath, manifestInput, expectedSha256, origin),
    );
    this.mutation = action.catch(() => {});
    return action;
  }

  private async installNow(
    source: string,
    packagePath: string,
    manifestInput: unknown,
    expectedSha256?: string,
    origin?: SourceRegistryRecord['origin'],
  ) {
    const m = this.loadManifest(manifestInput);
    if (m.key !== source) throw new HostError('INVALID_MANIFEST', 'source key mismatch');
    if (!expectedSha256 || !/^[a-f0-9]{64}$/.test(expectedSha256)) {
      throw new HostError('INVALID_MANIFEST', 'trusted checksum required');
    }
    const bytes = await readFile(packagePath);
    const digest = sha256(bytes);
    if (digest !== expectedSha256) throw new HostError('INVALID_MANIFEST', 'checksum mismatch');
    const directory =
      this.options.pluginDirectory ??
      this.registry.pluginDirectory ??
      this.journal.pluginDirectory ??
      resolve(dirname(packagePath), '.installed');
    this.registry.bindPluginDirectory(directory);
    this.journal.bindPluginDirectory(directory);
    await mkdir(directory, { recursive: true });
    packagePath = resolve(directory, digest + '.js');
    await immutableArtifact(packagePath, bytes, digest);
    const actual = await this.inspect(packagePath);
    if (!isDeepStrictEqual(actual, m)) {
      throw new HostError('INVALID_MANIFEST', 'installed script manifest does not match trusted manifest');
    }
    const previous = this.registry.get(source);
    const record = this.journal.begin(source, m.version, previous?.version, {
      sha256: digest,
      permissions: permissionChanges(previous?.manifest, m),
      previous,
      next: {
        source,
        version: m.version,
        packagePath: resolve(packagePath),
        manifest: m,
        sha256: digest,
        enabled: previous ? previous.enabled : true,
        updatedAt: new Date().toISOString(),
      },
    });
    await this.journal.flush();
    try {
      await this.dispose(source);
      if (origin) record.next!.origin = structuredClone(origin);
      this.registry.upsert(record.next!);
      await this.registry.flush();
      this.index.add({
        source,
        version: m.version,
        minAppVersion: m.minAppVersion,
        sha256: digest,
        manifest: m,
        packagePath: resolve(packagePath),
      });
      this.journal.commit(record);
      await this.journal.flush();
      return record;
    } catch (error) {
      this.registry.rollbackWrite(source, previous);
      await this.registry.flush();
      this.journal.rollback(record);
      await this.journal.flush();
      throw error;
    }
  }

  /**
   * Uninstall a plugin (custom or withdrawn official plugin): cleans up runtime, browser session,
   * registry entry, and source private state/cookies while preserving user library, history, and downloads.
   */
  async uninstall(source: string) {
    const action = this.mutation.then(async () => {
      const existing = this.registry.get(source);
      if (!existing) throw new HostError('NOT_FOUND', 'source not installed');
      await this.dispose(source);
      this.registry.remove(source);
      await this.registry.flush();
      this.index.remove(source);
      this.privateStates.delete(source);
      this.challengeTargets.delete(source);
      if (this.options.stateDirectory) {
        await rm(resolve(this.options.stateDirectory, source + '.json'), { force: true }).catch(() => {});
      }
      return { source, removed: true };
    });
    this.mutation = action.catch(() => {});
    return action;
  }

  async rollback(source: string) {
    const previous = this.registry.previous(source);
    if (!previous) throw new HostError('CONFIG', 'no previous plugin version');
    return this.install(
      source,
      previous.packagePath,
      previous.manifest,
      sha256(await readFile(previous.packagePath)),
      previous.origin,
    );
  }

  async setEnabled(source: string, enabled: boolean) {
    if (!enabled) await this.dispose(source);
    const result = this.registry.setEnabled(source, enabled);
    await this.registry.flush();
    return result;
  }

  mediaContext(source: string, row: unknown): string | undefined {
    const registered = this.registry.get(source);
    if (!registered?.enabled) throw new HostError('CONFIG', 'source disabled');
    const key = row && typeof row === 'object' ? this.mediaContexts.get(row) : undefined;
    if (!key) return undefined;
    const resource = this.mediaResources.get(key);
    if (!resource || resource.source !== source) {
      throw new HostError('BLOCKED', 'media context is not an authorized invocation result');
    }
    if (resource.expiresAt <= Date.now()) {
      this.mediaResources.delete(key);
      throw new HostError('TIMEOUT', 'media context expired');
    }
    // Sliding TTL extension on active consumption
    resource.expiresAt = Date.now() + 2 * 3600 * 1000;
    return key;
  }

  async fetchResource(
    source: string,
    url: string,
    options: {
      signal?: AbortSignal;
      range?: string;
      method?: 'GET' | 'HEAD';
      mediaContext?: string;
      image?: boolean;
    } = {},
  ): Promise<Response> {
    const r = this.registry.get(source);
    if (!r?.enabled) throw new HostError('CONFIG', 'source disabled');
    const target = new URL(url);
    const resource = options.mediaContext ? this.mediaResources.get(options.mediaContext) : undefined;
    if (options.mediaContext && (!resource || resource.source !== source)) {
      throw new HostError('BLOCKED', 'media context is invalid');
    }
    if (resource && resource.expiresAt <= Date.now()) {
      this.mediaResources.delete(options.mediaContext!);
      throw new HostError('TIMEOUT', 'media context expired');
    }
    if (resource) {
      resource.expiresAt = Date.now() + 2 * 3600 * 1000;
    }
    const sameOrigin = resource && new URL(resource.url).origin === target.origin;
    const domains = !options.image
      ? [...r.manifest.domains, ...(r.manifest.media?.domains ?? []), ...(r.manifest.imageNetwork?.domains ?? [])]
      : undefined;
    const supplied = options.image ? (r.manifest.imageHeaders ?? {}) : resource?.image ? {} : (resource?.headers ?? {});
    const headers = mediaRequestHeaders(r.manifest, supplied, options.image === true);
    for (const key of Object.keys(headers)) {
      if (key.startsWith('x-') && !sameOrigin) delete headers[key];
    }
    if (options.range) headers.range = options.range;

    const routeKey = `${source}|${target.hostname.toLowerCase()}`;
    const browser = async () => {
      try {
        if (!this.browserExecutor) throw new HostError('UNSUPPORTED', 'browser resource executor is unavailable');
        await validateNetworkUrl(url, resource?.session || options.image ? undefined : domains);
        const imageOrigin = r.manifest.imageNetwork?.origin ? new URL(r.manifest.imageNetwork.origin) : undefined;
        const imageSession =
          options.image === true &&
          r.manifest.imageNetwork?.mode === 'browser' &&
          imageOrigin?.origin === target.origin &&
          hostAllowed(imageOrigin.hostname, r.manifest.domains);
        const result = await this.browserExecutor.request({
          source,
          manifest: r.manifest,
          request: {
            url,
            method: options.method ?? 'GET',
            headers,
            responseType: 'base64',
            signal: options.signal,
            mode: 'browser',
          },
          cookies: imageSession ? await this.browserCookies(source) : [],
          resource: true,
          image: options.image === true,
          session: resource?.session === true,
        });
        if (imageSession && result.cookies) {
          await this.syncBrowserCookies(r.manifest, await this.privateState(source), result.cookies);
        }
        await validateNetworkUrl(result.url, resource?.session || options.image ? undefined : domains);
        const bytes = Buffer.from(result.body, 'base64');
        if (options.image && result.status >= 200 && result.status < 300 && options.method !== 'HEAD') {
          const decoded = decodeImage(bytes, r.manifest.imageDecrypt);
          this.browserImageRoutes.add(routeKey);
          const outHeaders = new Headers(result.headers);
          outHeaders.set('content-type', decoded.mime);
          outHeaders.set('content-length', String(decoded.bytes.length));
          outHeaders.set('x-hp-image-decoded', '1');
          const response = new Response(new Uint8Array(decoded.bytes), { status: result.status, headers: outHeaders });
          Object.defineProperty(response, 'url', { value: result.url });
          return response;
        }
        const response = new Response(
          options.method === 'HEAD' || [204, 205, 304].includes(result.status) ? null : bytes,
          { status: result.status, headers: result.headers },
        );
        Object.defineProperty(response, 'url', { value: result.url });
        return response;
      } catch (error) {
        throw runnerError(options.signal?.aborted ? toAbortError(options.signal) : toPluginError(error));
      }
    };

    if (!options.image && r.manifest.media?.mode === 'browser') return browser();
    const fallback = options.image && r.manifest.imageNetwork?.mode === 'browser' && this.browserExecutor !== undefined;
    // Align with Android ImageStore._browserRoutes: skip redundant failing native requests once browser route is proven for this host
    if (fallback && this.browserImageRoutes.has(routeKey)) {
      return browser();
    }

    try {
      const response = await fetchPinnedResource(url, resource?.session ? undefined : domains, {
        signal: options.signal,
        method: options.method,
        headers,
        allowPort: options.image === true,
      });
      if (!options.image) return response;
      if (!response.ok) {
        if (!fallback) return response;
        await response.body?.cancel();
        return browser();
      }
      if (options.method === 'HEAD') return response;
      const reader = response.body?.getReader();
      const parts: Uint8Array[] = [];
      let size = 0;
      try {
        if (reader) {
          for (;;) {
            const next = await reader.read();
            if (next.done) break;
            size += next.value.length;
            if (size > 20 * 1024 * 1024) throw new HostError('PARSE', 'image response limit');
            parts.push(next.value);
          }
        }
      } finally {
        await reader?.cancel().catch(() => {});
      }
      const bytes = Buffer.concat(parts);
      // Decode & decrypt once and return the ready-to-serve plaintext image (eliminates double AES decryption in MediaProxy)
      const decoded = decodeImage(bytes, r.manifest.imageDecrypt);
      const outHeaders = new Headers(response.headers);
      outHeaders.set('content-type', decoded.mime);
      outHeaders.set('content-length', String(decoded.bytes.length));
      outHeaders.set('x-hp-image-decoded', '1');
      const result = new Response(new Uint8Array(decoded.bytes), { status: response.status, headers: outHeaders });
      Object.defineProperty(result, 'url', { value: response.url });
      return result;
    } catch (error) {
      if (!fallback || options.signal?.aborted || ['BLOCKED', 'CONFIG'].includes(toPluginError(error).code)) {
        throw runnerError(options.signal?.aborted ? toAbortError(options.signal) : toPluginError(error));
      }
      return browser();
    }
  }

  async setCookies(
    source: string,
    cookies: Array<{
      name: string;
      value: string;
      domain: string;
      path?: string;
      expires?: number;
      secure?: boolean;
      httpOnly?: boolean;
      sameSite?: 'Strict' | 'Lax' | 'None';
    }>,
  ) {
    const r = this.registry.get(source);
    if (!r) throw new HostError('CONFIG', 'source not registered');
    const state = await this.privateState(source);
    for (const c of cookies) {
      const domain = c.domain.replace(/^\./, '');
      if (!hostAllowed(domain, r.manifest.domains)) continue;
      const cookie = new Cookie({
        key: c.name,
        value: c.value,
        domain,
        hostOnly: !c.domain.startsWith('.'),
        path: c.path ?? '/',
        secure: true,
        httpOnly: c.httpOnly,
        sameSite: c.sameSite?.toLowerCase(),
        expires: c.expires && c.expires > 0 ? new Date(c.expires * 1000) : 'Infinity',
      });
      await state.jar.setCookie(cookie, 'https://' + domain + '/', { ignoreError: true });
    }
    await this.persistState(source);
    await this.dispose(source);
  }

  async browserCookies(source: string) {
    const record = this.registry.get(source);
    if (!record?.enabled) throw new HostError('CONFIG', 'source disabled');
    const state = await this.privateState(source);
    const cookies: Array<{
      name: string;
      value: string;
      domain: string;
      path: string;
      expires: number;
      httpOnly: boolean;
      secure: boolean;
      sameSite?: 'Strict' | 'Lax' | 'None';
    }> = [];
    for (const value of state.jar.serializeSync()!.cookies) {
      const cookie = Cookie.fromJSON(value);
      if (!cookie?.domain || !hostAllowed(cookie.domain, record.manifest.domains)) continue;
      const expires = cookie.expiryTime() ?? Infinity;
      if (expires <= Date.now()) continue;
      cookies.push({
        name: cookie.key,
        value: cookie.value,
        domain: cookie.hostOnly ? cookie.domain : '.' + cookie.domain,
        path: cookie.path ?? '/',
        expires: Number.isFinite(expires) ? expires / 1000 : -1,
        httpOnly: cookie.httpOnly,
        secure: true,
        ...(cookie.sameSite
          ? { sameSite: ({ strict: 'Strict', lax: 'Lax', none: 'None' } as const)[cookie.sameSite as 'strict' | 'lax' | 'none'] }
          : {}),
      });
    }
    return cookies;
  }

  async finishReverseSearch(
    source: string,
    page: { url: string; html: string },
    options: { signal?: AbortSignal; timeoutMs?: number } = {},
  ) {
    return this.withSourceExecution(source, options, async (signal) => {
      const record = this.registry.get(source);
      if (!record?.enabled || record.manifest.capabilities?.reverseSearch !== true) {
        throw new HostError('UNSUPPORTED', 'reverse search is unavailable');
      }
      if (
        !page ||
        typeof page.url !== 'string' ||
        page.url.length > 8192 ||
        typeof page.html !== 'string' ||
        !page.html.length ||
        Buffer.byteLength(page.html, 'utf8') > 4 * 1024 * 1024
      ) {
        throw new HostError('CONFIG', 'invalid reverse search page');
      }
      await validateNetworkUrl(page.url, record.manifest.domains);
      const state = await this.privateState(source);
      if (signal.aborted) throw runnerError(toAbortError(signal));
      const entry = await this.reserveClient(record.manifest, record.packagePath, state, signal);
      try {
        return await entry.client.request(
          'reverseSearchResult',
          { page, expectedManifest: record.manifest, stateSnapshot: { data: state.data, settings: state.settings } },
          options.timeoutMs,
          signal,
        );
      } catch (error) {
        throw toPluginError(error);
      } finally {
        this.releaseRunnerSlot(entry);
      }
    });
  }

  async filterOptions(
    source: string,
    input: Record<string, unknown>,
    options: { signal?: AbortSignal; timeoutMs?: number } = {},
  ) {
    return this.withSourceExecution(source, options, async (signal) => {
      const record = this.registry.get(source);
      if (!record?.enabled) throw new HostError('CONFIG', 'source disabled');
      if (
        !input ||
        typeof input !== 'object' ||
        Array.isArray(input) ||
        Object.keys(input).some((key) => !['scope', 'feed', 'filter', 'keyword', 'values'].includes(key)) ||
        !['feed', 'search'].includes(String(input.scope)) ||
        typeof input.filter !== 'string'
      ) {
        throw new HostError('CONFIG', 'invalid filter query');
      }
      const manifest = record.manifest;
      const feed =
        input.scope === 'feed' && typeof input.feed === 'string'
          ? manifest.feeds?.find((value) => value.key === input.feed)
          : undefined;
      if (
        input.scope === 'feed'
          ? !feed || manifest.capabilities?.feed !== true || input.keyword !== undefined
          : input.feed !== undefined || !(manifest.capabilities?.search || manifest.capabilities?.metadataSearch)
      ) {
        throw new HostError('UNSUPPORTED', 'filter scope is not declared');
      }
      const declarations = input.scope === 'feed' ? feed?.options : manifest.searchFilters;
      const setting = declarations?.find((value) => value.key === input.filter && value.dynamic === true);
      if (!setting) throw new HostError('UNSUPPORTED', 'dynamic filter is not declared');
      if (
        (input.keyword !== undefined &&
          (typeof input.keyword !== 'string' || input.keyword.length > 512 || /[\u0000-\u001f\u007f]/.test(input.keyword))) ||
        (setting.keywordDependent && (!input.keyword || typeof input.keyword !== 'string'))
      ) {
        throw new HostError('CONFIG', 'invalid filter keyword');
      }
      const values = input.values ?? {};
      if (!values || typeof values !== 'object' || Array.isArray(values)) {
        throw new HostError('CONFIG', 'invalid filter dependencies');
      }
      const dependencies = setting.dependsOn ?? [];
      if (
        Object.keys(values).some((key) => !dependencies.includes(key)) ||
        dependencies.some((key) => !Object.hasOwn(values, key))
      ) {
        throw new HostError('CONFIG', 'filter dependencies mismatch');
      }
      for (const value of Object.values(values)) {
        if (
          typeof value === 'string'
            ? !value || value.length > 512 || /[\u0000-\u001f\u007f]/.test(value)
            : typeof value === 'number'
              ? !Number.isFinite(value)
              : typeof value !== 'boolean'
        ) {
          throw new HostError('CONFIG', 'invalid filter dependency');
        }
      }
      const state = await this.privateState(source);
      if (signal.aborted) throw runnerError(toAbortError(signal));
      const entry = await this.reserveClient(manifest, record.packagePath, state, signal);
      try {
        return await entry.client.request(
          'filterOptions',
          {
            query: {
              scope: input.scope,
              filter: setting.key,
              values,
              ...(feed ? { feed: feed.key } : {}),
              ...(input.keyword === undefined ? {} : { keyword: input.keyword }),
            },
            expectedManifest: manifest,
            stateSnapshot: { data: state.data, settings: state.settings },
          },
          options.timeoutMs,
          signal,
        );
      } catch (error) {
        throw toPluginError(error);
      } finally {
        this.releaseRunnerSlot(entry);
      }
    });
  }

  async getSettings(source: string): Promise<{ settings: Record<string, unknown>; version: number; updatedAt: string }> {
    if (this.accountTransactions.has(source)) throw new HostError('RATE_LIMITED', 'account update is in progress');
    const record = this.registry.get(source);
    if (!record) throw new HostError('CONFIG', 'source not registered');
    const state = await this.privateState(source);
    const defaults = Object.fromEntries(
      (record.manifest.settings ?? [])
        .filter((setting) => setting.default !== undefined)
        .map((setting) => [setting.key, setting.default]),
    );
    return {
      settings: structuredClone({ ...defaults, ...state.settings }),
      version: state.settingsVersion,
      updatedAt: state.settingsUpdatedAt,
    };
  }

  async updateSettings(
    source: string,
    settings: Record<string, unknown>,
    version: number,
  ): Promise<{ settings: Record<string, unknown>; version: number; updatedAt: string }> {
    const action = this.mutation.then(async () => {
      const record = this.registry.get(source);
      if (!record) throw new HostError('CONFIG', 'source not registered');
      validateSourceSettings(record.manifest, settings);
      const current = await this.privateState(source);
      if (!Number.isSafeInteger(version) || version !== current.settingsVersion) {
        throw new HostError('CONFIG', 'source settings version conflict', { reason: 'SETTINGS_CONFLICT' });
      }
      await this.dispose(source);
      const next = {
        ...current,
        settings: structuredClone(settings),
        settingsVersion: current.settingsVersion + 1,
        settingsUpdatedAt: isDeepStrictEqual(current.settings, settings) ? current.settingsUpdatedAt : new Date().toISOString(),
      };
      this.privateStates.set(source, next);
      try {
        await this.persistState(source);
      } catch (error) {
        this.privateStates.set(source, current);
        throw error;
      }
      return this.getSettings(source);
    });
    this.mutation = action.catch(() => {});
    return action;
  }

  async account(
    source: string,
    operation: 'login' | 'status' | 'logout' | 'enableManaged',
    values: Record<string, string> = {},
    options: { signal?: AbortSignal; timeoutMs?: number; internalTransaction?: boolean } = {},
  ) {
    if (this.accountTransactions.has(source) && !options.internalTransaction) {
      throw new HostError('RATE_LIMITED', 'account update is in progress');
    }
    const r = this.registry.get(source);
    if (!r?.enabled || !r.manifest.account) throw new HostError('UNSUPPORTED', 'source account is unavailable');
    if (operation === 'enableManaged' && r.manifest.account.managedAccount !== true) {
      throw new HostError('UNSUPPORTED', 'managed account is not declared');
    }
    const state = await this.privateState(source);
    if (operation !== 'status') await this.dispose(source);
    let client = new SourceRunnerClient(
      this.runnerPath,
      r.packagePath,
      this.sourceBroker(r.manifest, state),
      this.options.runtimePath,
      (op, args) => this.native(source, r.manifest, op, args),
    );
    try {
      const methods = (await client.request('accountMethods', {}, options.timeoutMs, options.signal)) as Record<string, boolean>;
      if (!methods[operation] && operation === 'login' && r.manifest.account.type === 'cookies' && r.manifest.account.cookieUrl) {
        const cookieUrl = (await validateNetworkUrl(r.manifest.account.cookieUrl, r.manifest.domains)).target;
        const entries = Object.entries(values).filter(
          ([key, value]) =>
            /^[!#$%&'*+.^_`|~0-9A-Za-z-]{1,128}$/.test(key) &&
            typeof value === 'string' &&
            value.length <= 16384 &&
            !/[\r\n\u0000-\u001f\u007f;]/.test(value),
        );
        if (!entries.length || entries.length > 200) throw new HostError('CONFIG', 'invalid cookie account');
        const next = CookieJar.deserializeSync(state.jar.serializeSync()!);
        for (const [key, value] of entries) {
          await next.setCookie(
            new Cookie({
              key,
              value,
              domain: cookieUrl.hostname,
              hostOnly: false,
              path: '/',
              secure: true,
              maxAge: 31536000,
            }),
            cookieUrl.href,
            { ignoreError: true },
          );
        }
        const previous = state.jar;
        state.jar = next;
        try {
          await this.persistState(source);
        } catch (error) {
          state.jar = previous;
          throw error;
        }
        await client.close();
        client = new SourceRunnerClient(
          this.runnerPath,
          r.packagePath,
          this.sourceBroker(r.manifest, state),
          this.options.runtimePath,
          (op, args) => this.native(source, r.manifest, op, args),
        );
      }
      let result: Record<string, unknown>;
      if (!methods[operation]) {
        if (operation === 'enableManaged' || (operation === 'login' && !(r.manifest.account.type === 'cookies' && r.manifest.account.cookieUrl))) {
          throw new HostError('UNSUPPORTED', 'account method is not implemented');
        }
        if (operation !== 'logout' && methods.status) {
          result = (await client.request(
            'account',
            { operation: 'status', values: {}, stateSnapshot: { data: state.data, settings: state.settings }, expectedManifest: r.manifest },
            options.timeoutMs,
            options.signal,
          )) as Record<string, unknown>;
        } else {
          const cookies = state.jar.serializeSync()!.cookies;
          const required = r.manifest.account.requiredCookies ?? [];
          const configured = required.length
            ? required.every((name) => cookies.some((cookie) => cookie.key === name && cookie.value))
            : cookies.length > 0;
          result = { loggedIn: operation !== 'logout' && configured, configured, verified: configured };
        }
      } else {
        result = (await client.request(
          'account',
          { operation, values, stateSnapshot: { data: state.data, settings: state.settings }, expectedManifest: r.manifest },
          options.timeoutMs,
          options.signal,
        )) as Record<string, unknown>;
      }
      if (operation === 'logout') {
        state.jar.removeAllCookiesSync();
        const accountData = state.data as Record<string, unknown>;
        state.data =
          r.manifest.account.managedAccount && accountData.managedAccount
            ? { managedAccount: { ...(accountData.managedAccount as Record<string, unknown>), token: null } }
            : {};
        if (r.manifest.account.managedAccount && state.settings.managedAccount === true) {
          state.settings = { ...state.settings, managedAccount: false };
          state.settingsVersion++;
          state.settingsUpdatedAt = new Date().toISOString();
        }
        await this.persistState(source);
      }
      return {
        loggedIn: result?.loggedIn === true,
        verified: result?.verified !== false,
        ...(typeof result?.configured === 'boolean' ? { configured: operation === 'logout' ? false : result.configured } : {}),
        ...(typeof result?.name === 'string' ? { name: result.name.slice(0, 256) } : {}),
      };
    } finally {
      await client.close();
    }
  }

  async loginBrowser(
    source: string,
    cookies: SourceBrowserCookie[],
    values: Record<string, string>,
    options: { signal?: AbortSignal; timeoutMs?: number } = {},
  ) {
    const action = this.mutation.then(async () => {
      const record = this.registry.get(source);
      if (!record?.enabled || !record.manifest.account) throw new HostError('UNSUPPORTED', 'account is unavailable');
      await this.dispose(source);
      await this.stateWriting;
      const previous = await this.privateState(source);
      const staged = {
        jar: new CookieJar(),
        data: structuredClone(previous.data),
        settings: structuredClone(previous.settings),
        settingsVersion: previous.settingsVersion,
        settingsUpdatedAt: previous.settingsUpdatedAt,
      };
      this.accountTransactions.add(source);
      this.stagedPrivateWrites.add(source);
      this.privateStates.set(source, staged);
      try {
        await this.setCookies(source, cookies);
        const result = await this.account(source, 'login', values, { ...options, internalTransaction: true });
        if (!result.loggedIn && !(result.verified === false && result.configured === true)) {
          throw new HostError('LOGIN_REQUIRED', 'browser account was not verified');
        }
        this.stagedPrivateWrites.delete(source);
        await this.persistState(source);
        return result;
      } catch (error) {
        this.privateStates.set(source, previous);
        await this.dispose(source);
        throw error;
      } finally {
        this.stagedPrivateWrites.delete(source);
        this.accountTransactions.delete(source);
      }
    });
    this.mutation = action.catch(() => {});
    return action;
  }

  async exportPrivateState(source: string, options: { includeAccounts?: boolean; includeCookies?: boolean } = {}) {
    if (this.accountTransactions.has(source)) throw new HostError('RATE_LIMITED', 'account update is in progress');
    if (!this.registry.get(source)) throw new HostError('CONFIG', 'source not registered');
    const state = await this.privateState(source);
    return {
      source,
      ...(options.includeAccounts ? { data: structuredClone(state.data), settings: structuredClone(state.settings) } : {}),
      ...(options.includeCookies ? { cookies: state.jar.serializeSync() } : {}),
    };
  }

  async subscriptionContext(source: string): Promise<string> {
    if (this.accountTransactions.has(source)) throw new HostError('RATE_LIMITED', 'account update is in progress');
    const record = this.registry.get(source);
    if (!record) throw new HostError('CONFIG', 'source not registered');
    const state = await this.privateState(source);
    const transient = new Set(['expires', 'expiresat', 'expiry', 'retryat', 'failures', 'ratelimited', 'updatedat']);
    const canonical = (value: unknown): unknown =>
      Array.isArray(value)
        ? value.map(canonical)
        : value && typeof value === 'object'
          ? Object.fromEntries(
              Object.entries(value)
                .filter(([key]) => !transient.has(key.toLowerCase().replace(/_/g, '')))
                .sort(([a], [b]) => a.localeCompare(b))
                .map(([key, item]) => [key, canonical(item)]),
            )
          : value;
    const stableKeys = new Set(['id', 'uid', 'userid', 'accountid', 'email', 'username', 'handle']);
    const principal = (value: unknown, depth = 0): Record<string, unknown> => {
      const out: Record<string, unknown> = {};
      if (!value || typeof value !== 'object' || Array.isArray(value) || depth > 3) return out;
      for (const [key, item] of Object.entries(value).sort(([a], [b]) => a.localeCompare(b))) {
        const normalized = key.toLowerCase().replace(/_/g, '');
        if (stableKeys.has(normalized) && ((typeof item === 'string' && item.length > 0) || (typeof item === 'number' && Number.isFinite(item)))) {
          out[key] = item;
        } else if (['user', 'account', 'profile', 'identity'].includes(normalized)) {
          const nested = principal(item, depth + 1);
          if (Object.keys(nested).length) out[key] = nested;
        }
      }
      return out;
    };
    const data = state.data && typeof state.data === 'object' && !Array.isArray(state.data) ? (state.data as Record<string, unknown>) : {};
    const credentials = Object.entries(data)
      .filter(([key]) => /credential|account|user|session|token|auth/i.test(key))
      .sort(([a], [b]) => a.localeCompare(b));
    const identities = Object.fromEntries(
      credentials
        .map(([key, value]) => [key, principal(value)])
        .filter(([, value]) => Object.keys(value).length),
    );
    const reliable = Object.keys(identities).length > 0;
    const cookies = reliable
      ? []
      : state.jar
          .serializeSync()!
          .cookies.filter((cookie) =>
            record.manifest.account?.requiredCookies?.length
              ? record.manifest.account.requiredCookies.includes(String(cookie.key))
              : Boolean(record.manifest.account) || credentials.length > 0,
          )
          .map((cookie) => [cookie.domain, cookie.path, cookie.key, cookie.value])
          .sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b)));
    const authorization = reliable ? identities : Object.fromEntries(credentials.map(([key, value]) => [key, canonical(value)]));
    const settings = Object.fromEntries(Object.entries(state.settings).sort(([a], [b]) => a.localeCompare(b)));
    return sha256(JSON.stringify([record.manifest.version, settings, authorization, cookies]));
  }

  async preparePrivateState(source: string, payload: unknown, options: PrivateStateOptions = {}) {
    const record = this.registry.get(source);
    if (!record) throw new HostError('CONFIG', 'source not registered');
    validatePrivateState(record.manifest, payload, options);
  }

  async importPrivateState(source: string, payload: unknown, options: { includeAccounts?: boolean; includeCookies?: boolean } = {}) {
    const record = this.registry.get(source);
    if (!record) throw new HostError('CONFIG', 'source not registered');
    validatePrivateState(record.manifest, payload, options);
    const value = payload as Record<string, unknown>;
    const current = await this.privateState(source);
    const changed = options.includeAccounts && value.settings !== undefined && !isDeepStrictEqual(current.settings, value.settings);
    const next = {
      jar: CookieJar.deserializeSync(current.jar.serializeSync()!),
      data: structuredClone(current.data),
      settings: structuredClone(current.settings),
      settingsVersion: current.settingsVersion + (changed ? 1 : 0),
      settingsUpdatedAt: changed ? new Date().toISOString() : current.settingsUpdatedAt,
    };
    if (options.includeAccounts) {
      if (value.data !== undefined) next.data = structuredClone(value.data);
      if (value.settings !== undefined) {
        if (!value.settings || typeof value.settings !== 'object' || Array.isArray(value.settings)) {
          throw new HostError('CONFIG', 'invalid private settings');
        }
        next.settings = structuredClone(value.settings) as Record<string, unknown>;
      }
    }
    if (options.includeCookies && value.cookies !== undefined) {
      next.jar = CookieJar.deserializeSync(value.cookies as Parameters<typeof CookieJar.deserializeSync>[0]);
      for (const cookie of next.jar.serializeSync()!.cookies) {
        if (typeof cookie.domain !== 'string' || !hostAllowed(cookie.domain.replace(/^\./, ''), record.manifest.domains)) {
          throw new HostError('BLOCKED', 'private backup contains out of source cookies');
        }
      }
    }
    await this.dispose(source);
    this.privateStates.set(source, next);
    try {
      await this.persistState(source);
    } catch (error) {
      this.privateStates.set(source, current);
      throw error;
    }
    return { source, restored: true };
  }

  async recover() {
    const pending = this.journal.pending();
    for (const record of pending) {
      if (record.from !== undefined && !record.previous) {
        throw new HostError('CONFIG', 'prepared installation is missing its previous registry snapshot');
      }
    }
    for (const r of pending) {
      this.registry.rollbackWrite(r.source, r.previous);
      await this.registry.flush();
      this.journal.rollback(r);
    }
    await this.journal.flush();
    return pending;
  }

  async reapIdle(now = Date.now()) {
    return this.withPool(async () => {
      const removed: string[] = [];
      for (const [source, entry] of this.clients) {
        if (!entry.active && now - entry.lastUsed >= this.idleMs) {
          await this.closeEntry(source, entry);
          removed.push(source);
        }
      }
      return removed;
    });
  }

  async dispose(source?: string) {
    for (const [key, queue] of this.sourceExecutions) {
      if (source === undefined || key === source) {
        queue.controller.abort(new HostError('CANCELLED', 'source disposed'));
      }
    }
    if (source) {
      for (const routeKey of [...this.browserImageRoutes]) {
        if (routeKey.startsWith(`${source}|`)) this.browserImageRoutes.delete(routeKey);
      }
    } else {
      this.browserImageRoutes.clear();
    }
    await this.browserExecutor?.dispose?.(source);
    return this.withPool(async () => {
      if (source) {
        for (const [key, resource] of this.mediaResources) {
          if (resource.source === source) this.mediaResources.delete(key);
        }
        const entry = this.clients.get(source);
        if (entry) await this.closeEntry(source, entry);
        this.stores.clear(source);
        return;
      }
      clearInterval(this.idleTimer);
      this.idleTimer = undefined;
      while (this.poolWaiters.length) {
        const w = this.poolWaiters.shift();
        w?.cancel();
      }
      await Promise.all([...this.clients.entries()].map(([key, entry]) => this.closeEntry(key, entry)));
      this.mediaResources.clear();
      this.stores.clearAll();
    });
  }
}

function compatible(actual: string, required: string) {
  const a = actual.split(/[.-]/).slice(0, 3).map(Number);
  const r = required.split(/[.-]/).slice(0, 3).map(Number);
  for (let i = 0; i < 3; i++) {
    if (a[i]! > r[i]!) return true;
    if (a[i]! < r[i]!) return false;
  }
  return true;
}

export const isCompatibleVersion = compatible;
export function sha256(value: Uint8Array | string) {
  return createHash('sha256').update(value).digest('hex');
}

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
  add(e: PluginIndexEntry) {
    validateManifest(e.manifest);
    if (
      e.source !== e.manifest.key ||
      e.version !== e.manifest.version ||
      e.minAppVersion !== e.manifest.minAppVersion ||
      !/^[a-f0-9]{64}$/.test(e.sha256)
    ) {
      throw new HostError('INVALID_MANIFEST', 'invalid index');
    }
    this.entries.set(e.source, e);
    return e;
  }
  get(source: string) {
    return this.entries.get(source);
  }
  list() {
    return [...this.entries.values()];
  }
  remove(source: string) {
    this.entries.delete(source);
  }
  async verify(source: string, bytes: Uint8Array | string) {
    const e = this.entries.get(source);
    if (!e || sha256(bytes) !== e.sha256) throw new HostError('INVALID_MANIFEST', 'checksum mismatch');
    return true;
  }
}

export function permissionChanges(previous: PluginManifest | undefined, next: PluginManifest) {
  const permissions = (m?: PluginManifest) =>
    m
      ? [
          ...m.domains.map((v) => `network:${v}`),
          ...(m.media?.domains ?? []).map((v) => `media:${v}`),
          ...(m.imageNetwork?.domains ?? []).map((v) => `image:${v}`),
          ...(m.navigationDomains ?? []).map((v) => `navigation:${v}`),
          ...(m.frameDomains ?? []).map((v) => `frame:${v}`),
          ...(m.account?.loginDomains ?? []).map((v) => `login:${v}`),
          ...(m.chat?.domains ?? []).map((v) => `chat:${v}`),
          ...(m.media?.referrerDomains ?? []).map((v) => `media-referrer:${v}`),
          ...(m.media?.requestHeaders
            ? Object.entries(m.media.requestHeaders).map(([name, rule]) => `media-header:${name}:${rule.scope}`)
            : []),
          ...(m.network?.mode ? [`network-mode:${m.network.mode}`] : []),
          ...(m.media ? [`media-mode:${m.media.mode}`, `media-scope:${m.media.scope ?? 'domains'}`] : []),
          ...(m.imageNetwork ? [`image-mode:${m.imageNetwork.mode}`] : []),
          ...(m.account
            ? [
                `account:${m.account.type}`,
                ...(m.account.managedAccount ? ['account:managed'] : []),
                ...(m.account.localStorageKeys ?? []).map((v) => `account-storage:${v}`),
              ]
            : []),
          ...Object.keys(m.capabilities ?? {}).filter((k) => m.capabilities?.[k as keyof typeof m.capabilities] === true),
        ]
      : [];
  const before = new Set(permissions(previous));
  const after = new Set(permissions(next));
  return {
    added: [...after].filter((v) => !before.has(v)).sort(),
    removed: [...before].filter((v) => !after.has(v)).sort(),
  };
}

export interface SourceRegistryRecord {
  source: string;
  version: string;
  packagePath: string;
  manifest: PluginManifest;
  enabled: boolean;
  updatedAt: string;
  crashed?: boolean;
  sha256?: string;
  origin?: { url: string; repository?: string; official?: boolean };
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

async function atomicWrite(filePath: string, data: string | Uint8Array) {
  await mkdir(dirname(filePath), { recursive: true });
  const temporary = `${filePath}.${randomUUID()}.tmp`;
  try {
    await writeFile(temporary, data, { encoding: typeof data === 'string' ? 'utf8' : undefined, flush: true });
    await rename(temporary, filePath);
  } catch (error) {
    await unlink(temporary).catch(() => {});
    throw error;
  }
}

async function immutableArtifact(filePath: string, bytes: Uint8Array, digest: string) {
  let existing: Buffer | undefined;
  try {
    existing = await readFile(filePath);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
  }
  if (existing) {
    if (sha256(existing) !== digest) {
      throw new HostError('INVALID_MANIFEST', 'existing immutable plugin artifact checksum mismatch');
    }
    return;
  }
  await atomicWrite(filePath, bytes);
}

function artifactReference(record: SourceRegistryRecord): { file: string; digest: string } {
  if (!record || typeof record.packagePath !== 'string') {
    throw new HostError('CONFIG', 'installed plugin reference is invalid');
  }
  const file = record.packagePath.replace(/\\/g, '/').split('/').at(-1)!;
  if (!/^[a-f0-9]{64}\.js$/.test(file)) {
    throw new HostError('INVALID_MANIFEST', 'installed plugin reference must be an immutable SHA-256 filename');
  }
  const digest = file.slice(0, -3);
  if (record.sha256 !== undefined && record.sha256 !== digest) {
    throw new HostError('INVALID_MANIFEST', 'installed plugin reference checksum mismatch');
  }
  return { file, digest };
}

function storedRecord(record: SourceRegistryRecord): SourceRegistryRecord {
  const { file, digest } = artifactReference(record);
  return { ...record, packagePath: file, sha256: digest };
}

async function relocatedRecord(value: unknown, directory: string | undefined): Promise<SourceRegistryRecord> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new HostError('CONFIG', 'invalid source registry record');
  }
  const record = value as SourceRegistryRecord;
  validateManifest(record.manifest);
  if (record.source !== record.manifest.key || record.version !== record.manifest.version || typeof record.enabled !== 'boolean') {
    throw new HostError('INVALID_MANIFEST', 'source registry identity is invalid');
  }
  const { file, digest } = artifactReference(record);
  if (!directory) throw new HostError('CONFIG', 'plugin directory must be configured before loading state');
  const packagePath = resolve(directory, file);
  let bytes: Buffer;
  try {
    bytes = await readFile(packagePath);
  } catch {
    throw new HostError('CONFIG', 'installed plugin artifact is missing or unreadable: ' + file, {
      source: record.source,
      reason: 'MISSING_ARTIFACT',
    });
  }
  if (sha256(bytes) !== digest) {
    throw new HostError('INVALID_MANIFEST', 'installed plugin artifact checksum mismatch: ' + file, {
      source: record.source,
      reason: 'CHECKSUM_MISMATCH',
    });
  }
  return { ...record, packagePath, sha256: digest };
}

async function readStateFile(filePath: string): Promise<unknown | undefined> {
  let raw: string;
  try {
    raw = await readFile(filePath, 'utf8');
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') return undefined;
    throw error;
  }
  return JSON.parse(raw);
}

class DurableState {
  protected dirty = false;
  protected loaded = false;
  protected artifactDirectory?: string;
  private writing: Promise<unknown> = Promise.resolve();
  constructor(
    protected readonly filePath?: string,
    pluginDirectory?: string,
  ) {
    this.artifactDirectory = pluginDirectory
      ? resolve(pluginDirectory)
      : filePath
        ? resolve(dirname(filePath), 'plugins')
        : undefined;
  }
  get pluginDirectory() {
    return this.artifactDirectory;
  }
  bindPluginDirectory(directory: string) {
    const target = resolve(directory);
    if (this.loaded && this.artifactDirectory && this.artifactDirectory !== target) {
      throw new HostError('CONFIG', 'plugin directory must be configured before loading state');
    }
    this.artifactDirectory = target;
  }
  protected snapshot(): unknown {
    return null;
  }
  async flush() {
    if (!this.filePath) return;
    const targetPath = this.filePath;
    const data = JSON.stringify(this.snapshot());
    const action = this.writing.then(() => atomicWrite(targetPath, data));
    this.writing = action.catch(() => {});
    await action;
    this.dirty = false;
  }
}

export class InstallationJournal extends DurableState {
  readonly records: InstallRecord[] = [];
  protected override snapshot() {
    return this.records.map((record) => ({
      ...record,
      ...(record.previous ? { previous: storedRecord(record.previous) } : {}),
      ...(record.next ? { next: storedRecord(record.next) } : {}),
    }));
  }
  async load() {
    if (!this.filePath) return;
    const data = await readStateFile(this.filePath);
    if (data === undefined) {
      this.loaded = true;
      return;
    }
    if (!Array.isArray(data)) throw new HostError('CONFIG', 'invalid installation journal');
    const records: InstallRecord[] = [];
    for (const value of data) {
      if (
        !value ||
        typeof value !== 'object' ||
        !['prepared', 'committed', 'rolled_back'].includes(value.status) ||
        typeof value.id !== 'string' ||
        typeof value.source !== 'string'
      ) {
        throw new HostError('CONFIG', 'invalid installation journal');
      }
      const previous = value.previous === undefined ? undefined : await relocatedRecord(value.previous, this.artifactDirectory);
      const next = value.next === undefined ? undefined : await relocatedRecord(value.next, this.artifactDirectory);
      if (
        (previous && (previous.source !== value.source || value.from !== previous.version)) ||
        (next && (next.source !== value.source || value.to !== next.version || (value.sha256 !== undefined && value.sha256 !== next.sha256)))
      ) {
        throw new HostError('INVALID_MANIFEST', 'installation journal identity mismatch');
      }
      records.push({ ...value, ...(previous ? { previous } : {}), ...(next ? { next } : {}) });
    }
    this.records.splice(0, this.records.length, ...records);
    this.loaded = true;
    if (JSON.stringify(data) !== JSON.stringify(this.snapshot())) await this.flush();
  }
  begin(source: string, to: string, from?: string, metadata: Pick<InstallRecord, 'sha256' | 'permissions' | 'previous' | 'next'> = {}) {
    const record: InstallRecord = { id: randomUUID(), source, from, to, status: 'prepared', at: new Date().toISOString(), ...metadata };
    this.records.push(record);
    this.dirty = true;
    return record;
  }
  commit(record: InstallRecord) {
    record.status = 'committed';
    this.dirty = true;
  }
  rollback(record: InstallRecord) {
    record.status = 'rolled_back';
    this.dirty = true;
  }
  pending() {
    return this.records.filter((record) => record.status === 'prepared');
  }
  recover() {
    const pending = this.pending();
    for (const record of pending) this.rollback(record);
    return pending;
  }
}

export class SourceRegistry extends DurableState {
  private readonly records = new Map<string, SourceRegistryRecord>();
  private readonly history = new Map<string, SourceRegistryRecord[]>();
  protected override snapshot() {
    return {
      records: [...this.records.values()].map(storedRecord),
      history: [...this.history.entries()].map(([source, records]) => [source, records.map(storedRecord)]),
    };
  }
  async load() {
    if (!this.filePath) return;
    const data = await readStateFile(this.filePath);
    if (data === undefined) {
      this.loaded = true;
      return;
    }
    if (!data || typeof data !== 'object' || !('records' in data) || !Array.isArray(data.records)) {
      throw new HostError('CONFIG', 'invalid source registry');
    }
    const records = new Map<string, SourceRegistryRecord>();
    const history = new Map<string, SourceRegistryRecord[]>();
    for (const value of data.records) {
      const record = await relocatedRecord(value, this.artifactDirectory);
      if (records.has(record.source)) throw new HostError('CONFIG', 'duplicate source registry identity');
      records.set(record.source, record);
    }
    const prior = (data as { history?: unknown }).history;
    if (prior !== undefined && !Array.isArray(prior)) throw new HostError('CONFIG', 'invalid source registry history');
    if (Array.isArray(prior)) {
      for (const item of prior) {
        if (!Array.isArray(item) || item.length !== 2 || typeof item[0] !== 'string' || !Array.isArray(item[1]) || history.has(item[0])) {
          throw new HostError('CONFIG', 'invalid source registry history');
        }
        const values: SourceRegistryRecord[] = [];
        for (const value of item[1]) {
          const record = await relocatedRecord(value, this.artifactDirectory);
          if (record.source !== item[0]) throw new HostError('INVALID_MANIFEST', 'source registry history identity mismatch');
          values.push(record);
        }
        history.set(item[0], values);
      }
    }
    this.records.clear();
    this.history.clear();
    for (const [source, record] of records) this.records.set(source, record);
    for (const [source, values] of history) this.history.set(source, values);
    this.loaded = true;
    if (JSON.stringify(data) !== JSON.stringify(this.snapshot())) await this.flush();
  }
  upsert(record: SourceRegistryRecord) {
    validateManifest(record.manifest);
    const current = this.records.get(record.source);
    if (current) {
      const history = this.history.get(record.source) ?? [];
      history.push(structuredClone(current));
      this.history.set(record.source, history);
    }
    const next = { ...record, updatedAt: new Date().toISOString(), crashed: false };
    this.records.set(record.source, next);
    this.dirty = true;
    return next;
  }
  remove(source: string) {
    this.records.delete(source);
    this.history.delete(source);
    this.dirty = true;
  }
  restore(source: string, record?: SourceRegistryRecord) {
    if (record) this.records.set(source, structuredClone(record));
    else this.records.delete(source);
    this.dirty = true;
  }
  rollbackWrite(source: string, previous?: SourceRegistryRecord) {
    const history = this.history.get(source);
    if (previous && history?.length && isDeepStrictEqual(history.at(-1), previous)) history.pop();
    this.restore(source, previous);
  }
  get(source: string) {
    return this.records.get(source);
  }
  previous(source: string) {
    return this.history.get(source)?.at(-1);
  }
  restorePrevious(source: string) {
    const previous = this.history.get(source)?.pop();
    if (!previous) throw new HostError('CONFIG', 'no previous plugin version');
    this.restore(source, previous);
    return previous;
  }
  list() {
    return [...this.records.values()];
  }
  setEnabled(source: string, enabled: boolean) {
    const record = this.records.get(source);
    if (!record) throw new HostError('CONFIG', 'source not registered');
    record.enabled = enabled;
    record.updatedAt = new Date().toISOString();
    this.dirty = true;
    return record;
  }
  markCrashed(source: string) {
    const record = this.records.get(source);
    if (record) {
      record.crashed = true;
      this.dirty = true;
    }
  }
}

export interface ResourceLease {
  source: string;
  id: string;
  expiresAt: number;
  release: () => void;
}

export class ResourceLimiter {
  private readonly active = new Map<string, Set<string>>();
  constructor(
    private readonly maxPerSource = 16,
    private readonly ttlMs = 300000,
  ) {}
  acquire(source: string, now = Date.now()): ResourceLease {
    const set = this.active.get(source) ?? new Set<string>();
    if (set.size >= this.maxPerSource) throw new HostError('RATE_LIMITED', 'resource limit');
    const id = randomUUID();
    set.add(id);
    this.active.set(source, set);
    let released = false;
    return {
      source,
      id,
      expiresAt: now + this.ttlMs,
      release: () => {
        if (released) return;
        released = true;
        set.delete(id);
        if (!set.size) this.active.delete(source);
      },
    };
  }
  count(source: string) {
    return this.active.get(source)?.size ?? 0;
  }
  clear(source?: string) {
    if (source) this.active.delete(source);
    else this.active.clear();
  }
}
