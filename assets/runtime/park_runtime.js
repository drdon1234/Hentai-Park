/*
 * HentaiPark source runtime.
 *
 * Shared by the app (loaded into a headless WebView) and the Node test runner.
 * The host injects `Park.__native` before any source script is evaluated:
 *
 *   request(opts)            -> Promise<{status, headers, body, url}>
 *   crypto(op, args)         -> Promise<any>
 *   cookies(op, args)        -> Promise<any>
 *   persist(sourceKey, data) -> void   (fire-and-forget)
 *   log(sourceKey, level, message)
 *
 * Source scripts call `Park.register(definition)`; see docs/SOURCE_API.md.
 */
(function (global) {
  'use strict';

  const API_VERSION = 1;

  class ParkError extends Error {
    constructor(code, message, extra) {
      super(message || code);
      this.name = 'ParkError';
      this.code = code;
      if (extra) Object.assign(this, extra);
    }
  }

  const ErrorCode = Object.freeze({
    NOT_FOUND: 'NOT_FOUND',
    LOGIN_REQUIRED: 'LOGIN_REQUIRED',
    BLOCKED: 'BLOCKED',
    CLOUDFLARE: 'CLOUDFLARE',
    NETWORK: 'NETWORK',
    HTTP: 'HTTP',
    UNSUPPORTED: 'UNSUPPORTED',
    PARSE: 'PARSE',
    CONFIG: 'CONFIG',
  });

  function native() {
    if (!Park.__native) throw new ParkError(ErrorCode.CONFIG, 'Park host is not attached');
    return Park.__native;
  }

  function rethrowNative(err) {
    if (err instanceof ParkError) throw err;
    if (err && typeof err === 'object' && err.code) {
      throw new ParkError(err.code, err.message, err);
    }
    throw new ParkError(ErrorCode.NETWORK, String((err && err.message) || err));
  }

  // ── HTTP ────────────────────────────────────────────────

  function encodeForm(form) {
    return Object.keys(form)
      .filter((k) => form[k] !== undefined && form[k] !== null)
      .map((k) => encodeURIComponent(k) + '=' + encodeURIComponent(String(form[k])))
      .join('&');
  }

  function withQuery(url, params) {
    if (!params) return url;
    const query = encodeForm(params);
    if (!query) return url;
    return url + (url.includes('?') ? '&' : '?') + query;
  }

  function createHttp(source) {
    const defaults = source.network || {};

    async function request(opts) {
      const o = Object.assign({ method: 'GET', headers: {} }, opts);
      o.url = withQuery(o.url, o.params);
      delete o.params;
      o.headers = Object.assign({}, defaults.headers || {}, o.headers || {});
      if (o.json !== undefined) {
        o.body = JSON.stringify(o.json);
        if (!hasHeader(o.headers, 'content-type')) o.headers['Content-Type'] = 'application/json; charset=UTF-8';
        delete o.json;
      } else if (o.form !== undefined) {
        o.body = encodeForm(o.form);
        if (!hasHeader(o.headers, 'content-type')) o.headers['Content-Type'] = 'application/x-www-form-urlencoded';
        delete o.form;
      }
      o.mode = o.mode || defaults.mode || 'native';
      o.origin = o.origin || defaults.origin || '';
      o.source = source.key;
      let res;
      try {
        res = await native().request(o);
      } catch (err) {
        rethrowNative(err);
      }
      res.headers = res.headers || {};
      res.ok = res.status >= 200 && res.status < 300;
      res.json = () => {
        try {
          return JSON.parse(res.body);
        } catch (e) {
          throw new ParkError(ErrorCode.PARSE, `响应不是 JSON（HTTP ${res.status}）：${String(res.body).slice(0, 120)}`);
        }
      };
      return res;
    }

    function ensureOk(res, allow) {
      if (res.ok || (allow && allow.includes(res.status))) return res;
      if (res.status === 404) throw new ParkError(ErrorCode.NOT_FOUND, '内容不存在或已被删除', { status: 404 });
      throw new ParkError(ErrorCode.HTTP, `HTTP ${res.status}`, { status: res.status, body: String(res.body || '').slice(0, 300) });
    }

    return {
      request,
      async get(url, opts) {
        return request(Object.assign({}, opts, { url, method: 'GET' }));
      },
      async post(url, opts) {
        return request(Object.assign({}, opts, { url, method: 'POST' }));
      },
      async text(url, opts) {
        const res = ensureOk(await request(Object.assign({ url }, opts)), opts && opts.allowStatus);
        return res.body;
      },
      async json(url, opts) {
        const res = ensureOk(await request(Object.assign({ url }, opts)), opts && opts.allowStatus);
        return res.json();
      },
      ensureOk,
    };
  }

  function hasHeader(headers, name) {
    const lower = name.toLowerCase();
    return Object.keys(headers).some((k) => k.toLowerCase() === lower);
  }

  // ── Crypto / cookies ────────────────────────────────────

  function call(kind, op, args) {
    return native()[kind](op, args).catch(rethrowNative);
  }

  const crypto = {
    /** md5 of utf8 text; accepts a string or an array of strings (batched). */
    md5Hex: (text) => call('crypto', 'md5Hex', { text }),
    sha256Hex: (text) => call('crypto', 'sha256Hex', { text }),
    hmacSha256Hex: (key, text) => call('crypto', 'hmacSha256Hex', { key, text }),
    /** AES-ECB decrypt base64 data with an utf8 key, PKCS7 unpadding, returns utf8 text. */
    aesEcbDecrypt: (base64, key) => call('crypto', 'aesEcbDecrypt', { base64, key }),
    uuid: () => call('crypto', 'uuid', {}),
  };

  function createCookies(source) {
    return {
      get: (url) => call('cookies', 'get', { url, source: source.key }),
      set: (url, cookies) => call('cookies', 'set', { url, cookies, source: source.key }),
      clear: (url) => call('cookies', 'clear', { url, source: source.key }),
    };
  }

  // ── HTML ────────────────────────────────────────────────

  const html = {
    parse(text) {
      if (typeof DOMParser === 'undefined') throw new ParkError(ErrorCode.CONFIG, 'DOMParser unavailable');
      return new DOMParser().parseFromString(String(text || ''), 'text/html');
    },
    text(node) {
      if (!node) return '';
      return String(node.textContent || '').replace(/\s+/g, ' ').trim();
    },
    attr(node, name) {
      return node ? node.getAttribute(name) || '' : '';
    },
    unescape(text) {
      return String(text || '')
        .replace(/&amp;/g, '&')
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&quot;/g, '"')
        .replace(/&#0?39;|&apos;/g, "'")
        .replace(/&nbsp;/g, ' ')
        .replace(/&#(\d+);/g, (_, d) => String.fromCharCode(Number(d)))
        .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCharCode(parseInt(h, 16)));
    },
    strip(text) {
      return html.unescape(String(text || '').replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim();
    },
  };

  // ── Utils ───────────────────────────────────────────────

  const utils = {
    toInt(value, fallback) {
      const n = parseInt(String(value === undefined || value === null ? '' : value).replace(/,/g, ''), 10);
      return Number.isFinite(n) ? n : fallback === undefined ? null : fallback;
    },
    toFloat(value, fallback) {
      const n = parseFloat(String(value === undefined || value === null ? '' : value).replace(/,/g, ''));
      return Number.isFinite(n) ? n : fallback === undefined ? null : fallback;
    },
    /** Parses "7K", "1.2M", "185.8萬" style counts. */
    parseCount(text) {
      const m = /^([\d.,]+)\s*([KkMmWw萬万億亿]?)/.exec(String(text || '').trim());
      if (!m) return null;
      const units = { k: 1e3, m: 1e6, w: 1e4, 万: 1e4, 萬: 1e4, 亿: 1e8, 億: 1e8 };
      const n = parseFloat(m[1].replace(/,/g, ''));
      return Number.isFinite(n) ? Math.round(n * (units[m[2].toLowerCase()] || 1)) : null;
    },
    formatDate(value) {
      let n = Number(value);
      if (!Number.isFinite(n) || n <= 0) return String(value || '');
      if (n < 1e11) n *= 1000;
      const d = new Date(n);
      const pad = (x) => String(x).padStart(2, '0');
      return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
    },
    sleep(ms) {
      return new Promise((resolve) => setTimeout(resolve, ms));
    },
    /** Serialises calls so that consecutive starts are at least `interval` ms apart. */
    rateLimiter(interval) {
      let last = 0;
      let chain = Promise.resolve();
      return function wait() {
        const run = chain.then(async () => {
          const delay = last + interval - Date.now();
          if (delay > 0) await utils.sleep(delay);
          last = Date.now();
        });
        chain = run.catch(() => {});
        return run;
      };
    },
    /** Runs async `fn` over items with bounded concurrency, preserving order. */
    async mapLimit(items, limit, fn) {
      const results = new Array(items.length);
      let next = 0;
      async function worker() {
        while (next < items.length) {
          const i = next++;
          results[i] = await fn(items[i], i);
        }
      }
      await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
      return results;
    },
    lruMap(limit) {
      const map = new Map();
      return {
        get(key) {
          if (!map.has(key)) return undefined;
          const value = map.get(key);
          map.delete(key);
          map.set(key, value);
          return value;
        },
        set(key, value) {
          map.delete(key);
          map.set(key, value);
          while (map.size > limit) map.delete(map.keys().next().value);
        },
        has: (key) => map.has(key),
        delete: (key) => map.delete(key),
      };
    },
  };

  // ── Registry ────────────────────────────────────────────

  const sources = {};

  function createStore(source, initial) {
    const data = Object.assign({}, initial || {});
    return {
      get(key, fallback) {
        return Object.prototype.hasOwnProperty.call(data, key) ? data[key] : fallback;
      },
      set(key, value) {
        if (value === undefined || value === null) delete data[key];
        else data[key] = value;
        try {
          native().persist(source.key, data);
        } catch (e) {
          /* host without persistence */
        }
      },
      all: () => Object.assign({}, data),
    };
  }

  function settingDefaults(def) {
    const out = {};
    for (const s of def.settings || []) out[s.key] = s.default;
    return out;
  }

  /** Strips functions so that the manifest can cross the bridge as JSON. */
  function manifestOf(def) {
    const pick = (obj) => JSON.parse(JSON.stringify(obj === undefined ? null : obj));
    return {
      apiVersion: def.apiVersion || API_VERSION,
      key: def.key,
      name: def.name,
      version: def.version || '0.0.0',
      type: def.type || 'comic',
      color: def.color || '#7C4DFF',
      icon: def.icon || '',
      description: def.description || '',
      homepage: def.homepage || '',
      domains: Array.isArray(def.domains) ? def.domains.map(String) : [],
      language: def.language || '',
      linkPatterns: def.linkPatterns || [],
      idPattern: def.idPattern || '',
      idExample: def.idExample || '',
      imageHeaders: def.imageHeaders || {},
      network: pick(def.network || {}),
      settings: pick(def.settings || []),
      account: def.account
        ? {
            type: def.account.type,
            title: def.account.title || '',
            hint: def.account.hint || '',
            fields: pick(def.account.fields || []),
            loginUrl: def.account.loginUrl || '',
            cookieUrl: def.account.cookieUrl || '',
            requiredCookies: def.account.requiredCookies || [],
            required: !!def.account.required,
          }
        : null,
      feeds: pick(def.feeds || []),
      searchFilters: pick(def.searchFilters || []),
      searchHint: def.searchHint || '',
      capabilities: {
        search: typeof def.search === 'function',
        random: typeof def.random === 'function',
        chapter: typeof def.chapter === 'function',
        resolveImage: typeof def.resolveImage === 'function',
        videos: typeof def.videos === 'function',
        thumbnails: typeof def.thumbnails === 'function',
        status: !!(def.account && typeof def.account.status === 'function'),
      },
    };
  }

  const Park = {
    API_VERSION,
    ErrorCode,
    ParkError,
    html,
    crypto,
    utils,
    __native: global.Park && global.Park.__native,
    __pending: null,

    error(code, message, extra) {
      return new ParkError(code, message, extra);
    },

    /** Called by source scripts. Only the last registered definition per key is kept. */
    register(def) {
      if (!def || !def.key) throw new ParkError(ErrorCode.CONFIG, 'source definition requires a key');
      Park.__pending = def;
      sources[def.key] = { def, ready: null };
      return def;
    },

    /** Host: attach settings/store and run `init`. Returns the manifest. */
    async setup(key, state) {
      const entry = sources[key];
      if (!entry) throw new ParkError(ErrorCode.CONFIG, `source ${key} not loaded`);
      const def = entry.def;
      def.settings_ = Object.assign(settingDefaults(def), (state && state.settings) || {});
      def.store = createStore(def, state && state.data);
      def.http = createHttp(def);
      def.cookies = createCookies(def);
      def.log = (...args) => {
        try {
          native().log(def.key, 'info', args.map((a) => (typeof a === 'string' ? a : JSON.stringify(a))).join(' '));
        } catch (e) {
          /* ignore */
        }
      };
      Object.defineProperty(def, 'config', { get: () => def.settings_, configurable: true });
      entry.ready = typeof def.init === 'function' ? Promise.resolve(def.init()).catch(() => {}) : Promise.resolve();
      return manifestOf(def);
    },

    manifest(key) {
      const entry = sources[key];
      return entry ? manifestOf(entry.def) : null;
    },

    updateSettings(key, settings) {
      const entry = sources[key];
      if (!entry) return;
      entry.def.settings_ = Object.assign(settingDefaults(entry.def), settings || {});
      if (typeof entry.def.onSettingsChanged === 'function') {
        entry.ready = Promise.resolve(entry.def.onSettingsChanged()).catch(() => {});
      }
    },

    /**
     * Host entry point. `path` is a method name, optionally namespaced ("account.login").
     * Resolves to {ok: true, value} or {ok: false, error: {code, message}} so errors survive the bridge.
     */
    async invoke(key, path, args) {
      const entry = sources[key];
      if (!entry) return { ok: false, error: { code: ErrorCode.CONFIG, message: `源 ${key} 未加载` } };
      try {
        await entry.ready;
        // Namespaced methods ("account.login") still run with the source as `this`.
        let target = entry.def;
        for (const part of String(path).split('.')) target = target ? target[part] : undefined;
        if (typeof target !== 'function') {
          throw new ParkError(ErrorCode.UNSUPPORTED, `${entry.def.name} 不支持 ${path}`);
        }
        const value = await target.apply(entry.def, args || []);
        return { ok: true, value: value === undefined ? null : JSON.parse(JSON.stringify(value)) };
      } catch (err) {
        const code = (err && err.code) || ErrorCode.PARSE;
        const message = (err && err.message) || String(err);
        return { ok: false, error: { code, message, status: err && err.status, url: err && err.url } };
      }
    },

    sourceKeys() {
      return Object.keys(sources);
    },
  };

  global.Park = Park;
})(typeof globalThis !== 'undefined' ? globalThis : this);
