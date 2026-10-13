/* 69story：只读取同站小说，正文与广告分离。 */
Park.register({
  key: 'story69', name: '69story', version: '0.0.2', type: 'novel', category: 'novel',
  language: 'zh-Hant', color: '#D56A74', homepage: 'https://69story.com',
  description: '中文短篇小说，支持最新与分类阅读；站点无有效搜索',
  domains: ['69story.com'], network: {mode: 'native', vpnHint: true},
  defaultFeed: 'latest', feeds: [{key: 'latest', label: '最新'}, {key: 'wife', label: '人妻'}, {key: 'sex-in-the-city', label: '都市生活'}],
  linkPatterns: ['69story\\.com/article/(\\d+)-'], idPattern: '^\\d{1,12}$',
  BASE: 'https://69story.com',
  idValue(value) {
    if (!/^\d{1,12}$/.test(String(value))) throw Park.error('NOT_FOUND', '作品编号无效');
    return String(value);
  },
  siteUrl(value) {
    if (typeof value !== 'string' || !value.trim()) return null;
    try { const u = new URL(value, this.BASE); return u.origin === this.BASE && !u.username && !u.password && !u.hash ? u : null; }
    catch (_) { return null; }
  },
  async page(url) {
    if (!this.siteUrl(url)) throw Park.error('CONFIG', '站点链接无效');
    const r = this.http.ensureOk(await this.http.get(url));
    if (!this.siteUrl(r.url || url)) throw Park.error('BLOCKED', '站点需要在浏览器中确认后访问');
    return {doc: Park.html.parse(r.body), url: r.url || url};
  },
  cards(doc) {
    const items = [], seen = new Set();
    for (const row of doc.querySelectorAll('main tr[id^="post-"]')) {
      const a = row.querySelector('td.entry-content a[rel="bookmark"]'), u = a && this.siteUrl(a.getAttribute('href'));
      const m = u && /^\/article\/(\d{1,12})-[^/]+\.html$/.exec(u.pathname), title = Park.html.text(a);
      if (!m || !title || seen.has(m[1])) continue;
      seen.add(m[1]); items.push({id: m[1], title, url: u.href, cover: '', mediaKind: 'novel', language: 'zh-Hant'});
    }
    return items;
  },
  async feed(key, req) {
    if (!this.feeds.some(x => x.key === key)) throw Park.error('CONFIG', '未知列表');
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    const base = key === 'latest' ? '' : '/' + key;
    const {doc} = await this.page(this.BASE + base + (page > 1 ? '/page/' + page + '/' : '/'));
    const items = this.cards(doc);
    const nextPath = base + '/page/' + (page + 1) + '/';
    const hasNext = [...doc.querySelectorAll('a[href]')].some(a => this.siteUrl(a.getAttribute('href'))?.pathname.replace(/\/$/, '') === nextPath.replace(/\/$/, ''));
    return {items, page, hasNext};
  },
  async detail(value) {
    const id = this.idValue(value), {doc, url} = await this.page(this.BASE + '/?p=' + id);
    const article = doc.querySelector('article#post-' + id), title = Park.html.text(article?.querySelector('h1'));
    if (!article || !title) throw Park.error('NOT_FOUND', '小说不存在');
    const tags = [...article.querySelectorAll('a[rel="tag"]')].map(a => ({name: Park.html.text(a)})).filter(x => x.name);
    return {id, title, url, cover: '', mediaKind: 'novel', language: 'zh-Hant', chapters: null, authors: [], tags, related: []};
  },
  paragraphs(doc, id) {
    const body = doc.querySelector('article#post-' + this.idValue(id) + ' > div.entry-content');
    if (!body) throw Park.error('PARSE', '小说正文为空或受限');
    for (const ad of body.querySelectorAll('script,style,iframe,ins,div')) ad.remove();
    const paragraphs = Park.html.paragraphs(body);
    if (!paragraphs.length) throw Park.error('PARSE', '小说正文为空或受限');
    return paragraphs;
  },
  async textChapter(value, chapterId) {
    const id = this.idValue(value);
    if (chapterId && chapterId !== '_' && chapterId !== id) throw Park.error('NOT_FOUND', '章节编号无效');
    const {doc} = await this.page(this.BASE + '/?p=' + id);
    return {paragraphs: this.paragraphs(doc, id)};
  },
});
