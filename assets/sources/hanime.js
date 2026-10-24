/* Hanime.tv：公开目录检索与应用内 HLS 播放。 */
Park.register({
  i18n: {
    "zh-Hant": {"影片列表解析失败":"影片列表解析失敗","里番目录、排行与搜索；支持应用内多清晰度播放":"裏番目錄、排行與搜尋；支援應用內多畫質播放","视频解析失败":"影片解析失敗"},
    "ja": {"影片列表解析失败":"動画一覧の解析に失敗しました","里番目录、排行与搜索；支持应用内多清晰度播放":"アニメのカタログ・ランキング・検索。アプリ内の複数画質再生に対応","视频解析失败":"動画の解析に失敗しました"},
    "ko": {"影片列表解析失败":"동영상 목록 분석 실패","里番目录、排行与搜索；支持应用内多清晰度播放":"애니메이션 목록, 순위 및 검색; 앱 내 다중 화질 재생 지원","视频解析失败":"동영상 분석 실패"},
    "en": {"影片列表解析失败":"Failed to parse video list","里番目录、排行与搜索；支持应用内多清晰度播放":"Anime catalog, rankings and search; supports in-app playback with multiple qualities","视频解析失败":"Failed to resolve video"},
    "es": {"影片列表解析失败":"No se pudo analizar la lista de vídeos","里番目录、排行与搜索；支持应用内多清晰度播放":"Catálogo de anime, clasificación y búsqueda; reproducción en la aplicación con varias calidades","视频解析失败":"No se pudo resolver el vídeo"},
    "ru": {"影片列表解析失败":"Не удалось разобрать список видео","里番目录、排行与搜索；支持应用内多清晰度播放":"Каталог аниме, рейтинг и поиск; воспроизведение в приложении с выбором качества","视频解析失败":"Не удалось получить видео"},
    "ar": {"影片列表解析失败":"تعذر تحليل قائمة الفيديو","里番目录、排行与搜索；支持应用内多清晰度播放":"دليل الأنمي والترتيب والبحث؛ تشغيل داخل التطبيق بجودات متعددة","视频解析失败":"تعذر تحليل الفيديو"},
  },
  key: 'hanime', name: 'Hanime.tv', version: '0.0.9', minAppVersion: '0.9.2', type: 'video', category: 'anime',
  language: 'en', color: '#EC407A', homepage: 'https://hanime.tv',
  description: '里番目录、排行与搜索；支持应用内多清晰度播放',
  domains: ['hanime.tv', 'hanime-cdn.com', 'guest.freeanimehentai.net'],
  network: {mode: 'native', vpnHint: true},
  media: {mode: 'native', origin: 'https://hanime.tv', scope: 'session'},
  imageHeaders: {Referer: 'https://hanime.tv/'},
  defaultFeed: 'rank', feeds: [{key: 'rank', label: '排行', options: [
    {key: 'tag', label: '标签', default: '', dynamic: true, values: []},
    {key: 'brand', label: '作者', default: '', dynamic: true, dependsOn: ['tag'], values: []},
  ]}, {key: 'trending', label: '热门'}],
  searchFilters: [
    {key: 'tag', label: '标签', default: '', dynamic: true, values: []},
    {key: 'brand', label: '作者', default: '', dynamic: true, dependsOn: ['tag'], values: []},
  ],
  linkPatterns: ['hanime\\.tv/videos/hentai/([a-z0-9-]+)'], idPattern: '^[a-z0-9-]{1,220}$',
  BASE: 'https://hanime.tv', database: null, databaseAt: 0, pendingDatabase: null,
  idValue(value) {
    if (!/^[a-z0-9][a-z0-9-]{0,219}$/.test(String(value))) throw Park.error('NOT_FOUND', '影片编号无效');
    return String(value);
  },
  cover(value) {
    // 封面 CDN 会更换主机，只要求是公网 HTTPS 地址。
    try { const u = new URL(String(value).trim(), this.BASE); return Park.url.parse(u.href, this.BASE, [u.hostname])?.href || ''; }
    catch (_) { return ''; }
  },
  item(row) {
    try {
      const id = this.idValue(row.slug), cover = this.cover(row.cover_url);
      if (!row.name) return null;
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
  tags(row) { return (Array.isArray(row.tags) ? row.tags : []).map(t => typeof t === 'string' ? t : t?.name || '').filter(Boolean); },
  async filterOptions(req) {
    if (req.scope === 'feed' && req.feed !== 'rank' || !['tag', 'brand'].includes(req.filter)) throw Park.error('CONFIG', '筛选参数无效');
    const rows = await this.records(), tag = String(req.values?.tag || '');
    const names = req.filter === 'tag' ? rows.flatMap(r => this.tags(r)) : rows.filter(r => !tag || this.tags(r).includes(tag)).map(r => r.brand).filter(Boolean);
    return [{value: '', label: '全部'}, ...[...new Set(names)].sort((a,b) => a.localeCompare(b)).map(value => ({value, label: value}))];
  },
  searchData(data, req, rank = false) {
    const page = Math.max(1, Math.floor(Number(req.page) || 1)), words = String(req.keyword || '').trim().toLowerCase().split(/\s+/).filter(Boolean);
    const options = rank ? req.options : req.filters;
    const tag = String(options?.tag || ''), brand = String(options?.brand || '');
    const rows = data.filter(x => (!tag || this.tags(x).includes(tag)) && (!brand || x.brand === brand) && words.every(w => [x.name, x.search_titles, x.description, x.brand, x.tags].map(v => Array.isArray(v) ? v.map(t => typeof t === 'object' ? t.name || '' : t).join(' ') : String(v || '')).join(' ').toLowerCase().includes(w)));
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
      if (!m || !title || !img || seen.has(m[1])) continue;
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
    if (!String(req.keyword || '').trim() && !req.filters?.tag && !req.filters?.brand) return {items: [], page: 1, hasNext: false};
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
  hex(bytes) {
    return Array.from(bytes, byte => byte.toString(16).padStart(2, '0')).join('');
  },
  encode(bytes) {
    return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  },
  decode(value) {
    if (typeof value !== 'string' || value.length > 12000 || !/^[A-Za-z0-9_-]+$/.test(value)) {
      throw Park.error('PARSE', '视频解析失败');
    }
    return Array.from(atob(value.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(value.length / 4) * 4, '=')), c => c.charCodeAt(0));
  },
  async playerHeaders(url, csrf) {
    const time = String(Math.floor(Date.now() / 1000));
    return {
      Referer: url, Origin: this.BASE,
      'x-signature-version': 'web2', 'x-time': time,
      'x-signature': await Park.crypto.sha256Hex(time + ',Xkdi29,' + this.BASE + ',mn2,' + time),
      'x-csrf-token': csrf,
    };
  },
  async videos(value) {
    const id = this.idValue(value);
    const url = this.BASE + '/videos/hentai/' + id;
    await this.page('/videos/hentai/' + id);
    // 公开播放器协议的密钥与附加认证数据，不读取或持久化账号凭据。
    const key = await Park.crypto.sha256Hex('htv-insecure-handshake-v1');
    const aad = this.hex(Array.from('htv-insecure-v1', c => c.charCodeAt(0)));
    let response;
    for (let attempt = 0; attempt < 2; attempt++) {
      const csrf = this.http.ensureOk(await this.http.get('https://ct.hanime.tv/csrf-token')).json();
      if (typeof csrf.csrf_token !== 'string' || !csrf.csrf_token) throw Park.error('PARSE', '视频解析失败');
      const iv = await Park.crypto.randomBytes(12);
      const payload = JSON.stringify({timestamp_unix: Math.floor(Date.now() / 1000), directive: 'htv_player_handshake', slug: id});
      const encrypted = await Park.crypto.aesGcmEncrypt(this.hex(Array.from(payload, c => c.charCodeAt(0))), key, this.hex(iv), aad);
      const envelope = JSON.stringify({v: 1, alg: 'AES-256-GCM', iv: this.encode(iv), tag: this.encode(encrypted.slice(-16)), data: this.encode(encrypted.slice(0, -16))});
      const token = this.encode(Array.from(envelope, c => c.charCodeAt(0)));
      response = await this.http.post('https://auth.hanime.tv/api/v11/handshake', {
        json: {token}, headers: await this.playerHeaders(url, csrf.csrf_token),
      });
      if (response.ok) break;
      let error; try { error = response.json().error_id; } catch (_) {}
      if (attempt || !/^CSRF_ERROR_[1-4]$/.test(error || '')) this.http.ensureOk(response);
    }
    let envelope;
    try { envelope = JSON.parse(String.fromCharCode(...this.decode(response.headers['x-token']))); }
    catch (_) { throw Park.error('PARSE', '视频解析失败'); }
    if (envelope.v !== 1 || envelope.alg !== 'AES-256-GCM') throw Park.error('PARSE', '视频解析失败');
    const ciphertext = [...this.decode(envelope.data), ...this.decode(envelope.tag)];
    let data;
    try {
      const plaintext = await Park.crypto.aesGcmDecrypt(this.hex(ciphertext), key, this.hex(this.decode(envelope.iv)), aad);
      data = JSON.parse(decodeURIComponent(escape(String.fromCharCode(...plaintext))));
    } catch (_) { throw Park.error('PARSE', '视频解析失败'); }
    const streams = [], seen = new Set();
    for (const source of Array.isArray(data.sources) ? data.sources : []) {
      // promotion 为会员升级入口，不能当作可播放的清晰度。
      if (source?.kind !== 'normal' || typeof source.src !== 'string' ||
          !/^\/hls\/\d+\/[A-Za-z0-9]{1,1024}$/.test(source.src) || seen.has(source.src)) continue;
      const quality = Number(source.height);
      if (!Number.isInteger(quality) || quality <= 0 || quality > 4320) continue;
      seen.add(source.src);
      streams.push({quality, label: quality + 'P', url: this.BASE + source.src, format: 'hls', headers: {Referer: url, Origin: this.BASE}});
    }
    if (!streams.length) throw Park.error('PARSE', '视频解析失败');
    return streams.sort((a, b) => b.quality - a.quality);
  },
});

Park.enableUpdateSubscriptions(Park.__pending, {dimensions: [
  {key: 'search', label: '搜索关键词', hint: '输入作品、作者或标签关键词'},
]});
