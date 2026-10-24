/* SpankBang：浏览器同源取页面，静态提取公开 MP4；不执行播放器。 */
Park.register({
  i18n: {
    "zh-Hant": {"站点年龄确认未自动完成，请重试": "網站年齡確認未自動完成，請重試", "综合成人视频，支持推荐、搜索与多清晰度MP4；站点验证在后台处理": "綜合成人影片，支援推薦、搜尋與多畫質MP4；網站驗證在背景處理"},
    "ja": {"站点年龄确认未自动完成，请重试": "サイトの年齢確認が自動で完了しませんでした。再試行してください。", "综合成人视频，支持推荐、搜索与多清晰度MP4；站点验证在后台处理": "成人動画。おすすめ・検索・複数画質の MP4 に対応。サイト認証はバックグラウンドで処理します"},
    "ko": {"站点年龄确认未自动完成，请重试": "사이트 연령 확인이 자동으로 완료되지 않았습니다. 다시 시도하세요.", "综合成人视频，支持推荐、搜索与多清晰度MP4；站点验证在后台处理": "성인 동영상; 추천, 검색 및 다양한 MP4 화질 지원; 사이트 인증은 백그라운드에서 처리합니다"},
    "en": {"站点年龄确认未自动完成，请重试": "Automatic age confirmation did not complete. Please try again.", "综合成人视频，支持推荐、搜索与多清晰度MP4；站点验证在后台处理": "Adult videos with recommendations, search and multiple MP4 qualities; site verification runs in the background"},
    "es": {"站点年龄确认未自动完成，请重试": "La confirmación automática de edad no se completó. Inténtalo de nuevo.", "综合成人视频，支持推荐、搜索与多清晰度MP4；站点验证在后台处理": "Vídeos para adultos con recomendaciones, búsqueda y varias calidades MP4; verificación en segundo plano"},
    "ru": {"站点年龄确认未自动完成，请重试": "Автоматическое подтверждение возраста не завершено. Повторите попытку.", "综合成人视频，支持推荐、搜索与多清晰度MP4；站点验证在后台处理": "Видео для взрослых: рекомендации, поиск и MP4 разного качества; проверка сайта в фоне"},
    "ar": {"站点年龄确认未自动完成，请重试": "لم يكتمل تأكيد العمر تلقائيًا. يرجى إعادة المحاولة.", "综合成人视频，支持推荐、搜索与多清晰度MP4；站点验证在后台处理": "فيديو للبالغين مع التوصيات والبحث وجودات MP4 متعددة؛ التحقق من الموقع في الخلفية"},
  },
  key: 'spankbang', name: 'SpankBang', version: '0.0.10', minAppVersion: '0.9.2', type: 'video', category: 'adult',
  language: 'en', color: '#F99B1C', homepage: 'https://spankbang.com',
  description: '综合成人视频，支持推荐、搜索与多清晰度MP4；站点验证在后台处理',
  domains: ['spankbang.com'], network: {mode: 'browser', origin: 'https://spankbang.com', vpnHint: true, confirmation: {
    selector: '#av-wrapper', readySelector: '[data-testid="video-item"] a[href*="/video/"], #new-video-page',
    requiredCookies: ['av'], auto: {clickSelector: '#age-check-yes'}, message: '站点年龄确认未自动完成，请重试',
  }},
  media: {mode: 'native', scope: 'session', origin: 'https://spankbang.com', domains: ['sb-cd.com']},
  imageHeaders: {Referer: 'https://spankbang.com/'},
  defaultFeed: 'recommended', feeds: [{key: 'recommended', label: '推荐'},
    {key: 'categories', label: '分类', options: [
      {key: 'range', label: '范围', type: 'select', default: '0', dynamic: true, values: []},
      {key: 'category', label: '标签', type: 'select', default: '', dynamic: true, dependsOn: ['range'], values: []}]}],
  linkPatterns: ['spankbang\\.com/([a-z0-9]+/video/[^/?#]+)'],
  // __CATALOG_START__：由 tools/build_catalog_sources.mjs 生成。
  async categoryDirectory() {
    if (this._categoryDirectory && Date.now() - this._categoryDirectory.time < 120000) return this._categoryDirectory.values;
    const config = {"home":"/","leaf":"^/s/[a-zA-Z0-9_%+-]+/$","index":"^/tags/?$","pageMethod":"page","absolute":true,"listMethod":"categoryListing","ranges":true}, leaf = new RegExp(config.leaf), index = config.index ? new RegExp(config.index) : null;
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
    const config = {"home":"/","leaf":"^/s/[a-zA-Z0-9_%+-]+/$","index":"^/tags/?$","pageMethod":"page","absolute":true,"listMethod":"categoryListing","ranges":true};
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
    const config = {"home":"/","leaf":"^/s/[a-zA-Z0-9_%+-]+/$","index":"^/tags/?$","pageMethod":"page","absolute":true,"listMethod":"categoryListing","ranges":true};
    return this[config.listMethod || 'listing'](category, request);
  },
  // __CATALOG_END__
  idPattern: '^[a-z0-9]{1,12}/(?:video/)?[^/?#]{1,240}$', BASE: 'https://spankbang.com',
  idValue(value) {
    const id = String(value).replace('/video/', '/'), m = /^([a-z0-9]{1,12})\/([^/?#]{1,240})$/.exec(id);
    if (!m || /[\\\s]/.test(id)) throw Park.error('NOT_FOUND', '影片编号无效');
    let slug; try { slug = decodeURIComponent(m[2]); } catch (_) { throw Park.error('NOT_FOUND', '影片编号无效'); }
    if (/[/?#\\\x00-\x1f\x7f]/.test(slug) || !slug.trim() || slug === '.' || slug === '..') throw Park.error('NOT_FOUND', '影片编号无效');
    return id;
  },
  siteUrl(value) { return Park.url.site(this, value); },
  // 图片与视频 CDN 会更换主机，只要求是公网 HTTPS 地址，播放按会话授权。
  mediaUrl(value) { return ((value, base) => { try { const u = new URL(String(value).trim(), base); return Park.url.parse(u.href, base, [u.hostname]); } catch (_) { return null; } })(value, this.BASE)?.href || ''; },
  coverUrl(value) { return this.mediaUrl(value); },
  async page(url) {
    if (!this.siteUrl(url)) throw Park.error('CONFIG', '视频列表地址无效');
    const r = this.http.ensureOk(await this.http.get(url));
    const finalUrl = Park.url.response(this, r, url);
    const doc = Park.html.parse(r.body);
    if (/\bid=["']av-wrapper["']/.test(r.body)) {
      const cookies = await this.cookies.get(this.BASE + '/');
      const [type, required] = String(cookies.av || '').split(':');
      const accepted = type === 'simple' && cookies.age_pass === '1' || type === 'advanced' && required === 'False';
      if (!accepted) throw Park.error('CONFIRM_REQUIRED', '站点年龄确认未自动完成，请重试', {url: r.url || url});
    }
    return {html: r.body, doc, url: finalUrl.href};
  },
  cards(doc) {
    const items = [], seen = new Set();
    for (const a of doc.querySelectorAll('[data-testid="video-item"] a[href*="/video/"]')) {
      const img = a.querySelector('img'); if (!img) continue;
      const u = this.siteUrl(a.getAttribute('href')), m = u && /^\/([a-z0-9]{1,12})\/video\/([^/]+)\/?$/.exec(u.pathname);
      const cover = this.coverUrl(img.getAttribute('data-src') || img.getAttribute('src'));
      const title = img.getAttribute('alt') || a.getAttribute('title');
      if (!m || !title || seen.has(m[1])) continue;
      let id; try { id = this.idValue(m[1] + '/' + m[2]); } catch (_) { continue; }
      seen.add(m[1]); items.push({id, title, cover, url: u.href, coverAspect: 16/9});
    }
    return items;
  },
  async listing(req, keyword) {
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    const base = keyword === undefined ? '/' : '/s/' + encodeURIComponent(keyword.toLowerCase()).replace(/%20/g, '+') + '/';
    let url = this.BASE + base;
    if (page > 1) {
      const u = this.siteUrl(req.cursor);
      const expected = (keyword === undefined ? '/trending_videos/' : base) + page;
      if (!u || u.pathname.replace(/\/$/, '') !== expected) throw Park.error('CONFIG', '分页链接无效');
      url = u.href;
    }
    const {doc} = await this.page(url), items = this.cards(doc);
    let cursor;
    for (const a of doc.querySelectorAll('a[href]')) {
      if (Park.html.text(a) !== String(page + 1)) continue;
      const u = this.siteUrl(a.getAttribute('href'));
      if (u && (keyword === undefined ? /^\/trending_videos\//.test(u.pathname) : u.pathname.startsWith(base))) { cursor = u.href; break; }
    }
    return {items, page, hasNext: !!cursor, cursor};
  },
  async feed(key, req) {
    if (key === 'categories') return this.categoryFeed(req);
    if (key !== 'recommended') throw Park.error('CONFIG', '未知列表');
    return this.listing(req);
  },
  async categoryListing(category, req) {
    let keyword;
    try { keyword = decodeURIComponent(category.split('/')[2].replace(/\+/g, ' ')); }
    catch (_) { throw Park.error('CONFIG', '筛选参数无效'); }
    return this.listing(req, keyword);
  },
  async search(req) {
    const keyword = String(req.keyword || '').trim();
    return keyword ? this.listing(req, keyword) : {items: [], page: 1, hasNext: false};
  },
  workUrl(value) {
    const id = this.idValue(value), split = id.indexOf('/');
    return this.BASE + '/' + id.slice(0, split) + '/video/' + id.slice(split + 1);
  },
  async detail(value) {
    const id = this.idValue(value), url = this.workUrl(id), {doc} = await this.page(url);
    const title = Park.html.text(doc.querySelector('#new-video-page h1,h1')), cover = this.coverUrl(doc.querySelector('#player_cover_img')?.getAttribute('src') || doc.querySelector('meta[property="og:image"]')?.getAttribute('content'));
    if (!title) throw Park.error('NOT_FOUND', '影片不存在');
    return {id, title, cover, coverAspect: 16/9, url, chapters: null, tags: [], authors: [], related: this.cards(doc).filter(x => x.id !== id)};
  },
  parseVideos(html, referer) {
    const start = html.indexOf('var stream_data'), end = html.indexOf('};', start);
    if (start < 0 || end < start || end - start > 256 * 1024) return [];
    const data = html.slice(start, end + 2), out = [];
    for (const m of data.matchAll(/['"](\d+p|4k)['"]\s*:\s*\[([^\]]*)\]/g)) {
      const quality = m[1] === '4k' ? 2160 : parseInt(m[1], 10);
      for (const x of m[2].matchAll(/['"]([^'"]+)['"]/g)) {
        const url = this.mediaUrl(Park.html.unescape(x[1].replace(/\\\//g, '/')));
        if (url) { out.push({quality, label: quality + 'P', format: 'mp4', url, headers: {Referer: referer}}); break; }
      }
    }
    out.sort((a, b) => b.quality - a.quality);
    const best = out.find(x => x.quality <= 720) || out[out.length - 1]; if (best) best.preferred = true;
    return out;
  },
  async videos(value) {
    const referer = this.workUrl(value), {html} = await this.page(referer), out = this.parseVideos(html, referer);
    if (!out.length) throw Park.error('UNSUPPORTED', '此影片没有可用的 MP4 清晰度');
    return out;
  },
});

Park.enableUpdateSubscriptions(Park.__pending, {dimensions: [
  {key: 'search', label: '搜索关键词', hint: '输入作品、作者或话题关键词'},
]});
