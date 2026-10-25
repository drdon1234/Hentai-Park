/* 完整详情路径作为作品 ID；静态提取媒体，不执行远程播放器代码。 */
Park.register({
  i18n: {
    "zh-Hant": {"标清": "標清", "综合成人视频，支持排行、搜索和高清播放": "綜合成人影片，支援排行、搜尋和高清播放", "高清": "高清"},
    "ja": {"标清": "標準画質", "综合成人视频，支持排行、搜索和高清播放": "ランキング・検索・高画質再生に対応した成人向け動画", "高清": "高画質"},
    "ko": {"标清": "표준 화질", "综合成人视频，支持排行、搜索和高清播放": "순위, 검색 및 고화질 재생을 지원하는 성인 동영상", "高清": "고화질"},
    "en": {"标清": "Standard quality", "综合成人视频，支持排行、搜索和高清播放": "Adult videos with rankings, search and high-quality playback", "高清": "High quality"},
    "es": {"标清": "Calidad estándar", "综合成人视频，支持排行、搜索和高清播放": "Vídeos para adultos con clasificaciones, búsqueda y reproducción de alta calidad", "高清": "Alta calidad"},
    "ru": {"标清": "Стандартное качество", "综合成人视频，支持排行、搜索和高清播放": "Видео для взрослых с рейтингами, поиском и высоким качеством", "高清": "Высокое качество"},
    "ar": {"标清": "جودة قياسية", "综合成人视频，支持排行、搜索和高清播放": "فيديوهات للبالغين مع تصنيفات وبحث وتشغيل بجودة عالية", "高清": "جودة عالية"},
  },
  key: 'xvideos', name: 'XVideos', version: '0.0.9', minAppVersion: '0.9.2', type: 'video', category: 'adult', color: '#E31B23',
  description: '综合成人视频，支持排行、搜索和高清播放', homepage: 'https://www.xvideos.com', domains: ['xvideos.com'], language: 'en',
  network: {mode: 'native', vpnHint: true}, imageHeaders: {Referer: 'https://www.xvideos.com/'},
  media: {mode: 'native', origin: 'https://www.xvideos.com', domains: ['xvideos-cdn.com']},
  linkPatterns: ['xvideos\\.com/(video\\.[a-z0-9]+/[^?#\\s]+)(?:[?#]|$)'],
  defaultFeed: 'ranking', feeds: [{key: 'ranking', label: '排行榜'}, {key: 'categories', label: '标签', options: [
    {key: 'tagGroup', label: '索引', type: 'select', default: 'popular', values: [
      {value: 'popular', label: '热门'}, {value: '09', label: '0–9'},
      ...'abcdefghijklmnopqrstuvwxyz'.split('').map(value => ({value, label: value.toUpperCase()})),
    ]},
    {key: 'tagRange', label: '范围', type: 'select', default: '1', dynamic: true, dependsOn: ['tagGroup'], values: []},
    {key: 'tag', label: '标签', type: 'select', default: '', dynamic: true, dependsOn: ['tagGroup', 'tagRange'], values: []},
  ]}],
  searchHint: '搜索作品名或标签', BASE: 'https://www.xvideos.com',
  siteUrl(value) { return !!Park.url.site(this, value); },
  validId(id) {
    const value = String(id);
    if (value.length > 2048 || !/^video\.[a-z0-9]{5,32}\/[a-zA-Z0-9_%./-]+$/.test(value) || /(?:^|\/)\.\.(?:\/|$)/.test(value) || /%(?![0-9a-f]{2})|%2[ef]|%5c/i.test(value)) throw Park.error('NOT_FOUND', '影片编号无效');
    return value;
  },
  pageUrl(value, kind) {
    let u;
    try { u = new URL(value, this.BASE); } catch (_) { throw Park.error('CONFIG', '视频列表地址无效'); }
    const allowed = kind === 'feed' ? /^\/best(?:\/\d{4}-\d{2}(?:\/\d+)?)?$/.test(u.pathname) : u.pathname === '/' || /^\/tags\/[a-z0-9_-]+(?:\/\d+)?\/?$/i.test(u.pathname);
    if (!allowed || !this.siteUrl(u)) throw Park.error('CONFIG', '视频列表地址无效');
    return u.href;
  },
  mediaUrl(value) { return Park.url.parse(value, this.BASE, this.media.domains)?.href || ''; },
  async getPage(url) {
    const r = await this.http.get(url, {timeout: 30000});
    if (r.status === 404) throw Park.error('NOT_FOUND', '影片不存在');
    if (!r.ok) throw Park.error('HTTP', '成人视频请求失败');
    const finalUrl = Park.url.response(this, r, url);
    if (r.body.length > 4 * 1024 * 1024) throw Park.error('PARSE', '影片页面过大');
    return {html: r.body, doc: Park.html.parse(r.body), url: finalUrl.href};
  },
  cards(doc) {
    const items = [], seen = new Set();
    for (const c of doc.querySelectorAll('div.thumb-block')) {
      const a = c.querySelector('.title a[href]') || c.querySelector('a[href^="/video."]'), img = c.querySelector('img');
      const href = a && a.getAttribute('href'), title = Park.html.text(a), cover = img && (img.getAttribute('data-src') || img.getAttribute('src'));
      if (!href || !title || !/^https:\/\//.test(cover || '')) continue;
      let id;
      try { const u = new URL(href, this.BASE); if (!this.siteUrl(u)) continue; id = this.validId(u.pathname.slice(1)); } catch (_) { continue; }
      const encoded = /^video\.([^/]+)/.exec(id)[1];
      if (seen.has(encoded)) continue;
      seen.add(encoded); items.push({id, title, cover, coverAspect: 16/9, duration: Park.html.text(c.querySelector('.duration')),
        views: Park.utils.parseCount(Park.html.text(c.querySelector('.views-count'))), uploader: Park.html.text(c.querySelector('.name'))});
    }
    return items;
  },
  async listing(url, req, kind) {
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    if (page > 1 && !req.cursor) throw Park.error('CONFIG', '请按顺序加载视频列表');
    const {doc, url: finalUrl} = await this.getPage(this.pageUrl(req.cursor || url, kind));
    let cursor;
    for (const a of doc.querySelectorAll('.pagination a[href], .pagination3 a[href]')) {
      const u = new URL(a.getAttribute('href'), finalUrl);
      const index = kind === 'feed' ? /\/(\d+)$/.exec(u.pathname)?.[1] : u.searchParams.get('p') || /\/(\d+)\/?$/.exec(u.pathname)?.[1];
      if (index !== null && index !== undefined && Number(index) === page) { cursor = this.pageUrl(u.href, kind); break; }
    }
    return {items: this.cards(doc), page, hasNext: !!cursor, cursor};
  },
  async feed(key, req) {
    if (key === 'categories') {
      const tag = req.options?.tag;
      if (tag) {
        if (typeof tag !== 'string' || !/^\/tags\/[a-z0-9][a-z0-9_-]*$/i.test(tag)) throw Park.error('CONFIG', '视频标签无效');
        return this.listing(this.BASE + tag, req, 'search');
      }
      return this.listing(this.BASE + '/best', req, 'feed');
    }
    if (key !== 'ranking') throw Park.error('CONFIG', '未知视频列表');
    return this.listing(this.BASE + '/best', req, 'feed');
  },
  async tagIndex(group) {
    if (group !== 'popular' && !/^(?:09|[a-z])$/.test(group || '')) throw Park.error('CONFIG', '视频标签无效');
    this.tagCache ||= new Map();
    const cached = this.tagCache.get(group);
    if (cached && Date.now() - cached.time < 300000) return cached.rows;
    const {doc} = await this.getPage(this.BASE + '/tags' + (group === 'popular' ? '' : '/' + group));
    const seen = new Set();
    const rows = [];
    for (const link of doc.querySelectorAll('#tags a[href]')) {
      const href = link.getAttribute('href'), match = /^\/tags\/([a-z0-9][a-z0-9_-]*)\/?$/i.exec(href || '');
      const label = Park.html.text(link.querySelector('b') || link);
      const value = match && '/tags/' + match[1];
      if (!value || !label || seen.has(value.toLowerCase())) continue;
      seen.add(value.toLowerCase());
      rows.push({value, label, count: Park.utils.parseCount(Park.html.text(link.querySelector('.navbadge')).replace(/,/g, '')) || 0});
    }
    rows.sort((a, b) => b.count - a.count);
    if (!rows.length || rows.length > 50000) throw Park.error('PARSE', '未找到标签列表');
    this.tagCache.set(group, {time: Date.now(), rows});
    while (this.tagCache.size > 4) this.tagCache.delete(this.tagCache.keys().next().value);
    return rows;
  },
  async filterOptions(request) {
    if (request.scope !== 'feed' || request.feed !== 'categories') return [];
    const rows = await this.tagIndex(request.values.tagGroup || 'popular');
    if (request.filter === 'tagRange') return Array.from({length: Math.ceil(rows.length / 100)}, (_, i) =>
      ({value: String(i + 1), label: (i * 100 + 1) + '–' + Math.min((i + 1) * 100, rows.length)}));
    if (request.filter !== 'tag') return [];
    const page = Number(request.values.tagRange || '1');
    if (!Number.isInteger(page) || page < 1 || page > Math.ceil(rows.length / 100)) throw Park.error('CONFIG', '视频标签无效');
    return [{value: '', label: '全部'}, ...rows.slice((page - 1) * 100, page * 100).map(({value, label}) => ({value, label}))];
  },
  async search(req) {
    const keyword = String(req.keyword || '').trim(), tag = req.filters?.tag;
    if (tag !== undefined && tag !== '') {
      if (typeof tag !== 'string' || !/^\/tags\/[a-z0-9][a-z0-9_-]*$/i.test(tag)) throw Park.error('CONFIG', '视频标签无效');
      return this.listing(this.BASE + tag, req, 'search');
    }
    if (!keyword) return {items: [], page: 1, hasNext: false};
    return this.listing(this.BASE + '/?k=' + encodeURIComponent(keyword), req, 'search');
  },
  // Related videos are not rendered as cards: the page script holds them as `var video_related=[...]`.
  related(html, id) {
    const start = html.indexOf('video_related=[');
    if (start < 0) return [];
    let depth = 0, quoted = false, end = -1;
    for (let i = start + 'video_related='.length; i < html.length && end < 0; i++) {
      const c = html[i];
      if (quoted) { if (c === '\\') i++; else if (c === '"') quoted = false; }
      else if (c === '"') quoted = true;
      else if (c === '[' || c === '{') depth++;
      else if ((c === ']' || c === '}') && --depth === 0) end = i + 1;
    }
    let data;
    try { data = JSON.parse(html.slice(start + 'video_related='.length, end)); } catch (_) { return []; }
    const items = [], seen = new Set();
    for (const v of Array.isArray(data) ? data.slice(0, 100) : []) {
      if (!v || typeof v.u !== 'string' || typeof v.i !== 'string' || !/^https:\/\//.test(v.i)) continue;
      let itemId;
      try { const u = new URL(v.u, this.BASE); if (!this.siteUrl(u)) continue; itemId = this.validId(u.pathname.slice(1)); } catch (_) { continue; }
      const encoded = /^video\.([^/]+)/.exec(itemId)[1], title = String(v.tf || v.t || '').trim();
      if (!title || itemId === id || seen.has(encoded)) continue;
      seen.add(encoded);
      items.push({id: itemId, title, cover: v.i, coverAspect: 16/9, duration: String(v.d || ''),
        views: Park.utils.parseCount(String(v.n || '')), uploader: String(v.pn || '')});
    }
    return items;
  },
  resolveContentLink(value) {
    const url = Park.url.site(this, value);
    if (!url || String(value).includes('#') || !/^\/video\.[a-z0-9]+\//.test(url.pathname)) return null;
    try { return {type: 'work', id: this.validId(url.pathname.slice(1))}; } catch (_) { return null; }
  },
  threadComments(data, ids, parentId, depth = 0) {
    if (depth > 4) throw Park.error('PARSE', '评论数据无效');
    return ids.map(id => {
      const row = data.posts?.[id];
      if (!row || typeof row !== 'object') throw Park.error('PARSE', '评论数据无效');
      if (row.private || row.deleted) return null;
      if (String(row.id) !== id || typeof row.message !== 'string') throw Park.error('PARSE', '评论数据无效');
      const body = Park.comments.html(row.message, this.BASE);
      if (!body.length) throw Park.error('PARSE', '评论数据无效');
      const replyCount = Math.max(0, Number(data.children?.[id] ?? row.nb_children) || 0);
      let replies = [];
      if (row.replies && Array.isArray(row.replies.ids) && row.replies.ids.length) {
        const ids = row.replies.ids.map(String), end = ids.indexOf(String(row.replies.id_post_end));
        if (end < 0 || ids.some(value => !/^\d{1,40}$/.test(value)) || new Set(ids).size !== ids.length) throw Park.error('PARSE', '评论数据无效');
        replies = this.threadComments(row.replies, ids.slice(0, end + 1), id, depth + 1);
      }
      return {id, parentId, author: {name: String(row.name || ''),
        url: Park.comments.url(row.url, this.BASE), avatar: Park.comments.url(row.pic, this.BASE)},
        body, date: typeof row.date === 'string' ? row.date : undefined,
        likes: Math.max(0, Number(row.votes?.nb) || 0), replyCount, replies,
        repliesAvailable: replyCount > replies.length};
    }).filter(Boolean);
  },
  async comments(value, req = {}) {
    const work = this.validId(value), parent = req.parentId == null ? '0' : String(req.parentId);
    const sort = req.sort && req.sort !== 'default' ? String(req.sort) : 'top';
    let page = Math.max(1, Math.floor(Number(req.page) || 1)), cursor = null;
    if (!['top', 'new'].includes(sort) || !/^\d{1,40}$/.test(parent) || !Number.isSafeInteger(page)) throw Park.error('CONFIG', '评论参数无效');
    if (req.cursor != null) {
      try { cursor = JSON.parse(req.cursor); } catch (_) { throw Park.error('CONFIG', '评论参数无效'); }
      if (!cursor || cursor.work !== work || cursor.sort !== sort || cursor.parent !== parent ||
          !/^\d{1,40}$/.test(cursor.after) || !Array.isArray(cursor.loaded) || !cursor.loaded.length ||
          cursor.loaded.some(id => typeof id !== 'string' || !/^\d{1,40}$/.test(id)) ||
          new Set(cursor.loaded).size !== cursor.loaded.length || cursor.loaded[cursor.loaded.length - 1] !== cursor.after) throw Park.error('CONFIG', '评论参数无效');
    } else if (page > 1) throw Park.error('CONFIG', '评论参数无效');
    const url = this.BASE + '/' + work, {html} = await this.getPage(url);
    const internal = /["']id_video["']\s*:\s*(\d+)/.exec(html)?.[1];
    if (!internal) throw Park.error('PARSE', '评论数据无效');
    const fetchPage = async state => {
      const response = this.http.ensureOk(await this.http.post(this.BASE + '/threads/video-comments/get-posts/' + sort + '/' + internal + '/' + parent + '/' + (state?.after || '0'), {
        form: {loaded_ids: state?.loaded.join(',') || '', load_all: 0}, headers: {Referer: url, 'X-Requested-With': 'XMLHttpRequest'},
      }));
      let data; try { data = response.json(); } catch (_) { throw Park.error('PARSE', '评论数据无效'); }
      const posts = data?.posts;
      if (data?.result !== true || !Array.isArray(posts?.ids) || !posts.posts || typeof posts.posts !== 'object' ||
          posts.ids.some(id => typeof id !== 'string' || !/^\d{1,40}$/.test(id)) || new Set(posts.ids).size !== posts.ids.length ||
          !Number.isInteger(posts.nb_after) || posts.nb_after < 0) throw Park.error('PARSE', '评论数据无效');
      return posts;
    };
    let data = await fetchPage(cursor), reset = false;
    // 原站返回完整顺序快照，但只填充未载入的正文；顺序改变时重拉首批。
    if (cursor && cursor.loaded.some((id, index) => data.ids[index] !== id)) {
      cursor = null; page = 1; reset = true; data = await fetchPage(null);
    }
    const end = data.ids.indexOf(String(data.id_post_end));
    if (data.ids.length && end < 0) throw Park.error('PARSE', '评论数据无效');
    const loaded = data.ids.slice(0, end + 1), previous = new Set(cursor?.loaded || []);
    const fresh = loaded.filter(id => !previous.has(id)), items = this.threadComments(data, fresh, parent === '0' ? undefined : parent);
    const hasNext = data.nb_after > 0 && fresh.length > 0;
    const next = hasNext ? JSON.stringify({work, sort, parent, after: data.id_post_end, loaded}) : null;
    if (next && next.length > 65536) throw Park.error('PARSE', '评论数据无效');
    return {items, page, reset, hasNext, cursor: next, total: Number.isFinite(Number(data.nb_posts_total)) ? Number(data.nb_posts_total) : undefined,
      sorts: [{value: 'top', label: '热门'}, {value: 'new', label: '最新'}]};
  },
  async detail(id) {
    id = this.validId(id);
    const url = this.BASE + '/' + id, {html, doc} = await this.getPage(url);
    const title = doc.querySelector('meta[property="og:title"]')?.getAttribute('content'), cover = doc.querySelector('meta[property="og:image"]')?.getAttribute('content');
    if (!title || !cover) throw Park.error('PARSE', '成人视频详情解析失败');
    const tags = [], seen = new Set();
    for (const a of doc.querySelectorAll('a[href^="/tags/"]')) {
      const tag = a.getAttribute('href'), name = Park.html.text(a);
      if (name && /^\/tags\/[a-z0-9_-]+\/?$/i.test(tag) && !seen.has(tag)) { seen.add(tag); tags.push({name, keyword: '', filters: {tag}}); }
    }
    return {id, title, cover, coverAspect: 16/9, url, duration: Park.html.text(doc.querySelector('h2.page-title .duration')),
      description: '', authors: [], tags: tags.length ? [{namespace: 'tag', label: '标签', tags}] : [], related: this.related(html, id)};
  },
  async videos(id) {
    const referer = this.BASE + '/' + this.validId(id), {html} = await this.getPage(referer);
    const videos = [], seen = new Set();
    for (const [method, label] of [['setVideoUrlHigh', '高清'], ['setVideoUrlLow', '标清']]) {
      const match = new RegExp('html5player\\.' + method + '\\([\'"]([^\'"\\s]+)[\'"]\\)').exec(html);
      const url = match && this.mediaUrl(match[1].replace(/\\\//g, '/'));
      if (url && !seen.has(url)) { seen.add(url); videos.push({quality: 0, label, url, preferred: videos.length === 0, headers: {Referer: referer}}); }
    }
    if (!videos.length) throw Park.error('UNSUPPORTED', '此影片没有可用的 MP4 清晰度');
    return videos;
  },
});

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"}]});
