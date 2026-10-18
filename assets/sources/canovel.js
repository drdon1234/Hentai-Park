(function () {
  'use strict';
  const HOME = 'https://canovel.com';
  function idValue(id) {
    if (!/^[1-9]\d{0,12}$/.test(String(id)))
      throw Park.error('NOT_FOUND', '作品编号无效');
    return String(id);
  }
  async function doc(source, url) {
    return Park.html.parse(
      source.http.ensureOk(await source.http.get(url)).body,
    );
  }
  async function list(source, req, search) {
    const page = Math.max(1, Number(req.page) || 1),
      url =
        HOME +
        (page > 1 ? '/page/' + page : '/') +
        (search ? '?s=' + encodeURIComponent(search) : ''),
      d = await doc(source, url),
      items = [],
      seen = new Set();
    for (const a of d.querySelectorAll('.post-title a[href]')) {
      const u = new URL(a.getAttribute('href'), HOME),
        m = u.pathname.match(/^\/article\/(\d+)\/?$/);
      if (u.hostname !== 'canovel.com' || !m || seen.has(m[1])) continue;
      seen.add(m[1]);
      const row = a.closest('.post-inner') || a.closest('article'),
        author = Park.html.text(row?.querySelector('a[rel="author"]')),
        tags = [...(row?.querySelectorAll('.post-category a') || [])]
          .map(n => Park.html.text(n)).filter(Boolean);
      items.push({
        id: m[1],
        title: Park.html.text(a),
        subtitle: Park.html.text(row?.querySelector('.entry-summary,.excerpt')),
        authors: author ? [author] : [],
        category: tags[0] || '',
        tags,
        uploaded: row?.querySelector('time')?.getAttribute('datetime') || '',
        cover: '',
        language: 'zh',
        mediaKind: 'novel',
      });
    }
    return { items, page, hasNext: !!d.querySelector('.nextpostslink') };
  }
  Park.register({
    i18n: {
      "zh-Hant": {"中文短篇与分篇小说，支持搜索和正文阅读": "中文短篇與分篇小說，支援搜尋和正文閱讀"},
      "ja": {"中文短篇与分篇小说，支持搜索和正文阅读": "中国語の短編・分割小説。検索と本文の閲覧に対応"},
      "ko": {"中文短篇与分篇小说，支持搜索和正文阅读": "중국어 단편·연작 소설. 검색 및 본문 읽기 지원"},
      "en": {"中文短篇与分篇小说，支持搜索和正文阅读": "Chinese short stories and serialized posts with search and text reading"},
      "es": {"中文短篇与分篇小说，支持搜索和正文阅读": "Relatos y entregas en chino con búsqueda y lectura"},
      "ru": {"中文短篇与分篇小说，支持搜索和正文阅读": "Китайские рассказы и серии публикаций: поиск и чтение"},
      "ar": {"中文短篇与分篇小说，支持搜索和正文阅读": "قصص صينية قصيرة ومتسلسلة مع البحث وقراءة النص"},
    },
    key: 'canovel',
    name: 'Canovel',
    version: '0.0.5',
    type: 'novel',
    category: 'novel',
    language: 'zh',
    color: '#3875A0',
    homepage: HOME,
    domains: ['canovel.com'],
    description: '中文短篇与分篇小说，支持搜索和正文阅读',
    network: {
      mode: 'native',
      vpnHint: true,
      headers: {
        'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
        Accept:
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
    },
    linkPatterns: ['canovel\\.com/article/([0-9]+)'],
    idPattern: '^[1-9]\\d+$',
    defaultFeed: 'latest',
    feeds: [{ key: 'latest', label: '最新' }],
    async feed(key, req) {
      if (key !== 'latest') throw Park.error('CONFIG', '未知列表');
      return list(this, req, '');
    },
    async search(req) {
      return list(this, req, String(req.keyword || ''));
    },
    async detail(value) {
      const id = idValue(value),
        url = HOME + '/article/' + id,
        d = await doc(this, url),
        title = Park.html.text(d.querySelector('h1.post-title'));
      if (!title) throw Park.error('NOT_FOUND', '小说不存在');
      return {
        id,
        title,
        cover: '',
        url,
        language: 'zh',
        mediaKind: 'novel',
        authors: [],
        chapters: null,
        tags: [],
        description: '',
      };
    },
    async textChapter(value, chapterId) {
      const id = idValue(value);
      if (chapterId && chapterId !== '_' && idValue(chapterId) !== id)
        throw Park.error('NOT_FOUND', '章节编号无效');
      const url = HOME + '/article/' + id,
        paragraphs = [],
        seen = new Set(),
        pending = [url];
      let title = '';
      while (pending.length) {
        const pageUrl = pending.shift();
        if (seen.has(pageUrl)) continue;
        if (seen.size >= 100) throw Park.error('PARSE', '小说正文分页无效');
        seen.add(pageUrl);
        const d = await doc(this, pageUrl);
        title ||= Park.html.text(d.querySelector('h1.post-title'));
        for (const a of d.querySelectorAll('.page-links a[href]')) {
          const u = new URL(a.getAttribute('href'), pageUrl);
          if (
            u.protocol === 'https:' &&
            u.hostname === 'canovel.com' &&
            new RegExp('^/article/' + id + '(?:/\\d+)?/?$').test(u.pathname) &&
            !seen.has(u.href)
          )
            pending.push(u.href);
        }
        const body = d.querySelector('article .entry')?.cloneNode(true);
        body?.querySelectorAll('.page-links').forEach((n) => n.remove());
        const part = Park.html.paragraphs(body);
        if (!part.length) throw Park.error('PARSE', '小说正文为空或受限');
        paragraphs.push(...part);
      }
      return { title, paragraphs };
    },
  });
})();

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"}]});
