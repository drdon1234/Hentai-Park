/* 列表和站内作品页；解析真实播放入口，交给隔离的应用内网页播放器。 */
Park.register({
  i18n: {
    "zh-Hant": {"综合成人视频搜索，支持热门、分页与应用内网页播放": "綜合成人影片搜尋，支援熱門、分頁與應用程式內網頁播放"},
    "ja": {"综合成人视频搜索，支持热门、分页与应用内网页播放": "人気一覧、ページ送り、アプリ内ウェブ再生に対応する成人動画検索"},
    "ko": {"综合成人视频搜索，支持热门、分页与应用内网页播放": "인기 목록, 페이지 탐색 및 앱 내 웹 재생을 지원하는 성인 동영상 검색"},
    "en": {"综合成人视频搜索，支持热门、分页与应用内网页播放": "Adult video search with popular lists, pagination and in-app web playback"},
    "es": {"综合成人视频搜索，支持热门、分页与应用内网页播放": "Búsqueda de vídeos para adultos con listas populares, paginación y reproducción web en la app"},
    "ru": {"综合成人视频搜索，支持热门、分页与应用内网页播放": "Поиск видео для взрослых: популярное, страницы и веб-плеер в приложении"},
    "ar": {"综合成人视频搜索，支持热门、分页与应用内网页播放": "بحث فيديوهات البالغين مع القوائم الشائعة والصفحات وتشغيل الويب داخل التطبيق"},
  },
  key: 'tubesafari', name: 'TubeSafari', version: '0.0.5', type: 'video', category: 'adult', color: '#21B7B5',
  description: '综合成人视频搜索，支持热门、分页与应用内网页播放', homepage: 'https://tubesafari.com', language: 'en',
  domains: ['tubesafari.com', 'xhcdn.com', 'nv7s.com', 'others-cdn.com', 'txxx.tube', 'phncdn.com'],
  network: {mode: 'native', vpnHint: true}, imageHeaders: {Referer: 'https://tubesafari.com/'},
  linkPatterns: ['tubesafari\\.com/video\\?(?:[^#\\s]*&)?id=([a-zA-Z0-9_-]+)(?:[&#]|$)'],
  idPattern: '^([a-zA-Z0-9_-]{1,128})$',
  defaultFeed: 'popular', feeds: [{key: 'popular', label: '热门'}], searchHint: '搜索作品名或标签',
  BASE: 'https://tubesafari.com',
  validId(id) {
    if (!/^[a-zA-Z0-9_-]{1,128}$/.test(String(id))) throw Park.error('NOT_FOUND', '影片编号无效');
    return String(id);
  },
  coverUrl(value) {
    try {
      const u = new URL(value);
      return u.protocol === 'https:' && !u.port && !u.username && !u.password &&
        /^(?:[a-z0-9-]+\.)*(?:xhcdn\.com|nv7s\.com|others-cdn\.com|txxx\.tube|phncdn\.com)$/.test(u.hostname);
    } catch (_) { return false; }
  },
  async getPage(url) {
    const r = await this.http.get(url, {timeout: 30000});
    if (r.status === 404) throw Park.error('NOT_FOUND', '影片不存在');
    if (!r.ok) throw Park.error('HTTP', '成人视频请求失败');
    const final = new URL(r.url || url);
    if (final.origin !== this.BASE || final.username || final.password) throw Park.error('BLOCKED', '站点需要在浏览器中确认后访问');
    if (r.body.length > 4 * 1024 * 1024) throw Park.error('PARSE', '影片页面过大');
    return {body: r.body, doc: Park.html.parse(r.body)};
  },
  cards(doc) {
    const items = [], seen = new Set();
    for (const card of doc.querySelectorAll('.vid_li')) {
      const a = card.querySelector('.video_title a[href]'), img = card.querySelector('img');
      const title = Park.html.text(a), cover = img?.getAttribute('data-src') || img?.getAttribute('src');
      let id;
      try {
        const u = new URL(a?.getAttribute('href'), this.BASE);
        if (u.origin !== this.BASE || u.pathname !== '/video') continue;
        id = this.validId(u.searchParams.get('id') || '');
      } catch (_) { continue; }
      if (!title || !this.coverUrl(cover) || seen.has(id)) continue;
      seen.add(id); items.push({id, title, cover, coverAspect: 16/9,
        duration: Park.html.text(card.querySelector('.video_length')),
        url: this.BASE + '/video?id=' + encodeURIComponent(id)});
    }
    return items;
  },
  async listing(keyword, req, feed = false) {
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    if (!Number.isSafeInteger(page) || page > 100000) throw Park.error('CONFIG', '视频列表地址无效');
    if (page === 1 && !feed) {
      const {doc} = await this.getPage(this.BASE + '/search?query=' + encodeURIComponent(keyword));
      const items = this.cards(doc), hasNext = !!doc.querySelector('.more_videos') && items.length > 0;
      return {items, page, hasNext};
    }
    const params = new URLSearchParams({method: 'search', query: keyword, sort: 'best', page: String(page - 1)});
    const {body} = await this.getPage(this.BASE + '/api?' + params);
    let data;
    try { data = JSON.parse(body); } catch (_) { throw Park.error('PARSE', '成人视频详情解析失败'); }
    if (typeof data.html !== 'string' || !Number.isFinite(Number(data.results_remaining))) throw Park.error('PARSE', '成人视频详情解析失败');
    const items = this.cards(Park.html.parse(data.html));
    return {items, page, hasNext: Number(data.results_remaining) > 0 && items.length > 0};
  },
  async feed(key, req) {
    if (key !== 'popular') throw Park.error('CONFIG', '未知视频列表');
    return this.listing('', req, true);
  },
  async search(req) {
    const keyword = String(req.keyword || '').trim();
    if (!keyword) return {items: [], page: 1, hasNext: false};
    return this.listing(keyword, req);
  },
  async detail(id, preview) {
    id = this.validId(id);
    const url = this.BASE + '/video?id=' + encodeURIComponent(id);
    const item = preview && preview.id === id ? preview : {};
    // 保留列表元数据；播放时重新解析，不用源凭据请求上游。
    const title = typeof item.title === 'string' && item.title ? item.title : id;
    return {id, url, title, cover: this.coverUrl(item.cover) ? item.cover : '', coverAspect: 16/9,
      duration: typeof item.duration === 'string' ? item.duration : '', tags: [], authors: []};
  },
  async webVideo(id) {
    id = this.validId(id);
    const pageUrl = this.BASE + '/video?id=' + encodeURIComponent(id);
    const response = await this.http.get(pageUrl, {timeout: 30000, followRedirects: false});
    if (response.status === 404) throw Park.error('NOT_FOUND', '影片不存在');
    let target;
    if ([301, 302, 303, 307, 308].includes(response.status)) {
      target = Object.entries(response.headers).find(([key]) => key.toLowerCase() === 'location')?.[1];
    } else {
      if (!response.ok) throw Park.error('HTTP', '成人视频请求失败');
      if (response.body.length > 4 * 1024 * 1024) throw Park.error('PARSE', '影片页面过大');
      target = Park.html.parse(response.body).querySelector('iframe#video2[src][allowfullscreen]')?.getAttribute('src');
    }
    if (!target) throw Park.error('PARSE', '播放器地址暂不可用');
    let url;
    try {
      url = new URL(target, this.BASE);
      if (url.protocol !== 'https:' || url.username || url.password || url.port ||
          !/^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,63}$/.test(url.hostname) ||
          /(?:^|\.)(?:localhost|local|internal|test|invalid)$/.test(url.hostname)) {
        throw new Error('unsafe');
      }
    } catch (_) { throw Park.error('PARSE', '播放器地址无效'); }
    // 实测的播放器跨域跳转；不扩大源 HTTP 或 Cookie 权限。
    const redirects = {
      'xh.partners': ['xhamster.com'],
      'xh.video': ['xhamster.com'],
      'videotxxx.com': ['txxx.me'],
    };
    return {url: url.href, navigationDomains: [url.hostname, ...(redirects[url.hostname] || [])]};
  },
});

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"}]});
