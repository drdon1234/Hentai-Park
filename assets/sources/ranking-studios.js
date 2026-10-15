Park.register({
  key: 'ranking-studios', name: '无码厂商', version: '0.0.1',
  type: 'video', category: 'jav', rankingOnly: true,
  description: '官方人气榜', homepage: 'https://www.1pondo.tv/',
  domains: ['1pondo.tv', '10musume.com', 'pacopacomama.com', 'caribbeancom.com'],
  network: { vpnHint: true },
  rankings: [
    ['1pondo', '一本道'], ['10musume', '天然むすめ'],
    ['pacopacomama', 'パコパコママ'], ['caribbeancom', '加勒比'],
  ].map(([key, label]) => ({ key, label, category: 'jav', metric: '官方人气榜',
    options: [{ key: 'period', label: '周期', default: 'weekly', values: [
      { value: 'weekly', label: '周榜' }, { value: 'monthly', label: '月榜' },
    ] }],
  })),
  async ranking(studio, req) {
    if (Number(req.page) > 1) return { items: [], page: Number(req.page), hasNext: false };
    const period = req.options?.period || 'weekly';
    let items;
    if (studio === 'caribbeancom') {
      const base = 'https://www.caribbeancom.com';
      const response = this.http.ensureOk(await this.http.get(`${base}/ranking/${period}.html`, { responseType: 'base64' }));
      const bytes = Uint8Array.from(atob(response.body), c => c.charCodeAt(0));
      const doc = Park.html.parse(new TextDecoder('euc-jp').decode(bytes));
      items = [...doc.querySelectorAll('.is-movie-ranking a.entry[href]')].map((row) => {
        const match = /^\/moviepages\/(\d{6}-\d{3})\/index\.html$/.exec(row.getAttribute('href') || '');
        if (!match) return null;
        return { id: match[1], keyword: match[1],
          rank: Number(Park.html.text(row.querySelector('.ranking-number'))),
          title: Park.html.text(row.querySelector('.meta-title')),
          cover: row.querySelector('img.media-image')?.getAttribute('src') || '',
          url: base + row.getAttribute('href') };
      }).filter(Boolean);
    } else {
      const base = { '1pondo': 'https://www.1pondo.tv', '10musume': 'https://www.10musume.com', 'pacopacomama': 'https://www.pacopacomama.com' }[studio];
      if (!base) throw Park.error('CONFIG', '未知列表');
      const data = await this.http.json(`${base}/dyn/phpauto/movie_lists/list_${period}_0.json`);
      if (!Array.isArray(data.Rows)) throw Park.error('PARSE', '排行榜解析失败');
      items = data.Rows.map((row, index) => {
        const id = String(row.MovieID || '');
        if (!/^\d{6}_\d{2,3}$/.test(id)) return null;
        return { id, rank: index + 1, title: row.Title, keyword: id,
          subtitle: row.Actor || '', cover: row.ThumbHigh || row.MovieThumb || '',
          url: `${base}/movies/${id}/` };
      }).filter(Boolean);
    }
    items = items.filter(row => row.title && row.rank > 0);
    if (!items.length) throw Park.error('PARSE', '排行榜解析失败');
    return { items, page: 1, hasNext: false };
  },
});
