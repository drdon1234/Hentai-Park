Park.register({
  i18n: {
    "zh-Hant": {"官方女优榜": "官方女優榜"},
    ja: {"官方女优榜": "公式女優ランキング"},
    ko: {"官方女优榜": "공식 배우 순위"},
    en: {"官方女优榜": "Official actress ranking"},
    es: {"官方女优榜": "Ranking oficial de actrices"},
    ru: {"官方女优榜": "Официальный рейтинг актрис"},
    ar: {"官方女优榜": "ترتيب الممثلات الرسمي"},
  },
  key: 'ranking-studios', name: '无码厂商', version: '0.0.6', minAppVersion: '0.9.2',
  type: 'video', category: 'jav', rankingOnly: true,
  description: '官方人气榜', homepage: 'https://www.1pondo.tv/',
  domains: ['1pondo.tv', '10musume.com', 'pacopacomama.com', 'caribbeancom.com'],
  network: { vpnHint: true },
  rankings: [
    ['10musume', '天然むすめ'],
    ['pacopacomama', 'パコパコママ'], ['caribbeancom', '加勒比'],
    ['caribbean-actresses', '加勒比'], ['1pondo', '一本道'],
  ].map(([key, label]) => ({ key, label, category: 'jav',
    ...(key === 'caribbean-actresses'
      ? { kind: 'actress', metric: '官方女优榜' }
      : { metric: '官方人气榜', options: [
        { key: 'period', label: '周期', default: 'weekly', values: [
          { value: 'weekly', label: '周榜' }, { value: 'monthly', label: '月榜' },
        ] },
      ] }),
  })),
  async comments(value, req = {}) {
    const bases = {'1pondo': 'https://www.1pondo.tv', '10musume': 'https://www.10musume.com', pacopacomama: 'https://www.pacopacomama.com'};
    let board = req.context?.board, id = String(value);
    if (!board && req.context?.url) {
      const url = Park.comments.url(req.context.url);
      if (url) board = Object.keys(bases).find(key => new URL(url).origin === bases[key]);
    }
    if (!bases[board]) throw Park.error('UNSUPPORTED', '此内容暂不支持评论');
    if (!/^\d{6}_\d{2,3}$/.test(id)) throw Park.error('NOT_FOUND', '作品编号无效');
    if (req.parentId || Number(req.page) > 1) return {items: [], hasNext: false};
    const data = await this.http.json(bases[board] + '/dyn/phpauto/new_movie_reviews/movie_id/' + id + '.json');
    if (!Array.isArray(data.Rows)) throw Park.error('PARSE', '评论数据无效');
    const items = data.Rows.map(c => {
      if (!c.ReviewID || String(c.MovieID) !== id || typeof c.UserComment !== 'string') throw Park.error('PARSE', '评论数据无效');
      return {id: String(c.ReviewID), author: {name: String(c.Nickname || '')}, body: Park.comments.text(c.UserComment),
        date: c.Created, rating: Number(c.UserRating) || undefined};
    }).filter(c => c.body.length);
    return {items, hasNext: false};
  },
  async ranking(studio, req) {
    if (Number(req.page) > 1) return { items: [], page: Number(req.page), hasNext: false };
    const period = req.options?.period || 'weekly';
    let items;
    if (studio === 'caribbeancom' || studio === 'caribbean-actresses') {
      const base = 'https://www.caribbeancom.com';
      const actress = studio === 'caribbean-actresses';
      const response = this.http.ensureOk(await this.http.get(`${base}/ranking/${actress ? 'actress.htm' : period + '.html'}`, { responseType: 'base64' }));
      const bytes = Uint8Array.from(atob(response.body), c => c.charCodeAt(0));
      const doc = Park.html.parse(new TextDecoder('euc-jp').decode(bytes));
      items = [...doc.querySelectorAll(actress ? '.is-actress-ranking a.entry[href]' : '.is-movie-ranking a.entry[href]')].map((row) => {
        if (actress) {
          const match = /^\/search_act\/(\d+)\/1\.html$/.exec(row.getAttribute('href') || '');
          if (!match) return null;
          const title = Park.html.text(row.querySelector('.meta-title'));
          return { id: match[1], title, keyword: title,
            rank: Number(Park.html.text(row.querySelector('.ranking-number'))),
            workCount: Number(Park.html.text(row).match(/出演作品数:\s*(\d+)/)?.[1]) || undefined,
            cover: new URL(row.querySelector('img.media-image')?.getAttribute('src') || '', base).href,
            url: base + row.getAttribute('href') };
        }
        const match = /^\/moviepages\/(\d{6}-\d{3})\/index\.html$/.exec(row.getAttribute('href') || '');
        if (!match) return null;
        return { id: match[1], keyword: match[1],
          rank: Number(Park.html.text(row.querySelector('.ranking-number'))),
          title: Park.html.text(row.querySelector('.meta-title')),
          cover: new URL(row.querySelector('img.media-image')?.getAttribute('src') || '', base).href,
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
