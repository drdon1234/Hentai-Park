/* PornPics：公开图集与 JSON 分页，页面脚本不执行。 */
Park.register({
  i18n: {
    "zh-Hant": {"国际写真图集，支持评分榜、热门、搜索与整套原图阅读": "國際寫真圖集，支援評分榜、熱門、搜尋與整套原圖閱讀", "图集列表解析失败": "圖集列表解析失敗", "图集地址无效": "圖集位址無效"},
    "ja": {"国际写真图集，支持评分榜、热门、搜索与整套原图阅读": "写真ギャラリー。評価順・人気順・検索・全原画像の閲覧に対応", "图集列表解析失败": "ギャラリー一覧の解析に失敗しました", "图集地址无效": "ギャラリーの URL が無効です"},
    "ko": {"国际写真图集，支持评分榜、热门、搜索与整套原图阅读": "사진 갤러리; 평점순, 인기순, 검색 및 전체 원본 이미지 보기 지원", "图集列表解析失败": "갤러리 목록 분석 실패", "图集地址无效": "갤러리 주소가 올바르지 않습니다"},
    "en": {"国际写真图集，支持评分榜、热门、搜索与整套原图阅读": "Photo galleries with ratings, popular lists, search and full original-image sets", "图集列表解析失败": "Failed to parse gallery list", "图集地址无效": "Invalid gallery URL"},
    "es": {"国际写真图集，支持评分榜、热门、搜索与整套原图阅读": "Galerías de fotos con clasificación, populares, búsqueda e imágenes originales completas", "图集列表解析失败": "No se pudo analizar la lista de galerías", "图集地址无效": "URL de galería no válida"},
    "ru": {"国际写真图集，支持评分榜、热门、搜索与整套原图阅读": "Фотогалереи: рейтинг, популярное, поиск и просмотр всех оригиналов", "图集列表解析失败": "Не удалось разобрать список галерей", "图集地址无效": "Недопустимый адрес галереи"},
    "ar": {"国际写真图集，支持评分榜、热门、搜索与整套原图阅读": "معارض صور مع التقييم والشائع والبحث وعرض جميع الصور الأصلية", "图集列表解析失败": "تعذر تحليل قائمة المعارض", "图集地址无效": "عنوان المعرض غير صالح"},
  },
  key: 'pornpics', name: 'PornPics', version: '0.0.10', minAppVersion: '0.9.2', type: 'comic', category: 'gallery',
  language: 'en', color: '#F16E24', homepage: 'https://www.pornpics.com',
  description: '国际写真图集，支持评分榜、热门、搜索与整套原图阅读',
  domains: ['pornpics.com'], network: {mode: 'native', vpnHint: true},
  imageHeaders: {Referer: 'https://www.pornpics.com/'},
  defaultFeed: 'rating', feeds: [{key: 'rating', label: '排行'}, {key: 'popular', label: '热门'},
    {key: 'categories', label: '分类', options: [{key: 'category', label: '分类', type: 'select', default: '', dynamic: true, values: []}]}],
  linkPatterns: ['pornpics\\.com/(?:[a-z]{2}/)?galleries/([a-z0-9-]+-\\d+)/'],
  idPattern: '^[a-z0-9-]+-\\d{1,12}$',
  // __CATALOG_START__：由 tools/build_catalog_sources.mjs 生成。
  async categoryDirectory() {
    if (this._categoryDirectory && Date.now() - this._categoryDirectory.time < 120000) return this._categoryDirectory.values;
    const config = {"home":"/","leaf":"^/[a-z0-9][a-z0-9-]*/$","selector":"#tiles a.rel-link[href]","pageMethod":"page","absolute":true,"listMethod":"categoryListing"}, leaf = new RegExp(config.leaf), index = config.index ? new RegExp(config.index) : null;
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
    const config = {"home":"/","leaf":"^/[a-z0-9][a-z0-9-]*/$","selector":"#tiles a.rel-link[href]","pageMethod":"page","absolute":true,"listMethod":"categoryListing"};
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
    const config = {"home":"/","leaf":"^/[a-z0-9][a-z0-9-]*/$","selector":"#tiles a.rel-link[href]","pageMethod":"page","absolute":true,"listMethod":"categoryListing"};
    return this[config.listMethod || 'listing'](category, request);
  },
  // __CATALOG_END__
  BASE: 'https://www.pornpics.com',
  feedParams: new Map(),
  idValue(value) {
    const id = String(value);
    if (id.length > 500 || !/^[a-z0-9][a-z0-9-]*-\d{1,12}$/.test(id)) throw Park.error('NOT_FOUND', '图集编号无效');
    return id;
  },
  siteUrl(value) { return Park.url.site(this, value); },
  // 图片 CDN 会更换主机，只要求是公网 HTTPS 地址；正文图片仍按页面结构选取。
  imageUrl(value) { return ((value, base) => { try { const u = new URL(String(value).trim(), base); return Park.url.parse(u.href, base, [u.hostname]); } catch (_) { return null; } })(value, this.BASE)?.href || ''; },
  remember(url) {
    const u = this.siteUrl(url), m = u && /^\/galleries\/([a-z0-9-]+-\d{1,12})\/$/.exec(u.pathname);
    if (!m) return null;
    return {id: m[1], url: u.href};
  },
  cards(doc) {
    const items = [], seen = new Set();
    for (const a of doc.querySelectorAll('a[data-gid][href]')) {
      const work = this.remember(a.getAttribute('href')), img = a.querySelector('img');
      const cover = this.imageUrl(img?.getAttribute('data-src') || img?.getAttribute('src'));
      const title = a.getAttribute('title') || img?.getAttribute('alt') || Park.html.text(a.closest('li')?.querySelector('.title,.thumb-title,.gallery-name')) || work?.url.split('/').filter(Boolean).pop().replace(/-\d+$/, '').replace(/-/g, ' ');
      if (!work || !title || seen.has(work.id)) continue;
      seen.add(work.id); items.push({...work, title, cover});
    }
    return items;
  },
  apiItems(data) {
    if (!Array.isArray(data)) throw Park.error('PARSE', '图集列表解析失败');
    const items = [], seen = new Set();
    for (const x of data) {
      if (!x || x.outLink) continue;
      const work = this.remember(x.g_url), cover = this.imageUrl(x.t_url_460 || x.t_url);
      if (!work || seen.has(work.id)) continue;
      const title = Park.html.strip(x.desc || '').trim() || new URL(work.url).pathname.split('/').filter(Boolean).pop().replace(/-\d+$/, '').replace(/-/g, ' ');
      if (!title) continue;
      seen.add(work.id); items.push({...work, title, cover});
    }
    return items;
  },
  async page(url) {
    if (!this.siteUrl(url)) throw Park.error('CONFIG', '图集地址无效');
    const r = this.http.ensureOk(await this.http.get(url));
    const finalUrl = Park.url.response(this, r, url);
    return {html: r.body, doc: Park.html.parse(r.body), url: finalUrl.href};
  },
  async feed(key, req) {
    if (key === 'categories') return this.categoryFeed(req);
    if (!['rating', 'popular'].includes(key)) throw Park.error('CONFIG', '未知列表');
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    if (page === 1 || !this.feedParams.has(key)) {
      const {html, doc} = await this.page(this.BASE + '/' + key + '/');
      const get = name => new RegExp('var\\s+' + name + '\\s*=\\s*[\"\x27]([^\"\x27]+)').exec(html)?.[1];
      const category = get('P_CID'), period = get('PP_PERIOD');
      if (!/^\d+$/.test(category || '') || !/^\d+$/.test(period || '')) throw Park.error('PARSE', '图集列表解析失败');
      this.feedParams.set(key, {category_id: category, period, lang: 'en', orientation: '3'});
      if (page === 1) return {items: this.cards(doc), page, hasNext: this.cards(doc).length >= 20};
    }
    const data = await this.http.json(this.BASE + '/popular/api/galleries/list/', {params: {...this.feedParams.get(key), offset: (page - 1) * 20, limit: 20}});
    return {items: this.apiItems(data), page, hasNext: data.length >= 20};
  },
  async categoryListing(category, req) {
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    if (page === 1) {
      const {doc} = await this.page(this.BASE + category), items = this.cards(doc);
      return {items, page, hasNext: items.length >= 20};
    }
    const data = await this.http.json(this.BASE + category, {
      headers: {'Content-Type': 'application/json'}, params: {offset: (page - 1) * 20, limit: 20},
    });
    return {items: this.apiItems(data), page, hasNext: data.length >= 20};
  },
  async search(req) {
    const keyword = String(req.keyword || '').trim(), page = Math.max(1, Math.floor(Number(req.page) || 1));
    if (!keyword) return {items: [], page, hasNext: false};
    const data = await this.http.json(this.BASE + '/search/srch.php', {params: {q: keyword, offset: (page - 1) * 20, limit: 20, lang: 'en'}});
    return {items: this.apiItems(data), page, hasNext: data.length >= 20};
  },
  async gallery(value, preview) {
    const id = this.idValue(value);
    const url = this.BASE + '/galleries/' + id + '/', data = await this.page(url);
    return {id, url, ...data};
  },
  parseImages(doc) {
    const pages = [], seen = new Set();
    for (const a of doc.querySelectorAll('#main a[data-tid][href]')) {
      const url = this.imageUrl(a.getAttribute('href'));
      if (!url || seen.has(url)) continue;
      seen.add(url); pages.push({url});
    }
    return pages;
  },
  // Gallery pages load related galleries in the browser from rel.pornpics.com, seeded by the page's PP_REL_CONF.
  async related(html, id) {
    const conf = /\bPP_REL_CONF\s*=\s*(\[[^\]\n]{0,4000}\])/.exec(html);
    if (!conf) return [];
    let data;
    try { data = JSON.parse(conf[1]); } catch (_) { return []; }
    if (!Array.isArray(data) || data.length > 50) return [];
    const r = await this.http.post('https://rel.pornpics.com/related/related_json.php', {readOnly: true, params: {offset: 0, limit: 20},
      headers: {Referer: this.BASE + '/'}, json: {data, lang: 'en', gid: /-(\d{1,12})$/.exec(id)[1], limit: 30}});
    if (!r.ok || r.body.length > 2 * 1024 * 1024) return [];
    try { return this.apiItems(JSON.parse(r.body)).filter(item => item.id !== id).slice(0, 30); } catch (_) { return []; }
  },
  async detail(value, preview) {
    const {id, url, html, doc} = await this.gallery(value, preview), pages = this.parseImages(doc);
    const title = Park.html.text(doc.querySelector('h1'));
    if (!title || !pages.length) throw Park.error('NOT_FOUND', '图集不存在');
    const tags = [...doc.querySelectorAll('.gallery-info .tags a[href]')].map(a => ({name: Park.html.text(a), keyword: Park.html.text(a)})).filter(x => x.name);
    const authors = [...doc.querySelectorAll('.gallery-info a[href*="/models/"]')].map(a => Park.html.text(a)).filter(Boolean);
    return {id, title, url, cover: pages[0].url, tags, authors, chapters: [{id: '_', title, count: pages.length}], related: await this.related(html, id)};
  },
  async chapter(value, chapterId) {
    if (chapterId && chapterId !== '_') throw Park.error('NOT_FOUND', '章节编号无效');
    const {doc} = await this.gallery(value), pages = this.parseImages(doc);
    if (!pages.length) throw Park.error('PARSE', '图集列表解析失败');
    return {pages};
  },
});

Park.enableUpdateSubscriptions(Park.__pending, {dimensions: [
  {key: 'search', label: '搜索关键词', hint: '输入作品、作者或话题关键词'},
]});
