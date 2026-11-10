Park.register({
  i18n: {
    'zh-Hant': {'真人 ASMR 视频，支持浏览和搜索': '真人 ASMR 影片，支援瀏覽和搜尋'},
    ja: {'真人 ASMR 视频，支持浏览和搜索': '実写 ASMR 動画の閲覧と検索'},
    ko: {'真人 ASMR 视频，支持浏览和搜索': '실사 ASMR 동영상 탐색 및 검색'},
    en: {'真人 ASMR 视频，支持浏览和搜索': 'Browse and search live-action ASMR videos'},
    es: {'真人 ASMR 视频，支持浏览和搜索': 'Explora y busca vídeos ASMR de imagen real'},
    ru: {'真人 ASMR 视频，支持浏览和搜索': 'Просмотр и поиск ASMR-видео с актёрами'},
    ar: {'真人 ASMR 视频，支持浏览和搜索': 'تصفح فيديوهات ASMR الحية والبحث فيها'},
  },
  key: 'eroasmr', name: 'EroASMR', version: '0.0.2', minAppVersion: '0.13.0',
  type: 'video', category: 'asmr', color: '#6B5676',
  description: '真人 ASMR 视频，支持浏览和搜索',
  homepage: 'https://eroasmr.com', domains: ['eroasmr.com'],
  network: {vpnHint: true},
  media: {mode: 'native', origin: 'https://eroasmr.com', domains: ['eroasmr.com']},
  imageHeaders: {Referer: 'https://eroasmr.com/'},
  defaultFeed: 'latest', feeds: [{key: 'latest', label: '最新'},
    {key: 'categories', label: '分类', options: [{key: 'category', label: '分类', default: '', dynamic: true, values: []}]}],
  searchFilters: [{key: 'category', label: '分类', default: '', dynamic: true, values: []}],
  linkPatterns: ['eroasmr\\.com/video/([a-z0-9-]+)(?:/|[?#]|$)'],
  idPattern: '^[a-z0-9][a-z0-9-]{0,199}$',
  BASE: 'https://eroasmr.com',

  validId(id) {
    const value = String(id);
    if (!/^[a-z0-9][a-z0-9-]{0,199}$/.test(value)) throw Park.error('NOT_FOUND', '影片不存在');
    return value;
  },

  async page(path, params = {}) {
    const result = await this.http.get(this.BASE + path, {params});
    if (result.status === 404) throw Park.error('NOT_FOUND', '影片不存在');
    if (!result.ok) throw Park.error('HTTP', 'HTTP {status}', {params: {status: result.status}, status: result.status});
    if (result.body.length > 4 * 1024 * 1024) throw Park.error('PARSE', '媒体数据无效');
    return Park.html.parse(result.body);
  },

  cards(doc) {
    const items = [];
    for (const article of doc.querySelectorAll('article.viem_video')) {
      const link = article.querySelector('.post-title a[href], a.dt-image-link[href]');
      let url;
      try { url = new URL(link?.getAttribute('href') || '', this.BASE); } catch (_) { continue; }
      const match = /^\/video\/([a-z0-9][a-z0-9-]{0,199})\/?$/.exec(url.pathname);
      if (url.origin !== this.BASE || !match || items.some(item => item.id === match[1])) continue;
      const title = Park.html.text(article.querySelector('.post-title a')) || link?.getAttribute('title') || '';
      const image = article.querySelector('img');
      let cover = '';
      try {
        const candidate = new URL(image?.getAttribute('data-src') || image?.getAttribute('src') || '', this.BASE);
        if (candidate.protocol === 'https:' && candidate.hostname === 'eroasmr.com') cover = candidate.href;
      } catch (_) {}
      if (!title) continue;
      items.push({id: match[1], title, cover, coverAspect: 16 / 9,
        duration: Park.html.text(article.querySelector('.video-duration')),
        mediaKind: 'video', voiceMediaForm: 'videoOnly'});
    }
    return items;
  },

  async listing(req, params, path = '/') {
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    const doc = await this.page(path, {...params, paged: page});
    const items = this.cards(doc);
    let hasNext = false;
    for (const link of doc.querySelectorAll('.pagination a[href]')) {
      let url;
      try { url = new URL(link.getAttribute('href'), this.BASE); } catch (_) { continue; }
      if (url.origin !== this.BASE) continue;
      const next = Number(url.searchParams.get('paged') || /\/page\/(\d+)\/?$/.exec(url.pathname)?.[1] || 0);
      const label = Park.html.text(link);
      if (next > page || (/^\d+$/.test(label) && Number(label) > page)) hasNext = true;
    }
    if (!items.length && params.post_type && page === 1) throw Park.error('PARSE', '媒体数据无效');
    return {items, page, hasNext};
  },

  async feed(key, req) {
    if (key === 'categories') {
      const category = String(req.options?.category || '');
      if (!category) return this.listing(req, {post_type: 'viem_video'});
      if (!/^[a-z0-9-]{1,100}$/.test(category)) throw Park.error('CONFIG', '筛选参数无效');
      return this.listing(req, {}, '/video-category/' + category + '/');
    }
    if (key !== 'latest') throw Park.error('CONFIG', '筛选参数无效');
    return this.listing(req, {post_type: 'viem_video'});
  },

  async search(req) {
    const keyword = String(req.keyword || '').trim();
    if (!keyword) return {items: [], page: 1, hasNext: false};
    const category = String(req.filters?.category || '');
    if (category && !/^[a-z0-9-]{1,100}$/.test(category)) throw Park.error('CONFIG', '筛选参数无效');
    return this.listing(req, {s: keyword, ...(category ? {video_cat: category} : {})});
  },

  async filterOptions(request) {
    if (request.filter !== 'category' || !['feed', 'search'].includes(request.scope)) return [];
    const doc = await this.page('/');
    const values = [{value: '', label: '全部'}], seen = new Set();
    for (const link of doc.querySelectorAll('a[href]')) {
      let value;
      try { value = new URL(link.getAttribute('href'), this.BASE); } catch (_) { continue; }
      const match = /^\/video-category\/([a-z0-9-]{1,100})\/$/.exec(value.pathname);
      const label = Park.html.text(link);
      if (value.origin !== this.BASE || !match || !label || seen.has(match[1])) continue;
      seen.add(match[1]); values.push({value: match[1], label});
    }
    if (values.length === 1) throw Park.error('PARSE', '媒体数据无效');
    return values;
  },

  async detail(id) {
    id = this.validId(id);
    const doc = await this.page('/video/' + id + '/');
    const title = doc.querySelector('meta[property="og:title"]')?.getAttribute('content') || '';
    if (!title) throw Park.error('PARSE', '媒体数据无效');
    const cover = doc.querySelector('meta[property="og:image"]')?.getAttribute('content') || '';
    const description = doc.querySelector('meta[property="og:description"]')?.getAttribute('content') || '';
    return {id, title, cover, description, url: this.BASE + '/video/' + id + '/',
      coverAspect: 16 / 9, mediaKind: 'video', voiceMediaForm: 'videoOnly'};
  },

  async videos(id) {
    id = this.validId(id);
    const doc = await this.page('/video/' + id + '/');
    const raw = doc.querySelector('video source[src], video[src]')?.getAttribute('src') || '';
    let url;
    try { url = new URL(raw, this.BASE); } catch (_) {}
    if (!url || url.protocol !== 'https:' || url.username || url.password ||
        !(url.hostname === 'eroasmr.com' || url.hostname.endsWith('.eroasmr.com')) ||
        !/\.mp4$/i.test(url.pathname)) throw Park.error('UNSUPPORTED', '此影片暂无可用播放地址');
    return [{url: url.href, format: 'mp4', label: '原画', preferred: true,
      headers: {Referer: this.BASE + '/video/' + id + '/'}}];
  },
});
