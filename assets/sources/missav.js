/* MissAV: only parse page data. Packed media strings are decoded without eval. */
Park.register({
  i18n: {
    "zh-Hant": {"MissAV 返回 HTTP {value0}": "MissAV 傳回 HTTP {value0}", "发行日期": "發行日期", "收藏最多": "收藏最多", "真人成人视频，支持多清晰度播放与安卓离线下载": "真人成人影片，支援多畫質播放與 Android 離線下載"},
    "ja": {"MissAV 返回 HTTP {value0}": "MissAV が HTTP {value0} を返しました", "发行日期": "発売日", "收藏最多": "お気に入り数順", "真人成人视频，支持多清晰度播放与安卓离线下载": "実写の成人向け動画。複数画質での再生と Android のオフラインダウンロードに対応"},
    "ko": {"MissAV 返回 HTTP {value0}": "MissAV가 HTTP {value0}을 반환했습니다", "发行日期": "출시일", "收藏最多": "즐겨찾기 많은 순", "真人成人视频，支持多清晰度播放与安卓离线下载": "실사 성인 동영상, 여러 화질 재생 및 Android 오프라인 다운로드 지원"},
    "en": {"MissAV 返回 HTTP {value0}": "MissAV returned HTTP {value0}", "发行日期": "Release date", "收藏最多": "Most saved", "真人成人视频，支持多清晰度播放与安卓离线下载": "Live-action adult videos with multiple playback resolutions and Android offline downloads"},
    "es": {"MissAV 返回 HTTP {value0}": "MissAV devolvió HTTP {value0}", "发行日期": "Fecha de lanzamiento", "收藏最多": "Más guardados", "真人成人视频，支持多清晰度播放与安卓离线下载": "Videos para adultos de acción real con varias resoluciones y descargas sin conexión en Android"},
    "ru": {"MissAV 返回 HTTP {value0}": "MissAV вернул HTTP {value0}", "发行日期": "Дата выпуска", "收藏最多": "Больше всего добавлений в избранное", "真人成人视频，支持多清晰度播放与安卓离线下载": "Видео для взрослых с реальными актёрами, выбором качества и офлайн-загрузкой на Android"},
    "ar": {"MissAV 返回 HTTP {value0}": "أعاد MissAV حالة HTTP {value0}", "发行日期": "تاريخ الإصدار", "收藏最多": "الأكثر حفظًا", "真人成人视频，支持多清晰度播放与安卓离线下载": "فيديوهات للبالغين بممثلين حقيقيين، مع خيارات متعددة للجودة والتنزيل دون اتصال على Android"},
  },
  key: 'missav',
  name: 'MissAV',
  version: '0.0.12', minAppVersion: '0.9.2',
  type: 'video',
  category: 'jav',
  color: '#EF4444',
  description: '真人成人视频，支持多清晰度播放与安卓离线下载',
  homepage: 'https://missav.ai',
  domains: ['missav.ai'],
  language: 'zh',
  linkPatterns: ['missav\\.ai/(?:dm\\d*/)?(?:(?:cn|ja|en|ko|zh)/)?([a-z0-9][a-z0-9-]*)(?:[?#]|$)'],
  idPattern: '^[a-z0-9][a-z0-9-]{1,120}$',
  idExample: 'bank-250',
  imageHeaders: {Referer: 'https://missav.ai/'},
  network: {mode: 'browser', origin: 'https://missav.ai', vpnHint: true},
  media: {mode: 'browser', origin: 'https://missav.ai', domains: ['surrit.com']},
  settings: [{key: 'quality', type: 'select', label: '默认清晰度', default: '1080', options: [
    {value: '1080', label: '1080P'}, {value: '720', label: '720P'}, {value: '480', label: '480P'},
  ]}],
  rankings: [{key: 'today-hot', label: '今日热门', category: 'jav', section: 'site', metric: '站内热门', feed: 'today-hot'},
    {key: 'weekly-hot', label: '本周热门', category: 'jav', section: 'site', metric: '站内热门', feed: 'weekly-hot'}],
  defaultFeed: 'today-hot',
  feeds: [{key: 'new', label: '最近更新'}, {key: 'release', label: '最新上市'},
    {key: 'today-hot', label: '今日热门'}, {key: 'weekly-hot', label: '本周热门'},
    {key: 'categories', label: '分类', options: [{key: 'category', label: '分类', default: '', dynamic: true, values: []}]}],
  searchHint: '搜索番号、作品名或演员',
  searchFilters: [{key: 'sort', label: '排序', default: 'released_at', values: [
    {value: 'released_at', label: '发行日期'}, {value: 'published_at', label: '最近更新'},
    {value: 'saved', label: '收藏最多'},
  ]}],
  // __CATALOG_START__：由 tools/build_catalog_sources.mjs 生成。
  async categoryDirectory() {
    if (this._categoryDirectory && Date.now() - this._categoryDirectory.time < 120000) return this._categoryDirectory.values;
    const config = {"home":"/cn/new","leaf":"^/(?:dm\\d*/)?cn/genres/[a-zA-Z0-9_%+-]+/?$","index":"^/(?:dm\\d*/)?cn/genres/?$"}, leaf = new RegExp(config.leaf), index = config.index ? new RegExp(config.index) : null;
    const values = new Map(), indexes = new Set(), origin = new URL(this.BASE).origin;
    const page = path => this[config.pageMethod || 'getPage']((config.absolute ? this.BASE : '') + path);
    const collect = doc => {
      for (const a of doc.querySelectorAll(config.selector || 'a[href]')) {
        let u;
        try { u = new URL(a.getAttribute('href'), this.BASE); } catch (_) { continue; }
        if (u.origin !== origin || u.username || u.password || u.search || u.hash ||
            /%2f|%5c|%2e|%00/i.test(u.pathname)) continue;
        try { if (/[\x00-\x1f\x7f\\]/.test(decodeURIComponent(u.pathname))) continue; } catch (_) { continue; }
        const label = Park.html.text(a).replace(/\s+/g, ' ').trim();
        if (leaf.test(u.pathname) && label && label.length <= 256 && !values.has(u.pathname)) values.set(u.pathname, label);
        else if (index?.test(u.pathname)) indexes.add(u.pathname);
      }
    };
    collect((await page(config.home)).doc);
    for (const path of [...indexes].slice(0, 1)) collect((await page(path)).doc);
    if (!values.size || values.size > (config.ranges ? 10000 : 499)) throw Park.error('PARSE', '分类列表解析失败');
    const rows = [...values].map(([value, label]) => ({value, label}));
    this._categoryDirectory = {time: Date.now(), values: rows};
    return rows;
  },
  async filterOptions(request) {
    const config = {"home":"/cn/new","leaf":"^/(?:dm\\d*/)?cn/genres/[a-zA-Z0-9_%+-]+/?$","index":"^/(?:dm\\d*/)?cn/genres/?$"};
    const rows = await this.categoryDirectory();
    if (config.ranges && request.filter === 'range') {
      return Array.from({length: Math.ceil(rows.length / 200)}, (_, i) => ({
        value: String(i), label: (i * 200 + 1) + '–' + Math.min((i + 1) * 200, rows.length),
      }));
    }
    if (request.filter !== 'category') throw Park.error('CONFIG', '筛选参数无效');
    let choices = rows;
    if (config.ranges) {
      const range = String(request.values?.range ?? '0');
      if (!/^(?:0|[1-9]\d{0,2})$/.test(range) || Number(range) * 200 >= rows.length) throw Park.error('CONFIG', '筛选参数无效');
      choices = rows.slice(Number(range) * 200, (Number(range) + 1) * 200);
    }
    return [{value: '', label: '全部'}, ...choices];
  },
  async categoryFeed(request) {
    const category = String(request.options?.category || '');
    if (!category) return this.feed(this.defaultFeed, request);
    const choices = await this.filterOptions({filter: 'category', values: request.options || {}});
    if (!choices.some(option => option.value === category)) {
      throw Park.error('CONFIG', '筛选参数无效');
    }
    const config = {"home":"/cn/new","leaf":"^/(?:dm\\d*/)?cn/genres/[a-zA-Z0-9_%+-]+/?$","index":"^/(?:dm\\d*/)?cn/genres/?$"};
    return this[config.listMethod || 'listing'](category, request);
  },
  // __CATALOG_END__
  BASE: 'https://missav.ai',

  account: {
    type: 'cookies', title: '登录', hint: '登录后可使用原站收藏',
    loginUrl: 'https://missav.ai', cookieUrl: 'https://missav.ai', fields: [],
    async login(values) {
      await this.cookies.set(this.BASE, values);
      const status = await this.account.status.call(this);
      if (!status.loggedIn) throw Park.error('LOGIN_REQUIRED', '请先登录');
      return {name: status.name};
    },
    async logout() { await this.cookies.clear(this.BASE); },
    async status() {
      const {doc} = await this.getPage('/cn/new');
      const item = this.cards(doc)[0];
      if (!item) throw Park.error('PARSE', '原站互动数据无效');
      const state = await this.interactionState(item.id);
      return {loggedIn: !!state.user, name: String(state.user?.username || state.user?.name || '')};
    },
  },

  async interactionState(id) {
    const {html} = await this.getPage('/cn/' + this.validId(id));
    const match = /\/api\/items\/([a-zA-Z0-9_-]+)\/view/.exec(html);
    if (!match) throw Park.error('PARSE', '原站互动数据无效');
    const state = await this.http.json(this.BASE + '/api/items/' + match[1] + '/view');
    if (typeof state.saved !== 'boolean') throw Park.error('PARSE', '原站互动数据无效');
    return {item: match[1], user: state.user, saved: state.saved};
  },

  async interaction(id, req = {}) {
    if (req.value !== undefined && req.type !== 'favorite') throw Park.error('CONFIG', '原站互动数据无效');
    let state = await this.interactionState(id);
    if (!state.user) throw Park.error('LOGIN_REQUIRED', '请先登录');
    if (req.value !== undefined) {
      if (typeof req.value !== 'boolean') throw Park.error('CONFIG', '原站互动数据无效');
      if (state.saved !== req.value) {
        const cookies = await this.cookies.get(this.BASE);
        const headers = {Accept: 'application/json', Referer: this.BASE + '/cn/' + id};
        if (cookies['XSRF-TOKEN']) {
          try { headers['X-XSRF-TOKEN'] = decodeURIComponent(cookies['XSRF-TOKEN']); }
          catch (_) { throw Park.error('AUTH', '原站操作未成功，请重试'); }
        }
        const res = await this.http.request({url: this.BASE + '/api/items/' + state.item + '/save',
          method: req.value ? 'POST' : 'DELETE', headers});
        if (res.status === 401) throw Park.error('LOGIN_REQUIRED', '请先登录');
        if (!res.ok) throw Park.error('HTTP', 'HTTP {status}', {status: res.status, params: {status: res.status}});
        state = await this.interactionState(id);
        if (!state.user || state.saved !== req.value) throw Park.error('AUTH', '原站操作未成功，请重试');
      }
    }
    return [{type: 'favorite', value: state.saved}];
  },

  identity(id, label = '') {
    const code = id.replace(/(?:-(?:uncensored-leak|uncensored|chinese-subtitle|english-subtitle))+$/, '');
    const text = id + ' ' + label;
    const editions = [];
    if (/uncensored-leak|无码流出|無碼流出/i.test(text)) editions.push('无码流出');
    else if (/uncensored|无码|無碼|無修正/i.test(text)) editions.push('无码');
    if (/chinese-subtitle|中文字幕|中文\s*字幕/i.test(text)) editions.push('中文字幕');
    if (/english-subtitle|英文字幕/i.test(text)) editions.push('英文字幕');
    return {workCode: /^(?:\d{0,4}[a-z]{2,12}-\d{2,8}[a-z]?|fc2-ppv-\d{2,12})$/i.test(code) ? code.toUpperCase() : '', editions};
  },

  variants(doc, id, title, cover) {
    const current = this.identity(id).workCode;
    if (!current) return [];
    const out = [];
    for (const a of doc.querySelectorAll('a[href]')) {
      let url;
      try { url = new URL(a.getAttribute('href'), this.BASE); } catch (_) { continue; }
      if (url.origin !== this.BASE || url.search || url.hash) continue;
      const match = /^\/(?:dm\d*\/)?cn\/([a-z0-9][a-z0-9-]{1,120})$/.exec(url.pathname);
      if (!match || match[1] === id || out.some(item => item.id === match[1])) continue;
      const label = Park.html.text(a);
      const identity = this.identity(match[1], label);
      if (identity.workCode !== current) continue;
      if (!identity.editions.length && /原版|原作|original/i.test(label)) identity.editions.push('原版');
      out.push({id: match[1], title, cover, coverAspect: 16 / 9, ...identity});
    }
    return out;
  },

  validId(id) {
    const value = String(id).toLowerCase();
    if (!/^[a-z0-9][a-z0-9-]{1,120}$/.test(value)) throw Park.error('NOT_FOUND', '影片编号无效');
    return value;
  },

  async getPage(path, params) {
    const response = await this.http.get(this.BASE + path, {params});
    if (response.status === 404) throw Park.error('NOT_FOUND', '影片不存在');
    if (!response.ok) throw Park.error('HTTP', 'MissAV 返回 HTTP {value0}', { params: {value0: response.status},status: response.status});
    return {html: response.body, doc: Park.html.parse(response.body)};
  },

  cards(doc) {
    const out = [];
    for (const card of doc.querySelectorAll('.thumbnail')) {
      const a = card.querySelector('a.text-secondary[href]') || card.querySelector('a[href]');
      const img = card.querySelector('img');
      const m = a && /\/(?:dm\d*\/)?(?:cn\/)?([a-z0-9][a-z0-9-]{1,120})(?:[?#]|$)/.exec(a.getAttribute('href') || '');
      if (!m || !img || out.some(item => item.id === m[1])) continue;
      const title = Park.html.text(a) || img.getAttribute('alt') || '';
      const cover = img.getAttribute('data-src') || img.getAttribute('src') || '';
      if (!title || !/^https:\/\//.test(cover)) continue;
      const duration = (Park.html.text(card).match(/\b(?:\d+:)?\d{1,2}:\d{2}\b/) || [''])[0];
      // 推荐模板会保留隐藏的字幕角标，不能把未显示的标记当成版本信息。
      const labels = card.cloneNode(true);
      for (const node of labels.querySelectorAll('[hidden], [style], script, template')) {
        if (node.hasAttribute('hidden') || /display\s*:\s*none/i.test(node.getAttribute('style') || '') || /^(SCRIPT|TEMPLATE)$/.test(node.nodeName)) node.remove();
      }
      const editionLabels = [...labels.querySelectorAll('span')].map(Park.html.text).join(' ');
      out.push({id: m[1], title, cover, coverAspect: 16 / 9, duration, ...this.identity(m[1], editionLabels)});
    }
    return out;
  },

  async listing(path, req, params = {}) {
    const page = Math.max(1, Number(req.page) || 1);
    const {doc} = await this.getPage(path, {...params, ...(page > 1 ? {page: String(page)} : {})});
    const items = this.cards(doc);
    let totalPages = page;
    for (const a of doc.querySelectorAll('a[href]')) {
      const m = /[?&]page=(\d+)/.exec(a.getAttribute('href'));
      if (m) totalPages = Math.max(totalPages, Number(m[1]));
    }
    return {items, page, totalPages, hasNext: page < totalPages};
  },

  async feed(key, req) {
    if (key === 'categories') return this.categoryFeed(req);
    if (!this.feeds.some(feed => feed.key === key)) throw Park.error('CONFIG', '未知视频列表');
    return this.listing('/cn/' + key, req);
  },

  async search(req) {
    const filters = req.filters || {};
    // Detail tags retain only a bounded site-relative category route.
    if (typeof filters.category === 'string' && /^\/(?:dm\d*\/)?cn\/(?:genres|actresses|makers|series|directors|labels)\/[^?#]+$/.test(filters.category)) {
      return this.listing(filters.category, req);
    }
    const keyword = String(req.keyword || '').trim();
    if (!keyword) return {items: [], page: 1, totalPages: 1, hasNext: false};
    const sort = ['released_at', 'published_at', 'saved'].includes(filters.sort) ? filters.sort : 'released_at';
    return this.listing('/cn/search/' + encodeURIComponent(keyword), req,
      sort === 'released_at' ? {} : {sort});
  },

  unpackLiteral(value) {
    // Only JavaScript string escapes used by the packer. Never execute script.
    return value.replace(/\\(u[0-9a-f]{4}|x[0-9a-f]{2}|[\\'"nrt])/gi, (_, escape) => {
      if (escape[0] === 'u' || escape[0] === 'x') return String.fromCharCode(parseInt(escape.slice(1),16));
      return ({n: '\n', r: '\r', t: '\t'})[escape] || escape;
    });
  },

  packedMedia(html) {
    if (html.length > 4 * 1024 * 1024) throw Park.error('PARSE', '影片页面过大');
    const candidates = [];
    // Match the packed data tuple, not arbitrary expressions or function bodies.
    const packed = /\}\s*\(\s*'((?:\\.|[^'\\])*)'\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*'((?:\\.|[^'\\])*)'\.split\('\|'\)/g;
    for (const m of html.matchAll(packed)) {
      const radix = Number(m[2]), count = Number(m[3]);
      if (radix < 2 || radix > 62 || count > 10000) continue;
      const words = this.unpackLiteral(m[4]).split('|');
      let payload = this.unpackLiteral(m[1]);
      const encode = n => n < radix ? (n > 35 ? String.fromCharCode(n + 29) : n.toString(36)) : encode(Math.floor(n/radix)) + encode(n%radix);
      const dictionary = new Map();
      for (let i = 0; i < count; i++) if (words[i]) dictionary.set(encode(i), words[i]);
      // A single replacement prevents substituted words from being decoded again.
      payload = payload.replace(/\b[0-9a-zA-Z]+\b/g, word => dictionary.get(word) || word);
      candidates.push(payload);
    }
    return candidates;
  },

  mediaSources(html) {
    const candidates = this.packedMedia(html);
    const found = new Map();
    for (const payload of candidates) {
      for (const match of payload.matchAll(/https:\/\/surrit\.com\/[a-f0-9-]{36}\/(\d{3,4})p\/[^'"\s;]+\.m3u8/g)) {
        const quality = Number(match[1]);
        if (quality >= 240 && quality <= 2160) found.set(quality, match[0]);
      }
    }
    return [...found].sort((a,b) => b[0]-a[0]).map(([quality,url]) => ({quality,url}));
  },

  // The site renders related videos in the browser from Recombee; its public frontend token
  // lives in the app bundle, so read it from there instead of copying it into the plugin.
  async recombee(doc) {
    const script = [...doc.querySelectorAll('script[src]')].map(s => s.getAttribute('src') || '')
      .find(src => /^https:\/\/missav\.ai\/build\/assets\/app\.[a-z0-9]+\.js$/.test(src));
    if (!script) return null;
    if (this.recombeeClient && this.recombeeClient.script === script) return this.recombeeClient;
    const r = await this.http.get(script);
    if (!r.ok || r.body.length > 4 * 1024 * 1024) return null;
    const m = /\.ApiClient\("([a-z0-9-]{1,64})","([A-Za-z0-9]{16,128})",\{baseUri:"([a-z0-9-]+\.recombee\.com)"\}/.exec(r.body);
    if (!m) return null;
    this.recombeeClient = {script, database: m[1], token: m[2], base: 'https://' + m[3]};
    return this.recombeeClient;
  },

  async hmacSha1Hex(key, text) {
    const bytes = value => Array.from(new TextEncoder().encode(value));
    let k = bytes(key);
    if (k.length > 64) k = await Park.crypto.digestBytes('sha1', k);
    const block = k.concat(new Array(64 - k.length).fill(0));
    const inner = await Park.crypto.digestBytes('sha1', block.map(b => b ^ 0x36).concat(bytes(text)));
    const outer = await Park.crypto.digestBytes('sha1', block.map(b => b ^ 0x5c).concat(inner));
    return outer.map(b => b.toString(16).padStart(2, '0')).join('');
  },

  async relatedItems(doc, id) {
    const client = await this.recombee(doc);
    if (!client) return [];
    // Same request and signature as the site's recombee-js-api-client RecommendItemsToItem.
    let path = `/${client.database}/recomms/items/${encodeURIComponent(id)}/items/?frontend_timestamp=${Math.floor(Date.now() / 1000)}`;
    path += '&frontend_sign=' + await this.hmacSha1Hex(client.token, path);
    const r = await this.http.post(client.base + path, {mode: 'native', json: {
      targetUserId: this.recombeeUser || (this.recombeeUser = await Park.crypto.uuid()),
      count: 16, scenario: 'mobile-watch-next', returnProperties: true,
      includedProperties: ['title_cn', 'duration'], cascadeCreate: true,
    }});
    if (!r.ok || r.body.length > 1024 * 1024) return [];
    let data;
    try { data = JSON.parse(r.body); } catch (_) { return []; }
    const out = [];
    for (const recomm of Array.isArray(data.recomms) ? data.recomms.slice(0, 50) : []) {
      const itemId = String(recomm && recomm.id || '').toLowerCase(), values = recomm && recomm.values || {};
      if (!/^[a-z0-9][a-z0-9-]{1,120}$/.test(itemId) || itemId === id || out.some(item => item.id === itemId)) continue;
      const code = itemId.toUpperCase().replace(/-(?:UNCENSORED-LEAK|CHINESE-SUBTITLE|ENGLISH-SUBTITLE)$/, '');
      const seconds = Number(values.duration) || 0;
      out.push({id: itemId, title: values.title_cn ? `${code} ${values.title_cn}` : code, ...this.identity(itemId),
        cover: `https://fourhoi.com/${itemId}/cover-t.jpg`, coverAspect: 16 / 9,
        duration: seconds ? `${Math.floor(seconds/3600)}:${String(Math.floor(seconds/60)%60).padStart(2,'0')}:${String(seconds%60).padStart(2,'0')}` : ''});
    }
    return out;
  },

  async detail(id) {
    id = this.validId(id);
    const {html, doc} = await this.getPage('/cn/' + id);
    const meta = key => { const el = doc.querySelector(`meta[property="${key}"]`); return el ? el.getAttribute('content') || '' : ''; };
    const title = Park.html.text(doc.querySelector('h1')) || meta('og:title');
    if (!title) throw Park.error('NOT_FOUND', '影片不存在');
    const tags = [];
    const actors = [];
    for (const a of doc.querySelectorAll('.space-y-2 a[href]')) {
      const href = a.getAttribute('href') || '';
      const match = /^https:\/\/missav\.ai(\/(?:dm\d*\/)?cn\/(genres|actresses|makers|series|directors|labels)\/[^?#]+)$/.exec(href);
      const name = Park.html.text(a);
      if (!match || !name) continue;
      if (match[2] === 'actresses') actors.push(name);
      tags.push({name, keyword: '', filters: {category: match[1]}});
    }
    const time = doc.querySelector('time[datetime]');
    const seconds = Number(meta('og:video:duration')) || 0;
    const editionTags = [...doc.querySelectorAll('.space-y-2 a[href]')]
      .map(a => a.getAttribute('href') || '').filter(url => /\/cn\/(?:chinese-subtitle|english-subtitle|uncensored-leak|uncensored)(?:[?#]|$)/.test(url)).join(' ');
    return {id, title, cover: meta('og:image'), coverAspect: 16/9, url: this.BASE + '/cn/' + id,
      ...this.identity(id, editionTags),
      variants: this.variants(doc, id, title, meta('og:image')),
      authors: actors, description: meta('og:description'), uploaded: time ? time.getAttribute('datetime').slice(0,10) : '',
      duration: seconds ? `${Math.floor(seconds/3600)}:${String(Math.floor(seconds/60)%60).padStart(2,'0')}:${String(seconds%60).padStart(2,'0')}` : '',
      tags: tags.length ? [{namespace: 'tag',label: '标签',tags}] : [],
      qualities: this.mediaSources(html).map(s => s.quality), related: await this.relatedItems(doc, id)};
  },

  async videos(id) {
    const {html} = await this.getPage('/cn/' + this.validId(id));
    const wanted = Number(this.config.quality) || 1080;
    const master = this.packedMedia(html).map(payload =>
      (payload.match(/https:\/\/surrit\.com\/[a-f0-9-]{36}\/playlist\.m3u8/) || [])[0]).find(Boolean);
    if (master) return [{url: master, quality: wanted, label: `${wanted}P`, format: 'hls', preferred: true}];
    const sources = this.mediaSources(html);
    if (!sources.length) throw Park.error('UNSUPPORTED', '此影片没有可用的 HLS 清晰度');
    const preferred = (sources.find(source => source.quality <= wanted) || sources[0]).quality;
    return sources.map(source => ({...source, label: `${source.quality}P`, format: 'hls', preferred: source.quality === preferred}));
  },
});

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"},{"key":"code","label":"完整番号","hint":"请输入完整番号，例如 ABP-123"},{"key":"series","label":"站点系列","hint":"请使用详情页的系列链接"}],"seriesPattern":"^/(?:dm\\d*/)?cn/series/[^?#]+$","searchFilters":{"sort":"published_at"}});
