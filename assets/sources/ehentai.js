/*
 * E-Hentai / ExHentai.
 * - Lists (search / popular / toplist) are HTML; only (gid, token) pairs are scraped from them and all
 *   metadata comes from the JSON gdata API, which keeps us independent of list layouts.
 * - Search pagination is cursor based (next=<gid>); the cursor is handed back to the host.
 * - Images: gallery thumbnail pages (?p=N) give per-page links /s/{key}/{gid}-{n}; the first single page
 *   gives the image plus a `showkey`, later pages use the faster `showpage` API. Retries pass the `nl`
 *   token so the server hands out a different H@H node. 509.gif means the image quota is exhausted.
 * - All requests are rate limited to avoid temporary IP bans.
 */
Park.register({
  key: 'ehentai',
  name: 'E-Hentai',
  version: '0.0.1',
  type: 'comic',
  color: '#9C2A2A',
  icon: 'https://e-hentai.org/favicon.ico',
  description: '历史最悠久的画廊站，标签体系完善；登录后可切换里站 ExHentai',
  homepage: 'https://e-hentai.org',
  domains: ['e-hentai.org', 'exhentai.org'],
  language: 'multi',
  linkPatterns: ['(?:e-hentai|exhentai)\\.org/g/(\\d+/[0-9a-f]{10})'],
  idPattern: '^(\\d+)[_/ ]([0-9a-f]{10})/?$',
  idExample: '2345678/abcdef1234',
  imageHeaders: { Referer: 'https://e-hentai.org/' },

  settings: [
    {
      key: 'site',
      type: 'select',
      label: '站点',
      description: '里站 ExHentai 需要登录且账号有访问权限',
      default: 'e-hentai',
      options: [
        { value: 'e-hentai', label: 'E-Hentai（表站）' },
        { value: 'exhentai', label: 'ExHentai（里站）' },
      ],
    },
    {
      key: 'interval',
      type: 'select',
      label: '请求间隔',
      description: '间隔过短容易被临时封禁 IP',
      default: '400',
      options: [
        { value: '200', label: '0.2 秒（激进）' },
        { value: '400', label: '0.4 秒（推荐）' },
        { value: '800', label: '0.8 秒（保守）' },
      ],
    },
  ],

  account: {
    type: 'cookies',
    title: 'E-Hentai 账号',
    hint: '登录后可以访问里站 ExHentai，并解除部分画廊的访问限制。',
    loginUrl: 'https://forums.e-hentai.org/index.php?act=Login&CODE=00',
    cookieUrl: 'https://e-hentai.org',
    requiredCookies: ['ipb_member_id', 'ipb_pass_hash'],
    fields: [
      { key: 'ipb_member_id', label: 'ipb_member_id', hint: '会员 ID，一串数字' },
      { key: 'ipb_pass_hash', label: 'ipb_pass_hash', hint: '32 位十六进制字符', secret: true },
      { key: 'igneous', label: 'igneous', hint: '访问里站时需要', secret: true, optional: true },
    ],
    async login(values) {
      const cookies = {};
      for (const k of ['ipb_member_id', 'ipb_pass_hash', 'igneous']) if (values[k]) cookies[k] = String(values[k]).trim();
      if (!cookies.ipb_member_id || !cookies.ipb_pass_hash) throw Park.error('LOGIN_REQUIRED', '缺少 ipb_member_id 或 ipb_pass_hash');
      for (const host of ['https://e-hentai.org', 'https://exhentai.org', 'https://forums.e-hentai.org']) {
        await this.cookies.set(host, cookies);
      }
      this.store.set('account', { id: cookies.ipb_member_id, igneous: !!cookies.igneous });
      return { name: `会员 ${cookies.ipb_member_id}` };
    },
    async logout() {
      for (const host of ['https://e-hentai.org', 'https://exhentai.org', 'https://forums.e-hentai.org']) {
        await this.cookies.clear(host);
      }
      this.store.set('account', null);
    },
    async status() {
      const acc = this.store.get('account');
      return acc ? { loggedIn: true, name: `会员 ${acc.id}` } : { loggedIn: false };
    },
  },

  defaultFeed: 'toplist',
  feeds: [
    { key: 'latest', label: '最新' },
    { key: 'popular', label: '当前热门' },
    {
      key: 'toplist',
      label: '排行榜',
      options: [
        {
          key: 'period',
          label: '周期',
          default: '15',
          values: [
            { value: '15', label: '昨日' },
            { value: '13', label: '近一月' },
            { value: '12', label: '近一年' },
            { value: '11', label: '总榜' },
          ],
        },
      ],
    },
  ],

  searchHint: '支持标签语法：female:"big breasts"$、artist:xxx、language:chinese',
  searchFilters: [
    {
      key: 'categories',
      label: '分类',
      type: 'multi',
      default: [],
      values: [
        { value: 'Doujinshi', label: '同人志', color: '#9E2720' },
        { value: 'Manga', label: '漫画', color: '#DB6C24' },
        { value: 'Artist CG', label: '画师CG', color: '#D38F1D' },
        { value: 'Game CG', label: '游戏CG', color: '#617C63' },
        { value: 'Western', label: '西方', color: '#AB9F60' },
        { value: 'Non-H', label: '非H', color: '#5FA9CF' },
        { value: 'Image Set', label: '图集', color: '#325CA2' },
        { value: 'Cosplay', label: 'Cosplay', color: '#6A32A2' },
        { value: 'Asian Porn', label: '亚洲', color: '#A23282' },
        { value: 'Misc', label: '杂项', color: '#777777' },
      ],
    },
    {
      key: 'language',
      label: '语言',
      default: '',
      values: [
        { value: '', label: '不限' },
        { value: 'chinese', label: '中文' },
        { value: 'japanese', label: '日文' },
        { value: 'english', label: '英文' },
      ],
    },
    {
      key: 'minRating',
      label: '最低评分',
      default: '0',
      values: [
        { value: '0', label: '不限' },
        { value: '2', label: '2 星' },
        { value: '3', label: '3 星' },
        { value: '4', label: '4 星' },
        { value: '5', label: '5 星' },
      ],
    },
    { key: 'minPages', label: '最少页数', type: 'number', default: 0 },
  ],

  CATEGORY_BITS: {
    Misc: 1,
    Doujinshi: 2,
    Manga: 4,
    'Artist CG': 8,
    'Game CG': 16,
    'Image Set': 32,
    Cosplay: 64,
    'Asian Porn': 128,
    'Non-H': 256,
    Western: 512,
  },
  CATEGORY_LABELS: {
    Doujinshi: ['同人志', '#9E2720'],
    Manga: ['漫画', '#DB6C24'],
    'Artist CG': ['画师CG', '#D38F1D'],
    'Game CG': ['游戏CG', '#617C63'],
    Western: ['西方', '#AB9F60'],
    'Non-H': ['非H', '#5FA9CF'],
    'Image Set': ['图集', '#325CA2'],
    Cosplay: ['Cosplay', '#6A32A2'],
    'Asian Porn': ['亚洲', '#A23282'],
    Misc: ['杂项', '#777777'],
    'Private': ['私有', '#777777'],
  },
  LANGUAGE_LABELS: { chinese: '中文', japanese: '日文', english: '英文', korean: '韩文' },
  NAMESPACES: [
    ['language', '语言'],
    ['parody', '原作'],
    ['character', '角色'],
    ['artist', '作者'],
    ['group', '社团'],
    ['cosplayer', 'Coser'],
    ['female', '女性'],
    ['male', '男性'],
    ['mixed', '混合'],
    ['other', '其他'],
    ['reclass', '重分类'],
    ['temp', '临时'],
  ],

  init() {
    this.wait = Park.utils.rateLimiter(Number(this.config.interval) || 400);
    this.galleries = Park.utils.lruMap(30); // gid → {perPage, links: Map(index → url), meta}
    this.showkeys = Park.utils.lruMap(30);
    this.nls = Park.utils.lruMap(500);
  },

  onSettingsChanged() {
    this.init();
  },

  get base() {
    return this.config.site === 'exhentai' ? 'https://exhentai.org' : 'https://e-hentai.org';
  },

  get apiUrl() {
    return this.config.site === 'exhentai' ? 'https://exhentai.org/api.php' : 'https://api.e-hentai.org/api.php';
  },

  async page(url, params) {
    await this.wait();
    const res = await this.http.get(url, { params });
    const body = String(res.body || '');
    if (body.includes('Your IP address has been temporarily banned')) {
      throw Park.error('BLOCKED', 'IP 被 E-Hentai 临时封禁，请稍后再试或更换网络');
    }
    if (res.status === 404 || /Key missing, or incorrect key provided|This gallery has been removed/.test(body)) {
      throw Park.error('NOT_FOUND', '画廊不存在或已被删除');
    }
    if (!res.ok) throw Park.error('HTTP', `HTTP ${res.status}`, { status: res.status });
    if (!body.trim()) {
      throw Park.error('LOGIN_REQUIRED', 'ExHentai 返回空页面：请先登录，或该账号没有里站权限');
    }
    return body;
  },

  async ensureNoWarning() {
    if (this.nwSet) return;
    await this.cookies.set(this.base, { nw: '1' });
    this.nwSet = true;
  },

  parseListing(html) {
    const seen = new Set();
    const pairs = [];
    const re = /\/g\/(\d+)\/([0-9a-f]{10})/g;
    let m;
    while ((m = re.exec(html))) {
      if (!seen.has(m[1])) {
        seen.add(m[1]);
        pairs.push([Number(m[1]), m[2]]);
      }
    }
    const next = /id="unext"\s+href="[^"]*?(?:[?&]|&amp;)next=(\d+)/.exec(html);
    const found = /Found(?: about)? ([\d,]+) results?/.exec(html);
    return {
      pairs,
      next: next ? next[1] : null,
      total: found ? Park.utils.toInt(found[1]) : null,
    };
  },

  async gdata(pairs) {
    const out = [];
    for (let i = 0; i < pairs.length; i += 25) {
      await this.wait();
      const data = await this.http.json(this.apiUrl, {
        method: 'POST',
        json: { method: 'gdata', gidlist: pairs.slice(i, i + 25), namespace: 1 },
      });
      for (const meta of data.gmetadata || []) if (!meta.error) out.push(meta);
    }
    const order = new Map(pairs.map(([gid], i) => [gid, i]));
    return out.sort((a, b) => order.get(a.gid) - order.get(b.gid));
  },

  thumb(url) {
    return String(url || '').replace('s.exhentai.org', 'ehgt.org');
  },

  tagGroups(tags) {
    const groups = {};
    for (const raw of tags || []) {
      const t = String(raw);
      const idx = t.indexOf(':');
      const ns = idx > 0 ? t.slice(0, idx) : 'misc';
      const name = idx > 0 ? t.slice(idx + 1) : t;
      (groups[ns] = groups[ns] || []).push(name);
    }
    return groups;
  },

  toItem(meta) {
    const groups = this.tagGroups(meta.tags);
    const lang = (groups.language || []).find((l) => l !== 'translated' && l !== 'rewrite') || '';
    const cat = this.CATEGORY_LABELS[meta.category] || [meta.category, '#777777'];
    return {
      id: `${meta.gid}/${meta.token}`,
      title: Park.html.unescape(meta.title),
      subtitle: Park.html.unescape(meta.title_jpn || ''),
      cover: this.thumb(meta.thumb),
      pages: Number(meta.filecount) || 0,
      rating: Park.utils.toFloat(meta.rating),
      language: this.LANGUAGE_LABELS[lang] || lang,
      category: cat[0],
      badgeColor: cat[1],
      uploaded: Park.utils.formatDate(meta.posted),
      tags: (groups.female || []).concat(groups.male || [], groups.other || []).slice(0, 6),
    };
  },

  async listPage(url, params, page) {
    await this.ensureNoWarning();
    const listing = this.parseListing(await this.page(url, params));
    const metas = await this.gdata(listing.pairs);
    return {
      items: metas.map((m) => this.toItem(m)),
      page,
      totalPages: listing.total ? Math.ceil(listing.total / 25) : null,
      total: listing.total,
      hasNext: !!listing.next,
      cursor: listing.next,
    };
  },

  async feed(key, req) {
    const page = Math.max(1, req.page || 1);
    if (key === 'popular') {
      const res = await this.listPage(`${this.base}/popular`, null, 1);
      return Object.assign(res, { hasNext: false, cursor: null, totalPages: 1 });
    }
    if (key === 'toplist') {
      const tl = (req.options && req.options.period) || '15';
      const params = { tl };
      if (page > 1) params.p = String(page - 1);
      const res = await this.listPage('https://e-hentai.org/toplist.php', params, page);
      return Object.assign(res, { hasNext: res.items.length > 0 && page < 200, cursor: null, totalPages: 200 });
    }
    return this.search({ keyword: '', page, cursor: req.cursor, filters: {} });
  },

  searchParams(req) {
    const f = req.filters || {};
    const params = {};
    const words = [String(req.keyword || '').trim()];
    if (f.language && !/language:/i.test(words[0])) words.push(`language:${f.language}`);
    const search = words.filter(Boolean).join(' ');
    if (search) params.f_search = search;
    const cats = Array.isArray(f.categories) ? f.categories : f.categories ? [f.categories] : [];
    if (cats.length) {
      let mask = 1023;
      for (const c of cats) mask &= ~(this.CATEGORY_BITS[c] || 0);
      params.f_cats = String(mask);
    }
    const rating = Number(f.minRating) || 0;
    if (rating >= 2) Object.assign(params, { advsearch: '1', f_sr: 'on', f_srdd: String(Math.min(rating, 5)) });
    if (Number(f.minPages) > 1) Object.assign(params, { advsearch: '1', f_sp: 'on', f_spf: String(Number(f.minPages)) });
    return params;
  },

  async search(req) {
    const page = Math.max(1, req.page || 1);
    const params = this.searchParams(req);
    if (page > 1 && !req.cursor) {
      throw Park.error('UNSUPPORTED', 'E-Hentai 只能按顺序翻页');
    }
    if (req.cursor) params.next = String(req.cursor);
    return this.listPage(`${this.base}/`, params, page);
  },

  async random(req) {
    // gid grows over time: jump to a random cursor between the newest and oldest galleries.
    const params = this.searchParams(req || {});
    await this.ensureNoWarning();
    const newest = this.parseListing(await this.page(`${this.base}/`, params));
    if (!newest.pairs.length) throw Park.error('NOT_FOUND', '没有符合条件的画廊');
    let pairs = newest.pairs;
    if (newest.next) {
      const oldest = this.parseListing(await this.page(`${this.base}/`, Object.assign({}, params, { prev: '1' })));
      const low = Math.min(...(oldest.pairs.length ? oldest.pairs : pairs).map((p) => p[0]));
      const high = Math.max(...pairs.map((p) => p[0]));
      if (high > low) {
        const cursor = low + 1 + Math.floor(Math.random() * (high - low));
        const jumped = this.parseListing(await this.page(`${this.base}/`, Object.assign({}, params, { next: String(cursor) })));
        if (jumped.pairs.length) pairs = jumped.pairs;
      }
    }
    const pick = pairs[Math.floor(Math.random() * pairs.length)];
    return `${pick[0]}/${pick[1]}`;
  },

  splitId(id) {
    const m = /^(\d+)[_/ ]([0-9a-f]{10})/.exec(String(id));
    if (!m) throw Park.error('NOT_FOUND', `无效的画廊 ID：${id}`);
    return [Number(m[1]), m[2]];
  },

  /** Parses one gallery thumbnail page: page links and (sprite) thumbnails keyed by 0-based index. */
  parseGalleryPage(html, gid) {
    const doc = Park.html.parse(html);
    const entries = [];
    for (const a of doc.querySelectorAll('#gdt a')) {
      const href = a.getAttribute('href') || '';
      const m = new RegExp(`/s/[0-9a-f]{10}/${gid}-(\\d+)`).exec(href);
      if (!m) continue;
      const div = a.querySelector('div[style]');
      const img = a.querySelector('img');
      let thumb = null;
      if (div) {
        const style = div.getAttribute('style') || '';
        const url = /url\(([^)]+)\)/.exec(style);
        const w = /width:\s*(\d+)px/.exec(style);
        const h = /height:\s*(\d+)px/.exec(style);
        const pos = /\)\s*(-?\d+)(?:px)?\s+(-?\d+)(?:px)?/.exec(style);
        if (url) {
          thumb = {
            url: url[1],
            width: w ? Number(w[1]) : null,
            height: h ? Number(h[1]) : null,
            offsetX: pos ? -Number(pos[1]) : 0,
            offsetY: pos ? -Number(pos[2]) : 0,
          };
        }
      } else if (img) {
        thumb = { url: img.getAttribute('src') || '' };
      }
      entries.push({ index: Number(m[1]) - 1, link: href, thumb });
    }
    const pageNums = [...doc.querySelectorAll('table.ptt td a')].map((a) => Number(a.textContent)).filter((n) => n > 0);
    return { entries, thumbPages: pageNums.length ? Math.max(...pageNums) : 1, doc };
  },

  async galleryPage(gid, token, p) {
    let state = this.galleries.get(gid);
    if (!state) {
      state = { links: new Map(), thumbs: new Map(), loaded: new Set(), perPage: 0, thumbPages: 1 };
      this.galleries.set(gid, state);
    }
    if (state.loaded.has(p)) return state;
    await this.ensureNoWarning();
    const html = await this.page(`${this.base}/g/${gid}/${token}/`, p ? { p: String(p) } : null);
    const parsed = this.parseGalleryPage(html, gid);
    for (const e of parsed.entries) {
      state.links.set(e.index, e.link);
      if (e.thumb) state.thumbs.set(e.index, e.thumb);
    }
    if (p === 0) {
      state.perPage = parsed.entries.length || 20;
      state.thumbPages = parsed.thumbPages;
      state.doc = parsed.doc;
    }
    state.loaded.add(p);
    return state;
  },

  async detail(id) {
    const [gid, token] = this.splitId(id);
    const [metas, state] = await Promise.all([this.gdata([[gid, token]]), this.galleryPage(gid, token, 0)]);
    const meta = metas[0];
    if (!meta) throw Park.error('NOT_FOUND', '画廊不存在或已被删除');
    const item = this.toItem(meta);
    const groups = this.tagGroups(meta.tags);
    const known = new Set(this.NAMESPACES.map(([ns]) => ns));
    const tags = this.NAMESPACES.filter(([ns]) => groups[ns])
      .concat(Object.keys(groups).filter((ns) => !known.has(ns)).map((ns) => [ns, ns]))
      .map(([ns, label]) => ({
        namespace: ns,
        label,
        tags: groups[ns].map((name) => ({ name, keyword: `${ns}:"${name}$"` })),
      }));
    const thumbs = [];
    for (let i = 0; i < state.perPage && i < item.pages; i++) thumbs.push(state.thumbs.get(i) || null);
    return Object.assign(item, {
      url: `${this.base}/g/${gid}/${token}/`,
      authors: (groups.artist || []).concat(groups.group || []),
      uploader: Park.html.unescape(meta.uploader || ''),
      size: meta.filesize ? `${(meta.filesize / 1048576).toFixed(1)} MB` : '',
      expunged: !!meta.expunged,
      tags,
      chapters: null,
      thumbnails: thumbs.filter(Boolean),
      thumbnailsTotal: item.pages,
    });
  },

  /** Thumbnails for the preview grid, one gallery thumbnail page at a time. */
  async thumbnails(id, page) {
    const [gid, token] = this.splitId(id);
    const first = await this.galleryPage(gid, token, 0);
    const p = Math.max(0, Number(page) || 0);
    const state = p === 0 ? first : await this.galleryPage(gid, token, p);
    const start = p * state.perPage;
    const list = [];
    for (let i = start; i < start + state.perPage; i++) {
      if (state.thumbs.has(i)) list.push(Object.assign({ index: i }, state.thumbs.get(i)));
    }
    return { thumbnails: list, page: p, hasNext: p + 1 < state.thumbPages };
  },

  async chapter(id) {
    const [gid, token] = this.splitId(id);
    const [metas] = await Promise.all([this.gdata([[gid, token]]), this.galleryPage(gid, token, 0)]);
    const count = metas[0] ? Number(metas[0].filecount) : 0;
    if (!count) throw Park.error('NOT_FOUND', '画廊没有图片');
    // Images are resolved lazily one page at a time by resolveImage.
    return { pages: Array.from({ length: count }, (_, i) => ({ token: String(i) })), cacheKey: `eh-${gid}` };
  },

  async pageLink(gid, token, index) {
    const first = await this.galleryPage(gid, token, 0);
    if (!first.links.has(index)) await this.galleryPage(gid, token, Math.floor(index / (first.perPage || 20)));
    const link = first.links.get(index);
    if (!link) throw Park.error('NOT_FOUND', `找不到第 ${index + 1} 页`);
    return link;
  },

  parseSinglePage(html) {
    const img = /<img id="img" src="([^"]+)"[^>]*?(?:style="width:(\d+)px;height:(\d+)px")?/.exec(html);
    const nl = /nl\('([^']+)'\)/.exec(html);
    const showkey = /showkey\s*=\s*"([^"]+)"/.exec(html);
    return {
      url: img ? Park.html.unescape(img[1]) : '',
      width: img && img[2] ? Number(img[2]) : null,
      height: img && img[3] ? Number(img[3]) : null,
      nl: nl ? nl[1] : null,
      showkey: showkey ? showkey[1] : null,
    };
  },

  async resolveImage(req) {
    const [gid, token] = this.splitId(req.id);
    const index = Number(req.token !== undefined ? req.token : req.index);
    const link = await this.pageLink(gid, token, index);
    const nlKey = `${gid}-${index}`;
    let result;
    const showkey = this.showkeys.get(gid);
    if (req.retry > 0 && this.nls.get(nlKey)) {
      result = this.parseSinglePage(await this.page(link, { nl: this.nls.get(nlKey) }));
    } else if (showkey) {
      await this.wait();
      const imgkey = /\/s\/([0-9a-f]{10})\//.exec(link)[1];
      const res = await this.http.post(this.apiUrl, {
        json: { method: 'showpage', gid, page: index + 1, imgkey, showkey },
      });
      if (res.ok) {
        const data = res.json();
        const parsed = this.parseSinglePage(`${data.i3 || ''}${data.i6 || ''}`);
        if (parsed.url) result = Object.assign(parsed, { width: Number(data.x) || null, height: Number(data.y) || null });
      }
      if (!result) result = this.parseSinglePage(await this.page(link));
    } else {
      result = this.parseSinglePage(await this.page(link));
    }
    if (result.showkey) this.showkeys.set(gid, result.showkey);
    if (result.nl) this.nls.set(nlKey, result.nl);
    if (!result.url) throw Park.error('PARSE', `第 ${index + 1} 页没有图片`);
    if (/\/509s?\.gif$/.test(result.url)) {
      throw Park.error('BLOCKED', 'E-Hentai 图片配额已用尽（509），请稍后再试或登录后重置配额');
    }
    return {
      url: result.url,
      width: result.width,
      height: result.height,
      headers: { Referer: `${this.base}/` },
      cacheKey: `eh-${gid}-${index}`,
    };
  },
});
