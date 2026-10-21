/* Jable.TV page data; remote player scripts are never executed. */
Park.register({
  i18n: {
    "zh-Hant": {"JAV 视频，支持热门、搜索与 HLS 播放": "JAV 影片，支援熱門、搜尋與 HLS 播放"},
    "ja": {"JAV 视频，支持热门、搜索与 HLS 播放": "JAV 動画、人気作品・検索・HLS 再生に対応"},
    "ko": {"JAV 视频，支持热门、搜索与 HLS 播放": "인기 목록, 검색 및 HLS 재생을 지원하는 JAV 동영상"},
    "en": {"JAV 视频，支持热门、搜索与 HLS 播放": "JAV videos with popular feeds, search and HLS playback"},
    "es": {"JAV 视频，支持热门、搜索与 HLS 播放": "Videos JAV con populares, búsqueda y reproducción HLS"},
    "ru": {"JAV 视频，支持热门、搜索与 HLS 播放": "JAV: популярное, поиск и воспроизведение HLS"},
    "ar": {"JAV 视频，支持热门、搜索与 HLS 播放": "فيديوهات JAV مع قوائم شائعة وبحث وتشغيل HLS"},
  },
  key: 'jable', name: 'JableTV', version: '0.0.8', minAppVersion: '0.9.2', type: 'video', category: 'jav',
  color: '#14B8A6', description: 'JAV 视频，支持热门、搜索与 HLS 播放',
  homepage: 'https://jable.tv', domains: ['jable.tv'], language: 'zh-Hant',
  network: {mode: 'browser', origin: 'https://jable.tv', vpnHint: true},
  media: {mode: 'native', origin: 'https://jable.tv', domains: ['mushroomtrack.com']},
  imageHeaders: {Referer: 'https://jable.tv/'},
  linkPatterns: ['jable\\.tv/videos/([a-z0-9][a-z0-9-]{1,120})(?:/|[?#]|$)'],
  idPattern: '^[a-z0-9][a-z0-9-]{1,120}$', idExample: 'ipzz-961',
  rankings: [{key: 'today-hot', label: '今日热门', category: 'jav', section: 'site', metric: '站内热门', feed: 'today-hot'},
    {key: 'hot', label: '本周热门', category: 'jav', section: 'site', metric: '站内热门', feed: 'hot'},
    {key: 'monthly-hot', label: '本月热门', category: 'jav', section: 'site', metric: '站内热门', feed: 'monthly-hot'}],
  defaultFeed: 'hot', feeds: [{key: 'hot', label: '本周热门'}, {key: 'today-hot', label: '今日热门'},
    {key: 'monthly-hot', label: '本月热门'}, {key: 'new', label: '最近更新'}, {key: 'release', label: '最新上市'},
    {key: 'categories', label: '分类', options: [{key: 'category', label: '分类', default: '', dynamic: true, values: []}]}],
  searchHint: '搜索番号、作品名或演员',
  settings: [{key: 'quality', type: 'select', label: '默认清晰度', default: '1080', options: [
    {value: '1080', label: '1080P'}, {value: '720', label: '720P'}, {value: '480', label: '480P'}]}],
  // __CATALOG_START__：由 tools/build_catalog_sources.mjs 生成。
  async categoryDirectory() {
    if (this._categoryDirectory && Date.now() - this._categoryDirectory.time < 120000) return this._categoryDirectory.values;
    const config = {"home":"/","leaf":"^/categories/[a-zA-Z0-9_%+-]+/$","index":"^/categories/?$"}, leaf = new RegExp(config.leaf), index = config.index ? new RegExp(config.index) : null;
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
    const config = {"home":"/","leaf":"^/categories/[a-zA-Z0-9_%+-]+/$","index":"^/categories/?$"};
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
    const config = {"home":"/","leaf":"^/categories/[a-zA-Z0-9_%+-]+/$","index":"^/categories/?$"};
    return this[config.listMethod || 'listing'](category, request);
  },
  // __CATALOG_END__
  BASE: 'https://jable.tv',
  identity(id, labels = '') {
    const code = id.replace(/(?:-(?:uncensored-leak|uncensored|chinese-subtitle|english-subtitle))+$/, '');
    const editions = [], text = id + ' ' + labels;
    if (/uncensored-leak|无码流出|無碼流出/i.test(text)) editions.push('无码流出');
    else if (/uncensored|无码|無碼/i.test(text)) editions.push('无码');
    if (/chinese-subtitle|中文字幕/i.test(text)) editions.push('中文字幕');
    if (/english-subtitle|英文字幕/i.test(text)) editions.push('英文字幕');
    return {workCode: /^(?:\d{0,4}[a-z]{2,12}-\d{2,8}[a-z]?|fc2-ppv-\d{2,12})$/i.test(code) ? code.toUpperCase() : '', editions};
  },
  validId(id) {
    const value = String(id).toLowerCase();
    if (!/^[a-z0-9][a-z0-9-]{1,120}$/.test(value)) throw Park.error('NOT_FOUND', '影片编号无效');
    return value;
  },
  async getPage(path, params = {}) {
    const response = await this.http.get(this.BASE + path, {params});
    if (response.status === 404) throw Park.error('NOT_FOUND', '影片不存在');
    if (!response.ok) throw Park.error('HTTP', 'JableTV HTTP {value0}', { params: {value0: response.status},status: response.status});
    if (response.body.length > 4 * 1024 * 1024) throw Park.error('PARSE', '影片页面过大');
    return {html: response.body, doc: Park.html.parse(response.body)};
  },
  cards(doc) {
    const items = [];
    for (const card of doc.querySelectorAll('.video-img-box')) {
      const a = card.querySelector('.detail a[href]'), img = card.querySelector('.img-box img');
      const match = a && /^https:\/\/jable\.tv\/videos\/([a-z0-9][a-z0-9-]{1,120})\/$/.exec(a.getAttribute('href') || '');
      const cover = img && (img.getAttribute('data-src') || img.getAttribute('src'));
      const title = Park.html.text(a);
      if (!match || !title || !/^https:\/\//.test(cover || '') || items.some(i => i.id === match[1])) continue;
      const labels = [...card.querySelectorAll('.label, .badge')].map(Park.html.text).join(' ');
      items.push({id: match[1], title, cover, coverAspect: 16/9, duration: Park.html.text(card.querySelector('.label')), ...this.identity(match[1], labels)});
    }
    return items;
  },
  async listing(path, req, params = {}) {
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    const {doc} = await this.getPage(path + (page > 1 ? page + '/' : ''), params);
    let totalPages = page;
    for (const a of doc.querySelectorAll('.pagination a[href]')) {
      const m = /\/(\d+)\/(?:[?#]|$)/.exec(a.getAttribute('href') || '');
      if (m) totalPages = Math.max(totalPages, Number(m[1]));
    }
    return {items: this.cards(doc), page, totalPages, hasNext: page < totalPages};
  },
  async feed(key, req) {
    if (key === 'categories') return this.categoryFeed(req);
    const routes = {hot: ['/hot/', 'video_viewed_week'], 'today-hot': ['/hot/', 'video_viewed_today'],
      'monthly-hot': ['/hot/', 'video_viewed_month'], new: ['/latest-updates/'], release: ['/new-release/']};
    const route = routes[key];
    if (!route) throw Park.error('CONFIG', '未知视频列表');
    return this.listing(route[0], req, route[1] ? {sort_by: route[1]} : {});
  },
  async search(req) {
    const category = (req.filters || {}).category;
    if (typeof category === 'string' && /^\/(?:categories|tags|models)\/[a-zA-Z0-9_%+-]+\/$/.test(category)) return this.listing(category, req);
    const keyword = String(req.keyword || '').trim();
    if (!keyword) return {items: [], page: 1, totalPages: 1, hasNext: false};
    return this.listing('/search/' + encodeURIComponent(keyword) + '/', req);
  },
  async detail(id) {
    id = this.validId(id);
    const {doc} = await this.getPage('/videos/' + id + '/');
    const title = Park.html.text(doc.querySelector('.video-info h4'));
    if (!title) throw Park.error('NOT_FOUND', '影片不存在');
    const image = doc.querySelector('meta[property="og:image"]');
    const tags = [];
    for (const a of doc.querySelectorAll('.video-info .tags a[href], .video-info .models a[href]')) {
      const m = /^https:\/\/jable\.tv(\/(categories|tags|models)\/[a-zA-Z0-9_%+-]+\/)$/ .exec(a.getAttribute('href') || '');
      const tooltip = a.querySelector('[data-original-title], [title]');
      const name = tooltip && (tooltip.getAttribute('data-original-title') || tooltip.getAttribute('title')) || Park.html.text(a);
      if (m && name) tags.push({name, keyword: '', filters: {category: m[1]}});
    }
    const identity = this.identity(id, tags.map(tag => tag.name).join(' '));
    const related = this.cards(doc).filter(i => i.id !== id);
    return {id, title, cover: image ? image.getAttribute('content') : '', coverAspect: 16/9, ...identity,
      variants: identity.workCode ? related.filter(item => item.workCode === identity.workCode) : [],
      url: this.BASE + '/videos/' + id + '/', description: Park.html.text(doc.querySelector('.video-info .desc')),
      authors: tags.filter(t => t.filters.category.startsWith('/models/')).map(t => t.name),
      tags: tags.length ? [{namespace: 'tag', label: '标签', tags}] : [], related};
  },
  async videos(id) {
    id = this.validId(id);
    const {html} = await this.getPage('/videos/' + id + '/');
    const match = /\bhlsUrl\s*=\s*['"](https:\/\/[^'"\s]+)['"]/.exec(html);
    if (!match || !/^https:\/\/(?:[a-z0-9-]+\.)*mushroomtrack\.com\/[^\s]+\.m3u8(?:\?[^\s]*)?$/.test(match[1])) {
      throw Park.error('UNSUPPORTED', '此影片没有可用的 HLS 清晰度');
    }
    return [{url: match[1], quality: Number(this.config.quality) || 1080, label: '原画', format: 'hls', preferred: true,
      headers: {Referer: this.BASE + '/videos/' + id + '/', Origin: this.BASE}}];
  },
});

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"},{"key":"code","label":"完整番号","hint":"请输入完整番号，例如 ABP-123"}]});
