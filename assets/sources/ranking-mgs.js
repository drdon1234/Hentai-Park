Park.register({
  key: 'ranking-mgs', name: 'MGStage', version: '0.0.3', minAppVersion: '0.9.2',
  type: 'video', category: 'jav', rankingOnly: true,
  description: '官方销量榜', homepage: 'https://www.mgstage.com/',
  domains: ['mgstage.com'],
  network: { vpnHint: true, headers: { 'User-Agent': 'Mozilla/5.0' } },
  rankings: [{ key: 'sales', label: 'MGStage', category: 'jav', metric: '官方销量榜',
    options: [{ key: 'period', label: '周期', default: 'week', values: [
      { value: 'day', label: '日榜' }, { value: 'week', label: '周榜' }, { value: 'month', label: '月榜' },
    ] }, { key: 'channel', label: '频道', default: '', values: [
      { value: '', label: '全部' }, { value: 'mgs_', label: 'MGS' },
      { value: 'shiroutotv_', label: 'シロウトTV' }, { value: 'nanpatv_', label: 'ナンパTV' },
      { value: 'luxutv_', label: 'ラグジュTV' },
    ] }],
  }],
  async ranking(_, req) {
    if (Number(req.page) > 1) return { items: [], page: Number(req.page), hasNext: false };
    const response = await this.http.get(`${this.homepage}ranking/ranking.php?id=${req.options?.channel || ''}${req.options?.period || 'week'}`, {
      headers: { Cookie: 'adc=1' },
    });
    if (response.status === 403) throw Park.error('BLOCKED', '此榜单可能需要日本地区的 VPN 或代理');
    const doc = Park.html.parse(this.http.ensureOk(response).body);
    const items = [...doc.querySelectorAll('#center_column .rank_list_detail li')].map((row) => {
      const a = row.querySelector('h5 a[href]'), path = a?.getAttribute('href') || '';
      const match = /^\/(?:product\/product_detail|monthly\/(?:shiroutotv|nanpatv|luxutv)\/video)\/([A-Za-z0-9_-]{2,40})\/?$/.exec(path);
      const rank = Number(Park.html.text(row.querySelector('[class^="ranking_"]')).match(/\d+/)?.[0]);
      if (!match || !rank) return null;
      const id = match[1].toUpperCase();
      return { id, rank, title: Park.html.text(a), keyword: id,
        cover: row.querySelector('h6 img')?.getAttribute('src') || '',
        url: new URL(path, this.homepage).href };
    }).filter(Boolean);
    if (!items.length) throw Park.error('PARSE', '排行榜解析失败');
    return { items, page: 1, hasNext: false };
  },
});
