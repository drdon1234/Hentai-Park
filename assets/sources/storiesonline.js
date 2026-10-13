(function () {
  'use strict';
  const HOME = 'https://storiesonline.net';
  function idValue(id) {
    if (
      !/^[sn]\/[1-9]\d{0,12}\/[a-z0-9-]{1,220}(?:\/[1-9]\d{0,5})?$/.test(
        String(id),
      )
    )
      throw Park.error('NOT_FOUND', '作品编号无效');
    return String(id);
  }
  function safe(url) {
    const u = new URL(url);
    if (
      u.protocol !== 'https:' ||
      u.hostname !== 'storiesonline.net' ||
      u.username ||
      u.password ||
      (u.port && u.port !== '443')
    )
      throw Park.error('CONFIG', '站点链接无效');
    return u;
  }
  async function doc(source, url, opts) {
    safe(url);
    const r = source.http.ensureOk(await source.http.request({ url, ...opts }));
    safe(r.url || url);
    return Park.html.parse(r.body);
  }
  function entries(d) {
    const items = [],
      seen = new Set();
    for (const a of d.querySelectorAll(
      'h3.sname a[href],.res-item > a[href]',
    )) {
      let u;
      try {
        u = safe(new URL(a.getAttribute('href'), HOME).href);
      } catch (_) {
        continue;
      }
      const m = u.pathname.match(/^\/([sn]\/\d+\/[a-z0-9-]+)$/);
      if (!m || seen.has(m[1])) continue;
      seen.add(m[1]);
      items.push({
        id: m[1],
        title: Park.html.text(a),
        cover: '',
        language: 'en',
        mediaKind: 'novel',
      });
    }
    return items;
  }
  async function list(source, req, url, opts) {
    const page = Math.max(1, Number(req.page) || 1);
    if (req.cursor) {
      const c = safe(req.cursor);
      if (!/^\/list\/|^\/library\//.test(c.pathname))
        throw Park.error('CONFIG', '分页链接无效');
      url = c.href;
    }
    const d = await doc(source, url, opts),
      next = [...d.querySelectorAll('a[href]')].find((a) =>
        /^(?:Next|Next Page|Next 50|>)[ >»]*$/i.test(Park.html.text(a)),
      );
    return {
      items: entries(d),
      page,
      hasNext: !!next,
      cursor: next
        ? safe(new URL(next.getAttribute('href'), url).href).href
        : null,
    };
  }
  Park.register({
    key: 'storiesonline',
    name: 'StoriesOnline',
    version: '0.0.3',
    type: 'novel',
    category: 'novel',
    language: 'en',
    color: '#49647D',
    homepage: HOME,
    domains: ['storiesonline.net'],
    description:
      '英文长短篇与连载小说，支持推荐、搜索与章节目录；部分正文需要登录',
    network: { mode: 'native', vpnHint: true },
    account: {
      type: 'cookies',
      title: '站点账号',
      required: false,
      loginUrl: HOME + '/sol-secure/login.php',
      cookieUrl: HOME + '/',
      requiredCookies: [],
    },
    linkPatterns: ['storiesonline\\.net/([sn]/[0-9]+/[a-z0-9-]+)'],
    idPattern: '^[sn]/[0-9]+/[a-z0-9-]+$',
    defaultFeed: 'recommend',
    feeds: [
      { key: 'recommend', label: '推荐' },
      { key: 'rank', label: '排行' },
    ],
    async feed(key, req) {
      if (!['recommend', 'rank'].includes(key))
        throw Park.error('CONFIG', '未知列表');
      return list(
        this,
        req,
        HOME +
          (key === 'recommend'
            ? '/list/9/stories_most_recommended_by_authors'
            : '/list/4/top_50_stories_by_rating_in_the_last_30_days'),
      );
    },
    async search(req) {
      if (req.cursor) return list(this, req, HOME + '/library/searchQuick.php');
      const d = await doc(this, HOME + '/'),
        f = d.querySelector('form[action*="searchQuick"]');
      if (!f) throw Park.error('PARSE', '站点搜索入口不可用');
      const form = {};
      for (const x of f.querySelectorAll('input[name]'))
        form[x.getAttribute('name')] = x.getAttribute('value') || '';
      form.q = String(req.keyword || '');
      return list(this, req, HOME + '/library/searchQuick.php', {
        method: 'POST',
        form,
      });
    },
    async detail(value) {
      const id = idValue(value),
        url = HOME + '/' + id,
        d = await doc(this, url),
        title = Park.html.text(d.querySelector('h1'));
      if (!title) throw Park.error('NOT_FOUND', '小说不存在');
      const chapters = [],
        seen = new Set();
      for (const a of d.querySelectorAll('a[href]')) {
        let u;
        try {
          u = safe(new URL(a.getAttribute('href'), url).href);
        } catch (_) {
          continue;
        }
        const cid = u.pathname.slice(1);
        if (
          cid.startsWith(id + '/') &&
          /^\d+$/.test(cid.slice(id.length + 1)) &&
          !seen.has(cid)
        ) {
          seen.add(cid);
          chapters.push({ id: cid, title: Park.html.text(a) });
        }
      }
      return {
        id,
        title,
        cover: '',
        url,
        language: 'en',
        mediaKind: 'novel',
        authors: [
          d.querySelector('meta[name="author"]')?.getAttribute('content') || '',
        ].filter(Boolean),
        chapters: chapters.length ? chapters : null,
        description:
          d
            .querySelector('meta[name="description"]')
            ?.getAttribute('content') || '',
        tags: [],
      };
    },
    async textChapter(value, chapterId) {
      const id = idValue(value),
        cid = chapterId && chapterId !== '_' ? idValue(chapterId) : id;
      if (cid !== id && !cid.startsWith(id + '/'))
        throw Park.error('NOT_FOUND', '章节编号无效');
      const d = await doc(this, HOME + '/' + cid),
        body = d.querySelector('article');
      if (
        /To read (?:the complete|this) story you need|log(?:ged)? in to (?:read|continue)|premier membership|daily.*limit/i.test(
          [...d.querySelectorAll('.notice,.fadeout,#login-required')]
            .map((n) => Park.html.text(n))
            .join(' '),
        )
      )
        throw Park.error('LOGIN_REQUIRED', '小说正文需要账号或站点权限');
      const paragraphs = Park.html.paragraphs(body);
      if (!paragraphs.length)
        throw Park.error('LOGIN_REQUIRED', '小说正文为空或受限');
      return { title: Park.html.text(d.querySelector('h2,h1')), paragraphs };
    },
  });
})();

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"}]});
