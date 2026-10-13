/* MissAV: only parse page data. Packed media strings are decoded without eval. */
Park.register({
  key: 'missav',
  name: 'MissAV',
  version: '0.0.3',
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
  defaultFeed: 'today-hot',
  feeds: [{key: 'new', label: '最近更新'}, {key: 'release', label: '最新上市'},
    {key: 'today-hot', label: '今日热门'}, {key: 'weekly-hot', label: '本周热门'}],
  searchHint: '搜索番号、作品名或演员',
  searchFilters: [{key: 'sort', label: '排序', default: 'released_at', values: [
    {value: 'released_at', label: '发行日期'}, {value: 'published_at', label: '最近更新'},
    {value: 'saved', label: '收藏最多'},
  ]}],
  BASE: 'https://missav.ai',

  validId(id) {
    const value = String(id).toLowerCase();
    if (!/^[a-z0-9][a-z0-9-]{1,120}$/.test(value)) throw Park.error('NOT_FOUND', '影片编号无效');
    return value;
  },

  async getPage(path, params) {
    const response = await this.http.get(this.BASE + path, {params});
    if (response.status === 404) throw Park.error('NOT_FOUND', '影片不存在');
    if (!response.ok) throw Park.error('HTTP', `MissAV 返回 HTTP ${response.status}`, {status: response.status});
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
      out.push({id: m[1], title, cover, coverAspect: 16 / 9, duration});
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
    return {id, title, cover: meta('og:image'), coverAspect: 16/9, url: this.BASE + '/cn/' + id,
      authors: actors, description: meta('og:description'), uploaded: time ? time.getAttribute('datetime').slice(0,10) : '',
      duration: seconds ? `${Math.floor(seconds/3600)}:${String(Math.floor(seconds/60)%60).padStart(2,'0')}:${String(seconds%60).padStart(2,'0')}` : '',
      tags: tags.length ? [{namespace: 'tag',label: '标签',tags}] : [],
      qualities: this.mediaSources(html).map(s => s.quality), related: this.cards(doc).filter(item => item.id !== id)};
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
