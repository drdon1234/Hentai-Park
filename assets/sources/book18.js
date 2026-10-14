(function () {
  'use strict';
  const HOME = 'https://www.book18.org';
  function idValue(id) {
    let s;
    try {
      s = decodeURIComponent(String(id));
    } catch (_) {
      throw Park.error('NOT_FOUND', '作品编号无效');
    }
    if (
      !/^(?:[1-9]\d{0,12}|chapters\/[^/?#\r\n]{1,250})$/.test(s) ||
      s.includes('://')
    )
      throw Park.error('NOT_FOUND', '作品编号无效');
    return s;
  }
  function urlOf(id) {
    const s = idValue(id);
    return (
      HOME +
      (s.startsWith('chapters/')
        ? '/chapters/' + encodeURIComponent(s.slice(9))
        : '/' + s)
    );
  }
  function href(node, base) {
    try {
      const u = new URL(node.getAttribute('href'), base);
      return u.protocol === 'https:' && u.hostname === 'www.book18.org'
        ? u
        : null;
    } catch (_) {
      return null;
    }
  }
  async function doc(source, url) {
    const r = source.http.ensureOk(await source.http.get(url));
    return Park.html.parse(r.body);
  }
  function entries(d, base) {
    const out = [],
      seen = new Set();
    for (const a of d.querySelectorAll('.list-group-item a[href]')) {
      const u = href(a, base);
      if (!u || !/^\/(?:chapters\/[^?#]+|\d+)$/.test(u.pathname)) continue;
      const id = decodeURIComponent(u.pathname.slice(1));
      if (seen.has(id)) continue;
      seen.add(id);
      out.push({
        id,
        title: Park.html.text(a),
        cover: '',
        language: 'zh',
        mediaKind: 'novel',
      });
    }
    return out;
  }
  async function list(source, req, path, params) {
    const page = Math.max(1, Number(req.page) || 1),
      u = new URL(path, HOME);
    for (const [k, v] of Object.entries(params)) u.searchParams.set(k, v);
    u.searchParams.set('page', page);
    const d = await doc(source, u.href),
      next = d.querySelector('.next:not(.disabled) a[href]');
    return { items: entries(d, u.href), page, hasNext: !!next };
  }
  Park.register({
    i18n: {
      "zh-Hant": {"中文长篇与短篇小说，支持推荐、搜索、目录和正文阅读": "中文長篇與短篇小說，支援推薦、搜尋、目錄和正文閱讀", "小说目录为空或受限": "小說目錄為空或受限", "请选择章节": "請選擇章節"},
      "ja": {"中文长篇与短篇小说，支持推荐、搜索、目录和正文阅读": "中国語の長編・短編小説。おすすめ、検索、目次、本文の閲覧に対応", "小说目录为空或受限": "目次が空または制限されています", "请选择章节": "章を選択してください"},
      "ko": {"中文长篇与短篇小说，支持推荐、搜索、目录和正文阅读": "중국어 장편·단편 소설. 추천, 검색, 목차 및 본문 읽기 지원", "小说目录为空或受限": "소설 목차가 비어 있거나 제한됩니다", "请选择章节": "장을 선택하세요"},
      "en": {"中文长篇与短篇小说，支持推荐、搜索、目录和正文阅读": "Chinese novels and short stories with recommendations, search, chapter lists and text reading", "小说目录为空或受限": "Novel contents list is empty or restricted", "请选择章节": "Select a chapter"},
      "es": {"中文长篇与短篇小说，支持推荐、搜索、目录和正文阅读": "Novelas y relatos en chino con recomendaciones, búsqueda, capítulos y lectura", "小说目录为空或受限": "Índice vacío o restringido", "请选择章节": "Selecciona un capítulo"},
      "ru": {"中文长篇与短篇小说，支持推荐、搜索、目录和正文阅读": "Китайские романы и рассказы: рекомендации, поиск, оглавление и чтение", "小说目录为空或受限": "Оглавление пусто или доступ ограничен", "请选择章节": "Выберите главу"},
      "ar": {"中文长篇与短篇小说，支持推荐、搜索、目录和正文阅读": "روايات وقصص صينية مع توصيات وبحث وفهرس فصول وقراءة النص", "小说目录为空或受限": "فهرس الرواية فارغ أو مقيد", "请选择章节": "اختر فصلاً"},
    },
    key: 'book18',
    name: 'Book18',
    version: '0.0.4',
    type: 'novel',
    category: 'novel',
    language: 'zh',
    color: '#D99A36',
    homepage: HOME,
    domains: ['www.book18.org'],
    description: '中文长篇与短篇小说，支持推荐、搜索、目录和正文阅读',
    network: { mode: 'native', vpnHint: true },
    linkPatterns: ['book18\\.org/(chapters/[^?#\\s]+|[0-9]+)'],
    idPattern: '^(?:[1-9]\\d*|chapters/.+)$',
    defaultFeed: 'recommend',
    feeds: [
      { key: 'recommend', label: '推荐' },
      { key: 'popular', label: '热门' },
      { key: 'latest', label: '最新' },
      { key: 'short', label: '短篇' },
    ],
    async feed(key, req) {
      if (!['recommend', 'popular', 'latest', 'short'].includes(key))
        throw Park.error('CONFIG', '未知列表');
      return list(this, req, key === 'short' ? '/article/index' : '/', {
        sort:
          key === 'recommend'
            ? 'score'
            : key === 'popular'
              ? 'views'
              : 'modified',
      });
    },
    async search(req) {
      return list(this, req, '/', { q: String(req.keyword || '').trim() });
    },
    async detail(value) {
      const id = idValue(value),
        url = urlOf(id),
        d = await doc(this, url),
        title = Park.html.text(d.querySelector('h1')) || id;
      const chapters = id.startsWith('chapters/')
        ? entries(d, url)
            .filter((e) => /^\d+$/.test(e.id))
            .map((e) => ({ id: e.id, title: e.title }))
        : null;
      if (chapters && !chapters.length)
        throw Park.error('PARSE', '小说目录为空或受限');
      const author = (title + ' ' + (chapters?.[0]?.title || '')).match(
        /作者[：:]\s*([^\s]+)/,
      );
      return {
        id,
        title,
        cover: '',
        url,
        language: 'zh',
        mediaKind: 'novel',
        authors: author ? [author[1]] : [],
        chapters,
        singleChapterId: chapters ? null : id,
        tags: [],
      };
    },
    async textChapter(value, chapterId) {
      const id = idValue(value);
      if (id.startsWith('chapters/') && !chapterId)
        throw Park.error('CONFIG', '请选择章节');
      if (chapterId && !/^\d+$/.test(String(chapterId)))
        throw Park.error('NOT_FOUND', '章节编号无效');
      if (!id.startsWith('chapters/') && chapterId && String(chapterId) !== id)
        throw Park.error('NOT_FOUND', '章节编号无效');
      const d = await doc(this, urlOf(chapterId || id)),
        paragraphs = Park.html.paragraphs(d.querySelector('#content.reader'));
      if (!paragraphs.length) throw Park.error('PARSE', '小说正文为空或受限');
      return { title: Park.html.text(d.querySelector('h1')), paragraphs };
    },
  });
})();

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"},{"key":"work","label":"作品连载","hint":"作品编号或详情链接"}]});
