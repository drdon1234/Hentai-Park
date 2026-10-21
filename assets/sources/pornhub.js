/* 从页面 JSON 与官方 MP4 元数据提取播放地址。 */
Park.register({
  i18n: {
    "zh-Hant": {"成人视频播放数据解析失败": "成人影片播放資料解析失敗", "综合成人视频，支持推荐、搜索和多清晰度播放": "綜合成人影片，支援推薦、搜尋和多畫質播放"},
    "ja": {"成人视频播放数据解析失败": "成人向け動画の再生データを解析できませんでした", "综合成人视频，支持推荐、搜索和多清晰度播放": "おすすめ・検索・複数画質再生に対応した成人向け動画"},
    "ko": {"成人视频播放数据解析失败": "성인 동영상 재생 데이터를 분석하지 못했습니다", "综合成人视频，支持推荐、搜索和多清晰度播放": "추천, 검색 및 다양한 화질 재생을 지원하는 성인 동영상"},
    "en": {"成人视频播放数据解析失败": "Could not parse adult video playback data", "综合成人视频，支持推荐、搜索和多清晰度播放": "Adult videos with recommendations, search and multiple playback qualities"},
    "es": {"成人视频播放数据解析失败": "No se pudieron analizar los datos de reproducción del vídeo para adultos", "综合成人视频，支持推荐、搜索和多清晰度播放": "Vídeos para adultos con recomendaciones, búsqueda y varias calidades"},
    "ru": {"成人视频播放数据解析失败": "Не удалось разобрать данные воспроизведения видео для взрослых", "综合成人视频，支持推荐、搜索和多清晰度播放": "Видео для взрослых с рекомендациями, поиском и выбором качества"},
    "ar": {"成人视频播放数据解析失败": "تعذر تحليل بيانات تشغيل الفيديو للبالغين", "综合成人视频，支持推荐、搜索和多清晰度播放": "فيديوهات للبالغين مع توصيات وبحث وخيارات جودة متعددة"},
  },
  key: 'pornhub', name: 'Pornhub', version: '0.0.8', type: 'video', category: 'adult',
  color: '#FF9900', description: '综合成人视频，支持推荐、搜索和多清晰度播放',
  homepage: 'https://www.pornhub.com', domains: ['pornhub.com'], language: 'en',
  network: {mode: 'auto', origin: 'https://www.pornhub.com', vpnHint: true},
  imageHeaders: {Referer: 'https://www.pornhub.com/'},
  media: {mode: 'native', origin: 'https://www.pornhub.com', domains: ['phncdn.com']},
  linkPatterns: ['pornhub\\.com/view_video\\.php\\?(?:[^#]*&)?viewkey=([a-z0-9]{5,64})(?:&|#|$)'],
  idPattern: '^[a-z0-9]{5,64}$', idExample: '6aa2dcb8c56d1',
  defaultFeed: 'recommend', feeds: [
    {key: 'recommend', label: '推荐'},
    {key: 'categories', label: '分类', options: [{key: 'category', label: '分类', type: 'select', default: '', dynamic: true, values: []}]},
  ], searchHint: '搜索作品名或标签',
  settings: [{key: 'quality', type: 'select', label: '默认清晰度', default: '1080', options: [
    {value: '1080', label: '1080P'}, {value: '720', label: '720P'}, {value: '480', label: '480P'}, {value: '240', label: '240P'}]}],
  BASE: 'https://www.pornhub.com',
  validId(id) {
    const value = String(id);
    if (!/^[a-z0-9]{5,64}$/.test(value)) throw Park.error('NOT_FOUND', '影片编号无效');
    return value;
  },
  siteUrl(value) { return !!Park.url.site(this, value); },
  pageUrl(value, kind) {
    let u;
    try { u = new URL(value, this.BASE); } catch (_) { throw Park.error('CONFIG', '视频列表地址无效'); }
    const allowed = kind === 'feed' ? u.pathname === '/recommended' :
      u.pathname === '/video/search' || (u.pathname === '/video' && /^\d{1,6}$/.test(u.searchParams.get('c') || '')) || /^\/categories\/[a-z0-9_-]+\/?$/i.test(u.pathname);
    if (!this.siteUrl(u) || !allowed) throw Park.error('CONFIG', '视频列表地址无效');
    return u.href;
  },
  mediaUrl(value) { return Park.url.parse(value, this.BASE, this.media.domains)?.href || ''; },
  async getPage(url, headers = {}) {
    const r = await this.http.get(url, {headers, timeout: 30000});
    if (r.status === 404) throw Park.error('NOT_FOUND', '影片不存在');
    if (!r.ok) throw Park.error('HTTP', '成人视频请求失败', {status: r.status, url: r.url || url});
    const finalUrl = Park.url.response(this, r, url);
    if (r.body.length > 4 * 1024 * 1024) throw Park.error('PARSE', '影片页面过大');
    return {html: r.body, doc: Park.html.parse(r.body), url: finalUrl.href};
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
    if (key === 'categories') {
      const category = String(req.options?.category || '');
      if (!category) return this.listing(this.BASE + '/recommended', req, 'feed');
      if (!/^\/categories\/[a-z0-9_-]+$/.test(category) && !/^\/video\?c=\d{1,6}$/.test(category)) throw Park.error('CONFIG', '视频分类无效');
      return this.listing(this.BASE + category, req, 'search');
    }
    if (key !== 'recommend') throw Park.error('CONFIG', '未知视频列表');
    return this.listing(this.BASE + '/recommended', req, 'feed');
  },
  async filterOptions(request) {
    if (request.scope !== 'feed' || request.feed !== 'categories' || request.filter !== 'category') return [];
    const {doc} = await this.getPage(this.BASE + '/categories');
    const options = [{value: '', label: '全部'}], seen = new Set();
    for (const link of doc.querySelectorAll('a[href]')) {
      const href = link.getAttribute('href') || '';
      if (!/^\/categories\/[a-z0-9_-]+$/.test(href) && !/^\/video\?c=\d{1,6}$/.test(href)) continue;
      const label = Park.html.text(link).replace(/\s+[\d,]+\s+Videos?\s*$/i, '').trim();
      if (!label || seen.has(href)) continue;
      seen.add(href);
      options.push({value: href, label});
      if (options.length > 500) throw Park.error('PARSE', '分类列表解析失败');
    }
    if (options.length === 1) throw Park.error('PARSE', '未找到视频分类');
    return options;
  },
  async search(req) {
    const keyword = String(req.keyword || '').trim();
    if (!keyword) return {items: [], page: 1, hasNext: false};
    return this.listing(this.BASE + '/video/search?search=' + encodeURIComponent(keyword), req, 'search');
  },
  async detail(id) {
    id = this.validId(id);
    const {doc, url} = await this.getPage(this.BASE + '/view_video.php?viewkey=' + id);
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
    const path = '/view_video.php?viewkey=' + this.validId(id), {html, url: referer} = await this.getPage(this.BASE + path);
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
