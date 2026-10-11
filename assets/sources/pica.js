/*
 * PicACG (哔咔漫画) — app API at picaapi.picacomic.com.
 * Every request is signed: HMAC-SHA256(secret, lower(path + time + nonce + METHOD + apiKey)), where
 * `path` is the exact path + query used in the request (no leading slash). Headers must mimic the app
 * or sign-in fails with misleading errors. Everything requires an account; the token lasts ~7 days and
 * is refreshed automatically on 401 using the saved credentials.
 */
Park.register({
  key: 'pica',
  name: '哔咔漫画',
  version: '1.0.2',
  type: 'comic',
  color: '#EC97B6',
  icon: 'https://manhuabika.com/favicon.ico',
  description: '分区丰富的老牌漫画社区，支持多话连载（需要账号）',
  homepage: 'https://manhuabika.com',
  language: 'zh',
  linkPatterns: ['(?:picacomic|manhuabika|bika)[\\w.-]*/[\\w/#?=&-]*?([0-9a-f]{24})'],
  idPattern: '^([0-9a-f]{24})$',
  idExample: '5821859b5f6b9a4f93dbf6e9',
  imageHeaders: {},

  settings: [
    {
      key: 'channel',
      type: 'select',
      label: '分流',
      default: '3',
      options: [
        { value: '1', label: '分流 1' },
        { value: '2', label: '分流 2' },
        { value: '3', label: '分流 3' },
      ],
    },
    {
      key: 'quality',
      type: 'select',
      label: '图片质量',
      default: 'original',
      options: [
        { value: 'original', label: '原图' },
        { value: 'high', label: '高' },
        { value: 'medium', label: '中' },
        { value: 'low', label: '低（省流量）' },
      ],
    },
  ],

  account: {
    type: 'password',
    title: '哔咔账号',
    hint: '哔咔所有内容都需要登录；密码只保存在本机，用于 Token 过期后自动重新登录。',
    required: true,
    registerUrl: 'https://manhuabika.com/pregister/?',
    fields: [
      { key: 'email', label: '用户名 / 邮箱' },
      { key: 'password', label: '密码', secret: true },
    ],
    async login(values) {
      const email = String(values.email || '').trim();
      const password = String(values.password || '');
      if (!email || !password) throw Park.error('LOGIN_REQUIRED', '请输入账号和密码');
      const token = await this.signIn(email, password);
      this.store.set('credentials', { email, password });
      this.store.set('token', token);
      const profile = await this.request('users/profile').catch(() => null);
      const name = (profile && profile.user && profile.user.name) || email;
      this.store.set('name', name);
      return { name };
    },
    async logout() {
      this.store.set('token', null);
      this.store.set('credentials', null);
      this.store.set('name', null);
    },
    async status() {
      return this.store.get('token') ? { loggedIn: true, name: this.store.get('name', '') } : { loggedIn: false };
    },
  },

  defaultFeed: 'ranking',
  feeds: [
    {
      key: 'ranking',
      label: '排行榜',
      options: [
        {
          key: 'period',
          label: '周期',
          default: 'H24',
          values: [
            { value: 'H24', label: '24 小时' },
            { value: 'D7', label: '7 天' },
            { value: 'D30', label: '30 天' },
          ],
        },
      ],
    },
    { key: 'random', label: '随便看看' },
    {
      key: 'category',
      label: '分区',
      options: [
        {
          key: 'category',
          label: '分区',
          default: '全彩',
          values: [
            '大家都在看', '大濕推薦', '那年今天', '官方都在看', '嗶咔漢化', '全彩', '長篇', '同人', '短篇',
            '圓神領域', '碧藍幻想', 'CG雜圖', '英語 ENG', '生肉', '純愛', '百合花園', '耽美花園', '偽娘哲學',
            '後宮閃光', '扶他樂園', '單行本', '姐姐系', '妹妹系', 'SM', '性轉換', '足の恋', '人妻', 'NTR',
            '強暴', '非人類', '艦隊收藏', 'Love Live', 'SAO 刀劍神域', 'Fate', '東方', 'WEBTOON', '禁書目錄',
            '歐美', 'Cosplay', '重口地帶',
          ].map((c) => ({ value: c, label: c })),
        },
        {
          key: 'sort',
          label: '排序',
          default: 'dd',
          values: [
            { value: 'dd', label: '新到旧' },
            { value: 'da', label: '旧到新' },
            { value: 'ld', label: '最多爱心' },
            { value: 'vd', label: '最多观看' },
          ],
        },
      ],
    },
  ],

  searchHint: '关键词为普通文字，可配合分区筛选',
  searchFilters: [
    {
      key: 'sort',
      label: '排序',
      default: 'dd',
      values: [
        { value: 'dd', label: '新到旧' },
        { value: 'da', label: '旧到新' },
        { value: 'ld', label: '最多爱心' },
        { value: 'vd', label: '最多观看' },
      ],
    },
  ],

  BASE: 'https://picaapi.picacomic.com/',
  API_KEY: 'C69BAF41DA5ABD1FFEDC6D2FEA56B',
  SECRET: '~d}$Q7$eIni=V)9\\RK/P.RM4;9[7|@/CA}b~OW!3?EV`:<>M7pddUBL5n|0/*Cn',

  async headersFor(method, path) {
    const time = String(Math.floor(Date.now() / 1000));
    const nonce = (await Park.crypto.uuid()).replace(/-/g, '');
    const raw = `${path}${time}${nonce}${method}${this.API_KEY}`.toLowerCase();
    const headers = {
      'api-key': this.API_KEY,
      accept: 'application/vnd.picacomic.com.v1+json',
      'app-channel': this.config.channel || '3',
      time,
      nonce,
      signature: await Park.crypto.hmacSha256Hex(this.SECRET, raw),
      'app-version': '2.2.1.3.3.4',
      'app-uuid': 'defaultUuid',
      'image-quality': this.config.quality || 'original',
      'app-platform': 'android',
      'app-build-version': '45',
      'User-Agent': 'okhttp/3.8.1',
      'Content-Type': 'application/json; charset=UTF-8',
    };
    const token = this.store.get('token');
    if (token) headers.authorization = token;
    return headers;
  },

  async send(method, path, body) {
    const res = await this.http.request({
      url: this.BASE + path,
      method,
      headers: await this.headersFor(method, path),
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    let json = {};
    try {
      json = res.json();
    } catch (e) {
      /* non-JSON error page */
    }
    return { status: res.status, json };
  },

  async signIn(email, password) {
    this.store.set('token', null);
    const { status, json } = await this.send('POST', 'auth/sign-in', { email, password });
    const token = json && json.data && json.data.token;
    if (status !== 200 || !token) {
      throw Park.error('LOGIN_REQUIRED', `哔咔登录失败：${(json && (json.message || json.error)) || 'HTTP ' + status}`);
    }
    return token;
  },

  /** Authenticated request; returns `data`. Re-logs in once on 401. */
  async request(path, body) {
    const method = body === undefined ? 'GET' : 'POST';
    if (!this.store.get('token')) {
      const cred = this.store.get('credentials');
      if (!cred) throw Park.error('LOGIN_REQUIRED', '哔咔需要登录后才能使用');
      this.store.set('token', await this.signIn(cred.email, cred.password));
    }
    for (let attempt = 0; attempt < 2; attempt++) {
      const { status, json } = await this.send(method, path, body);
      if (status === 401 && attempt === 0) {
        const cred = this.store.get('credentials');
        if (!cred) {
          this.store.set('token', null);
          throw Park.error('LOGIN_REQUIRED', '哔咔登录已过期，请重新登录');
        }
        this.store.set('token', await this.signIn(cred.email, cred.password));
        continue;
      }
      if (status === 400 || status === 404) throw Park.error('NOT_FOUND', `哔咔：${json.message || '内容不存在'}`);
      if (status !== 200) throw Park.error('HTTP', `哔咔请求失败：HTTP ${status} ${json.message || ''}`, { status });
      return json.data || {};
    }
    throw Park.error('LOGIN_REQUIRED', '哔咔登录状态失效');
  },

  media(m) {
    if (!m || !m.path) return '';
    const server = String(m.fileServer || 'https://storage1.picacomic.com').replace(/\/$/, '');
    return m.path.startsWith('http') ? m.path : `${server}/static/${m.path}`;
  },

  toItem(c) {
    return {
      id: String(c._id),
      title: String(c.title || '').trim(),
      subtitle: String(c.author || '').trim(),
      cover: this.media(c.thumb),
      coverAspect: 0.72,
      pages: Number(c.pagesCount) || 0,
      likes: Number(c.totalLikes !== undefined ? c.totalLikes : c.likesCount) || 0,
      views: Number(c.totalViews !== undefined ? c.totalViews : c.viewsCount) || null,
      category: (c.categories || [])[0] || '', // one category keeps the cover badge readable
      badge: c.finished ? '完结' : '',
      tags: (c.tags || []).slice(0, 6),
    };
  },

  pageOf(comics, page) {
    const docs = (comics && comics.docs) || [];
    const totalPages = Number(comics && comics.pages) || null;
    return {
      items: docs.filter((d) => d && d._id).map((d) => this.toItem(d)),
      page,
      totalPages,
      total: Number(comics && comics.total) || null,
      hasNext: !!totalPages && page < totalPages,
    };
  },

  async feed(key, req) {
    const page = Math.max(1, req.page || 1);
    const o = req.options || {};
    if (key === 'ranking') {
      const data = await this.request(`comics/leaderboard?tt=${o.period || 'H24'}&ct=VC`);
      return { items: (data.comics || []).map((c) => this.toItem(c)), page: 1, totalPages: 1, hasNext: false };
    }
    if (key === 'random') {
      const data = await this.request('comics/random');
      return { items: (data.comics || []).map((c) => this.toItem(c)), page, hasNext: true };
    }
    const c = encodeURIComponent(o.category || '全彩');
    const data = await this.request(`comics?page=${page}&c=${c}&s=${o.sort || 'dd'}`);
    return this.pageOf(data.comics, page);
  },

  async search(req) {
    const page = Math.max(1, req.page || 1);
    const f = req.filters || {};
    const body = { keyword: String(req.keyword || '').trim(), sort: f.sort || 'dd' };
    if (f.category) body.categories = [f.category];
    const data = await this.request(`comics/advanced-search?page=${page}`, body);
    return this.pageOf(data.comics, page);
  },

  async random() {
    const data = await this.request('comics/random');
    const list = data.comics || [];
    if (!list.length) throw Park.error('NOT_FOUND', '哔咔随机接口没有返回作品');
    return String(list[Math.floor(Math.random() * list.length)]._id);
  },

  async episodes(id) {
    const all = [];
    for (let page = 1; page <= 50; page++) {
      const data = await this.request(`comics/${id}/eps?page=${page}`);
      const eps = data.eps || {};
      all.push(...(eps.docs || []));
      if (!eps.pages || page >= eps.pages) break;
    }
    // `order` is what the pages endpoint expects; the list comes newest first.
    return all.sort((a, b) => a.order - b.order).map((e) => ({ id: String(e.order), title: e.title || `第 ${e.order} 话` }));
  },

  async detail(id) {
    const [info, chapters, related] = await Promise.all([
      this.request(`comics/${id}`),
      this.episodes(id),
      this.request(`comics/${id}/recommendation`).catch(() => ({})),
    ]);
    const c = info.comic;
    if (!c || !c._id) throw Park.error('NOT_FOUND', `哔咔作品 ${id} 不存在`);
    const item = this.toItem(c);
    const group = (ns, label, list) =>
      list && list.length ? { namespace: ns, label, tags: list.map((name) => ({ name, keyword: name })) } : null;
    return Object.assign(item, {
      url: '',
      authors: [c.author, c.chineseTeam].filter(Boolean),
      description: String(c.description || '').trim(),
      uploaded: String(c.updated_at || c.created_at || '').slice(0, 10),
      comments: Number(c.totalComments || c.commentsCount) || null,
      tags: [group('categories', '分区', c.categories), group('tags', '标签', c.tags)].filter(Boolean),
      chapters: chapters.length > 1 ? chapters : null,
      singleChapterId: chapters.length === 1 ? chapters[0].id : '1',
      related: (related.comics || []).map((r) => this.toItem(r)),
    });
  },

  async chapter(id, chapterId) {
    const order = chapterId || '1';
    const first = (await this.request(`comics/${id}/order/${order}/pages?page=1`)).pages || {};
    const total = Number(first.pages) || 1;
    const rest = await Park.utils.mapLimit(
      Array.from({ length: Math.max(0, total - 1) }, (_, i) => i + 2),
      4,
      (p) => this.request(`comics/${id}/order/${order}/pages?page=${p}`)
    );
    const docs = (first.docs || []).concat(...rest.map((r) => (r.pages && r.pages.docs) || []));
    return { pages: docs.map((d) => ({ url: this.media(d.media) })).filter((p) => p.url) };
  },
});
