/*
 * Hanime1 — HTML site behind Cloudflare. All requests run inside the in-app browser engine
 * (network.mode = "browser") so they carry a real browser fingerprint and clearance cookies.
 * - Search: /search?query=&genre=&sort=&tags[]=&page=
 * - Watch page: title, artist, views/date, caption, tags, <source size> list, series playlist.
 * - /download?v= lists extra qualities (data-url). Video URLs carry a short-lived `secure` token,
 *   so they are always resolved right before playback / download.
 */
Park.register({
  key: 'hanime1',
  name: 'Hanime1',
  version: '1.0.2',
  type: 'video',
  color: '#E5355F',
  icon: 'https://hanime1.me/favicon.ico',
  description: '里番、泡面番与 3D 动画，支持多清晰度在线播放与下载',
  homepage: 'https://hanime1.me',
  language: 'zh',
  linkPatterns: ['hanime1\\.(?:me|com)/watch\\?v=(\\d+)'],
  idPattern: '^(\\d{1,8})$',
  idExample: '408297',
  imageHeaders: { Referer: 'https://hanime1.me/' },
  network: { mode: 'browser', origin: 'https://hanime1.me' },

  settings: [
    {
      key: 'genre',
      type: 'select',
      label: '默认类型',
      default: '裏番',
      options: ['全部', '裏番', '泡麵番', 'Motion Anime', '3DCG', '2.5D', '2D動畫', 'AI生成', 'MMD', 'Cosplay'].map((g) => ({
        value: g,
        label: g,
      })),
    },
    {
      key: 'quality',
      type: 'select',
      label: '默认清晰度',
      default: '1080',
      options: [
        { value: '1080', label: '1080P' },
        { value: '720', label: '720P' },
        { value: '480', label: '480P' },
      ],
    },
  ],

  defaultFeed: 'ranking',
  feeds: [
    { key: 'latest', label: '最新上市' },
    {
      key: 'ranking',
      label: '排行榜',
      options: [
        {
          key: 'period',
          label: '周期',
          default: '本週排行',
          values: [
            { value: '本日排行', label: '日榜' },
            { value: '本週排行', label: '周榜' },
            { value: '本月排行', label: '月榜' },
            { value: '觀看次數', label: '总榜' },
          ],
        },
      ],
    },
    { key: 'uploads', label: '最新上传' },
  ],

  searchHint: '搜索作品名、标签或作者',
  searchFilters: [
    {
      key: 'genre',
      label: '类型',
      default: '全部', // searches span every genre; the setting only shapes the browse tabs
      values: [{ value: '@setting', label: '跟随设置' }].concat(
        ['全部', '裏番', '泡麵番', 'Motion Anime', '3DCG', '2.5D', '2D動畫', 'AI生成', 'MMD', 'Cosplay'].map((g) => ({
          value: g,
          label: g,
        }))
      ),
    },
    {
      key: 'sort',
      label: '排序',
      default: '',
      values: [
        { value: '', label: '相关度' },
        { value: '最新上市', label: '最新上市' },
        { value: '最新上傳', label: '最新上传' },
        { value: '本日排行', label: '今日热门' },
        { value: '本週排行', label: '本周热门' },
        { value: '本月排行', label: '本月热门' },
        { value: '觀看次數', label: '观看最多' },
        { value: '讚好比例', label: '好评最多' },
        { value: '時長最長', label: '时长最长' },
      ],
    },
  ],

  BASE: 'https://hanime1.me',

  genre(value) {
    const g = value === '@setting' || value === undefined ? this.config.genre : value;
    return g === '全部' ? '' : g || '';
  },

  async getDoc(path, params) {
    const res = await this.http.get(this.BASE + path, { params });
    if (res.status === 404) throw Park.error('NOT_FOUND', '影片不存在');
    if (!res.ok) throw Park.error('HTTP', `Hanime1 返回 HTTP ${res.status}`, { status: res.status });
    return Park.html.parse(res.body);
  },

  parseCards(doc) {
    const items = [];
    const seen = new Set();
    for (const a of doc.querySelectorAll('a[href*="watch?v="]')) {
      const m = /watch\?v=(\d+)/.exec(a.getAttribute('href') || '');
      if (!m || seen.has(m[1])) continue;
      const titleEl = a.querySelector('.home-rows-videos-title, .card-mobile-title, .title');
      const img = a.querySelector('img');
      const title = Park.html.text(titleEl) || (img && (img.getAttribute('alt') || img.getAttribute('title'))) || '';
      if (!title || !img) continue;
      seen.add(m[1]);
      const src = img.getAttribute('src') || img.getAttribute('data-src') || '';
      const duration = Park.html.text(a.querySelector('.card-mobile-duration, .duration'));
      const portrait = /\/image\/cover\//.test(src);
      items.push({
        id: m[1],
        title,
        cover: src,
        coverAspect: portrait ? 268 / 394 : 16 / 9,
        duration: /^\d+:\d+/.test(duration) ? duration.match(/^[\d:]+/)[0] : '',
      });
    }
    return items;
  },

  maxPage(doc) {
    let max = 0;
    for (const a of doc.querySelectorAll('a.page-link')) {
      const m = /[?&]page=(\d+)/.exec(a.getAttribute('href') || '');
      if (m) max = Math.max(max, Number(m[1]));
    }
    return max || null;
  },

  async searchPage(params, page) {
    const query = {};
    for (const [k, v] of Object.entries(params)) if (v) query[k] = v;
    if (page > 1) query.page = String(page);
    const tags = query.tags;
    delete query.tags;
    let path = '/search';
    if (tags && tags.length) path += '?' + tags.map((t) => 'tags%5B%5D=' + encodeURIComponent(t)).join('&');
    const doc = await this.getDoc(path, query);
    const items = this.parseCards(doc);
    const maxPage = this.maxPage(doc);
    const totalPages = items.length ? Math.max(maxPage || 1, page) : maxPage;
    return { items, page, totalPages, hasNext: !!totalPages && page < totalPages };
  },

  async feed(key, req) {
    const page = Math.max(1, req.page || 1);
    const genre = this.genre();
    if (key === 'ranking') return this.searchPage({ genre, sort: (req.options && req.options.period) || '本週排行' }, page);
    if (key === 'uploads') return this.searchPage({ genre, sort: '最新上傳' }, page);
    return this.searchPage({ genre, sort: '最新上市' }, page);
  },

  async search(req) {
    const f = req.filters || {};
    const tags = Array.isArray(f.tags) ? f.tags : f.tags ? [f.tags] : [];
    return this.searchPage(
      { query: String(req.keyword || '').trim(), genre: this.genre(f.genre), sort: f.sort || '', tags },
      Math.max(1, req.page || 1)
    );
  },

  parseSources(doc) {
    const found = new Map();
    for (const s of doc.querySelectorAll('video source[src]')) {
      const q = Number(s.getAttribute('size')) || Number((/-(\d{3,4})p\.mp4/.exec(s.getAttribute('src')) || [])[1]);
      if (q && !found.has(q)) found.set(q, s.getAttribute('src'));
    }
    for (const a of doc.querySelectorAll('[data-url*=".mp4"], a[href*=".mp4"]')) {
      const url = a.getAttribute('data-url') || a.getAttribute('href');
      const m = /-(\d{3,4})p\.mp4/.exec(url);
      if (m && !found.has(Number(m[1]))) found.set(Number(m[1]), url);
    }
    return [...found.entries()].sort((a, b) => b[0] - a[0]).map(([quality, url]) => ({ quality, url }));
  },

  async detail(id) {
    const doc = await this.getDoc('/watch', { v: id });
    const og = (p) => {
      const el = doc.querySelector(`meta[property="og:${p}"]`);
      return el ? el.getAttribute('content') || '' : '';
    };
    const title = Park.html.text(doc.querySelector('#shareBtn-title')) || og('title').replace(/\s*-\s*Hanime1\.me\s*$/i, '');
    if (!title) throw Park.error('NOT_FOUND', `Hanime1 影片 ${id} 不存在或需要登录`);
    const panel = Park.html.text(doc.querySelector('.video-description-panel'));
    const vd = /(?:觀看次數|观看次数)：\s*([\d.,]+\s*[萬万億亿]?)次\s*(\d{4}-\d{2}-\d{2})?/.exec(panel);
    const tags = [];
    for (const el of doc.querySelectorAll('.single-video-tag a')) {
      const href = el.getAttribute('href') || '';
      const m = /tags%5B%5D=([^&]+)|tags\[\]=([^&]+)/.exec(href);
      const name = (el.childNodes[0] && el.childNodes[0].textContent ? el.childNodes[0].textContent : el.textContent)
        .replace(/ /g, ' ')
        .trim();
      // Only real tag links carry tags[]; the add / remove buttons in the same box do not.
      if (!m || !name) continue;
      const tag = decodeURIComponent(m[1] || m[2]);
      if (!tags.some((t) => t.name === name)) tags.push({ name, keyword: '', filters: { tags: [tag], genre: '全部' } });
    }
    const artist = Park.html.text(doc.querySelector('#video-artist-name'));
    // Each playlist entry is a thumbnail link plus a separate text link with the same href.
    const series = [];
    const seriesTitles = {};
    const playlist = [...doc.querySelectorAll('#playlist-scroll a[href*="watch?v="]')];
    for (const a of playlist) {
      const m = /watch\?v=(\d+)/.exec(a.getAttribute('href'));
      if (m && !a.querySelector('img') && Park.html.text(a)) seriesTitles[m[1]] = Park.html.text(a);
    }
    for (const a of playlist) {
      const m = /watch\?v=(\d+)/.exec(a.getAttribute('href'));
      const img = a.querySelector('img');
      if (!m || !img || series.some((s) => s.id === m[1])) continue;
      series.push({
        id: m[1],
        title: seriesTitles[m[1]] || img.getAttribute('alt') || `#${m[1]}`,
        cover: img.getAttribute('src') || '',
        coverAspect: 16 / 9,
        duration: (Park.html.text(a.querySelector('.duration')).match(/^[\d:]+/) || [''])[0],
      });
    }
    const related = this.parseCards(doc).filter((it) => it.id !== String(id) && !series.some((s) => s.id === it.id));
    const video = doc.querySelector('video');
    const sources = this.parseSources(doc);
    return {
      id: String(id),
      title,
      subtitle: Park.html.text(doc.querySelector('.video-description-panel div:not(.hidden-xs)')) || '',
      cover: (video && video.getAttribute('poster')) || og('image'),
      coverAspect: 16 / 9,
      url: `${this.BASE}/watch?v=${id}`,
      authors: artist ? [artist] : [],
      views: vd ? Park.utils.parseCount(vd[1]) : null,
      uploaded: vd && vd[2] ? vd[2] : '',
      description: Park.html.text(doc.querySelector('.video-caption-text')) || og('description'),
      tags: tags.length ? [{ namespace: 'tag', label: '标签', tags }] : [],
      authorSearch: artist ? { keyword: artist, filters: { genre: '全部' } } : null,
      series,
      related: related.slice(0, 24),
      qualities: sources.map((s) => s.quality),
    };
  },

  /** Fresh, playable sources (URLs expire), best first, with the extra qualities from /download. */
  async videos(id) {
    const [watch, download] = await Promise.all([
      this.getDoc('/watch', { v: id }),
      this.getDoc('/download', { v: id }).catch(() => null),
    ]);
    const merged = new Map();
    for (const s of this.parseSources(watch).concat(download ? this.parseSources(download) : [])) {
      if (!merged.has(s.quality)) merged.set(s.quality, s.url);
    }
    const list = [...merged.entries()]
      .sort((a, b) => b[0] - a[0])
      .map(([quality, url]) => ({ quality, label: `${quality}P`, url, headers: { Referer: `${this.BASE}/` } }));
    if (!list.length) throw Park.error('NOT_FOUND', '没有找到可用的视频源（可能需要登录）');
    const preferred = Number(this.config.quality) || 1080;
    const best = list.find((s) => s.quality <= preferred) || list[list.length - 1];
    best.preferred = true;
    return list;
  },
});
