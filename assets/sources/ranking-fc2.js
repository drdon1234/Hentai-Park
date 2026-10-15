Park.register({
  key: 'ranking-fc2', name: 'FC2', version: '0.0.3',
  type: 'video', category: 'jav', rankingOnly: true,
  description: '官方销量榜', homepage: 'https://adult.contents.fc2.com/',
  domains: ['fc2.com'], network: { vpnHint: true },
  rankings: [{ key: 'sales', label: 'FC2', category: 'jav', metric: '官方销量榜',
    options: [{ key: 'period', label: '周期', default: 'weekly', values: [
      { value: 'realtime', label: '实时' }, { value: 'daily', label: '日榜' },
      { value: 'weekly', label: '周榜' }, { value: 'monthly', label: '月榜' },
      { value: 'yearly', label: '年榜' },
    ] }],
  }, { key: 'sellers', label: '卖家榜', kind: 'seller', category: 'jav', metric: '官方卖家榜',
    options: [{ key: 'period', label: '周期', default: 'monthly', values: [
      { value: 'monthly', label: '上月' }, { value: 'yearly', label: '年榜' },
    ] }],
  }],
  async ranking(board, req) {
    const page = Math.max(1, Number(req.page) || 1);
    if (page > 5) return { items: [], page, hasNext: false };
    const url = board === 'sellers'
      ? `${this.homepage}ranking/writer/${req.options?.period === 'yearly' ? 'yearly' : ''}?page=${page}`
      : `${this.homepage}ranking/article/${req.options?.period || 'weekly'}?page=${page}`;
    const doc = Park.html.parse(await this.http.text(url));
    const rows = [...doc.querySelectorAll(board === 'sellers'
      ? '.c-ranksell-110, .c-rankbox-100 > .c-ranklist-110'
      : '.c-rankbox-100 > .c-ranklist-110')];
    const items = rows.map((row) => {
      if (board === 'sellers') {
        const anchor = row.querySelector('.c-ranksell-110_inbox[href], .c-ranklist-130 h3 a[href]');
        const url = new URL(anchor?.getAttribute('href') || '', this.homepage);
        const author = row.querySelector('a[href*="author_id="]');
        const feed = row.querySelector('[data-feed-api*="author_id="]');
        const authorUrl = new URL(author?.getAttribute('href') || '', this.homepage);
        const feedUrl = new URL(feed?.getAttribute('data-feed-api') || '', this.homepage);
        const id = authorUrl.searchParams.get('author_id') || feedUrl.searchParams.get('author_id');
        const rank = Number(Park.html.text(row.querySelector('[class^="c-ranklabel-"]')).match(/^\d+/)?.[0]);
        const title = row.querySelector('.c-ranklist-120_info h3, .c-ranklist-130 h3');
        const image = row.querySelector('.c-ranklist-120_tmbimg img, .c-rankwriter-100 img');
        if (!id || !/^[A-Za-z0-9_-]{1,60}$/.test(id) || !rank || url.host !== 'adult.contents.fc2.com') return null;
        return { id, rank, title: Park.html.text(title || anchor),
          subtitle: Park.html.text(row.querySelector('.c-ranklist-120_dis, .c-ranklist-130_dis')),
          workCount: Number(Park.html.text(author).match(/\((\d+)\)/)?.[1]) || undefined,
          cover: new URL(image?.getAttribute('src') || '', this.homepage).href,
          url: url.href };
      }
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
