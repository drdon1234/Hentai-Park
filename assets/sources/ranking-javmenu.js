Park.register({
  key: 'ranking-javmenu', name: 'JavMenu', version: '0.0.3', minAppVersion: '0.10.8',
  type: 'video', category: 'jav', rankingOnly: true,
  description: '站内热门', homepage: 'https://javmenu.com/',
  domains: ['javmenu.com'], network: { vpnHint: true },
  rankings: [{ key: 'censored', label: 'JAV', section: 'site', category: 'jav', metric: '站内热门',
    options: [{ key: 'period', label: '周期', default: 'week', values: [
      { value: 'day', label: '日榜' }, { value: 'week', label: '周榜' }, { value: 'month', label: '月榜' },
    ] }],
  }],

  async metadataDetail(value, context = {}) {
    const id = String(value);
    if (!/^[A-Za-z0-9]{2,12}-\d{2,6}[A-Za-z]?$/.test(id)) throw Park.error('NOT_FOUND', '作品编号无效');
    let url = `${this.homepage}zh/${id}`;
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
    const title = text("h1.display-5");
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
    for (const row of doc.querySelectorAll(".movie-info tr")) {
      const label = Park.html.text(row.querySelector('th')).replace(/[:：\s]/g, '');
      const value = Park.html.text(row.querySelector('td'));
      if (label && value) fields[label] = value;
    }
    const field = pattern => Object.entries(fields).find(([key]) => pattern.test(key))?.[1] || '';
    return { id, code: id, title, url, cover: image(meta('og:image')),
      description: text("") || meta('og:description'),
      studio: field(/製作商|制作商|片商/), releaseDate: field(/發行日期|发行日期/),
      duration: field(/収録時間|再生時間|長度|时长/),
      series: field(/シリーズ|系列/),
      actors: [...new Set([...doc.querySelectorAll(".detail_data a[href*=\"actor\"], main a[href*=\"/actor/\"]")].map(Park.html.text).filter(Boolean))],
      tags: [...new Set([...doc.querySelectorAll("main a[href*=\"/genre/\"]")].map(Park.html.text).filter(Boolean))],
      images: [...new Set(([]).map(image).filter(Boolean))].slice(0, 100) };
  },
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
