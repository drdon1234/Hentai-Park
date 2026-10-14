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
      out.push({
        id: m[1],
        title,
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
        uploader: String(x.authorname || ''),
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
    version: '0.0.5',
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
    feeds: [{ key: 'rank', label: '排行' }],
    async feed(key, req) {
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
