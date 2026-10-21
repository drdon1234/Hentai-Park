/* rou.video 成人视频源：视频库、分类、搜索与原生 PNG-HLS 播放。 */
Park.register({
  i18n: {
    "zh-Hant": {
      "肉视频": "肉視頻",
      "肉视频短剧": "肉視頻短劇",
      "成人视频库，支持分类、搜索与原生 HLS 播放": "成人影片庫，支援分類、搜尋與原生 HLS 播放",
      "AI短剧，支持推荐、搜索和分集播放": "AI短劇，支援推薦、搜尋和分集播放",
      "国产AV": "國產AV",
      "麻豆传媒": "麻豆傳媒",
      "自拍流出": "自拍流出",
      "探花": "探花",
      "现代": "現代",
      "都市": "都市",
      "熟女": "熟女"
    },
    "ja": {
      "肉视频": "RouVideo",
      "肉视频短剧": "RouVideo ショートドラマ",
      "成人视频库，支持分类、搜索与原生 HLS 播放": "カテゴリ、検索、ネイティブ HLS 再生に対応する成人動画",
      "AI短剧，支持推荐、搜索和分集播放": "おすすめ、検索、エピソード再生に対応する AI ショートドラマ",
      "国产AV": "中国AV",
      "麻豆传媒": "麻豆メディア",
      "自拍流出": "自撮り",
      "探花": "出会い動画",
      "现代": "現代",
      "都市": "都市",
      "熟女": "熟女"
    },
    "ko": {
      "肉视频": "RouVideo",
      "肉视频短剧": "RouVideo 숏드라마",
      "成人视频库，支持分类、搜索与原生 HLS 播放": "분류, 검색 및 기본 HLS 재생을 지원하는 성인 동영상",
      "AI短剧，支持推荐、搜索和分集播放": "추천, 검색 및 회차별 재생을 지원하는 AI 숏드라마",
      "国产AV": "중국 AV",
      "麻豆传媒": "마도우 미디어",
      "自拍流出": "셀프 촬영",
      "探花": "만남 영상",
      "现代": "현대",
      "都市": "도시",
      "熟女": "성숙한 여성"
    },
    "en": {
      "肉视频": "RouVideo",
      "肉视频短剧": "RouVideo Shorts",
      "成人视频库，支持分类、搜索与原生 HLS 播放": "Adult video library with categories, search and native HLS playback",
      "AI短剧，支持推荐、搜索和分集播放": "AI short dramas with recommendations, search and episode playback",
      "国产AV": "Chinese AV",
      "麻豆传媒": "Madou Media",
      "自拍流出": "Amateur",
      "探花": "Dating videos",
      "现代": "Modern",
      "都市": "Urban",
      "熟女": "Mature"
    },
    "es": {
      "肉视频": "RouVideo",
      "肉视频短剧": "Series cortas RouVideo",
      "成人视频库，支持分类、搜索与原生 HLS 播放": "Vídeos para adultos con categorías, búsqueda y reproducción HLS nativa",
      "AI短剧，支持推荐、搜索和分集播放": "Series cortas de IA con recomendaciones, búsqueda y episodios",
      "国产AV": "AV chino",
      "麻豆传媒": "Madou Media",
      "自拍流出": "Aficionados",
      "探花": "Vídeos de citas",
      "现代": "Moderno",
      "都市": "Urbano",
      "熟女": "Maduras"
    },
    "ru": {
      "肉视频": "RouVideo",
      "肉视频短剧": "Мини-сериалы RouVideo",
      "成人视频库，支持分类、搜索与原生 HLS 播放": "Видео для взрослых с категориями, поиском и встроенным HLS-плеером",
      "AI短剧，支持推荐、搜索和分集播放": "ИИ-мини-сериалы с рекомендациями, поиском и просмотром по сериям",
      "国产AV": "Китайское AV",
      "麻豆传媒": "Madou Media",
      "自拍流出": "Любительское",
      "探花": "Видео знакомств",
      "现代": "Современность",
      "都市": "Город",
      "熟女": "Зрелые"
    },
    "ar": {
      "肉视频": "RouVideo",
      "肉视频短剧": "مسلسلات RouVideo القصيرة",
      "成人视频库，支持分类、搜索与原生 HLS 播放": "مكتبة فيديو للبالغين مع تصنيفات وبحث وتشغيل HLS مدمج",
      "AI短剧，支持推荐、搜索和分集播放": "مسلسلات قصيرة بالذكاء الاصطناعي مع توصيات وبحث وحلقات",
      "国产AV": "أفلام صينية للبالغين",
      "麻豆传媒": "Madou Media",
      "自拍流出": "هواة",
      "探花": "فيديوهات مواعدة",
      "现代": "حديث",
      "都市": "حضري",
      "熟女": "ناضجات"
    }
  },
  key: 'rouvideo', name: '肉视频', version: '0.0.1', type: 'video', category: 'adult', color: '#E85D75',
  description: '成人视频库，支持分类、搜索与原生 HLS 播放', homepage: 'https://rou.video', domains: ['rou.video'], language: 'zh',
  linkPatterns: ['rou\\.video/v/([a-z0-9]+)(?:[/?#]|$)'], idPattern: '^[a-z0-9]{10,40}$',
  imageNetwork: {mode: 'browser', origin: 'https://rou.video', domains: ['v.rn252.xyz']},
  imageHeaders: {Referer: 'https://rou.video/'},
  media: {mode: 'native', scope: 'session', origin: 'https://rou.video'},
  network: {mode: 'native', vpnHint: true}, defaultFeed: 'recommend', searchHint: '搜索作品名或标签',
  feeds: [
    {key: 'recommend', label: '推荐'},
    {key: 'latest', label: '最新'},
    {key: 'category', label: '分类', options: [{key: 'category', label: '分类', type: 'select', default: 'all', values: [
      {value: 'all', label: '全部'}, {value: '自拍流出', label: '自拍流出'}, {value: '國產AV', label: '国产AV'}, {value: '探花', label: '探花'}, {value: '日本', label: '日本'}, {value: '麻豆傳媒', label: '麻豆传媒'}, {value: 'OnlyFans', label: 'OnlyFans'},
    ]}]},
  ],
  BASE: 'https://rou.video',
  id(value) { const id = String(value || ''); if (!/^[a-z0-9]{10,40}$/.test(id)) throw Park.error('NOT_FOUND', '影片编号无效'); return id; },
  page(value) { const page = value == null ? 1 : Number(value); if (!Number.isSafeInteger(page) || page < 1 || page > 100000) throw Park.error('CONFIG', '视频列表地址无效'); return page; },
  absolute(value) { if (typeof value !== 'string' || !value) return ''; try { const u = new URL(value, this.BASE); return u.protocol === 'https:' && !u.username && !u.password && !u.port && ['rou.video', 'v.rn252.xyz'].includes(u.hostname) ? u.href : ''; } catch (_) { return ''; } },
  async doc(path, params) {
    const r = await this.http.get(this.BASE + path, {params, headers: {Referer: this.BASE + '/'}});
    if (r.status === 404) throw Park.error('NOT_FOUND', '影片不存在');
    if (!r.ok) throw Park.error('HTTP', '成人视频请求失败', {status: r.status});
    Park.url.response(this, r, this.BASE + path);
    return Park.html.parse(r.body);
  },
  cards(doc, series = false) {
    const out = [], seen = new Set(), pattern = series ? /^\/s\/([a-z0-9]+)$/ : /^\/v\/([a-z0-9]+)$/;
    for (const a of doc.querySelectorAll('a[href]')) {
      const m = pattern.exec(a.getAttribute('href') || ''), img = a.querySelector('img'), title = Park.html.text(a.querySelector('h3')) || img?.getAttribute('alt') || '';
      const cover = img?.getAttribute('src') || img?.getAttribute('data-src') || '';
      if (!m || !title || !cover || !a.querySelector('h3') || seen.has(m[1]) || /AI短劇/.test(a.textContent)) continue;
      seen.add(m[1]); out.push({id: m[1], title, cover: this.absolute(cover), coverAspect: series ? 3 / 4 : 16 / 10,
        duration: [...a.querySelectorAll('span')].map(n => Park.html.text(n)).find(t => /^(?:\d+小時)?(?:\d+分)?(?:\d+秒)?$/.test(t) && t) || '', url: this.BASE + a.getAttribute('href')});
    }
    return out;
  },
  pageInfo(doc, page) {
    let totalPages = page;
    for (const a of doc.querySelectorAll('main a[href]')) { const u = a.getAttribute('href') || ''; const m = /(?:[?&])page=(\d+)/.exec(u); if (m) totalPages = Math.max(totalPages, Number(m[1])); }
    return {page, totalPages, hasNext: totalPages > page};
  },
  async feed(key, req = {}) {
    const page = this.page(req.page), options = req.options || {};
    let path;
    if (key === 'recommend') { if (page > 1) return {items: [], page, totalPages: 1, hasNext: false}; path = '/home'; }
    else if (key === 'latest') path = '/v?order=createdAt&page=' + page;
    else if (key === 'category') { const tag = String(options.category || 'all'); if (!this.feeds[2].options[0].values.some(v => v.value === tag)) throw Park.error('CONFIG', '视频列表地址无效'); path = tag === 'all' ? '/v?page=' + page : '/t/' + encodeURIComponent(tag) + '?page=' + page; }
    else throw Park.error('CONFIG', '未知视频列表');
    const doc = await this.doc(path), main = doc.querySelector('main');
    if (!main) throw Park.error('PARSE', '成人视频详情解析失败');
    if (key === 'recommend') for (const section of main.querySelectorAll('section')) { if (Park.html.text(section.querySelector('h2')) === 'AI短劇') section.remove(); }
    const items = this.cards(main);
    if (!items.length) throw Park.error('PARSE', '成人视频详情解析失败');
    return {...this.pageInfo(doc, page), items};
  },
  async search(req = {}) {
    const keyword = String(req.keyword || '').trim(), page = this.page(req.page);
    if (!keyword) return {items: [], page, totalPages: 0, hasNext: false};
    const doc = await this.doc('/search', {q: keyword, page});
    const main = doc.querySelector('main');
    if (!main) throw Park.error('PARSE', '成人视频详情解析失败');
    return {...this.pageInfo(doc, page), items: this.cards(main)};
  },
  jsonLd(doc) { for (const node of doc.querySelectorAll('script[type="application/ld+json"]')) { try { const v = JSON.parse(node.textContent || ''); if (v && (v['@type'] === 'VideoObject' || v.name)) return v; } catch (_) {} } return {}; },
  async detail(value) {
    const id = this.id(value), doc = await this.doc('/v/' + id), data = this.jsonLd(doc);
    const title = String(data.name || Park.html.text(doc.querySelector('h1')) || '').trim(), cover = this.absolute((Array.isArray(data.thumbnailUrl) ? data.thumbnailUrl[0] : data.thumbnailUrl) || doc.querySelector('meta[property="og:image"]')?.getAttribute('content'));
    if (!title || !cover) throw Park.error('PARSE', '成人视频详情解析失败');
    const tags = [...new Set((doc.querySelector('meta[name="keywords"]')?.getAttribute('content') || '').split(',').map(t => t.trim()).filter(Boolean))].map(name => ({name, keyword: name}));
    return {id, title, url: this.BASE + '/v/' + id, cover, coverAspect: 16 / 10, description: String(data.description || ''), uploaded: String(data.uploadDate || ''), tags: tags.length ? [{namespace: 'tag', label: '标签', tags}] : []};
  },
  async videos(value) { const id = this.id(value); return [{quality: 0, label: '原画', url: this.BASE + '/api/hls/' + id, headers: {Referer: this.BASE + '/v/' + id}, preferred: true, format: 'hls'}]; },
});
