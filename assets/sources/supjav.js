/* SupJav FST: parse bounded strings without executing remote JavaScript. */
Park.register({
  i18n: {
    "zh-Hant": {"FST 播放线路暂不可用": "FST 播放線路暫不可用", "JAV 视频，支持热门、搜索与 FST 线路播放": "JAV 影片，支援熱門、搜尋與 FST 線路播放", "中文字幕": "中文字幕", "无码": "無碼", "此影片没有可用的 FST 线路": "此影片沒有可用的 FST 線路"},
    "ja": {"FST 播放线路暂不可用": "FST サーバーは一時的に利用できません", "JAV 视频，支持热门、搜索与 FST 线路播放": "JAV 動画、人気作品・検索・FST 再生に対応", "中文字幕": "中国語字幕", "无码": "無修正", "此影片没有可用的 FST 线路": "利用可能な FST サーバーがありません"},
    "ko": {"FST 播放线路暂不可用": "FST 서버를 일시적으로 사용할 수 없습니다", "JAV 视频，支持热门、搜索与 FST 线路播放": "인기 목록, 검색 및 FST 재생을 지원하는 JAV 동영상", "中文字幕": "중국어 자막", "无码": "무수정", "此影片没有可用的 FST 线路": "사용 가능한 FST 서버가 없습니다"},
    "en": {"FST 播放线路暂不可用": "The FST server is temporarily unavailable", "JAV 视频，支持热门、搜索与 FST 线路播放": "JAV videos with popular feeds, search and FST playback", "中文字幕": "Chinese subtitles", "无码": "Uncensored", "此影片没有可用的 FST 线路": "This video has no available FST server"},
    "es": {"FST 播放线路暂不可用": "El servidor FST no está disponible temporalmente", "JAV 视频，支持热门、搜索与 FST 线路播放": "Videos JAV con populares, búsqueda y reproducción FST", "中文字幕": "Subtítulos en chino", "无码": "Sin censura", "此影片没有可用的 FST 线路": "Este video no tiene un servidor FST disponible"},
    "ru": {"FST 播放线路暂不可用": "Сервер FST временно недоступен", "JAV 视频，支持热门、搜索与 FST 线路播放": "JAV: популярное, поиск и воспроизведение FST", "中文字幕": "Китайские субтитры", "无码": "Без цензуры", "此影片没有可用的 FST 线路": "Для этого видео нет доступного сервера FST"},
    "ar": {"FST 播放线路暂不可用": "خادم FST غير متاح مؤقتًا", "JAV 视频，支持热门、搜索与 FST 线路播放": "فيديوهات JAV مع قوائم شائعة وبحث وتشغيل FST", "中文字幕": "ترجمة صينية", "无码": "غير خاضع للرقابة", "此影片没有可用的 FST 线路": "لا يوجد خادم FST متاح لهذا الفيديو"},
  },
  key: 'supjav', name: 'SupJav', version: '0.0.9', minAppVersion: '0.9.2', type: 'video', category: 'jav', color: '#F59E0B',
  description: 'JAV 视频，支持热门、搜索与 FST 线路播放',
  homepage: 'https://supjav.com', domains: ['supjav.com', 'lk1.supremejav.com', 'fc2stream.tv'], language: 'zh',
  network: {mode: 'browser', origin: 'https://supjav.com', vpnHint: true},
  media: {mode: 'native', origin: 'https://fc2stream.tv', domains: ['cdn-centaurus.com', 'premilkyway.com']},
  imageHeaders: {Referer: 'https://supjav.com/'},
  linkPatterns: ['supjav\\.com/(?:(?:zh|en|ja)/)?([0-9]{1,12})\\.html(?:[?#]|$)'],
  idPattern: '^[0-9]{1,12}$', idExample: '455086',
  rankings: [{key: 'today-hot', label: '今日热门', category: 'jav', section: 'site', metric: '站内热门', feed: 'today-hot'},
    {key: 'hot', label: '本周热门', category: 'jav', section: 'site', metric: '站内热门', feed: 'hot'},
    {key: 'monthly-hot', label: '本月热门', category: 'jav', section: 'site', metric: '站内热门', feed: 'monthly-hot'}],
  defaultFeed: 'hot', feeds: [{key: 'hot', label: '本周热门'}, {key: 'today-hot', label: '今日热门'},
    {key: 'monthly-hot', label: '本月热门'}, {key: 'new', label: '最近更新'},
    {key: 'chinese', label: '中文字幕'}, {key: 'uncensored', label: '无码'},
    {key: 'categories', label: '分类', options: [{key: 'category', label: '分类', default: '', dynamic: true, values: []}]}],
  searchHint: '搜索番号、作品名或演员',
  settings: [{key: 'quality', type: 'select', label: '默认清晰度', default: '1080', options: [
    {value: '1080', label: '1080P'}, {value: '720', label: '720P'}, {value: '480', label: '480P'}]}],
  // __CATALOG_START__：由 tools/build_catalog_sources.mjs 生成。
  async categoryDirectory() {
    if (this._categoryDirectory && Date.now() - this._categoryDirectory.time < 120000) return this._categoryDirectory.values;
    const config = {"home":"/zh","leaf":"^/zh/category/[a-zA-Z0-9_%+-]+/?$","index":"^/zh/category/?$"}, leaf = new RegExp(config.leaf), index = config.index ? new RegExp(config.index) : null;
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
    const config = {"home":"/zh","leaf":"^/zh/category/[a-zA-Z0-9_%+-]+/?$","index":"^/zh/category/?$"};
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
    const config = {"home":"/zh","leaf":"^/zh/category/[a-zA-Z0-9_%+-]+/?$","index":"^/zh/category/?$"};
    return this[config.listMethod || 'listing'](category, request);
  },
  // __CATALOG_END__
  BASE: 'https://supjav.com',
  validId(id) {
    const value = String(id);
    if (!/^[0-9]{1,12}$/.test(value)) throw Park.error('NOT_FOUND', '影片编号无效');
    return value;
  },
  async getPage(path, params = {}) {
    const response = await this.http.get(this.BASE + path, {params});
    if (response.status === 404) throw Park.error('NOT_FOUND', '影片不存在');
    if (!response.ok) throw Park.error('HTTP', 'SupJav HTTP {value0}', { params: {value0: response.status},status: response.status});
    if (response.body.length > 4 * 1024 * 1024) throw Park.error('PARSE', '影片页面过大');
    const doc = Park.html.parse(response.body);
    // 站点可能以 HTTP 200 返回 404 模板，不能将其当作空列表。
    if (doc.querySelector('.e404')) throw Park.error('NOT_FOUND', '影片不存在');
    return {html: response.body, doc};
  },
  identity(title, labels = '') {
    const match = /^\s*(?:\[[^\]]{1,40}\]\s*|【[^】]{1,40}】\s*)*(FC2[- ]?PPV[- ]?\d{2,12}|\d{0,4}[a-z]{2,12}-\d{2,8}[a-z]?)(?=\s|$)/i.exec(title);
    const workCode = match ? match[1].replace(/^FC2[- ]?PPV[- ]?/i, 'FC2-PPV-').toUpperCase() : '';
    const text = (match ? title.slice(0, match.index + match[0].length - match[1].length) : '') + ' ' + labels;
    const editions = [];
    if (/无码破解|無碼破解|reducing-mosaic/i.test(text)) editions.push('无码破解');
    else if (/无码|無碼|uncensored-jav/i.test(text)) editions.push('无码');
    else if (/有码|有碼|censored-jav/i.test(text)) editions.push('有码');
    if (/中文字幕|chinese-subtitles/i.test(text)) editions.push('中文字幕');
    if (/英文字幕|english-subtitles/i.test(text)) editions.push('英文字幕');
    return {workCode, editions};
  },
  variants(doc, id, title) {
    const code = this.identity(title).workCode;
    if (!code) return [];
    const items = [];
    for (const a of doc.querySelectorAll('a[href]')) {
      const match = /^https:\/\/supjav\.com\/zh\/([0-9]{1,12})\.html$/.exec(a.getAttribute('href') || '');
      const name = Park.html.text(a), identity = this.identity(name);
      if (!match || match[1] === id || identity.workCode !== code || items.some(item => item.id === match[1])) continue;
      items.push({id: match[1], title: name, ...identity});
    }
    return items;
  },
  cards(doc) {
    const items = [];
    for (const card of doc.querySelectorAll('div.post')) {
      const a = card.querySelector('h3 a[href]'), img = card.querySelector('img.thumb');
      const m = a && /^https:\/\/supjav\.com\/(?:zh\/)?([0-9]{1,12})\.html$/.exec(a.getAttribute('href') || '');
      const title = Park.html.text(a), cover = img && (img.getAttribute('data-original') || img.getAttribute('src'));
      if (!m || !title || !/^https:\/\//.test(cover || '') || items.some(i => i.id === m[1])) continue;
      items.push({id: m[1], title, cover, coverAspect: 320/216, ...this.identity(title)});
    }
    return items;
  },
  async listing(path, req, params = {}) {
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    const {doc} = await this.getPage(path.replace(/\/$/, '') + (page > 1 ? '/page/' + page + '/' : '/'), params);
    let totalPages = page;
    for (const a of doc.querySelectorAll('.pagination a[href], .wp-pagenavi a[href]')) {
      const m = /\/page\/(\d+)(?:\/|[?#]|$)/.exec(a.getAttribute('href') || '');
      if (m) totalPages = Math.max(totalPages, Number(m[1]));
    }
    return {items: this.cards(doc), page, totalPages, hasNext: page < totalPages};
  },
  async feed(key, req) {
    if (key === 'categories') return this.categoryFeed(req);
    const routes = {hot: ['/zh/popular', 'week'], 'today-hot': ['/zh/popular', 'day'], 'monthly-hot': ['/zh/popular', 'month'],
      new: ['/zh'], chinese: ['/zh/category/chinese-subtitles'], uncensored: ['/zh/category/uncensored-jav']};
    const route = routes[key];
    if (!route) throw Park.error('CONFIG', '未知视频列表');
    return this.listing(route[0], req, route[1] ? {sort: route[1]} : {});
  },
  async search(req) {
    const category = (req.filters || {}).category;
    if (typeof category === 'string' && /^\/zh\/(?:category|tag)\/[a-zA-Z0-9_%+-]+(?:\/[a-zA-Z0-9_%+-]+)?\/?$/.test(category)) return this.listing(category, req);
    const keyword = String(req.keyword || '').trim();
    if (!keyword) return {items: [], page: 1, totalPages: 1, hasNext: false};
    return this.listing('/zh', req, {s: keyword});
  },
  async detail(id) {
    id = this.validId(id);
    const {doc} = await this.getPage('/zh/' + id + '.html');
    const title = Park.html.text(doc.querySelector('.archive-title h1'));
    if (!title) throw Park.error('NOT_FOUND', '影片不存在');
    const img = doc.querySelector('.video-wrap img.img') || doc.querySelector('img.img');
    const tags = [], authors = [];
    for (const a of doc.querySelectorAll('.post-meta .tags a[href], .post-meta .cats a[href]')) {
      const m = /^https:\/\/supjav\.com(\/zh\/(?:category|tag)\/[a-zA-Z0-9_%+-]+(?:\/[a-zA-Z0-9_%+-]+)?\/?$)/.exec(a.getAttribute('href') || '');
      const name = Park.html.text(a);
      if (!m || !name) continue;
      if (m[1].includes('/category/cast/')) authors.push(name);
      if (!tags.some(t => t.filters.category === m[1])) tags.push({name, keyword: '', filters: {category: m[1]}});
    }
    const editionTags = [...doc.querySelectorAll('.post-meta .cats a[href]')].map(a => a.getAttribute('href') || '').join(' ');
    return {id, title, cover: img ? img.getAttribute('src') : '', coverAspect: 16/9, url: this.BASE + '/zh/' + id + '.html', authors,
      ...this.identity(title, editionTags), variants: this.variants(doc, id, title),
      tags: tags.length ? [{namespace: 'tag', label: '标签', tags}] : [], related: this.cards(doc).filter(i => i.id !== id)};
  },
  packedMedia(html) {
    if (html.length > 4 * 1024 * 1024) throw Park.error('PARSE', '影片页面过大');
    const out = [], literal = s => s.replace(/\\(u[0-9a-f]{4}|x[0-9a-f]{2}|[\\'"nrt])/gi, (_, e) =>
      e[0] === 'u' || e[0] === 'x' ? String.fromCharCode(parseInt(e.slice(1), 16)) : ({n:'\n', r:'\r', t:'\t'})[e] || e);
    const packed = /\}\s*\(\s*'((?:\\.|[^'\\])*)'\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*'((?:\\.|[^'\\])*)'\.split\('\|'\)/g;
    for (const m of html.matchAll(packed)) {
      const radix = Number(m[2]), count = Number(m[3]);
      if (radix < 2 || radix > 62 || count > 10000) continue;
      const words = literal(m[4]).split('|'), dictionary = new Map();
      const encode = n => n < radix ? (n > 35 ? String.fromCharCode(n + 29) : n.toString(36)) : encode(Math.floor(n/radix)) + encode(n%radix);
      for (let i=0; i<count; i++) if (words[i]) dictionary.set(encode(i), words[i]);
      out.push(literal(m[1]).replace(/\b[0-9a-zA-Z]+\b/g, w => dictionary.get(w) || w));
    }
    return out;
  },
  async videos(id) {
    const {doc} = await this.getPage('/zh/' + this.validId(id) + '.html');
    const server = [...doc.querySelectorAll('a.btn-server[data-link]')].find(a => Park.html.text(a) === 'FST');
    const token = server && server.getAttribute('data-link');
    if (!/^[a-zA-Z0-9]{32,512}$/.test(token || '')) throw Park.error('UNSUPPORTED', '此影片没有可用的 FST 线路');
    const response = await this.http.get('https://lk1.supremejav.com/supjav.php', {
      mode: 'native', params: {l: token}, headers: {Referer: this.BASE + '/'}});
    // Only the verified FST origin can supply media and its Referer. No eval or iframe execution.
    if (!/^https:\/\/fc2stream\.tv\/[^\s]*$/.test(response.url || '') || !response.ok) throw Park.error('UNSUPPORTED', 'FST 播放线路暂不可用');
    const playerUrl = response.url.split('#')[0];
    // Native redirects deliberately drop cross-origin Referer. Once the FST
    // destination is validated, request that page explicitly with its required header.
    const player = await this.http.get(playerUrl, {mode: 'native', headers: {Referer: this.BASE + '/'}});
    if (!player.ok || !/^https:\/\/fc2stream\.tv\/[^\s]*$/.test(player.url || '')) throw Park.error('UNSUPPORTED', 'FST 播放线路暂不可用');
    for (const payload of this.packedMedia(player.body)) {
      const m = /https:\/\/(?:[a-z0-9-]+\.)*(?:cdn-centaurus\.com|premilkyway\.com)\/[^'"\s\\]+\.m3u8(?:\?[^'"\s\\]*)?/.exec(payload);
      if (m) return [{url: m[0], quality: Number(this.config.quality) || 1080, format: 'hls', preferred: true,
        headers: {Referer: player.url.split('#')[0], Origin: 'https://fc2stream.tv'}}];
    }
    throw Park.error('UNSUPPORTED', '此影片没有可用的 HLS 清晰度');
  },
});

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"},{"key":"code","label":"完整番号","hint":"请输入完整番号，例如 ABP-123"}]});
