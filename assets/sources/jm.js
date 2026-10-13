/*
 * JMComic (禁漫天堂) — mobile app API.
 * - API domains rotate often: the current list is fetched from the official domain server (AES-ECB
 *   encrypted), with built-in fallbacks; failed requests automatically move on to the next domain.
 * - Each request carries token = md5(ts + secret) and tokenparam = "ts,version"; the `data` field of the
 *   response is AES-ECB encrypted with md5(ts + data secret).
 * - Images are scrambled into horizontal strips (count derived from md5(photoId + filename)); the host
 *   reassembles them natively using the `transform` descriptor returned with each page.
 */
Park.register({
  key: 'jm',
  name: '禁漫天堂',
  version: '0.0.4',
  type: 'comic',
  category: 'doujin',
  color: '#F7841E',
  icon: 'https://18comic.vip/favicon.ico',
  description: '中文本子与韩漫资源丰富，支持连载分话、自动切换线路与图片还原',
  homepage: 'https://18comic.vip',
  language: 'zh',
  linkPatterns: [
    '(?:18comic|jmcomic|jm-?comic|18-comic)[\\w.-]*\\.\\w+/(?:album|photo)s?/(\\d{3,9})',
    '(?:^|[^a-zA-Z0-9])[Jj][Mm]\\s*[-_:：#]?\\s*(\\d{3,9})(?!\\d)',
  ],
  idPattern: '^(?:[Jj][Mm])?(\\d{3,9})$',
  idExample: 'JM350234',
  imageHeaders: {
    'X-Requested-With': 'com.example.app',
    Referer: 'https://localhost/',
  },

  settings: [
    {
      key: 'apiDomain',
      type: 'select',
      label: 'API 线路',
      description: '自动模式会在请求失败时依次尝试其他线路',
      default: 'auto',
      options: [
        { value: 'auto', label: '自动' },
        { value: '0', label: '线路 1' },
        { value: '1', label: '线路 2' },
        { value: '2', label: '线路 3' },
        { value: '3', label: '线路 4' },
      ],
    },
    {
      key: 'imageStream',
      type: 'select',
      label: '图片分流',
      default: '1',
      options: [
        { value: '1', label: '分流 1' },
        { value: '2', label: '分流 2' },
        { value: '3', label: '分流 3' },
        { value: '4', label: '分流 4' },
      ],
    },
  ],

  defaultFeed: 'promote',
  feeds: [
    { key: 'promote', label: '推荐' },
    { key: 'latest', label: '最新' },
    {
      key: 'ranking',
      label: '排行榜',
      options: [
        {
          key: 'period',
          label: '周期',
          default: 'mv_w',
          values: [
            { value: 'mv_t', label: '日榜' },
            { value: 'mv_w', label: '周榜' },
            { value: 'mv_m', label: '月榜' },
            { value: 'mv', label: '总榜' },
          ],
        },
      ],
    },
    {
      key: 'category',
      label: '分类',
      options: [
        {
          key: 'category',
          label: '分类',
          default: 'doujin',
          values: [
            { value: 'doujin', label: '同人' },
            { value: 'single', label: '单本' },
            { value: 'short', label: '短篇' },
            { value: 'hanman', label: '韩漫' },
            { value: 'meiman', label: '美漫' },
            { value: 'another', label: '其他' },
            { value: 'doujin_cosplay', label: 'Cosplay' },
            { value: '3D', label: '3D' },
            { value: '禁漫漢化組', label: '禁漫汉化组' },
          ],
        },
        {
          key: 'sort',
          label: '排序',
          default: 'mr',
          values: [
            { value: 'mr', label: '最新' },
            { value: 'mv', label: '最多观看' },
            { value: 'mv_w', label: '本周热门' },
            { value: 'tf', label: '最多喜欢' },
            { value: 'mp', label: '最多图片' },
          ],
        },
      ],
    },
  ],

  searchHint: '可搜索作品名、作者、标签；直接输入车号（如 350234）可跳转作品',
  searchFilters: [
    {
      key: 'sort',
      label: '排序',
      default: 'mr',
      values: [
        { value: 'mr', label: '最新' },
        { value: 'mv', label: '最多观看' },
        { value: 'mv_m', label: '本月热门' },
        { value: 'mv_w', label: '本周热门' },
        { value: 'mv_t', label: '今日热门' },
        { value: 'tf', label: '最多喜欢' },
        { value: 'mp', label: '最多图片' },
      ],
    },
    {
      key: 'mainTag',
      label: '搜索范围',
      default: '0',
      values: [
        { value: '0', label: '全部' },
        { value: '1', label: '作品' },
        { value: '2', label: '作者' },
        { value: '3', label: '标签' },
        { value: '4', label: '登场人物' },
      ],
    },
  ],

  APP_VERSION: '2.0.16',
  TOKEN_SECRET: '18comicAPPContent',
  DATA_SECRET: '185Hcomic3PAPP7R',
  DOMAIN_SECRET: 'diosfjckwpqpdfjkvnqQjsik',
  DOMAIN_SERVERS: [
    'https://rup4a04-c02.tos-cn-hongkong.bytepluses.com/newsvr-2025.txt',
    'https://rup4a04-c01.tos-ap-southeast-1.bytepluses.com/newsvr-2025.txt',
    'https://rup4a04-c03.tos-cn-beijing.bytepluses.com.cn/newsvr-2025.txt',
  ],
  FALLBACK_DOMAINS: ['www.cdnhjk.net', 'www.cdngwc.cc', 'www.cdngwc.net', 'www.cdngwc.club', 'www.cdnutc.me'],
  FALLBACK_IMAGE_HOST: 'https://cdn-msp.jmapinodeudzn.net',
  UA: 'Mozilla/5.0 (Linux; Android 10; K; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/130.0.0.0 Mobile Safari/537.36',

  async init() {
    this.domains = this.store.get('domains') || this.FALLBACK_DOMAINS.slice();
    this.imageHost = this.store.get('imageHost') || this.FALLBACK_IMAGE_HOST;
    this.preferred = 0;
    const lastRefresh = this.store.get('domainsAt', 0);
    if (Date.now() - lastRefresh > 6 * 3600 * 1000) await this.refreshDomains().catch(() => {});
    await this.refreshImageHost().catch(() => {});
  },

  async onSettingsChanged() {
    await this.refreshImageHost().catch(() => {});
  },

  async decrypt(data, secret) {
    const text = await Park.crypto.aesEcbDecrypt(String(data).trim(), await Park.crypto.md5Hex(secret));
    const start = text.search(/[[{]/);
    const end = Math.max(text.lastIndexOf('}'), text.lastIndexOf(']'));
    return JSON.parse(text.slice(start, end + 1));
  },

  async refreshDomains() {
    for (const url of this.DOMAIN_SERVERS) {
      try {
        const res = await this.http.get(url, { timeout: 8000 });
        if (!res.ok) continue;
        const body = String(res.body).replace(/^[^\x00-\x7f]+/, '');
        const json = await this.decrypt(body, this.DOMAIN_SECRET);
        if (Array.isArray(json.Server) && json.Server.length) {
          this.domains = json.Server.slice(0, 6);
          this.store.set('domains', this.domains);
          this.store.set('domainsAt', Date.now());
          return this.domains;
        }
      } catch (e) {
        /* try next server */
      }
    }
    return this.domains;
  },

  async refreshImageHost() {
    const setting = await this.api('/setting', { app_img_shunt: this.config.imageStream || '1', express: '' });
    if (setting && setting.img_host) {
      this.imageHost = String(setting.img_host).replace(/\/$/, '');
      this.store.set('imageHost', this.imageHost);
    }
  },

  domainOrder() {
    const fixed = this.config.apiDomain;
    if (fixed !== undefined && fixed !== 'auto' && this.domains[Number(fixed)]) return [Number(fixed)];
    const order = [];
    for (let i = 0; i < this.domains.length; i++) order.push((this.preferred + i) % this.domains.length);
    return order;
  },

  headers(ts) {
    return {
      Accept: '*/*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
      Origin: 'https://localhost',
      Referer: 'https://localhost/',
      'X-Requested-With': 'com.example.app',
      'User-Agent': this.UA,
      Authorization: 'Bearer',
      tokenparam: `${ts},${this.APP_VERSION}`,
    };
  },

  /** Calls an API path on the first working domain and returns the decrypted `data`. */
  async api(path, params, form) {
    let lastError = null;
    for (const index of this.domainOrder()) {
      const domain = this.domains[index];
      const ts = Math.floor(Date.now() / 1000);
      const headers = this.headers(ts);
      headers.token = await Park.crypto.md5Hex(`${ts}${this.TOKEN_SECRET}`);
      let res;
      try {
        res = await this.http.request({
          url: `https://${domain}${path}`,
          method: form ? 'POST' : 'GET',
          params,
          form,
          headers,
          timeout: 15000,
        });
      } catch (err) {
        lastError = err;
        continue;
      }
      if (res.status >= 500 || res.status === 403) {
        lastError = Park.error('HTTP', `禁漫线路 ${index + 1} 异常（HTTP ${res.status}）`, { status: res.status });
        continue;
      }
      let json;
      try {
        json = res.json();
      } catch (err) {
        lastError = err;
        continue;
      }
      this.preferred = index;
      if (res.status === 401) throw Park.error('LOGIN_REQUIRED', json.errorMsg || '需要登录');
      if (json.code !== undefined && json.code !== 200) {
        const msg = json.errorMsg || json.message || `code ${json.code}`;
        if (/不存在|not found|找不到/i.test(msg)) throw Park.error('NOT_FOUND', msg);
        throw Park.error('HTTP', `禁漫：${msg}`);
      }
      if (typeof json.data !== 'string') return json.data;
      return this.decrypt(json.data, `${ts}${this.DATA_SECRET}`);
    }
    throw lastError || Park.error('NETWORK', '所有禁漫线路均不可用');
  },

  cover(id) {
    return `${this.imageHost}/media/albums/${id}_3x4.jpg`;
  },

  toItem(e) {
    const cat = (e.category && e.category.title) || '';
    const sub = (e.category_sub && e.category_sub.title) || '';
    return {
      id: String(e.id),
      title: e.name || `JM${e.id}`,
      subtitle: e.author || '',
      cover: this.cover(e.id),
      coverAspect: 0.75,
      category: sub && sub !== cat ? `${cat}·${sub}` : cat,
      likes: Park.utils.toInt(e.likes),
      views: Park.utils.toInt(e.total_views),
      uploaded: e.update_at ? Park.utils.formatDate(e.update_at) : '',
    };
  },

  pageOf(data, page) {
    const items = (data.content || data.list || []).map((e) => this.toItem(e));
    const total = Park.utils.toInt(data.total, 0);
    const totalPages = total ? Math.ceil(total / 80) : null;
    return { items, page, totalPages, total, hasNext: totalPages ? page < totalPages : items.length >= 80 };
  },

  async feed(key, req) {
    const page = Math.max(1, req.page || 1);
    const o = req.options || {};
    if (key === 'promote') {
      const data = await this.api('/promote', { page: 0 });
      const sections = (data || [])
        .filter((s) => !['library', 'novels'].includes(s.type) && Array.isArray(s.content) && s.content.length)
        .map((s) => ({ title: String(s.title || '').replace(/→.*$/, '').trim(), items: s.content.map((e) => this.toItem(e)) }));
      return { sections, page: 1, hasNext: false };
    }
    if (key === 'latest') return this.filter('0', 'mr', page);
    if (key === 'ranking') return this.filter('0', o.period || 'mv_w', page);
    return this.filter(o.category || 'doujin', o.sort || 'mr', page);
  },

  async filter(category, order, page) {
    const data = await this.api('/categories/filter', { page, order: '', c: category, o: order });
    return this.pageOf(data, page);
  },

  async search(req) {
    const page = Math.max(1, req.page || 1);
    const f = req.filters || {};
    const keyword = String(req.keyword || '').trim().replace(/^jm\s*(?=\d+$)/i, '');
    // The search endpoint returns nothing without a keyword: browse everything in the chosen order instead.
    if (!keyword) return this.filter('0', f.sort || 'mr', page);
    const data = await this.api('/search', {
      search_query: keyword,
      page,
      o: f.sort || 'mr',
      main_tag: f.mainTag || '0',
    });
    if (data && data.redirect_aid) {
      const d = await this.detail(String(data.redirect_aid));
      return { items: [d], page: 1, totalPages: 1, hasNext: false };
    }
    return this.pageOf(data, page);
  },

  async random() {
    const first = await this.filter('0', 'mr', 1);
    const pages = Math.max(1, Math.min(first.totalPages || 1, 200));
    const page = 1 + Math.floor(Math.random() * pages);
    const listing = page === 1 ? first : await this.filter('0', 'mr', page);
    const items = listing.items.length ? listing.items : first.items;
    if (!items.length) throw Park.error('NOT_FOUND', '没有可随机的作品');
    return items[Math.floor(Math.random() * items.length)].id;
  },

  async detail(id) {
    const aid = String(id).replace(/^jm/i, '');
    const d = await this.api('/album', { id: aid });
    if (!d || !d.name) throw Park.error('NOT_FOUND', `JM${aid} 不存在`);
    const series = (d.series || []).slice().sort((a, b) => Number(a.sort) - Number(b.sort));
    const chapters = series.length
      ? series.map((e) => ({ id: String(e.id), title: String(e.name || '').trim() || `第 ${e.sort} 话` }))
      : null;
    const group = (label, list, mainTag) =>
      list && list.length
        ? { namespace: label, label, tags: list.map((name) => ({ name, keyword: name, filters: { mainTag } })) }
        : null;
    return {
      id: aid,
      title: d.name,
      subtitle: `JM${aid}`,
      cover: this.cover(aid),
      url: `https://18comic.vip/album/${aid}/`,
      authors: d.author || [],
      pages: Park.utils.toInt(d.total_photos, 0),
      likes: Park.utils.toInt(d.likes),
      views: Park.utils.toInt(d.total_views),
      uploaded: Park.utils.formatDate(d.addtime),
      description: String(d.description || '').trim(),
      comments: Park.utils.toInt(d.comment_total),
      tags: [
        group('作者', d.author, '2'),
        group('作品', d.works, '1'),
        group('登场人物', d.actors, '4'),
        group('标签', d.tags, '3'),
      ].filter(Boolean),
      chapters,
      related: (d.related_list || []).map((e) => this.toItem(e)),
    };
  },

  /** Number of strips an image was cut into (0 = not scrambled). */
  segments(photoId, filename, hash) {
    const pid = Number(photoId);
    if (pid < 220980) return 0;
    if (pid < 268850) return 10;
    const mod = pid < 421926 ? 10 : 8;
    return (hash.charCodeAt(hash.length - 1) % mod) * 2 + 2;
  },

  async chapter(id, chapterId) {
    const pid = String(chapterId || id).replace(/^jm/i, '');
    const d = await this.api('/chapter', { id: pid });
    const images = (d && d.images) || [];
    if (!images.length) throw Park.error('NOT_FOUND', '章节没有图片');
    const names = images.map((name) => name.replace(/\.[^.]+$/, ''));
    const hashes = await Park.crypto.md5Hex(names.map((n) => `${pid}${n}`));
    return {
      pages: images.map((name, i) => {
        const n = name.toLowerCase().endsWith('.gif') ? 0 : this.segments(pid, names[i], hashes[i]);
        const page = { url: `${this.imageHost}/media/photos/${pid}/${name}` };
        if (n > 1) page.transform = { type: 'unscramble-strips', segments: n };
        return page;
      }),
    };
  },
});

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"},{"key":"work","label":"作品连载","hint":"作品编号或详情链接"}],"searchFilters":{"sort":"mr"}});
