/* 静态解析页面 JSON 与官方 MP4 元数据，不执行远程脚本。 */
Park.register({
  key: 'pornhub', name: 'Pornhub', version: '0.0.2', type: 'video', category: 'adult',
  color: '#FF9900', description: '综合成人视频，支持推荐、搜索和多清晰度播放',
  homepage: 'https://www.pornhub.com', domains: ['pornhub.com'], language: 'en',
  network: {mode: 'native', vpnHint: true}, imageHeaders: {Referer: 'https://www.pornhub.com/'},
  linkPatterns: ['pornhub\\.com/view_video\\.php\\?(?:[^#]*&)?viewkey=([a-z0-9]{5,64})(?:&|#|$)'],
  idPattern: '^[a-z0-9]{5,64}$', idExample: '6aa2dcb8c56d1',
  defaultFeed: 'recommend', feeds: [{key: 'recommend', label: '推荐'}], searchHint: '搜索作品名或标签',
  settings: [{key: 'quality', type: 'select', label: '默认清晰度', default: '1080', options: [
    {value: '1080', label: '1080P'}, {value: '720', label: '720P'}, {value: '480', label: '480P'}, {value: '240', label: '240P'}]}],
  BASE: 'https://www.pornhub.com',
  validId(id) {
    const value = String(id);
    if (!/^[a-z0-9]{5,64}$/.test(value)) throw Park.error('NOT_FOUND', '影片编号无效');
    return value;
  },
  siteUrl(u) { return u.protocol === 'https:' && u.hostname === 'www.pornhub.com' && !u.port && !u.username && !u.password && !u.hash; },
  pageUrl(value, kind) {
    let u;
    try { u = new URL(value, this.BASE); } catch (_) { throw Park.error('CONFIG', '视频列表地址无效'); }
    if (!this.siteUrl(u) || u.pathname !== (kind === 'feed' ? '/recommended' : '/video/search')) throw Park.error('CONFIG', '视频列表地址无效');
    return u.href;
  },
  mediaUrl(value) {
    try {
      const u = new URL(value);
      if (u.protocol !== 'https:' || u.port || u.username || u.password || u.hash || !/^(?:[a-z0-9-]+\.)*phncdn\.com$/.test(u.hostname) || !/\.mp4$/i.test(u.pathname)) return null;
      return u.href;
    } catch (_) { return null; }
  },
  async getPage(url, headers = {}) {
    const r = await this.http.get(url, {headers, timeout: 30000});
    if (r.status === 404) throw Park.error('NOT_FOUND', '影片不存在');
    if (!r.ok) throw Park.error('HTTP', '成人视频请求失败');
    if (!this.siteUrl(new URL(r.url || url))) throw Park.error('BLOCKED', '站点需要在浏览器中确认后访问');
    if (r.body.length > 4 * 1024 * 1024) throw Park.error('PARSE', '影片页面过大');
    return {html: r.body, doc: Park.html.parse(r.body), url: r.url || url};
  },
  cards(doc) {
    const items = [], seen = new Set();
    for (const c of doc.querySelectorAll('li[data-video-vkey]')) {
      const a = c.querySelector('.title a[href]') || c.querySelector('a[href*="view_video.php"]'), img = c.querySelector('img');
      const m = a && /(?:\?|&)viewkey=([a-z0-9]{5,64})(?:&|$)/.exec(a.getAttribute('href') || '');
      const title = Park.html.text(a), cover = img && (img.getAttribute('data-image') || img.getAttribute('src'));
      if (!m || !title || !/^https:\/\//.test(cover || '') || seen.has(m[1])) continue;
      seen.add(m[1]); items.push({id: m[1], title, cover, coverAspect: 16/9, duration: Park.html.text(c.querySelector('.duration')),
        views: Park.utils.parseCount(Park.html.text(c.querySelector('.views var, .videoViews'))), uploader: Park.html.text(c.querySelector('.usernameWrap a, .uploaderLink'))});
    }
    return items;
  },
  async listing(url, req, kind) {
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    url = this.pageUrl(req.cursor || url, kind);
    if (!req.cursor && page > 1) { const u = new URL(url); u.searchParams.set('page', page); url = u.href; }
    const {doc, url: finalUrl} = await this.getPage(url);
    let cursor;
    for (const a of doc.querySelectorAll('.pagination a[href], .pagination3 a[href]')) {
      const u = new URL(a.getAttribute('href'), finalUrl);
      if (Number(u.searchParams.get('page')) === page + 1) { cursor = this.pageUrl(u.href, kind); break; }
    }
    return {items: this.cards(doc), page, hasNext: !!cursor, cursor};
  },
  async feed(key, req) {
    if (key !== 'recommend') throw Park.error('CONFIG', '未知视频列表');
    return this.listing(this.BASE + '/recommended', req, 'feed');
  },
  async search(req) {
    const keyword = String(req.keyword || '').trim();
    if (!keyword) return {items: [], page: 1, hasNext: false};
    return this.listing(this.BASE + '/video/search?search=' + encodeURIComponent(keyword), req, 'search');
  },
  async detail(id) {
    id = this.validId(id);
    const url = this.BASE + '/view_video.php?viewkey=' + id, {doc} = await this.getPage(url);
    const title = Park.html.text(doc.querySelector('h1.title')) || doc.querySelector('meta[property="og:title"]')?.getAttribute('content');
    const cover = doc.querySelector('meta[property="og:image"]')?.getAttribute('content');
    if (!title || !cover) throw Park.error('PARSE', '成人视频详情解析失败');
    const tags = [], seen = new Set();
    for (const a of doc.querySelectorAll('.video-detailed-info a[href*="/video/search"], .abovePlayerButtons a[href*="/video/search"]')) {
      const u = new URL(a.getAttribute('href'), this.BASE), keyword = u.searchParams.get('search'), name = Park.html.text(a);
      if (this.siteUrl(u) && keyword && name && !seen.has(keyword)) { seen.add(keyword); tags.push({name, keyword}); }
    }
    return {id, title, cover, coverAspect: 16/9, url, description: Park.html.text(doc.querySelector('.videoDescription')),
      authors: [Park.html.text(doc.querySelector('.userRow .usernameWrap a'))].filter(Boolean),
      tags: tags.length ? [{namespace: 'tag', label: '标签', tags}] : [], related: this.cards(doc).filter(i => i.id !== id)};
  },
  playerData(html) {
    const m = /\bvar\s+flashvars_\d+\s*=\s*/.exec(html);
    if (!m) throw Park.error('UNSUPPORTED', '此影片没有可用的 MP4 清晰度');
    const start = m.index + m[0].length;
    let depth = 0, quoted = false, escape = false;
    for (let end = start; end < html.length; end++) {
      const c = html[end];
      if (quoted) { if (escape) escape = false; else if (c === '\\') escape = true; else if (c === '"') quoted = false; }
      else if (c === '"') quoted = true;
      else if (c === '{') depth++;
      else if (c === '}' && --depth === 0) {
        try { return JSON.parse(html.slice(start, end + 1)); } catch (_) { break; }
      }
    }
    throw Park.error('PARSE', '成人视频播放数据解析失败');
  },
  async videos(id) {
    const referer = this.BASE + '/view_video.php?viewkey=' + this.validId(id), {html} = await this.getPage(referer);
    const data = this.playerData(html), entries = Array.isArray(data.mediaDefinitions) ? data.mediaDefinitions : [];
    const endpoint = entries.find(i => i && i.format === 'mp4' && typeof i.videoUrl === 'string');
    let u;
    try { u = new URL(endpoint?.videoUrl); } catch (_) { throw Park.error('UNSUPPORTED', '此影片没有可用的 MP4 清晰度'); }
    if (!this.siteUrl(u) || u.pathname !== '/video/get_media') throw Park.error('UNSUPPORTED', '此影片没有可用的 MP4 清晰度');
    const {html: payload} = await this.getPage(u.href, {Referer: referer});
    let qualities;
    try { qualities = JSON.parse(payload); } catch (_) { throw Park.error('PARSE', '成人视频播放数据解析失败'); }
    const videos = [], seen = new Set();
    for (const e of Array.isArray(qualities) ? qualities : []) {
      if (!e || typeof e !== 'object') continue;
      const url = this.mediaUrl(e.videoUrl), quality = Number(e.quality);
      if (!url || !Number.isInteger(quality) || quality < 144 || quality > 4320 || seen.has(quality)) continue;
      seen.add(quality); videos.push({quality, label: quality + 'P', url, headers: {Referer: referer}});
    }
    videos.sort((a, b) => b.quality - a.quality);
    if (!videos.length) throw Park.error('UNSUPPORTED', '此影片没有可用的 MP4 清晰度');
    (videos.find(v => v.quality <= (Number(this.config.quality) || 1080)) || videos[0]).preferred = true;
    return videos;
  },
});

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"}]});
