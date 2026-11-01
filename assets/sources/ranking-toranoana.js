Park.register({
  key: 'ranking-toranoana', name: '虎之穴', version: '0.0.3', minAppVersion: '0.10.8',
  type: 'comic', category: 'doujin', rankingOnly: true,
  description: '官方销量榜', homepage: 'https://ec.toranoana.jp/',
  domains: ['toranoana.jp'], network: { vpnHint: true },
  imageHeaders: { Referer: 'https://ec.toranoana.jp/' },
  rankings: [{ key: 'doujin', label: '同人漫画', category: 'doujin', metric: '官方销量榜',
    options: [{ key: 'period', label: '周期', default: 'weekly', values: [
      { value: 'daily', label: '日榜' }, { value: 'weekly', label: '周榜' }, { value: 'monthly', label: '月榜' },
    ] }],
  }],

  async metadataDetail(value, context = {}) {
    const id = String(value);
    if (!/^\d{12}$/.test(id)) throw Park.error('NOT_FOUND', '作品编号无效');
    let url = `${this.homepage}tora_r/ec/item/${id}/`;
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
    const title = text(".product-detail-desc-title");
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
    for (const row of doc.querySelectorAll(".product-detail-spec-table tr")) {
      const label = Park.html.text(row.querySelector('th')).replace(/[:：\s]/g, '');
      const value = Park.html.text(row.querySelector('td'));
      if (label && value) fields[label] = value;
    }
    const field = pattern => Object.entries(fields).find(([key]) => pattern.test(key))?.[1] || '';
    return { id, code: id, title, url, cover: image(doc.querySelector('.product-detail-image-thumb-item')?.getAttribute('data-src')),
      description: text(".product-detail-comment") || meta('og:description'),
      studio: field(/サークル名/), releaseDate: field(/発行日/),
      authors: field(/作者|作家|著者/) ? [field(/作者|作家|著者/)] : [],
      duration: field(/収録時間|再生時間|長度|时长/),
      series: field(/シリーズ|系列/),
      actors: [...new Set([...doc.querySelectorAll(".detail_data a[href*=\"actor\"], main a[href*=\"/actor/\"]")].map(Park.html.text).filter(Boolean))],
      tags: [...new Set([...doc.querySelectorAll(".product-detail-spec-table a[href*=\"/genre/\"]")].map(Park.html.text).filter(Boolean))],
      images: [...new Set(([...doc.querySelectorAll('.product-detail-image-thumb-item[data-src]')].map(e => e.getAttribute('data-src'))).map(image).filter(Boolean))].slice(0, 100) };
  },
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
