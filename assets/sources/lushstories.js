(function () {
  'use strict';
  const HOME = 'https://www.lushstories.com';
  function idValue(id) {
    if (
      !/^[a-z0-9-]+\/[a-z0-9-]{1,240}$/.test(String(id)) ||
      ['audio', 'erotic-poems', 'love-poems'].includes(String(id).split('/')[0])
    )
      throw Park.error('NOT_FOUND', '作品编号无效');
    return String(id);
  }
  function safe(url) {
    const u = new URL(url);
    if (
      u.protocol !== 'https:' ||
      u.hostname !== 'www.lushstories.com' ||
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
      const h = a.querySelector('h2,h3');
      if (
        !h ||
        !a.closest('article') ||
        a.closest('article').parentElement?.classList.contains('relative')
      )
        continue;
      let u;
      try {
        u = safe(new URL(a.getAttribute('href'), HOME).href);
      } catch (_) {
        continue;
      }
      const m = u.pathname.match(/^\/stories\/([^/]+\/[^/]+)$/);
      if (
        !m ||
        ['audio', 'erotic-poems', 'love-poems'].includes(m[1].split('/')[0]) ||
        seen.has(m[1])
      )
        continue;
      seen.add(m[1]);
      const row = a.closest('article'),
        authorNode = row.querySelector('header a[href^="/profile/"]'),
        author = authorNode?.getAttribute('aria-label') || Park.html.text(authorNode),
        categoryNode = [...row.querySelectorAll('footer a[href]')].find(n =>
          n.getAttribute('href') === '/stories/' + m[1].split('/')[0]),
        category = Park.html.text(categoryNode),
        summary = [Park.html.text(a.querySelector('em')), Park.html.text(a.querySelector('p'))]
          .find(text => text && !/^(?:Lorem ipsum|Sed ut perspiciatis)\b/i.test(text)) || '',
        tags = [...row.querySelectorAll('footer a[href*="?tag="]')]
          .map(n => Park.html.text(n)).filter(Boolean);
      out.push({
        id: m[1],
        title: Park.html.text(h),
        subtitle: summary,
        authors: author ? [author] : [],
        category,
        tags,
        uploaded: row.querySelector('time')?.getAttribute('datetime') ||
          row.querySelector('time')?.getAttribute('title') || '',
        cover: '',
        language: 'en',
        mediaKind: 'novel',
      });
    }
    return out;
  }
  async function list(source, req, path, params = {}) {
    const page = Math.max(1, Number(req.page) || 1),
      u = new URL(path, HOME);
    for (const [k, v] of Object.entries(params)) u.searchParams.set(k, v);
    if (req.cursor) {
      const c = safe(req.cursor);
      if (c.pathname !== u.pathname) throw Park.error('CONFIG', '分页链接无效');
      u.href = c.href;
    }
    const d = await doc(source, u.href),
      next = [...d.querySelectorAll('a[href]')].find(
        (a) =>
          Park.html.text(a) === 'Next' &&
          !(a.getAttribute('aria-disabled') === 'true') &&
          /page=/.test(a.getAttribute('href')),
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
      "zh-Hant": {"英文小说社区，支持推荐、搜索与正文阅读": "英文小說社群，支援推薦、搜尋與正文閱讀"},
      "ja": {"英文小说社区，支持推荐、搜索与正文阅读": "英語の小説コミュニティ。おすすめ、検索、本文の閲覧に対応"},
      "ko": {"英文小说社区，支持推荐、搜索与正文阅读": "영어 소설 커뮤니티. 추천, 검색 및 본문 읽기 지원"},
      "en": {"英文小说社区，支持推荐、搜索与正文阅读": "English fiction community with recommendations, search and text reading"},
      "es": {"英文小说社区，支持推荐、搜索与正文阅读": "Comunidad de ficción en inglés con recomendaciones, búsqueda y lectura"},
      "ru": {"英文小说社区，支持推荐、搜索与正文阅读": "Сообщество английской прозы: рекомендации, поиск и чтение"},
      "ar": {"英文小说社区，支持推荐、搜索与正文阅读": "مجتمع روايات إنجليزية مع توصيات وبحث وقراءة النص"},
    },
    key: 'lushstories',
    name: 'Lush Stories',
    version: '0.0.7', minAppVersion: '0.9.2',
    type: 'novel',
    category: 'novel',
    language: 'en',
    color: '#963643',
    homepage: HOME,
    domains: ['www.lushstories.com'],
    description: '英文小说社区，支持推荐、搜索与正文阅读',
    network: { mode: 'native', vpnHint: true },
    linkPatterns: ['lushstories\\.com/stories/([^/?#]+/[^/?#]+)'],
    idPattern: '^[a-z0-9-]+/[a-z0-9-]+$',
    defaultFeed: 'recommend',
    feeds: [
      { key: 'recommend', label: '推荐' },
      { key: 'latest', label: '最新' },
      {key: 'categories', label: '分类', options: [{key: 'category', label: '分类', type: 'select', default: '', dynamic: true, values: []}]},
    ],
    async filterOptions(req) {
      if (req.scope !== 'feed' || req.feed !== 'categories' || req.filter !== 'category') return [];
      const d = await doc(this, HOME + '/stories'), options = [{value: '', label: '全部'}], seen = new Set();
      const excluded = new Set(['create','audio','erotic-poems','love-poems','recommended','editors-picks','famous','legendary','competition-winners']);
      for (const a of d.querySelectorAll('a[href]')) {
        let u; try {u = safe(new URL(a.getAttribute('href'), HOME).href);} catch (_) {continue;}
        const m = /^\/stories\/([a-z0-9-]+)$/.exec(u.pathname), label = Park.html.text(a);
        if (!m || !label || excluded.has(m[1]) || seen.has(m[1])) continue;
        seen.add(m[1]); options.push({value: m[1], label});
      }
      if (!seen.size) throw Park.error('PARSE', '未找到分类');
      return options;
    },
    async feed(key, req) {
      if (key === 'categories') {
        const category = String(req.options?.category || '');
        if (category && (!/^[a-z0-9-]{1,80}$/.test(category) || ['audio','erotic-poems','love-poems'].includes(category))) throw Park.error('CONFIG', '分类无效');
        return list(this, req, '/stories' + (category ? '/' + category : ''));
      }
      if (!['recommend', 'latest'].includes(key))
        throw Park.error('CONFIG', '未知列表');
      return list(
        this,
        req,
        key === 'recommend' ? '/stories/recommended' : '/stories',
      );
    },
    async search(req) {
      return list(this, req, '/stories', {
        keywords: String(req.keyword || ''),
        sort: 'relevance',
      });
    },
    async detail(value) {
      const id = idValue(value),
        url = HOME + '/stories/' + id,
        d = await doc(this, url),
        title = Park.html.text(d.querySelector('h1')),
        author = Park.html.text(d.querySelector('a[href*="/profiles/view/"]'));
      if (!title) throw Park.error('NOT_FOUND', '小说不存在');
      return {
        id,
        title,
        cover: '',
        url,
        language: 'en',
        mediaKind: 'novel',
        authors: author ? [author] : [],
        chapters: null,
        description:
          d
            .querySelector('meta[name="description"]')
            ?.getAttribute('content') || '',
        tags: [],
      };
    },
    async textChapter(value, chapterId) {
      const id = idValue(value);
      if (chapterId && chapterId !== '_' && idValue(chapterId) !== id)
        throw Park.error('NOT_FOUND', '章节编号无效');
      const d = await doc(this, HOME + '/stories/' + id),
        body = d.querySelector('#story-body'),
        paragraphs = Park.html.paragraphs(body);
      if (!paragraphs.length) throw Park.error('PARSE', '小说正文为空或受限');
      return { title: Park.html.text(d.querySelector('h1')), paragraphs };
    },
  });
})();

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"}]});
