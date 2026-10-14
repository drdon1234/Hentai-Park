/* 黄豆短剧：仅解析当前站点公开页面；播放时重新读取指定集的签名地址。 */
Park.register({
  key: 'huangdou', name: '黄豆短剧', version: '0.0.5',
  type: 'video', category: 'aiDrama', color: '#FFC857',
  description: 'AI短剧与漫剧，支持分类、排行、搜索和分集播放',
  homepage: 'https://aihuangdou.com', domains: ['aihuangdou.com'], language: 'zh',
  linkPatterns: ['aihuangdou\\.com/(?:drama|video)/(\\d+)(?:/|[?#]|$)'],
  idPattern: '^([1-9]\\d*)$',
  imageHeaders: { Referer: 'https://aihuangdou.com/' },
  imageDecrypt: {
    type: 'aes-cbc', key: 'f5d965df75336270', iv: '97b60394abc2fbe1',
    domains: ['pic.drleao.cn'],
  },
  network: { mode: 'native', vpnHint: true },
  media: { mode: 'native', scope: 'session', origin: 'https://aihuangdou.com', domains: [
    'yd-hls.hzjvlo.cn', 'tp1.drleao.cn', 'tp2.drleao.cn', 'tp3.drleao.cn',
    'tp4.drleao.cn', 'tp5.drleao.cn', 'tp6.drleao.cn', 'tp7.drleao.cn', 'tp8.drleao.cn',
  ] },
  defaultFeed: 'recommend',
  feeds: [
    { key: 'recommend', label: '推荐' },
    { key: 'ranking', label: '排行榜', options: [
      { key: 'ranking', label: '榜单', type: 'select', default: 'hot', values: [
        { value: 'hot', label: '热门榜' }, { value: 'week', label: '推荐榜' },
        { value: 'rising', label: '潜力榜' },
      ] },
    ] },
    { key: 'category', label: '分类', options: [
      { key: 'category', label: '类型', type: 'select', default: 'duanju', values: [
        { value: 'duanju', label: 'AI短剧' }, { value: 'manju', label: 'AI 漫剧' },
        { value: 'mogai', label: 'AI 魔改' },
      ] },
      { key: 'sort', label: '排序', type: 'select', default: 'hot', values: [
        { value: 'hot', label: '热门' }, { value: 'new', label: '最新' },
        { value: 'score', label: '高分推荐' }, { value: 'collect', label: '收藏' },
      ] },
    ] },
  ],
  searchHint: '搜索作品名、标签或作者',
  BASE: 'https://aihuangdou.com', COVER_ASPECT: 360 / 640,

  absolute(value) {
    if (typeof value !== 'string' || !value) return '';
    try { const u = new URL(value, this.BASE); return /^https?:$/.test(u.protocol) ? u.href : ''; }
    catch (_) { return ''; }
  },
  pageNumber(value) { const n = Number(value); return Number.isSafeInteger(n) && n > 0 ? n : 1; },
  workId(value) {
    const id = String(value || '');
    if (!/^[1-9]\d*$/.test(id)) throw Park.error('NOT_FOUND', 'AI短剧作品或分集不存在');
    return id;
  },
  text(node) { return node ? Park.html.text(node) : ''; },
  image(img) {
    return img ? this.absolute(img.getAttribute('data-src') || img.getAttribute('src')) : '';
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
  cards(root, ranking = false) {
    const items = [], seen = new Set();
    if (!root) return items;
    for (const card of root.querySelectorAll(ranking ? '.rank-lead, .rank-runner, .rank-row' : '.drama-card')) {
      const a = card.querySelector('a[href*="/drama/"]');
      const u = a && this.absolute(a.getAttribute('href'));
      const match = u && new URL(u).origin === this.BASE && /\/drama\/([1-9]\d*)\/$/.exec(new URL(u).pathname);
      const img = a && a.querySelector('img');
      const title = this.text(card.querySelector('h3, h2'));
      if (!match || !img || !title || seen.has(match[1])) continue;
      seen.add(match[1]);
      const width = Number(img.getAttribute('width')), height = Number(img.getAttribute('height'));
      const score = parseFloat(this.text(card.querySelector('.card-score')));
      items.push({
        id: match[1], title, cover: this.image(img),
        coverAspect: width > 0 && height > 0 ? width / height : this.COVER_ASPECT,
        subtitle: this.text(card.querySelector('.eps-flag')), rating: score > 0 ? score : null,
      });
    }
    return items;
  },
  list(doc, page, fragment = false) {
    const root = fragment ? doc : doc.querySelector('main');
    const body = root && root.querySelector('.drama-grid, .result-list.is-video');
    if (!body) throw Park.error('PARSE', 'AI短剧列表解析失败');
    const pager = root.querySelector('[data-page-jump]');
    if (pager && Number(pager.getAttribute('data-page')) !== page) throw Park.error('PARSE', 'AI短剧列表解析失败');
    const totalPages = pager ? Number(pager.getAttribute('data-pages')) : 1;
    if (!Number.isSafeInteger(totalPages) || totalPages < 1) throw Park.error('PARSE', 'AI短剧列表解析失败');
    const items = this.cards(body);
    return { items, page, totalPages, hasNext: items.length > 0 && page < totalPages };
  },
  async feed(key, req = {}) {
    const page = this.pageNumber(req.page), options = req.options || {};
    if (key === 'category') {
      const category = options.category || 'duanju', sort = options.sort || 'hot';
      if (!['duanju', 'manju', 'mogai'].includes(category) || !['hot', 'new', 'score', 'collect'].includes(sort)) {
        throw Park.error('CONFIG', 'AI短剧列表选项无效');
      }
      const channel = { duanju: 'duanju', manju: 'dongman-sm', mogai: 'videos' }[category];
      return this.list(await this.document('/api/list/fragment', { scope: 'ninechannel', key: channel, sort, page }), page, true);
    }
    if (key === 'ranking') {
      const ranking = options.ranking || 'hot';
      if (!['hot', 'week', 'rising'].includes(ranking)) throw Park.error('CONFIG', 'AI短剧列表选项无效');
      if (page > 1) return { items: [], page, totalPages: 1, hasNext: false };
      const doc = await this.document('/rankings/' + (ranking === 'hot' ? '' : ranking + '/'));
      const main = doc.querySelector('main');
      if (!main || !main.querySelector('.rank-podium')) throw Park.error('PARSE', 'AI短剧列表解析失败');
      return { items: this.cards(main, true), page, totalPages: 1, hasNext: false };
    }
    if (key !== 'recommend') throw Park.error('CONFIG', 'AI短剧列表选项无效');
    if (page > 1) return { items: [], page, totalPages: 1, hasNext: false };
    const doc = await this.document('/');
    const hero = doc.querySelector('main .hero');
    if (!hero) throw Park.error('PARSE', 'AI短剧列表解析失败');
    const items = [], seen = new Set();
    for (const card of hero.querySelectorAll('.hero-card[data-url]')) {
      const match = /^\/drama\/([1-9]\d*)\/$/.exec(card.getAttribute('data-url') || '');
      const title = card.getAttribute('data-title'), cover = this.image(card.querySelector('.poster-img'));
      if (!match || !title || !cover || seen.has(match[1])) continue;
      seen.add(match[1]);
      items.push({ id: match[1], title, cover, coverAspect: this.COVER_ASPECT, rating: Number(card.getAttribute('data-score')) || null });
    }
    if (!items.length) throw Park.error('PARSE', 'AI短剧列表解析失败');
    return { items, page, totalPages: 1, hasNext: false };
  },
  async search(req = {}) {
    const keyword = String(req.keyword || '').trim(), page = this.pageNumber(req.page);
    if (!keyword) return { items: [], page, totalPages: 0, hasNext: false };
    const path = '/search/video/' + encodeURIComponent(keyword) + '/' + (page > 1 ? page + '/' : '');
    return this.list(await this.document(path), page);
  },
  episodes(doc, id) {
    const grid = doc.querySelector('#nineEpisodeGrid');
    if (!grid && this.text(doc.querySelector('.detail-cover-status')) === '单片上线') return null;
    if (!grid) throw Park.error('PARSE', 'AI短剧详情解析失败');
    const chapters = [], seen = new Set();
    for (const a of grid.querySelectorAll('a[href]')) {
      const u = new URL(a.getAttribute('href'), this.BASE);
      const m = /^\/video\/([1-9]\d*)\/(?:([1-9]\d*)\/)?$/.exec(u.pathname);
      if (u.origin !== this.BASE || !m || m[1] !== id) throw Park.error('PARSE', 'AI短剧详情解析失败');
      const ep = m[2] || '1';
      if (!seen.has(ep)) { seen.add(ep); chapters.push({ id: ep, title: '第' + ep + '集' }); }
    }
    chapters.sort((a, b) => Number(a.id) - Number(b.id));
    const total = Number(grid.getAttribute('data-total'));
    if (!chapters.length || chapters.length !== total || chapters.some((c, i) => Number(c.id) !== i + 1)) {
      throw Park.error('PARSE', 'AI短剧详情解析失败');
    }
    return chapters;
  },
  async detail(value) {
    const id = this.workId(value), doc = await this.document('/drama/' + id + '/');
    const top = doc.querySelector('.detail-top');
    if (!top || top.getAttribute('data-drama-id') !== id) throw Park.error('PARSE', 'AI短剧详情解析失败');
    const title = this.text(top.querySelector('h1'));
    if (!title) throw Park.error('PARSE', 'AI短剧详情解析失败');
    const names = [...top.querySelectorAll('a[href*="/tag/"]')].map(a => this.text(a)).filter(Boolean);
    return {
      id, title, url: this.BASE + '/drama/' + id + '/',
      cover: this.image(top.querySelector('.detail-cover img')), coverAspect: this.COVER_ASPECT,
      description: this.text(top.querySelector('#nineDetailIntro')), authors: [],
      rating: parseFloat(this.text(top.querySelector('.detail-stats em'))) || null,
      tags: [{ namespace: 'tag', label: '标签', tags: [...new Set(names)].map(name => ({ name, keyword: name })) }],
      chapters: this.episodes(doc, id),
      related: this.cards(doc.querySelector('.nine-detail-recos')).filter(item => item.id !== id),
    };
  },
  async videos(value, episodeId = '_') {
    const id = this.workId(value), ep = episodeId === '_' ? '1' : String(episodeId);
    if (!/^[1-9]\d*$/.test(ep)) throw Park.error('NOT_FOUND', 'AI短剧作品或分集不存在');
    const path = '/video/' + id + '/' + (ep === '1' ? '' : ep + '/');
    const doc = await this.document(path), node = doc.querySelector('#ninePlayData');
    let data;
    try { data = JSON.parse(node ? node.textContent : ''); } catch (_) { throw Park.error('PARSE', 'AI短剧播放数据解析失败'); }
    if (!data || String(data.id) !== id || !data.current || String(data.current.n) !== ep || String(data.startEp) !== ep) {
      throw Park.error('NOT_FOUND', 'AI短剧作品或分集不存在');
    }
    if (data.videoApi || data.videoKey || data.videoIv) throw Park.error('UNSUPPORTED', 'AI短剧该分集使用暂不支持的播放方式');
    if (!data.current.src) throw Park.error('NOT_FOUND', 'AI短剧该分集暂无可用播放地址');
    const url = this.absolute(data.current.src), u = url && new URL(url);
    if (!u || u.protocol !== 'https:' || u.port || u.username || u.password || u.hash || (!/\.m3u8(?:\?|$)/i.test(url) && !this.media.domains.includes(u.hostname))) {
      throw Park.error('PARSE', 'AI短剧播放地址无效');
    }
    return [{ quality: 0, label: '原画', url, headers: { Referer: this.BASE + path }, preferred: true,
      ...(/\.m3u8(?:[?#]|$)/i.test(url) ? { format: 'hls' } : {}),
    }];
  },
});

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"},{"key":"work","label":"作品连载","hint":"作品编号或详情链接"}]});
