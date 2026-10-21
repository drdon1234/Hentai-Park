/* 静态解码已验证的媒体元素百分号字符串，不执行远程脚本。 */
Park.register({
  i18n: {
    "zh-Hant": {"成人视频社区，支持推荐、搜索和原画播放": "成人影片社群，支援推薦、搜尋和原畫播放"},
    "ja": {"成人视频社区，支持推荐、搜索和原画播放": "おすすめ・検索・元画質再生に対応した成人向け動画コミュニティ"},
    "ko": {"成人视频社区，支持推荐、搜索和原画播放": "추천, 검색 및 원본 화질 재생을 지원하는 성인 동영상 커뮤니티"},
    "en": {"成人视频社区，支持推荐、搜索和原画播放": "Adult video community with recommendations, search and original-quality playback"},
    "es": {"成人视频社区，支持推荐、搜索和原画播放": "Comunidad de vídeos para adultos con recomendaciones, búsqueda y calidad original"},
    "ru": {"成人视频社区，支持推荐、搜索和原画播放": "Сообщество видео для взрослых с рекомендациями, поиском и оригинальным качеством"},
    "ar": {"成人视频社区，支持推荐、搜索和原画播放": "مجتمع فيديوهات للبالغين مع توصيات وبحث وتشغيل بالجودة الأصلية"},
  },
  key: 'porn91', name: '91porn', version: '0.0.7', type: 'video', category: 'adult', color: '#D81B60',
  description: '成人视频社区，支持推荐、搜索和原画播放', homepage: 'https://91porn.com', domains: ['91porn.com'], language: 'zh',
  network: {mode: 'native', vpnHint: true}, imageHeaders: {Referer: 'https://91porn.com/'},
  media: {mode: 'native', origin: 'https://91porn.com', domains: ['la.btc620.com', '1470423830.rsc.cdn77.org']},
  linkPatterns: ['91porn\\.com/view_video\\.php\\?(?:[^#]*&)?viewkey=([a-zA-Z0-9]{5,64})(?:&|#|$)'],
  idPattern: '^[a-zA-Z0-9]{5,64}$', idExample: '402751768',
  defaultFeed: 'recommend', feeds: [{key: 'recommend', label: '推荐'}, {key: 'categories', label: '分类', options: [{key: 'category', label: '分类', default: 'category=rf&viewtype=basic', dynamic: true, values: []}]}], searchHint: '搜索作品名或标签', BASE: 'https://91porn.com',
  async filterOptions(req) {
    if (req.scope !== 'feed' || req.feed !== 'categories' || req.filter !== 'category') return [];
    const {doc} = await this.getPage(this.BASE + '/v.php?category=rf&viewtype=basic'), seen = new Set(), values = [];
    for (const a of doc.querySelectorAll('.navbar a[href],nav a[href]')) {
      const u = new URL(a.getAttribute('href'), this.BASE), label = Park.html.text(a);
      if (!this.siteUrl(u) || u.pathname !== '/v.php' || !/^(?:ori|hot|top|long|longer|tf|rf|hd|md|mf)$/.test(u.searchParams.get('category') || '') || !label) continue;
      const params = new URLSearchParams({category: u.searchParams.get('category'), viewtype: 'basic'});
      if (u.searchParams.get('m') === '-1') params.set('m', '-1');
      const value = params.toString(); if (!seen.has(value)) {seen.add(value); values.push({value, label});}
    }
    if (!values.length) throw Park.error('PARSE', '未找到分类'); return values;
  },
  validId(id) {
    const value = String(id);
    if (!/^[a-zA-Z0-9]{5,64}$/.test(value)) throw Park.error('NOT_FOUND', '影片编号无效');
    return value;
  },
  siteUrl(u) { return u.protocol === 'https:' && u.hostname === '91porn.com' && !u.port && !u.username && !u.password && !u.hash; },
  pageUrl(value, kind) {
    let u;
    try { u = new URL(value, this.BASE); } catch (_) { throw Park.error('CONFIG', '视频列表地址无效'); }
    if (!this.siteUrl(u) || u.pathname !== (kind === 'feed' ? '/v.php' : '/search_result.php')) throw Park.error('CONFIG', '视频列表地址无效');
    return u.href;
  },
  mediaUrl(value) {
    try {
      const u = new URL(value);
      if (u.protocol !== 'https:' || u.port || u.username || u.password || u.hash || !['la.btc620.com', '1470423830.rsc.cdn77.org'].includes(u.hostname) || !/\.mp4$/i.test(u.pathname)) return null;
      return u.href;
    } catch (_) { return null; }
  },
  async getPage(url) {
    const r = await this.http.get(url, {timeout: 30000});
    if (r.status === 404) throw Park.error('NOT_FOUND', '影片不存在');
    if (!r.ok) throw Park.error('HTTP', '成人视频请求失败');
    if (!this.siteUrl(new URL(r.url || url))) throw Park.error('BLOCKED', '站点需要在浏览器中确认后访问');
    if (r.body.length > 4 * 1024 * 1024) throw Park.error('PARSE', '影片页面过大');
    const doc = Park.html.parse(r.body);
    if (/at least 18 years/.test(r.body) && !doc.querySelector('a[href*="view_video.php"], #videodetails')) throw Park.error('BLOCKED', '站点需要在浏览器中确认后访问');
    return {html: r.body, doc, url: r.url || url};
  },
  cards(doc) {
    const items = [], seen = new Set();
    for (const c of doc.querySelectorAll('.well')) {
      const a = c.querySelector('a[href*="view_video.php"]'), img = c.querySelector('img');
      const m = a && /(?:\?|&)viewkey=([a-zA-Z0-9]{5,64})(?:&|$)/.exec(a.getAttribute('href') || '');
      const title = Park.html.text(c.querySelector('.video-title')) || img?.getAttribute('title') || img?.getAttribute('alt') || Park.html.text(a), cover = img && (img.getAttribute('data-src') || img.getAttribute('src'));
      // 插入的推广卡会复用真实影片链接，但封面属于另一影片；必须在去重前排除。
      const videoId = /playvthumb_(\d+)/.exec(c.querySelector('[id^="playvthumb_"]')?.getAttribute('id') || '')?.[1];
      const coverId = /\/thumb\/(\d+)\./.exec(cover || '')?.[1];
      if (videoId && coverId && videoId !== coverId) continue;
      if (!m || !title || !/^https:\/\//.test(cover || '') || seen.has(m[1])) continue;
      seen.add(m[1]); items.push({id: m[1], title, cover, coverAspect: 16/9, duration: Park.html.text(c.querySelector('.duration'))});
    }
    return items;
  },
  async listing(url, req, kind) {
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    if (req.cursor && kind === 'feed') {
      const a = new URL(url), b = new URL(this.pageUrl(req.cursor, kind));
      for (const key of ['category', 'm']) if (a.searchParams.get(key) !== b.searchParams.get(key)) throw Park.error('CONFIG', '分页链接无效');
    }
    url = this.pageUrl(req.cursor || url, kind);
    if (!req.cursor && page > 1) { const u = new URL(url); u.searchParams.set('page', page); url = u.href; }
    const {doc, url: finalUrl} = await this.getPage(url);
    let cursor;
    for (const a of doc.querySelectorAll('a[href]')) {
      const u = new URL(a.getAttribute('href'), finalUrl);
      if (this.siteUrl(u) && u.pathname === new URL(url).pathname && Number(u.searchParams.get('page')) === page + 1) { cursor = this.pageUrl(u.href, kind); break; }
    }
    return {items: this.cards(doc), page, hasNext: !!cursor, cursor};
  },
  async feed(key, req) {
    if (key === 'categories') {
      const value = String(req.options?.category || 'category=rf&viewtype=basic');
      if (!/^category=(?:ori|hot|top|long|longer|tf|rf|hd|md|mf)&viewtype=basic(?:&m=-1)?$/.test(value)) throw Park.error('CONFIG', '分类无效');
      return this.listing(this.BASE + '/v.php?' + value, req, 'feed');
    }
    if (key !== 'recommend') throw Park.error('CONFIG', '未知视频列表');
    return this.listing(this.BASE + '/v.php?category=rf&viewtype=basic', req, 'feed');
  },
  async search(req) {
    const keyword = String(req.keyword || '').trim();
    if (!keyword) return {items: [], page: 1, hasNext: false};
    return this.listing(this.BASE + '/search_result.php?search_type=search_videos&search_id=' + encodeURIComponent(keyword), req, 'search');
  },
  async detail(id) {
    id = this.validId(id);
    const url = this.BASE + '/view_video.php?viewkey=' + id, {doc} = await this.getPage(url);
    const title = Park.html.text(doc.querySelector('#videodetails > h4')), cover = doc.querySelector('video[poster]')?.getAttribute('poster');
    if (!title || !cover) throw Park.error('PARSE', '成人视频详情解析失败');
    return {id, title, cover, coverAspect: 16/9, url, description: Park.html.text(doc.querySelector('#v_desc')),
      authors: [Park.html.text(doc.querySelector('#videodetails-content a[href*="UID="] .title'))].filter(Boolean),
      tags: [], related: this.cards(doc).filter(i => i.id !== id)};
  },
  async videos(id) {
    const referer = this.BASE + '/view_video.php?viewkey=' + this.validId(id), {html} = await this.getPage(referer);
    const block = /document\.write\(\s*strencode2\(\s*["']((?:%[0-9a-f]{2})+)["']\s*\)\s*\)/i.exec(html);
    if (!block || block[1].length > 16384) throw Park.error('UNSUPPORTED', '此影片没有可用的 MP4 清晰度');
    const doc = Park.html.parse(block[1].replace(/%([0-9a-f]{2})/gi, (_, hex) => String.fromCharCode(parseInt(hex, 16))));
    const url = this.mediaUrl(doc.querySelector('source[src]')?.getAttribute('src'));
    if (!url) throw Park.error('UNSUPPORTED', '此影片没有可用的 MP4 清晰度');
    return [{quality: 0, label: '原画', url, preferred: true, headers: {Referer: referer}}];
  },
});

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"}]});
