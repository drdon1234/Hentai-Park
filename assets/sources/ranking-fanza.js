Park.register({
  i18n: {
    "zh-Hant": {"分类累计排序（非周期榜）": "分類累計排序（非週期榜）", "月度女优榜": "月度女優榜", "累计人气": "累計人氣", "累计销量": "累計銷量", "评价排序": "評價排序"},
    ja: {"分类累计排序（非周期榜）": "ジャンル累計順（期間別ではありません）", "月度女优榜": "月間女優ランキング", "累计人气": "累計人気", "累计销量": "累計販売数", "评价排序": "レビュー順"},
    ko: {"分类累计排序（非周期榜）": "장르 누적 순위(기간별 아님)", "月度女优榜": "월간 배우 순위", "累计人气": "누적 인기", "累计销量": "누적 판매량", "评价排序": "평점순"},
    en: {"分类累计排序（非周期榜）": "Cumulative ranking by genre (not periodic)", "月度女优榜": "Monthly actress ranking", "累计人气": "All-time popularity", "累计销量": "All-time sales", "评价排序": "By rating"},
    es: {"分类累计排序（非周期榜）": "Clasificación acumulada por género (no periódica)", "月度女优榜": "Ranking mensual de actrices", "累计人气": "Popularidad acumulada", "累计销量": "Ventas acumuladas", "评价排序": "Por valoración"},
    ru: {"分类累计排序（非周期榜）": "Накопительный рейтинг по жанру (без периода)", "月度女优榜": "Ежемесячный рейтинг актрис", "累计人气": "Популярность за всё время", "累计销量": "Продажи за всё время", "评价排序": "По оценкам"},
    ar: {"分类累计排序（非周期榜）": "ترتيب تراكمي حسب النوع (غير دوري)", "月度女优榜": "ترتيب الممثلات الشهري", "累计人气": "الشعبية الإجمالية", "累计销量": "المبيعات الإجمالية", "评价排序": "حسب التقييم"},
  },
  key: 'ranking-fanza', name: 'FANZA', version: '0.0.4', minAppVersion: '0.9.2',
  type: 'video', category: 'jav', rankingOnly: true,
  description: '官方销量榜', homepage: 'https://video.dmm.co.jp/',
  domains: ['dmm.co.jp'], network: { vpnHint: true },
  rankings: [...['AV', 'AMATEUR', 'ANIME'].map((floor) => ({
    key: floor, label: { AV: 'JAV', AMATEUR: '素人', ANIME: '里番' }[floor],
    category: floor === 'ANIME' ? 'anime' : 'jav', metric: '官方销量榜',
    options: [{ key: 'period', label: '周期', default: 'weekly', values: [
      { value: 'trending', label: '实时' }, { value: 'daily', label: '日榜' },
      { value: 'weekly', label: '周榜' }, { value: 'monthly', label: '月榜' },
    ] }],
  })),
  { key: 'actresses', label: '女优榜', kind: 'actress', category: 'jav', metric: '月度女优榜' },
  { key: 'genres', label: '分类榜', kind: 'genre', category: 'jav', metric: '分类累计排序（非周期榜）', options: [
    { key: 'genre', label: '分类', dynamic: true },
    { key: 'sort', label: '排序', default: 'SALES_RANK_SCORE', values: [
      { value: 'SALES_RANK_SCORE', label: '累计人气' }, { value: 'SALES_COUNT', label: '累计销量' },
      { value: 'REVIEW_RANK_SCORE', label: '评价排序' },
    ] },
  ] }],
  async query(query, variables = {}) {
    const response = await this.http.post('https://api.video.dmm.co.jp/graphql', {
      headers: { Referer: this.homepage, Origin: 'https://video.dmm.co.jp', 'Fanza-Device': 'BROWSER' },
      json: { query, variables },
    });
    const data = this.http.ensureOk(response).json();
    if (data.errors || !data.data) throw Park.error('PARSE', '排行榜解析失败');
    return data.data;
  },
  async rankingOptions() {
    if (this.genreOptions) return this.genreOptions;
    const data = await this.query(`query Genres {
      legacySearchPPV(limit: 1, offset: 0, floor: AV, sort: SALES_RANK_SCORE,
        facetLimit: 300, includeExplicit: true, excludeUndelivered: true) {
        result { facet { ... on PPVContentSearchFacet { genre { items { id name count } } } } }
      }
    }`);
    const rows = data.legacySearchPPV?.result?.facet?.genre?.items;
    const values = (Array.isArray(rows) ? rows : []).filter(r => /^\d+$/.test(r.id) && r.name)
      .map(r => ({ value: r.id, label: r.name }));
    if (!values.length) throw Park.error('PARSE', '排行榜解析失败');
    this.genreOptions = [{ key: 'genre', label: '分类', type: 'select', default: values[0].value, values }];
    return this.genreOptions;
  },
  work(id, content, rank, floor = 'AV') {
    id = String(id || '');
    if (!/^[a-z0-9_]{2,60}$/i.test(id) || !content?.title || !Number.isInteger(rank) || rank < 1) return null;
    const match = /^(?:h_\d+|\d+)?([a-z]{2,10})0*(\d{2,6})([a-z]?)$/i.exec(id);
    const keyword = floor === 'AV' && match
      ? `${match[1].toUpperCase()}-${String(Number(match[2])).padStart(3, '0')}${match[3].toUpperCase()}` : content.title;
    return { id, rank, title: content.title, keyword,
      subtitle: (content.actresses || []).map(a => a.name).filter(Boolean).join(' · '),
      cover: content.packageImage?.largeUrl || content.packageImage?.mediumUrl || '',
      url: `https://video.dmm.co.jp/${{ AV: 'av', AMATEUR: 'amateur', ANIME: 'anime' }[floor]}/content/?id=${id}` };
  },
  async ranking(floor, req) {
    const page = Math.max(1, Number(req.page) || 1), limit = 20;
    if (floor === 'actresses') {
      const data = await this.query(`query ActressRanking($limit: Int!, $offset: Int!) {
        ppvActressRanking(limit: $limit, offset: $offset, filter: {monthly: {floor: AV}}) {
          items { rank actress { id name imageUrl contentsCountOnSale } }
        }
      }`, { limit, offset: (page - 1) * limit });
      const rows = data.ppvActressRanking?.items;
      if (!Array.isArray(rows) || (!rows.length && page === 1)) throw Park.error('PARSE', '排行榜解析失败');
      const items = rows.filter(r => /^\d+$/.test(r.actress?.id) && r.actress.name && r.rank > 0).map(r => ({
        id: r.actress.id, rank: r.rank, title: r.actress.name, keyword: r.actress.name,
        cover: r.actress.imageUrl || '', workCount: r.actress.contentsCountOnSale,
        url: `${this.homepage}av/list/?actress=${r.actress.id}`,
      }));
      if (rows.length && !items.length) throw Park.error('PARSE', '排行榜解析失败');
      return { items, page, hasNext: rows.length === limit };
    }
    if (floor === 'genres') {
      const data = await this.query(`query GenreRanking($sort: ContentSearchPPVSort!, $filter: ContentSearchPPVFilterInput, $limit: Int!, $offset: Int!) {
        legacySearchPPV(limit: $limit, offset: $offset, floor: AV, sort: $sort, filter: $filter,
          facetLimit: 1, includeExplicit: true, excludeUndelivered: true) {
          result { contents { id title packageImage { largeUrl mediumUrl } actresses { name } } }
        }
      }`, { limit, offset: (page - 1) * limit, sort: req.options.sort,
        filter: { genreIds: { ids: [{ id: req.options.genre }], op: 'AND' } } });
      const rows = data.legacySearchPPV?.result?.contents;
      if (!Array.isArray(rows)) throw Park.error('PARSE', '排行榜解析失败');
      const items = rows.map((r, i) => this.work(r.id, r, (page - 1) * limit + i + 1)).filter(Boolean);
      if (rows.length && !items.length) throw Park.error('PARSE', '排行榜解析失败');
      return { items, page, hasNext: rows.length === limit };
    }
    const query = `query Ranking($filter: PPVContentRankingFilterInput, $limit: Int!, $offset: Int!, $amateur: Boolean!) {
      ppvContentRanking(limit: $limit, offset: $offset, filter: $filter) {
        items { id rank content { title packageImage { largeUrl mediumUrl } actresses @skip(if: $amateur) { name } } }
      }
    }`;
    const response = await this.http.post('https://api.video.dmm.co.jp/graphql', {
      headers: { Referer: this.homepage, Origin: 'https://video.dmm.co.jp', 'Fanza-Device': 'BROWSER' },
      json: { query, variables: {
        filter: { [req.options?.period || 'weekly']: { floor } },
        limit, offset: (page - 1) * limit, amateur: floor === 'AMATEUR',
      } },
    });
    const data = this.http.ensureOk(response).json();
    const rows = data.data?.ppvContentRanking?.items;
    if (data.errors || !Array.isArray(rows) || (!rows.length && page === 1)) throw Park.error('PARSE', '排行榜解析失败');
    const items = rows.map(row => this.work(row.id, row.content, row.rank, floor)).filter(Boolean);
    if (rows.length && !items.length) throw Park.error('PARSE', '排行榜解析失败');
    return { items, page, hasNext: rows.length === limit };
  },
});
