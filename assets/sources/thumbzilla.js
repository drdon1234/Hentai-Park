/* 静态 JSON 提取同站 MP4 元数据，不执行播放器脚本。 */
Park.register({
  i18n: {
    "zh-Hant": {"成人视频，支持热门、搜索和多清晰度 MP4 播放": "成人影片，支援熱門、搜尋與多畫質 MP4 播放"},
    "ja": {"成人视频，支持热门、搜索和多清晰度 MP4 播放": "成人動画。人気一覧、検索、複数画質の MP4 再生に対応"},
    "ko": {"成人视频，支持热门、搜索和多清晰度 MP4 播放": "인기 목록, 검색 및 여러 화질의 MP4 재생을 지원하는 성인 동영상"},
    "en": {"成人视频，支持热门、搜索和多清晰度 MP4 播放": "Adult videos with popular lists, search and multi-quality MP4 playback"},
    "es": {"成人视频，支持热门、搜索和多清晰度 MP4 播放": "Vídeos para adultos con listas populares, búsqueda y reproducción MP4 en varias calidades"},
    "ru": {"成人视频，支持热门、搜索和多清晰度 MP4 播放": "Видео для взрослых: популярное, поиск и MP4 в разных качествах"},
    "ar": {"成人视频，支持热门、搜索和多清晰度 MP4 播放": "فيديوهات البالغين مع قوائم شائعة وبحث وتشغيل MP4 بجودات متعددة"},
  },
  key: 'thumbzilla', name: 'Thumbzilla', version: '0.0.7', type: 'video', category: 'adult', color: '#FF9900',
  description: '成人视频，支持热门、搜索和多清晰度 MP4 播放', homepage: 'https://www.thumbzilla.com',
  domains: ['thumbzilla.com'], language: 'en',
  network: {mode: 'auto', origin: 'https://www.thumbzilla.com', vpnHint: true}, imageHeaders: {Referer: 'https://www.thumbzilla.com/'},
  media: {mode: 'native', origin: 'https://www.thumbzilla.com', domains: ['ypncdn.com']},
  linkPatterns: ['thumbzilla\\.com/watch/(\\d+)/'], idPattern: '^\\d{1,15}$',
  defaultFeed: 'popular', feeds: [
    {key: 'popular', label: '热门'},
    {key: 'categories', label: '分类', options: [{key: 'category', label: '分类', type: 'select', default: '', dynamic: true, values: []}]},
  ], searchHint: '搜索作品名或标签',
  BASE: 'https://www.thumbzilla.com',
  validId(id) {
    if (!/^\d{1,15}$/.test(String(id))) throw Park.error('NOT_FOUND', '影片编号无效');
    return String(id);
  },
  siteUrl(value) { return Park.url.site(this, value); },
  pageUrl(value, kind) {
    const u = this.siteUrl(value), path = kind === 'feed' ? '/most_viewed/' : '/search/';
    if (!u || (kind === 'search' && u.pathname !== path && !/^\/category\/[a-z0-9_-]+\/$/i.test(u.pathname)) ||
        (kind === 'feed' && u.pathname !== path) ||
        (u.searchParams.has('page') && !/^[1-9]\d{0,5}$/.test(u.searchParams.get('page')))) throw Park.error('CONFIG', '视频列表地址无效');
    return u.href;
  },
  async getPage(url) {
    const r = await this.http.get(url, {timeout: 30000});
    if (r.status === 404) throw Park.error('NOT_FOUND', '影片不存在');
    if (!r.ok) throw Park.error('HTTP', '成人视频请求失败');
    const finalUrl = Park.url.response(this, r, url);
    if (r.body.length > 4 * 1024 * 1024) throw Park.error('PARSE', '影片页面过大');
    return {html: r.body, doc: Park.html.parse(r.body), url: finalUrl.href};
  },
  coverUrl(value) { return Park.url.parse(value, this.BASE, ['ypncdn.com', 'phncdn.com'])?.href || ''; },
  cards(doc) {
    const items = [], seen = new Set();
    for (const card of doc.querySelectorAll('article.video-box')) {
      const a = card.querySelector('a[data-testid="plw_video_thumbnail_link"]'), img = a?.querySelector('img');
      const u = a && this.siteUrl(a.getAttribute('href')), match = u && /^\/watch\/(\d{1,15})\/$/.exec(u.pathname);
      const title = Park.html.text(card.querySelector('a.video-title-text')) || card.getAttribute('aria-label');
      const cover = img?.getAttribute('data-src') || img?.getAttribute('src');
      if (!match || !title || !this.coverUrl(cover) || seen.has(match[1])) continue;
      seen.add(match[1]);
      items.push({id: match[1], title, cover, coverAspect: 16/9,
        duration: Park.html.text(card.querySelector('.video-duration')),
        uploader: Park.html.text(card.querySelector('.author-title-text'))});
    }
    return items;
  },
  async listing(url, req, kind) {
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    if (page > 1 && !req.cursor) throw Park.error('CONFIG', '请按顺序加载视频列表');
    const {doc, url: finalUrl} = await this.getPage(this.pageUrl(req.cursor || url, kind));
    let cursor;
    for (const a of doc.querySelectorAll('a[href]')) {
      if (Park.html.text(a) !== String(page + 1)) continue;
      try {
        const next = this.pageUrl(new URL(a.getAttribute('href'), finalUrl).href, kind);
        if (Number(new URL(next).searchParams.get('page')) === page + 1) { cursor = next; break; }
      } catch (_) {}
    }
    return {items: this.cards(doc), page, hasNext: !!cursor, cursor};
  },
  async feed(key, req) {
    if (key === 'categories') {
      const category = String(req.options?.category || '');
      if (!category) return this.listing(this.BASE + '/most_viewed/', req, 'feed');
      if (!/^\/[a-z0-9_-]+$/.test(category)) throw Park.error('CONFIG', '视频分类无效');
      return this.listing(this.BASE + '/category' + category + '/', req, 'search');
    }
    if (key !== 'popular') throw Park.error('CONFIG', '未知视频列表');
    return this.listing(this.BASE + '/most_viewed/', req, 'feed');
  },
  async filterOptions(request) {
    if (request.scope !== 'feed' || request.feed !== 'categories' || request.filter !== 'category') return [];
    const {doc} = await this.getPage(this.BASE + '/categories/');
    const options = [{value: '', label: '全部'}], seen = new Set();
    for (const link of doc.querySelectorAll('a[href^="/category/"]')) {
      const href = link.getAttribute('href'), match = /^\/category\/([a-z0-9_-]+)\/$/i.exec(href || '');
      const label = Park.html.text(link);
      if (!match || !label || seen.has(match[1].toLowerCase())) continue;
      seen.add(match[1].toLowerCase()); options.push({value: '/' + match[1], label});
      if (options.length > 500) throw Park.error('PARSE', '分类列表解析失败');
    }
    if (options.length === 1) throw Park.error('PARSE', '未找到视频分类');
    return options;
  },
  async search(req) {
    const keyword = String(req.keyword || '').trim();
    if (!keyword) return {items: [], page: 1, hasNext: false};
    return this.listing(this.BASE + '/search/?query=' + encodeURIComponent(keyword), req, 'search');
  },
  async detail(id) {
    id = this.validId(id);
    const {doc, url} = await this.getPage(this.BASE + '/watch/' + id + '/');
    const title = doc.querySelector('meta[property="og:title"]')?.getAttribute('content');
    const cover = doc.querySelector('meta[property="og:image"]')?.getAttribute('content');
    if (!title || !this.coverUrl(cover)) throw Park.error('PARSE', '成人视频详情解析失败');
    return {id, title, cover, coverAspect: 16/9, url, tags: [], authors: [],
      related: this.cards(doc).filter(item => item.id !== id)};
  },
  mediaUrl(value) { return Park.url.parse(value, this.BASE, this.media.domains)?.href || ''; },
  async videos(id) {
    const {html, url: referer} = await this.getPage(this.BASE + '/watch/' + this.validId(id) + '/');
    let endpoint;
    for (const match of html.matchAll(/mediaDefinitions?"?\s*:\s*(\[.*?\])/g)) {
      let entries;
      try { entries = JSON.parse(match[1]); } catch (_) { continue; }
      for (const entry of entries) {
        const u = entry.format === 'mp4' && this.siteUrl(entry.videoUrl);
        if (u && u.pathname === '/media/mp4/' && u.searchParams.has('s')) { endpoint = u.href; break; }
      }
      if (endpoint) break;
    }
    if (!endpoint) throw Park.error('UNSUPPORTED', '此影片没有可用的 MP4 清晰度');
    const r = await this.http.get(endpoint, {headers: {Referer: referer}, timeout: 30000});
    if (!r.ok) throw Park.error('HTTP', '成人视频请求失败');
    if (!this.siteUrl(r.url || endpoint) || r.body.length > 128 * 1024) throw Park.error('PARSE', '成人视频详情解析失败');
    let entries;
    try { entries = JSON.parse(r.body); } catch (_) { throw Park.error('PARSE', '成人视频详情解析失败'); }
    if (!Array.isArray(entries)) throw Park.error('PARSE', '成人视频详情解析失败');
    const videos = [], seen = new Set();
    for (const entry of entries) {
      const url = entry.format === 'mp4' && this.mediaUrl(entry.videoUrl), quality = Number(entry.quality);
      if (!url || !Number.isInteger(quality) || quality < 1 || quality > 4320 || seen.has(quality)) continue;
      seen.add(quality); videos.push({quality, label: quality + 'P', url, format: 'mp4', headers: {Referer: referer}});
    }
    videos.sort((a, b) => b.quality - a.quality);
    if (!videos.length) throw Park.error('UNSUPPORTED', '此影片没有可用的 MP4 清晰度');
    videos[0].preferred = true;
    return videos;
  },
});

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"}]});
