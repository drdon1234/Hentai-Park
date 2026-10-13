/* 完整详情路径作为作品 ID；静态提取媒体，不执行远程播放器代码。 */
Park.register({
  key: 'xvideos', name: 'XVideos', version: '0.0.2', type: 'video', category: 'adult', color: '#E31B23',
  description: '综合成人视频，支持排行、搜索和高清播放', homepage: 'https://www.xvideos.com', domains: ['xvideos.com'], language: 'en',
  network: {mode: 'native', vpnHint: true}, imageHeaders: {Referer: 'https://www.xvideos.com/'},
  linkPatterns: ['xvideos\\.com/(video\\.[a-z0-9]+/[^?#\\s]+)(?:[?#]|$)'],
  defaultFeed: 'ranking', feeds: [{key: 'ranking', label: '排行榜'}], searchHint: '搜索作品名或标签', BASE: 'https://www.xvideos.com',
  siteUrl(u) { return u.protocol === 'https:' && u.hostname === 'www.xvideos.com' && !u.port && !u.username && !u.password && !u.hash; },
  validId(id) {
    const value = String(id);
    if (value.length > 2048 || !/^video\.[a-z0-9]{5,32}\/[a-zA-Z0-9_%./-]+$/.test(value) || /(?:^|\/)\.\.(?:\/|$)/.test(value) || /%(?![0-9a-f]{2})|%2[ef]|%5c/i.test(value)) throw Park.error('NOT_FOUND', '影片编号无效');
    return value;
  },
  pageUrl(value, kind) {
    let u;
    try { u = new URL(value, this.BASE); } catch (_) { throw Park.error('CONFIG', '视频列表地址无效'); }
    const allowed = kind === 'feed' ? /^\/best(?:\/\d{4}-\d{2}(?:\/\d+)?)?$/.test(u.pathname) : u.pathname === '/' || /^\/tags\/[a-z0-9_-]+(?:\/\d+)?\/?$/i.test(u.pathname);
    if (!allowed || !this.siteUrl(u)) throw Park.error('CONFIG', '视频列表地址无效');
    return u.href;
  },
  mediaUrl(value) {
    try {
      const u = new URL(value);
      if (u.protocol !== 'https:' || u.port || u.username || u.password || u.hash || !/^(?:[a-z0-9-]+\.)*xvideos-cdn\.com$/.test(u.hostname) || !/\.mp4$/i.test(u.pathname)) return null;
      return u.href;
    } catch (_) { return null; }
  },
  async getPage(url) {
    const r = await this.http.get(url, {timeout: 30000});
    if (r.status === 404) throw Park.error('NOT_FOUND', '影片不存在');
    if (!r.ok) throw Park.error('HTTP', '成人视频请求失败');
    if (!this.siteUrl(new URL(r.url || url))) throw Park.error('BLOCKED', '站点需要在浏览器中确认后访问');
    if (r.body.length > 4 * 1024 * 1024) throw Park.error('PARSE', '影片页面过大');
    return {html: r.body, doc: Park.html.parse(r.body), url: r.url || url};
  },
  cards(doc) {
    const items = [], seen = new Set();
    for (const c of doc.querySelectorAll('div.thumb-block')) {
      const a = c.querySelector('.title a[href]') || c.querySelector('a[href^="/video."]'), img = c.querySelector('img');
      const href = a && a.getAttribute('href'), title = Park.html.text(a), cover = img && (img.getAttribute('data-src') || img.getAttribute('src'));
      if (!href || !title || !/^https:\/\//.test(cover || '')) continue;
      let id;
      try { const u = new URL(href, this.BASE); if (!this.siteUrl(u)) continue; id = this.validId(u.pathname.slice(1)); } catch (_) { continue; }
      const encoded = /^video\.([^/]+)/.exec(id)[1];
      if (seen.has(encoded)) continue;
      seen.add(encoded); items.push({id, title, cover, coverAspect: 16/9, duration: Park.html.text(c.querySelector('.duration')),
        views: Park.utils.parseCount(Park.html.text(c.querySelector('.views-count'))), uploader: Park.html.text(c.querySelector('.name'))});
    }
    return items;
  },
  async listing(url, req, kind) {
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    if (page > 1 && !req.cursor) throw Park.error('CONFIG', '请按顺序加载视频列表');
    const {doc, url: finalUrl} = await this.getPage(this.pageUrl(req.cursor || url, kind));
    let cursor;
    for (const a of doc.querySelectorAll('.pagination a[href], .pagination3 a[href]')) {
      const u = new URL(a.getAttribute('href'), finalUrl);
      const index = kind === 'feed' ? /\/(\d+)$/.exec(u.pathname)?.[1] : u.searchParams.get('p') || /\/(\d+)\/?$/.exec(u.pathname)?.[1];
      if (index !== null && index !== undefined && Number(index) === page) { cursor = this.pageUrl(u.href, kind); break; }
    }
    return {items: this.cards(doc), page, hasNext: !!cursor, cursor};
  },
  async feed(key, req) {
    if (key !== 'ranking') throw Park.error('CONFIG', '未知视频列表');
    return this.listing(this.BASE + '/best', req, 'feed');
  },
  async search(req) {
    const keyword = String(req.keyword || '').trim(), tag = req.filters?.tag;
    if (typeof tag === 'string' && /^\/tags\/[a-z0-9_-]+\/?$/i.test(tag)) return this.listing(this.BASE + tag, req, 'search');
    if (!keyword) return {items: [], page: 1, hasNext: false};
    return this.listing(this.BASE + '/?k=' + encodeURIComponent(keyword), req, 'search');
  },
  async detail(id) {
    id = this.validId(id);
    const url = this.BASE + '/' + id, {doc} = await this.getPage(url);
    const title = doc.querySelector('meta[property="og:title"]')?.getAttribute('content'), cover = doc.querySelector('meta[property="og:image"]')?.getAttribute('content');
    if (!title || !cover) throw Park.error('PARSE', '成人视频详情解析失败');
    const tags = [], seen = new Set();
    for (const a of doc.querySelectorAll('a[href^="/tags/"]')) {
      const tag = a.getAttribute('href'), name = Park.html.text(a);
      if (name && /^\/tags\/[a-z0-9_-]+\/?$/i.test(tag) && !seen.has(tag)) { seen.add(tag); tags.push({name, keyword: '', filters: {tag}}); }
    }
    return {id, title, cover, coverAspect: 16/9, url, duration: Park.html.text(doc.querySelector('h2.page-title .duration')),
      description: '', authors: [], tags: tags.length ? [{namespace: 'tag', label: '标签', tags}] : [], related: this.cards(doc).filter(i => i.id !== id)};
  },
  async videos(id) {
    const referer = this.BASE + '/' + this.validId(id), {html} = await this.getPage(referer);
    const videos = [], seen = new Set();
    for (const [method, label] of [['setVideoUrlHigh', '高清'], ['setVideoUrlLow', '标清']]) {
      const match = new RegExp('html5player\\.' + method + '\\([\'"]([^\'"\\s]+)[\'"]\\)').exec(html);
      const url = match && this.mediaUrl(match[1].replace(/\\\//g, '/'));
      if (url && !seen.has(url)) { seen.add(url); videos.push({quality: 0, label, url, preferred: videos.length === 0, headers: {Referer: referer}}); }
    }
    if (!videos.length) throw Park.error('UNSUPPORTED', '此影片没有可用的 MP4 清晰度');
    return videos;
  },
});

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"}]});
