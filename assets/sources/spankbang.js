/* SpankBang：浏览器同源取页面，静态提取公开 MP4；不执行播放器。 */
Park.register({
  key: 'spankbang', name: 'SpankBang', version: '0.0.3', type: 'video', category: 'adult',
  language: 'en', color: '#F99B1C', homepage: 'https://spankbang.com',
  description: '综合成人视频，支持推荐、搜索与多清晰度MP4；可能需浏览器确认',
  domains: ['spankbang.com', 'sb-cd.com'], network: {mode: 'browser', origin: 'https://spankbang.com', vpnHint: true, confirmation: {
    selector: '#av-wrapper', readySelector: '[data-testid="video-item"] a[href*="/video/"], #new-video-page',
    requiredCookies: ['av'], message: '请在站点页面中完成年龄确认后继续',
  }},
  media: {mode: 'native', origin: 'https://spankbang.com', domains: ['sb-cd.com']},
  imageHeaders: {Referer: 'https://spankbang.com/'},
  defaultFeed: 'recommended', feeds: [{key: 'recommended', label: '推荐'}],
  linkPatterns: ['spankbang\\.com/([a-z0-9]+/video/[^/?#]+)'],
  idPattern: '^[a-z0-9]{1,12}/(?:video/)?[^/?#]{1,240}$', BASE: 'https://spankbang.com',
  idValue(value) {
    const id = String(value).replace('/video/', '/'), m = /^([a-z0-9]{1,12})\/([^/?#]{1,240})$/.exec(id);
    if (!m || /[\\\s]/.test(id)) throw Park.error('NOT_FOUND', '影片编号无效');
    let slug; try { slug = decodeURIComponent(m[2]); } catch (_) { throw Park.error('NOT_FOUND', '影片编号无效'); }
    if (/[/?#\\\x00-\x1f\x7f]/.test(slug) || !slug.trim() || slug === '.' || slug === '..') throw Park.error('NOT_FOUND', '影片编号无效');
    return id;
  },
  siteUrl(value) {
    if (typeof value !== 'string' || !value.trim()) return null;
    try { const u = new URL(value, this.BASE); return u.origin === this.BASE && !u.username && !u.password && !u.hash ? u : null; }
    catch (_) { return null; }
  },
  mediaUrl(value) {
    try {
      const u = new URL(value);
      return u.protocol === 'https:' && /^[a-z0-9-]+\.sb-cd\.com$/.test(u.hostname) && !u.port && !u.username && !u.password && /\.mp4$/i.test(u.pathname) ? u.href : '';
    } catch (_) { return ''; }
  },
  coverUrl(value) {
    try { const u = new URL(value, this.BASE); return u.protocol === 'https:' && u.hostname === 'tbi.sb-cd.com' && !u.port && !u.username && !u.password ? u.href : ''; }
    catch (_) { return ''; }
  },
  async page(url) {
    if (!this.siteUrl(url)) throw Park.error('CONFIG', '视频列表地址无效');
    const r = this.http.ensureOk(await this.http.get(url));
    if (!this.siteUrl(r.url || url)) throw Park.error('BLOCKED', '站点需要在浏览器中确认后访问');
    const doc = Park.html.parse(r.body);
    if (/\bid=["']av-wrapper["']/.test(r.body)) {
      const cookies = await this.cookies.get(this.BASE + '/');
      const [type, required] = String(cookies.av || '').split(':');
      const accepted = type === 'simple' && cookies.age_pass === '1' || type === 'advanced' && required === 'False';
      if (!accepted) throw Park.error('CONFIRM_REQUIRED', '请在站点页面中完成年龄确认后继续', {url: r.url || url});
    }
    return {html: r.body, doc, url: r.url || url};
  },
  cards(doc) {
    const items = [], seen = new Set();
    for (const a of doc.querySelectorAll('[data-testid="video-item"] a[href*="/video/"]')) {
      const img = a.querySelector('img'); if (!img) continue;
      const u = this.siteUrl(a.getAttribute('href')), m = u && /^\/([a-z0-9]{1,12})\/video\/([^/]+)\/?$/.exec(u.pathname);
      const cover = this.coverUrl(img.getAttribute('data-src') || img.getAttribute('src'));
      const title = img.getAttribute('alt') || a.getAttribute('title');
      if (!m || !cover || !title || seen.has(m[1])) continue;
      let id; try { id = this.idValue(m[1] + '/' + m[2]); } catch (_) { continue; }
      seen.add(m[1]); items.push({id, title, cover, url: u.href, coverAspect: 16/9});
    }
    return items;
  },
  async listing(req, keyword) {
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    const base = keyword === undefined ? '/' : '/s/' + encodeURIComponent(keyword.toLowerCase()).replace(/%20/g, '+') + '/';
    let url = this.BASE + base;
    if (page > 1) {
      const u = this.siteUrl(req.cursor);
      const expected = (keyword === undefined ? '/trending_videos/' : base) + page;
      if (!u || u.pathname.replace(/\/$/, '') !== expected || u.search) throw Park.error('CONFIG', '分页链接无效');
      url = u.href;
    }
    const {doc} = await this.page(url), items = this.cards(doc);
    let cursor;
    for (const a of doc.querySelectorAll('a[href]')) {
      if (Park.html.text(a) !== String(page + 1)) continue;
      const u = this.siteUrl(a.getAttribute('href'));
      if (u && (keyword === undefined ? /^\/trending_videos\//.test(u.pathname) : u.pathname.startsWith(base))) { cursor = u.href; break; }
    }
    return {items, page, hasNext: !!cursor, cursor};
  },
  async feed(key, req) {
    if (key !== 'recommended') throw Park.error('CONFIG', '未知列表');
    return this.listing(req);
  },
  async search(req) {
    const keyword = String(req.keyword || '').trim();
    return keyword ? this.listing(req, keyword) : {items: [], page: 1, hasNext: false};
  },
  workUrl(value) {
    const id = this.idValue(value), split = id.indexOf('/');
    return this.BASE + '/' + id.slice(0, split) + '/video/' + id.slice(split + 1);
  },
  async detail(value) {
    const id = this.idValue(value), url = this.workUrl(id), {doc} = await this.page(url);
    const title = Park.html.text(doc.querySelector('#new-video-page h1,h1')), cover = this.coverUrl(doc.querySelector('#player_cover_img')?.getAttribute('src') || doc.querySelector('meta[property="og:image"]')?.getAttribute('content'));
    if (!title) throw Park.error('NOT_FOUND', '影片不存在');
    return {id, title, cover, coverAspect: 16/9, url, chapters: null, tags: [], authors: [], related: this.cards(doc).filter(x => x.id !== id)};
  },
  parseVideos(html, referer) {
    const start = html.indexOf('var stream_data'), end = html.indexOf('};', start);
    if (start < 0 || end < start || end - start > 256 * 1024) return [];
    const data = html.slice(start, end + 2), out = [];
    for (const m of data.matchAll(/['"](\d+p|4k)['"]\s*:\s*\[([^\]]*)\]/g)) {
      const quality = m[1] === '4k' ? 2160 : parseInt(m[1], 10);
      for (const x of m[2].matchAll(/['"]([^'"]+)['"]/g)) {
        const url = this.mediaUrl(Park.html.unescape(x[1].replace(/\\\//g, '/')));
        if (url) { out.push({quality, label: quality + 'P', format: 'mp4', url, headers: {Referer: referer}}); break; }
      }
    }
    out.sort((a, b) => b.quality - a.quality);
    const best = out.find(x => x.quality <= 720) || out[out.length - 1]; if (best) best.preferred = true;
    return out;
  },
  async videos(value) {
    const referer = this.workUrl(value), {html} = await this.page(referer), out = this.parseVideos(html, referer);
    if (!out.length) throw Park.error('UNSUPPORTED', '此影片没有可用的 MP4 清晰度');
    return out;
  },
});
