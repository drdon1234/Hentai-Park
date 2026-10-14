/* Hanime.tv：公开目录检索；未验证的播放器握手不冒充本地媒体。 */
Park.register({
  i18n: {
    "zh-Hant": {"影片列表解析失败": "影片列表解析失敗", "里番目录、排行与搜索；播放需打开原站": "裏番目錄、排行與搜尋；播放需開啟原站"},
    "ja": {"影片列表解析失败": "動画一覧の解析に失敗しました", "里番目录、排行与搜索；播放需打开原站": "アニメのカタログ・ランキング・検索。再生は元サイトで"},
    "ko": {"影片列表解析失败": "동영상 목록 분석 실패", "里番目录、排行与搜索；播放需打开原站": "애니메이션 목록, 순위 및 검색; 재생은 원본 사이트에서"},
    "en": {"影片列表解析失败": "Failed to parse video list", "里番目录、排行与搜索；播放需打开原站": "Anime catalog, rankings and search; open the original site to play"},
    "es": {"影片列表解析失败": "No se pudo analizar la lista de vídeos", "里番目录、排行与搜索；播放需打开原站": "Catálogo de anime, clasificación y búsqueda; reproducción en el sitio original"},
    "ru": {"影片列表解析失败": "Не удалось разобрать список видео", "里番目录、排行与搜索；播放需打开原站": "Каталог аниме, рейтинг и поиск; просмотр на исходном сайте"},
    "ar": {"影片列表解析失败": "تعذر تحليل قائمة الفيديو", "里番目录、排行与搜索；播放需打开原站": "دليل الأنمي والترتيب والبحث؛ التشغيل على الموقع الأصلي"},
  },
  key: 'hanime', name: 'Hanime.tv', version: '0.0.3', type: 'video', category: 'anime',
  language: 'en', color: '#EC407A', homepage: 'https://hanime.tv',
  description: '里番目录、排行与搜索；播放需打开原站',
  domains: ['hanime.tv', 'hanime-cdn.com', 'guest.freeanimehentai.net'],
  network: {mode: 'native', vpnHint: true},
  imageHeaders: {Referer: 'https://hanime.tv/'},
  defaultFeed: 'rank', feeds: [{key: 'rank', label: '排行'}, {key: 'trending', label: '热门'}],
  linkPatterns: ['hanime\\.tv/videos/hentai/([a-z0-9-]+)'], idPattern: '^[a-z0-9-]{1,220}$',
  BASE: 'https://hanime.tv', database: null, databaseAt: 0, pendingDatabase: null,
  idValue(value) {
    if (!/^[a-z0-9][a-z0-9-]{0,219}$/.test(String(value))) throw Park.error('NOT_FOUND', '影片编号无效');
    return String(value);
  },
  cover(value) {
    try { const u = new URL(value); return u.protocol === 'https:' && u.hostname === 'hanime-cdn.com' && !u.port && !u.username && !u.password ? u.href : ''; }
    catch (_) { return ''; }
  },
  item(row) {
    try {
      const id = this.idValue(row.slug), cover = this.cover(row.cover_url);
      if (!row.name || !cover) return null;
      return {id, title: row.name, cover, url: this.BASE + '/videos/hentai/' + id, uploader: row.brand || ''};
    } catch (_) { return null; }
  },
  async records() {
    if (this.database && Date.now() - this.databaseAt < 15 * 60 * 1000) return this.database;
    if (!this.pendingDatabase) this.pendingDatabase = (async () => {
      const r = this.http.ensureOk(await this.http.get('https://guest.freeanimehentai.net/api/v11/search_hvs'));
      if (r.body.length > 12 * 1024 * 1024) throw Park.error('PARSE', '影片列表解析失败');
      const data = r.json(), rows = Array.isArray(data) ? data : data.data;
      if (!Array.isArray(rows)) throw Park.error('PARSE', '影片列表解析失败');
      this.database = rows.filter(x => x && typeof x.slug === 'string' && typeof x.name === 'string');
      this.databaseAt = Date.now(); return this.database;
    })().finally(() => { this.pendingDatabase = null; });
    return this.pendingDatabase;
  },
  searchData(data, req, rank = false) {
    const page = Math.max(1, Math.floor(Number(req.page) || 1)), words = String(req.keyword || '').trim().toLowerCase().split(/\s+/).filter(Boolean);
    const rows = data.filter(x => words.every(w => [x.name, x.search_titles, x.description, x.brand, x.tags].map(v => Array.isArray(v) ? v.map(t => typeof t === 'object' ? t.name || '' : t).join(' ') : String(v || '')).join(' ').toLowerCase().includes(w)));
    rows.sort((a, b) => rank ? Number(b.views || 0) - Number(a.views || 0) : Number(b.created_at_unix || 0) - Number(a.created_at_unix || 0));
    const items = rows.slice((page - 1) * 24, page * 24).map(x => this.item(x)).filter(Boolean);
    return {items, page, hasNext: page * 24 < rows.length, totalPages: Math.ceil(rows.length / 24)};
  },
  async page(path) {
    const r = this.http.ensureOk(await this.http.get(this.BASE + path));
    if (new URL(r.url || this.BASE).origin !== this.BASE) throw Park.error('BLOCKED', '站点需要在浏览器中确认后访问');
    return Park.html.parse(r.body);
  },
  cards(doc) {
    const out = [], seen = new Set();
    for (const a of doc.querySelectorAll('main a[href*="/videos/hentai/"]')) {
      let u; try { u = new URL(a.getAttribute('href'), this.BASE); } catch (_) { continue; }
      const m = u.origin === this.BASE && /^\/videos\/hentai\/([a-z0-9-]+)$/.exec(u.pathname);
      const img = a.querySelector('img'), title = Park.html.text(a.querySelector('h3')) || img?.getAttribute('alt');
      const cover = this.cover(img?.getAttribute('src'));
      if (!m || !title || !cover || seen.has(m[1])) continue;
      seen.add(m[1]); out.push({id: m[1], title, cover, url: u.href});
    }
    return out;
  },
  async feed(key, req) {
    if (key === 'rank') return this.searchData(await this.records(), {...req, keyword: ''}, true);
    if (key !== 'trending') throw Park.error('CONFIG', '未知列表');
    if (Number(req.page) > 1) return {items: [], page: Number(req.page), hasNext: false};
    return {items: this.cards(await this.page('/browse/trending')), page: 1, hasNext: false};
  },
  async search(req) {
    if (!String(req.keyword || '').trim()) return {items: [], page: 1, hasNext: false};
    return this.searchData(await this.records(), req);
  },
  async detail(value) {
    const id = this.idValue(value), url = this.BASE + '/videos/hentai/' + id, doc = await this.page('/videos/hentai/' + id);
    let meta;
    for (const script of doc.querySelectorAll('script[type="application/ld+json"]')) {
      try { const x = JSON.parse(script.textContent); if (x['@type'] === 'VideoObject') { meta = x; break; } } catch (_) {}
    }
    if (!meta?.name) throw Park.error('NOT_FOUND', '影片不存在');
    const tags = [...doc.querySelectorAll('main a[href*="/browse/tags/"]')].map(a => ({name: Park.html.text(a), keyword: Park.html.text(a)})).filter(x => x.name);
    return {id, title: meta.name, cover: this.cover(meta.thumbnailUrl), url, description: meta.description || '', duration: meta.duration || '', chapters: null, tags, authors: [], related: this.cards(doc).filter(x => x.id !== id)};
  },
});
