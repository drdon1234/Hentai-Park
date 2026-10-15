Park.register({
  key: 'ranking-fanza', name: 'FANZA', version: '0.0.1',
  type: 'video', category: 'jav', rankingOnly: true,
  description: '官方销量榜', homepage: 'https://video.dmm.co.jp/',
  domains: ['dmm.co.jp'], network: { vpnHint: true },
  rankings: ['AV', 'AMATEUR', 'ANIME'].map((floor) => ({
    key: floor, label: { AV: 'JAV', AMATEUR: '素人', ANIME: '里番' }[floor],
    category: floor === 'ANIME' ? 'anime' : 'jav', metric: '官方销量榜',
    options: [{ key: 'period', label: '周期', default: 'weekly', values: [
      { value: 'trending', label: '实时' }, { value: 'daily', label: '日榜' },
      { value: 'weekly', label: '周榜' }, { value: 'monthly', label: '月榜' },
    ] }],
  })),
  async ranking(floor, req) {
    const page = Math.max(1, Number(req.page) || 1), limit = 20;
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
    const items = rows.map((row) => {
      const id = String(row.id || ''), content = row.content;
      if (!/^[a-z0-9_]{2,60}$/i.test(id) || !content?.title || !Number.isInteger(row.rank) || row.rank < 1) return null;
      const match = /^(?:h_\d+|\d+)?([a-z]{2,10})0*(\d{2,6})([a-z]?)$/i.exec(id);
      const keyword = floor === 'AV' && match
        ? `${match[1].toUpperCase()}-${String(Number(match[2])).padStart(3, '0')}${match[3].toUpperCase()}`
        : content.title;
      return {
        id, rank: row.rank, title: content.title, keyword,
        subtitle: (content.actresses || []).map(a => a.name).filter(Boolean).join(' · '),
        cover: content.packageImage?.largeUrl || content.packageImage?.mediumUrl || '',
        url: `https://video.dmm.co.jp/${{ AV: 'av', AMATEUR: 'amateur', ANIME: 'anime' }[floor]}/content/?id=${id}`,
      };
    }).filter(Boolean);
    if (rows.length && !items.length) throw Park.error('PARSE', '排行榜解析失败');
    return { items, page, hasNext: rows.length === limit };
  },
});
