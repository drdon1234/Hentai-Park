Park.register({
  i18n: {
    'zh-Hant': {
      '韩国主播录播，支持热门、分页、搜索与原生播放': '韓國主播錄播，支援熱門、分頁、搜尋與原生播放', '录播暂无可用播放地址': '錄播暫無可用播放位址',
      'KoreanBJ.club 录播': 'KoreanBJ.club 錄播', '热门': '熱門', '最新': '最新',
      '录播请求失败': '錄播請求失敗', '录播数据无效': '錄播資料無效', '录播不存在': '錄播不存在',
    },
    ja: {
      '韩国主播录播，支持热门、分页、搜索与原生播放': '韓国配信者の録画。人気・ページ送り・検索・ネイティブ再生に対応', '录播暂无可用播放地址': '再生可能な録画がありません',
      'KoreanBJ.club 录播': 'KoreanBJ.club 録画', '热门': '人気', '最新': '最新',
      '录播请求失败': '録画の取得に失敗しました', '录播数据无效': '録画データが無効です', '录播不存在': '録画が見つかりません',
    },
    ko: {
      '韩国主播录播，支持热门、分页、搜索与原生播放': '한국 BJ 다시보기 인기 목록, 페이지 이동, 검색 및 네이티브 재생 지원', '录播暂无可用播放地址': '재생 가능한 다시보기가 없습니다',
      'KoreanBJ.club 录播': 'KoreanBJ.club 다시보기', '热门': '인기', '最新': '최신',
      '录播请求失败': '다시보기 요청에 실패했습니다', '录播数据无效': '다시보기 데이터가 올바르지 않습니다', '录播不存在': '다시보기를 찾을 수 없습니다',
    },
    en: {
      '韩国主播录播，支持热门、分页、搜索与原生播放': 'Korean creator recordings with popular feeds, pagination, search and native playback', '录播暂无可用播放地址': 'No playable recording is available',
      'KoreanBJ.club 录播': 'KoreanBJ.club Recordings', '热门': 'Popular', '最新': 'Latest',
      '录播请求失败': 'Recording request failed', '录播数据无效': 'Invalid recording data', '录播不存在': 'Recording not found',
    },
    es: {
      '韩国主播录播，支持热门、分页、搜索与原生播放': 'Grabaciones de creadores coreanos con populares, páginas, búsqueda y reproducción nativa', '录播暂无可用播放地址': 'No hay una grabación reproducible',
      'KoreanBJ.club 录播': 'Grabaciones de KoreanBJ.club', '热门': 'Popular', '最新': 'Más recientes',
      '录播请求失败': 'Error al solicitar la grabación', '录播数据无效': 'Datos de grabación no válidos', '录播不存在': 'Grabación no encontrada',
    },
    ru: {
      '韩国主播录播，支持热门、分页、搜索与原生播放': 'Записи корейских авторов: популярное, страницы, поиск и встроенное воспроизведение', '录播暂无可用播放地址': 'Нет доступной записи для воспроизведения',
      'KoreanBJ.club 录播': 'Записи KoreanBJ.club', '热门': 'Популярные', '最新': 'Новые',
      '录播请求失败': 'Ошибка запроса записи', '录播数据无效': 'Некорректные данные записи', '录播不存在': 'Запись не найдена',
    },
    ar: {
      '韩国主播录播，支持热门、分页、搜索与原生播放': 'تسجيلات منشئي المحتوى الكوريين مع قوائم شائعة وصفحات وبحث وتشغيل أصلي', '录播暂无可用播放地址': 'لا يوجد تسجيل متاح للتشغيل',
      'KoreanBJ.club 录播': 'تسجيلات KoreanBJ.club', '热门': 'الأكثر شعبية', '最新': 'الأحدث',
      '录播请求失败': 'فشل طلب التسجيل', '录播数据无效': 'بيانات التسجيل غير صالحة', '录播不存在': 'التسجيل غير موجود',
    },
  },
  key: 'koreanbj_recording', name: 'KoreanBJ.club 录播', version: '0.0.2', type: 'video', category: 'recording',
  color: '#8d2738', description: '韩国主播录播，支持热门、分页、搜索与原生播放', language: 'ko',
  homepage: 'https://ww1.koreanbj.club/', domains: ['koreanbj.club'],
  network: {mode: 'auto', vpnHint: true},
  media: {mode: 'native', scope: 'session', origin: 'https://ww1.koreanbj.club', domains: ['kbj.31cek.xyz']},
  imageHeaders: {Referer: 'https://ww1.koreanbj.club/'},
  idPattern: '^[A-Za-z0-9%._~-]{1,220}$',
  linkPatterns: ['koreanbj\\.club/video/([^/?#]+)'],
  defaultFeed: 'popular', feeds: [
    {key: 'popular', label: '热门'},
    {key: 'latest', label: '最新'},
  ],
  BASE: 'https://ww1.koreanbj.club',
  validId(value) {
    const id = String(value || '');
    if (!/^[A-Za-z0-9%._~-]{1,220}$/.test(id)) throw Park.error('NOT_FOUND', '录播不存在');
    return id;
  },
  safeSiteUrl(value) {
    try {
      const url = new URL(value, this.BASE + '/');
      if (url.protocol !== 'https:' || url.username || url.password || url.port ||
          !/(^|\.)koreanbj\.club$/i.test(url.hostname)) return null;
      return url;
    } catch (_) { return null; }
  },
  async text(path) {
    const response = await this.http.get(this.BASE + path, {timeout: 20000, headers: {
      'User-Agent': 'Mozilla/5.0', Referer: this.BASE + '/',
    }});
    if (!response.ok) throw Park.error('HTTP', '录播请求失败', {status: response.status});
    if (!response.body || response.body.length > 4 * 1024 * 1024) throw Park.error('PARSE', '录播数据无效');
    return response.body;
  },
  document(html) { return Park.html.parse(html); },
  card(article) {
    const anchor = article?.querySelector('a[href*="/video/"]');
    const image = article?.querySelector('.post-thumbnail img');
    if (!anchor || !image) return null;
    const url = this.safeSiteUrl(anchor.getAttribute('href'));
    const cover = this.safeSiteUrl(image.getAttribute('data-src') || image.getAttribute('data-original') || image.getAttribute('src'));
    const match = url?.pathname.match(/^\/video\/([^/]+)\/?$/);
    const title = String(anchor.getAttribute('title') || article.querySelector('.entry-header')?.textContent || '').trim();
    if (!url || !cover || !match || !title || /placeholder\.png$/i.test(cover.pathname)) return null;
    const duration = String(article.querySelector('.duration')?.textContent || '').trim();
    const viewsText = String(article.querySelector('.views')?.textContent || '').replace(/[^\d]/g, '');
    const views = viewsText ? Number(viewsText) : undefined;
    return {
      id: match[1], title, cover: cover.href, coverAspect: 16 / 9,
      url: url.href, mediaKind: 'video',
      ...(duration ? {duration} : {}), ...(Number.isFinite(views) ? {views} : {}),
    };
  },
  pagePath(path, page) {
    if (page <= 1) return path;
    const url = new URL(path, this.BASE + '/');
    url.pathname = url.pathname.replace(/\/$/, '') + '/page/' + page + '/';
    return url.pathname + url.search;
  },
  async list(path, page) {
    const doc = this.document(await this.text(this.pagePath(path, page)));
    const items = [...doc.querySelectorAll('article.loop-video')].map(article => this.card(article)).filter(Boolean);
    const sitePage = doc.querySelector('#searchform, .videos-list, article.loop-video') &&
      /korean\s*bj/i.test(String(doc.querySelector('title')?.textContent || ''));
    if (!sitePage || (!items.length && page === 1)) throw Park.error('PARSE', '录播数据无效');
    const hasNext = !!doc.querySelector('link[rel="next"], .pagination a.next, a.next.page-numbers');
    return {items, page, hasNext: hasNext && items.length > 0};
  },
  async feed(key, req = {}) {
    if (!this.feeds.some(feed => feed.key === key)) throw Park.error('CONFIG', '录播数据无效');
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    const path = key === 'popular' ? '/?filter=most-viewed' : '/?filter=latest';
    return this.list(path, page);
  },
  async search(req = {}) {
    const keyword = String(req.keyword || '').trim().slice(0, 80);
    if (!keyword) return {items: [], page: 1, hasNext: false};
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    const params = new URLSearchParams({s: keyword});
    if (page > 1) params.set('paged', String(page));
    return this.list('/?' + params.toString(), page);
  },
  async detail(value, preview) {
    const id = this.validId(value);
    const url = this.BASE + '/video/' + id + '/';
    const doc = this.document(await this.text('/video/' + id + '/'));
    const title = String(doc.querySelector('h1')?.textContent || preview?.title || '').trim();
    let cover = this.safeSiteUrl(doc.querySelector('meta[property="og:image"]')?.getAttribute('content') || preview?.cover);
    if (!title || !cover) throw Park.error('NOT_FOUND', '录播不存在');
    const duration = String(doc.querySelector('[itemprop="duration"]')?.getAttribute('content') || preview?.duration || '').trim();
    const tags = [...doc.querySelectorAll('.tags-list a')]
      .map(node => String(node.textContent || '').trim()).filter(Boolean)
      .map(name => ({name, keyword: name}));
    return {
      id, title, url, cover: cover.href, coverAspect: 16 / 9, mediaKind: 'video', chapters: null,
      ...(duration ? {duration} : {}),
      ...(tags.length ? {tags: [{namespace: 'tag', label: '标签', tags}]} : {}),
    };
  },
  async videos(value) {
    const id = this.validId(value);
    const detailUrl = this.BASE + '/video/' + id + '/';
    const detail = this.document(await this.text('/video/' + id + '/'));
    let embed;
    for (const iframe of detail.querySelectorAll('iframe[src]')) {
      let candidate;
      try { candidate = new URL(iframe.getAttribute('src'), this.BASE + '/'); } catch (_) { continue; }
      if (candidate.protocol === 'https:' && !candidate.username && !candidate.password && !candidate.port && !candidate.hash &&
          ((candidate.hostname === 'ww1.koreanbj.club' && candidate.pathname === '/embed/player-6w.php' && candidate.searchParams.has('token')) ||
            (candidate.hostname === '31cek.xyz' && candidate.pathname === '/embed/kbj.php' && candidate.searchParams.has('url')))) {
        embed = candidate;
        break;
      }
    }
    if (!embed) {
      throw Park.error('UNSUPPORTED', '录播暂无可用播放地址');
    }
    const response = await this.http.get(embed.href, {timeout: 20000, headers: {
      'User-Agent': 'Mozilla/5.0', Referer: detailUrl,
    }});
    if (!response.ok || !response.body || response.body.length > 1024 * 1024) {
      throw Park.error('HTTP', '录播请求失败', {status: response.status});
    }
    const player = this.document(response.body);
    const scripts = [...player.querySelectorAll('script:not([src])')]
      .map(node => String(node.textContent || ''))
      .filter(script => /jwplayer\s*\(\s*["']player["']\s*\)\s*\.\s*setup\s*\(/.test(script)).join('\n');
    const fileMatch = scripts.match(/\bfile\s*:\s*["']((?:https?:\\?\/\\?\/)[^"']+)["']/i);
    if (!fileMatch) throw Park.error('UNSUPPORTED', '录播暂无可用播放地址');
    const mediaText = fileMatch[1].replace(/\\\//g, '/');
    let media;
    try { media = new URL(mediaText); } catch (_) { throw Park.error('PARSE', '录播数据无效'); }
    if (media.protocol !== 'https:' || media.username || media.password || media.port || media.hash) {
      throw Park.error('UNSUPPORTED', '录播暂无可用播放地址');
    }
    if (media.hostname === 'kbj.31cek.xyz' && /^\/self\/data\/[A-Za-z0-9_-]+\.mp4$/i.test(media.pathname)) {
      return [{url: media.href, format: 'mp4', label: '原画', preferred: true,
        headers: {Referer: detailUrl}}];
    }
    if (!/(^|\.)bestmovietrailers\.cyou$/i.test(media.hostname) || !/\.(?:m3u8|txt)$/i.test(media.pathname)) {
      throw Park.error('UNSUPPORTED', '录播暂无可用播放地址');
    }
    // CDN 清单与伪装扩展名的 TS 分片由共享 HLS 会话解析，不扩大站点 Cookie 权限。
    return [{url: media.href, format: 'hls', label: '原画', preferred: true,
      headers: {Referer: detailUrl}}];
  },
});
