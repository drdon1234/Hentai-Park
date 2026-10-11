/* WNACG — public galleries and chapter collections. Remote scripts are parsed as data only. */
(function () {
  const ORIGINS = ['https://www.wn001.cfd', 'https://www.wn002.cfd', 'https://www.wn10.cfd', 'https://www.wnacg.com', 'https://www.wnacg.ru'];
  const CATEGORIES = [
    ['5', '同人志'], ['1', '同人志（汉化）'], ['12', '同人志（日文）'], ['16', '同人志（英文）'],
    ['6', '单行本'], ['9', '单行本（汉化）'], ['13', '单行本（日文）'], ['17', '单行本（英文）'],
    ['7', '短篇'], ['10', '短篇（汉化）'], ['14', '短篇（日文）'], ['18', '短篇（英文）'],
    ['19', '韩漫'], ['38', '韩漫合集'], ['2', 'CG画集'], ['37', 'AI图集'], ['22', '3D漫画'], ['3', 'Cosplay'],
  ].map(([value, label]) => ({ value, label }));
  const text = (node) => Park.html.text(node).replace(/\s+/g, ' ').trim();
  const error = () => Park.error('PARSE', '源返回了无效结果');
  const missing = () => Park.error('NOT_FOUND', '内容不存在');
  const idOf = (value) => {
    const id = String(value ?? '');
    if (!/^\d{1,9}$/.test(id)) throw missing();
    return id;
  };
  const originOf = (value) => {
    try {
      const url = new URL(value);
      return /^https?:$/.test(url.protocol) && /^(?:www\.)?(?:wn\d+\.cfd|wnacg\.(?:com|ru))$/.test(url.hostname) && !url.port && !url.username && !url.password
        ? `https://${url.hostname}` : null;
    } catch (_) { return null; }
  };
  const imageUrl = (value, origin) => {
    const raw = String(value || '').trim().replace(/^\/{2,}/, '//');
    if (!raw) return '';
    try {
      const url = new URL(raw, origin);
      if (!/^https?:$/.test(url.protocol)) return '';
      url.protocol = 'https:';
      return url.href;
    } catch (_) { return ''; }
  };
  const pageNumber = (url) => Number(/-page-(\d+)/.exec(url.pathname)?.[1] || url.searchParams.get('p') || url.searchParams.get('page') || 1);
  const pageInfo = (doc, origin, page) => {
    const links = [...doc.querySelectorAll('.paginator a[href]')].map((a) => new URL(a.getAttribute('href'), origin));
    const next = links.find((url) => pageNumber(url) === page + 1);
    // Preserve the search engine's opaque c cursor, but never its origin.
    const cursor = next && originOf(next.href) ? next.pathname + next.search : null;
    return { page, hasNext: !!cursor, cursor };
  };
  const language = (category) => /漢化|汉化/.test(category) ? 'chinese' : /日語|日文/.test(category) ? 'japanese' : /English|英文/i.test(category) ? 'english' : '';

  Park.register({
    key: 'wnacg', name: '绅士漫画', version: '0.0.1', type: 'comic', color: '#E86F9C',
    description: '汉化漫画与图集，支持多话合集和自动切换线路',
    homepage: 'https://www.wnacg.com', language: 'multi',
    domains: ['wnacg.com', 'wnacg.ru', 'wn001.cfd', 'wn002.cfd', 'wn10.cfd', 'wnacg01.link', 'wnacg02.link'],
    linkPatterns: [
      '(?:^|[\\s:：（(【<])https?://(?:www\\.)?(?:wn\\d+\\.cfd|wnacg\\.(?:com|ru))/photos-(?:index|slide|list)-(?:page-\\d+-)?aid-(\\d+)(?:-sid-\\d+)?(?:-page-\\d+)?\\.html(?=$|[\\s）)】>,;，；。?#])',
      '(?:^|[\\s:：（(【<])(?:[Ww][Nn][Aa][Cc][Gg]|[Ww][Nn])\\s*[-_:：#]?\\s*(\\d{1,9})(?!\\d)',
    ],
    idPattern: '^(?:(?:[Ww][Nn][Aa][Cc][Gg]|[Ww][Nn])\\s*)?(\\d{1,9})$',
    idExample: 'WNACG395071',
    imageHeaders: { Referer: 'https://www.wnacg.com/' },
    network: { mode: 'native', headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
    } },
    defaultFeed: 'latest',
    feeds: [
      { key: 'latest', label: '最新' },
      { key: 'ranking', label: '排行榜', options: [{ key: 'period', label: '周期', default: 'week', values: [
        { value: 'day', label: '今日' }, { value: 'week', label: '本周' }, { value: 'month', label: '本月' }, { value: 'year', label: '今年' },
      ] }] },
      { key: 'category', label: '分类', options: [{ key: 'category', label: '分类', default: '1', values: CATEGORIES }] },
    ],
    searchHint: '可搜索作品名、作者；支持 tag:标签 和 WNACG 编号直达',
    searchFilters: [{ key: 'sort', label: '排序', default: 'create_time_DESC', values: [
      { value: 'create_time_DESC', label: '最新' }, { value: 'heat_day_DESC', label: '今日热门' },
      { value: 'heat_week_DESC', label: '本周热门' }, { value: 'heat_month_DESC', label: '本月热门' }, { value: 'heat_year_DESC', label: '今年' },
    ] }],

    async init() {
      const saved = this.store.get('origins', []);
      this.origins = [...new Set([this.store.get('origin'), ...(Array.isArray(saved) ? saved : []), ...ORIGINS].map(originOf).filter(Boolean))];
      this.pageCache = new Map();
      this.pageRequests = new Map();
      this.thumbSizes = new Map();
    },

    async refreshOrigins() {
      if (this.originRefresh) return this.originRefresh;
      this.originRefresh = (async () => {
        for (const url of ['https://wnacg01.link/', 'https://wnacg02.link/']) {
          try {
            const html = await this.http.text(url, { timeout: 6000 });
            const hosts = html.match(/(?:https?:\/\/)?(?:www\.)?(?:wn\d+\.cfd|wnacg\.(?:com|ru))\b/g) || [];
            const origins = [...new Set(hosts.map((host) => originOf(/^https?:/.test(host) ? host : `https://${host}`)).filter(Boolean))];
            if (!origins.length) continue;
            this.origins = [...new Set([...origins, ...this.origins])].slice(0, 10);
            this.store.set('origins', this.origins);
            return;
          } catch (_) { /* Try the other official publication page. */ }
        }
      })();
      try { await this.originRefresh; } finally { this.originRefresh = null; }
    },

    async request(path, parse) {
      if (!path.startsWith('/') || path.startsWith('//')) throw error();
      let lastError;
      const tried = new Set();
      for (let round = 0; round < 2; round++) {
        for (const origin of [...this.origins]) {
          if (tried.has(origin)) continue;
          tried.add(origin);
          try {
            const res = await this.http.get(origin + path, { timeout: 12000, headers: { Referer: origin + '/' } });
            this.http.ensureOk(res);
            if (!originOf(res.url || origin)) throw error();
            const result = parse(String(res.body), origin);
            this.origins = [origin, ...this.origins.filter((x) => x !== origin)];
            this.store.set('origin', origin);
            return result;
          } catch (e) {
            // A stale mirror may return HTTP 404, the homepage, or a different work.
            // Preserve the failure if no other verified mirror can serve this request.
            lastError = e;
          }
        }
        if (round === 0) await this.refreshOrigins();
      }
      throw lastError || error();
    },

    async document(path) {
      return this.request(path, (html, origin) => {
        const doc = Park.html.parse(html);
        const id = /^\/photos-index-.*?aid-(\d+)/.exec(path)?.[1];
        if (id) {
          const labels = [...doc.querySelectorAll('.uwconn label')].map(text);
          if (!doc.querySelector('.userwrap h2') || !labels.some((label) => new RegExp(`\\bwnacg${id}(?!\\d)`, 'i').test(label))) throw missing();
        }
        if (!doc.querySelector('.gallary_wrap, .userwrap, .sr_compact')) throw error();
        return { doc, origin };
      });
    },

    parseList(doc, origin, page) {
      const items = [];
      const seen = new Set();
      for (const card of doc.querySelectorAll('.gallary_item')) {
        const anchor = card.querySelector('.title a[href]');
        const id = /\/photos-index-aid-(\d+)\.html/.exec(anchor?.getAttribute('href') || '')?.[1];
        if (!id || seen.has(id)) continue;
        seen.add(id);
        const img = card.querySelector('.pic_box img');
        const info = text(card.querySelector('.info_col'));
        const categoryId = /\bcate-(\d+)\b/.exec(card.querySelector('.pic_box')?.className || '')?.[1];
        const category = CATEGORIES.find((c) => c.value === categoryId)?.label || '';
        items.push({
          id, title: text(anchor), cover: imageUrl(img?.getAttribute('data-original') || img?.getAttribute('src'), origin),
          pages: Number(/(\d+)\s*張圖片/.exec(info)?.[1]) || undefined,
          uploaded: /\d{4}-\d{2}-\d{2}/.exec(info)?.[0] || '',
          category, language: language(category), badge: text(card.querySelector('.sr_ctag')),
        });
      }
      return { items, ...pageInfo(doc, origin, page) };
    },

    async feed(key, { page = 1, cursor, options = {} } = {}) {
      let path;
      if (key === 'ranking') {
        const period = ['day', 'week', 'month', 'year'].includes(options.period) ? options.period : 'week';
        path = `/albums-favorite_ranking-page-${page}-type-${period}.html`;
      } else if (key === 'category') {
        const category = CATEGORIES.some((c) => c.value === String(options.category)) ? String(options.category) : '1';
        path = page === 1 ? `/albums-index-cate-${category}.html` : `/albums-index-page-${page}-cate-${category}.html`;
      } else {
        path = page === 1 ? '/albums.html' : `/albums-index-page-${page}.html`;
      }
      if (cursor && page > 1) path = cursor;
      const { doc, origin } = await this.document(path);
      return this.parseList(doc, origin, page);
    },

    async search({ keyword = '', page = 1, cursor, filters = {} }) {
      const query = keyword.trim();
      if (!query) return this.feed('latest', { page, cursor });
      let path;
      if (/^tag:/i.test(query)) {
        const tag = query.slice(4).trim().replace(/^"(.*)"$/, '$1');
        if (!tag) return { items: [], page, hasNext: false };
        path = `/albums-index-page-${page}-tag-${encodeURIComponent(tag)}.html`;
      } else {
        const sort = this.searchFilters[0].values.some((v) => v.value === filters.sort) ? filters.sort : 'create_time_DESC';
        path = `/search/?q=${encodeURIComponent(query)}&f=_all&s=${sort}&syn=yes&p=${page}`;
      }
      const { doc, origin } = await this.document(cursor && page > 1 ? cursor : path);
      return this.parseList(doc, origin, page);
    },

    thumbs(doc, origin, offset = 0) {
      return [...doc.querySelectorAll('.gallary_item')].map((card, index) => {
        const img = card.querySelector('.pic_box img');
        return { url: imageUrl(img?.getAttribute('data-original') || img?.getAttribute('src'), origin), index: offset + index };
      }).filter((img) => img.url);
    },

    async detail(value) {
      const id = idOf(value);
      const path = `/photos-index-aid-${id}.html?order=asc&mode=list`;
      const { doc, origin } = await this.document(path);
      const heading = doc.querySelector('.userwrap h2');
      const info = doc.querySelector('.uwconn');
      const labels = [...(info?.querySelectorAll('label') || [])].map(text);
      const category = labels.find((s) => s.startsWith('分類：'))?.replace(/^分類：/, '') || '';
      const pages = Number(/頁數：(\d+)/.exec(labels.join(' '))?.[1]) || undefined;
      const totalChapters = Number(/章節：(\d+)/.exec(labels.join(' '))?.[1]) || 0;
      let chapters = null;
      if (doc.querySelector('#sr_pub')) {
        const collected = new Map();
        let current = { doc, origin };
        let page = 1;
        const visited = new Set();
        while (true) {
          const before = collected.size;
          for (const a of current.doc.querySelectorAll('a[data-chid]')) {
            const chapterId = idOf(a.getAttribute('data-chid'));
            collected.set(chapterId, { id: chapterId, title: text(a) });
          }
          if (collected.size === before) throw error();
          const next = pageInfo(current.doc, current.origin, page).cursor;
          if (!next) break;
          if (visited.has(next)) throw error();
          visited.add(next);
          const nextUrl = new URL(next, origin);
          nextUrl.searchParams.set('order', 'asc');
          nextUrl.searchParams.set('mode', 'list');
          current = await this.document(nextUrl.pathname + nextUrl.search);
          page++;
        }
        chapters = [...collected.values()];
        if (totalChapters && chapters.length !== totalChapters) throw error();
      }
      const tags = [...doc.querySelectorAll('.addtags a.tagshow[href]')].map((a) => ({ name: text(a), keyword: `tag:${text(a)}` }));
      const thumbnails = chapters ? [] : this.thumbs(doc, origin);
      if (thumbnails.length) this.thumbSizes.set(id, thumbnails.length);
      return {
        id, title: text(heading), url: `${origin}/photos-index-aid-${id}.html`,
        cover: imageUrl(doc.querySelector('.uwthumb img')?.getAttribute('src'), origin),
        category, language: language(category), pages, chapters, authors: [],
        description: text(info?.querySelector('p')).replace(/^簡介：/, ''),
        uploader: text(doc.querySelector('.uwuinfo a[href*="albums-user"]')),
        tags: tags.length ? [{ namespace: 'tag', label: '标签', tags }] : [],
        thumbnails, thumbnailsTotal: chapters ? 0 : pages,
      };
    },

    async thumbnails(value, page) {
      const id = idOf(value);
      // The host counts additional thumbnail pages from 1; the website starts at 1.
      const { doc, origin } = await this.document(`/photos-index-page-${page + 1}-aid-${id}.html`);
      return { thumbnails: this.thumbs(doc, origin, page * (this.thumbSizes.get(id) || 12)), ...pageInfo(doc, origin, page + 1) };
    },

    async imagePages(value, refresh = false) {
      const id = idOf(value);
      if (this.pageRequests.has(id)) return this.pageRequests.get(id);
      const cached = this.pageCache.get(id);
      if (!refresh && cached && Date.now() - cached.at < 5 * 60 * 1000) return cached.pages;
      const pending = this.request(`/photos-item-aid-${id}.html`, (script, origin) => {
        const call = /\bmReader\.initData\(\s*\{/.exec(script);
        if (!call) throw error();
        const start = call.index + call[0].length - 1;
        let end = start, depth = 0, quoted = false, escaped = false;
        for (; end < script.length; end++) {
          const ch = script[end];
          if (quoted) {
            if (escaped) escaped = false;
            else if (ch === '\\') escaped = true;
            else if (ch === '"') quoted = false;
          } else if (ch === '"') quoted = true;
          else if (ch === '{') depth++;
          else if (ch === '}' && --depth === 0) break;
        }
        if (depth !== 0 || quoted) throw error();
        const raw = script.slice(start, end + 1);
        let data;
        try {
          // WNACG emits JavaScript arrays with trailing commas. Preserve quoted text verbatim.
          data = JSON.parse(raw.replace(/"(?:[^"\\]|\\.)*"|,\s*(?=[}\]])/g, (token) => token.startsWith('"') ? token : ''));
        } catch (_) { throw error(); }
        if (!Array.isArray(data.page_url) || !data.page_url.length) throw missing();
        return data.page_url.map((rawUrl, index) => {
          const url = imageUrl(rawUrl, origin);
          if (!url) throw error();
          const size = data.page_size?.[index];
          return { url, headers: { Referer: origin + '/' }, width: Number(size?.[0]) || undefined, height: Number(size?.[1]) || undefined, cacheKey: `wnacg:${id}:${index}` };
        });
      });
      this.pageRequests.set(id, pending);
      try {
        const pages = await pending;
        this.pageCache.delete(id);
        this.pageCache.set(id, { at: Date.now(), pages });
        while (this.pageCache.size > 8) this.pageCache.delete(this.pageCache.keys().next().value);
        return pages;
      } finally { this.pageRequests.delete(id); }
    },

    async chapter(id, chapterId) {
      const aid = idOf(chapterId || id);
      const pages = await this.imagePages(aid);
      return { pages: pages.map((page, index) => ({ token: String(index), width: page.width, height: page.height, cacheKey: page.cacheKey })) };
    },

    async resolveImage({ id, chapterId, index, token, retry = 0 }) {
      const page = Number(token ?? index);
      if (!Number.isInteger(page) || page < 0) throw missing();
      const pages = await this.imagePages(chapterId || id, retry > 0);
      if (!pages[page]) throw missing();
      return pages[page];
    },
  });
})();
