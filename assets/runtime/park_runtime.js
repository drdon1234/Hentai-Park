/*
 * HentaiPark source runtime.
 *
 * Shared by the app (loaded into a headless WebView) and the Node test runner.
 * The host injects `Park.__native` before any source script is evaluated:
 *
 *   request(opts)            -> Promise<{status, headers, body, url}>
 *   crypto(op, args)         -> Promise<any>
 *   cookies(op, args)        -> Promise<any>
 *   persist(sourceKey, data, flush) -> Promise<void> (flush waits for durable storage)
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
    CONFIRM_REQUIRED: 'CONFIRM_REQUIRED',
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

  // Only structured, non-secret transport facts are allowed in automatic logs.
  function networkDiagnostics(err) {
    const d = err && err.diagnostics;
    if (!d || typeof d !== 'object') return {};
    const safe = {};
    if (typeof d.host === 'string' && d.host.length <= 253 && /^[a-z0-9.-]+$/i.test(d.host)) safe.host = d.host;
    if (['native', 'browser'].includes(d.transport)) safe.transport = d.transport;
    if (['TLS_CERTIFICATE', 'TLS_HANDSHAKE', 'TLS_HANDSHAKE_TERMINATED', 'DNS', 'CONNECTION', 'CONNECT_TIMEOUT',
      'RECEIVE_TIMEOUT', 'SEND_TIMEOUT', 'RESPONSE_STREAM', 'NETWORK'].includes(d.reason)) safe.reason = d.reason;
    return safe;
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

  function createHttp(source, invocation) {
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
      if (invocation !== undefined) o.invocation = invocation;
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
          throw new ParkError(ErrorCode.PARSE, '响应不是 JSON（HTTP {status}）：{body}', { params: { status: res.status, body: String(res.body).slice(0, 120) } });
        }
      };
      return res;
    }

    function ensureOk(res, allow) {
      if (res.ok || (allow && allow.includes(res.status))) return res;
      if (res.status === 404) throw new ParkError(ErrorCode.NOT_FOUND, '内容不存在或已被删除', { status: 404 });
      throw new ParkError(ErrorCode.HTTP, 'HTTP {status}', { status: res.status, body: String(res.body || '').slice(0, 300), params: { status: res.status } });
    }

    return {
      invocation,
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
    digestBytes: (algorithm, bytes) => call('crypto', 'digestBytes', { algorithm, bytes: Array.from(bytes) }),
    randomBytes: (length) => call('crypto', 'randomBytes', { length }),
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
    // Extract only text, preserving block and BR boundaries without running site markup.
    paragraphs(node) {
      if (!node) return [];
      const root = node.cloneNode(true);
      for (const unwanted of root.querySelectorAll('script,style,nav,form,button,iframe,aside')) unwanted.remove();
      let value = '';
      const blocks = /^(P|DIV|SECTION|ARTICLE|BLOCKQUOTE|H[1-6]|LI|PRE)$/;
      function walk(n) {
        if (n.nodeType === 3) { value += n.textContent; return; }
        if (n.nodeName === 'BR') { value += '\n'; return; }
        const block = blocks.test(n.nodeName);
        if (block) value += '\n';
        for (const child of n.childNodes || []) walk(child);
        if (block) value += '\n';
      }
      walk(root);
      return value.replace(/\r/g, '').split(/\n+/).map(p => p.replace(/[\t \u00a0]+/g, ' ').trim()).filter(Boolean);
    },
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
    let pending = Promise.resolve();
    const snapshot = () => JSON.parse(JSON.stringify(data));
    return {
      get(key, fallback) {
        return Object.prototype.hasOwnProperty.call(data, key) ? data[key] : fallback;
      },
      set(key, value) {
        if (value === undefined || value === null) delete data[key];
        else data[key] = value;
        const next = snapshot();
        pending = pending.then(() => native().persist(source.key, next, false)).catch(() => {});
      },
      /** Flush must succeed before externally creating an account whose credentials cannot be lost. */
      async flush() {
        const next = snapshot();
        pending = pending.catch(() => {}).then(() => native().persist(source.key, next, true));
        return pending;
      },
      all: () => Object.assign({}, data),
    };
  }

  function settingDefaults(def) {
    const out = {};
    for (const s of def.settings || []) out[s.key] = s.default;
    return out;
  }

  function rankingDefs(def) {
    return (def.rankings || []).map(board => ({
      ...board,
      section: board.section || (def.rankingOnly ? 'market' : 'site'),
      kind: board.kind || 'work',
      options: board.options || (def.feeds || []).find(feed => feed.key === board.feed)?.options || [],
    }));
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
      category: def.category || 'other',
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
      imageNetwork: def.imageNetwork ? pick(def.imageNetwork) : null,
      imageDecrypt: pick(def.imageDecrypt || {}),
      network: pick(def.network || {}),
      media: pick(def.media || {}),
      subscription: pick(def.subscription ? {hint:def.subscription.hint || '',joinedTargets:typeof def.subscription.targets === 'function'} : null),
      updateSubscriptions: pick(def.updateSubscriptions ? {dimensions:def.updateSubscriptions.dimensions} : null),
      settings: pick(def.settings || []),
      account: def.account
        ? {
            type: def.account.type,
            title: def.account.title || '',
            hint: def.account.hint || '',
            fields: pick(def.account.fields || []),
            loginUrl: def.account.loginUrl || '',
            loginDomains: Array.isArray(def.account.loginDomains) ? def.account.loginDomains.map(String) : [],
            cookieUrl: def.account.cookieUrl || '',
            requiredCookies: def.account.requiredCookies || [],
            required: !!def.account.required,
            managedAccount: !!def.account.managedAccount,
          }
        : null,
      feeds: pick(def.feeds || []),
      rankingOnly: def.rankingOnly === true,
      rankings: pick(rankingDefs(def)),
      // The plugin's own translations, keyed by its Chinese source text: {locale: {text: translation}}.
      i18n: pick(def.i18n || {}),
      defaultFeed: def.defaultFeed || '',
      anonymousDefaultFeed: def.anonymousDefaultFeed || '',
      searchFilters: pick(def.searchFilters || []),
      searchHint: def.searchHint || '',
      capabilities: {
        rankings: Array.isArray(def.rankings) && def.rankings.length > 0,
        subscription: !!(def.subscription && typeof def.subscription.normalize === 'function' && typeof def.subscription.posts === 'function'),
        subscriptionUpdates: !!(def.updateSubscriptions && typeof def.updateSubscriptions.check === 'function'),
        search: typeof def.search === 'function',
        random: typeof def.random === 'function',
        chapter: typeof def.chapter === 'function',
        textChapter: typeof def.textChapter === 'function',
        resolveImage: typeof def.resolveImage === 'function',
        videos: typeof def.videos === 'function',
        webVideo: typeof def.webVideo === 'function',
        gameResources: typeof def.gameResources === 'function',
        resolveGameResource: typeof def.resolveGameResource === 'function',
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

    /** 源显式选择维度，框架只负责规范化协议和稳定 ID。 */
    enableUpdateSubscriptions(def, rules) {
      const dimensions = rules.dimensions;
      const bounded = value => {
        const text = String(value || '').trim();
        if (!text || text.length > 2048 || /[\u0000-\u001f]/.test(text)) throw Park.error('CONFIG','订阅目标无效');
        return text;
      };
      const code = value => bounded(value).toUpperCase().replace(/[_\s]/g,'-');
      def.updateSubscriptions = {
        dimensions,
        async normalize(dimension, input) {
          if (!dimensions.some(d => d.key === dimension)) throw Park.error('UNSUPPORTED','不支持此订阅维度');
          let id = bounded(input);
          if (dimension === 'posts') return this.subscription.normalize.call(this,id);
          if (dimension === 'work') {
            for (const pattern of this.linkPatterns || []) { const m = new RegExp(pattern).exec(id); if (m) {id=m[1];break;} }
            const detail = await this.detail(id);
            if (!detail || !Array.isArray(detail.chapters) || !detail.chapters.length) throw Park.error('UNSUPPORTED','此作品没有可订阅的连载章节');
            return {id: String(detail.id || id), label: String(detail.title || id)};
          }
          if (dimension === 'code') {
            id = code(id);
            if (!/^[A-Z0-9]{2,16}-\d{2,8}$/.test(id)) throw Park.error('CONFIG','请输入完整番号，例如 ABP-123');
          }
          if(dimension==='series' && /^https:\/\//.test(id)) {
            const url=new URL(id);
            if(!(this.domains||[]).some(domain=>url.hostname===domain || url.hostname.endsWith('.'+domain)) || url.username || url.password) throw Park.error('CONFIG','请使用详情页的系列链接');
            id=url.pathname;
          }
          if (dimension === 'series' && (!rules.seriesPattern || !new RegExp(rules.seriesPattern).test(id))) throw Park.error('CONFIG','请使用详情页的系列链接');
          if (dimension === 'filter') {
            let data; try {data=JSON.parse(id);} catch (_) {throw Park.error('CONFIG','订阅筛选无效');}
            if (!data || typeof data.keyword !== 'string' || !data.filters || typeof data.filters !== 'object' || Array.isArray(data.filters)) throw Park.error('CONFIG','订阅筛选无效');
            id=JSON.stringify({keyword:data.keyword,filters:data.filters});
          }
          return {id,label:id};
        },
        async check(target, options = {}) {
          const dimension=target.dimension;
          if (!dimensions.some(d=>d.key===dimension)) throw Park.error('UNSUPPORTED','不支持此订阅维度');
          const cursor=options.cursor;
          if (dimension === 'work') {
            const detail=await this.detail(target.target);
            if (!detail || !Array.isArray(detail.chapters) || !detail.chapters.length) throw Park.error('PARSE','章节目录暂不可用');
            if(detail.chapters.some(c=>!c || c.id==null || !String(c.id).trim())) throw Park.error('PARSE','章节编号无效');
            return {items:detail.chapters.map(c=>({id:target.target+'\u001f'+String(c.id),title:String(detail.title||'')+' · '+String(c.title||c.id),workId:target.target,chapterId:String(c.id),kind:'chapter'})),hasNext:false};
          }
          if (dimension === 'posts') {
            const page=await this.subscription.posts.call(this,target.target,{cursor});
            if(!page || !Array.isArray(page.items) || page.items.some(p=>!p || p.id==null || !String(p.id).trim())) throw Park.error('PARSE','动态编号无效');
            return {...page,windowed:true,items:page.items.map(p=>({id:String(p.id),title:String(p.title||p.text||'').slice(0,512),kind:'post'}))};
          }
          const position=cursor ? JSON.parse(cursor) : {page:1};
          const pageNumber=position.page;
          if (!Number.isInteger(pageNumber) || pageNumber<1 || pageNumber>10000) throw Park.error('CONFIG','分页参数无效');
          let keyword=target.target, filters={...(rules.searchFilters||{})};
          if (dimension==='series') {keyword='';filters.category=target.target;}
          if (dimension==='filter') {const data=JSON.parse(target.target);keyword=data.keyword;filters={...filters,...data.filters};}
          const page=await this.search({keyword,page:pageNumber,cursor:position.sourceCursor,filters});
          if (!page || !Array.isArray(page.items)) throw Park.error('PARSE','订阅列表暂不可用');
          if(page.items.some(i=>!i || i.id==null || !String(i.id).trim())) throw Park.error('PARSE','作品编号无效');
          let items=page.items;
          if (dimension==='code') items=items.filter(i=>code(i.id)===target.target || (String(i.title||'').toUpperCase().match(/[A-Z0-9]{2,16}[-_ ]\d{2,8}/g)||[]).some(c=>code(c)===target.target));
          return {windowed:true,items:items.map(i=>({id:String(i.id),title:String(i.title||''),workId:String(i.id),kind:'work'})),hasNext:page.hasNext===true,cursor:page.hasNext===true?JSON.stringify({page:pageNumber+1,sourceCursor:page.cursor}):null};
        },
      };
      return def;
    },

    /** Called by source scripts. Only the last registered definition per key is kept. */
    register(def) {
      if (!def || !def.key) throw new ParkError(ErrorCode.CONFIG, 'source definition requires a key');
      Park.__pending = def;
      sources[def.key] = { def, ready: null };
      return def;
    },

    /** Host: attach settings/store and run `init`. Returns the manifest. */
    async setup(key, state, { waitForInit = false } = {}) {
      const entry = sources[key];
      if (!entry) throw new ParkError(ErrorCode.CONFIG, '站点未加载');
      const def = entry.def;
      def.settings_ = Object.assign(settingDefaults(def), (state && state.settings) || {});
      def.store = createStore(def, state && state.data);
      def.http = createHttp(def);
      def.cookies = createCookies(def);
      def.log = (...args) => {
        try {
          native().log(def.key, 'info', args.length === 1 && args[0] && typeof args[0] === 'object' ? args[0] : null);
        } catch (e) {
          /* ignore */
        }
      };
      Object.defineProperty(def, 'config', { get: () => def.settings_, configurable: true });
      const initialized = Promise.resolve().then(() => typeof def.init === 'function' ? def.init() : undefined);
      entry.ready = waitForInit ? initialized : initialized.catch(() => {});
      if (waitForInit) {
        await entry.ready;
        // Installation may commit only after init and all its private-state writes succeed.
        await def.store.flush();
      }
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
    async invoke(key, path, args, invocation) {
      if (invocation === null) invocation = undefined;
      const entry = sources[key];
      if (!entry) return { ok: false, error: { code: ErrorCode.CONFIG, message: '站点未加载' } };
      try {
        await entry.ready;
        // Namespaced methods ("account.login") still run with the source as `this`.
        let target = entry.def;
        for (const part of String(path).split('.')) target = target ? target[part] : undefined;
        if (path === 'ranking' || path === 'rankingOptions') {
          const board = rankingDefs(entry.def).find(b => b.key === args?.[0]);
          if (!board) throw new ParkError(ErrorCode.CONFIG, '未知列表');
          const loadOptions = async function () {
            const declared = board.options || [];
            if (!declared.some(o => o.dynamic)) return declared;
            if (typeof this.rankingOptions !== 'function') throw new ParkError(ErrorCode.CONFIG, '未知列表');
            const dynamic = await this.rankingOptions(board.key);
            return declared.map(option => {
              if (!option.dynamic) return option;
              const resolved = dynamic?.find(o => o.key === option.key);
              if (!resolved?.values?.length) throw new ParkError(ErrorCode.PARSE, '排行榜解析失败');
              return {...option, ...resolved};
            });
          };
          const ranking = target;
          target = path === 'rankingOptions' ? loadOptions : async function (_, request = {}) {
            const options = await loadOptions.call(this);
            const selected = {...request.options};
            for (const option of options) {
              const value = selected[option.key] ?? option.default;
              if (option.values && !option.values.some(choice => choice.value === value)) {
                throw new ParkError(ErrorCode.CONFIG, '未知列表');
              }
              selected[option.key] = value;
            }
            const req = {...request, options: selected};
            const fromFeed = typeof ranking !== 'function' && board.feed && typeof this.feed === 'function';
            if (!fromFeed && typeof ranking !== 'function') throw new ParkError(ErrorCode.CONFIG, '未知列表');
            const page = fromFeed ? await this.feed(board.feed, req) : await ranking.call(this, board.key, req);
            return {...page, items: (page.items || []).map((item, index) => ({
              ...item,
              kind: board.kind === 'actress' || board.kind === 'seller' ? board.kind : 'work',
              ...(fromFeed ? {rank: item.rank ?? (Number(req.offset) || 0) + index + 1, workId: item.id} : {}),
            }))};
          };
        }
        if (typeof target !== 'function') {
          throw new ParkError(ErrorCode.UNSUPPORTED, '{site}不支持{action}', { params: { site: entry.def.name, action: path } });
        }
        // Keep the source state shared, but bind HTTP to this invocation even
        // across awaits and nested source methods. Never use a global active ID.
        const http = invocation === undefined ? entry.def.http : createHttp(entry.def, invocation);
        const receiver = invocation === undefined ? entry.def : new Proxy(entry.def, {
          get: (def, property, receiver) => property === 'http' ? http : Reflect.get(def, property, receiver),
          set: (def, property, value) => Reflect.set(def, property, value),
        });
        const value = await target.apply(receiver, args || []);
        return { ok: true, value: value === undefined ? null : JSON.parse(JSON.stringify(value)) };
      } catch (err) {
        const code = (err && err.code) || ErrorCode.PARSE;
        const message = (err && err.message) || String(err);
        // The host logs the failure with the method name and the plugin's copy.
        const diagnostics = networkDiagnostics(err);
        // Messages are templates; their values travel separately so the app can translate them.
        const params = err && err.params && typeof err.params === 'object'
          ? Object.fromEntries(Object.entries(err.params).map(([k, v]) => [k, v == null ? '' : String(v)]))
          : undefined;
        return { ok: false, error: { code, message, params, status: err && err.status, url: err && err.url, diagnostics } };
      }
    },

  };

  global.Park = Park;
})(typeof globalThis !== 'undefined' ? globalThis : this);
