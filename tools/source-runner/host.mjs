// Node implementation of the Park host bridge, used to develop and test source scripts
// against the live sites without building the app.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import crypto from 'node:crypto';
import https from 'node:https';
import { fileURLToPath } from 'node:url';
import { DOMParser } from 'linkedom';
import { Cookie, CookieJar, domainMatch } from 'tough-cookie';

const here = path.dirname(fileURLToPath(import.meta.url));
export const repoRoot = path.resolve(here, '..', '..');

const UA =
  'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';

// 与应用一致按源分区；域、路径、Secure 和过期语义交给标准 Cookie 容器。
const jars = new Map();
function cookieJar(source = '') {
  if (!jars.has(source)) jars.set(source, new CookieJar());
  return jars.get(source);
}

// ── Native bridge ───────────────────────────────────────────
export const persisted = {};
export const logs = [];

const errorCodes = new Set(['NETWORK', 'TIMEOUT', 'AUTH', 'PARSE', 'CONFIG', 'UNSUPPORTED', 'HTTP', 'CANCELLED', 'UNKNOWN', 'CONFIRM_REQUIRED', 'CLOUDFLARE', 'LOGIN_REQUIRED', 'NOT_FOUND', 'BLOCKED']);
const failureReasons = new Set(['TLS_CERTIFICATE', 'TLS_HANDSHAKE_TERMINATED', 'TLS_HANDSHAKE', 'CONNECT_TIMEOUT', 'RECEIVE_TIMEOUT', 'SEND_TIMEOUT', 'DNS', 'CONNECTION', 'RESPONSE_STREAM', 'NETWORK', 'CANCELLED', 'UNKNOWN', 'UPSTREAM_EMPTY', 'NO_VIDEO', 'EMPTY_RESULT', 'CONTENT_FILTERED', 'SEARCH_ONLY']);
export function diagnosticMessage(value) {
  if (!value || typeof value !== 'object') return 'event=message';
  const fields = ['event=source'];
  if (typeof value.action === 'string' && /^[A-Za-z][A-Za-z0-9_.-]{0,63}$/.test(value.action)) fields.push(`action=${value.action}`);
  if (errorCodes.has(value.code)) fields.push(`code=${value.code}`);
  if (['native', 'browser'].includes(value.transport)) fields.push(`transport=${value.transport}`);
  if (failureReasons.has(value.reason)) fields.push(`reason=${value.reason}`);
  if (typeof value.host === 'string' && value.host.length <= 253 && /^(?:[a-zA-Z0-9-]+\.)*[a-zA-Z0-9-]+$/.test(value.host)) fields.push(`host=${value.host}`);
  return fields.join(' ');
}

const native = {
  async request(o) {
    const jar = cookieJar(o.source);
    let url = new URL(o.url), method = o.method || 'GET';
    let bodyData = o.bodyBase64 === undefined ? o.body : Buffer.from(o.bodyBase64, 'base64');
    const headers = new Headers({'User-Agent': UA, ...o.headers});
    const signal = AbortSignal.timeout(o.timeout || 30000);
    let res;
    try {
      for (let hop = 0; ; hop++) {
        const requestHeaders = new Headers(headers);
        if (!requestHeaders.has('cookie')) {
          const cookie = jar.getCookieStringSync(url.href);
          if (cookie) requestHeaders.set('cookie', cookie);
        }
        const options = {method, headers: requestHeaders, body: bodyData, redirect: 'manual', signal};
        if (o.connectAddress && url.hostname === new URL(o.url).hostname) {
          // 保留目标主机名、SNI 与证书校验；跨主机跳转不能复用指定 IP。
          res = await new Promise((resolve, reject) => {
            const request = https.request(url, {
              method, headers: Object.fromEntries(requestHeaders), signal,
              lookup: (_host, opts, callback) => callback(null, opts.all ? [{address: o.connectAddress, family: 4}] : o.connectAddress, 4),
            }, response => {
              const chunks = [];
              response.on('data', chunk => chunks.push(chunk));
              response.on('error', reject);
              response.on('end', () => {
                try {
                  const empty = method === 'HEAD' || [204, 205, 304].includes(response.statusCode);
                  const responseHeaders = new Headers();
                  for (const [key, value] of Object.entries(response.headers)) {
                    for (const entry of Array.isArray(value) ? value : [value]) {
                      if (entry !== undefined) responseHeaders.append(key, entry);
                    }
                  }
                  const result = new Response(empty ? null : Buffer.concat(chunks), {status: response.statusCode, headers: responseHeaders});
                  Object.defineProperty(result, 'url', {value: url.href});
                  resolve(result);
                } catch (error) { reject(error); }
              });
            });
            request.on('error', reject);
            request.end(bodyData);
          });
        } else res = await fetch(url, options);
        for (const cookie of res.headers.getSetCookie()) {
          jar.setCookieSync(cookie, url.href, {ignoreError: true});
        }
        const location = res.headers.get('location');
        if (o.followRedirects === false || ![301, 302, 303, 307, 308].includes(res.status) || !location) break;
        await res.body?.cancel();
        if (hop >= 19) throw new Error('Too many redirects');
        const next = new URL(location, url);
        // 与应用一致允许 HTTP 跳转，只禁止 HTTPS 降级及非 HTTP 地址。
        if (!['http:', 'https:'].includes(next.protocol) ||
            (url.protocol === 'https:' && next.protocol !== 'https:') ||
            next.username || next.password) throw new Error('Invalid redirect');
        if (next.origin !== url.origin) {
          for (const key of ['cookie', 'authorization', 'proxy-authorization', 'host']) headers.delete(key);
        }
        if ((res.status === 303 && method !== 'HEAD') || ([301, 302].includes(res.status) && method === 'POST')) {
          method = 'GET'; bodyData = undefined;
          for (const key of ['content-length', 'content-type', 'content-encoding', 'content-language', 'content-location']) headers.delete(key);
        }
        url = next;
      }
    } catch (err) {
      throw {code: 'NETWORK', message: `${o.url}: ${err.cause?.code || err.message}`};
    }
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
      case 'aesGcmEncrypt':
      case 'aesGcmDecrypt': {
        const hex = (name, lengths, maximum = 4096, allowEmpty = false) => {
          const value = a[name];
          if (typeof value !== 'string' || value.length > maximum * 2 || value.length % 2 || !(allowEmpty ? /^[0-9a-f]*$/i : /^[0-9a-f]+$/i).test(value) ||
              (lengths && !lengths.includes(value.length / 2))) throw new Error('AES-GCM 参数无效');
          return Buffer.from(value, 'hex');
        };
        const encrypt = op === 'aesGcmEncrypt';
        const key = hex('key', [16, 24, 32]), iv = hex('iv', [12]);
        const data = hex(encrypt ? 'plaintext' : 'ciphertext', null, encrypt ? 4080 : 4096, encrypt);
        const aad = a.aad == null ? Buffer.alloc(0) : hex('aad', null, 4096, true);
        if (!encrypt && data.length < 16) throw new Error('AES-GCM 密文无效');
        const cipher = encrypt ? crypto.createCipheriv(`aes-${key.length * 8}-gcm`, key, iv)
          : crypto.createDecipheriv(`aes-${key.length * 8}-gcm`, key, iv);
        cipher.setAAD(aad);
        if (encrypt) return Array.from(Buffer.concat([cipher.update(data), cipher.final(), cipher.getAuthTag()]));
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
    const jar = cookieJar(a.source);
    if (op === 'get') {
      const cookies = {};
      // 更具体的路径在前；与 HTTP 请求优先使用的同名 Cookie 保持一致。
      for (const cookie of jar.getCookiesSync(a.url)) {
        if (!Object.hasOwn(cookies, cookie.key)) Object.defineProperty(cookies, cookie.key, {value: cookie.value, enumerable: true});
      }
      return cookies;
    }
    if (op === 'set') {
      for (const [key, value] of Object.entries(a.cookies || {})) {
        jar.setCookieSync(new Cookie({key, value: String(value), path: '/', secure: new URL(a.url).protocol === 'https:'}), a.url);
      }
      return true;
    }
    if (op === 'clear') {
      const host = new URL(a.url).hostname;
      for (const cookie of jar.serializeSync().cookies) {
        if (cookie.domain === host || (!cookie.hostOnly && domainMatch(host, cookie.domain))) {
          await jar.store.removeCookie(cookie.domain, cookie.path, cookie.key);
        }
      }
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
  Park.__pending = null;
  vm.runInThisContext(code, { filename: file });
  const def = Park.__pending;
  if (!def || typeof def.key !== 'string' || !def.key) throw new Error('插件未注册有效定义');
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
