/*
 * nhentai — official v2 anonymous API.
 *   GET /api/v2/search?query=&sort=&page=   (25 per page, query must not be empty → "*")
 *   GET /api/v2/galleries/{id} | /galleries/random | /cdn
 * The website is behind Cloudflare but the API currently is not; images come from i*.nhentai.net.
 */
(function () {
const browseFilters = [
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
  ];
Park.register({
  i18n: {
    "zh-Hant": {"nhentai {value0} 不存在": "nhentai {value0} 不存在", "nhentai 随机接口没有返回作品": "nhentai 隨機介面沒有返回作品", "应用于排行与搜索（关键词里写了 language: 时以关键词为准）": "應用於排行與搜尋（關鍵詞裡寫了 language: 時以關鍵詞為準）", "总热门": "總熱門", "支持 tag:\"big breasts\"、artist:xxx、-yaoi、pages:>20 等站内语法": "支援 tag:\"big breasts\"、artist:xxx、-yaoi、pages:>20 等站內語法", "海量同人志，官方 API，支持标签语法与语言过滤": "海量同人誌，官方 API，支援標籤語法與語言過濾", "源返回了不一致的作品标识": "來源傳回了不一致的作品識別碼", "默认语言过滤": "預設語言過濾"},
    "ja": {"nhentai {value0} 不存在": "nhentai の作品 {value0} は存在しません", "nhentai 随机接口没有返回作品": "nhentai からランダム作品を取得できませんでした", "应用于排行与搜索（关键词里写了 language: 时以关键词为准）": "ランキングと検索に適用します（検索語に language: がある場合はそちらを優先）", "总热门": "総合人気度", "支持 tag:\"big breasts\"、artist:xxx、-yaoi、pages:>20 等站内语法": "tag:\"big breasts\"、artist:xxx、-yaoi、pages:>20 などのサイト検索構文に対応", "海量同人志，官方 API，支持标签语法与语言过滤": "大規模な同人誌、公式 API、タグ構文と言語フィルタリングをサポート", "源返回了不一致的作品标识": "ソースが一致しない作品識別子を返しました", "默认语言过滤": "デフォルト言語フィルタリング"},
    "ko": {"nhentai {value0} 不存在": "nhentai 작품 {value0}이(가) 존재하지 않습니다", "nhentai 随机接口没有返回作品": "nhentai에서 무작위 작품을 반환하지 않았습니다", "应用于排行与搜索（关键词里写了 language: 时以关键词为准）": "순위와 검색에 적용됩니다. 검색어의 language: 필터가 우선합니다", "总热门": "총 인기도", "支持 tag:\"big breasts\"、artist:xxx、-yaoi、pages:>20 等站内语法": "tag:\"big breasts\", artist:xxx, -yaoi, pages:>20 등의 사이트 검색 구문 지원", "海量同人志，官方 API，支持标签语法与语言过滤": "공식 API인 대규모 동인지는 태그 구문 및 언어 필터링을 지원합니다.", "源返回了不一致的作品标识": "소스가 일치하지 않는 작품 식별자를 반환했습니다", "默认语言过滤": "기본 언어 필터"},
    "en": {"nhentai {value0} 不存在": "nhentai work {value0} does not exist", "nhentai 随机接口没有返回作品": "nhentai returned no random works", "应用于排行与搜索（关键词里写了 language: 时以关键词为准）": "Applies to rankings and search; a language: filter in the query takes priority", "总热门": "Total Popularity", "支持 tag:\"big breasts\"、artist:xxx、-yaoi、pages:>20 等站内语法": "Supports site search syntax such as tag:\"big breasts\", artist:xxx, -yaoi and pages:>20", "海量同人志，官方 API，支持标签语法与语言过滤": "Massive doujinshi, official API, supports tag syntax and language filtering", "源返回了不一致的作品标识": "The source returned an inconsistent work identifier", "默认语言过滤": "Default language filtering"},
    "es": {"nhentai {value0} 不存在": "La obra {value0} no existe en nhentai", "nhentai 随机接口没有返回作品": "nhentai no devolvió ninguna obra aleatoria", "应用于排行与搜索（关键词里写了 language: 时以关键词为准）": "Se aplica a clasificaciones y búsquedas; el filtro language: de la consulta tiene prioridad", "总热门": "Popularidad total", "支持 tag:\"big breasts\"、artist:xxx、-yaoi、pages:>20 等站内语法": "Admite sintaxis del sitio como tag:\"big breasts\", artist:xxx, -yaoi y pages:>20", "海量同人志，官方 API，支持标签语法与语言过滤": "Massive doujinshi, API oficial, admite sintaxis de etiquetas y filtrado de idiomas", "源返回了不一致的作品标识": "La fuente devolvió un identificador de obra inconsistente", "默认语言过滤": "Filtrado de idioma predeterminado"},
    "ru": {"nhentai {value0} 不存在": "Произведение {value0} не найдено в nhentai", "nhentai 随机接口没有返回作品": "nhentai не вернул случайных произведений", "应用于排行与搜索（关键词里写了 language: 时以关键词为准）": "Применяется к рейтингам и поиску; фильтр language: в запросе имеет приоритет", "总热门": "Общая популярность", "支持 tag:\"big breasts\"、artist:xxx、-yaoi、pages:>20 等站内语法": "Поддерживается синтаксис поиска сайта: tag:\"big breasts\", artist:xxx, -yaoi, pages:>20", "海量同人志，官方 API，支持标签语法与语言过滤": "Massive doujinshi, официальный API, поддерживает синтаксис тегов и языковую фильтрацию.", "源返回了不一致的作品标识": "Источник вернул несоответствующий идентификатор произведения", "默认语言过滤": "Фильтрация языка по умолчанию"},
    "ar": {"nhentai {value0} 不存在": "العمل {value0} غير موجود في nhentai", "nhentai 随机接口没有返回作品": "لم يُرجع nhentai أي أعمال عشوائية", "应用于排行与搜索（关键词里写了 language: 时以关键词为准）": "يُطبّق على الترتيب والبحث؛ تكون الأولوية لمرشح language: في عبارة البحث", "总热门": "إجمالي الشعبية", "支持 tag:\"big breasts\"、artist:xxx、-yaoi、pages:>20 等站内语法": "يدعم صيغ البحث في الموقع مثل tag:\"big breasts\" وartist:xxx و-yaoi وpages:>20", "海量同人志，官方 API，支持标签语法与语言过滤": "الدوجينشي الضخم، واجهة برمجة التطبيقات الرسمية، تدعم بناء جملة العلامة وتصفية اللغة", "源返回了不一致的作品标识": "أعاد المصدر معرّف عمل غير متطابق", "默认语言过滤": "تصفية اللغة الافتراضية"},
  },
  key: 'nhentai',
  name: 'nhentai',
  version: '0.0.10', minAppVersion: '0.9.2',
  type: 'comic',
  category: 'doujin',
  color: '#ED2553',
  icon: 'https://nhentai.net/favicon.ico',
  description: '海量同人志，官方 API，支持标签语法与语言过滤',
  homepage: 'https://nhentai.net',
  language: 'multi',
  linkPatterns: ['nhentai\\.(?:net|to|xxx|website)/g/(\\d+)'],
  idPattern: '^(?:nh)?(\\d{1,7})$',
  idExample: '177013',
  imageHeaders: { Referer: 'https://nhentai.net/' },
  network: { vpnHint: true, headers: { Accept: 'application/json' } },

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

  rankings: [{ key: 'popular', label: '排行榜', category: 'doujin', metric: '站内热门', feed: 'popular' }],
  defaultFeed: 'popular',
  feeds: [
    {key: 'category', label: '分类', options: browseFilters.filter(option => option.type !== 'number'), commonFilters: {pages: {range: ['min']} }},
    { key: 'latest', label: '最新', commonFilters: {pages: {range: ['min']} } },
    {
      key: 'popular',
      label: '热门',
      commonFilters: {pages: {range: ['min']}},
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
  searchFilters: browseFilters,
  searchCommonFilters: {pages: {range: ['min']}},
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

  commonPageClauses(common) {
    const pages = common?.pages || {};
    const clauses = [];
    if (pages.min !== undefined) clauses.push(`pages:>=${pages.min}`);
    return clauses;
  },

  async feed(key, req) {
    if (key === 'category') return this.search({keyword: '', page: req.page, cursor: req.cursor, filters: req.options || {}, common: req.common});
    const lang = this.defaultLanguageClause('', this.config.language);
    const clauses = this.commonPageClauses(req.common);
    if (key === 'latest') return this.listing({ query: [lang, ...clauses].filter(Boolean).join(' ') || '*', sort: 'date', page: req.page });
    const period = (req.options && req.options.period) || 'popular-week';
    return this.listing({ query: [lang, ...clauses].filter(Boolean).join(' ') || '*', sort: period, page: req.page });
  },

  async search(req) {
    const f = req.filters || {};
    const keyword = String(req.keyword || '').trim();
    const common = req.common || {};
    const lang = f.language === '@setting' || f.language === undefined ? this.config.language : f.language;
    const words = [keyword];
    words.push(this.defaultLanguageClause(keyword, lang));
    if (f.category) words.push(`category:${f.category}`);
    if (Number(f.minPages) > 0 && common.pages?.min === undefined) words.push(`pages:>=${Number(f.minPages)}`);
    words.push(...this.commonPageClauses(common));
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

  async comments(value, req = {}) {
    const id = String(value), page = Math.max(1, Math.floor(Number(req.page) || 1));
    if (!/^\d{1,12}$/.test(id)) throw Park.error('NOT_FOUND', '作品编号无效');
    if (req.parentId) return {items: [], hasNext: false};
    const data = await this.http.json(`${this.API}/galleries/${id}/comments`, {params: {page}});
    if (!Array.isArray(data.result) || !Number.isInteger(data.num_pages)) throw Park.error('PARSE', '评论数据无效');
    const items = data.result.map(c => {
      if (!c.id || String(c.gallery_id) !== id || typeof c.body !== 'string') throw Park.error('PARSE', '评论数据无效');
      return {id: String(c.id), author: {name: String(c.poster?.username || ''), avatar: c.poster?.avatar_url,
        url: c.poster?.id ? 'https://nhentai.net/users/' + c.poster.id + '/' : undefined},
        body: Park.comments.text(c.body), date: Number(c.post_date) ? new Date(Number(c.post_date) * 1000).toISOString() : undefined};
    }).filter(c => c.body.length);
    return {items, total: Number(data.total) || 0, hasNext: page < data.num_pages};
  },

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
    if (!d || !d.id) throw Park.error('NOT_FOUND', 'nhentai {value0} 不存在', { params: {value0: id} });
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

})();

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"}]});
