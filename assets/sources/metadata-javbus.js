Park.register({
  key: 'metadata-javbus', name: 'JavBus', version: '0.0.2', minAppVersion: '0.10.0',
  type: 'video', category: 'jav', metadataOnly: true,
  description: '作品资料与磁链', homepage: 'https://www.javbus.com/',
  domains: ['javbus.com'], network: {
    mode: 'browser', origin: 'https://www.javbus.com', vpnHint: true,
    confirmation: {
      selector: '#ageVerify, form:has(input[name^="userAnswers"])',
      readySelector: '#waterfall, .info, .alert, .not-found',
      requiredCookies: ['age'],
      auto: { checkSelector: '#ageVerify #form1 input[type="checkbox"]', clickSelector: '#ageVerify #form1 input[type="submit"]' },
      message: '站点年龄确认未自动完成，请重试',
    },
  },
  imageHeaders: { Referer: 'https://www.javbus.com/' },
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
    if (!/^[a-z0-9][a-z0-9_-]{1,100}$/i.test(id)) throw Park.error('NOT_FOUND', '作品编号无效');
    return id;
  },
  async page(url, { empty404 = false, headers = {} } = {}) {
    const response = await this.http.get(url, { headers });
    if (empty404 && response.status === 404) return null;
    this.http.ensureOk(response);
    const doc = Park.html.parse(response.body);
    if (doc.querySelector('#ageVerify, input[name^="userAnswers"]') ||
        /\/doc\/driver-verify/.test(response.url || '') ||
        /Age Verification JavBus/i.test(Park.html.text(doc.querySelector('title')))) {
      throw Park.error('CONFIRM_REQUIRED', '站点验证暂未完成', { url: response.url || url });
    }
    return { doc, body: response.body };
  },
  async metadataSearch(value) {
    const keyword = String(value || '').trim();
    if (!keyword || keyword.length > 256) throw Park.error('CONFIG', '请输入关键词');
    const page = await this.page(`${this.homepage}search/${encodeURIComponent(keyword)}`, { empty404: true });
    if (!page) return [];
    const seen = new Set();
    const items = [...page.doc.querySelectorAll('a.movie-box, .movie-box a[href]')].map(row => {
      const url = Park.url.parse(row.getAttribute('href'), this.homepage, this.domains);
      const id = url?.pathname.replace(/^\/+|\/+$/g, '');
      if (!id || !/^[a-z0-9][a-z0-9_-]{1,100}$/i.test(id) || seen.has(id)) return null;
      const image = row.querySelector('img');
      const title = image?.getAttribute('title') || image?.getAttribute('alt') || '';
      if (!title.trim()) return null;
      seen.add(id);
      return { id, code: Park.html.text(row.querySelector('date')) || id, title,
        cover: this.image(image?.getAttribute('data-src') || image?.getAttribute('src')), url: url.href };
    }).filter(Boolean);
    if (!items.length && !page.doc.querySelector('#waterfall, .alert, .not-found')) {
      throw Park.error('PARSE', '作品资料无效');
    }
    return items.slice(0, 100);
  },
  async metadataDetail(value) {
    const id = this.identity(value), url = this.homepage + encodeURIComponent(id);
    const { doc, body } = await this.page(url);
    const title = Park.html.text(doc.querySelector('.container h3'));
    const cover = this.image(doc.querySelector('a.bigImage')?.getAttribute('href'));
    if (!title || !doc.querySelector('.info') || !cover) throw Park.error('PARSE', '作品资料无效');
    const fields = {};
    for (const row of doc.querySelectorAll('.info p')) {
      const header = row.querySelector('.header');
      if (!header) continue;
      const label = Park.html.text(header).replace(/[:：\s]/g, '');
      const copy = row.cloneNode(true);
      copy.querySelector('.header')?.remove();
      fields[label] = Park.html.text(copy);
    }
    const names = selector => [...new Set([...doc.querySelectorAll(selector)].map(Park.html.text).filter(Boolean))];
    const images = [...new Set([...doc.querySelectorAll('a.sample-box')]
      .map(row => this.image(row.getAttribute('href'))).filter(Boolean))];
    const vars = {};
    for (const match of body.matchAll(/\bvar\s+(gid|uc|img|lang)\s*=\s*(?:'([^']*)'|"([^"]*)"|(\d+))\s*;/g)) {
      vars[match[1]] = match[2] ?? match[3] ?? match[4];
    }
    this.magnetPages ??= new Map();
    this.magnetPages.set(id, { vars, body });
    while (this.magnetPages.size > 10) this.magnetPages.delete(this.magnetPages.keys().next().value);
    const code = fields['識別碼'] || fields['识别码'];
    if (!code) throw Park.error('PARSE', '作品资料无效');
    return { id, code, title, cover, url,
      releaseDate: fields['發行日期'] || fields['发行日期'] || '',
      duration: fields['長度'] || fields['长度'] || '',
      director: fields['導演'] || fields['导演'] || '',
      studio: fields['製作商'] || fields['制作商'] || '',
      publisher: fields['發行商'] || fields['发行商'] || '',
      series: fields['系列'] || '',
      actors: names('.star-name a, .info a[href*="/star/"]'),
      tags: names('.genre a[href*="/genre/"]'), images };
  },
  parseMagnets(body) {
    const doc = Park.html.parse('<!doctype html><html><body><table>' + body + '</table></body></html>'), unique = new Map();
    for (const row of doc.querySelectorAll('tr')) {
      const link = row.querySelector('a[href^="magnet:?"]');
      if (!link) continue;
      let url;
      try { url = new URL(link.getAttribute('href')); } catch (_) { continue; }
      const topic = url.searchParams.get('xt') || '';
      if (url.protocol !== 'magnet:' || !/^urn:btih:(?:[a-f0-9]{40}|[a-z2-7]{32})$/i.test(topic)) continue;
      const cells = [...row.querySelectorAll('td')];
      const name = Park.html.text(link), key = topic.toUpperCase();
      if (!name || unique.has(key)) continue;
      const labels = [...row.querySelectorAll('.label')].map(Park.html.text).filter(Boolean);
      unique.set(key, { url: url.href, name, size: Park.html.text(cells[1]), date: Park.html.text(cells[2]), tags: labels });
    }
    return [...unique.values()].slice(0, 500);
  },
  async metadataMagnets(value) {
    const id = this.identity(value);
    if (!this.magnetPages?.has(id)) await this.metadataDetail(id);
    const { vars, body } = this.magnetPages.get(id), initial = this.parseMagnets(body);
    if (!/^\d{1,18}$/.test(vars.gid || '') || !vars.img || !/^[01]$/.test(vars.uc || '0')) {
      if (initial.length) return initial;
      throw Park.error('PARSE', '作品资料无效');
    }
    const url = new URL('ajax/uncledatoolsbyajax.php', this.homepage);
    for (const [key, value] of Object.entries({ gid: vars.gid, lang: 'zh', img: vars.img, uc: vars.uc || '0', floor: '1' })) {
      url.searchParams.set(key, value);
    }
    const page = await this.page(url.href, { headers: { Referer: this.homepage + encodeURIComponent(id), 'X-Requested-With': 'XMLHttpRequest' } });
    if (!/<tr\b/i.test(page.body) && !/暫時沒有|暂时没有|No\s+(?:magnet|data|result)/i.test(page.body)) {
      throw Park.error('PARSE', '作品资料无效');
    }
    const results = new Map([...initial, ...this.parseMagnets(page.body)].map(row => [new URL(row.url).searchParams.get('xt').toUpperCase(), row]));
    return [...results.values()].slice(0, 500);
  },
});
