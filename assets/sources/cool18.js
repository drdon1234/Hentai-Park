(function () {
  'use strict';
  const HOME = 'https://www.cool18.com',
    BOARD = HOME + '/bbs4/index.php';
  function idValue(id) {
    if (!/^[1-9]\d{0,12}$/.test(String(id)))
      throw Park.error('NOT_FOUND', '作品编号无效');
    return String(id);
  }
  function thread(id) {
    return BOARD + '?app=forum&act=threadview&tid=' + idValue(id);
  }
  async function doc(source, url) {
    return Park.html.parse(
      source.http.ensureOk(await source.http.get(url)).body,
    );
  }
  function entries(d, search) {
    const items = [],
      seen = new Set();
    for (const a of d.querySelectorAll(
      search
        ? '.thread-list a[href*="threadview"]'
        : '.post-item a[href],.title-col a[href],li a[href*="threadview"]',
    )) {
      const u = new URL(a.getAttribute('href'), BOARD);
      if (u.hostname !== 'www.cool18.com' || u.pathname !== '/bbs4/index.php')
        continue;
      const id = u.searchParams.get('tid'),
        text = Park.html.text(a),
        bytes = text.match(/\((\d+) bytes\)/i);
      if (
        !id ||
        !/^\d+$/.test(id) ||
        seen.has(id) ||
        (bytes && +bytes[1] < 500) ||
        /^(?:[.\s]*Re[:：]|[.\s]*回复|[.\s]*点赞)/i.test(text)
      )
        continue;
      seen.add(id);
      items.push({
        id,
        title: text
          .replace(/^\.\s*/, '')
          .replace(/\s+-\s+[^]*?\(\d+ bytes\)[^]*$/, '')
          .trim(),
        cover: '',
        language: 'zh',
        mediaKind: 'novel',
      });
    }
    return items;
  }
  async function list(source, req, params) {
    const page = Math.max(1, Number(req.page) || 1),
      u = new URL(BOARD);
    for (const [k, v] of Object.entries(params)) u.searchParams.set(k, v);
    if (page > 1) u.searchParams.set('p', page);
    const d = await doc(source, u.href),
      next = [...d.querySelectorAll('a[href]')].find((a) =>
        /下一页/.test(Park.html.text(a)),
      );
    return { items: entries(d, !!params.keywords), page, hasNext: !!next };
  }
  Park.register({
    key: 'cool18',
    name: 'Cool18',
    version: '0.0.3',
    type: 'novel',
    category: 'novel',
    language: 'zh',
    color: '#A83E40',
    homepage: BOARD,
    domains: ['www.cool18.com'],
    description: '禁忌书屋小说版，支持精华、热帖、搜索与正文阅读',
    network: { mode: 'native', vpnHint: true },
    account: {
      type: 'cookies',
      title: '站点账号',
      required: false,
      loginUrl: BOARD,
      cookieUrl: HOME + '/',
      requiredCookies: [],
    },
    linkPatterns: ['cool18\\.com/bbs4/index\\.php\\?[^\\s#]*?tid=([0-9]+)'],
    idPattern: '^[1-9]\\d+$',
    defaultFeed: 'recommend',
    feeds: [
      { key: 'recommend', label: '精华' },
      { key: 'popular', label: '热门' },
    ],
    async feed(key, req) {
      if (!['recommend', 'popular'].includes(key))
        throw Park.error('CONFIG', '未知列表');
      return list(this, req, {
        app: 'forum',
        act: key === 'recommend' ? 'gold' : 'hot',
      });
    },
    async search(req) {
      return list(this, req, {
        action: 'search',
        bbsdr: 'bbs4',
        act: 'threadsearch',
        app: 'forum',
        keywords: String(req.keyword || ''),
        submit: '查询',
      });
    },
    async detail(value) {
      const id = idValue(value),
        url = thread(id),
        d = await doc(this, url),
        title = Park.html.text(d.querySelector('.main-title'));
      if (!title) throw Park.error('NOT_FOUND', '小说不存在或受限');
      const author = title.match(/作者[：:]\s*(.+)$/);
      return {
        id,
        title,
        cover: '',
        url,
        language: 'zh',
        mediaKind: 'novel',
        authors: author ? [author[1]] : [],
        chapters: null,
        tags: [],
      };
    },
    async textChapter(value, chapterId) {
      const id = idValue(value);
      if (chapterId && chapterId !== '_' && idValue(chapterId) !== id)
        throw Park.error('NOT_FOUND', '章节编号无效');
      const d = await doc(this, thread(id)),
        body = d.querySelector('#content-section'),
        paragraphs = Park.html.paragraphs(body);
      if (!body || paragraphs.join('').length < 200) {
        if (
          /金币|登录后|login to|购买/.test(
            Park.html.text(d.querySelector('.post-content')),
          )
        )
          throw Park.error('LOGIN_REQUIRED', '小说正文需要账号或站点权限');
        throw Park.error('PARSE', '小说正文为空或受限');
      }
      return {
        title: Park.html.text(d.querySelector('.main-title')),
        paragraphs,
      };
    },
  });
})();

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"}]});
