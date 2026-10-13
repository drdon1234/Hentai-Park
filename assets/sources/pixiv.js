/* Pixiv — verified website JSON endpoints; static illustrations and manga only. */
(function () {
  'use strict';
  const HOME = 'https://www.pixiv.net';
  const LOGIN = '请登录 Pixiv；Cookie 可能已过期，R-18 内容还需在站点开启显示权限';
  const PARSE = 'Pixiv 返回的数据无效，请稍后重试';
  const contentOption = {
    key: 'content', label: '作品类型', default: '@setting', values: [
      { value: '@setting', label: '跟随设置' },
      { value: 'manga', label: '漫画' }, { value: 'illust', label: '插画' },
    ],
  };
  const ratingOption = {
    key: 'rating', label: '内容分级', default: 'all', values: [
      { value: 'all', label: '站点默认' }, { value: 'r18', label: 'R-18' },
    ],
  };
  function idValue(value) {
    const id = String(value);
    if (!/^[1-9]\d{0,11}$/.test(id)) throw Park.error('NOT_FOUND', 'Pixiv 作品编号无效');
    return id;
  }
  function pageNumber(value) {
    const page = Number(value === undefined ? 1 : value);
    if (!Number.isSafeInteger(page) || page < 1) throw Park.error('CONFIG', 'Pixiv 筛选参数无效');
    return page;
  }
  function choice(value, values, fallback) {
    const result = value === undefined || value === '' ? fallback : String(value);
    if (!values.includes(result)) throw Park.error('CONFIG', 'Pixiv 筛选参数无效');
    return result;
  }
  function imageUrl(value) {
    try {
      const u = new URL(String(value));
      if (u.protocol === 'https:' && !u.username && !u.password && !u.hash &&
          (!u.port || u.port === '443') && (u.hostname === 'pximg.net' || u.hostname.endsWith('.pximg.net'))) return u.href;
    } catch (_) {}
    throw Park.error('PARSE', PARSE);
  }
  function workType(work) { return Number(work.illustType === undefined ? work.illust_type : work.illustType); }
  function ratingBadge(work) {
    // Ranking's sexual field is a sensitivity level, not the xRestrict enum.
    const tags = Array.isArray(work.tags) ? work.tags : [];
    const rating = work.xRestrict === undefined ? (tags.includes('R-18G') ? 2 : tags.includes('R-18') ? 1 : 0) : Number(work.xRestrict);
    return rating === 2 ? 'R-18G' : rating === 1 ? 'R-18' : undefined;
  }
  function isVisible(work, content) {
    return work && workType(work) === (content === 'manga' ? 1 : 0) && !work.isMasked && !work.is_masked &&
      !(work.isAdContainer) && /^\d+$/.test(String(work.id || work.illust_id || ''));
  }
  function toItem(work, ranking = false) {
    const square = !ranking;
    return {
      id: idValue(work.id || work.illust_id), title: String(work.title || ''),
      subtitle: String(work.userName || work.user_name || ''), cover: imageUrl(work.url),
      coverAspect: square ? 1 : (Number(work.width) && Number(work.height) ? Number(work.width) / Number(work.height) : null),
      pages: Number(work.pageCount || work.illust_page_count) || 0,
      views: ranking ? Number(work.view_count) || 0 : undefined,
      category: workType(work) === 1 ? '漫画' : '插画',
      badge: ratingBadge(work),
      tags: Array.isArray(work.tags) ? work.tags.map(String) : [],
    };
  }
  Park.register({
    key: 'pixiv', name: 'Pixiv', version: '0.0.2', type: 'comic', category: 'doujin',
    color: '#0096FA', icon: 'https://www.pixiv.net/favicon.ico',
    description: '插画与漫画社区，支持个性化推荐、排行、搜索和多页原图阅读',
    homepage: HOME, domains: ['pixiv.net'], language: 'multi',
    linkPatterns: ['pixiv\\.net/(?:[a-z]{2}/)?artworks/(\\d+)', 'pixiv\\.net/member_illust\\.php\\?[^#]*?illust_id=(\\d+)'],
    idPattern: '^(?:pixiv)?([1-9]\\d{0,11})$', idExample: '150687026',
    // Mobile ranking pages ignore format=json; request the desktop representation.
    network: { vpnHint: true, headers: { Referer: HOME + '/', Accept: 'application/json',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
    } },
    imageHeaders: { Referer: HOME + '/' },
    settings: [{ key: 'content', type: 'select', label: '默认作品类型', default: 'manga', options: [
      { value: 'manga', label: '漫画' }, { value: 'illust', label: '插画' },
    ] }],
    account: {
      type: 'cookies', title: 'Pixiv 账号', required: false,
      hint: '推荐与 R-18 内容需要登录；请在 Pixiv 账号设置中开启相应内容显示。Cookie 仅保存在本机。',
      loginUrl: 'https://accounts.pixiv.net/login?return_to=https%3A%2F%2Fwww.pixiv.net%2F',
      cookieUrl: HOME + '/', requiredCookies: ['PHPSESSID'],
      fields: [{ key: 'PHPSESSID', label: 'PHPSESSID', secret: true, hint: '粘贴 Pixiv 的 PHPSESSID 值' }],
      async login(values) {
        const session = String(values.PHPSESSID || '').trim();
        if (!session) throw Park.error('LOGIN_REQUIRED', LOGIN);
        if (!/^\d+_[A-Za-z0-9_-]+$/.test(session)) throw Park.error('CONFIG', 'Pixiv Cookie 格式无效');
        // Validate the candidate before replacing the current cookie jar.
        const headers = { Cookie: 'PHPSESSID=' + session };
        const extra = await this.request('/ajax/user/extra', { lang: 'zh' }, { auth: true, headers });
        if (!extra || !Number.isFinite(Number(extra.following))) throw Park.error('LOGIN_REQUIRED', LOGIN);
        const userId = session.split('_')[0];
        const user = await this.request('/ajax/user/' + userId, { full: 0, lang: 'zh' }, { headers });
        if (!user || String(user.userId) !== userId) throw Park.error('LOGIN_REQUIRED', LOGIN);
        await this.cookies.set(HOME + '/', { PHPSESSID: session });
        this.store.set('account', { id: userId, name: String(user.name || 'Pixiv') });
        await this.store.flush();
        return { name: String(user.name || 'Pixiv') };
      },
      async logout() {
        await this.cookies.clear(HOME + '/');
        this.store.set('account', null);
        await this.store.flush();
      },
      async status() {
        const cookies = await this.cookies.get(HOME + '/');
        if (!cookies.PHPSESSID) return { loggedIn: false, configured: false, name: '' };
        const account = this.store.get('account') || {};
        try {
          const extra = await this.request('/ajax/user/extra', { lang: 'zh' }, { auth: true });
          if (!extra || !Number.isFinite(Number(extra.following))) throw Park.error('LOGIN_REQUIRED', LOGIN);
          return { loggedIn: true, configured: true, name: account.name || 'Pixiv' };
        } catch (e) {
          if (e.code !== 'LOGIN_REQUIRED') throw e;
          return { loggedIn: false, configured: true, name: account.name || '' };
        }
      },
    },
    defaultFeed: 'recommended',
    feeds: [
      { key: 'recommended', label: '推荐', options: [contentOption, ratingOption] },
      { key: 'ranking', label: '排行榜', options: [contentOption, ratingOption, {
        key: 'period', label: '周期', default: 'daily', values: [
          { value: 'daily', label: '每日' }, { value: 'weekly', label: '每周' },
        ],
      }] },
    ],
    searchHint: '输入关键词或标签，可筛选漫画、插画与 R-18 内容',
    searchFilters: [contentOption, ratingOption, {
      key: 'match', label: '匹配方式', default: 's_tag', values: [
        { value: 's_tag', label: '标签部分匹配' }, { value: 's_tag_full', label: '标签完全匹配' },
        { value: 's_tc', label: '标题与简介' },
      ],
    }, { key: 'sort', label: '排序', default: 'date_d', values: [
      { value: 'date_d', label: '新到旧' }, { value: 'date', label: '旧到新' },
    ] }],

    contentOf(options) {
      const selected = options && options.content;
      return choice(!selected || selected === '@setting' ? this.config.content : selected, ['manga', 'illust'], 'manga');
    },
    async requireLogin() {
      const cookies = await this.cookies.get(HOME + '/');
      if (!cookies.PHPSESSID) throw Park.error('LOGIN_REQUIRED', LOGIN);
    },
    async request(path, params = {}, { auth = false, headers = {} } = {}) {
      const response = await this.http.get(HOME + path, { params, headers });
      if (response.status === 401 || (auth && [400, 403].includes(response.status))) throw Park.error('LOGIN_REQUIRED', LOGIN);
      if (response.status === 404) throw Park.error('NOT_FOUND', '内容不存在或已被删除');
      if (!response.ok) throw Park.error('HTTP', 'Pixiv 请求失败，请检查网络后重试', { status: response.status });
      let data;
      try { data = JSON.parse(response.body); } catch (_) { throw Park.error('PARSE', PARSE); }
      if (!data || typeof data !== 'object') throw Park.error('PARSE', PARSE);
      if (data.error) {
        if (auth || /login|ログイン|登录|登入|age|年齢|年龄|閲覧|浏览|权限/i.test(String(data.message || ''))) throw Park.error('LOGIN_REQUIRED', LOGIN);
        if (/not found|見つか|不存在|已删除|削除/i.test(String(data.message || ''))) throw Park.error('NOT_FOUND', '内容不存在或已被删除');
        throw Park.error('PARSE', PARSE);
      }
      return path === '/ranking.php' ? data : data.body;
    },
    async feed(key, req = {}) {
      const page = pageNumber(req.page), options = req.options || {};
      const content = this.contentOf(options);
      const rating = choice(options.rating, ['all', 'r18'], 'all');
      if (key === 'recommended') {
        await this.requireLogin();
        // The site's homepage has a finite recommendation section, not numbered pages.
        if (page > 1) return { items: [], page, hasNext: false };
        const data = await this.request('/ajax/top/' + (content === 'manga' ? 'manga' : 'illust'), { mode: rating, lang: 'zh' }, { auth: true });
        const ids = data && data.page && data.page.recommend && data.page.recommend.ids;
        const works = data && data.thumbnails && data.thumbnails.illust;
        if (!Array.isArray(ids) || !Array.isArray(works)) throw Park.error('PARSE', PARSE);
        const byId = new Map(works.map(w => [String(w.id), w]));
        const selected = [...new Set(ids.map(String))].map(id => byId.get(id)).filter(w => isVisible(w, content));
        return { items: selected.map(w => toItem(w)), page, hasNext: false };
      }
      if (key !== 'ranking') throw Park.error('CONFIG', 'Pixiv 筛选参数无效');
      if (rating === 'r18') await this.requireLogin();
      const period = choice(options.period, ['daily', 'weekly'], 'daily');
      const params = { mode: period + (rating === 'r18' ? '_r18' : ''), content: content === 'manga' ? 'manga' : 'illust', format: 'json', p: page };
      if (req.cursor) {
        if (!/^\d{8}$/.test(String(req.cursor))) throw Park.error('CONFIG', 'Pixiv 筛选参数无效');
        params.date = String(req.cursor);
      }
      const data = await this.request('/ranking.php', params, { auth: rating === 'r18' });
      if (!data || !Array.isArray(data.contents)) throw Park.error('PARSE', PARSE);
      const items = data.contents.filter(w => isVisible(w, content)).map(w => toItem(w, true));
      const hasNext = Number(data.next) > page;
      const date = String(data.date || '');
      if (!/^\d{8}$/.test(date)) throw Park.error('PARSE', PARSE);
      return { items, page, hasNext, cursor: hasNext ? date : null };
    },
    async search(req = {}) {
      const page = pageNumber(req.page), filters = req.filters || {};
      const keyword = String(req.keyword || '').trim();
      if (!keyword) return { items: [], page, hasNext: false };
      const content = this.contentOf(filters), rating = choice(filters.rating, ['all', 'r18'], 'all');
      if (rating === 'r18') await this.requireLogin();
      const params = { word: keyword, order: choice(filters.sort, ['date_d', 'date'], 'date_d'), mode: rating,
        p: page, s_mode: choice(filters.match, ['s_tag', 's_tag_full', 's_tc'], 's_tag'), type: content, lang: 'zh' };
      const data = await this.request('/ajax/search/' + (content === 'manga' ? 'manga' : 'illustrations') + '/' + encodeURIComponent(keyword), params, { auth: rating === 'r18' });
      const list = data && data[content === 'manga' ? 'manga' : 'illust'];
      if (!list || !Array.isArray(list.data) || !Number.isSafeInteger(Number(list.lastPage)) || Number(list.lastPage) < 0) throw Park.error('PARSE', PARSE);
      return { items: list.data.filter(w => isVisible(w, content)).map(w => toItem(w)), page,
        total: Number(list.total) || 0, totalPages: Number(list.lastPage), hasNext: page < Number(list.lastPage) };
    },
    async artwork(id) {
      const key = idValue(id);
      const data = await this.request('/ajax/illust/' + key, { lang: 'zh' });
      if (!data || String(data.id) !== key) throw Park.error('PARSE', PARSE);
      if (![0, 1].includes(Number(data.illustType))) throw Park.error('UNSUPPORTED', 'Pixiv 动图暂不支持，请在站点查看');
      if (data.isMasked || !data.urls || !data.urls.original) throw Park.error('LOGIN_REQUIRED', LOGIN);
      if (data.isLoginOnly || Number(data.xRestrict) > 0) await this.requireLogin();
      return data;
    },
    async detail(id) {
      const data = await this.artwork(id);
      const tags = (data.tags && data.tags.tags || []).map(t => ({ name: String(t.tag), keyword: String(t.tag), filters: { match: 's_tag_full' } }));
      return {
        id: String(data.id), title: String(data.title || data.illustTitle || ''),
        cover: imageUrl(data.urls.small || data.urls.regular || data.urls.original),
        coverAspect: Number(data.width) && Number(data.height) ? Number(data.width) / Number(data.height) : null,
        url: HOME + '/artworks/' + data.id, authors: [String(data.userName || '')].filter(Boolean),
        description: Park.html.strip(String(data.description || data.illustComment || '').replace(/<br\s*\/?\s*>/gi, '\n')),
        category: Number(data.illustType) === 1 ? '漫画' : '插画', pages: Number(data.pageCount) || 0,
        likes: Number(data.bookmarkCount) || 0, views: Number(data.viewCount) || 0,
        uploaded: data.uploadDate || data.createDate || '',
        badge: ratingBadge(data),
        tags: [{ namespace: 'tag', label: '标签', tags }], chapters: null,
      };
    },
    async chapter(id) {
      const data = await this.artwork(id);
      const images = await this.request('/ajax/illust/' + idValue(id) + '/pages', { lang: 'zh' });
      if (!Array.isArray(images) || !images.length || images.length !== Number(data.pageCount)) throw Park.error('PARSE', PARSE);
      return { pages: images.map(p => ({ url: imageUrl(p.urls && p.urls.original), width: Number(p.width) || 0, height: Number(p.height) || 0 })) };
    },
  });
})();

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"}]});
