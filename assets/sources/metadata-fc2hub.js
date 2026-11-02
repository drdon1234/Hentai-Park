Park.register({
  key: 'metadata-fc2hub', name: 'FC2HUB', version: '0.0.1', minAppVersion: '0.10.9',
  type: 'video', category: 'jav', metadataOnly: true,
  description: 'FC2作品资料', homepage: 'https://fc2hub.net/',
  domains: ['fc2hub.net'], network: { vpnHint: true },
  imageHeaders: { Referer: 'https://fc2hub.net/' },
  i18n: {
    'zh-Hant': { 'FC2作品资料': 'FC2作品資料' },
    ja: { 'FC2作品资料': 'FC2作品情報' },
    ko: { 'FC2作品资料': 'FC2 작품 정보' },
    en: { 'FC2作品资料': 'FC2 work information' },
    es: { 'FC2作品资料': 'Información de obras FC2' },
    ru: { 'FC2作品资料': 'Сведения о произведениях FC2' },
    ar: { 'FC2作品资料': 'معلومات أعمال FC2' },
  },
  defaultFeed: 'latest',
  feeds: [{ key: 'latest', label: '最新', options: [
    { key: 'category', label: '分类', dynamic: true, default: '' },
  ] }],

  productUrl(value) {
    const url = Park.url.parse(value, this.homepage, this.domains);
    return url?.hostname === 'fc2hub.net' && /^\/fc2ppv-\d{2,9}-[^/]+\/$/i.test(url.pathname) ? url : null;
  },
  image(value) {
    const url = Park.url.parse(value, this.homepage, this.domains);
    return url?.hostname === 'fc2hub.net' && url.pathname.startsWith('/wp-content/uploads/') ? url.href : '';
  },
  async filterOptions(req) {
    if (req.scope !== 'feed' || req.feed !== 'latest' || req.filter !== 'category') {
      throw Park.error('CONFIG', '筛选参数无效');
    }
    const doc = Park.html.parse(await this.http.text(this.homepage));
    const options = new Map([['', { value: '', label: '全部' }]]);
    for (const a of doc.querySelectorAll('nav a[href], .menu a[href]')) {
      const url = Park.url.parse(a.getAttribute('href'), this.homepage, this.domains);
      const slug = url?.pathname.match(/^\/category\/([a-z0-9-]+)\/$/)?.[1];
      if (url?.hostname === 'fc2hub.net' && slug && slug !== 'sone') {
        options.set(slug, { value: slug, label: Park.html.text(a) });
      }
    }
    if (options.size < 2) throw Park.error('PARSE', '动态筛选选项无效');
    return [...options.values()];
  },
  async listing(url, page) {
    const doc = Park.html.parse(await this.http.text(url)), seen = new Set();
    const rows = [...doc.querySelectorAll('#content .content-loop .hentry')];
    if (!rows.length && !doc.querySelector('#content .content-loop .no-results')) {
      throw Park.error('PARSE', '作品资料无效');
    }
    const items = rows.map(row => {
      const a = row.querySelector('.entry-title a[href]'), link = this.productUrl(a?.getAttribute('href'));
      const id = link?.pathname.match(/^\/fc2ppv-(\d{2,9})-/i)?.[1];
      if (!id || seen.has(id)) return null;
      seen.add(id);
      const img = row.querySelector('.thumbnail-wrap img');
      const variants = (img?.getAttribute('srcset') || '').split(',').map(part => {
        const [address, width] = part.trim().split(/\s+/);
        return { address, width: Number.parseInt(width) || 0 };
      }).sort((a, b) => b.width - a.width);
      const cover = variants.map(v => this.image(v.address)).find(Boolean) || this.image(img?.getAttribute('src'));
      const title = Park.html.text(a);
      if (!title) throw Park.error('PARSE', '作品资料无效');
      return { id, code: 'FC2-PPV-' + id, workCode: 'FC2-PPV-' + id, title, cover, url: link.href };
    }).filter(Boolean);
    const next = doc.querySelector('a.next.page-numbers[href]');
    const target = Park.url.parse(next?.getAttribute('href'), this.homepage, this.domains);
    const current = new URL(url);
    return { items, page, hasNext: target?.hostname === 'fc2hub.net' &&
      target.searchParams.get('s') === current.searchParams.get('s') &&
      target.pathname.replace(/page\/\d+\/$/, '') === current.pathname.replace(/page\/\d+\/$/, '') &&
      Number(target.pathname.match(/\/page\/(\d+)\/$/)?.[1]) === page + 1 };
  },
  async feed(key, req) {
    if (key !== 'latest') throw Park.error('CONFIG', '未知列表');
    const page = Math.max(1, Number(req.page) || 1), category = req.options?.category || '';
    if (category && !/^[a-z0-9-]+$/.test(category)) throw Park.error('CONFIG', '筛选参数无效');
    const path = (category ? 'category/' + category + '/' : '') + (page > 1 ? 'page/' + page + '/' : '');
    return this.listing(new URL(path, this.homepage).href, page);
  },
  async search(req) {
    const page = Math.max(1, Number(req.page) || 1);
    const keyword = String(req.keyword || '').trim().replace(/^FC2\s*[-_ ]*\s*(?:PPV\s*[-_ ]*)?(\d+)$/i, '$1');
    if (!keyword) return { items: [], page, hasNext: false };
    const url = new URL(page > 1 ? 'page/' + page + '/' : '', this.homepage);
    url.searchParams.set('s', keyword);
    return this.listing(url.href, page);
  },
  async metadataSearch(keyword) {
    return (await this.search({ keyword, page: 1 })).items;
  },
  async metadataDetail(value, context = {}) {
    const id = String(value);
    if (!/^\d{2,9}$/.test(id)) throw Park.error('NOT_FOUND', '作品编号无效');
    let url;
    if (context.url) {
      url = this.productUrl(context.url);
      if (url?.pathname.match(/^\/fc2ppv-(\d{2,9})-/i)?.[1] !== id) {
        throw Park.error('CONFIG', '作品编号无效');
      }
    } else {
      const item = (await this.metadataSearch(id)).find(item => item.id === id);
      if (!item) throw Park.error('NOT_FOUND', '内容不存在或已被删除');
      url = new URL(item.url);
    }
    const doc = Park.html.parse(await this.http.text(url.href));
    const meta = name => doc.querySelector('meta[property="' + name + '"]')?.getAttribute('content') || '';
    const title = Park.html.text(doc.querySelector('h1.post-title'));
    const canonical = this.productUrl(meta('og:url'));
    if (!title || canonical?.pathname.match(/^\/fc2ppv-(\d{2,9})-/i)?.[1] !== id) {
      throw Park.error('PARSE', '作品资料无效');
    }
    return { id, code: 'FC2-PPV-' + id, title, url: canonical.href,
      cover: this.image(meta('og:image')), description: meta('og:description') };
  },
});
