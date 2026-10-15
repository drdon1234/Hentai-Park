Park.register({
  key: 'ranking-javmenu', name: 'JavMenu', version: '0.0.1',
  type: 'video', category: 'jav', rankingOnly: true,
  description: '站内热门', homepage: 'https://javmenu.com/',
  domains: ['javmenu.com'], network: { vpnHint: true },
  rankings: [{ key: 'censored', label: 'JAV', section: 'site', category: 'jav', metric: '站内热门',
    options: [{ key: 'period', label: '周期', default: 'week', values: [
      { value: 'day', label: '日榜' }, { value: 'week', label: '周榜' }, { value: 'month', label: '月榜' },
    ] }],
  }],
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
