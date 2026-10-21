(function () {
  'use strict';
  const HOME = 'https://www.literotica.com',
    SEARCH = 'https://search.literotica.com',
    API = 'https://literotica.com/api/3';
  function idValue(id) {
    if (!/^[a-z0-9][a-z0-9-]{0,220}$/.test(String(id)))
      throw Park.error('NOT_FOUND', '作品编号无效');
    return String(id);
  }
  function safe(url) {
    const u = new URL(url);
    if (
      u.protocol !== 'https:' ||
      !['www.literotica.com', 'search.literotica.com'].includes(u.hostname) ||
      u.username ||
      u.password ||
      (u.port && u.port !== '443')
    )
      throw Park.error('CONFIG', '站点链接无效');
    return u;
  }
  async function doc(source, url) {
    safe(url);
    const r = source.http.ensureOk(await source.http.get(url));
    safe(r.url || url);
    return Park.html.parse(r.body);
  }
  function entries(d) {
    const out = [],
      seen = new Set();
    for (const a of d.querySelectorAll('a[href]')) {
      let u;
      try {
        u = safe(new URL(a.getAttribute('href'), HOME).href);
      } catch (_) {
        continue;
      }
      const m = u.pathname.match(/^\/s\/([a-z0-9-]+)$/);
      if (!m || seen.has(m[1])) continue;
      const row =
        a.closest(
          '[typeof="CreativeWork"],article,li,[class*="_item_"],[class*="story"]',
        ) || a.parentElement;
      if (/Non-English|Audio|How To|Reviews & Essays/.test(Park.html.text(row)))
        continue;
      const title = Park.html.text(a);
      if (!title || /^(?:Page \d+|Next|Previous)$/i.test(title)) continue;
      seen.add(m[1]);
      const authorNode = row?.querySelector('[property~="author"],a[href*="/authors/"]'),
        author = authorNode?.querySelector('meta[property="name"]')?.getAttribute('content') ||
          Park.html.text(authorNode).replace(/^by\s+/i, ''),
        category = Park.html.text(row?.querySelector('a[href*="/c/"] span,a[href*="/c/"]'));
      out.push({
        id: m[1],
        title,
        subtitle: Park.html.text(row?.querySelector('[property="headline"]')),
        authors: author ? [author] : [],
        category,
        tags: category ? [category] : [],
        uploaded: row?.querySelector('[property="datePublished"]')?.getAttribute('content') || '',
        cover: '',
        language: 'en',
        mediaKind: 'novel',
      });
    }
    return out;
  }
  // Story pages load "Similar stories" from the public API instead of rendering them.
  async function similar(source, id) {
    const r = await source.http.get(
      API + '/stories/' + encodeURIComponent(id) + '/similar',
    );
    if (!r.ok || r.body.length > 1024 * 1024) return [];
    let data;
    try {
      data = JSON.parse(r.body);
    } catch (_) {
      return [];
    }
    const out = [],
      seen = new Set([id]);
    for (const x of Array.isArray(data) ? data.slice(0, 50) : []) {
      const slug = x && String(x.url || '');
      if (
        x.type !== 'story' ||
        x.language !== 1 ||
        !/^[a-z0-9][a-z0-9-]{0,220}$/.test(slug) ||
        !x.title ||
        seen.has(slug)
      )
        continue;
      seen.add(slug);
      out.push({
        id: slug,
        title: String(x.title),
        cover: '',
        language: 'en',
        mediaKind: 'novel',
        authors: x.authorname ? [String(x.authorname)] : [],
        subtitle: String(x.description || ''),
        category: '',
        tags: (Array.isArray(x.tags) ? x.tags : [])
          .filter(tag => typeof tag?.tag === 'string' && !tag.is_banned)
          .map(tag => tag.tag),
        uploaded: typeof x.date_approve === 'string' ? x.date_approve : '',
      });
    }
    return out;
  }
  async function list(source, req, url) {
    const u = new URL(url),
      page = Math.max(1, Number(req.page) || 1);
    if (req.cursor) {
      const c = safe(req.cursor);
      if (c.hostname !== u.hostname || c.pathname !== u.pathname)
        throw Park.error('CONFIG', '分页链接无效');
      u.href = c.href;
    }
    const d = await doc(source, u.href),
      next = [...d.querySelectorAll('a[href]')].find(
        (a) =>
          /next/i.test(
            a.getAttribute('aria-label') ||
              a.getAttribute('title') ||
              Park.html.text(a),
          ) && /page=/.test(a.getAttribute('href')),
      );
    return {
      items: entries(d),
      page,
      hasNext: !!next,
      cursor: next
        ? safe(new URL(next.getAttribute('href'), u.href).href).href
        : null,
    };
  }
  Park.register({
    i18n: {
      "zh-Hant": {"英文小说与系列故事，支持排行、搜索和完整正文分页": "英文小說與系列故事，支援排行、搜尋和完整正文分頁"},
      "ja": {"英文小说与系列故事，支持排行、搜索和完整正文分页": "英語の小説・連作。ランキング、検索、本文の全ページ閲覧に対応"},
      "ko": {"英文小说与系列故事，支持排行、搜索和完整正文分页": "영어 소설·연작. 순위, 검색 및 전체 본문 페이지 읽기 지원"},
      "en": {"英文小说与系列故事，支持排行、搜索和完整正文分页": "English fiction with rankings, search and complete multi-page text"},
      "es": {"英文小说与系列故事，支持排行、搜索和完整正文分页": "Ficción en inglés con rankings, búsqueda y texto completo de varias páginas"},
      "ru": {"英文小说与系列故事，支持排行、搜索和完整正文分页": "Английская проза: рейтинги, поиск и полный многостраничный текст"},
      "ar": {"英文小说与系列故事，支持排行、搜索和完整正文分页": "روايات إنجليزية مع ترتيب وبحث وقراءة النص الكامل متعدد الصفحات"},
    },
    key: 'literotica',
    name: 'Literotica',
    version: '0.0.7',
    type: 'novel',
    category: 'novel',
    language: 'en',
    color: '#AE3942',
    homepage: HOME + '/stories',
    domains: ['www.literotica.com', 'search.literotica.com'],
    description: '英文小说与系列故事，支持排行、搜索和完整正文分页',
    network: { mode: 'native', vpnHint: true },
    linkPatterns: ['literotica\\.com/s/([a-z0-9-]+)'],
    idPattern: '^[a-z0-9][a-z0-9-]+$',
    defaultFeed: 'rank',
    feeds: [{ key: 'rank', label: '排行' }, {key: 'categories', label: '分类', options: [{key: 'category', label: '分类', type: 'select', default: '', dynamic: true, values: []}]}],
    async filterOptions(req) {
      if (req.scope !== 'feed' || req.feed !== 'categories' || req.filter !== 'category') return [];
      const d = await doc(this, HOME + '/stories'), options = [{value: '', label: '全部'}], seen = new Set();
      for (const a of d.querySelectorAll('a[href]')) {
        let u; try {u = safe(new URL(a.getAttribute('href'), HOME).href);} catch (_) {continue;}
        const m = /^\/c\/([a-z0-9-]+)$/.exec(u.pathname), label = Park.html.text(a);
        if (!m || !label || /audio|poetry|non-english|adult-how-to|reviews-and-essays/.test(m[1]) || seen.has(m[1])) continue;
        seen.add(m[1]); options.push({value: m[1], label});
      }
      if (!seen.size) throw Park.error('PARSE', '未找到分类');
      return options;
    },
    async categoryList(req, category) {
      const page = Math.max(1, Math.floor(Number(req.page) || 1));
      let categoryId;
      if (category) {
        this.categoryIds ||= new Map();
        categoryId = this.categoryIds.get(category);
        if (!categoryId) {
          const html = await this.http.text(HOME + '/c/' + category);
          const ids = [...new Set([...html.matchAll(/categoryid=(\d+)/g)].map(m => Number(m[1])))];
          if (ids.length !== 1 || ids[0] < 1) throw Park.error('PARSE', '分类列表解析失败');
          categoryId = ids[0];
          this.categoryIds.set(category, categoryId);
        }
      }
      const data = await this.http.json(API + '/stories/new', {params: {params: JSON.stringify({
        ...(categoryId ? {category: categoryId} : {}), page, pageSize: 35, language: 1,
      })}});
      if (!Array.isArray(data?.submissions) || !Number.isSafeInteger(data.meta?.submissions_count)) throw Park.error('PARSE', '分类列表解析失败');
      const items = data.submissions.filter(x => x.type === 'story' && x.language === 1).map(x => {
        if (categoryId && (x.category !== categoryId || x.category_info?.pageUrl !== category)) throw Park.error('PARSE', '分类列表解析失败');
        return {id: idValue(x.url), title: String(x.title || ''), subtitle: String(x.description || ''),
          cover: '', mediaKind: 'novel', language: 'en', authors: x.authorname ? [String(x.authorname)] : [],
          uploaded: String(x.date_approve || ''), category: String(x.category_info?.pageUrl || '')};
      });
      return {items, page, total: data.meta.submissions_count, hasNext: page * 35 < data.meta.submissions_count};
    },
    async feed(key, req) {
      if (key === 'categories') {
        const category = String(req.options?.category || '');
        if (category && (!/^[a-z0-9-]{1,80}$/.test(category) || /audio|poetry|non-english|adult-how-to|reviews-and-essays/.test(category))) throw Park.error('CONFIG', '分类无效');
        return this.categoryList(req, category);
      }
      if (key !== 'rank') throw Park.error('CONFIG', '未知列表');
      return list(this, req, HOME + '/top/stories');
    },
    async search(req) {
      return list(
        this,
        req,
        SEARCH + '/?query=' + encodeURIComponent(String(req.keyword || '')),
      );
    },
    async detail(value) {
      const id = idValue(value),
        url = HOME + '/s/' + id,
        d = await doc(this, url),
        title = Park.html.text(d.querySelector('h1')),
        author = Park.html.text(
          d.querySelector('a[rel="author"],a[href*="/authors/"]'),
        );
      if (!title) throw Park.error('NOT_FOUND', '小说不存在');
      const related = await similar(this, id);
      return {
        id,
        title,
        cover: '',
        url,
        mediaKind: 'novel',
        language: 'en',
        chapters: null,
        authors: author ? [author] : [],
        description:
          d
            .querySelector('meta[name="description"]')
            ?.getAttribute('content') || '',
        related,
        tags: [],
      };
    },
    async textChapter(value, chapterId) {
      const id = idValue(value);
      if (chapterId && chapterId !== '_' && idValue(chapterId) !== id)
        throw Park.error('NOT_FOUND', '章节编号无效');
      const url = HOME + '/s/' + id,
        paragraphs = [];
      let pageUrl = url;
      const seen = new Set();
      while (pageUrl) {
        if (seen.has(pageUrl) || seen.size >= 100)
          throw Park.error('PARSE', '小说正文分页无效');
        seen.add(pageUrl);
        const d = await doc(this, pageUrl),
          body = d.querySelector('[class*="_article__content_"]');
        const part = Park.html.paragraphs(body);
        if (!part.length) throw Park.error('PARSE', '小说正文为空或受限');
        paragraphs.push(...part);
        const current = +(new URL(pageUrl).searchParams.get('page') || 1),
          pages = [
            ...d.querySelectorAll('nav[aria-label="Pagination"] a[href]'),
          ]
            .map((a) => {
              try {
                return safe(new URL(a.getAttribute('href'), url).href);
              } catch (_) {
                return null;
              }
            })
            .filter(
              (u) =>
                u &&
                u.pathname === '/s/' + id &&
                +(u.searchParams.get('page') || 1) === current + 1,
            );
        pageUrl = pages[0]?.href || null;
      }
      return { paragraphs };
    },
  });
})();

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"}]});
