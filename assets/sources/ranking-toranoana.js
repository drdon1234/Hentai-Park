Park.register({
  key: 'ranking-toranoana', name: '虎之穴', version: '0.0.1',
  type: 'comic', category: 'doujin', rankingOnly: true,
  description: '官方销量榜', homepage: 'https://ec.toranoana.jp/',
  domains: ['toranoana.jp'], network: { vpnHint: true },
  imageHeaders: { Referer: 'https://ec.toranoana.jp/' },
  rankings: [{ key: 'doujin', label: '同人漫画', category: 'doujin', metric: '官方销量榜',
    options: [{ key: 'period', label: '周期', default: 'weekly', values: [
      { value: 'daily', label: '日榜' }, { value: 'weekly', label: '周榜' }, { value: 'monthly', label: '月榜' },
    ] }],
  }],
  async ranking(_, req) {
    if (Number(req.page) > 1) return { items: [], page: Number(req.page), hasNext: false };
    const doc = Park.html.parse(await this.http.text(`${this.homepage}tora_r/ec/cot/ranking/${req.options?.period || 'weekly'}/all/`));
    const items = [...doc.querySelectorAll('.product-list-item')].map((row) => {
      const a = row.querySelector('.product-list-title a[href]'), href = a?.getAttribute('href') || '';
      const id = /^\/tora_r\/ec\/item\/(\d{12})\/$/.exec(href)?.[1];
      const rank = Number(Park.html.text(row.querySelector('.ranking-no')).match(/\d+/)?.[0]);
      if (!id || !rank) return null;
      const image = row.querySelector('.product-list-img img');
      return { id, rank, title: Park.html.text(a), keyword: Park.html.text(a),
        subtitle: Park.html.text(row.querySelector('.product-list-name')),
        cover: image?.getAttribute('data-src') || image?.getAttribute('src') || '',
        url: new URL(href, this.homepage).href };
    }).filter(Boolean);
    if (!items.length) throw Park.error('PARSE', '排行榜解析失败');
    return { items, page: 1, hasNext: false };
  },
});
