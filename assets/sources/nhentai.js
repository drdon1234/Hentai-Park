/*
 * nhentai — official v2 anonymous API.
 *   GET /api/v2/search?query=&sort=&page=   (25 per page, query must not be empty → "*")
 *   GET /api/v2/galleries/{id} | /galleries/random | /cdn
 * The website is behind Cloudflare but the API currently is not; images come from i*.nhentai.net.
 */
Park.register({
  key: 'nhentai',
  name: 'nhentai',
  version: '0.0.2',
  type: 'comic',
  color: '#ED2553',
  icon: 'https://nhentai.net/favicon.ico',
  description: '海量同人志，官方 API，支持标签语法与语言过滤',
  homepage: 'https://nhentai.net',
  language: 'multi',
  linkPatterns: ['nhentai\\.(?:net|to|xxx|website)/g/(\\d+)'],
  idPattern: '^(?:nh)?(\\d{1,7})$',
  idExample: '177013',
  imageHeaders: { Referer: 'https://nhentai.net/' },
  network: { headers: { Accept: 'application/json' } },

  settings: [
    {
      key: 'language',
      type: 'select',
      label: '默认语言过滤',
      description: '应用于排行与搜索（关键词里写了 language: 时以关键词为准）',
      default: '',
      options: [
        { value: '', label: '不限' },
        { value: 'chinese', label: '中文' },
        { value: 'japanese', label: '日文' },
        { value: 'english', label: '英文' },
      ],
    },
  ],

  defaultFeed: 'popular',
  feeds: [
    { key: 'latest', label: '最新' },
    {
      key: 'popular',
      label: '热门',
      options: [
        {
          key: 'period',
          label: '周期',
          default: 'popular-week',
          values: [
            { value: 'popular-today', label: '今日' },
            { value: 'popular-week', label: '本周' },
            { value: 'popular-month', label: '本月' },
            { value: 'popular', label: '总榜' },
          ],
        },
      ],
    },
  ],

  searchHint: '支持 tag:"big breasts"、artist:xxx、-yaoi、pages:>20 等站内语法',
  searchFilters: [
    {
      key: 'sort',
      label: '排序',
      default: 'date',
      values: [
        { value: 'date', label: '最新' },
        { value: 'popular-today', label: '今日热门' },
        { value: 'popular-week', label: '本周热门' },
        { value: 'popular-month', label: '本月热门' },
        { value: 'popular', label: '总热门' },
      ],
    },
    {
      key: 'language',
      label: '语言',
      default: '@setting',
      values: [
        { value: '@setting', label: '跟随设置' },
        { value: '', label: '不限' },
        { value: 'chinese', label: '中文' },
        { value: 'japanese', label: '日文' },
        { value: 'english', label: '英文' },
      ],
    },
    {
      key: 'category',
      label: '分类',
      default: '',
      values: [
        { value: '', label: '全部' },
        { value: 'doujinshi', label: '同人志' },
        { value: 'manga', label: '漫画' },
      ],
    },
    { key: 'minPages', label: '最少页数', type: 'number', default: 0 },
  ],

  API: 'https://nhentai.net/api/v2',
  LANGUAGE_TAGS: { 29963: '中文', 6346: '日文', 12227: '英文' },
  servers: null,

  async init() {
    this.pageCache = Park.utils.lruMap(8);
    this.pageRequests = new Map();
    await this.cdn().catch(() => {});
  },

  async cdn() {
    if (this.servers) return this.servers;
    let data = null;
    try {
      data = await this.http.json(`${this.API}/cdn`);
    } catch (e) {
      /* fall back to defaults */
    }
    const pick = (list, prefix) =>
      Array.isArray(list) && list.length ? list : [1, 2, 3, 4].map((n) => `https://${prefix}${n}.nhentai.net`);
    this.servers = { images: pick(data && data.image_servers, 'i'), thumbs: pick(data && data.thumb_servers, 't') };
    return this.servers;
  },

  /** Paths sometimes carry doubled extensions ("cover.webp.webp"). */
  fixPath(p) {
    return String(p || '').replace(/(\.(?:jpg|jpeg|png|webp|gif))(?:\.(?:jpg|jpeg|png|webp|gif))+$/i, '$1');
  },

  async thumbUrl(p) {
    if (!p) return '';
    if (/^https?:/.test(p)) return p;
    const { thumbs } = await this.cdn();
    return `${thumbs[0]}/${this.fixPath(p)}`;
  },

  languageOf(tagIds) {
    for (const id of tagIds || []) if (this.LANGUAGE_TAGS[id]) return this.LANGUAGE_TAGS[id];
    return '';
  },

  async toItem(r) {
    return {
      id: String(r.id),
      title: r.english_title || r.japanese_title || String(r.id),
      subtitle: r.japanese_title || '',
      cover: await this.thumbUrl(r.thumbnail),
      coverAspect: r.thumbnail_width && r.thumbnail_height ? r.thumbnail_width / r.thumbnail_height : null,
      pages: r.num_pages || 0,
      likes: r.num_favorites || 0,
      language: this.languageOf(r.tag_ids),
    };
  },

  async listing(params) {
    const page = Math.max(1, params.page || 1);
    const data = await this.http.json(`${this.API}/search`, {
      params: { query: params.query || '*', sort: params.sort || 'date', page },
    });
    const items = await Promise.all((data.result || []).map((r) => this.toItem(r)));
    const totalPages = data.num_pages || null;
    return { items, page, totalPages, total: data.total || null, hasNext: !!totalPages && page < totalPages };
  },

  defaultLanguageClause(keyword, lang) {
    if (!lang || /language:/i.test(keyword || '')) return '';
    return `language:${lang}`;
  },

  async feed(key, req) {
    const lang = this.defaultLanguageClause('', this.config.language);
    if (key === 'latest') return this.listing({ query: lang || '*', sort: 'date', page: req.page });
    const period = (req.options && req.options.period) || 'popular-week';
    return this.listing({ query: lang || '*', sort: period, page: req.page });
  },

  async search(req) {
    const f = req.filters || {};
    const keyword = String(req.keyword || '').trim();
    const lang = f.language === '@setting' || f.language === undefined ? this.config.language : f.language;
    const words = [keyword];
    words.push(this.defaultLanguageClause(keyword, lang));
    if (f.category) words.push(`category:${f.category}`);
    if (Number(f.minPages) > 0) words.push(`pages:>=${Number(f.minPages)}`);
    const query = words.filter(Boolean).join(' ').trim();
    return this.listing({ query: query || '*', sort: f.sort || 'date', page: req.page });
  },

  async random() {
    const data = await this.http.json(`${this.API}/galleries/random`);
    if (!data || !data.id) throw Park.error('NOT_FOUND', 'nhentai 随机接口没有返回作品');
    return String(data.id);
  },

  TAG_GROUPS: [
    ['parody', '原作'],
    ['character', '角色'],
    ['artist', '作者'],
    ['group', '社团'],
    ['language', '语言'],
    ['category', '分类'],
    ['tag', '标签'],
  ],

  async detail(id) {
    return (await this.fetchDetail(id)).detail;
  },

  async fetchDetail(id) {
    const key = String(id);
    const owner = this.http.invocation;
    let requests = this.pageRequests.get(owner);
    if (!requests) this.pageRequests.set(owner, requests = new Map());
    if (requests.has(key)) return requests.get(key);
    const pending = this.loadDetail(key);
    requests.set(key, pending);
    try { return await pending; } finally {
      requests.delete(key);
      if (!requests.size) this.pageRequests.delete(owner);
    }
  },

  async loadDetail(id) {
    const d = await this.http.json(`${this.API}/galleries/${encodeURIComponent(id)}`);
    if (!d || !d.id) throw Park.error('NOT_FOUND', `nhentai ${id} 不存在`);
    const byType = {};
    for (const t of d.tags || []) (byType[t.type] = byType[t.type] || []).push(t);
    const quote = (name) => (name.includes(' ') ? `"${name}"` : name);
    const tags = this.TAG_GROUPS.filter(([type]) => byType[type])
      .map(([type, label]) => ({
        namespace: type,
        label,
        tags: byType[type].map((t) => ({ name: t.name, keyword: `${type}:${quote(t.name)}`, count: t.count })),
      }));
    const { images } = await this.cdn();
    const pages = (d.pages || []).map((p, i) => ({
      url: `${images[i % images.length]}/${this.fixPath(p.path)}`,
      fallbacks: images.filter((_, j) => j !== i % images.length).map((s) => `${s}/${this.fixPath(p.path)}`),
      width: p.width,
      height: p.height,
      thumb: p.thumbnail ? `${this.servers.thumbs[0]}/${this.fixPath(p.thumbnail)}` : '',
    }));
    if (String(d.id) !== String(id)) throw Park.error('PARSE', '源返回了不一致的作品标识');
    this.pageCache.set(String(id), pages);
    const authors = [...(byType.artist || []), ...(byType.group || [])].map((t) => t.name);
    const languages = (byType.language || []).map((t) => t.name).filter((n) => n !== 'translated');
    return { pages, detail: {
      id: String(d.id),
      title: (d.title && (d.title.english || d.title.pretty)) || String(d.id),
      subtitle: (d.title && d.title.japanese) || '',
      cover: await this.thumbUrl((d.cover && d.cover.path) || (d.thumbnail && d.thumbnail.path)),
      url: `https://nhentai.net/g/${d.id}/`,
      authors,
      category: (byType.category || []).map((t) => t.name).join(', '),
      language: languages.join(', '),
      pages: d.num_pages || pages.length,
      likes: d.num_favorites || 0,
      uploaded: Park.utils.formatDate(d.upload_date),
      tags,
      chapters: null,
      thumbnails: pages.map((p) => p.thumb),
    } };
  },

  async chapter(id) {
    const key = String(id);
    let pages = this.pageCache.get(key);
    if (!pages) {
      // Keep the pages on this request's result too: a bounded cache may evict
      // this ID while many other requests finish concurrently.
      pages = (await this.fetchDetail(key)).pages;
    }
    return { pages: pages.map(({ url, fallbacks, width, height }) => ({ url, fallbacks, width, height })) };
  },
});
