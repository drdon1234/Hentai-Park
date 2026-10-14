/* 91 短剧：稳定编号为 分类/作品编号，详情页提供当前规范链接与完整选集。 */
Park.register({
  i18n: {
    "zh-Hant": {"91短剧": "91短劇", "AI短剧、漫剧与视频，支持推荐、分类、搜索和分集播放": "AI短劇、漫劇與影片，支援推薦、分類、搜尋和分集播放", "成人漫剧": "成人漫劇", "成人短剧": "成人短劇", "真人剧": "真人劇"},
    "ja": {"91短剧": "91ショートドラマ", "AI短剧、漫剧与视频，支持推荐、分类、搜索和分集播放": "AIショートドラマ、動画コミック、動画。おすすめ、カテゴリ、検索、話数別再生に対応", "成人漫剧": "成人向け動画コミック", "成人短剧": "成人向け短編ドラマ", "真人剧": "実写ドラマ"},
    "ko": {"91短剧": "91 숏드라마", "AI短剧、漫剧与视频，支持推荐、分类、搜索和分集播放": "AI 숏드라마, 애니메이션 만화와 동영상. 추천·분류·검색·회차별 재생 지원", "成人漫剧": "성인 애니메이션 만화", "成人短剧": "성인 숏드라마", "真人剧": "실사 드라마"},
    "en": {"91短剧": "91 Shorts", "AI短剧、漫剧与视频，支持推荐、分类、搜索和分集播放": "AI short dramas, animated comics and videos with recommendations, categories, search and episode playback", "成人漫剧": "Adult animated comics", "成人短剧": "Adult short dramas", "真人剧": "Live-action dramas"},
    "es": {"91短剧": "Series cortas 91", "AI短剧、漫剧与视频，支持推荐、分类、搜索和分集播放": "Dramas cortos de IA, cómics animados y vídeos con recomendaciones, categorías, búsqueda y reproducción por episodio", "成人漫剧": "Cómics animados para adultos", "成人短剧": "Dramas cortos para adultos", "真人剧": "Dramas de acción real"},
    "ru": {"91短剧": "Короткие сериалы 91", "AI短剧、漫剧与视频，支持推荐、分类、搜索和分集播放": "ИИ-мини-драмы, анимированные комиксы и видео с рекомендациями, категориями, поиском и просмотром по сериям", "成人漫剧": "Анимированные комиксы для взрослых", "成人短剧": "Короткие сериалы для взрослых", "真人剧": "Игровые сериалы"},
    "ar": {"91短剧": "مسلسلات 91 القصيرة", "AI短剧、漫剧与视频，支持推荐、分类、搜索和分集播放": "دراما قصيرة بالذكاء الاصطناعي وقصص مصورة متحركة وفيديوهات، مع توصيات وتصنيفات وبحث وتشغيل الحلقات", "成人漫剧": "قصص مصورة متحركة للبالغين", "成人短剧": "مسلسلات قصيرة للبالغين", "真人剧": "مسلسلات تمثيلية"},
  },
  key: 'drama91', name: '91短剧', version: '0.0.8',
  type: 'video', category: 'aiDrama', color: '#E6C87A',
  description: 'AI短剧、漫剧与视频，支持推荐、分类、搜索和分集播放',
  homepage: 'https://91crdjai.com', domains: ['91crdjai.com'], language: 'zh',
  linkPatterns: ['91crdjai\\.com/((?:duanju|manju|zhenrenju|shipin)/[1-9]\\d*)(?:-[^/?#]+)?(?:/|[?#]|$)'],
  idPattern: '^((?:duanju|manju|zhenrenju|shipin)/[1-9]\\d*)$',
  imageHeaders: { Referer: 'https://91crdjai.com/' },
  imageDecrypt: { type: 'aes-cbc', key: 'f5d965df75336270', iv: '97b60394abc2fbe1', domains: ['pic.drleao.cn'] },
  network: { mode: 'native', vpnHint: true },
  media: { mode: 'native', scope: 'session', origin: 'https://91crdjai.com' },
  defaultFeed: 'recommend',
  feeds: [
    { key: 'recommend', label: '推荐' }, { key: 'ranking', label: '排行榜' },
    { key: 'category', label: '分类', options: [
      { key: 'category', label: '类型', type: 'select', default: 'duanju', values: [
        { value: 'duanju', label: '成人短剧' }, { value: 'manju', label: '成人漫剧' },
        { value: 'zhenrenju', label: '真人剧' }, { value: 'shipin', label: '成人视频' },
      ] },
      { key: 'sort', label: '排序', type: 'select', default: 'hot', values: [
        { value: 'hot', label: '热门' }, { value: 'new', label: '最新' },
      ] },
    ] },
  ],
  searchHint: '搜索作品名、标签或作者',
  BASE: 'https://91crdjai.com', COVER_ASPECT: 360 / 640,
  absolute(value) {
    if (typeof value !== 'string' || !value) return '';
    try { const u = new URL(value, this.BASE); return /^https?:$/.test(u.protocol) ? u.href : ''; }
    catch (_) { return ''; }
  },
  text(node) { return node ? Park.html.text(node) : ''; },
  image(img) { return img ? this.absolute(img.getAttribute('data-src') || img.getAttribute('src')) : ''; },
  pageNumber(value) { const n = Number(value); return Number.isSafeInteger(n) && n > 0 ? n : 1; },
  workId(value) {
    const id = String(value || '');
    if (!/^(?:duanju|manju|zhenrenju|shipin)\/[1-9]\d*$/.test(id)) throw Park.error('NOT_FOUND', 'AI短剧作品或分集不存在');
    return id;
  },
  linkId(value) {
    const url = this.absolute(value);
    if (!url) return '';
    const u = new URL(url);
    const m = /^\/((?:duanju|manju|zhenrenju|shipin)\/[1-9]\d*)(?:-[^/]+)?\/(?:[1-9]\d*\/)?$/.exec(u.pathname);
    return u.origin === this.BASE && m ? m[1] : '';
  },
  async document(path, params) {
    const res = await this.http.get(this.BASE + path, {
      params, headers: { Referer: this.BASE + '/', 'Cache-Control': 'no-cache' },
    });
    if (res.status === 401) throw Park.error('LOGIN_REQUIRED', 'AI短剧需要登录后访问');
    if (res.status === 403) throw Park.error('BLOCKED', '访问受限');
    if (res.status === 404) throw Park.error('NOT_FOUND', 'AI短剧作品或分集不存在');
    if (!res.ok) throw Park.error('HTTP', 'AI短剧请求失败', { status: res.status });
    return Park.html.parse(res.body);
  },
  cards(root, recommend = false) {
    const items = [], seen = new Set();
    if (!root) return items;
    for (const card of root.querySelectorAll(recommend ? '.sh-slide' : 'a.card')) {
      const a = recommend ? card.querySelector('.sh-more, .sh-btn') : card;
      const id = a && this.linkId(a.getAttribute('href'));
      const title = this.text(card.querySelector(recommend ? '.sh-title' : 'h3'));
      const img = card.querySelector(recommend ? '.sh-poster' : '.p-img');
      if (!id || !title || !img || seen.has(id)) continue;
      seen.add(id);
      const score = this.text(card.querySelector(recommend ? '.sh-meta strong' : '.score')).replace('★', '');
      items.push({ id, title, cover: this.image(img), coverAspect: this.COVER_ASPECT,
        subtitle: this.text(card.querySelector('.eps-flag')), rating: parseFloat(score) || null,
      });
    }
    return items;
  },
  list(doc, page, fragment = false, search = false) {
    const root = fragment ? doc : doc.querySelector('main');
    const body = root && root.querySelector(search ? '.grid[data-search-result-count]' : '.grid');
    if (!body) throw Park.error('PARSE', 'AI短剧列表解析失败');
    const pager = root.querySelector('.pager[data-pages]');
    const totalPages = pager ? Number(pager.getAttribute('data-pages')) : 1;
    if (!Number.isSafeInteger(totalPages) || totalPages < 1) throw Park.error('PARSE', 'AI短剧列表解析失败');
    const current = pager && (pager.getAttribute('data-page') || this.text(pager.querySelector('.pg.cur')));
    if (current && Number(current) !== page) throw Park.error('PARSE', 'AI短剧列表解析失败');
    const items = this.cards(body);
    // 搜索/榜单混有漫画、小说和其他视频；整页被排除时用游标保持下一页可达。
    return { items, page, totalPages, hasNext: page < totalPages,
      ...(page < totalPages ? { cursor: String(page + 1) } : {}),
    };
  },
  async feed(key, req = {}) {
    const page = this.pageNumber(req.cursor || req.page), options = req.options || {};
    if (key === 'category') {
      const category = options.category || 'duanju', sort = options.sort || 'hot';
      if (!['duanju', 'manju', 'zhenrenju', 'shipin'].includes(category) || !['hot', 'new'].includes(sort)) throw Park.error('CONFIG', 'AI短剧列表选项无效');
      const channel = { duanju: 'duanju', manju: 'dongman-sm', zhenrenju: 'zhibo-huifang', shipin: 'videos' }[category];
      return this.list(await this.document('/api/list/fragment', { scope: 'category', key: channel, sort, page }), page, true);
    }
    if (key === 'ranking') return this.list(await this.document('/paihang/' + (page > 1 ? 'page/' + page + '/' : '')), page);
    if (key !== 'recommend') throw Park.error('CONFIG', 'AI短剧列表选项无效');
    if (page > 1) return { items: [], page, totalPages: 1, hasNext: false };
    const doc = await this.document('/'), hero = doc.querySelector('main .shelf-hero');
    const items = this.cards(hero, true);
    if (!hero || !items.length) throw Park.error('PARSE', 'AI短剧列表解析失败');
    return { items, page, totalPages: 1, hasNext: false };
  },
  async search(req = {}) {
    const keyword = String(req.keyword || '').trim(), page = this.pageNumber(req.cursor || req.page);
    if (!keyword) return { items: [], page, totalPages: 0, hasNext: false };
    return this.list(await this.document('/search/' + encodeURIComponent(keyword) + '/' + (page > 1 ? page + '/' : '')), page, false, true);
  },
  async detailDocument(id) {
    const doc = await this.document('/' + id + '/'), node = doc.querySelector('#videoInitialData');
    let data;
    try { data = JSON.parse(node ? node.textContent : ''); } catch (_) { throw Park.error('PARSE', 'AI短剧详情解析失败'); }
    if (!data || String(data.id) !== id.split('/')[1] || this.linkId(data.playBase) !== id) throw Park.error('PARSE', 'AI短剧详情解析失败');
    const base = this.absolute(data.playBase), path = new URL(base).pathname;
    if (!/^\/(?:duanju|manju|zhenrenju|shipin)\/[1-9]\d*(?:-[^/]+)?\/$/.test(path)) throw Park.error('PARSE', 'AI短剧详情解析失败');
    return { doc, data, path };
  },
  episodes(doc, id, path) {
    const chapters = [], seen = new Set();
    for (const a of doc.querySelectorAll('.ep-grid a[href]')) {
      const u = new URL(a.getAttribute('href'), this.BASE);
      const ep = u.pathname.startsWith(path) && /^([1-9]\d*)\/$/.exec(u.pathname.slice(path.length));
      if (this.linkId(u.href) !== id || !ep) throw Park.error('PARSE', 'AI短剧详情解析失败');
      if (!seen.has(ep[1])) { seen.add(ep[1]); chapters.push({ id: ep[1], title: '第' + ep[1] + '集' }); }
    }
    chapters.sort((a, b) => Number(a.id) - Number(b.id));
    const count = /共\s*(\d+)\s*集/.exec(this.text(doc.querySelector('.ep-panel .sec-head')));
    if (!count || chapters.length !== Number(count[1]) || !chapters.length || chapters.some((c, i) => Number(c.id) !== i + 1)) {
      throw Park.error('PARSE', 'AI短剧详情解析失败');
    }
    return chapters;
  },
  async detail(value) {
    const id = this.workId(value), { doc, data, path } = await this.detailDocument(id);
    const main = doc.querySelector('main'), title = this.text(main && main.querySelector('.detail-title'));
    if (!title) throw Park.error('PARSE', 'AI短剧详情解析失败');
    const names = [...main.querySelectorAll('.d-tags a')].map(a => this.text(a)).filter(Boolean);
    const meta = new Map([...main.querySelectorAll('.work-meta > div')].map(row => [this.text(row.querySelector('dt')), this.text(row.querySelector('dd'))]));
    return {
      id, title, url: this.BASE + path, cover: this.image(main.querySelector('.d-poster img')), coverAspect: this.COVER_ASPECT,
      description: this.text(main.querySelector('#viBody')), authors: [],
      rating: parseFloat(this.text(main.querySelector('.rv'))) || null,
      views: Park.utils.parseCount(meta.get('热度') || ''), likes: Number(data.likesNum) || null,
      uploaded: meta.get('发布') || '',
      tags: [{ namespace: 'tag', label: '标签', tags: [...new Set(names)].map(name => ({ name, keyword: name })) }],
      chapters: this.episodes(doc, id, path), related: this.cards(main.querySelector('.section')).filter(item => item.id !== id),
    };
  },
  async videos(value, episodeId = '_') {
    const id = this.workId(value), ep = episodeId === '_' ? '1' : String(episodeId);
    if (!/^[1-9]\d*$/.test(ep)) throw Park.error('NOT_FOUND', 'AI短剧作品或分集不存在');
    // 编号入口由站点重定向到现行 slug，每次播放读取当前规范路径。
    const { path } = await this.detailDocument(id), playPath = path + ep + '/';
    const doc = await this.document(playPath), node = doc.querySelector('#playInitialData');
    let data;
    try { data = JSON.parse(node ? node.textContent : ''); } catch (_) { throw Park.error('PARSE', 'AI短剧播放数据解析失败'); }
    if (!data || String(data.id) !== id.split('/')[1] || this.linkId(data.playBase) !== id || !data.current || String(data.current.n) !== ep || String(data.startEp) !== ep) {
      throw Park.error('NOT_FOUND', 'AI短剧作品或分集不存在');
    }
    if (data.videoApi || data.videoKey || data.videoIv) throw Park.error('UNSUPPORTED', 'AI短剧该分集使用暂不支持的播放方式');
    if (!data.current.src) throw Park.error('NOT_FOUND', 'AI短剧该分集暂无可用播放地址');
    const url = this.absolute(data.current.src), u = url && new URL(url);
    if (!u || u.protocol !== 'https:' || u.port || u.username || u.password || u.hash || !/\.m3u8(?:\?|$)/i.test(url)) throw Park.error('PARSE', 'AI短剧播放地址无效');
    return [{ quality: 0, label: '原画', url, headers: { Referer: this.BASE + playPath }, preferred: true,
      format: 'hls',
    }];
  },
});

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"},{"key":"work","label":"作品连载","hint":"作品编号或详情链接"}]});
