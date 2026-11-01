Park.register({
  key: 'ranking-dlsite', name: 'DLsite', version: '0.0.4', minAppVersion: '0.10.8',
  type: 'comic', category: 'doujin', rankingOnly: true,
  description: '官方销量榜', homepage: 'https://www.dlsite.com/',
  domains: ['dlsite.com', 'dlsite.jp'], network: { vpnHint: true },
  imageHeaders: { Referer: 'https://www.dlsite.com/' },
  rankings: [['maniax', '同人漫画'], ['books', '成年漫画']].map(([key, label]) => ({
    key, label, category: 'doujin', metric: '官方销量榜',
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
