// Node implementation of the Park host bridge, used to develop and test source scripts
// against the live sites without building the app.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import crypto from 'node:crypto';
import https from 'node:https';
import { fileURLToPath } from 'node:url';
import { DOMParser } from 'linkedom';

const here = path.dirname(fileURLToPath(import.meta.url));
export const repoRoot = path.resolve(here, '..', '..');

const UA =
  'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';

// ── Cookie jar (host-scoped, good enough for tests) ─────────
const jar = new Map(); // host -> Map(name -> value)

function hostOf(url) {
  return new URL(url).hostname;
}

function cookiesFor(url) {
  const host = hostOf(url);
  const out = [];
  for (const [domain, cookies] of jar) {
    if (host === domain || host.endsWith('.' + domain)) {
      for (const [k, v] of cookies) out.push(`${k}=${v}`);
    }
  }
  return out.join('; ');
}

function storeCookies(url, setCookies) {
  const host = hostOf(url);
  for (const line of setCookies) {
    const [pair, ...attrs] = line.split(';');
    const eq = pair.indexOf('=');
    if (eq < 0) continue;
    const name = pair.slice(0, eq).trim();
    const value = pair.slice(eq + 1).trim();
    const domainAttr = attrs.map((a) => a.trim()).find((a) => /^domain=/i.test(a));
    const domain = domainAttr ? domainAttr.split('=')[1].replace(/^\./, '') : host;
    if (!jar.has(domain)) jar.set(domain, new Map());
    jar.get(domain).set(name, value);
  }
}

// ── Native bridge ───────────────────────────────────────────
export const persisted = {};
export const logs = [];

const errorCodes = new Set(['NETWORK', 'TIMEOUT', 'AUTH', 'PARSE', 'CONFIG', 'UNSUPPORTED', 'HTTP', 'CANCELLED', 'UNKNOWN', 'CONFIRM_REQUIRED', 'CLOUDFLARE', 'LOGIN_REQUIRED', 'NOT_FOUND', 'BLOCKED']);
const failureReasons = new Set(['TLS_CERTIFICATE', 'TLS_HANDSHAKE_TERMINATED', 'TLS_HANDSHAKE', 'CONNECT_TIMEOUT', 'RECEIVE_TIMEOUT', 'SEND_TIMEOUT', 'DNS', 'CONNECTION', 'RESPONSE_STREAM', 'NETWORK', 'CANCELLED', 'UNKNOWN']);
export function diagnosticMessage(value) {
  if (!value || typeof value !== 'object') return 'event=message';
  const fields = ['event=source'];
  if (errorCodes.has(value.code)) fields.push(`code=${value.code}`);
  if (['native', 'browser'].includes(value.transport)) fields.push(`transport=${value.transport}`);
  if (failureReasons.has(value.reason)) fields.push(`reason=${value.reason}`);
  if (typeof value.host === 'string' && value.host.length <= 253 && /^(?:[a-zA-Z0-9-]+\.)*[a-zA-Z0-9-]+$/.test(value.host)) fields.push(`host=${value.host}`);
  return fields.join(' ');
}

const native = {
  async request(o) {
    const headers = { 'User-Agent': UA, ...o.headers };
    const cookie = cookiesFor(o.url);
    if (cookie && !Object.keys(headers).some((k) => k.toLowerCase() === 'cookie')) headers.Cookie = cookie;
    let res;
    try {
      const options = {
        method: o.method,
        headers,
        body: o.bodyBase64 === undefined ? o.body : Buffer.from(o.bodyBase64, 'base64'),
        redirect: o.followRedirects === false ? 'manual' : 'follow',
        signal: AbortSignal.timeout(o.timeout || 30000),
      };
      if (o.connectAddress) {
        // 开发宿主同样保留 URL 主机名、SNI 与 Node 默认的证书校验。
        res = await new Promise((resolve, reject) => {
          const request = https.request(o.url, {
            method: options.method, headers, signal: options.signal,
            lookup: (_host, opts, callback) => callback(null, opts.all ? [{ address: o.connectAddress, family: 4 }] : o.connectAddress, 4),
          }, response => {
            const chunks = [];
            response.on('data', chunk => chunks.push(chunk));
            response.on('error', reject);
            response.on('end', () => {
              const result = new Response(Buffer.concat(chunks), { status: response.statusCode, headers: response.headers });
              Object.defineProperty(result, 'url', { value: o.url });
              resolve(result);
            });
          });
          request.on('error', reject);
          request.end(options.body);
        });
      } else res = await fetch(o.url, options);
    } catch (err) {
      throw { code: 'NETWORK', message: `${o.url}: ${err.cause?.code || err.message}` };
    }
    storeCookies(o.url, res.headers.getSetCookie?.() || []);
    const outHeaders = {};
    res.headers.forEach((v, k) => (outHeaders[k] = v));
    let body;
    if (o.responseType === 'base64') body = Buffer.from(await res.arrayBuffer()).toString('base64');
    else body = await res.text();
    if ((res.status === 403 || res.status === 503) && /cloudflare|cf-ray|Just a moment/i.test(body + (outHeaders.server || ''))) {
      if (outHeaders['cf-mitigated'] === 'challenge' || /Just a moment|Attention Required/i.test(body)) {
        throw { code: 'CLOUDFLARE', message: `Cloudflare 拦截：${o.url}`, url: o.url };
      }
    }
    return { status: res.status, headers: outHeaders, body, url: res.url };
  },

  async crypto(op, a) {
    switch (op) {
      case 'randomBytes':
        if (!Number.isInteger(a.length) || a.length < 1 || a.length > 65536) throw {code:'CONFIG',message:'随机字节长度无效'};
        return Array.from(crypto.randomBytes(a.length));
      case 'digestBytes':
        if (!['sha1','sha256'].includes(a.algorithm) || !Array.isArray(a.bytes) || a.bytes.length > 2097152 || a.bytes.some(b=>!Number.isInteger(b)||b<0||b>255)) throw {code:'CONFIG',message:'摘要数据无效'};
        return Array.from(crypto.createHash(a.algorithm).update(Buffer.from(a.bytes)).digest());
      case 'md5Hex':
        return Array.isArray(a.text)
          ? a.text.map((t) => crypto.createHash('md5').update(t, 'utf8').digest('hex'))
          : crypto.createHash('md5').update(a.text, 'utf8').digest('hex');
      case 'sha256Hex':
        return crypto.createHash('sha256').update(a.text, 'utf8').digest('hex');
      case 'hmacSha256Hex':
        return crypto.createHmac('sha256', Buffer.from(a.key, 'utf8')).update(a.text, 'utf8').digest('hex');
      case 'aesEcbDecrypt': {
        const key = Buffer.from(a.key, 'utf8');
        const decipher = crypto.createDecipheriv(`aes-${key.length * 8}-ecb`, key, null);
        decipher.setAutoPadding(false);
        let out = Buffer.concat([decipher.update(Buffer.from(a.base64, 'base64')), decipher.final()]);
        const pad = out[out.length - 1];
        if (pad > 0 && pad <= 16) out = out.subarray(0, out.length - pad);
        return out.toString('utf8');
      }
      case 'aesGcmDecrypt': {
        const hex = (name, lengths) => {
          const value = a[name];
          if (typeof value !== 'string' || value.length > 8192 || value.length % 2 || !/^[0-9a-f]+$/i.test(value) ||
              (lengths && !lengths.includes(value.length / 2))) throw new Error('AES-GCM 参数无效');
          return Buffer.from(value, 'hex');
        };
        const key = hex('key', [16, 24, 32]), iv = hex('iv', [12]), data = hex('ciphertext');
        if (data.length < 16) throw new Error('AES-GCM 密文无效');
        const cipher = crypto.createDecipheriv(`aes-${key.length * 8}-gcm`, key, iv);
        cipher.setAuthTag(data.subarray(-16));
        return Array.from(Buffer.concat([cipher.update(data.subarray(0, -16)), cipher.final()]));
      }
      case 'uuid':
        return crypto.randomUUID();
      default:
        throw { code: 'UNSUPPORTED', message: `crypto op ${op}` };
    }
  },

  async cookies(op, a) {
    const host = hostOf(a.url);
    if (op === 'get') return Object.fromEntries(jar.get(host) || []);
    if (op === 'set') {
      if (!jar.has(host)) jar.set(host, new Map());
      for (const [k, v] of Object.entries(a.cookies || {})) jar.get(host).set(k, String(v));
      return true;
    }
    if (op === 'clear') {
      jar.delete(host);
      return true;
    }
    return null;
  },

  persist(key, data) {
    persisted[key] = data;
  },

  log(key, level, message) {
    const tag = /^[A-Za-z0-9_-]{1,100}$/.test(key) ? key : 'source';
    const entry = `[${tag}] ${diagnosticMessage(message)}`;
    logs.push(entry);
    if (process.env.PARK_VERBOSE) console.log(entry);
  },
};

// ── Runtime loading ─────────────────────────────────────────
globalThis.DOMParser = DOMParser;
globalThis.Park = { __native: native };
vm.runInThisContext(fs.readFileSync(path.join(repoRoot, 'assets/runtime/park_runtime.js'), 'utf8'), {
  filename: 'park_runtime.js',
});

export const Park = globalThis.Park;

export async function loadSource(file, state = {}) {
  const code = fs.readFileSync(path.join(repoRoot, 'assets/sources', file), 'utf8');
  vm.runInThisContext(code, { filename: file });
  const def = Park.__pending;
  const manifest = await Park.setup(def.key, state);
  const call = async (method, ...args) => {
    const res = await Park.invoke(def.key, method, args);
    if (!res.ok) {
      const err = new Error(`${res.error.code}: ${res.error.message}`);
      err.code = res.error.code;
      throw err;
    }
    return res.value;
  };
  return { manifest, call, def };
}

/** Downloads raw bytes to check that an image URL is actually served. */
export async function probeImage(url, headers = {}) {
  const res = await fetch(url, { headers: { 'User-Agent': UA, ...headers }, signal: AbortSignal.timeout(30000) });
  const buf = Buffer.from(await res.arrayBuffer());
  return { status: res.status, bytes: buf.length, type: res.headers.get('content-type'), head: buf.subarray(0, 4).toString('hex') };
}
