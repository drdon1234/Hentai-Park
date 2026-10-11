// Node implementation of the Park host bridge, used to develop and test source scripts
// against the live sites without building the app.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import crypto from 'node:crypto';
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

const native = {
  async request(o) {
    const headers = { 'User-Agent': UA, ...o.headers };
    const cookie = cookiesFor(o.url);
    if (cookie && !Object.keys(headers).some((k) => k.toLowerCase() === 'cookie')) headers.Cookie = cookie;
    let res;
    try {
      res = await fetch(o.url, {
        method: o.method,
        headers,
        body: o.body,
        redirect: 'follow',
        signal: AbortSignal.timeout(o.timeout || 30000),
      });
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
    logs.push(`[${key}] ${message}`);
    if (process.env.PARK_VERBOSE) console.log(`  · [${key}] ${message}`);
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
