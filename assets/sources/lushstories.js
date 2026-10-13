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
      out.push({
        id: m[1],
        title: Park.html.text(h),
        subtitle: Park.html.text(a.querySelector('em')),
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
    key: 'lushstories',
    name: 'Lush Stories',
    version: '0.0.3',
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
    ],
    async feed(key, req) {
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
