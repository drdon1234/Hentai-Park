Park.register({
  key: 'metadata-javdb', name: 'JavDB', version: '0.0.3', minAppVersion: '0.11.0',
  type: 'video', category: 'jav', metadataOnly: true,
  description: '作品资料与磁链', homepage: 'https://javdb.com/',
  domains: ['javdb.com'],
  network: {
    mode: 'browser', origin: 'https://javdb.com', vpnHint: true,
    confirmation: {
      selector: '.over18-modal.is-active',
      readySelector: 'html:not(:has(.over18-modal.is-active)) :is(.movie-list, .movie-panel-info, .empty-message, form[action="/user_sessions"])',
      requiredCookies: ['over18'],
      auto: { clickSelector: '.over18-modal.is-active a[href^="/over18?respond=1"]' },
      message: '站点年龄确认未自动完成，请重试',
    },
  },
  imageHeaders: { Referer: 'https://javdb.com/' },
  i18n: {
    'zh-Hant': { '欧美': '歐美', '作品资料与磁链': '作品資料與磁鏈' },
    ja: { '作品资料与磁链': '作品情報とマグネットリンク' },
    ko: { '作品资料与磁链': '작품 정보 및 마그넷 링크' },
    en: { '作品资料与磁链': 'Work information and magnet links' },
    es: { '作品资料与磁链': 'Información de obras y enlaces magnet' },
    ru: { '作品资料与磁链': 'Сведения о произведениях и magnet-ссылки' },
    ar: { '作品资料与磁链': 'معلومات الأعمال وروابط ماغنت' },
  },

  defaultFeed: 'latest',
  feeds: [['latest', '全部'], ['censored', '有码'], ['uncensored', '无码'], ['western', '欧美'], ['fc2', 'FC2']]
    .map(([key, label]) => ({key, label, options: [{key: 'native', label: '筛选', dynamic: true, default: ''}]})),
  searchFilters: [{ key: 'native', label: '筛选', dynamic: true, keywordDependent: true, default: '' }],
  nativeFilters(doc, keyword = '') {
    const values = new Map([['', {value: '', label: '全部'}]]);
    for (const row of doc.querySelectorAll('.filters a[href], .filter-panel a[href], .video-filter a[href], .tabs a[href], .filter a[href], .buttons.has-addons a[href]')) {
      const url = Park.url.parse(row.getAttribute('href'), this.homepage, this.domains);
      const label = Park.html.text(row);
      if (!url || !label || !['/', '/search', '/censored', '/uncensored', '/western', '/fc2'].includes(url.pathname)) continue;
      if (keyword && url.pathname !== '/search') continue;
      const params = new URLSearchParams(url.search);
      if (keyword && params.has('f') && !['all', 'playable', 'single', 'code', 'download', 'cnsub', 'preview'].includes(params.get('f'))) continue;
      params.delete('q'); params.delete('page'); params.delete('lm');
      if ([...params.keys()].some(key => !['vft', 'vst', 'f', 'sort', 't', 'sb'].includes(key))) continue;
      if (![...params.keys()].length) continue;
      const value = params.toString();
      values.set(value, {value, label: label.slice(0, 256)});
    }
    // 不用空选项伪装成已支持原站筛选；验证或结构变化直接报错。
    if (values.size < 2) throw Park.error('PARSE', '动态筛选选项无效');
    return [...values.values()].slice(0, 500);
  },
  async filterOptions(req) {
    const keyword = req.scope === 'search' ? String(req.keyword || '').trim() : '';
    const path = ['censored', 'uncensored', 'western', 'fc2'].includes(req.feed) ? req.feed : '';
    const url = keyword ? `${this.homepage}search?q=${encodeURIComponent(keyword)}&f=all` : this.homepage + path;
    return this.nativeFilters(await this.page(url), keyword);
  },
  listItems(doc) {
    const seen = new Set();
    return [...doc.querySelectorAll('.movie-list a.box[href*="/v/"]')].map(row => {
      const url = Park.url.parse(row.getAttribute('href'), this.homepage, this.domains);
      const id = url?.pathname.match(/^\/v\/([a-z0-9]{2,32})\/?$/i)?.[1];
      const code = Park.html.text(row.querySelector('.video-title strong'));
      const title = row.getAttribute('title') || Park.html.text(row.querySelector('.video-title'));
      if (!id || !code || !title || seen.has(id)) return null;
      seen.add(id);
      const img = row.querySelector('img');
      return {id, code, title, url: url.href, cover: this.image(img?.getAttribute('data-src') || img?.getAttribute('src'))};
    }).filter(Boolean);
  },
  async list(req, keyword = '', feed = '') {
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    const url = new URL(keyword ? 'search' : ['censored', 'uncensored', 'western', 'fc2'].includes(feed) ? feed : '', this.homepage);
    if (keyword) { url.searchParams.set('q', keyword); url.searchParams.set('f', 'all'); }
    const selected = (keyword ? req.filters : req.options)?.native;
    if (selected) {
      const doc = await this.page(url.href);
      const allowed = this.nativeFilters(doc, keyword);
      if (!allowed.some(row => row.value === selected)) throw Park.error('CONFIG', '筛选条件无效');
      for (const [key, value] of new URLSearchParams(selected)) url.searchParams.set(key, value);
    }
    url.searchParams.set('page', String(page));
    const doc = await this.page(url.href, {empty404: true});
    if (!doc) return {items: [], page, hasNext: false};
    const items = this.listItems(doc);
    if (!items.length && !doc.querySelector('.empty-message, .movie-list')) throw Park.error('PARSE', '作品资料无效');
    return {items, page, hasNext: !!doc.querySelector('a.pagination-next:not([disabled]), a[rel="next"]')};
  },
  async feed(key, req = {}) { return this.list(req, '', key); },
  async search(req = {}) {
    const keyword = String(req.keyword || '').trim();
    if (!keyword || keyword.length > 256) throw Park.error('CONFIG', '请输入关键词');
    return this.list(req, keyword);
  },
  image(value) {
    if (!value) return '';
    try {
      const url = new URL(value, this.homepage);
      return url.protocol === 'https:' && !url.username && !url.password && !url.port &&
        /^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$/i.test(url.hostname) &&
        !/\.(?:local|localhost)$/i.test(url.hostname) ? url.href : '';
    } catch (_) { return ''; }
  },
  identity(value) {
    const id = String(value || '').trim();
    if (!/^[a-z0-9]{2,32}$/i.test(id)) throw Park.error('NOT_FOUND', '作品编号无效');
    return id;
  },
  async page(url, { empty404 = false } = {}) {
    const response = await this.http.get(url);
    if (empty404 && response.status === 404) return null;
    this.http.ensureOk(response);
    const doc = Park.html.parse(response.body);
    if (doc.querySelector('.over18-modal.is-active')) {
      throw Park.error('CONFIRM_REQUIRED', '站点年龄确认未自动完成，请重试', { url: response.url || url });
    }
    if (/^\s*window\.location\.href\s*=\s*['"]\/login['"];?\s*$/.test(response.body)) {
      throw Park.error('LOGIN_REQUIRED', '需要登录', {url: new URL('/login', this.homepage).href});
    }
    if (doc.querySelector('form[action="/user_sessions"] input[type="password"]') && !doc.querySelector('.movie-list, .movie-panel-info')) {
      throw Park.error('LOGIN_REQUIRED', '需要登录', { url: response.url || url });
    }
    return doc;
  },
  async metadataSearch(value) {
    const keyword = String(value || '').trim();
    if (!keyword || keyword.length > 256) throw Park.error('CONFIG', '请输入关键词');
    const doc = await this.page(`${this.homepage}search?q=${encodeURIComponent(keyword)}&f=all`, { empty404: true });
    if (!doc) return [];
    const items = this.listItems(doc);
    if (!items.length && !doc.querySelector('.empty-message, .movie-list')) throw Park.error('PARSE', '作品资料无效');
    return items.slice(0, 100);
  },
  async metadataDetail(value) {
    const id = this.identity(value), url = `${this.homepage}v/${id}`;
    const doc = await this.page(url), fields = {};
    for (const row of doc.querySelectorAll('.movie-panel-info .panel-block')) {
      const label = Park.html.text(row.querySelector('strong')).replace(/[:：\s]/g, '');
      const val = Park.html.text(row.querySelector('.value'));
      if (label && val) fields[label] = val;
    }
    const code = Park.html.text(doc.querySelector('.movie-panel-info .first-block .value')) || fields['番號'] || fields['番号'] || fields.ID;
    const title = Park.html.text(doc.querySelector('.video-detail .origin-title')) ||
      Park.html.text(doc.querySelector('.video-detail .current-title'));
    if (!code || !title) throw Park.error('PARSE', '作品资料无效');
    const names = selector => [...new Set([...doc.querySelectorAll(selector)].map(Park.html.text).filter(Boolean))];
    const detail = { id, code, title, url,
      cover: this.image(doc.querySelector('.video-cover')?.getAttribute('src')),
      releaseDate: fields['日期'] || fields['ReleasedDate'] || '', duration: fields['時長'] || fields['时长'] || fields.Duration || '',
      director: fields['導演'] || fields['导演'] || fields.Director || '', studio: fields['片商'] || fields.Maker || '',
      publisher: fields['發行商'] || fields['发行商'] || fields.Publisher || '', series: fields['系列'] || fields.Series || '',
      rating: fields['評分'] || fields['评分'] || fields.Rating || '',
      actors: names('.movie-panel-info a[href^="/actors/"]'),
      tags: names('.movie-panel-info a[href^="/tags"]'),
      images: [...doc.querySelectorAll('.preview-images a.tile-item[href]')].map(row => ({
        url: this.image(row.getAttribute('href')),
        thumbnail: this.image(row.querySelector('img')?.getAttribute('data-src') || row.querySelector('img')?.getAttribute('src')),
      })).filter(row => row.url),
    };
    const magnets = new Map();
    for (const row of doc.querySelectorAll('#magnets-content .item')) {
      const link = row.querySelector('.magnet-name a[href^="magnet:?"]');
      let magnet;
      try { magnet = new URL(link?.getAttribute('href')); } catch (_) { continue; }
      const topic = magnet.searchParams.get('xt') || '';
      if (magnet.protocol !== 'magnet:' || !/^urn:btih:(?:[a-f0-9]{40}|[a-z2-7]{32})$/i.test(topic)) continue;
      const name = Park.html.text(link.querySelector('.name'));
      if (!name) continue;
      magnets.set(topic.toUpperCase(), { url: magnet.href, name,
        size: Park.html.text(row.querySelector('.meta')),
        date: Park.html.text(row.querySelector('.date .time')),
        tags: [...row.querySelectorAll('.tag')].map(Park.html.text).filter(Boolean) });
    }
    // 登录限制与空磁链应分别呈现，不能用空数组掩盖页面结构变化。
    const restricted = !doc.querySelector('#magnets-content') &&
      [...doc.querySelectorAll('a[href="/login"]')].some(row => row.closest('#magnets, #magnetTab, .magnet-tab'));
    this.details ??= new Map();
    this.details.set(id, { magnets: [...magnets.values()].slice(0, 500),
      error: restricted ? 'LOGIN_REQUIRED' : doc.querySelector('#magnets-content') ? '' : 'PARSE' });
    while (this.details.size > 10) this.details.delete(this.details.keys().next().value);
    return detail;
  },
  async metadataMagnets(value) {
    const id = this.identity(value);
    if (!this.details?.has(id)) await this.metadataDetail(id);
    const result = this.details.get(id);
    if (result.error) throw Park.error(result.error, result.error === 'LOGIN_REQUIRED' ? '需要登录' : '作品资料无效', { url: `${this.homepage}v/${id}` });
    return result.magnets;
  },
});
