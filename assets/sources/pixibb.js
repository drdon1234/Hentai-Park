/* PixiBB — photo galleries. Site data is parsed, never executed. */
(function () {
  'use strict';
  const SITE = {
  "key": "pixibb",
  "name": "PixiBB",
  "domain": "pixibb.com",
  "home": "https://hub.pixibb.com",
  "api": "https://sexy.pixibb.com/wp-json/wp/v2",
  "color": "#02B6E8",
  "language": "en",
  "description": "Cosplay 与写真图集，支持推荐、分类与搜索",
  "ero": 0,
  "nude": 0,
  "categories": [
    10,
    112
  ],
  "excludeCategories": [
    74,
    209
  ],
  "excludeTags": [
    3472,
    3821
  ],
  "aiCategories": [
    24,
    119
  ],
  "aiTags": [
    3535,
    3881
  ],
  "popular": "/home/",
  "popularSelector": ".featured__post-single .post-title a[href]",
  "month": "",
  "week": "",
  "titleNoise": "\\s*\\(\\d+ photos?(?: \\+ \\d+ videos?)?\\)|\\s*\\bSexy (?:Cosplay|Girls?)\\s*$"
};
  const PAGE_SIZE = 20;
  const EXCLUDES = {categories: SITE.excludeCategories, tags: SITE.excludeTags};
  const cache = new Map();
  const popularCache = new Map();
  const option = {key: 'rating', label: '站点分级', type: 'select', default: 'all', values: [
    {value: 'all', label: '全部'}, {value: 'ero', label: '非裸露分类'}, {value: 'nude', label: '裸露分类'},
  ]};
  const filters = SITE.ero ? [option] : SITE.categories.length ? [{key: 'category', label: '分类', type: 'select', default: '', values: [
    {value: '', label: '全部'}, {value: '10', label: 'Cosplay'}, {value: '112', label: '写真'},
  ]}] : [];

  function hostAllowed(url, domain = SITE.domain) {
    try {
      const u = new URL(url);
      return u.protocol === 'https:' && !u.username && !u.password && (!u.port || u.port === '443') &&
        (u.hostname === domain || u.hostname.endsWith('.' + domain));
    } catch (_) { return false; }
  }
  function idValue(id) {
    let value;
    try { value = decodeURIComponent(String(id)); } catch (_) { throw Park.error('NOT_FOUND', '图集编号无效'); }
    if (!/^[\p{L}\p{N}_-]{1,240}$/u.test(value)) throw Park.error('NOT_FOUND', '图集编号无效');
    return value;
  }
  function numberFilter(value) {
    if (value === undefined || value === null || value === '') return '';
    if (!/^[1-9]\d{0,9}$/.test(String(value))) throw Park.error('CONFIG', '图片筛选参数无效');
    return String(value);
  }
  function pageNumber(value) { return Math.max(1, Math.floor(Number(value) || 1)); }
  function text(value) { return Park.html.strip(String(value || '')); }
  function title(post) { return text(post.title && post.title.rendered).replace(SITE.titleNoise ? new RegExp(SITE.titleNoise, 'i') : /$^/, '').trim(); }
  function terms(post, taxonomy) {
    return (post._embedded && post._embedded['wp:term'] || []).flat()
      .filter(t => t && t.taxonomy === taxonomy && Number.isInteger(t.id));
  }
  function excludes(source) {
    return {categories: [...EXCLUDES.categories, ...(source.config.blockAI ? SITE.aiCategories : [])],
      tags: [...EXCLUDES.tags, ...(source.config.blockAI ? SITE.aiTags : [])]};
  }
  function allowed(source, post, filters = {}) {
    if (!post || !Number.isSafeInteger(post.id) || post.id < 1) return false;
    const categories = post.categories || [], tags = post.tags || [], blocked = excludes(source);
    if (categories.some(c => blocked.categories.includes(c)) || tags.some(t => blocked.tags.includes(t))) return false;
    if (SITE.categories.length && !SITE.categories.some(c => categories.includes(c))) return false;
    if (SITE.ero && !categories.includes(SITE.ero) && !categories.includes(SITE.nude)) return false;
    if (filters.rating === 'ero' && (!categories.includes(SITE.ero) || categories.includes(SITE.nude))) return false;
    if (filters.rating === 'nude' && !categories.includes(SITE.nude)) return false;
    if (filters.category && !categories.includes(Number(filters.category))) return false;
    if (filters.tag && !tags.includes(Number(filters.tag))) return false;
    return true;
  }
  function images(post) {
    const doc = Park.html.parse(post.content && post.content.rendered || ''), out = [], seen = new Set();
    for (const img of doc.querySelectorAll('img')) {
      const url = Park.html.unescape(img.getAttribute('data-src') || img.getAttribute('src') || '').trim();
      if (!hostAllowed(url) || !/\.(?:jpe?g|png|webp|gif)$/i.test(new URL(url).pathname)) continue;
      if (SITE.domain !== 'pixibb.com' && !new URL(url).pathname.includes('/wp-content/uploads/')) continue;
      const width = Number(img.getAttribute('width')) || 0, height = Number(img.getAttribute('height')) || 0;
      if (width && height && Math.max(width, height) < 500 || seen.has(url)) continue;
      seen.add(url);
      out.push({url, ...(width ? {width} : {}), ...(height ? {height} : {})});
    }
    return out;
  }
  function remember(post) {
    cache.delete(String(post.id)); cache.set(String(post.id), {post, time: Date.now()});
    while (cache.size > 40) cache.delete(cache.keys().next().value);
  }
  function item(post) {
    const pages = images(post), media = (post._embedded && post._embedded['wp:featuredmedia'] || [])[0];
    const mediaUrl = media && media.source_url;
    const cover = hostAllowed(mediaUrl) ? mediaUrl : (pages[0] && pages[0].url || '');
    if (!pages.length || !cover || !title(post)) return null;
    const size = hostAllowed(mediaUrl) ? media.media_details || {} : pages[0];
    const category = terms(post, 'category').map(t => text(t.name)).join(' · ');
    return {id: String(post.id), title: title(post), cover, pages: pages.length, uploaded: post.date || '',
      category, ...(size.width > 0 && size.height > 0 ? {coverAspect: size.width / size.height} : {}),
      tags: terms(post, 'post_tag').map(t => text(t.name))};
  }
  function headersNumber(response, name) {
    const pair = Object.entries(response.headers || {}).find(([key]) => key.toLowerCase() === name);
    return pair && /^\d+$/.test(String(pair[1])) ? Number(pair[1]) : null;
  }
  function filtersFor(source, filters = {}) {
    const blocked = excludes(source), categories = [...SITE.categories];
    const params = {};
    if (SITE.ero) {
      const rating = filters.rating || 'all';
      if (!['all', 'ero', 'nude'].includes(rating)) throw Park.error('CONFIG', '图片筛选参数无效');
      categories.push(...(rating === 'ero' ? [SITE.ero] : rating === 'nude' ? [SITE.nude] : [SITE.ero, SITE.nude]));
      if (rating === 'ero') blocked.categories.push(SITE.nude);
    }
    const category = numberFilter(filters.category), tag = numberFilter(filters.tag);
    if (category) params.categories = category;
    else if (categories.length) params.categories = categories.join(',');
    if (tag) params.tags = tag;
    if (blocked.categories.length) params.categories_exclude = blocked.categories.join(',');
    if (blocked.tags.length) params.tags_exclude = blocked.tags.join(',');
    return params;
  }
  async function posts(source, params) {
    const response = await source.http.get(SITE.api + '/posts', {params: {_embed: 'wp:term,wp:featuredmedia', ...params}});
    if (!response.ok) {
      let code;
      try { code = response.json().code; } catch (_) { /* Status remains authoritative. */ }
      if (response.status === 400 && code === 'rest_post_invalid_page_number') return {data: [], response, ended: true};
      throw Park.error('HTTP', 'HTTP ' + response.status, {status: response.status});
    }
    const data = response.json();
    if (!Array.isArray(data)) throw Park.error('PARSE', '图集数据格式无效');
    data.forEach(remember);
    return {data, response, ended: false};
  }
  async function listing(source, req, filters = {}, extra = {}) {
    const page = pageNumber(req.page), query = filtersFor(source, filters);
    const {data, response, ended} = await posts(source, {per_page: PAGE_SIZE, page, ...query, ...extra});
    const totalPages = headersNumber(response, 'x-wp-totalpages'), total = headersNumber(response, 'x-wp-total');
    return {items: data.filter(p => allowed(source, p, filters)).map(item).filter(Boolean), page,
      ...(totalPages !== null ? {totalPages} : {}), ...(total !== null ? {total} : {}),
      hasNext: !ended && (totalPages !== null ? page < totalPages : data.length === PAGE_SIZE)};
  }
  function popularSlugs(html) {
    const doc = Park.html.parse(html), slugs = [];
    let links;
    if (SITE.key === 'cosplaytele') {
      const heading = [...doc.querySelectorAll('h3')].find(h => /Popular Cosplay/i.test(Park.html.text(h)));
      const slider = heading && heading.parentElement.nextElementSibling;
      links = slider ? slider.querySelectorAll('.post-title a[href]') : [];
    } else links = doc.querySelectorAll(SITE.popularSelector);
    for (const link of links) {
      const href = link.getAttribute('href');
      if (!hostAllowed(href)) continue;
      const match = /^\/([^/]+)\/$/.exec(new URL(href).pathname);
      if (!match) continue;
      try { const slug = idValue(match[1]); if (!slugs.includes(slug)) slugs.push(slug); } catch (_) { /* Ignore non-work links. */ }
    }
    if (!slugs.length) throw Park.error('PARSE', '未找到图片推荐或热门列表');
    return slugs.slice(0, 100);
  }
  async function popular(source, req, path) {
    const filters = req.options || {}, params = filtersFor(source, filters);
    const cacheKey = path + JSON.stringify(params), cached = popularCache.get(cacheKey);
    let ordered;
    if (cached && Date.now() - cached.time < 60 * 1000) ordered = cached.items;
    else {
      const html = await source.http.text(SITE.home + path), slugs = popularSlugs(html), data = [];
      // Bounded REST batches avoid fetching dozens of full gallery bodies in one response.
      for (let offset = 0; offset < slugs.length; offset += PAGE_SIZE) {
        const batch = await posts(source, {per_page: PAGE_SIZE, slug: slugs.slice(offset, offset + PAGE_SIZE).join(','), ...params});
        data.push(...batch.data);
      }
      ordered = slugs.map(slug => data.find(p => {
        try { return decodeURIComponent(p.slug) === slug; } catch (_) { return false; }
      })).filter(p => allowed(source, p, filters)).map(item).filter(Boolean);
      popularCache.delete(cacheKey); popularCache.set(cacheKey, {time: Date.now(), items: ordered});
      while (popularCache.size > 12) popularCache.delete(popularCache.keys().next().value);
    }
    const page = pageNumber(req.page), totalPages = Math.max(1, Math.ceil(ordered.length / PAGE_SIZE));
    return {items: ordered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE), page, total: ordered.length, totalPages, hasNext: page < totalPages};
  }
  async function getPost(source, value) {
    const id = idValue(value), cached = cache.get(id);
    if (cached && Date.now() - cached.time < 5 * 60 * 1000) {
      if (!allowed(source, cached.post)) throw Park.error('BLOCKED', '此图集已被站点的筛选规则屏蔽');
      return cached.post;
    }
    let post;
    if (/^[1-9]\d{0,14}$/.test(id)) {
      post = await source.http.json(SITE.api + '/posts/' + id, {params: {_embed: 'wp:term,wp:featuredmedia'}});
    } else {
      const {data} = await posts(source, {slug: id, per_page: 1});
      post = data[0];
    }
    if (!post || !post.id) throw Park.error('NOT_FOUND', '图集不存在');
    if (!allowed(source, post)) throw Park.error('BLOCKED', '此图集已被站点的筛选规则屏蔽');
    if (!item(post)) throw Park.error('NOT_FOUND', '此图集没有可用图片');
    remember(post);
    return post;
  }

  Park.register({
    i18n: {
      "zh-Hant": {"Cosplay 与写真图集，支持推荐、分类与搜索": "Cosplay 與寫真圖集，支援推薦、分類與搜尋", "PixiBB": "PixiBB"},
      "ja": {"Cosplay 与写真图集，支持推荐、分类与搜索": "コスプレ・写真集。おすすめ・カテゴリ・検索に対応", "PixiBB": "PixiBB"},
      "ko": {"Cosplay 与写真图集，支持推荐、分类与搜索": "코스플레이 및 화보, 추천·분류·검색 지원", "PixiBB": "PixiBB"},
      "en": {"Cosplay 与写真图集，支持推荐、分类与搜索": "Cosplay and photo galleries with recommendations, categories and search", "PixiBB": "PixiBB"},
      "es": {"Cosplay 与写真图集，支持推荐、分类与搜索": "Galerías de cosplay y fotografía con recomendaciones, categorías y búsqueda", "PixiBB": "PixiBB"},
      "ru": {"Cosplay 与写真图集，支持推荐、分类与搜索": "Косплей и фотосессии: рекомендации, категории и поиск", "PixiBB": "PixiBB"},
      "ar": {"Cosplay 与写真图集，支持推荐、分类与搜索": "معارض كوسبلاي وتصوير مع توصيات وتصنيفات وبحث", "PixiBB": "PixiBB"},
    },
    key: SITE.key, name: SITE.name, version: '0.0.3', type: 'comic', category: 'gallery',
    color: SITE.color, description: SITE.description, homepage: SITE.home, domains: [SITE.domain], language: SITE.language,
    network: {mode: 'native', vpnHint: true}, imageHeaders: {Referer: SITE.home + '/'},
    linkPatterns: [SITE.domain.replace(/\./g, '\\.') + '/([^/?#]+)(?:/|[?#]|$)'], idPattern: '^[1-9]\\d{0,14}$',
    defaultFeed: SITE.key === 'pixibb' ? 'recommend' : 'popular',
    feeds: [
      {key: SITE.key === 'pixibb' ? 'recommend' : 'popular', label: SITE.key === 'pixibb' ? '推荐' : '热门', options: filters},
      ...(SITE.month ? [{key: 'month', label: '本月热门', options: filters},
        {key: 'week', label: '本周热门', options: filters}] : []),
      {key: 'latest', label: '最新', options: filters},
    ],
    searchFilters: filters,
    searchHint: '搜索角色、作品名、模特或 Coser',
    settings: [{key: 'blockAI', label: '屏蔽 AI 图片', type: 'switch', default: true}],
    async feed(key, req) {
      if (key === 'latest') return listing(this, req, req.options || {});
      if (key === 'popular' && SITE.key !== 'pixibb' || key === 'recommend' && SITE.key === 'pixibb') return popular(this, req, SITE.popular);
      if (key === 'month' && SITE.month) return popular(this, req, SITE.month);
      if (key === 'week' && SITE.week) return popular(this, req, SITE.week);
      throw Park.error('CONFIG', '未知图片列表');
    },
    async search(req) { return listing(this, req, req.filters || {}, {search: String(req.keyword || '').trim()}); },
    async random() {
      const initial = await listing(this, {page: 1});
      if (!initial.total) {
        if (!initial.items.length) throw Park.error('NOT_FOUND', '没有可用图集');
        return initial.items[Math.floor(Math.random() * initial.items.length)].id;
      }
      const page = Math.floor(Math.random() * initial.total) + 1;
      const {data} = await posts(this, {per_page: 1, page, ...filtersFor(this)});
      const found = data.find(p => allowed(this, p) && item(p));
      if (!found) throw Park.error('NOT_FOUND', '没有可用图集');
      return String(found.id);
    },
    async detail(id) {
      const post = await getPost(this, id), entry = item(post);
      const groups = ['category', 'post_tag'].map(taxonomy => ({namespace: taxonomy === 'category' ? 'category' : 'tag',
        label: taxonomy === 'category' ? '分类' : '标签', tags: terms(post, taxonomy).map(term => ({name: text(term.name), keyword: '',
          filters: {[taxonomy === 'category' ? 'category' : 'tag']: String(term.id)}}))})).filter(g => g.tags.length);
      return {...entry, url: hostAllowed(post.link) ? post.link : SITE.home, chapters: null, authors: [],
        thumbnails: images(post).map(page => page.url),
        description: text(post.excerpt && post.excerpt.rendered), tags: groups};
    },
    async chapter(id) { return {pages: images(await getPost(this, id))}; },
  });
})();

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"}]});
