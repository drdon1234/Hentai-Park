/* WordPress 编号入口解析当前页面，播放签名每次重新获取。 */
Park.register({
  i18n: {
    "zh-Hant": {"竖屏短视频，支持连续播放和搜索": "直式短影片，支援連續播放和搜尋"},
    "ja": {"竖屏短视频，支持连续播放和搜索": "連続再生と検索に対応する縦型動画"},
    "ko": {"竖屏短视频，支持连续播放和搜索": "연속 재생과 검색을 지원하는 세로 동영상"},
    "en": {"竖屏短视频，支持连续播放和搜索": "Vertical videos with continuous playback and search"},
    "es": {"竖屏短视频，支持连续播放和搜索": "Vídeos verticales con reproducción continua y búsqueda"},
    "ru": {"竖屏短视频，支持连续播放和搜索": "Вертикальные видео с непрерывным просмотром и поиском"},
    "ar": {"竖屏短视频，支持连续播放和搜索": "مقاطع عمودية تدعم التشغيل المتواصل والبحث"},
  },
  key: 'fyptt', name: 'Fyptt', version: '0.0.3', type: 'video', category: 'shortvideo',
  color: '#F34468', description: '竖屏短视频，支持连续播放和搜索', language: 'en',
  homepage: 'https://fyptt.to/', domains: ['fyptt.to'], network: {mode: 'native', vpnHint: true},
  imageHeaders: {Referer: 'https://fyptt.to/'},
  media: {mode: 'native', origin: 'https://fyptt.to', domains: ['stream.fyptt.to']},
  idPattern: '^[1-9]\\d{0,11}$', linkPatterns: ['fyptt\\.to/([1-9]\\d{0,11})/'],
  defaultFeed: 'latest', feeds: [{key: 'latest', label: '最新'}], searchHint: '搜索作品名或标签',
  BASE: 'https://fyptt.to',
  validId(value) {
    const id = String(value);
    if (!/^[1-9]\d{0,11}$/.test(id)) throw Park.error('NOT_FOUND', '影片编号无效');
    return id;
  },
  siteUrl(u) { return u.origin === this.BASE && !u.username && !u.password && !u.hash; },
  listUrl(value, keyword = '') {
    let u;
    try { u = new URL(value, this.BASE); } catch (_) { throw Park.error('CONFIG', '短视频分页数据无效'); }
    // WordPress 首页翻页会产生空的 ?0 参数；移除该已验证的无效参数。
    if (u.searchParams.get('0') === '') u.searchParams.delete('0');
    if (!this.siteUrl(u) || !/^\/(?:page\/[1-9]\d*\/)?$/.test(u.pathname)
      || (u.searchParams.get('s') || '') !== keyword || [...u.searchParams.keys()].some(k => k !== 's')) throw Park.error('CONFIG', '短视频分页数据无效');
    return u.href;
  },
  async document(url) {
    const r = await this.http.get(url, {headers: {Referer: this.BASE + '/'}, timeout: 30000});
    if (r.status === 404) throw Park.error('NOT_FOUND', '影片不存在');
    if (!r.ok) throw Park.error('HTTP', '短视频请求失败');
    if (!this.siteUrl(new URL(r.url || url))) throw Park.error('BLOCKED', '访问受限');
    if (r.body.length > 4 * 1024 * 1024) throw Park.error('PARSE', '短视频数据解析失败');
    return {doc: Park.html.parse(r.body), url: r.url || url};
  },
  cards(doc) {
    const items = [], seen = new Set();
    for (const c of doc.querySelectorAll('.fl-post-grid-post')) {
      const a = c.querySelector('.fl-post-grid-image a'), img = c.querySelector('.fl-post-grid-image img');
      if (!a || !img) continue;
      const u = new URL(a.getAttribute('href') || '', this.BASE), id = /^\/([1-9]\d{0,11})\//.exec(u.pathname)?.[1];
      const title = Park.html.text(c.querySelector('.fl-post-grid-title a')) || a.getAttribute('title');
      const cover = img.getAttribute('data-src') || img.getAttribute('src');
      if (!this.siteUrl(u) || !id || !title || !/^https:\/\//.test(cover || '') || seen.has(id)) continue;
      seen.add(id);
      items.push({id, title, cover, coverAspect: Number(img.getAttribute('width')) / Number(img.getAttribute('height')) || 9/16,
        url: u.href, uploaded: Park.html.text(c.querySelector('.fl-post-grid-date'))});
    }
    return items;
  },
  async listing(req, keyword = '') {
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    const path = page > 1 ? '/page/' + page + '/' : '/';
    const url = this.listUrl(req.cursor || this.BASE + path + (keyword ? '?s=' + encodeURIComponent(keyword) : ''), keyword);
    const {doc} = await this.document(url), next = doc.querySelector('a.page-numbers.next');
    const cursor = next ? this.listUrl(next.getAttribute('href'), keyword) : undefined;
    const items = this.cards(doc);
    if (!items.length && !doc.querySelector('.fl-post-grid, .fl-post-grid-empty')) throw Park.error('PARSE', '短视频数据解析失败');
    return {items, page, hasNext: !!cursor, cursor};
  },
  async feed(key, req = {}) {
    if (key !== 'latest') throw Park.error('CONFIG', '未知视频列表');
    return this.listing(req);
  },
  async search(req = {}) {
    const keyword = String(req.keyword || '').trim();
    return keyword ? this.listing(req, keyword) : {items: [], page: 1, hasNext: false};
  },
  async detailDocument(id) {
    id = this.validId(id);
    const result = await this.document(this.BASE + '/?p=' + id), u = new URL(result.url);
    if (!(u.pathname.startsWith('/' + id + '/') || u.pathname === '/' && u.searchParams.get('p') === id)) throw Park.error('NOT_FOUND', '影片不存在');
    return result;
  },
  async detail(id) {
    id = this.validId(id);
    const {doc, url} = await this.detailDocument(id);
    const title = Park.html.text(doc.querySelector('h1.fl-post-title, h1.entry-title')) || doc.querySelector('meta[property="og:title"]')?.getAttribute('content');
    const cover = doc.querySelector('meta[property="og:image"]')?.getAttribute('content');
    if (!title || !cover) throw Park.error('PARSE', '短视频数据解析失败');
    return {id, title, cover, coverAspect: 9/16, url, tags: [], chapters: null};
  },
  mediaUrl(value) {
    try {
      const u = new URL(value);
      return u.protocol === 'https:' && u.hostname === 'stream.fyptt.to' && !u.port && !u.username && !u.password && !u.hash
        && /\.(mp4|m3u8)$/i.test(u.pathname) ? u.href : null;
    } catch (_) { return null; }
  },
  async videos(id) {
    const {doc} = await this.detailDocument(id);
    let embed;
    for (const node of doc.querySelectorAll('iframe[src]')) {
      const u = new URL(node.getAttribute('src'), this.BASE);
      if (this.siteUrl(u) && ['/fypttstr.php', '/fypttjwstrhls.php'].includes(u.pathname)) { embed = u.href; break; }
    }
    if (!embed) throw Park.error('UNSUPPORTED', '此影片暂无可用播放地址');
    const {doc: player} = await this.document(embed), videos = [];
    for (const s of player.querySelectorAll('video source[src], video-js source[src]')) {
      const url = this.mediaUrl(s.getAttribute('src'));
      if (url && !videos.some(v => v.url === url)) videos.push({url, quality: 0, label: '原画',
        format: /\.m3u8$/i.test(new URL(url).pathname) ? 'hls' : 'mp4', headers: {Referer: embed}});
    }
    if (!videos.length) throw Park.error('UNSUPPORTED', '此影片暂无可用播放地址');
    videos[0].preferred = true;
    return videos;
  },
});

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"}]});
