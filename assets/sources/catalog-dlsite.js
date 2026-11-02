Park.register({
  key: 'catalog-dlsite', name: 'DLsite', version: '0.0.7', minAppVersion: '0.10.8',
  type: 'comic', category: 'doujin', metadataOnly: true,
  description: '排行榜与作品资料', homepage: 'https://www.dlsite.com/',
  domains: ['dlsite.com', 'dlsite.jp'], network: { vpnHint: true },
  imageHeaders: { Referer: 'https://www.dlsite.com/' },
  defaultFeed: 'maniax',
  feeds: [['maniax', '同人漫画'], ['books', '成年漫画']].map(([key,label]) => ({key, label, options: [
    {key: 'sort', label: '排序', dynamic: true, default: 'trend'},
    {key: 'work_type_category', label: '类型', dynamic: true, default: ''},
    {key: 'genre', label: '分类', dynamic: true, default: ''},
  ]})),
  searchFilters: [
    {key: 'floor', label: '分类', default: 'maniax', values: [{value: 'maniax', label: '同人漫画'}, {value: 'books', label: '成年漫画'}]},
    {key: 'sort', label: '排序', dynamic: true, dependsOn: ['floor'], default: 'trend'},
    {key: 'work_type_category', label: '类型', dynamic: true, dependsOn: ['floor'], default: ''},
    {key: 'genre', label: '分类', dynamic: true, dependsOn: ['floor'], default: ''},
  ],
  async filterOptions(req) {
    const floor=req.feed || req.values?.floor || 'maniax';
    if (!['maniax','books'].includes(floor)) throw Park.error('CONFIG','未知列表');
    const body = await this.http.text(`${this.homepage}${floor}/fsr/=/work_category/${floor==='books'?'books':'doujin'}/order/release_d/per_page/30/`);
    const key = req.filter === 'sort' ? 'order' : req.filter;
    if (!['order', 'work_type_category', 'genre'].includes(key)) throw Park.error('CONFIG', '筛选参数无效');
    const match = body.match(new RegExp('"' + key + '":(\\[[\\s\\S]*?\\])'));
    if (!match) throw Park.error('PARSE', '动态筛选选项无效');
    const values = new Map();
    if (key !== 'order') values.set('', {value: '', label: '全部'});
    for (const item of JSON.parse(match[1])) {
      if (item.val != null && item.text) values.set(String(item.val), {value: String(item.val), label: item.text});
    }
    if (values.size < 2) throw Park.error('PARSE', '动态筛选选项无效');
    return [...values.values()];
  },
  async browse(keyword, req = {}) {
    const page = Math.max(1, Number(req.page) || 1), filters = req.filters || req.options || {};
    const floor=req.floor || filters.floor || 'maniax';
    if (!['maniax','books'].includes(floor)) throw Park.error('CONFIG','未知列表');
    let path = `${floor}/fsr/=/work_category/${floor==='books'?'books':'doujin'}/order/${encodeURIComponent(filters.sort || 'trend')}/per_page/30/page/${page}/`;
    if (keyword) path += `keyword/${encodeURIComponent(keyword)}/`;
    for (const key of ['work_type_category', 'genre']) if (filters[key]) path += `${key}/${encodeURIComponent(filters[key])}/`;
    const response = this.http.ensureOk(await this.http.get(this.homepage + path));
    const doc = Park.html.parse(response.body), seen = new Set();
    if (/一致する作品は見つかりませんでした|条件に一致する作品はありません/.test(Park.html.text(doc.querySelector('.work_not_found .lead')))) return {items:[],page,hasNext:false};
    const items = [...doc.querySelectorAll('.work_name a[href]')].map(a => {
      const url = Park.url.parse(a.getAttribute('href'), this.homepage, this.domains);
      const id = url?.pathname.match(/\/product_id\/((?:RJ|BJ)\d+)\.html$/)?.[1];
      if (!id || seen.has(id)) return null;
      seen.add(id);
      const row = a.closest('tr, .search_result_img_box_inner, .work_1col'), img = row?.querySelector('img');
      const candidates = row?.querySelector('thumb-with-ng-filter, thumb-with-ng-filter-block')?.getAttribute(':thumb-candidates') || '';
      const image = img?.getAttribute('data-src') || img?.getAttribute('src') || '';
      const cover = candidates.match(/['"]((?:https?:)?\/\/[^'"]+)['"]/)?.[1] || (/^(?:https?:)?\/\//.test(image) ? image : '');
      return {id, code: id, workCode: id, title: Park.html.text(a), cover: cover ? new URL(cover, this.homepage).href : '', url: url.href};
    }).filter(Boolean);
    if (!items.length && !/該当する作品がありません|作品が見つかりません|検索条件に一致する作品|見つかりませんでした/.test(Park.html.text(doc.body))) throw Park.error('PARSE', '作品资料无效');
    const hasNext = [...doc.querySelectorAll('a[href]')].some(a => {
      const url = Park.url.parse(a.getAttribute('href'), this.homepage, this.domains);
      return url?.pathname.includes('/fsr/') && Number(url.pathname.match(/\/page\/(\d+)/)?.[1]) === page + 1;
    });
    return {items, page, hasNext};
  },
  async feed(floor, req) { return this.browse('', {...req,floor}); },
  async search(req) { return this.browse(req.keyword, req); },
  rankings: [['maniax', '同人漫画'], ['books', '成年漫画']].map(([key, label]) => ({
    key, label, category: 'doujin', section: 'market', metric: '官方销量榜',
    options: [{ key: 'period', label: '周期', default: 'week', values: [
      { value: 'day', label: '日榜' }, { value: 'week', label: '周榜' },
      { value: 'month', label: '月榜' }, { value: 'total', label: '总榜' },
    ] }],
  })),
  async comments(value, req = {}) {
    const id = String(value), page = Math.max(1, Math.floor(Number(req.page) || 1));
    if (!/^(?:RJ|BJ)\d+$/.test(id)) throw Park.error('NOT_FOUND', '作品编号无效');
    if (req.parentId) return {items: [], hasNext: false};
    const floor = id.startsWith('BJ') ? 'books' : 'maniax';
    const data = await this.http.json(this.homepage + floor + '/api/review', {params: {
      product_id: id, order: 'regist_d', limit: 10, page, locale: 'ja_JP',
    }});
    if (!data.is_success || !Array.isArray(data.review_list)) throw Park.error('PARSE', '评论数据无效');
    const items = data.review_list.map(c => {
      if (!c.member_review_id || typeof c.review_text !== 'string') throw Park.error('PARSE', '评论数据无效');
      return {id: String(c.member_review_id), author: {name: String(c.nick_name || '')},
        body: Park.comments.html(c.review_text, this.homepage), date: c.regist_date || c.entry_date,
        likes: Number(c.good_review) || 0, rating: Number(c.rate_num ?? c.rate) || undefined,
        spoiler: c.spoiler === true || String(c.spoiler) === '1'};
    }).filter(c => c.body.length);
    return {items, hasNext: data.review_list.length === 10};
  },

  async metadataSearch(keyword) {
    if (!String(keyword || '').trim()) throw Park.error('CONFIG', '请输入关键词');
    return (await this.browse(keyword, {page: 1})).items;
  },
  async metadataDetail(value, context = {}) {
    const id = String(value);
    if (!/^(?:RJ|BJ)\d+$/.test(id)) throw Park.error('NOT_FOUND', '作品编号无效');
    let url = `${this.homepage}${id.startsWith('BJ') ? 'books' : 'maniax'}/work/=/product_id/${id}.html`;
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
    const title = text("#work_name");
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
    for (const row of doc.querySelectorAll("#work_outline tr, #work_maker tr")) {
      const label = Park.html.text(row.querySelector('th')).replace(/[:：\s]/g, '');
      const value = Park.html.text(row.querySelector('td'));
      if (label && value) fields[label] = value;
    }
    const field = pattern => Object.entries(fields).find(([key]) => pattern.test(key))?.[1] || '';
    return { id, code: id, title, url, cover: image(meta('og:image')),
      description: text(".work_parts_container") || meta('og:description'),
      studio: field(/サークル名|著者/), releaseDate: field(/販売日/),
      authors: field(/作者|作家|著者/) ? [field(/作者|作家|著者/)] : [],
      duration: field(/収録時間|再生時間|長度|时长/),
      series: field(/シリーズ|系列/),
      actors: [...new Set([...doc.querySelectorAll(".detail_data a[href*=\"actor\"], main a[href*=\"/actor/\"]")].map(Park.html.text).filter(Boolean))],
      tags: [...new Set([...doc.querySelectorAll("#work_outline a[href*=\"/genre/\"]")].map(Park.html.text).filter(Boolean))],
      images: [...new Set(([...doc.querySelectorAll('[data-src]')].map(e => e.getAttribute('data-src')).filter(v => /_smp\d+\./.test(v))).map(image).filter(Boolean))].slice(0, 100) };
  },
  async ranking(floor, req) {
    if (Number(req.page) > 1) return { items: [], page: Number(req.page), hasNext: false };
    const period = req.options?.period || 'week';
    const url = floor === 'maniax'
      ? `${this.homepage}maniax/ranking/${period}?category=comic&sub=MNG&sort=sale`
      : `${this.homepage}books/ranking?term=${period}&sort=sale`;
    const doc = Park.html.parse(await this.http.text(url));
    const rows = [...doc.querySelectorAll('tr, .ranking_top_worklist_item')];
    const seen = new Set();
    const items = rows.map((row) => {
      const a = row.querySelector('.work_name a[href]'), href = a?.getAttribute('href') || '';
      const match = /product_id\/((?:RJ|BJ)\d+)\.html$/.exec(href);
      const rank = Number(Park.html.text(row.querySelector('.rank_no, .rank i')));
      if (!match || !rank || seen.has(match[1])) return null;
      seen.add(match[1]);
      const thumb = row.querySelector('thumb-with-ng-filter');
      const candidates = thumb?.getAttribute(':thumb-candidates') || '';
      const image = candidates.match(/['"]((?:https?:)?\/\/[^'"]+)['"]/)?.[1];
      return { id: match[1], rank, title: Park.html.text(a), keyword: Park.html.text(a),
        subtitle: Park.html.text(row.querySelector('.maker_name')),
        cover: image ? new URL(image, this.homepage).href : '', url: href };
    }).filter(Boolean);
    if (!items.length || items.some(row => !row.cover)) throw Park.error('PARSE', '排行榜解析失败');
    return { items, page: 1, hasNext: false };
  },
});
