/* Jable.TV page data; remote player scripts are never executed. */
Park.register({
  key: 'jable', name: 'JableTV', version: '0.0.3', type: 'video', category: 'jav',
  color: '#14B8A6', description: 'JAV 视频，支持热门、搜索与 HLS 播放',
  homepage: 'https://jable.tv', domains: ['jable.tv'], language: 'zh-Hant',
  network: {mode: 'browser', origin: 'https://jable.tv', vpnHint: true},
  media: {mode: 'native', origin: 'https://jable.tv', domains: ['mushroomtrack.com']},
  imageHeaders: {Referer: 'https://jable.tv/'},
  linkPatterns: ['jable\\.tv/videos/([a-z0-9][a-z0-9-]{1,120})(?:/|[?#]|$)'],
  idPattern: '^[a-z0-9][a-z0-9-]{1,120}$', idExample: 'ipzz-961',
  defaultFeed: 'hot', feeds: [{key: 'hot', label: '本周热门'}, {key: 'today-hot', label: '今日热门'},
    {key: 'monthly-hot', label: '本月热门'}, {key: 'new', label: '最近更新'}, {key: 'release', label: '最新上市'}],
  searchHint: '搜索番号、作品名或演员',
  settings: [{key: 'quality', type: 'select', label: '默认清晰度', default: '1080', options: [
    {value: '1080', label: '1080P'}, {value: '720', label: '720P'}, {value: '480', label: '480P'}]}],
  BASE: 'https://jable.tv',
  validId(id) {
    const value = String(id).toLowerCase();
    if (!/^[a-z0-9][a-z0-9-]{1,120}$/.test(value)) throw Park.error('NOT_FOUND', '影片编号无效');
    return value;
  },
  async getPage(path, params = {}) {
    const response = await this.http.get(this.BASE + path, {params});
    if (response.status === 404) throw Park.error('NOT_FOUND', '影片不存在');
    if (!response.ok) throw Park.error('HTTP', `JableTV HTTP ${response.status}`, {status: response.status});
    if (response.body.length > 4 * 1024 * 1024) throw Park.error('PARSE', '影片页面过大');
    return {html: response.body, doc: Park.html.parse(response.body)};
  },
  cards(doc) {
    const items = [];
    for (const card of doc.querySelectorAll('.video-img-box')) {
      const a = card.querySelector('.detail a[href]'), img = card.querySelector('.img-box img');
      const match = a && /^https:\/\/jable\.tv\/videos\/([a-z0-9][a-z0-9-]{1,120})\/$/.exec(a.getAttribute('href') || '');
      const cover = img && (img.getAttribute('data-src') || img.getAttribute('src'));
      const title = Park.html.text(a);
      if (!match || !title || !/^https:\/\//.test(cover || '') || items.some(i => i.id === match[1])) continue;
      items.push({id: match[1], title, cover, coverAspect: 16/9, duration: Park.html.text(card.querySelector('.label'))});
    }
    return items;
  },
  async listing(path, req, params = {}) {
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    const {doc} = await this.getPage(path + (page > 1 ? page + '/' : ''), params);
    let totalPages = page;
    for (const a of doc.querySelectorAll('.pagination a[href]')) {
      const m = /\/(\d+)\/(?:[?#]|$)/.exec(a.getAttribute('href') || '');
      if (m) totalPages = Math.max(totalPages, Number(m[1]));
    }
    return {items: this.cards(doc), page, totalPages, hasNext: page < totalPages};
  },
  async feed(key, req) {
    const routes = {hot: ['/hot/', 'video_viewed_week'], 'today-hot': ['/hot/', 'video_viewed_today'],
      'monthly-hot': ['/hot/', 'video_viewed_month'], new: ['/latest-updates/'], release: ['/new-release/']};
    const route = routes[key];
    if (!route) throw Park.error('CONFIG', '未知视频列表');
    return this.listing(route[0], req, route[1] ? {sort_by: route[1]} : {});
  },
  async search(req) {
    const category = (req.filters || {}).category;
    if (typeof category === 'string' && /^\/(?:categories|tags|models)\/[a-zA-Z0-9_%+-]+\/$/.test(category)) return this.listing(category, req);
    const keyword = String(req.keyword || '').trim();
    if (!keyword) return {items: [], page: 1, totalPages: 1, hasNext: false};
    return this.listing('/search/' + encodeURIComponent(keyword) + '/', req);
  },
  async detail(id) {
    id = this.validId(id);
    const {doc} = await this.getPage('/videos/' + id + '/');
    const title = Park.html.text(doc.querySelector('.video-info h4'));
    if (!title) throw Park.error('NOT_FOUND', '影片不存在');
    const image = doc.querySelector('meta[property="og:image"]');
    const tags = [];
    for (const a of doc.querySelectorAll('.video-info .tags a[href], .video-info .models a[href]')) {
      const m = /^https:\/\/jable\.tv(\/(categories|tags|models)\/[a-zA-Z0-9_%+-]+\/)$/ .exec(a.getAttribute('href') || '');
      const tooltip = a.querySelector('[data-original-title], [title]');
      const name = tooltip && (tooltip.getAttribute('data-original-title') || tooltip.getAttribute('title')) || Park.html.text(a);
      if (m && name) tags.push({name, keyword: '', filters: {category: m[1]}});
    }
    return {id, title, cover: image ? image.getAttribute('content') : '', coverAspect: 16/9,
      url: this.BASE + '/videos/' + id + '/', description: Park.html.text(doc.querySelector('.video-info .desc')),
      authors: tags.filter(t => t.filters.category.startsWith('/models/')).map(t => t.name),
      tags: tags.length ? [{namespace: 'tag', label: '标签', tags}] : [], related: this.cards(doc).filter(i => i.id !== id)};
  },
  async videos(id) {
    id = this.validId(id);
    const {html} = await this.getPage('/videos/' + id + '/');
    const match = /\bhlsUrl\s*=\s*['"](https:\/\/[^'"\s]+)['"]/.exec(html);
    if (!match || !/^https:\/\/(?:[a-z0-9-]+\.)*mushroomtrack\.com\/[^\s]+\.m3u8(?:\?[^\s]*)?$/.test(match[1])) {
      throw Park.error('UNSUPPORTED', '此影片没有可用的 HLS 清晰度');
    }
    return [{url: match[1], quality: Number(this.config.quality) || 1080, label: '原画', format: 'hls', preferred: true,
      headers: {Referer: this.BASE + '/videos/' + id + '/', Origin: this.BASE}}];
  },
});

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"},{"key":"code","label":"完整番号","hint":"请输入完整番号，例如 ABP-123"}]});
