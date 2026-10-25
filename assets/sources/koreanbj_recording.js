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
  key: 'koreanbj_recording', name: 'KoreanBJ.club 录播', version: '0.0.6', minAppVersion: '0.9.2', type: 'video', category: 'recording',
  color: '#8d2738', description: '韩国主播录播，支持热门、分页、搜索与原生播放', language: 'ko',
  homepage: 'https://ww1.koreanbj.club/', domains: ['koreanbj.club'],
  network: {mode: 'auto', vpnHint: true},
  media: {mode: 'native', scope: 'session', origin: 'https://ww1.koreanbj.club', domains: ['kbj.31cek.xyz', 'onlyfanleaks.me'],
    referrerDomains: ['io12379storege.xyz']},
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
  async comments(value, req = {}) {
    const id = this.validId(value), page = Math.max(1, Math.floor(Number(req.page) || 1));
    if (req.sort && req.sort !== 'default') throw Park.error('UNSUPPORTED', '评论暂不支持此操作');
    if (page > 1) return {items: [], page, hasNext: false};
    const url = this.BASE + '/video/' + id + '/', doc = this.document(await this.text('/video/' + id + '/'));
    const area = doc.querySelector('#comments');
    if (!area) throw Park.error('PARSE', '评论数据无效');
    const items = [], map = new Map();
    for (const row of area.querySelectorAll('li.comment[id]')) {
      // 只取当前 article，不能读取包含 children 的 li.textContent。
      const id = /^comment-(\d+)$/.exec(row.id)?.[1], article = [...row.children].find(n => n.tagName === 'ARTICLE');
      const body = Park.comments.html(article?.querySelector('.comment-content')?.innerHTML || '', url);
      if (!id || !body.length || map.has(id)) continue;
      const author = article.querySelector('.fn'), parentId = row.parentElement?.closest('li.comment[id]')?.id.replace(/^comment-/, '');
      const item = {id, parentId, author: {name: Park.html.text(author), url: Park.comments.url(author?.querySelector('a')?.getAttribute('href'), url),
        avatar: Park.comments.url(article.querySelector('.avatar')?.getAttribute('src'), url)}, body, date: article.querySelector('time')?.getAttribute('datetime'), replies: []};
      map.set(id, item);
    }
    for (const item of map.values()) { const parent = map.get(item.parentId); if (parent) parent.replies.push(item); else items.push(item); }
    for (const item of map.values()) {item.replyCount = item.replies.length; item.repliesAvailable = item.replies.length > 0;}
    if (!items.length) throw Park.error('PARSE', '评论数据无效');
    return {items: req.parentId ? map.get(String(req.parentId))?.replies || [] : items, page, hasNext: false};
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
    // 部分录播直接嵌入 MP4 播放器。
    for (const source of detail.querySelectorAll('video#player source[src]')) {
      let media;
      try { media = new URL(source.getAttribute('src')); } catch (_) { continue; }
      if (media.protocol === 'https:' && !media.username && !media.password && !media.port && !media.hash &&
          Park.url.parse(media.href, detailUrl, [media.hostname]) && /^\/videos\/[0-9]+\.mp4$/i.test(media.pathname)) {
        return [{url: media.href, format: 'mp4', label: '原画', preferred: true, headers: {Referer: detailUrl}}];
      }
    }
    let embed;
    // 播放器 iframe 可能在点击后才由脚本插入，此时地址只出现在结构化数据中。
    const embeds = [
      ...[...detail.querySelectorAll('iframe[src]')].map(node => node.getAttribute('src')),
      ...[...detail.querySelectorAll('meta[itemprop="contentURL"]')].map(node => node.getAttribute('content')),
    ];
    for (const value of embeds) {
      let candidate;
      try { candidate = new URL(value, this.BASE + '/'); } catch (_) { continue; }
      if (candidate.protocol === 'https:' && !candidate.username && !candidate.password && !candidate.port && !candidate.hash &&
          ((candidate.hostname === 'ww1.koreanbj.club' && candidate.pathname === '/embed/player-6w.php' && candidate.searchParams.has('token')) ||
            (candidate.pathname === '/embed/kbj.php' && candidate.searchParams.has('url') && Park.url.parse(candidate.href, detailUrl, [candidate.hostname])))) {
        embed = candidate;
        break;
      }
    }
    if (!embed) {
      for (const script of detail.querySelectorAll('script:not([src])')) {
        // 只读取站点点击处理器声明的地址，不执行页面脚本。
        const match = String(script.textContent || '').match(/\.setAttribute\(\s*['"]src['"]\s*,\s*['"](https:\/\/io12379storege\.xyz\/e\/[a-z0-9]+\/)['"]\s*\)/);
        if (match) { embed = new URL(match[1]); break; }
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
    if (embed.hostname === 'io12379storege.xyz') {
      let config;
      try {
        const envelope = JSON.parse(player.querySelector('script[type="application/json"]')?.textContent || '');
        if (!Array.isArray(envelope) || envelope.length !== 1 || typeof envelope[0] !== 'string' || envelope[0].length > 128 * 1024) throw new Error();
        const encoded = envelope[0].replace(/[a-zA-Z]/g, char =>
          String.fromCharCode(char.charCodeAt(0) + (char.toLowerCase() <= 'm' ? 13 : -13)))
          .replace(/@\$|\^\^|~@|%\?|\*~|!!|#&/g, '');
        const shifted = Array.from(atob(encoded), char =>
          String.fromCharCode(char.charCodeAt(0) - 3)).reverse().join('');
        config = JSON.parse(atob(shifted));
      } catch (_) { throw Park.error('PARSE', '录播数据无效'); }
      let media;
      try { media = new URL(config.source); } catch (_) { throw Park.error('PARSE', '录播数据无效'); }
      if (media.protocol !== 'https:' || media.username || media.password || media.port || media.hash ||
          !Park.url.parse(media.href, embed.href, [media.hostname]) || !/\.m3u8$/i.test(media.pathname)) {
        throw Park.error('UNSUPPORTED', '录播暂无可用播放地址');
      }
      return [{url: media.href, format: 'hls', label: '原画', preferred: true,
        headers: {Referer: embed.href}}];
    }
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
    // 直链与清单 CDN 会更换主机，按会话授权，只按路径识别。
    if (/^\/self\/data\/[A-Za-z0-9_-]+\.mp4$/i.test(media.pathname)) {
      return [{url: media.href, format: 'mp4', label: '原画', preferred: true,
        headers: {Referer: detailUrl}}];
    }
    if (!/\.(?:m3u8|txt)$/i.test(media.pathname)) {
      throw Park.error('UNSUPPORTED', '录播暂无可用播放地址');
    }
    // CDN 主机会轮换；清单与伪装扩展名的 TS 分片按本次会话授权，不扩大站点 Cookie 权限。
    return [{url: media.href, format: 'hls', label: '原画', preferred: true,
      headers: {Referer: detailUrl}}];
  },
});
