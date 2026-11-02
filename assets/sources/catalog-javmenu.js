Park.register({
  key: 'catalog-javmenu', name: 'JavMenu', version: '0.0.5', minAppVersion: '0.10.8',
  type: 'video', category: 'jav', metadataOnly: true,
  description: '排行榜与作品资料', homepage: 'https://javmenu.com/',
  domains: ['javmenu.com'], network: { vpnHint: true },
  defaultFeed: 'censored',
  feeds: [['censored', '有码'], ['uncensored', '无码'], ['western', '欧美'], ['fc2', 'FC2']].map(([key, label]) => ({key, label,
    options: [
      {key: 'genre', label: '分类', dynamic: true, default: ''},
      {key: 'order', label: '排序', dynamic: true, default: 'update'},
      {key: 'sort', label: '类型', dynamic: true, default: 'all'},
    ]})),
  searchFilters: [
    {key:'order',label:'排序',dynamic:true,default:'update'},
    {key:'sort',label:'类型',dynamic:true,default:'all'},
  ],
  async filterOptions(req) {
    if (req.scope==='search') req={...req,feed:'censored'};
    if (!['censored', 'uncensored', 'western', 'fc2'].includes(req.feed)) throw Park.error('CONFIG', '未知列表');
    const doc = Park.html.parse(await this.http.text(`${this.homepage}zh/${req.feed}/filter`));
    const values = new Map();
    if (req.filter === 'genre') {
      values.set('', {value: '', label: '全部'});
      for (const el of doc.querySelectorAll('[onclick]')) {
        const match = el.getAttribute('onclick').match(/^addFilterParam\('c'\s*,\s*(\d+)\)$/);
        if (match) values.set(match[1], {value: match[1], label: Park.html.text(el)});
      }
    } else {
      if (!['sort', 'order'].includes(req.filter)) throw Park.error('CONFIG', '筛选参数无效');
      for (const el of doc.querySelectorAll('[onclick]')) {
        const match = el.getAttribute('onclick').match(/^addParam\('(sort|order)'\s*,\s*'([a-z]+)'\)$/);
        if (match?.[1] === req.filter) values.set(match[2], {value: match[2], label: Park.html.text(el)});
      }
    }
    if (values.size < 2) throw Park.error('PARSE', '动态筛选选项无效');
    return [...values.values()];
  },
  async browse(url, page) {
    const response = this.http.ensureOk(await this.http.get(url)), doc = Park.html.parse(response.body), seen = new Set();
    const items = [...doc.querySelectorAll('.card')].map(row => {
      const a = row.querySelector('.card-body a[href]'), link = Park.url.parse(a?.getAttribute('href'), this.homepage, this.domains);
      const id = link?.pathname.match(/^\/zh\/([A-Za-z0-9_-]{2,100})$/)?.[1];
      if (!id || seen.has(id)) return null;
      seen.add(id);
      const text = row.querySelector('.card-text'), img = row.querySelector('img.card-img-top');
      return {id, code: id, workCode: id, title: text?.getAttribute('title') || Park.html.text(text) || id,
        cover: img?.getAttribute('data-src') || img?.getAttribute('src') || '', url: link.href};
    }).filter(Boolean);
    if (!items.length && !/没有找到|無搜尋結果|没有搜索|未找到|找不到|沒有找到/.test(Park.html.text(doc.body))) throw Park.error('PARSE', '作品资料无效');
    const target = new URL(url);
    const hasNext = [...doc.querySelectorAll('.pagination a[href]')].some(a => {
      const next = Park.url.parse(a.getAttribute('href'), this.homepage, this.domains);
      return next?.pathname === target.pathname && Number(next.searchParams.get('page')) === page + 1;
    });
    return {items, page, hasNext};
  },
  async feed(key, req) {
    if (!['censored', 'uncensored', 'western', 'fc2'].includes(key)) throw Park.error('CONFIG', '未知列表');
    const page = Math.max(1, Number(req.page) || 1), opts = req.options || {};
    const url = new URL(`zh/${key}/filter`, this.homepage);
    url.searchParams.set('page', page);
    for (const param of ['sort', 'order']) if (opts[param]) url.searchParams.set(param, opts[param]);
    if (opts.genre) url.searchParams.set('c', opts.genre);
    return this.browse(url.href, page);
  },
  async search(req) {
    const page = Math.max(1, Number(req.page) || 1), url = new URL('zh/search', this.homepage);
    url.searchParams.set('wd', String(req.keyword || '').trim());
    url.searchParams.set('page', page);
    for (const key of ['order','sort']) if (req.filters?.[key]) url.searchParams.set(key,req.filters[key]);
    const result=await this.browse(url.href,page);
    // 原站对无匹配查询返回最新作品；不将这批无关内容当作搜索结果。
    const words=String(req.keyword||'').normalize('NFKC').toLocaleLowerCase().split(/\s+/).filter(Boolean);
    const matches=result.items.filter(item=>words.every(word=>(item.id+' '+item.title).normalize('NFKC').toLocaleLowerCase().includes(word)));
    return {...result,items:matches,hasNext:matches.length>0 && result.hasNext};
  },
  async metadataSearch(keyword) { return (await this.search({keyword, page: 1})).items; },
  rankings: [{ key: 'censored', label: 'JAV', section: 'site', category: 'jav', metric: '站内热门',
    options: [{ key: 'period', label: '周期', default: 'week', values: [
      { value: 'day', label: '日榜' }, { value: 'week', label: '周榜' }, { value: 'month', label: '月榜' },
    ] }],
  }],

  async metadataDetail(value, context = {}) {
    const id = String(value);
    if (!/^[A-Za-z0-9_-]{2,100}$/.test(id)) throw Park.error('NOT_FOUND', '作品编号无效');
    let url = `${this.homepage}zh/${id}`;
    if (context.url) {
      const supplied = Park.url.parse(context.url, this.homepage, this.domains);
      const expected = new URL(url);
      if (!supplied || !supplied.pathname.includes(id) ||
          supplied.pathname !== expected.pathname) throw Park.error('CONFIG', '作品编号无效');
      url = supplied.href;
    }
    const response = await this.http.get(url, {});
    this.http.ensureOk(response);
    const doc = Park.html.parse(response.body);
    const meta = key => doc.querySelector(`meta[property="${key}"]`)?.getAttribute('content') || '';
    const text = selector => selector ? Park.html.text(doc.querySelector(selector)) : '';
    const title = text("h1.display-5").replace(/\s*免费AV在线看\s*$/, '');
    if (!title) {
      if (/age[_-]?(?:check|verify)|年齢認証|年齢確認/i.test(response.url + response.body.slice(0, 20000))) {
        throw Park.error('CONFIRM_REQUIRED', '站点验证暂未完成', { url });
      }
      throw Park.error('PARSE', '作品资料无效');
    }
    const image = value => {
      if (!value) return '';
      try { const u = new URL(value, url); return u.protocol === 'https:' && !u.username && !u.password && !u.port ? u.href : ''; }
      catch (_) { return ''; }
    };
    const fields = {};
    for (const row of doc.querySelectorAll('.card-body > .d-flex')) {
      const label = Park.html.text(row.firstElementChild).replace(/[:：\s]/g, '');
      const value = [...row.children].slice(1).map(Park.html.text).join(' ');
      if (label && value) fields[label] = value;
    }
    const field = pattern => Object.entries(fields).find(([key]) => pattern.test(key))?.[1] || '';
    return { id, code: id, title, url, cover: image(meta('og:image')),
      description: text("") || meta('og:description'),
      studio: field(/製作|制作|片商/), releaseDate: field(/發行日期|发行日期|发佈于/),
      duration: field(/収録時間|再生時間|長度|时长/),
      series: field(/シリーズ|系列/),
      actors: [...new Set([...doc.querySelectorAll('a.actress[href*="/actor/"]')].map(Park.html.text).filter(Boolean))],
      tags: [...new Set([...doc.querySelectorAll('a.genre[href]')].map(Park.html.text).filter(Boolean))],
      images: [...new Set(([]).map(image).filter(Boolean))].slice(0, 100) };
  },
  async ranking(_, req) {
    if (Number(req.page) > 1) return { items: [], page: Number(req.page), hasNext: false };
    const doc = Park.html.parse(await this.http.text(`${this.homepage}zh/rank/censored/${req.options?.period || 'week'}`));
    const items = [...doc.querySelectorAll('.card')].map(row => {
      const anchor = row.querySelector('.card-body a[href]');
      const match = /^https:\/\/javmenu\.com\/zh\/([A-Za-z0-9]{2,12}-\d{2,6}[A-Za-z]?)$/.exec(anchor?.getAttribute('href') || '');
      const rank = Number(Park.html.text(row.querySelector('.badge-rank')));
      if (!match || !Number.isInteger(rank) || rank < 1) return null;
      const title = row.querySelector('.card-text'), image = row.querySelector('img.card-img-top');
      const id = match[1].toUpperCase();
      return { id, rank, keyword: id, title: title?.getAttribute('title') || Park.html.text(title) || id,
        subtitle: id, cover: image?.getAttribute('data-src') || '', url: `${this.homepage}zh/${match[1]}` };
    }).filter(Boolean);
    if (!items.length) throw Park.error('PARSE', '排行榜解析失败');
    return { items, page: 1, hasNext: false };
  },
});
