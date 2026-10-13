/* 只解析聚合索引，不带源 Cookie 请求外部作品或执行远端脚本。 */
Park.register({
  key: 'ixxx', name: 'iXXX', version: '0.0.3', type: 'video', category: 'adult', color: '#F97316',
  description: '综合成人视频搜索，支持排行、分页与原站打开',
  homepage: 'https://www.ixxx.com', domains: ['ixxx.com', 'ttcache.com'], language: 'en',
  network: {mode: 'native', vpnHint: true, confirmation: {
    selector: '#splash-page[open], #age-verification', readySelector: 'a.item-link[href]',
    requiredCookies: ['splashPageAccepted'],
    message: '请在站点页面中完成年龄确认后继续',
  }}, imageHeaders: {Referer: 'https://www.ixxx.com/'},
  defaultFeed: 'ranking', feeds: [{key: 'ranking', label: '排行榜'}], searchHint: '搜索作品名或标签',
  BASE: 'https://www.ixxx.com',
  externalUrl(value) {
    if (typeof value !== 'string' || value.length > 4096 || /[\x00-\x20\\]/.test(value)) return null;
    try {
      const u = new URL(value);
      if (!['https:', 'http:'].includes(u.protocol) || u.username || u.password || u.port ||
          !/^(?:[a-z0-9-]+\.)+[a-z]{2,63}$/.test(u.hostname) ||
          /(?:^|\.)(?:localhost|local|internal|test|invalid)$/.test(u.hostname)) return null;
      u.hash = '';
      for (const key of Array.from(u.searchParams.keys())) {
        if (/^(?:utm_.+|trx|ref|referrer|aff_id|affiliate_id)$/i.test(key)) u.searchParams.delete(key);
      }
      return u.href;
    } catch (_) { return null; }
  },
  target(href) {
    try {
      const u = new URL(href, this.BASE);
      if (u.origin !== this.BASE || u.pathname !== '/out/') return null;
      const value = u.searchParams.get('l');
      if (!value || value.length > 16384 || !/^[a-zA-Z0-9+/]*={0,2}$/.test(value)) return null;
      const raw = atob(value), match = /https?:\/\/[\x21-\x7e]+/.exec(raw);
      return match ? this.externalUrl(match[0]) : null;
    } catch (_) { return null; }
  },
  pageUrl(value, kind) {
    try {
      const u = new URL(value, this.BASE);
      const validPath = kind === 'feed' ? u.pathname === '/rating' : /^\/c\/[^/?#]+\/?$/.test(u.pathname);
      if (u.origin === this.BASE && !u.username && !u.password && !u.hash && validPath &&
          !/%2f|%5c|%2e/i.test(u.pathname) &&
          Array.from(u.searchParams.keys()).every(k => k === 'page') &&
          (!u.searchParams.has('page') || /^[1-9]\d{0,5}$/.test(u.searchParams.get('page')))) return u.href;
    } catch (_) {}
    throw Park.error('CONFIG', '视频列表地址无效');
  },
  async request(url, form) {
    const r = form ? await this.http.post(url, {form, timeout: 30000}) : await this.http.get(url, {timeout: 30000});
    if (!r.ok) throw Park.error('HTTP', '成人视频请求失败');
    if (new URL(r.url || url).origin !== this.BASE) throw Park.error('BLOCKED', '站点需要在浏览器中确认后访问');
    if (r.body.length > 4 * 1024 * 1024) throw Park.error('PARSE', '影片页面过大');
    const doc = Park.html.parse(r.body);
    if (doc.querySelector(this.network.confirmation.selector)) {
      const cookies = await this.cookies.get(this.BASE + '/');
      if (!cookies.splashPageAccepted || doc.querySelector('#age-verification')) {
        throw Park.error('CONFIRM_REQUIRED', '请在站点页面中完成年龄确认后继续', {url: r.url || url});
      }
    }
    return {doc, url: r.url || url};
  },
  cards(doc) {
    const items = [], seen = new Set();
    for (const a of doc.querySelectorAll('a.item-link[href]')) {
      const id = this.target(a.getAttribute('href'));
      const img = a.querySelector('img'), title = a.getAttribute('title') || img?.getAttribute('alt');
      const cover = img?.getAttribute('data-src') || img?.getAttribute('src');
      if (!id || !title || seen.has(id) || !this.coverUrl(cover)) continue;
      seen.add(id);
      const card = a.closest('.card');
      items.push({id, title: Park.html.unescape(title).trim(), cover, coverAspect: 16/9,
        duration: Park.html.text(a.querySelector('.badge')),
        uploader: Park.html.text(card?.querySelector('.item-source')), url: id});
    }
    return items;
  },
  coverUrl(value) {
    try { const u = new URL(value); return u.protocol === 'https:' && !u.username && !u.password && !u.port && /^(?:c[1-4]\.)ttcache\.com$/.test(u.hostname); }
    catch (_) { return false; }
  },
  result({doc, url}, page, kind) {
    let cursor;
    for (const a of doc.querySelectorAll('a[href]')) {
      if (Park.html.text(a) !== String(page + 1)) continue;
      try {
        const next = this.pageUrl(new URL(a.getAttribute('href'), url).href, kind);
        if (Number(new URL(next).searchParams.get('page')) === page + 1) { cursor = next; break; }
      } catch (_) {}
    }
    return {items: this.cards(doc), page, hasNext: !!cursor, cursor};
  },
  async feed(key, req) {
    if (key !== 'ranking') throw Park.error('CONFIG', '未知视频列表');
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    if (page > 1 && !req.cursor) throw Park.error('CONFIG', '请按顺序加载视频列表');
    return this.result(await this.request(this.pageUrl(req.cursor || this.BASE + '/rating', 'feed')), page, 'feed');
  },
  async search(req) {
    const keyword = String(req.keyword || '').trim(), page = Math.max(1, Math.floor(Number(req.page) || 1));
    if (!keyword) return {items: [], page, hasNext: false};
    if (page > 1 && !req.cursor) throw Park.error('CONFIG', '请按顺序加载视频列表');
    const result = page === 1
      ? await this.request(this.BASE + '/searching/by-form', {'search_query[query]': keyword})
      : await this.request(this.pageUrl(req.cursor, 'search'));
    return this.result(result, page, 'search');
  },
  async detail(id, preview) {
    const url = this.externalUrl(id);
    if (!url || url !== id) throw Park.error('NOT_FOUND', '影片编号无效');
    const item = preview && preview.id === id ? preview : {};
    return {id, url, title: typeof item.title === 'string' && item.title ? item.title : new URL(url).hostname,
      cover: this.coverUrl(item.cover) ? item.cover : '', coverAspect: 16/9,
      duration: typeof item.duration === 'string' ? item.duration : '',
      uploader: typeof item.uploader === 'string' ? item.uploader : '', tags: [], authors: []};
  },
});

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"}]});
