Park.register({
  key: 'ranking-fc2', name: 'FC2', version: '0.0.1',
  type: 'video', category: 'jav', rankingOnly: true,
  description: '官方销量榜', homepage: 'https://adult.contents.fc2.com/',
  domains: ['fc2.com'], network: { vpnHint: true },
  rankings: [{ key: 'sales', label: 'FC2', category: 'jav', metric: '官方销量榜',
    options: [{ key: 'period', label: '周期', default: 'weekly', values: [
      { value: 'realtime', label: '实时' }, { value: 'daily', label: '日榜' },
      { value: 'weekly', label: '周榜' }, { value: 'monthly', label: '月榜' },
      { value: 'yearly', label: '年榜' },
    ] }],
  }],
  async ranking(_, req) {
    const page = Math.max(1, Number(req.page) || 1);
    if (page > 5) return { items: [], page, hasNext: false };
    const url = `${this.homepage}ranking/article/${req.options?.period || 'weekly'}?page=${page}`;
    const doc = Park.html.parse(await this.http.text(url));
    const rows = [...doc.querySelectorAll('.c-rankbox-100 > .c-ranklist-110')];
    const items = rows.map((row) => {
      const title = row.querySelector('.c-ranklist-110_info h3');
      const anchor = row.matches('a[href]') ? row : title?.querySelector('a[href]');
      const match = /\/article_search\.php\?id=(\d{2,9})$/.exec(anchor?.getAttribute('href') || '');
      const rank = Number(Park.html.text(row.querySelector('[class^="c-ranklabel-"]')).match(/^\d+/)?.[0]);
      if (!match || !rank) return null;
      const id = match[1], image = row.querySelector('.c-ranklist-110_tmb img');
      return {
        id, rank, title: Park.html.text(title), keyword: `FC2-PPV-${id}`,
        subtitle: Park.html.text(row.querySelector('.c-ranklist-110_own')),
        cover: new URL(image?.getAttribute('src') || '', this.homepage).href,
        url: `${this.homepage}article/${id}/`,
      };
    }).filter(Boolean);
    if (!items.length) throw Park.error('PARSE', '排行榜解析失败');
    return { items, page, hasNext: page < 5 && rows.length === 20 };
  },
});
