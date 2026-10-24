/* rou.video AI 短剧源：剧集列表拆分到 AI 短剧域，分集映射到独立视频 ID。 */
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
  key: 'rouvideo-drama', name: '肉视频短剧', version: '0.0.3', minAppVersion: '0.9.2', type: 'video', category: 'aiDrama', color: '#B58CFF',
  description: 'AI短剧，支持推荐、搜索和分集播放', homepage: 'https://rou.video/series', domains: ['rou.video'], language: 'zh',
  linkPatterns: ['rou\\.video/s/([a-z0-9]+)(?:[/?#]|$)'], idPattern: '^[a-z0-9]{10,40}$',
  imageNetwork: {mode: 'browser', origin: 'https://rou.video', domains: ['v.rn252.xyz']}, imageHeaders: {Referer: 'https://rou.video/'},
  media: {mode: 'native', scope: 'session', origin: 'https://rou.video'}, network: {mode: 'native', vpnHint: true},
  defaultFeed: 'recommend', searchHint: '搜索作品名或标签', feeds: [
    {key: 'recommend', label: '推荐'}, {key: 'latest', label: '最新'},
    {key: 'category', label: '分类', options: [{key: 'category', label: '标签', type: 'select', default: 'AI短劇', values: [{value: 'AI短劇', label: 'AI短剧'}, {value: '現代', label: '现代'}, {value: '都市', label: '都市'}, {value: '熟女', label: '熟女'}]}]},
  ],
  BASE: 'https://rou.video',
  id(value) { const id = String(value || ''); if (!/^[a-z0-9]{10,40}$/.test(id)) throw Park.error('NOT_FOUND', 'AI短剧作品或分集不存在'); return id; },
  page(value) { const page = value == null ? 1 : Number(value); if (!Number.isSafeInteger(page) || page < 1 || page > 100000) throw Park.error('CONFIG', 'AI短剧列表选项无效'); return page; },
  // 图片 CDN 会更换主机，只要求是公网 HTTPS 地址。
  absolute(value) { if (typeof value !== 'string' || !value) return ''; try { const u = new URL(value.trim(), this.BASE); return Park.url.parse(u.href, this.BASE, [u.hostname])?.href || ''; } catch (_) { return ''; } },
  async doc(path, params) {
    const r = await this.http.get(this.BASE + path, {params, headers: {Referer: this.BASE + '/'}});
    if (r.status === 404) throw Park.error('NOT_FOUND', 'AI短剧作品或分集不存在');
    if (!r.ok) throw Park.error('HTTP', 'AI短剧请求失败', {status: r.status});
    Park.url.response(this, r, this.BASE + path);
    return Park.html.parse(r.body);
  },
  cards(doc) {
    const out = [], seen = new Set();
    for (const a of doc.querySelectorAll('a[href]')) {
      const m = /^\/s\/([a-z0-9]+)$/.exec(a.getAttribute('href') || ''), img = a.querySelector('img'), title = Park.html.text(a.querySelector('h3')), cover = this.absolute(img?.getAttribute('src') || img?.getAttribute('data-src'));
      if (!m || !title || !cover || !/AI短劇/.test(a.textContent) || seen.has(m[1])) continue;
      seen.add(m[1]); out.push({id: m[1], title, cover, coverAspect: 3 / 4, url: this.BASE + a.getAttribute('href')});
    }
    return out;
  },
  pageInfo(doc, page) {
    let totalPages = page;
    for (const a of doc.querySelectorAll('main a[href]')) { const m = /(?:[?&])page=(\d+)/.exec(a.getAttribute('href') || ''); if (m) totalPages = Math.max(totalPages, Number(m[1])); }
    return {page, totalPages, hasNext: totalPages > page};
  },
  async feed(key, req = {}) {
    const page = this.page(req.page), options = req.options || {};
    if (key === 'recommend' && page > 1) return {items: [], page, totalPages: 1, hasNext: false};
    if (!['recommend', 'latest', 'category'].includes(key)) throw Park.error('CONFIG', 'AI短剧列表选项无效');
    const params = {tag: 'AI短劇', page};
    if (key === 'category') { const tag = String(options.category || 'AI短劇'); if (!this.feeds[2].options[0].values.some(v => v.value === tag)) throw Park.error('CONFIG', 'AI短剧列表选项无效'); params.tag = tag; }
    const doc = await this.doc(key === 'recommend' ? '/home' : '/series', key === 'recommend' ? undefined : params), main = doc.querySelector('main');
    if (!main) throw Park.error('PARSE', 'AI短剧列表解析失败');
    const section = key === 'recommend' ? [...main.querySelectorAll('section')].find(s => Park.html.text(s.querySelector('h2')) === 'AI短劇') : main;
    if (!section) throw Park.error('PARSE', 'AI短剧列表解析失败');
    const items = this.cards(section);
    if (!items.length && page === 1) throw Park.error('PARSE', 'AI短剧列表解析失败');
    return {...(key === 'recommend' ? {page, totalPages: 1, hasNext: false} : this.pageInfo(doc, page)), items};
  },
  async search(req = {}) {
    const keyword = String(req.keyword || '').trim(), page = this.page(req.page);
    if (!keyword) return {items: [], page, totalPages: 0, hasNext: false};
    const doc = await this.doc('/search', {q: keyword, tab: 'series', page}), main = doc.querySelector('main');
    if (!main) throw Park.error('PARSE', 'AI短剧列表解析失败');
    return {...this.pageInfo(doc, page), items: this.cards(main)};
  },
  async detail(value) {
    const id = this.id(value), doc = await this.doc('/s/' + id), title = Park.html.text(doc.querySelector('h1')), cover = this.absolute(doc.querySelector('meta[property="og:image"]')?.getAttribute('content'));
    if (!title || !cover) throw Park.error('PARSE', 'AI短剧详情解析失败');
    const grid = [...doc.querySelectorAll('main section')].find(s => Park.html.text(s.querySelector('h2')) === '選集');
    if (!grid) throw Park.error('PARSE', 'AI短剧详情解析失败');
    const chapters = [], seen = new Set();
    for (const a of grid.querySelectorAll('a[href^="/v/"]')) {
      const m = /^\/v\/([a-z0-9]{10,40})$/.exec(a.getAttribute('href') || ''), match = /^第\s*(\d+)\s*集/.exec(Park.html.text(a));
      if (!m || !match || seen.has(m[1])) throw Park.error('PARSE', 'AI短剧详情解析失败');
      seen.add(m[1]); chapters.push({id: m[1], title: match[0], order: Number(match[1])});
    }
    chapters.sort((a, b) => a.order - b.order);
    if (!chapters.length || chapters.some((c, i) => c.order !== i + 1)) throw Park.error('PARSE', 'AI短剧详情解析失败');
    return {id, title, url: this.BASE + '/s/' + id, cover, coverAspect: 3 / 4, description: doc.querySelector('meta[name="description"]')?.getAttribute('content') || '', chapters: chapters.map(({id, title}) => ({id, title}))};
  },
  async videos(value, episodeId = '_') {
    const detail = await this.detail(value), chapter = episodeId === '_' ? detail.chapters[0] : detail.chapters.find(c => c.id === String(episodeId));
    if (!chapter) throw Park.error('NOT_FOUND', 'AI短剧作品或分集不存在');
    const id = chapter.id;
    return [{quality: 0, label: '原画', url: this.BASE + '/api/hls/' + id, headers: {Referer: this.BASE + '/v/' + id}, preferred: true, format: 'hls'}];
  },
});
