/* Rule34Video：静态 KVS 数据，拒绝执行播放器脚本。 */
Park.register({
  key: 'rule34video', name: 'Rule34Video', version: '0.0.2', type: 'video', category: 'anime',
  language: 'en', color: '#88AA44', homepage: 'https://rule34video.com',
  description: '同人动画与游戏角色短片，支持评分榜、搜索和多清晰度 MP4',
  domains: ['rule34video.com'], network: {mode: 'native', vpnHint: true},
  media: {mode: 'native', origin: 'https://rule34video.com', domains: ['rule34video.com']},
  imageHeaders: {Referer: 'https://rule34video.com/'},
  defaultFeed: 'rating', feeds: [{key: 'rating', label: '排行'}],
  linkPatterns: ['rule34video\\.com/video/(\\d+/[a-z0-9-]+)/'],
  idPattern: '^\\d{1,12}/[a-z0-9-]{1,240}$', BASE: 'https://rule34video.com',
  idValue(value) {
    if (!/^\d{1,12}\/[a-z0-9-]{1,240}$/.test(String(value))) throw Park.error('NOT_FOUND', '影片编号无效');
    return String(value);
  },
  siteUrl(value) {
    if (typeof value !== 'string' || !value.trim()) return null;
    try { const u = new URL(value, this.BASE); return u.origin === this.BASE && !u.username && !u.password && !u.hash ? u : null; }
    catch (_) { return null; }
  },
  async page(url) {
    if (!this.siteUrl(url)) throw Park.error('CONFIG', '视频列表地址无效');
    const r = this.http.ensureOk(await this.http.get(url));
    if (!this.siteUrl(r.url || url)) throw Park.error('BLOCKED', '站点需要在浏览器中确认后访问');
    return {html: r.body, doc: Park.html.parse(r.body), url: r.url || url};
  },
  cards(doc) {
    const items = [], seen = new Set();
    for (const a of doc.querySelectorAll('a.th[href]')) {
      const u = this.siteUrl(a.getAttribute('href')), m = u && /^\/video\/(\d{1,12}\/[a-z0-9-]{1,240})\/$/.exec(u.pathname);
      const img = a.querySelector('img'), cover = this.siteUrl(img?.getAttribute('data-rd-src') || img?.getAttribute('data-src') || img?.getAttribute('src'));
      const title = Park.html.text(a.querySelector('.thumb_title')) || a.getAttribute('title');
      if (!m || !cover || !title || seen.has(m[1])) continue;
      seen.add(m[1]); items.push({id: m[1], title, cover: cover.href, coverAspect: 16/9, duration: Park.html.text(a.querySelector('.time')), url: u.href});
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
        if (!['q', 'sort_by', 'from', 'from_videos', 'from_albums'].includes(key)) continue;
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
          ![u.searchParams.get('from_videos'), u.searchParams.get('from')].some(x => Number(x) === page) ||
          [...u.searchParams.keys()].some(x => !['q', 'mode', 'function', 'block_id', 'sort_by', 'from', 'from_videos', 'from_albums'].includes(x))) throw Park.error('CONFIG', '分页链接无效');
      url = u.href;
    }
    const result = await this.page(url), items = this.cards(result.doc), cursor = this.nextPage(result.doc, base, page + 1, keyword);
    return {items, page, hasNext: !!cursor, cursor};
  },
  async feed(key, req) {
    if (key !== 'rating') throw Park.error('CONFIG', '未知列表');
    return this.listing(req);
  },
  async search(req) {
    const keyword = String(req.keyword || '').trim();
    return keyword ? this.listing(req, keyword) : {items: [], page: 1, hasNext: false};
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
    cover = this.siteUrl(cover)?.href || '';
    if (!title) throw Park.error('NOT_FOUND', '影片不存在');
    return {id, title, cover, coverAspect: 16/9, url, chapters: null, tags: [], authors: [], related: this.cards(doc).filter(x => x.id !== id)};
  },
  parseVideos(html, referer) {
    const values = new Map();
    for (const m of html.matchAll(/\b(video_(?:alt_)?url\d*(?:_text)?):\s*['"]([^'"]+)['"]/g)) values.set(m[1], Park.html.unescape(m[2]));
    const out = [], seen = new Set();
    for (const [key, value] of values) {
      if (key.endsWith('_text')) continue;
      const u = this.siteUrl(value), quality = parseInt(values.get(key + '_text') || '', 10);
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
