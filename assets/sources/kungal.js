/* KUN's public API. Resource download counters are touched only on a user click. */
(function () {
  const BASE = 'https://www.kungal.com', API = BASE + '/api/v1';
  const fail = () => Park.error('PARSE', '游戏站点返回的数据无效');
  const idOf = value => { const id = String(value); if (!/^[1-9]\d{0,11}$/.test(id)) throw fail(); return id; };
  const localized = v => v?.localized?.['zh-Hans']?.value || v?.display_name || '';
  const item = w => ({ id: String(w.id), title: localized(w), subtitle: (w.aliases || []).join(' / '),
    cover: w.cover?.url || '', coverAspect: w.cover?.width && w.cover?.height ? w.cover.width / w.cover.height : 0.67,
    rating: w.rating_score, views: w.view_count, likes: w.like_count, uploaded: w.resource_updated_at,
    mediaKind: 'game', contentDomain: 'game', contentRating: w.content_rating || 'unknown', isNsfw: !!w.is_nsfw,
    coverRating: w.cover?.sexual || 'unknown', tags: (w.tags || []).map(localized) });
  const text = document => {
    if (!document) return '';
    if (document.object === 'text') return document.value || '';
    const children = (document.children || []).map(text).join(document.object === 'document' ? '\n\n' : '');
    return children || document.value || '';
  };
  Park.register({
    key: 'kungal', name: 'KUN Galgame', version: '0.0.4', type: 'game', category: 'game', color: '#6FA7DF',
    description: '游戏排行、搜索及社区分享资源', homepage: BASE, language: 'multi',
    domains: ['kungal.com', 'image.kungal.iloveren.link'], network: { mode: 'native', vpnHint: true },
    linkPatterns: ['https?://(?:www\\.)?kungal\\.com/(?:galgame|works)/(\\d+)'], idPattern: '^(\\d+)$', idExample: '1408',
    defaultFeed: 'ranking', feeds: [{ key: 'ranking', label: '本周热门' }, { key: 'latest', label: '资源更新' }],
    settings: [{ key: 'nsfw', type: 'switch', label: '显示 NSFW 内容', default: true }],
    async list(path, params) {
      const page = Number(params.page || 1), limit = 24;
      const result = await this.http.json(API + path, { params: { ...params, page, limit, include_nsfw: !!this.config.nsfw } });
      if (!Array.isArray(result.items)) throw fail();
      return { items: result.items.map(item), page, total: result.total, hasNext: page * limit < result.total };
    },
    async feed(key, { page = 1 } = {}) {
      return this.list('/works', { page, resource_type: 'game', sort: key === 'ranking' ? 'view_7d_desc' : 'resource_updated_desc' });
    },
    async search({ keyword, page = 1 }) {
      if (!String(keyword || '').trim()) return this.feed('latest', { page });
      return this.list('/search/works', { q: String(keyword), page, resource_type: 'game' });
    },
    async detail(id) {
      id = idOf(id);
      const w = await this.http.json(API + '/works/' + id);
      if (String(w.id) !== id) throw fail();
      const intros = w.intros || [];
      return { ...item(w), url: BASE + '/galgame/' + id, authors: w.maker ? [localized(w.maker)] : [],
        description: (intros.find(i => i.locale === 'zh-Hans') || intros[0])?.value || '',
        tags: [{ namespace: 'tags', label: '标签', tags: (w.tags || []).map(t => ({ name: localized(t), keyword: localized(t) })) }] };
    },
    async resourceRows(id) {
      const rows = [], seen = new Set(); let page = 1;
      while (true) {
        const result = await this.http.json(API + '/works/' + idOf(id) + '/resources', { params: { page, limit: 50 } });
        if (!Array.isArray(result.items) || !Number.isInteger(result.total) || result.total < 0) throw fail();
        for (const row of result.items) {
          const key = String(row.id);
          if (seen.has(key)) throw fail();
          seen.add(key);
        }
        rows.push(...result.items);
        if (rows.length >= result.total) break;
        if (!result.items.length) throw fail();
        page++;
      }
      return rows.filter(r => r.resource_type === 'game');
    },
    async gameResources(id) {
      return (await this.resourceRows(id)).map(r => ({ id: String(r.id), title: r.title || '', version: r.version_label || '',
        size: r.size || '', platforms: r.resource_platforms || [], languages: r.resource_languages || [],
        notes: text(r.content), status: r.state || 'unknown', testStatus: 'unknown',
        channels: [{ id: 'links', kind: 'external', label: (r.provider_names || []).join(' / ') || '网盘资源' }] }));
    },
    async resolveGameResource(id, resourceId, channelId) {
      if (channelId !== 'links' || !(await this.resourceRows(id)).some(r => String(r.id) === String(resourceId))) throw fail();
      const result = await this.http.json(API + '/galgame-resources/' + idOf(resourceId) + '/downloads', { method: 'POST' });
      const urls = result.download_urls;
      if (!Array.isArray(urls) || !urls.length || urls.some(u => typeof u !== 'string')) throw fail();
      // Multiple links are returned together after the click; never discard mirrors or archive parts.
      return { url: urls[0], urls, kind: 'external', extractionCode: result.extraction_code || '', archivePassword: result.archive_password || '' };
    },
  });
})();

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"}]});
