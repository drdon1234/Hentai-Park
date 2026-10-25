/* Iwara：浏览器网络访问公开 API；内容混合 MMD、动画与其他创作视频，保留原站分级。 */
Park.register({
  i18n: {
    "zh-Hant": {"动画与创作视频，支持搜索、分级与多清晰度播放": "動畫與創作影片，支援搜尋、分級與多畫質播放"}, ja: {"动画与创作视频，支持搜索、分级与多清晰度播放": "アニメ・創作動画。検索、レーティング、複数画質再生に対応"}, ko: {"动画与创作视频，支持搜索、分级与多清晰度播放": "애니메이션 및 창작 동영상, 검색·등급·다중 화질 재생 지원"}, en: {"动画与创作视频，支持搜索、分级与多清晰度播放": "Animated and creator videos with search, ratings and multi-quality playback"}, es: {"动画与创作视频，支持搜索、分级与多清晰度播放": "Vídeos de animación y creadores con búsqueda, clasificación y varias calidades"}, ru: {"动画与创作视频，支持搜索、分级与多清晰度播放": "Анимация и авторские видео с поиском, рейтингами и разным качеством"}, ar: {"动画与创作视频，支持搜索、分级与多清晰度播放": "فيديوهات رسوم وإبداع مع البحث والتصنيف وتشغيل متعدد الجودة"},
  },
  key: 'iwara', name: 'Iwara', version: '0.0.5', minAppVersion: '0.9.2', type: 'video', category: 'anime', language: 'en', color: '#f06b8d',
  homepage: 'https://www.iwara.tv/', description: '动画与创作视频，支持搜索、分级与多清晰度播放', domains: ['iwara.tv'],
  network: {mode: 'browser', origin: 'https://www.iwara.tv', vpnHint: true}, media: {mode: 'native', origin: 'https://www.iwara.tv', domains: ['iwara.tv', 'filesq.iwara.tv', 'files.iwara.tv'], scope: 'session'},
  imageNetwork: {mode: 'browser', origin: 'https://www.iwara.tv', domains: ['iwara.tv']}, imageHeaders: {Referer: 'https://www.iwara.tv/'},
  idPattern: '^[A-Za-z0-9]{8,32}$', defaultFeed: 'popular', feeds: [{key: 'popular', label: '热门'}], API: 'https://api.iwara.tv', PAGE_SIZE: 20,
  validId(v) { const id = String(v || ''); if (!/^[A-Za-z0-9]{8,32}$/.test(id)) throw Park.error('NOT_FOUND', '视频编号无效'); return id; },
  async api(path, params) { const r = await this.http.get(this.API + path, {params, timeout: 30000}); if (!r.ok) throw Park.error(r.status === 403 ? 'CONFIRM_REQUIRED' : 'HTTP', 'Iwara 请求失败', {status: r.status}); try { return r.json(); } catch (_) { throw Park.error('PARSE', 'Iwara 返回的数据无效'); } },
  item(v) { const id = this.validId(v?.id), title = String(v?.title || '').trim(), f = v?.file || {}; if (!title || !f.id) return null; const cover = 'https://files.iwara.tv/image/thumbnail/' + encodeURIComponent(String(f.id)) + '/thumbnail-00.jpg'; const rating = String(v?.rating || 'unknown'); return {id, title, subtitle: v?.user?.name || v?.user?.username || '', cover, coverAspect: 16 / 9, url: 'https://www.iwara.tv/video/' + id + '/' + (v.slug || ''), duration: Number(f.duration) || 0, description: String(v?.body || '') + '\nrating:' + rating, rating, tags: Array.isArray(v.tags) ? v.tags.map(x => ({name: String(x.id || ''), keyword: String(x.id || '')})).filter(x => x.name) : [], chapters: null, mediaKind: 'video'}; },
  async listing(req = {}, query) { const page = Math.max(1, Number(req.page) || 1), d = query === undefined ? await this.api('/videos', {sort: 'views', page: page - 1, limit: this.PAGE_SIZE}) : await this.api('/search', {type: 'videos', query: String(query).slice(0, 100), page: page - 1, limit: this.PAGE_SIZE}); const rows = Array.isArray(d?.results) ? d.results : []; return {items: rows.map(x => this.item(x)).filter(Boolean), page, hasNext: rows.length >= this.PAGE_SIZE}; },
  async feed(key, req) { if (key !== 'popular') throw Park.error('CONFIG', '未知热门列表'); return this.listing(req); }, async search(req) { const q = String(req?.keyword || '').trim(); return q ? this.listing(req, q) : {items: [], page: 1, hasNext: false}; },
  async detail(value) { const id = this.validId(value), v = await this.api('/video/' + id), item = this.item(v); if (!item) throw Park.error('NOT_FOUND', '视频不存在'); return item; },
  async comments(value, req = {}) {
    const id = this.validId(value), page = Math.max(1, Math.floor(Number(req.page) || 1));
    const parentId = req.parentId == null ? null : String(req.parentId);
    if (parentId && !/^[a-zA-Z0-9_-]{1,64}$/.test(parentId)) throw Park.error('CONFIG', '评论数据无效');
    const data = await this.api('/video/' + id + '/comments', {page: page - 1, ...(parentId ? {parent: parentId} : {})});
    if (!Array.isArray(data?.results) || !Number.isSafeInteger(data.count) || data.count < 0 ||
        !Number.isSafeInteger(data.limit) || data.limit < 1 || data.page !== page - 1) throw Park.error('PARSE', '评论数据无效');
    const seen = new Set(), items = [];
    for (const row of data.results) {
      const cid = String(row?.id || ''), parent = row?.parent == null ? null : String(row.parent.id || '');
      if (!/^[a-zA-Z0-9_-]{1,64}$/.test(cid) || typeof row.body !== 'string' ||
          row.videoId !== id || parent !== parentId) throw Park.error('PARSE', '评论数据无效');
      if (seen.has(cid)) continue;
      seen.add(cid);
      const body = Park.comments.text(row.body);
      if (!body.length) continue;
      const replyCount = Math.max(0, Math.floor(Number(row.numReplies) || 0));
      items.push({id: cid, parentId: parent || undefined, author: {name: String(row.user?.name || row.user?.username || '')},
        body, date: String(row.createdAt || ''), replyCount, repliesAvailable: replyCount > 0});
    }
    return {items, page, total: data.count, hasNext: data.results.length > 0 && page * data.limit < data.count};
  },
  async mediaList(v) {
    const url = String(v?.fileUrl || '');
    if (!url) return [];
    const u = new URL(url), expires = u.searchParams.get('expires') || '', segment = u.pathname.split('/').filter(Boolean).pop() || '';
    const source = segment + '_' + expires + '_mSvL05GfEmeEmsEYfGCnVpEjYgTJraJN';
    const bytes = Array.from(new TextEncoder().encode(source));
    const digest = await Park.crypto.digestBytes('sha1', bytes);
    const version = digest.map(x => x.toString(16).padStart(2, '0')).join('');
    const r = await this.http.get(url, {mode: 'native', headers: {'X-Version': version}});
    this.http.ensureOk(r);
    try {
      const data = r.json();
      if (Array.isArray(data)) return data;
    } catch (_) {}
    throw Park.error('PARSE', 'Iwara 返回的数据无效');
  },
  async videos(value) {
    const v = await this.api('/video/' + this.validId(value)), rows = await this.mediaList(v), out = [];
    for (const row of rows) {
      const src = row?.src?.view || row?.src?.download || row?.url;
      const url = Park.url.parse(src, 'https://www.iwara.tv', this.media.domains);
      if (!url || url.protocol !== 'https:') continue;
      const label = String(row?.name || row?.quality || '原站');
      const quality = Number(label.match(/\d+/)?.[0] || 0);
      out.push({url: url.href, format: 'mp4', label, quality});
    }
    out.sort((a, b) => b.quality - a.quality);
    if (out[0]) out[0].preferred = true;
    if (!out.length) throw Park.error('UNSUPPORTED', '此视频没有可用播放地址');
    return out;
  },
});
