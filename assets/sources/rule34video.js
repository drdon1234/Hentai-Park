/* Rule34Video：静态 KVS 数据，拒绝执行播放器脚本。 */
Park.register({
  i18n: {
    "zh-Hant": {"同人动画与游戏角色短片，支持评分榜、搜索和多清晰度 MP4": "同人動畫與遊戲角色短片，支援評分榜、搜尋和多畫質 MP4"},
    "ja": {"同人动画与游戏角色短片，支持评分榜、搜索和多清晰度 MP4": "同人アニメ・ゲームキャラクター動画。評価順・検索・複数画質の MP4 に対応"},
    "ko": {"同人动画与游戏角色短片，支持评分榜、搜索和多清晰度 MP4": "동인 애니메이션과 게임 캐릭터 영상; 평점순, 검색 및 다양한 MP4 화질 지원"},
    "en": {"同人动画与游戏角色短片，支持评分榜、搜索和多清晰度 MP4": "Fan animations and game character clips with ratings, search and multiple MP4 qualities"},
    "es": {"同人动画与游戏角色短片，支持评分榜、搜索和多清晰度 MP4": "Animaciones de fans y personajes de videojuegos, con clasificación, búsqueda y varias calidades MP4"},
    "ru": {"同人动画与游戏角色短片，支持评分榜、搜索和多清晰度 MP4": "Фанатская анимация и ролики с игровыми персонажами: рейтинг, поиск и MP4 разного качества"},
    "ar": {"同人动画与游戏角色短片，支持评分榜、搜索和多清晰度 MP4": "رسوم المعجبين ومقاطع شخصيات الألعاب مع التقييم والبحث وجودات MP4 متعددة"},
  },
  key: 'rule34video', name: 'Rule34Video', version: '0.0.10', minAppVersion: '0.9.2', type: 'video', category: 'anime',
  language: 'en', color: '#88AA44', homepage: 'https://rule34video.com',
  description: '同人动画与游戏角色短片，支持评分榜、搜索和多清晰度 MP4',
  domains: ['rule34video.com'], network: {mode: 'native', vpnHint: true},
  media: {mode: 'native', scope: 'session', origin: 'https://rule34video.com', domains: ['rule34video.com', 'boomio-cdn.com']},
  imageHeaders: {Referer: 'https://rule34video.com/'},
  defaultFeed: 'rating', feeds: [{key: 'rating', label: '排行'}, {key: 'categories', label: '分类', options: [
    {key: 'group', label: '分类', default: 'categories', dynamic: true, values: []},
    {key: 'range', label: '索引', default: '0', dynamic: true, dependsOn: ['group'], values: []},
    {key: 'category', label: '标签', default: '', dynamic: true, dependsOn: ['group', 'range'], values: []},
  ]}],
  catalogCache: new Map(),
  async catalog(group, offset = 0) {
    if (!['body', 'positions', 'moments', 'camera', 'motion', 'sizes', 'style', 'characters', 'categories', 'other'].includes(group) || !Number.isInteger(offset) || offset < 0 || offset > 100000 || offset % 100) throw Park.error('CONFIG', '筛选参数无效');
    const key = group + ':' + offset, old = this.catalogCache.get(key);
    if (old && Date.now() - old.time < 600000) return old.data;
    const data = await this.http.json(this.BASE + '/tag_wiki.php', {params: {action: 'tags', view: 'group', g: group, offset, limit: 100}});
    if (data?.status !== 'ok' || !Array.isArray(data.items) || !Array.isArray(data.groups) || !Number.isInteger(data.total) || data.total < 0) throw Park.error('PARSE', '分类列表解析失败');
    if (this.catalogCache.size >= 30) this.catalogCache.delete(this.catalogCache.keys().next().value);
    this.catalogCache.set(key, {time: Date.now(), data}); return data;
  },
  async filterOptions(req) {
    if (req.scope !== 'feed' || req.feed !== 'categories') return [];
    const group = String(req.values?.group || 'categories'), offset = Number(req.values?.range || 0);
    const data = await this.catalog(group, req.filter === 'category' ? offset : 0);
    if (req.filter === 'group') return data.groups.map(x => ({value: x.slug, label: x.name}));
    if (req.filter === 'range') return Array.from({length: Math.ceil(data.total / 100)}, (_, i) => ({value: String(i * 100), label: (i * 100 + 1) + '–' + Math.min((i + 1) * 100, data.total)}));
    if (req.filter !== 'category') return [];
    return [{value: '', label: '全部'}, ...data.items.filter(x => /^(?:\/categories\/|\/tags\/)[a-z0-9-]+\/$/.test(x.url) && x.n).map(x => ({value: x.url, label: x.n}))];
  },
  linkPatterns: ['rule34video\\.com/video/(\\d+/[a-z0-9-]+)/'],
  idPattern: '^\\d{1,12}/[a-z0-9-]{1,240}$', BASE: 'https://rule34video.com',
  idValue(value) {
    if (!/^\d{1,12}\/[a-z0-9-]{1,240}$/.test(String(value))) throw Park.error('NOT_FOUND', '影片编号无效');
    return String(value);
  },
  siteUrl(value) { return Park.url.site(this, value); },
  // 图片与视频 CDN 会更换主机，只要求是公网 HTTPS 地址，播放按会话授权。
  publicUrl(value) { return ((value, base) => { try { const u = new URL(String(value).trim(), base); return Park.url.parse(u.href, base, [u.hostname]); } catch (_) { return null; } })(value, this.BASE); },
  async page(url) {
    if (!this.siteUrl(url)) throw Park.error('CONFIG', '视频列表地址无效');
    const r = this.http.ensureOk(await this.http.get(url));
    const finalUrl = Park.url.response(this, r, url);
    return {html: r.body, doc: Park.html.parse(r.body), url: finalUrl.href};
  },
  cards(doc) {
    const items = [], seen = new Set();
    for (const a of doc.querySelectorAll('a.th[href]')) {
      const u = this.siteUrl(a.getAttribute('href')), m = u && /^\/video\/(\d{1,12}\/[a-z0-9-]{1,240})\/$/.exec(u.pathname);
      const img = a.querySelector('img'), cover = this.publicUrl(img?.getAttribute('data-rd-src') || img?.getAttribute('data-src') || img?.getAttribute('src'));
      const title = Park.html.text(a.querySelector('.thumb_title')) || a.getAttribute('title');
      if (!m || !title || seen.has(m[1])) continue;
      seen.add(m[1]); items.push({id: m[1], title, cover: cover?.href || '', coverAspect: 16/9, duration: Park.html.text(a.querySelector('.time')), url: u.href});
    }
    return items;
  },
  nextPage(doc, base, next, keyword) {
    for (const a of doc.querySelectorAll('.pagination a[data-parameters]')) {
      const raw = a.getAttribute('data-parameters'), params = new URLSearchParams();
      for (const part of raw.split(';')) {
        const i = part.indexOf(':'); if (i < 1) continue;
        for (const key of part.slice(0, i).split('+')) params.set(key, part.slice(i + 1));
      }
      if (![params.get('from_videos'), params.get('from')].some(x => Number(x) === next)) continue;
      if (keyword !== undefined && params.get('q') !== keyword) continue;
      const u = new URL(base); u.search = '';
      u.searchParams.set('mode', 'async'); u.searchParams.set('function', 'get_block');
      const block = a.getAttribute('data-block-id');
      if (block !== (keyword === undefined ? 'custom_list_videos_most_recent_videos' : 'custom_list_videos_videos_list_search')) continue;
      u.searchParams.set('block_id', block);
      for (const [key, value] of params) {
        u.searchParams.set(key, value);
      }
      return u.href;
    }
    return null;
  },
  async listing(req, keyword) {
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    const base = keyword === undefined ? this.BASE + '/?sort_by=rating' : this.BASE + '/search/?q=' + encodeURIComponent(keyword);
    let url = base;
    if (page > 1) {
      const u = this.siteUrl(req.cursor);
      if (!u || u.pathname !== new URL(base).pathname || u.searchParams.get('q') !== (keyword ?? null) || u.searchParams.get('mode') !== 'async' || u.searchParams.get('function') !== 'get_block' ||
          u.searchParams.get('block_id') !== (keyword === undefined ? 'custom_list_videos_most_recent_videos' : 'custom_list_videos_videos_list_search') ||
          (keyword === undefined && u.searchParams.get('sort_by') !== 'rating') ||
          ![u.searchParams.get('from_videos'), u.searchParams.get('from')].some(x => Number(x) === page)) throw Park.error('CONFIG', '分页链接无效');
      url = u.href;
    }
    const result = await this.page(url), items = this.cards(result.doc), cursor = this.nextPage(result.doc, result.url, page + 1, keyword);
    return {items, page, hasNext: !!cursor, cursor};
  },
  async feed(key, req) {
    if (key === 'categories') {
      const category = String(req.options?.category || '');
      if (!category) return this.listing(req);
      if (!/^\/(?:categories|tags)\/[a-z0-9-]{1,240}\/$/.test(category)) throw Park.error('CONFIG', '分类无效');
      const page = Math.max(1, Math.floor(Number(req.page) || 1)), {doc} = await this.page(this.BASE + category + (page > 1 ? page + '/' : ''));
      const next = [...doc.querySelectorAll('.pagination a[href], a[rel="next"]')].some(a => this.siteUrl(a.getAttribute('href'))?.pathname === category + (page + 1) + '/');
      return {items: this.cards(doc), page, hasNext: next};
    }
    if (key !== 'rating') throw Park.error('CONFIG', '未知列表');
    return this.listing(req);
  },
  async search(req) {
    const keyword = String(req.keyword || '').trim();
    return keyword ? this.listing(req, keyword) : {items: [], page: 1, hasNext: false};
  },
  async comments(value, req = {}) {
    const id = this.idValue(value), page = Math.max(1, Math.floor(Number(req.page) || 1));
    if (req.parentId || (req.sort && req.sort !== 'default')) throw Park.error('UNSUPPORTED', '评论暂不支持此操作');
    if (page > 1) return {items: [], page, hasNext: false};
    const url = this.BASE + '/video/' + id + '/', {doc} = await this.page(url);
    const area = doc.querySelector('#video_comments_video_comments_items');
    if (!area) throw Park.error('PARSE', '评论数据无效');
    const items = [], seen = new Set();
    for (const row of area.querySelectorAll('[data-comment-id]')) {
      const id = row.getAttribute('data-comment-id'), body = Park.comments.html(row.querySelector('.coment-text')?.innerHTML || '', url);
      if (!id || seen.has(id) || !body.length) continue;
      const author = row.querySelector('.comment-info .inner > a');
      seen.add(id); items.push({id, author: {name: Park.html.text(author), url: Park.comments.url(author?.getAttribute('href'), url),
        avatar: Park.comments.url(row.querySelector('.user-logo img')?.getAttribute('src'), url)}, body, date: Park.html.text(row.querySelector('.date'))});
    }
    if (!items.length && Park.html.text(doc.querySelector('#tab_comments .vp-h small')) !== '0') throw Park.error('PARSE', '评论数据无效');
    return {items, page, hasNext: false};
  },
  async detail(value) {
    const id = this.idValue(value), url = this.BASE + '/video/' + id + '/', {doc} = await this.page(url);
    const title = Park.html.text(doc.querySelector('h1.title_video,h1'));
    let cover = doc.querySelector('meta[property="og:image"]')?.getAttribute('content');
    if (!cover) {
      for (const script of doc.querySelectorAll('script[type="application/ld+json"]')) {
        try {
          const data = JSON.parse(script.textContent);
          if (data['@type'] === 'VideoObject') { cover = Array.isArray(data.thumbnailUrl) ? data.thumbnailUrl[0] : data.thumbnailUrl; break; }
        } catch (_) {}
      }
    }
    cover = this.publicUrl(cover)?.href || '';
    if (!title) throw Park.error('NOT_FOUND', '影片不存在');
    return {id, title, cover, coverAspect: 16/9, url, chapters: null, tags: [], authors: [], related: this.cards(doc).filter(x => x.id !== id)};
  },
  parseVideos(html, referer) {
    const values = new Map();
    for (const m of html.matchAll(/\b(video_(?:alt_)?url\d*(?:_text)?):\s*['"]([^'"]+)['"]/g)) values.set(m[1], Park.html.unescape(m[2]));
    const out = [], seen = new Set();
    for (const [key, value] of values) {
      if (key.endsWith('_text')) continue;
      const u = this.publicUrl(value), quality = parseInt(values.get(key + '_text') || '', 10);
      if (!u || !/\/get_file\/.+\.mp4\/?$/i.test(u.pathname) || !Number.isInteger(quality) || quality < 1 || quality > 4320 || seen.has(quality)) continue;
      seen.add(quality); out.push({quality, label: quality + 'P', format: 'mp4', url: u.href, headers: {Referer: referer}});
    }
    out.sort((a, b) => b.quality - a.quality);
    const best = out.find(x => x.quality <= 720) || out[out.length - 1];
    if (best) best.preferred = true;
    return out;
  },
  async videos(value) {
    const referer = this.BASE + '/video/' + this.idValue(value) + '/', {html} = await this.page(referer), list = this.parseVideos(html, referer);
    if (!list.length) throw Park.error('UNSUPPORTED', '此影片没有可用的 MP4 清晰度');
    return list;
  },
});

Park.enableUpdateSubscriptions(Park.__pending, {dimensions: [
  {key: 'search', label: '搜索关键词', hint: '输入作品、作者或话题关键词'},
]});
