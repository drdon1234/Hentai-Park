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
  function field(row, label) {
    const heading = [...(row?.querySelectorAll('.misc b') || [])]
      .find(n => Park.html.text(n) === label + ':');
    const parts = [];
    for (let n = heading?.nextSibling; n; n = n.nextSibling) {
      if (n.nodeName === 'BR' || n.nodeName === 'B') break;
      if (n.nodeName !== 'SCRIPT' && n.nodeName !== 'STYLE') parts.push(Park.html.text(n));
    }
    return parts.join(' ').replace(/\s*\|\s*$/, '').trim();
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
      const row = a.closest('.res-item') || a.closest('h3.sname')?.parentElement,
        author = Park.html.text(row?.querySelector('a[href^="/a/"]')),
        summary = row?.querySelector('.sdesc,.res-desc')?.cloneNode(true);
      summary?.querySelectorAll('div,script,style').forEach(n => n.remove());
      summary?.querySelectorAll('a[href*="/library/get_review.php"]').forEach(n => n.remove());
      const category = field(row, 'Genre'),
        tags = field(row, 'Tags').split(',').map(t => t.trim()).filter(Boolean),
        uploaded = field(row, 'Updated') || field(row, 'Concluded') || field(row, 'Posted');
      items.push({
        id: m[1],
        title: Park.html.text(a),
        subtitle: Park.html.text(summary).replace(/\s*\/\s*\(\s*\)\s*$/, ''),
        authors: author ? [author] : [],
        category,
        tags,
        uploaded,
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
      const base = new URL(url).pathname;
      if (!/^\/list\/|^\/library\//.test(c.pathname) && !(base.startsWith('/stories/bytag/') && (c.pathname === base || c.pathname.startsWith(base + '/') && /^[1-9]\d*$/.test(c.pathname.slice(base.length + 1)))))
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
    i18n: {
      "zh-Hant": {"站点搜索入口不可用": "站點搜尋入口不可用", "英文长短篇与连载小说，支持推荐、搜索与章节目录；部分正文需要登录": "英文長短篇與連載小說，支援推薦、搜尋與章節目錄；部分正文需要登入"},
      "ja": {"站点搜索入口不可用": "サイト検索を利用できません", "英文长短篇与连载小说，支持推荐、搜索与章节目录；部分正文需要登录": "英語の長編・短編・連載小説。おすすめ、検索、目次に対応。一部の本文はログインが必要"},
      "ko": {"站点搜索入口不可用": "사이트 검색을 사용할 수 없습니다", "英文长短篇与连载小说，支持推荐、搜索与章节目录；部分正文需要登录": "영어 장편·단편·연재 소설. 추천, 검색 및 목차 지원. 일부 본문은 로그인 필요"},
      "en": {"站点搜索入口不可用": "Site search is unavailable", "英文长短篇与连载小说，支持推荐、搜索与章节目录；部分正文需要登录": "English novels, short stories and serials with recommendations, search and chapter lists; some text requires login"},
      "es": {"站点搜索入口不可用": "Búsqueda del sitio no disponible", "英文长短篇与连载小说，支持推荐、搜索与章节目录；部分正文需要登录": "Novelas, relatos y series en inglés con recomendaciones, búsqueda y capítulos; algunos textos requieren iniciar sesión"},
      "ru": {"站点搜索入口不可用": "Поиск по сайту недоступен", "英文长短篇与连载小说，支持推荐、搜索与章节目录；部分正文需要登录": "Английские романы, рассказы и сериалы: рекомендации, поиск и оглавление; часть текстов требует входа"},
      "ar": {"站点搜索入口不可用": "البحث في الموقع غير متاح", "英文长短篇与连载小说，支持推荐、搜索与章节目录；部分正文需要登录": "روايات وقصص ومسلسلات إنجليزية مع توصيات وبحث وفهرس فصول؛ بعض النصوص تتطلب تسجيل الدخول"},
    },
    key: 'storiesonline',
    name: 'StoriesOnline',
    version: '0.0.8', minAppVersion: '0.9.2',
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
      loginDomains: ['login.wlpc.com'],

      cookieUrl: HOME + '/',
      requiredCookies: [],
    },
    linkPatterns: ['storiesonline\\.net/([sn]/[0-9]+/[a-z0-9-]+)'],
    idPattern: '^[sn]/[0-9]+/[a-z0-9-]+$',
    defaultFeed: 'recommend',
    feeds: [
      { key: 'recommend', label: '推荐' },
      { key: 'rank', label: '排行' },
      {key: 'categories', label: '分类', options: [{key: 'category', label: '分类', default: '', dynamic: true, values: []}]},
    ],
    async filterOptions(req) {
      if (req.scope !== 'feed' || req.feed !== 'categories' || req.filter !== 'category') return [];
      const d = await doc(this, HOME + '/library/categories.php'), values = [{value: '', label: '全部'}], seen = new Set();
      for (const a of d.querySelectorAll('form#cat a[href]')) {
        let u; try {u = safe(new URL(a.getAttribute('href'), HOME).href);} catch (_) {continue;}
        const m = /^\/stories\/bytag\/([a-z0-9-]+)\/?$/.exec(u.pathname), label = Park.html.text(a);
        if (!m || !label || seen.has(m[1])) continue;
        seen.add(m[1]); values.push({value: m[1], label});
      }
      if (!seen.size) throw Park.error('PARSE', '未找到分类');
      return values;
    },
    async feed(key, req) {
      if (key === 'categories') {
        const category = String(req.options?.category || '');
        if (category && !/^[a-z0-9-]{1,100}$/.test(category)) throw Park.error('CONFIG', '分类无效');
        return list(this, req, HOME + (category ? '/stories/bytag/' + category : '/list/9/stories_most_recommended_by_authors'));
      }
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
