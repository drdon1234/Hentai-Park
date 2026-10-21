(function () {
  'use strict';
  const HOME = 'https://canovel.com';
  let directory;
  const categoryFilter = {key: 'category', label: '分类', type: 'select', default: '', dynamic: true, values: []};
  function categoryPath(value) {
    try {
      const u = new URL(value, HOME);
      if (u.origin === HOME && !u.username && !u.password && !u.search && !u.hash &&
          /^\/article\/category\/(?:[a-zA-Z0-9_-]|%[a-fA-F0-9]{2})+\/?$/.test(u.pathname)) {
        const slug = decodeURIComponent(u.pathname.split('/')[3]);
        if (!/[/\\\x00-\x20\x7f]/.test(slug) && slug !== '.' && slug !== '..') return u.pathname.replace(/\/$/, '');
      }
    } catch (_) {}
    return '';
  }
  async function categories(source) {
    if (directory && Date.now() - directory.time < 120000) return directory.values;
    const d = await doc(source, HOME + '/'), values = new Map();
    for (const a of d.querySelectorAll('a[href]')) {
      const value = categoryPath(a.getAttribute('href')), label = Park.html.text(a).replace(/\s+/g, ' ').trim();
      if (value && label && label.length <= 256 && !values.has(value)) values.set(value, label);
    }
    if (!values.size || values.size > 499) throw Park.error('PARSE', '分类列表解析失败');
    directory = {time: Date.now(), values: [...values].map(([value, label]) => ({value, label}))};
    return directory.values;
  }
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
  async function list(source, req, search, category = '') {
    if (category && (!(await categories(source)).some(option => option.value === category) || categoryPath(category) !== category)) {
      throw Park.error('CONFIG', '筛选参数无效');
    }
    const page = Math.max(1, Math.floor(Number(req.page) || 1)),
      url =
        HOME +
        category + (page > 1 ? '/page/' + page + '/' : '/') +
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
    version: '0.0.7', minAppVersion: '0.9.2',
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
    feeds: [{ key: 'latest', label: '最新' }, {key: 'categories', label: '分类', options: [categoryFilter]}],
    searchFilters: [categoryFilter],
    async filterOptions(request) {
      if (request.filter !== 'category') throw Park.error('CONFIG', '筛选参数无效');
      return [{value: '', label: '全部'}, ...await categories(this)];
    },
    async feed(key, req) {
      if (key === 'categories') return list(this, req, '', String(req.options?.category || ''));
      if (key !== 'latest') throw Park.error('CONFIG', '未知列表');
      return list(this, req, '');
    },
    async search(req) {
      return list(this, req, String(req.keyword || ''), String(req.filters?.category || ''));
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
