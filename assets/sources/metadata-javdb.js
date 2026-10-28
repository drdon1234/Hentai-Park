Park.register({
  key: 'metadata-javdb', name: 'JavDB', version: '0.0.1', minAppVersion: '0.10.0',
  type: 'video', category: 'jav', metadataOnly: true,
  description: '作品资料与磁链', homepage: 'https://javdb.com/',
  domains: ['javdb.com'],
  network: {
    mode: 'browser', origin: 'https://javdb.com', vpnHint: true,
    confirmation: {
      selector: '.over18-modal.is-active',
      readySelector: 'html:not(:has(.over18-modal.is-active)) :is(.movie-list, .movie-panel-info, .empty-message)',
      requiredCookies: ['_jdb_session'],
      auto: { clickSelector: '.over18-modal.is-active a[href^="/over18?respond=1"]' },
      message: '站点年龄确认未自动完成，请重试',
    },
  },
  imageHeaders: { Referer: 'https://javdb.com/' },
  i18n: {
    'zh-Hant': { '作品资料与磁链': '作品資料與磁鏈' },
    ja: { '作品资料与磁链': '作品情報とマグネットリンク' },
    ko: { '作品资料与磁链': '작품 정보 및 마그넷 링크' },
    en: { '作品资料与磁链': 'Work information and magnet links' },
    es: { '作品资料与磁链': 'Información de obras y enlaces magnet' },
    ru: { '作品资料与磁链': 'Сведения о произведениях и magnet-ссылки' },
    ar: { '作品资料与磁链': 'معلومات الأعمال وروابط ماغنت' },
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
    if (doc.querySelector('form[action="/sessions"]') && !doc.querySelector('.movie-list, .movie-panel-info')) {
      throw Park.error('CONFIRM_REQUIRED', '需要登录', { url: response.url || url });
    }
    return doc;
  },
  async metadataSearch(value) {
    const keyword = String(value || '').trim();
    if (!keyword || keyword.length > 256) throw Park.error('CONFIG', '请输入关键词');
    const doc = await this.page(`${this.homepage}search?q=${encodeURIComponent(keyword)}&f=all`, { empty404: true });
    if (!doc) return [];
    const seen = new Set();
    const items = [...doc.querySelectorAll('.movie-list a.box[href*="/v/"]')].map(row => {
      const url = Park.url.parse(row.getAttribute('href'), this.homepage, this.domains);
      const id = url?.pathname.match(/^\/v\/([a-z0-9]{2,32})\/?$/i)?.[1];
      const code = Park.html.text(row.querySelector('.video-title strong'));
      const title = row.getAttribute('title') || Park.html.text(row.querySelector('.video-title'));
      if (!id || !code || !title || seen.has(id)) return null;
      seen.add(id);
      const img = row.querySelector('img');
      return { id, code, title, url: url.href, cover: this.image(img?.getAttribute('data-src') || img?.getAttribute('src')) };
    }).filter(Boolean);
    if (!items.length && !doc.querySelector('.empty-message')) throw Park.error('PARSE', '作品资料无效');
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
    const code = fields['番號'] || fields['番号'];
    const title = Park.html.text(doc.querySelector('.video-detail .origin-title')) ||
      Park.html.text(doc.querySelector('.video-detail .current-title'));
    if (!code || !title) throw Park.error('PARSE', '作品资料无效');
    const names = selector => [...new Set([...doc.querySelectorAll(selector)].map(Park.html.text).filter(Boolean))];
    const detail = { id, code, title, url,
      cover: this.image(doc.querySelector('.video-cover')?.getAttribute('src')),
      releaseDate: fields['日期'] || '', duration: fields['時長'] || fields['时长'] || '',
      director: fields['導演'] || fields['导演'] || '', studio: fields['片商'] || '',
      publisher: fields['發行商'] || fields['发行商'] || '', series: fields['系列'] || '',
      rating: fields['評分'] || fields['评分'] || '',
      actors: names('.movie-panel-info a[href^="/actors/"]'),
      tags: names('.movie-panel-info a[href^="/tags"]'),
      images: [...new Set([...doc.querySelectorAll('.preview-images a.tile-item[href]')]
        .map(row => this.image(row.getAttribute('href'))).filter(Boolean))],
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
      error: restricted ? 'CONFIRM_REQUIRED' : doc.querySelector('#magnets-content') ? '' : 'PARSE' });
    while (this.details.size > 10) this.details.delete(this.details.keys().next().value);
    return detail;
  },
  async metadataMagnets(value) {
    const id = this.identity(value);
    if (!this.details?.has(id)) await this.metadataDetail(id);
    const result = this.details.get(id);
    if (result.error) throw Park.error(result.error, result.error === 'CONFIRM_REQUIRED' ? '需要登录' : '作品资料无效', { url: `${this.homepage}v/${id}` });
    return result.magnets;
  },
});
