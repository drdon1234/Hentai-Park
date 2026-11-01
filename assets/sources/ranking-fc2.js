Park.register({
  i18n: {
    "zh-Hant": {"上月": "上月", "官方卖家榜": "官方賣家榜"},
    ja: {"上月": "先月", "官方卖家榜": "公式販売者ランキング"},
    ko: {"上月": "지난달", "官方卖家榜": "공식 판매자 순위"},
    en: {"上月": "Last month", "官方卖家榜": "Official seller ranking"},
    es: {"上月": "Mes pasado", "官方卖家榜": "Ranking oficial de vendedores"},
    ru: {"上月": "Прошлый месяц", "官方卖家榜": "Официальный рейтинг продавцов"},
    ar: {"上月": "الشهر الماضي", "官方卖家榜": "ترتيب البائعين الرسمي"},
  },
  key: 'ranking-fc2', name: 'FC2', version: '0.0.7', minAppVersion: '0.10.8',
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
  async comments(value, req = {}) {
    const id = String(value);
    if (req.context?.board === 'sellers' || req.parentId) throw Park.error('UNSUPPORTED', '此内容暂不支持评论');
    if (!/^\d{2,9}$/.test(id)) throw Park.error('NOT_FOUND', '作品编号无效');
    // The public server currently repeats its first page even when page=2 is requested.
    if (Number(req.page) > 1) return {items: [], hasNext: false};
    const url = this.homepage + 'article/' + id + '/review', doc = Park.html.parse(await this.http.text(url));
    if (!doc.querySelector('.items_comment_reviewComp')) throw Park.error('PARSE', '评论数据无效');
    const items = [...doc.querySelectorAll('.userIdreview')].map(author => {
      const row = author.closest('ul'), reviewer = row?.querySelector('[data-reviewer-id]')?.getAttribute('data-reviewer-id');
      const content = row?.children[0]?.cloneNode(true);
      if (!content || !/^\d+$/.test(reviewer || '')) throw Park.error('PARSE', '评论数据无效');
      // Rating-only reviews have an explicit empty-title placeholder; do not display it as a comment.
      for (const empty of content.querySelectorAll('.items_comment_notTitle')) empty.remove();
      const body = Park.comments.html(content.innerHTML, url);
      if (!body.length) return null;
      const star = row.querySelector('[class^="items_comment_Star"][class$="1"], [class^="items_comment_Star"][class$="2"], [class^="items_comment_Star"][class$="3"], [class^="items_comment_Star"][class$="4"], [class^="items_comment_Star"][class$="5"]');
      return {id: id + ':' + reviewer, author: {name: Park.html.text(author)}, body,
        date: Park.html.text(row.querySelector('.userDatareview')), rating: Number(star?.className.match(/(\d)$/)?.[1]) || undefined};
    }).filter(Boolean);
    return {items, hasNext: false};
  },

  async metadataDetail(value, context = {}) {
    const id = String(value);
    if (!/^\d{2,9}$/.test(id)) throw Park.error('NOT_FOUND', '作品编号无效');
    let url = `${this.homepage}article/${id}/`;
    if (context.url) {
      const supplied = Park.url.parse(context.url, this.homepage, this.domains);
      const expected = new URL(url);
      if (!supplied || !supplied.pathname.includes(id) ||
          supplied.pathname !== expected.pathname) throw Park.error('CONFIG', '作品编号无效');
      url = supplied.href;
    }
    const response = await this.http.get(url, {});
    this.http.ensureOk(response);
    const doc = Park.html.parse(response.body);
    const meta = key => doc.querySelector(`meta[property="${key}"]`)?.getAttribute('content') || '';
    const text = selector => selector ? Park.html.text(doc.querySelector(selector)) : '';
    const title = text(".items_article_headerInfo h3, .items_article_MainitemNameTitle");
    if (!title) {
      if (/age[_-]?(?:check|verify)|年齢認証|年齢確認/i.test(response.url + response.body.slice(0, 20000))) {
        throw Park.error('CONFIRM_REQUIRED', '站点验证暂未完成', { url });
      }
      throw Park.error('PARSE', '作品资料无效');
    }
    const image = value => {
      if (!value) return '';
      try { const u = new URL(value, url); return u.protocol === 'https:' && !u.username && !u.password && !u.port ? u.href : ''; }
      catch (_) { return ''; }
    };
    const fields = {};
    for (const row of doc.querySelectorAll(".items_article_headerInfo tr")) {
      const label = Park.html.text(row.querySelector('th')).replace(/[:：\s]/g, '');
      const value = Park.html.text(row.querySelector('td'));
      if (label && value) fields[label] = value;
    }
    const field = pattern => Object.entries(fields).find(([key]) => pattern.test(key))?.[1] || '';
    return { id, code: id, title, url, cover: image(meta('og:image')),
      description: meta('og:description'),
      studio: field(/販売者/), releaseDate: field(/販売日/) || text(".items_article_Releasedate"),
      duration: field(/収録時間|再生時間|長度|时长/),
      series: field(/シリーズ|系列/),
      actors: [...new Set([...doc.querySelectorAll(".detail_data a[href*=\"actor\"], main a[href*=\"/actor/\"]")].map(Park.html.text).filter(Boolean))],
      tags: [...new Set([...doc.querySelectorAll(".items_article_headerInfo a[href*=\"tag\"]")].map(Park.html.text).filter(Boolean))],
      images: [...new Set(([...doc.querySelectorAll('.items_article_SampleImages a[href]')].map(e => e.getAttribute('href')).concat([...doc.querySelectorAll('.items_article_modalAreaPict img[src]')].map(e => e.getAttribute('src'))).concat([...doc.querySelectorAll('[data-pdp-sample-thumbnail][data-img]')].map(e => e.getAttribute('data-img')))).map(image).filter(Boolean))].slice(0, 100) };
  },
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
