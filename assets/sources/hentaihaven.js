/* HentaiHaven：公开作品 API，详情页提取当前作品的 episode HLS。 */
Park.register({
  i18n: {
    "zh-Hant": {"里番目录、搜索与 HLS 播放": "裏番目錄、搜尋與 HLS 播放"}, ja: {"里番目录、搜索与 HLS 播放": "アニメの一覧・検索・HLS再生"}, ko: {"里番目录、搜索与 HLS 播放": "리반 카탈로그, 검색 및 HLS 재생"}, en: {"里番目录、搜索与 HLS 播放": "Anime catalog, search and HLS playback"}, es: {"里番目录、搜索与 HLS 播放": "Catálogo de anime, búsqueda y reproducción HLS"}, ru: {"里番目录、搜索与 HLS 播放": "Каталог аниме, поиск и воспроизведение HLS"}, ar: {"里番目录、搜索与 HLS 播放": "دليل أنمي مع البحث وتشغيل HLS"},
  },
  key: 'hentaihaven', name: 'HentaiHaven', version: '0.0.4', minAppVersion: '0.9.2', type: 'video', category: 'anime', language: 'en', color: '#9c4dcc',
  homepage: 'https://hentaihaven.xxx/', description: '里番目录、搜索与 HLS 播放', domains: ['hentaihaven.xxx'], network: {mode: 'browser', origin: 'https://hentaihaven.xxx', vpnHint: true},
  media: {mode: 'native', origin: 'https://hentaihaven.xxx', domains: ['octopusmanifest.org'], scope: 'session'},
  imageHeaders: {Referer: 'https://hentaihaven.xxx/'}, idPattern: '^[a-z0-9-]{1,240}$', defaultFeed: 'trending', feeds: [{key: 'trending', label: '热门'}], API: 'https://hentaihaven.xxx/api/manga/',
  validId(v) { const id = String(v || ''); if (!/^[a-z0-9-]{1,240}$/.test(id)) throw Park.error('NOT_FOUND', '作品编号无效'); return id; },
  async api(params) { const r = await this.http.get(this.API, {params, timeout: 30000}); if (!r.ok) throw Park.error(r.status === 403 ? 'CONFIRM_REQUIRED' : 'HTTP', 'HentaiHaven 请求失败', {status: r.status}); try { const d = r.json(); if (!Array.isArray(d?.data)) throw 0; return d.data; } catch (_) { throw Park.error('PARSE', 'HentaiHaven 返回的数据无效'); } },
  item(v) { const slug = this.validId(v?.slug), title = Park.html.unescape(String(v?.title?.rendered || v?.title || '')).trim(), path = String(v?.meta?.vraven_remote_thumbnail || ''); if (!title) return null; return {id: slug, title, cover: path ? 'https://img.hentaihaven.xxx/' + path.replace(/^\/+/, '') : '', coverAspect: 16 / 9, url: 'https://hentaihaven.xxx/watch/' + slug + '/', description: '', chapters: null, mediaKind: 'video'}; },
  async listing(req = {}, query) { const page = Math.max(1, Number(req.page) || 1), rows = query === undefined ? await this.api({trending_period: 'monthly', per_page: 20, page}) : await this.api({search: String(query).slice(0, 100), per_page: 20, page}); return {items: rows.map(x => this.item(x)).filter(Boolean), page, hasNext: rows.length >= 20}; },
  async feed(key, req) { if (key !== 'trending') throw Park.error('CONFIG', '未知热门列表'); return this.listing(req); }, async search(req) { const q = String(req?.keyword || '').trim(); return q ? this.listing(req, q) : {items: [], page: 1, hasNext: false}; },
  async detail(value) { const id = this.validId(value), url = 'https://hentaihaven.xxx/watch/' + id + '/', r = await this.http.get(url); if (!r.ok) throw Park.error('NOT_FOUND', '作品不存在'); const doc = Park.html.parse(r.body), title = Park.html.text(doc.querySelector('h1,.entry-title')) || id, cover = doc.querySelector('meta[property="og:image"]')?.getAttribute('content') || ''; const chapters = [], seen = new Set(); for (const a of doc.querySelectorAll('a[href*="/watch/' + id + '/episode-"]')) { const u = new URL(a.getAttribute('href'), url); const m = u.pathname.match(/episode-(\d+)/); if (!m || seen.has(m[1])) continue; seen.add(m[1]); chapters.push({id: m[1], title: '第 ' + m[1] + ' 集', url: u.href}); } chapters.sort((a, b) => Number(a.id) - Number(b.id)); return {id, title, cover: cover || '', url, chapters: chapters.length ? chapters : null, tags: []}; },
  async videos(value, episodeId) {
    const detail = await this.detail(value);
    const episode = episodeId && episodeId !== '_'
      ? detail.chapters?.find(row => String(row.id) === String(episodeId))
      : detail.chapters?.[0];
    if (!episode) throw Park.error('NOT_FOUND', '分集不存在');
    const response = this.http.ensureOk(await this.http.get(episode.url));
    const doc = Park.html.parse(response.body), candidates = [];
    function visit(value) {
      if (!value || typeof value !== 'object') return;
      if (value['@type'] === 'VideoObject' && typeof value.contentUrl === 'string') candidates.push(value.contentUrl);
      if (Array.isArray(value)) value.forEach(visit);
      if (Array.isArray(value['@graph'])) value['@graph'].forEach(visit);
    }
    for (const script of doc.querySelectorAll('script[type="application/ld+json"]')) {
      try { visit(JSON.parse(script.textContent)); } catch (_) {}
    }
    // 清单 CDN 会更换主机，按会话授权，只校验公网 HTTPS 与 HLS 路径。
    const url = candidates.map(value => { try { const u = new URL(String(value).trim(), episode.url); return Park.url.parse(u.href, episode.url, [u.hostname]); } catch (_) { return null; } })
      .find(url => url?.protocol === 'https:' && /\.m3u8$/i.test(url.pathname));
    if (!url) throw Park.error('UNSUPPORTED', '此分集没有可用 HLS');
    return [{url: url.href, format: 'hls', label: episode.title, preferred: true,
      headers: {Referer: episode.url}}];
  },
});
