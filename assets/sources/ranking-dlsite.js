Park.register({
  key: 'ranking-dlsite', name: 'DLsite', version: '0.0.2', minAppVersion: '0.9.2',
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
