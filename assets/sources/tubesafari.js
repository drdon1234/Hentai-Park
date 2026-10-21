/* 聚合索引：已验证的上游使用原生媒体，其余保留隔离网页播放。 */
Park.register({
  i18n: {
    "zh-Hant": {"综合成人视频搜索，常见来源优先原生播放，其他来源使用网页播放": "綜合成人影片搜尋，常見來源優先原生播放，其他來源使用網頁播放", "高清": "高清", "标清": "標清"},
    "ja": {"综合成人视频搜索，常见来源优先原生播放，其他来源使用网页播放": "成人動画検索。対応する主な配信元はネイティブ再生を優先し、その他はウェブ再生", "高清": "高画質", "标清": "標準画質"},
    "ko": {"综合成人视频搜索，常见来源优先原生播放，其他来源使用网页播放": "성인 동영상 검색. 지원되는 주요 출처는 네이티브 재생을 우선하고 나머지는 웹 재생", "高清": "고화질", "标清": "표준 화질"},
    "en": {"综合成人视频搜索，常见来源优先原生播放，其他来源使用网页播放": "Adult video search; native playback for supported popular providers, web playback for others", "高清": "High quality", "标清": "Standard quality"},
    "es": {"综合成人视频搜索，常见来源优先原生播放，其他来源使用网页播放": "Búsqueda de vídeos para adultos; reproducción nativa de proveedores populares compatibles y web para los demás", "高清": "Alta calidad", "标清": "Calidad estándar"},
    "ru": {"综合成人视频搜索，常见来源优先原生播放，其他来源使用网页播放": "Поиск видео для взрослых: нативное воспроизведение популярных поддерживаемых источников, веб-плеер для остальных", "高清": "Высокое качество", "标清": "Стандартное качество"},
    "ar": {"综合成人视频搜索，常见来源优先原生播放，其他来源使用网页播放": "بحث فيديوهات للبالغين؛ تشغيل أصلي للمصادر الشائعة المدعومة وتشغيل ويب للمصادر الأخرى", "高清": "جودة عالية", "标清": "جودة قياسية"},
  },
  key: 'tubesafari', name: 'TubeSafari', version: '0.0.7', type: 'video', category: 'adult', color: '#21B7B5',
  description: '综合成人视频搜索，常见来源优先原生播放，其他来源使用网页播放', homepage: 'https://tubesafari.com', language: 'en',
  domains: ['tubesafari.com', 'xhcdn.com', 'nv7s.com', 'others-cdn.com', 'txxx.tube', 'phncdn.com'],
  network: {mode: 'native', vpnHint: true}, imageHeaders: {Referer: 'https://tubesafari.com/'},
  media: {mode: 'native', origin: 'https://tubesafari.com', domains: ['xvideos-cdn.com', 'phncdn.com', 'xhcdn.com', 'txxx.me', 'pornl.com', 'pornl-ah.nv7s.com', 'ahcdn.com'], referrerDomains: ['pornhub.com', 'txxx.me', 'pornl.com']},
  linkPatterns: ['tubesafari\\.com/video\\?(?:[^#\\s]*&)?id=([a-zA-Z0-9_-]+)(?:[&#]|$)'],
  idPattern: '^([a-zA-Z0-9_-]{1,128})$',
  defaultFeed: 'popular', feeds: [{key: 'popular', label: '热门'}, {key: 'categories', label: '分类', options: [
    {key: 'category', label: '分类', default: '', dynamic: true, values: []},
  ]}], searchHint: '搜索作品名或标签',
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
  async filterOptions(req) {
    if (req.scope !== 'feed' || req.feed !== 'categories' || req.filter !== 'category') throw Park.error('CONFIG', '筛选参数无效');
    const {doc} = await this.getPage(this.BASE + '/categories'), values = new Map([['', '全部']]);
    for (const a of doc.querySelectorAll('a.vid[href]')) {
      let u; try { u = new URL(a.getAttribute('href'), this.BASE); } catch (_) { continue; }
      const m = u.origin === this.BASE && /^\/search\/([a-z0-9-]+)$/.exec(u.pathname), label = Park.html.text(a);
      if (m && label) values.set(m[1], label);
    }
    if (values.size < 2) throw Park.error('PARSE', '分类列表解析失败');
    return [...values].map(([value,label]) => ({value,label}));
  },
  async listing(keyword, req, feed = false, category = '') {
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    if (!Number.isSafeInteger(page) || page > 100000) throw Park.error('CONFIG', '视频列表地址无效');
    if (page === 1 && !feed) {
      const {doc} = await this.getPage(this.BASE + (category ? '/search/' + category : '/search?query=' + encodeURIComponent(keyword)));
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
    if (key === 'categories') {
      const category = String(req.options?.category || '');
      if (category && !/^[a-z0-9-]{1,100}$/.test(category)) throw Park.error('CONFIG', '筛选参数无效');
      return this.listing(category.replace(/-/g, ' '), req, !category, category);
    }
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
  mediaUrl(value, domain) {
    try {
      const u = new URL(value);
      return u.protocol === 'https:' && !u.username && !u.password && !u.port && !u.hash &&
        (u.hostname === domain || u.hostname.endsWith('.' + domain)) ? u.href : null;
    } catch (_) { return null; }
  },
  playerData(html) {
    const match = /\bvar\s+flashvars(?:_\d+)?\s*=\s*(?=\{)/.exec(html);
    if (!match) return null;
    const start = match.index + match[0].length;
    let depth = 0, quoted = false, escape = false;
    for (let i = start; i < html.length; i++) {
      const c = html[i];
      if (quoted) { if (escape) escape = false; else if (c === '\\') escape = true; else if (c === '"') quoted = false; }
      else if (c === '"') quoted = true;
      else if (c === '{') depth++;
      else if (c === '}' && --depth === 0) {
        try { return JSON.parse(html.slice(start, i + 1)); } catch (_) { return null; }
      }
    }
    return null;
  },
  async videos(id) {
    const target = await this.webVideo(id), u = new URL(target.url);
    const xhDomains = ['xh.partners', 'xh.video', 'xhamster.com', 'xhsocial.com'];
    if (this.upstreamUrl(u.href, xhDomains)) {
      const out = await this.xhVariants(await this.upstreamPage(u.href, xhDomains), xhDomains);
      if (!out.length) throw Park.error('PARSE', '此影片暂无可用播放地址');
      out.sort((a, b) => b.quality - a.quality); out[0].preferred = true;
      return out;
    }
    const files = [
      {pages: ['videopornl.com', 'pornl.com'], base: 'https://pornl.com', media: ['pornl.com', 'pornl-ah.nv7s.com', 'ahcdn.com']},
      {pages: ['videotxxx.com', 'txxx.me'], base: 'https://txxx.me', media: ['txxx.me', 'ahcdn.com']},
    ];
    const family = files.find(f => this.upstreamUrl(u.href, f.pages));
    if (family) {
      const videoId = /^\/(?:embed|videos?)\/(\d+)(?:\/|$)/.exec(u.pathname)?.[1];
      if (!videoId) throw Park.error('UNSUPPORTED', '此影片暂无可用播放地址');
      const out = await this.videoFileVariants(family.base, videoId, family.media);
      if (!out.length) throw Park.error('PARSE', '此影片暂无可用播放地址');
      out.sort((a, b) => b.quality - a.quality); out[0].preferred = true;
      return out;
    }
    const xvideos = /^(?:www\.)?xvideos\.com$/.test(u.hostname) && /^\/embedframe\/[a-z0-9]+$/.test(u.pathname);
    const pornhub = /^(?:www\.)?pornhub\.com$/.test(u.hostname) && /^\/embed\/[a-z0-9]+$/.test(u.pathname);
    if (!xvideos && !pornhub) throw Park.error('UNSUPPORTED', '此影片暂无可用播放地址');
    // 外站不使用索引站浏览器会话，也不跟随未声明的播放器重定向。
    const response = await this.http.get(u.href, {mode: 'native', followRedirects: false, timeout: 30000});
    if (response.status === 404) throw Park.error('NOT_FOUND', '影片不存在');
    if (!response.ok) throw Park.error('HTTP', '成人视频请求失败', {status: response.status});
    const html = response.body;
    if (html.length > 4 * 1024 * 1024) throw Park.error('PARSE', '影片页面过大');
    const out = [];
    if (xvideos) {
      for (const [method, label] of [['setVideoUrlHigh', '高清'], ['setVideoUrlLow', '标清']]) {
        const m = new RegExp('html5player\\.' + method + '\\([\'"]([^\'"\\s]+)[\'"]\\)').exec(html);
        const url = m && this.mediaUrl(m[1].replace(/\\\//g, '/'), 'xvideos-cdn.com');
        if (url && !out.some(x => x.url === url)) out.push({url, quality: 0, label, format: 'mp4'});
      }
    } else {
      const data = this.playerData(html);
      for (const entry of Array.isArray(data?.mediaDefinitions) ? data.mediaDefinitions : []) {
        const url = this.mediaUrl(entry?.videoUrl, 'phncdn.com'), quality = Number(entry?.quality) || 0;
        if (entry?.format !== 'hls' || !url || !new URL(url).pathname.endsWith('.m3u8') || out.some(x => x.url === url)) continue;
        out.push({url, quality, label: quality ? quality + 'P' : 'HLS', format: 'hls', headers: {Referer: 'https://www.pornhub.com/'}});
      }
      out.sort((a, b) => b.quality - a.quality);
    }
    if (!out.length) throw Park.error('UNSUPPORTED', '此影片暂无可用播放地址');
    out[0].preferred = true;
    return out;
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
      'xh.partners': ['xhamster.com', 'xhsocial.com'],
      'xh.video': ['xhamster.com', 'xhsocial.com'],
      'xhamster.com': ['xhsocial.com'],
      'videotxxx.com': ['txxx.me'],
      'videopornl.com': ['pornl.com'],
    };
    return {url: url.href, navigationDomains: [url.hostname, ...(redirects[url.hostname] || [])]};
  },
});

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"}]});
