/* 聚合索引与已验证上游的原生媒体；不执行外站脚本。 */
Park.register({
  i18n: {
    "zh-Hant": {"站点年龄确认未自动完成，请重试":"網站年齡確認未自動完成，請重試","演员":"演員","综合成人视频搜索，常见来源优先原生播放，其他来源使用网页播放":"綜合成人影片搜尋，常見來源優先原生播放，其他來源使用網頁播放","站点搜索表单无效":"站點搜尋表單無效","高清":"高清","标清":"標清"},
    "ja": {"站点年龄确认未自动完成，请重试":"サイトの年齢確認が自動で完了しませんでした。再試行してください。","演员":"出演者","综合成人视频搜索，常见来源优先原生播放，其他来源使用网页播放":"成人動画検索。対応する主な配信元はネイティブ再生を優先し、その他はウェブ再生","站点搜索表单无效":"サイトの検索フォームが無効です","高清":"高画質","标清":"標準画質"},
    "ko": {"站点年龄确认未自动完成，请重试":"사이트 연령 확인이 자동으로 완료되지 않았습니다. 다시 시도하세요.","演员":"출연자","综合成人视频搜索，常见来源优先原生播放，其他来源使用网页播放":"성인 동영상 검색. 지원되는 주요 출처는 네이티브 재생을 우선하고 나머지는 웹 재생","站点搜索表单无效":"사이트 검색 양식이 잘못되었습니다","高清":"고화질","标清":"표준 화질"},
    "en": {"站点年龄确认未自动完成，请重试":"Automatic age confirmation did not complete. Please try again.","演员":"Performers","综合成人视频搜索，常见来源优先原生播放，其他来源使用网页播放":"Adult video search; native playback for supported popular providers, web playback for others","站点搜索表单无效":"The site's search form is invalid","高清":"High quality","标清":"Standard quality"},
    "es": {"站点年龄确认未自动完成，请重试":"La confirmación automática de edad no se completó. Inténtalo de nuevo.","演员":"Intérpretes","综合成人视频搜索，常见来源优先原生播放，其他来源使用网页播放":"Búsqueda de vídeos para adultos; reproducción nativa de proveedores populares compatibles y web para los demás","站点搜索表单无效":"El formulario de búsqueda del sitio no es válido","高清":"Alta calidad","标清":"Calidad estándar"},
    "ru": {"站点年龄确认未自动完成，请重试":"Автоматическое подтверждение возраста не завершено. Повторите попытку.","演员":"Исполнители","综合成人视频搜索，常见来源优先原生播放，其他来源使用网页播放":"Поиск видео для взрослых: нативное воспроизведение популярных поддерживаемых источников, веб-плеер для остальных","站点搜索表单无效":"Форма поиска на сайте недействительна","高清":"Высокое качество","标清":"Стандартное качество"},
    "ar": {"站点年龄确认未自动完成，请重试":"لم يكتمل تأكيد العمر تلقائيًا. يرجى إعادة المحاولة.","演员":"المؤدون","综合成人视频搜索，常见来源优先原生播放，其他来源使用网页播放":"بحث فيديوهات للبالغين؛ تشغيل أصلي للمصادر الشائعة المدعومة وتشغيل ويب للمصادر الأخرى","站点搜索表单无效":"نموذج البحث في الموقع غير صالح","高清":"جودة عالية","标清":"جودة قياسية"},
  },
  key: 'ixxx', name: 'iXXX', version: '0.0.14', type: 'video', category: 'adult', color: '#F97316',
  description: '综合成人视频搜索，常见来源优先原生播放，其他来源使用网页播放',
  homepage: 'https://www.ixxx.com', domains: ['ixxx.com'], language: 'en',
  media: {mode: 'native', origin: 'https://www.ixxx.com', domains: ['eporner.com', 'xhcdn.com', 'abxxx.com', 'xmilf.com', 'txxx.me', 'pornl.com', 'pornl-ah.nv7s.com', 'porntop.com', 'ptah.m3pd.com', 'ahcdn.com', 'xozilla.xxx', 'pornid.xxx', 'theyarehuge.com', 'inxxx.com', 'dafreeporn.com', 'freeporn8.com', 'xhand.net', 'xhand.com', 'amateur8.com', 'maturetubehere.com', 'sortporn.com', 'lesbian8.com', 'pornone.com', 'ok.xxx', 'cdn.privatehost.com'], referrerDomains: ['abxxx.com', 'xmilf.com', 'txxx.me', 'pornl.com', 'porntop.com', 'xozilla.xxx', 'pornid.xxx', 'theyarehuge.com', 'inxxx.com', 'dafreeporn.com', 'xhand.net', 'amateur8.com', 'maturetubehere.com', 'sortporn.com', 'lesbian8.com', 'ok.xxx']},
  network: {mode: 'browser', origin: 'https://www.ixxx.com', vpnHint: true, confirmation: {
    selector: '#splash-page[open], #age-verification[open], #age-verification:not(dialog)', readySelector: 'a.item-link[href]',
    requiredCookies: ['splashPageAccepted'], auto: {clickSelector: '#splash-page .eighteen-plus-button'},
    message: '站点年龄确认未自动完成，请重试',
  }}, imageHeaders: {Referer: 'https://www.ixxx.com/'},
  defaultFeed: 'ranking', feeds: [{key: 'ranking', label: '排行榜'},
    {key: 'categories', label: '分类', options: [
      {key: 'range', label: '范围', type: 'select', default: '0', dynamic: true, values: []},
      {key: 'category', label: '分类', type: 'select', default: '', dynamic: true, dependsOn: ['range'], values: []}]}], searchHint: '搜索作品名或标签',
  // __CATALOG_START__：由 tools/build_catalog_sources.mjs 生成。
  async categoryDirectory() {
    if (this._categoryDirectory && Date.now() - this._categoryDirectory.time < 120000) return this._categoryDirectory.values;
    const config = {"home":"/rating","leaf":"^/c/[a-zA-Z0-9_%+-]+/?$","index":"^/a-z/?$","pageMethod":"request","absolute":true,"listMethod":"categoryListing","ranges":true}, leaf = new RegExp(config.leaf), index = config.index ? new RegExp(config.index) : null;
    const values = new Map(), indexes = new Set(), origin = new URL(this.BASE).origin;
    const page = path => this[config.pageMethod || 'getPage']((config.absolute ? this.BASE : '') + path);
    const collect = doc => {
      for (const a of doc.querySelectorAll(config.selector || 'a[href]')) {
        let u;
        try { u = new URL(a.getAttribute('href'), this.BASE); } catch (_) { continue; }
        if (u.origin !== origin || u.username || u.password || u.search || u.hash ||
            /%2f|%5c|%2e|%00/i.test(u.pathname)) continue;
        try { if (/[\x00-\x1f\x7f\\]/.test(decodeURIComponent(u.pathname))) continue; } catch (_) { continue; }
        const label = Park.html.text(a).replace(/\s+/g, ' ').trim();
        if (leaf.test(u.pathname) && label && label.length <= 256 && !values.has(u.pathname)) values.set(u.pathname, label);
        else if (index?.test(u.pathname)) indexes.add(u.pathname);
      }
    };
    collect((await page(config.home)).doc);
    for (const path of [...indexes].slice(0, 1)) collect((await page(path)).doc);
    if (!values.size || values.size > (config.ranges ? 10000 : 499)) throw Park.error('PARSE', '分类列表解析失败');
    const rows = [...values].map(([value, label]) => ({value, label}));
    this._categoryDirectory = {time: Date.now(), values: rows};
    return rows;
  },
  async filterOptions(request) {
    const config = {"home":"/rating","leaf":"^/c/[a-zA-Z0-9_%+-]+/?$","index":"^/a-z/?$","pageMethod":"request","absolute":true,"listMethod":"categoryListing","ranges":true};
    const rows = await this.categoryDirectory();
    if (config.ranges && request.filter === 'range') {
      return Array.from({length: Math.ceil(rows.length / 200)}, (_, i) => ({
        value: String(i), label: (i * 200 + 1) + '–' + Math.min((i + 1) * 200, rows.length),
      }));
    }
    if (request.filter !== 'category') throw Park.error('CONFIG', '筛选参数无效');
    let choices = rows;
    if (config.ranges) {
      const range = String(request.values?.range ?? '0');
      if (!/^(?:0|[1-9]\d{0,2})$/.test(range) || Number(range) * 200 >= rows.length) throw Park.error('CONFIG', '筛选参数无效');
      choices = rows.slice(Number(range) * 200, (Number(range) + 1) * 200);
    }
    return [{value: '', label: '全部'}, ...choices];
  },
  async categoryFeed(request) {
    const category = String(request.options?.category || '');
    if (!category) return this.feed(this.defaultFeed, request);
    const choices = await this.filterOptions({filter: 'category', values: request.options || {}});
    if (!choices.some(option => option.value === category)) {
      throw Park.error('CONFIG', '筛选参数无效');
    }
    const config = {"home":"/rating","leaf":"^/c/[a-zA-Z0-9_%+-]+/?$","index":"^/a-z/?$","pageMethod":"request","absolute":true,"listMethod":"categoryListing","ranges":true};
    return this[config.listMethod || 'listing'](category, request);
  },
  // __CATALOG_END__
  BASE: 'https://www.ixxx.com',
  linkPatterns: ['((?:https?://)?(?:www\\.)?ixxx\\.com/out/\\?[^\\s#]+)'],
  resolveLink(id) {
    const value = /^https?:\/\//i.test(id) ? id : 'https://' + id;
    const url = this.target(value);
    if (!url) throw Park.error('NOT_FOUND', '影片编号无效');
    return url;
  },
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
      const u = Park.url.site(this, href);
      if (!u || u.pathname !== '/out/') return null;
      const value = u.searchParams.get('l');
      if (!value || value.length > 16384 || !/^[a-zA-Z0-9+/]*={0,2}$/.test(value)) return null;
      const raw = atob(value), match = /https?:\/\/[\x21-\x7e]+/.exec(raw);
      return match ? this.externalUrl(match[0]) : null;
    } catch (_) { return null; }
  },
  pageUrl(value, kind) {
    try {
      const u = Park.url.site(this, value);
      if (!u) throw Park.error('CONFIG', '视频列表地址无效');
      const validPath = kind === 'feed' ? /^\/(?:[a-z]{2}(?:-[a-z]{2})?\/)?rating\/?$/i.test(u.pathname)
        : /^\/(?:[a-z]{2}(?:-[a-z]{2})?\/)?c\/[^/?#]+\/?$/i.test(u.pathname);
      if (validPath &&
          !/%2f|%5c|%2e/i.test(u.pathname) &&
          (!u.searchParams.has('page') || /^[1-9]\d{0,5}$/.test(u.searchParams.get('page')))) return u.href;
    } catch (_) {}
    throw Park.error('CONFIG', '视频列表地址无效');
  },
  async request(url, form) {
    const r = form ? await this.http.post(url, {form, timeout: 30000}) : await this.http.get(url, {timeout: 30000});
    if (!r.ok) throw Park.error('HTTP', '成人视频请求失败');
    const finalUrl = Park.url.response(this, r, url);
    if (r.body.length > 4 * 1024 * 1024) throw Park.error('PARSE', '影片页面过大');
    const doc = Park.html.parse(r.body);
    if (doc.querySelector(this.network.confirmation.selector)) {
      const cookies = await this.cookies.get(this.BASE + '/');
      if (!cookies.splashPageAccepted || doc.querySelector('#age-verification[open], #age-verification:not(dialog)')) {
        throw Park.error('CONFIRM_REQUIRED', '站点年龄确认未自动完成，请重试', {url: r.url || url});
      }
    }
    return {doc, url: finalUrl.href};
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
      const authors = [...new Set(Array.from(card?.querySelectorAll('a.pornstar-label[href]') || [])
        .map(a => Park.html.text(a).trim()).filter(name => name && name.length <= 240))];
      items.push({id, title: Park.html.unescape(title).trim(), cover, coverAspect: 16/9,
        duration: Park.html.text(a.querySelector('.badge')),
        uploader: Park.html.text(card?.querySelector('.item-source')), authors, url: id});
    }
    return items;
  },
  coverUrl(value) { return Park.url.parse(value, this.BASE, ['ttcache.com'])?.href || ''; },
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
    if (key === 'categories') return this.categoryFeed(req);
    if (key !== 'ranking') throw Park.error('CONFIG', '未知视频列表');
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    if (page > 1 && !req.cursor) throw Park.error('CONFIG', '请按顺序加载视频列表');
    return this.result(await this.request(this.pageUrl(req.cursor || this.BASE + '/rating', 'feed')), page, 'feed');
  },
  async categoryListing(category, req) {
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    if (page > 1 && !req.cursor) throw Park.error('CONFIG', '请按顺序加载视频列表');
    const url = new URL(this.pageUrl(req.cursor || this.BASE + category, 'search'));
    if (url.origin !== this.BASE || url.pathname.replace(/\/$/, '') !== category.replace(/\/$/, '') ||
        [...url.searchParams.keys()].some(key => key !== 'page') ||
        Number(url.searchParams.get('page') || 1) !== page) throw Park.error('CONFIG', '分页链接无效');
    const result = this.result(await this.request(url.href), page, 'search');
    if (result.cursor && new URL(result.cursor).pathname.replace(/\/$/, '') !== category.replace(/\/$/, '')) {
      throw Park.error('PARSE', '分页链接无效');
    }
    return result;
  },
  async search(req) {
    const keyword = String(req.keyword || '').trim(), page = Math.max(1, Math.floor(Number(req.page) || 1));
    if (!keyword) return {items: [], page, hasNext: false};
    if (page > 1 && !req.cursor) throw Park.error('CONFIG', '请按顺序加载视频列表');
    let result;
    if (page === 1) {
      const home = await this.request(this.BASE + '/');
      const form = home.doc.querySelector('form input[name="search_query[query]"]')?.closest('form');
      let action;
      try { action = new URL(form?.getAttribute('action'), home.url); } catch (_) {}
      if (!action || action.origin !== this.BASE || action.username || action.password || action.search || action.hash ||
          !/^\/(?:[a-z]{2}(?:-[a-z]{2})?\/)?searching\/by-form$/i.test(action.pathname)) {
        throw Park.error('PARSE', '站点搜索表单无效');
      }
      result = await this.request(action.href, {'search_query[query]': keyword});
    } else {
      result = await this.request(this.pageUrl(req.cursor, 'search'));
    }
    return this.result(result, page, 'search');
  },
  async detail(id, preview) {
    const url = this.externalUrl(id);
    if (!url || url !== id) throw Park.error('NOT_FOUND', '影片编号无效');
    const item = preview && preview.id === id ? preview : {};
    const authors = Array.isArray(item.authors) ? [...new Set(item.authors.filter(name =>
      typeof name === 'string' && name.trim() && name.length <= 240).map(name => name.trim()))] : [];
    return {id, url, title: typeof item.title === 'string' && item.title ? item.title : new URL(url).hostname,
      cover: this.coverUrl(item.cover) ? item.cover : '', coverAspect: 16/9,
      duration: typeof item.duration === 'string' ? item.duration : '',
      uploader: typeof item.uploader === 'string' ? item.uploader : '', authors,
      tags: authors.length ? [{namespace: 'actor', label: '演员', tags: authors.map(name => ({name, keyword: name}))}] : []};
  },
  upstreamUrl(value, domains, base, upgrade = false) {
    if (typeof value !== 'string' || value.length > 16384 || /[\x00-\x20\x7f\\]/.test(value)) return null;
    try {
      const u = new URL(value, base);
      if (upgrade && u.protocol === 'http:') u.protocol = 'https:';
      if (u.protocol !== 'https:' || u.username || u.password || u.port || u.hash ||
          !domains.some(d => u.hostname === d || u.hostname.endsWith('.' + d))) return null;
      return u.href;
    } catch (_) { return null; }
  },
  responseHeader(response, name) {
    return Object.entries(response.headers || {}).find(([key]) => key.toLowerCase() === name)?.[1] || '';
  },
  async upstreamPage(url, domains) {
    const seen = new Set();
    for (let hop = 0; hop < 5; hop++) {
      url = this.upstreamUrl(url, domains);
      if (!url || seen.has(url)) throw Park.error('BLOCKED', '播放器地址无效');
      seen.add(url);
      const r = await this.http.get(url, {mode: 'native', followRedirects: false, timeout: 30000});
      if ([301, 302, 303, 307, 308].includes(r.status)) {
        url = this.upstreamUrl(this.responseHeader(r, 'location'), domains, url);
        continue;
      }
      if (r.status === 404 || r.status === 410) throw Park.error('NOT_FOUND', '影片不存在');
      if (!r.ok) throw Park.error('HTTP', '成人视频请求失败', {status: r.status});
      if (r.body.length > 4 * 1024 * 1024) throw Park.error('PARSE', '影片页面过大');
      return {body: r.body, url};
    }
    throw Park.error('BLOCKED', '播放器地址无效');
  },
  // 仅 HEAD 解析媒体跳转，避免把整部影片读进插件；每一跳都重新校验。
  async resolveUpstreamMedia(value, domains, headers) {
    let url = this.upstreamUrl(value, domains), seen = new Set();
    if (!url) return null;
    for (let hop = 0; hop < 5; hop++) {
      if (seen.has(url)) throw Park.error('BLOCKED', '播放器地址无效');
      seen.add(url);
      const r = await this.http.request({url, method: 'HEAD', headers, mode: 'native', followRedirects: false, timeout: 20000});
      if ([301, 302, 303, 307, 308].includes(r.status)) {
        // 已验证的 CDN 可能返回 HTTP Location；只访问其 HTTPS 端点。
        url = this.upstreamUrl(this.responseHeader(r, 'location'), domains, url, true);
        if (!url) throw Park.error('BLOCKED', '播放器地址无效');
        continue;
      }
      if (!r.ok) throw Park.error('HTTP', '成人视频请求失败', {status: r.status});
      const type = this.responseHeader(r, 'content-type').split(';')[0].trim().toLowerCase();
      if (['application/vnd.apple.mpegurl', 'application/x-mpegurl', 'audio/mpegurl', 'audio/x-mpegurl'].includes(type)) return {url, format: 'hls'};
      if (type === 'video/mp4') return {url, format: 'mp4'};
      // 登录页、广告页、预览图片不能作为正片媒体。
      return null;
    }
    throw Park.error('BLOCKED', '播放器地址无效');
  },
  async upstreamVariants(candidates, domains, headers) {
    const out = [], seen = new Set();
    let failure;
    // 不同清晰度可能跳到同一个 HLS 主清单，按最终地址去重。
    for (const entry of candidates.slice(0, 8)) {
      if (seen.has(entry.url)) continue;
      seen.add(entry.url);
      try {
        const media = await this.resolveUpstreamMedia(entry.url, domains, headers);
        if (media && !out.some(x => x.url === media.url)) {
          const master = media.format === 'hls' && entry.format !== 'hls';
          out.push({...entry, ...media, ...(master ? {quality: 0, label: 'HLS'} : {}), headers});
        }
      } catch (e) {
        if (!['HTTP', 'NETWORK', 'TIMEOUT', 'NOT_FOUND'].includes(e.code)) throw e;
        failure ||= e;
      }
    }
    if (!out.length && failure) throw failure;
    return out;
  },
  scriptObject(html, pattern) {
    const match = pattern.exec(html);
    if (!match) return '';
    const start = match.index + match[0].length;
    let depth = 0, quote = '', escaped = false;
    for (let i = start; i < html.length; i++) {
      const c = html[i];
      if (quote) { if (escaped) escaped = false; else if (c === '\\') escaped = true; else if (c === quote) quote = ''; }
      else if (c === '"' || c === "'") quote = c;
      else if (c === '{') depth++;
      else if (c === '}' && --depth === 0) return html.slice(start, i + 1);
    }
    return '';
  },
  jsonObject(html, pattern) {
    try { return JSON.parse(this.scriptObject(html, pattern)); } catch (_) { return null; }
  },
  decodeVideoFile(value) {
    if (typeof value !== 'string' || value.length > 65536) return '';
    const map = {'Ѕ':'S', 'І':'I', 'Ј':'J', 'А':'A', 'В':'B', 'Е':'E', 'К':'K', 'М':'M', 'Н':'H', 'О':'O', 'Р':'P', 'С':'C', 'Х':'X', ',':'/', '.':'+', '~':'='};
    try { return atob(value.replace(/[ЅІЈАВЕКМНОРСХ,.~]/g, c => map[c])); } catch (_) { return ''; }
  },
  async videoFileVariants(base, id, mediaDomains, encoded) {
    let data;
    if (encoded) {
      try { data = JSON.parse(this.decodeVideoFile(encoded)); } catch (_) { throw Park.error('PARSE', '成人视频详情解析失败'); }
    } else {
      const r = await this.upstreamPage(base + '/api/videofile.php?video_id=' + encodeURIComponent(id) + '&lifetime=8640000', [new URL(base).hostname]);
      try { data = JSON.parse(r.body); } catch (_) { throw Park.error('PARSE', '成人视频详情解析失败'); }
    }
    if (!Array.isArray(data)) throw Park.error('PARSE', '成人视频详情解析失败');
    const candidates = [];
    for (const entry of data.slice(0, 16)) {
      const url = this.upstreamUrl(this.decodeVideoFile(entry?.video_url), [new URL(base).hostname], base);
      const format = Array.isArray(entry?.format) ? entry.format[0] : entry?.format;
      if (!url || !new URL(url).pathname.startsWith('/get_file/') || !['.mp4', '_hq.mp4', '_sd.mp4', '_lq.mp4'].includes(format)) continue;
      // 接口的 hq/sd/lq 是档位名，不代表经过验证的像素高度。
      const rank = format === '_hq.mp4' ? 3 : format === '.mp4' ? 2 : 1;
      candidates.push({url, quality: 0, rank, label: format === '_hq.mp4' ? '高清' : format === '.mp4' ? 'MP4' : '标清'});
    }
    candidates.sort((a, b) => b.rank - a.rank);
    return this.upstreamVariants(candidates.map(({rank, ...entry}) => entry), mediaDomains, {Referer: base + '/'});
  },
  decipherXh(value) {
    if (typeof value !== 'string' || value.length > 16384) return '';
    const decode = hex => {
      if (!/^[a-f0-9]{12,}$/i.test(hex) || hex.length % 2) return '';
      const bytes = hex.match(/../g).map(x => parseInt(x, 16));
      const algorithm = bytes[0];
      let state = bytes[1] | bytes[2] << 8 | bytes[3] << 16 | bytes[4] << 24, out = '';
      for (const byte of bytes.slice(5)) {
        let n;
        switch (algorithm) {
          case 1: state = (Math.imul(state, 1664525) + 1013904223) | 0; n = state; break;
          case 2: state ^= state << 13; state ^= state >>> 17; state ^= state << 5; n = state; break;
          case 3:
            state = (state + 0x9e3779b9) | 0; n = state; n ^= n >>> 16;
            n = Math.imul(n, 0x85ebca77); n ^= n >>> 13; n = Math.imul(n, 0xc2b2ae3d); n ^= n >>> 16; break;
          case 4:
            state = (state + 0x6d2b79f5) | 0; n = state << 7 | state >>> 25;
            n = (n + 0x9e3779b9) | 0; n ^= n >>> 11; n = Math.imul(n, 0x27d4eb2d); break;
          case 5: state ^= state << 7; state ^= state >>> 9; state ^= state << 8; state = (state + 0xa5a5a5a5) | 0; n = state; break;
          case 6: state = (Math.imul(state, 0x2c9277b5) + 0xac564b05) | 0; n = (state ^ state >>> 18) >>> (state >>> 27 & 31); break;
          case 7: state = (state + 0x9e3779b9) | 0; n = Math.imul(state ^ state << 5, 0x7feb352d); n ^= n >>> 15; n = Math.imul(n, 0x846ca68b); break;
          default: return '';
        }
        out += String.fromCharCode(byte ^ (n & 255));
      }
      return out;
    };
    if (/^[a-f0-9]+$/i.test(value)) return decode(value);
    // 部分播放器将密文放在 URL 的首个路径段。
    try {
      const u = new URL(value), parts = u.pathname.split('/');
      if (/^[a-f0-9]{12,}$/i.test(parts[1])) {
        const path = decode(parts[1]);
        if (!path) return '';
        parts[1] = path; u.pathname = parts.join('/');
      }
      return u.href;
    } catch (_) { return ''; }
  },
  async xhVariants(page, pageDomains) {
    let data = this.jsonObject(page.body, /window\.initials\s*=\s*(?=\{)/);
    if (!data?.xplayerSettings?.sources) {
      // Embed 页面可能只声明规范详情页；只允许同家族详情路径，最多补一次。
      const canonical = this.upstreamUrl(data?.sharingComponent?.shareLink, pageDomains);
      if (canonical && /^\/videos\/[^/]+$/.test(new URL(canonical).pathname)) {
        page = await this.upstreamPage(canonical, pageDomains);
        data = this.jsonObject(page.body, /window\.initials\s*=\s*(?=\{)/);
      }
    }
    const sources = data?.xplayerSettings?.sources, out = [];
    const add = (value, quality, format) => {
      const url = this.upstreamUrl(this.decipherXh(value), ['xhcdn.com']);
      if (url && !out.some(x => x.url === url)) out.push({url, quality, format, label: quality ? quality + 'P' : format.toUpperCase()});
    };
    // 优先通用 H.264，避免设备不支持 AV1 时无法播放。
    for (const entry of Array.isArray(sources?.standard?.h264) ? sources.standard.h264 : []) {
      const quality = parseInt(entry.quality, 10) || 0;
      add(entry.url, quality, /\.m3u8(?:[/?]|$)/.test(this.decipherXh(entry.url)) ? 'hls' : 'mp4');
      add(entry.fallback, quality, /\.m3u8(?:[/?]|$)/.test(this.decipherXh(entry.fallback)) ? 'hls' : 'mp4');
    }
    if (sources?.hls?.url) add(sources.hls.url, 0, 'hls');
    const hls = out.filter(x => x.format === 'hls');
    return this.upstreamVariants(hls.length ? hls : out, ['xhcdn.com'], {});
  },
  upstreamProfile(url) {
    const host = new URL(url).hostname;
    const profiles = [
      {kind: 'xh', pages: ['xh.partners', 'xh.video', 'xhamster.com', 'xhsocial.com'], media: ['xhcdn.com']},
      {kind: 'file', pages: ['abxxx.tube', 'abxxx.com'], base: 'https://abxxx.com', media: ['abxxx.com', 'ahcdn.com']},
      {kind: 'file', pages: ['vid-xm.com', 'xmilf.com'], base: 'https://xmilf.com', media: ['xmilf.com', 'ahcdn.com']},
      {kind: 'file', pages: ['videotxxx.com', 'txxx.me'], base: 'https://txxx.me', media: ['txxx.me', 'ahcdn.com']},
      {kind: 'file', pages: ['videopornl.com', 'pornl.com'], base: 'https://pornl.com', media: ['pornl.com', 'pornl-ah.nv7s.com', 'ahcdn.com']},
      {kind: 'porntop', pages: ['vid-pt.com', 'porntop.com'], base: 'https://porntop.com', media: ['porntop.com', 'ptah.m3pd.com', 'ahcdn.com']},
      ...[
        ['xozilla.xxx'], ['pornid.xxx', 'avideos.xxx'], ['theyarehuge.com'], ['inxxx.com'],
        ['dafreeporn.com'], ['xhand.net'], ['amateur8.com'], ['maturetubehere.com'], ['sortporn.com'], ['lesbian8.com'],
      ].map(pages => ({kind: 'kvs', pages, media: [...pages, 'ahcdn.com',
        ...(pages[0] === 'dafreeporn.com' ? ['freeporn8.com'] : pages[0] === 'xhand.net' ? ['xhand.com'] : [])]})),
      {kind: 'html', pages: ['pornone.com'], media: ['pornone.com']},
      {kind: 'html', pages: ['ok.xxx'], media: ['ok.xxx', 'cdn.privatehost.com']},
    ];
    return profiles.find(p => p.pages.some(d => host === d || host.endsWith('.' + d)));
  },
  // 只读取对象顶层的字符串属性；不 eval、不执行函数或外站脚本。
  literalFields(block) {
    const fields = {};
    let depth = 0;
    const readString = (start, quote) => {
      let text = '', i = start;
      for (; i < block.length; i++) {
        const c = block[i];
        if (c === quote) return {text, end: i};
        if (c !== '\\') { text += c; continue; }
        const next = block[++i];
        if (next === 'u' && /^[a-f0-9]{4}$/i.test(block.slice(i + 1, i + 5))) { text += String.fromCharCode(parseInt(block.slice(i + 1, i + 5), 16)); i += 4; }
        else if (next === 'x' && /^[a-f0-9]{2}$/i.test(block.slice(i + 1, i + 3))) { text += String.fromCharCode(parseInt(block.slice(i + 1, i + 3), 16)); i += 2; }
        else text += ({n: '\n', r: '\r', t: '\t'}[next] || next || '');
      }
      return {text: '', end: i};
    };
    for (let i = 0; i < block.length; i++) {
      const c = block[i];
      if (c === '{') { depth++; continue; }
      if (c === '}') { depth--; continue; }
      if (depth === 1) {
        const m = /^\s*(?:([A-Za-z_]\w*)|["']([A-Za-z_]\w*)["'])\s*:\s*(["'])/.exec(block.slice(i));
        if (m) {
          const value = readString(i + m[0].length, m[3]);
          fields[m[1] || m[2]] = value.text; i = value.end; continue;
        }
      }
      if (c === '"' || c === "'") i = readString(i + 1, c).end;
    }
    return fields;
  },
  async indexedVariants(url, profile) {
    if (profile.kind === 'file') {
      const id = /^\/(?:videos?|embed)\/(\d+)(?:\/|$)/.exec(new URL(url).pathname)?.[1];
      if (!id) throw Park.error('UNSUPPORTED', '此影片暂无可用播放地址');
      return this.videoFileVariants(profile.base, id, profile.media);
    }
    const page = await this.upstreamPage(url, profile.pages);
    if (profile.kind === 'xh') return this.xhVariants(page, profile.pages);
    if (profile.kind === 'porntop') {
      const encoded = /window\.initPlayer\([\s\S]*?\}\}\},\s*'([^']+)'/.exec(page.body)?.[1];
      if (!encoded) throw Park.error('PARSE', '成人视频详情解析失败');
      return this.videoFileVariants(profile.base, '', profile.media, encoded);
    }
    const candidates = [];
    if (profile.kind === 'kvs') {
      const pattern = /\bvar\s+flashvars(?:_\d+)?\s*=\s*(?=\{)/g;
      let match;
      while ((match = pattern.exec(page.body))) {
        const fields = this.literalFields(this.scriptObject(page.body.slice(match.index), /\bvar\s+flashvars(?:_\d+)?\s*=\s*(?=\{)/));
        for (const key of Object.keys(fields).filter(k => /^video_(?:alt_)?url\d*$/.test(k))) {
          if (fields[key + '_redirect'] === '1') continue;
          const media = this.upstreamUrl(fields[key], profile.pages, page.url);
          if (!media || !new URL(media).pathname.startsWith('/get_file/')) continue;
          const quality = parseInt(fields[key + '_text'], 10) || 0;
          // 后出现的播放器配置可修正相同地址的清晰度标签。
          const old = candidates.find(x => x.url === media);
          if (old) { old.quality = quality || old.quality; old.label = old.quality ? old.quality + 'P' : 'MP4'; }
          else candidates.push({url: media, quality, label: quality ? quality + 'P' : 'MP4'});
        }
      }
    } else {
      for (const entry of Park.html.parse(page.body).querySelectorAll('video source[src]')) {
        const media = this.upstreamUrl(entry.getAttribute('src'), profile.media, page.url);
        if (!media || /preview/i.test(new URL(media).pathname)) continue;
        const quality = parseInt(entry.getAttribute('label'), 10) || 0;
        candidates.push({url: media, quality, label: quality ? quality + 'P' : 'MP4'});
      }
    }
    const headers = {Referer: profile.kind === 'kvs' || new URL(page.url).hostname === 'ok.xxx' ? new URL(page.url).origin + '/' : this.BASE + '/'};
    return this.upstreamVariants(candidates, profile.media, headers);
  },
  async videos(id) {
    const target = await this.webVideo(id), u = new URL(target.url);
    if (/^(?:www\.)?eporner\.com$/.test(u.hostname)) return this.epornerVariants(id);
    const profile = this.upstreamProfile(u.href);
    if (!profile) throw Park.error('UNSUPPORTED', '此影片暂无可用播放地址');
    const out = await this.indexedVariants(u.href, profile);
    if (!out.length) throw Park.error('PARSE', '此影片暂无可用播放地址');
    out.sort((a, b) => b.quality - a.quality);
    out[0].preferred = true;
    return out;
  },
  async epornerVariants(id) {
    const target = await this.webVideo(id), u = new URL(target.url);
    const match = /^(?:www\.)?eporner\.com$/.test(u.hostname) && /^\/video-([A-Za-z0-9]{1,32})(?:\/|$)/.exec(u.pathname);
    if (!match) throw Park.error('UNSUPPORTED', '此影片暂无可用播放地址');
    const videoId = match[1], base = 'https://www.eporner.com';
    const get = async (url, params) => {
      const r = await this.http.get(url, {params, mode: 'native', followRedirects: false, timeout: 30000});
      if (r.status === 404) throw Park.error('NOT_FOUND', '影片不存在');
      if (!r.ok) throw Park.error('HTTP', '成人视频请求失败', {status: r.status});
      if (r.body.length > 4 * 1024 * 1024) throw Park.error('PARSE', '影片页面过大');
      return r;
    };
    const data = (await get(base + '/api/v2/video/id/', {id: videoId, format: 'json'})).json();
    const video = data?.video || data;
    let hash = String(video?.hash || '');
    if (!/^[a-f0-9]{32}$/i.test(hash)) {
      // API 返回的规范详情地址包含标题；无标题路径会 301，不能放开外站重定向。
      let pageUrl = u.href;
      try {
        const canonical = new URL(video?.url);
        if (canonical.origin === base && !canonical.username && !canonical.password &&
            !canonical.search && !canonical.hash && canonical.pathname.startsWith('/video-' + videoId + '/')) {
          pageUrl = canonical.href;
        }
      } catch (_) {}
      const page = await get(pageUrl);
      hash = /EP\.video\.player\.hash\s*=\s*['"]([a-f0-9]{32})['"]/i.exec(page.body)?.[1] || '';
    }
    if (!hash) throw Park.error('UNSUPPORTED', '此影片暂无可用播放地址');
    let transformed = '';
    for (let i = 0; i < 32; i += 8) transformed += parseInt(hash.slice(i, i + 8), 16).toString(36);
    const media = (await get(base + '/xhr/video/' + videoId, {hash: transformed, device: 'generic', domain: 'www.eporner.com', fallback: 'false'})).json();
    const out = [];
    for (const [label, entry] of Object.entries(media?.sources?.mp4 || {})) {
      let url;
      try { url = new URL(typeof entry === 'string' ? entry : entry?.src); } catch (_) { continue; }
      if (url.protocol !== 'https:' || url.username || url.password || url.port || url.hash ||
          !(url.hostname === 'eporner.com' || url.hostname.endsWith('.eporner.com')) || out.some(x => x.url === url.href)) continue;
      const quality = Number(label.replace(/\D/g, '')) || 0;
      out.push({url: url.href, format: 'mp4', quality, label: quality ? quality + 'P' : 'MP4'});
    }
    out.sort((a, b) => b.quality - a.quality);
    if (!out.length) throw Park.error('UNSUPPORTED', '此影片暂无可用播放地址');
    out[0].preferred = true;
    return out;
  },
  async webVideo(id) {
    let url = this.externalUrl(id);
    if (!url || url !== id) throw Park.error('NOT_FOUND', '影片编号无效');
    // 索引中的历史 HTTP 链接仍保持作品 ID；播放器只使用 HTTPS。
    const target = new URL(url);
    target.protocol = 'https:';
    url = target.href;
    const profile = this.upstreamProfile(url);
    return {url, navigationDomains: profile ? profile.pages : [new URL(url).hostname]};
  },
});

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"}]});
