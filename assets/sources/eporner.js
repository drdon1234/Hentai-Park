/* Eporner：公开目录 API 与多清晰度 MP4。 */
Park.register({
  i18n: {
    "zh-Hant": {"成人视频目录、搜索与多清晰度 MP4": "成人影片目錄、搜尋與多畫質 MP4"},
    ja: {"成人视频目录、搜索与多清晰度 MP4": "成人動画の一覧・検索・複数画質 MP4"},
    ko: {"成人视频目录、搜索与多清晰度 MP4": "성인 동영상 카탈로그, 검색 및 다중 화질 MP4"},
    en: {"成人视频目录、搜索与多清晰度 MP4": "Adult video catalog, search and multi-quality MP4"},
    es: {"成人视频目录、搜索与多清晰度 MP4": "Catálogo de vídeos para adultos, búsqueda y MP4 multicalidad"},
    ru: {"成人视频目录、搜索与多清晰度 MP4": "Каталог видео для взрослых, поиск и MP4 разных качеств"},
    ar: {"成人视频目录、搜索与多清晰度 MP4": "دليل فيديو للبالغين مع البحث وملفات MP4 متعددة الجودة"},
  },
  key: 'eporner', name: 'Eporner', version: '0.0.7', minAppVersion: '0.9.2', type: 'video', category: 'adult', language: 'en',
  color: '#e84b39', homepage: 'https://www.eporner.com/', description: '成人视频目录、搜索与多清晰度 MP4',
  domains: ['eporner.com'], network: {mode: 'native', vpnHint: true},
  media: {mode: 'native', origin: 'https://www.eporner.com', domains: ['eporner.com']},
  imageNetwork: {mode: 'browser', origin: 'https://www.eporner.com', domains: ['eporner.com']},
  imageHeaders: {Referer: 'https://www.eporner.com/'},
  idPattern: '^[A-Za-z0-9]{1,32}$', defaultFeed: 'recommended', feeds: [{key: 'recommended', label: '推荐'},
    {key: 'categories', label: '分类', options: [{key: 'category', label: '分类', default: 'all', dynamic: true, values: []}]}],
  API: 'https://www.eporner.com/api/v2/video',
  validId(value) { const id = String(value || ''); if (!/^[A-Za-z0-9]{1,32}$/.test(id)) throw Park.error('NOT_FOUND', '视频编号无效'); return id; },
  async api(path, params) {
    const r = await this.http.get(this.API + path, {params: {...params, format: 'json'}, timeout: 30000});
    if (!r.ok) throw Park.error('HTTP', 'Eporner 请求失败', {status: r.status});
    try { return r.json(); } catch (_) { throw Park.error('PARSE', 'Eporner 返回的数据无效'); }
  },
  item(v) {
    const id = this.validId(v?.id), cover = String(v?.default_thumb?.src || v?.thumb || '');
    if (!id || !String(v?.title || '').trim() || !/^https:\/\//i.test(cover)) return null;
    return {id, title: String(v.title).trim(), cover, coverAspect: Number(v.default_thumb?.width) && Number(v.default_thumb?.height) ? Number(v.default_thumb.width) / Number(v.default_thumb.height) : 16 / 9, duration: String(v.length_min || ''), url: String(v.url || 'https://www.eporner.com/video-' + id + '/')};
  },
  async listing(req = {}, keyword) {
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    const data = await this.api('/search/', {query: keyword === undefined ? 'all' : String(keyword).slice(0, 100), per_page: 20, page, order: 'top-weekly'});
    const rows = Array.isArray(data?.videos) ? data.videos : [];
    const items = rows.map(v => this.item(v)).filter(Boolean);
    const total = Number(data?.total_pages || data?.total_count || 0);
    return {items, page, hasNext: total ? page < total : rows.length >= 20};
  },
  async html(path) {
    const url = 'https://www.eporner.com' + path, r = this.http.ensureOk(await this.http.get(url));
    if (new URL(r.url || url).origin !== 'https://www.eporner.com') throw Park.error('BLOCKED', '站点需要在浏览器中确认后访问');
    return Park.html.parse(r.body);
  },
  async filterOptions(req) {
    if (req.scope !== 'feed' || req.feed !== 'categories' || req.filter !== 'category') throw Park.error('CONFIG', '筛选参数无效');
    const doc = await this.html('/cats/'), values = new Map([['all', '全部']]);
    for (const a of doc.querySelectorAll('a[href]')) {
      let u; try { u = new URL(a.getAttribute('href'), 'https://www.eporner.com'); } catch (_) { continue; }
      const m = u.origin === 'https://www.eporner.com' && /^\/cat\/([a-z0-9-]+)\/$/.exec(u.pathname);
      const label = Park.html.text(a.querySelector('h2,h3,.ctt')) || a.querySelector('img')?.getAttribute('alt') || Park.html.text(a);
      if (m && m[1] !== 'all' && label && !values.has(m[1])) values.set(m[1], label);
    }
    if (values.size < 2) throw Park.error('PARSE', '分类列表解析失败');
    return [...values].map(([value,label]) => ({value,label}));
  },
  async categoryFeed(req = {}) {
    const slug = String(req.options?.category || 'all'), page = Math.max(1, Math.floor(Number(req.page) || 1));
    if (!/^[a-z0-9-]{1,100}$/.test(slug)) throw Park.error('CONFIG', '筛选参数无效');
    const path = '/cat/' + slug + '/' + (page > 1 ? page + '/' : ''), doc = await this.html(path), items = [], seen = new Set();
    for (const a of doc.querySelectorAll('a[href]')) {
      let u; try { u = new URL(a.getAttribute('href'), 'https://www.eporner.com'); } catch (_) { continue; }
      const m = u.origin === 'https://www.eporner.com' && /^\/video-([A-Za-z0-9]{1,32})\//.exec(u.pathname), img = a.querySelector('img');
      const cover = img?.getAttribute('data-src') || img?.getAttribute('src'), title = img?.getAttribute('alt');
      if (!m || !title || !cover || seen.has(m[1])) continue;
      const c = new URL(cover, u); if (c.protocol !== 'https:' || !c.hostname.endsWith('.eporner.com')) continue;
      seen.add(m[1]); items.push({id: m[1], title, cover: c.href, coverAspect: 16/9, url: u.href});
    }
    const next = doc.querySelector('a.nmnext[href]');
    return {items, page, hasNext: !!next && new URL(next.getAttribute('href'), 'https://www.eporner.com').pathname === '/cat/' + slug + '/' + (page + 1) + '/'};
  },
  async feed(key, req) { if (key === 'categories') return this.categoryFeed(req); if (key !== 'recommended') throw Park.error('CONFIG', '未知推荐列表'); return this.listing(req); },
  async search(req) { const q = String(req?.keyword || '').trim(); return q ? this.listing(req, q) : {items: [], page: 1, hasNext: false}; },
  async detail(value) {
    const id = this.validId(value), data = await this.api('/id/', {id});
    const v = data?.video || data; const item = this.item(v);
    if (!item) throw Park.error('NOT_FOUND', '视频不存在');
    return {...item, description: String(v.description || ''), tags: String(v.keywords || '').split(',').map(x => x.trim()).filter(Boolean).map(name => ({name, keyword: name})), chapters: null};
  },
  async videos(value) {
    const id = this.validId(value), data = await this.api('/id/', {id}), v = data?.video || data;
    let hash = String(v?.hash || ''), out = [];
    const pageUrl = String(v?.url || 'https://www.eporner.com/video-' + id + '/');
    if (!hash) {
      const page = await this.http.get(pageUrl, {timeout: 30000});
      if (!page.ok) throw Park.error('HTTP', 'Eporner 详情页请求失败', {status: page.status});
      const match = String(page.body || '').match(/EP\.video\.player\.hash\s*=\s*['\"]([a-f0-9]{32})['\"]/i);
      hash = match ? match[1] : '';
    }
    if (!hash) throw Park.error('UNSUPPORTED', '此视频没有可用的 MP4');
    let transformed = '';
    for (let i = 0; i < 32; i += 8) transformed += parseInt(hash.slice(i, i + 8), 16).toString(36);
    const r = await this.http.get('https://www.eporner.com/xhr/video/' + encodeURIComponent(id), {params: {hash: transformed, device: 'generic', domain: 'www.eporner.com', fallback: 'false'}});
    if (!r.ok) throw Park.error('HTTP', 'Eporner 媒体请求失败', {status: r.status});
    let mediaData; try { mediaData = r.json(); } catch (_) { throw Park.error('PARSE', 'Eporner 返回的媒体无效'); }
    for (const [label, entry] of Object.entries(mediaData?.sources?.mp4 || mediaData?.sources || {})) {
      const url = typeof entry === 'string' ? entry : entry?.src;
      if (!/^https:\/\//i.test(String(url))) continue;
      const quality = Number(String(label).replace(/\D/g, '')) || 0; out.push({url: String(url), format: 'mp4', label: quality ? quality + 'P' : label, quality, headers: {Referer: 'https://www.eporner.com/'}});
    }
    out.sort((a, b) => b.quality - a.quality); if (out[0]) out[0].preferred = true;
    if (!out.length) throw Park.error('UNSUPPORTED', '此视频没有可用的 MP4'); return out;
  },
});
