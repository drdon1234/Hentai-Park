Park.register({
  i18n: {
    "zh-Hant": {"频道": "頻道"},
    ja: {"频道": "チャンネル"},
    ko: {"频道": "채널"},
    en: {"频道": "Channel"},
    es: {"频道": "Canal"},
    ru: {"频道": "Канал"},
    ar: {"频道": "القناة"},
  },
  key: 'catalog-mgs', name: 'MGStage', version: '0.0.8', minAppVersion: '0.11.0',
  type: 'video', category: 'jav', metadataOnly: true,
  description: '排行榜与作品资料', homepage: 'https://www.mgstage.com/',
  domains: ['mgstage.com'],
  network: { mode: 'browser', origin: 'https://www.mgstage.com', vpnHint: true,
    confirmation: { selector: '#entry_column:has(#AC), body#entry:has(a[href="javascript:goSite();"])',
      readySelector: '#center_column, .detail_data, #header_nav', requiredCookies: ['adc'],
      auto: { clickSelector: '#entry_column #AC, body#entry a[href="javascript:goSite();"]' }, message: '站点年龄确认未自动完成，请重试' },
  },
  defaultFeed: 'catalog',
  feeds: [{key: 'catalog', label: '全部', options: [
    {key: 'sort', label: '排序', dynamic: true, default: 'popular'},
    {key: 'genre', label: '分类', dynamic: true, default: ''},
    {key: 'maker', label: '制作商', dynamic: true, default: ''},
  ]}],
  searchFilters: [
    {key: 'sort', label: '排序', dynamic: true, default: 'popular'},
    {key: 'genre', label: '分类', dynamic: true, default: ''},
    {key: 'maker', label: '制作商', dynamic: true, default: ''},
  ],
  async filterOptions(req) {
    const base = 'https://sp.mgstage.com/api/n/search/';
    if (req.filter === 'sort') {
      const data = await this.http.json(base + 'search_parts.php?type=top');
      if (!Array.isArray(data.sort_list) || !data.sort_list.length) throw Park.error('PARSE', '动态筛选选项无效');
      return data.sort_list.map(row => ({value: row.value, label: row.name}));
    }
    if (!['genre', 'maker'].includes(req.filter)) throw Park.error('CONFIG', '筛选参数无效');
    const data = await this.http.json(base + 'facet/?type=top&facet_key=' + req.filter);
    const rows = data.facet?.[req.filter]?.word;
    if (!Array.isArray(rows) || !rows.length) throw Park.error('PARSE', '动态筛选选项无效');
    return [{value: '', label: '全部'}, ...rows.map(row => ({value: String(row.id), label: row.name}))];
  },
  async browse(keyword, req = {}) {
    const page = Math.max(1, Number(req.page) || 1), options = req.filters || req.options || {};
    const query = new URLSearchParams({type: 'top', page: String(page), sort: options.sort || 'popular'});
    if (keyword) query.set('search_word', keyword);
    for (const key of ['genre', 'maker']) if (options[key]) query.set(key, options[key]);
    const data = await this.http.json('https://sp.mgstage.com/api/n/search/index.php?' + query);
    if (!Array.isArray(data.search_result) || !Number.isFinite(Number(data.all_pages_count))) throw Park.error('PARSE', '作品资料无效');
    const items = data.search_result.map(row => {
      const id = String(row.sku || '');
      if (!/^[A-Za-z0-9_-]{2,40}$/.test(id) || !row.name) throw Park.error('PARSE', '作品资料无效');
      return {id, code: id, workCode: id, title: row.name, cover: row.image_path ? new URL(row.image_path, 'https://image.mgstage.com').href : '',
        url: `${this.homepage}product/product_detail/${id}/`};
    });
    return {items, page, hasNext: page < Number(data.all_pages_count)};
  },
  async feed(_, req) { return this.browse('', req); },
  async search(req) { return this.browse(req.keyword, req); },
  async metadataSearch(keyword) { return (await this.browse(keyword, {page: 1})).items; },
  rankings: [{ key: 'sales', label: 'MGStage', category: 'jav', section: 'market', metric: '官方销量榜',
    options: [{ key: 'period', label: '周期', default: 'week', values: [
      { value: 'day', label: '日榜' }, { value: 'week', label: '周榜' }, { value: 'month', label: '月榜' },
    ] }, { key: 'channel', label: '频道', default: '', values: [
      { value: '', label: '全部' }, { value: 'mgs_', label: 'MGS' },
      { value: 'shiroutotv_', label: 'シロウトTV' }, { value: 'nanpatv_', label: 'ナンパTV' },
      { value: 'luxutv_', label: 'ラグジュTV' },
    ] }],
  }],

  async metadataDetail(value, context = {}) {
    const id = String(value);
    if (!/^[A-Za-z0-9_-]{2,40}$/.test(id)) throw Park.error('NOT_FOUND', '作品编号无效');
    let url = `${this.homepage}product/product_detail/${id}/`;
    if (context.url) {
      const supplied = Park.url.parse(context.url, this.homepage, this.domains);
      const expected = new URL(url);
      if (!supplied || !supplied.pathname.includes(id) ||
          (supplied.pathname !== expected.pathname && !/^\/monthly\/(?:shiroutotv|nanpatv|luxutv)\/video\//.test(supplied.pathname))) throw Park.error('CONFIG', '作品编号无效');
      url = supplied.href;
    }
    const response = await this.http.get(url);
    this.http.ensureOk(response);
    const doc = Park.html.parse(response.body);
    const meta = key => doc.querySelector(`meta[property="${key}"]`)?.getAttribute('content') || '';
    const text = selector => selector ? Park.html.text(doc.querySelector(selector)) : '';
    const title = text("h1.tag, #content h1");
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
    for (const row of doc.querySelectorAll(".detail_data tr")) {
      const label = Park.html.text(row.querySelector('th')).replace(/[:：\s]/g, '');
      const value = Park.html.text(row.querySelector('td'));
      if (label && value) fields[label] = value;
    }
    for (const label of doc.querySelectorAll('#detail .info dt')) {
      const value = label.nextElementSibling;
      if (value?.tagName === 'DD') fields[Park.html.text(label).replace(/[:：\s]/g, '')] = Park.html.text(value);
    }
    const field = pattern => Object.entries(fields).find(([key]) => pattern.test(key))?.[1] || '';
    return { id, code: id, title, url, cover: image(meta('og:image')),
      description: text(".detail_txt, #summary > p") || meta('og:description'),
      studio: field(/メーカー/), releaseDate: field(/配信開始日|発売日/),
      duration: field(/収録時間|再生時間|長度|时长/),
      series: field(/シリーズ|系列/),
      actors: [...new Set([...doc.querySelectorAll(".detail_data a[href*=\"actor\"], #detail a[href*=\"actor=\"], main a[href*=\"/actor/\"]")].map(Park.html.text).filter(Boolean))],
      tags: [...new Set([...doc.querySelectorAll(".detail_data a[href*=\"genre\"], #detail a[href*=\"genre=\"]")].map(Park.html.text).filter(Boolean))],
      images: [...doc.querySelectorAll('#sample-photo a.sample_image, a.sample-image-wrap[href^="https:"]')].map(row => ({
        url: image(row.getAttribute('href')),
        thumbnail: image(row.querySelector('img')?.getAttribute('data-src') || row.querySelector('img')?.getAttribute('src')),
      })).filter(row => row.url).slice(0, 100) };
  },
  async ranking(_, req) {
    if (Number(req.page) > 1) return { items: [], page: Number(req.page), hasNext: false };
    const response = await this.http.get(`${this.homepage}ranking/ranking.php?id=${req.options?.channel || ''}${req.options?.period || 'week'}`);
    if (response.status === 403) throw Park.error('BLOCKED', '此榜单可能需要日本地区的 VPN 或代理');
    const doc = Park.html.parse(this.http.ensureOk(response).body);
    const items = [...doc.querySelectorAll('#center_column .rank_list_detail li, #rank_list .ranking-content')].map((row) => {
      const a = row.querySelector('h5 a[href], .ranking-content-r > a[href]'), path = a?.getAttribute('href') || '';
      const match = /^\/(?:product\/product_detail|monthly\/(?:shiroutotv|nanpatv|luxutv)\/video)\/([A-Za-z0-9_-]{2,40})\/?$/.exec(path);
      const rank = Number(Park.html.text(row.querySelector('[class^="ranking_"], .rank-num')).match(/\d+/)?.[0]);
      if (!match || !rank) return null;
      const id = match[1].toUpperCase();
      return { id, rank, title: Park.html.text(row.querySelector('.title') || a), keyword: id,
        cover: row.querySelector('h6 img, .ranking-content-l img')?.getAttribute('src') || '',
        url: new URL(path, this.homepage).href };
    }).filter(Boolean);
    if (!items.length) throw Park.error('PARSE', '排行榜解析失败');
    return { items, page: 1, hasNext: false };
  },
});
