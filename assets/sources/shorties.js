/* 只解析 Shorties 的 JSON；请求令牌仅保存在源实例内存。 */
Park.register({
  i18n: {
    "zh-Hant": {"竖屏短视频推荐，上下滑动连续播放": "直式短影片推薦，上下滑動連續播放", "请刷新短视频列表": "請重新整理短影片清單"},
    "ja": {"竖屏短视频推荐，上下滑动连续播放": "縦型動画のおすすめを上下スワイプで連続再生", "请刷新短视频列表": "ショート動画一覧を更新してください"},
    "ko": {"竖屏短视频推荐，上下滑动连续播放": "위아래로 넘기며 연속 재생하는 세로 동영상 추천", "请刷新短视频列表": "짧은 동영상 목록을 새로고침하세요"},
    "en": {"竖屏短视频推荐，上下滑动连续播放": "Vertical video recommendations with continuous swipe playback", "请刷新短视频列表": "Refresh the short video feed"},
    "es": {"竖屏短视频推荐，上下滑动连续播放": "Recomendaciones de vídeos verticales con reproducción continua al deslizar", "请刷新短视频列表": "Actualiza la lista de vídeos cortos"},
    "ru": {"竖屏短视频推荐，上下滑动连续播放": "Рекомендации вертикальных видео с непрерывным просмотром свайпами", "请刷新短视频列表": "Обновите ленту коротких видео"},
    "ar": {"竖屏短视频推荐，上下滑动连续播放": "اقتراحات مقاطع عمودية مع تشغيل متواصل بالسحب لأعلى وأسفل", "请刷新短视频列表": "حدّث قائمة المقاطع القصيرة"},
  },
  key: 'shorties', name: 'Pornhub Shorties', version: '0.0.7', type: 'video', category: 'shortvideo',
  color: '#FF9900', description: '竖屏短视频推荐，上下滑动连续播放', language: 'en',
  homepage: 'https://www.pornhub.com/shorties', domains: ['pornhub.com'],
  network: {mode: 'auto', origin: 'https://www.pornhub.com', vpnHint: true},
  // CDN 按 Accept 返回 AVIF；显式请求已在 Android 解码验证的 JPEG。
  imageHeaders: {Referer: 'https://www.pornhub.com/', Accept: 'image/jpeg'},
  media: {mode: 'native', origin: 'https://www.pornhub.com', domains: ['phncdn.com']},
  linkPatterns: ['pornhub\\.com/shorties/([a-z0-9]{5,64})(?:[/?#]|$)'],
  idPattern: '^[a-z0-9]{5,64}$', defaultFeed: 'recommend', feeds: [{key: 'recommend', label: '推荐'}],
  settings: [{key: 'quality', type: 'select', label: '默认清晰度', default: '720', options: [
    {value: '1080', label: '1080P'}, {value: '720', label: '720P'}, {value: '480', label: '480P'}]}],
  BASE: 'https://www.pornhub.com', sessions: new Map(), nextSession: 0,
  validId(value) {
    const id = String(value);
    if (!/^[a-z0-9]{5,64}$/.test(id)) throw Park.error('NOT_FOUND', '影片编号无效');
    return id;
  },
  async page(path, options = {}) {
    const r = await this.http.get(this.BASE + path, {timeout: 30000, ...options});
    if (r.status === 404) throw Park.error('NOT_FOUND', '影片不存在');
    if (!r.ok) throw Park.error('HTTP', '短视频请求失败', {status: r.status, url: r.url || this.BASE + path});
    const u = Park.url.response(this, r, this.BASE + path);
    if (!u.pathname.startsWith('/shorties')) throw Park.error('BLOCKED', '访问受限');
    if (r.body.length > 4 * 1024 * 1024) throw Park.error('PARSE', '短视频数据解析失败');
    return r.body;
  },
  data(html) {
    const m = /JSON_SHORTIES\s*=\s*(?:insertAfterNthPosition\()?\s*(\[)/.exec(html);
    if (!m) throw Park.error('PARSE', '短视频数据解析失败');
    const start = m.index + m[0].length - 1;
    let depth = 0, quoted = false, escaped = false;
    for (let i = start; i < html.length; i++) {
      const c = html[i];
      if (quoted) { if (escaped) escaped = false; else if (c === '\\') escaped = true; else if (c === '"') quoted = false; }
      else if (c === '"') quoted = true;
      else if (c === '[') depth++;
      else if (c === ']' && --depth === 0) {
        try { return JSON.parse(html.slice(start, i + 1)); } catch (_) { break; }
      }
    }
    throw Park.error('PARSE', '短视频数据解析失败');
  },
  item(v) {
    if (!v || !/^[a-z0-9]{5,64}$/.test(v.vkey || '') || !v.videoTitle) return null;
    const cover = [v.largePreviewUrl, v.imageUrl].find(u => typeof u === 'string' && /^https:\/\//.test(u) && !/blank\.gif/.test(u));
    if (!cover) return null;
    return {id: v.vkey, title: v.videoTitle, cover, coverAspect: 9/16,
      url: this.BASE + '/shorties/' + v.vkey, likes: Number(v.likeNumber) || null, subtitle: v.name || ''};
  },
  cursor(seed, offset, session, batch) {
    if (!Number.isSafeInteger(seed) || seed < 0 || !Number.isSafeInteger(offset) || offset < 0
      || !Number.isSafeInteger(session) || session < 1
      || !Number.isSafeInteger(batch) || batch < 1) throw Park.error('PARSE', '短视频分页数据无效');
    // 推荐流会在同一 seed/offset 下返回不同批次，批次号标识应用中的分页进度。
    return JSON.stringify({seed, offset, session, batch});
  },
  async feed(key, req = {}) {
    if (key !== 'recommend') throw Park.error('CONFIG', '未知视频列表');
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    if (!req.cursor) {
      const html = await this.page('/shorties');
      const doc = Park.html.parse(html), token = doc.querySelector('#shorties')?.getAttribute('data-token');
      const seed = Number(/ddSeed\s*=\s*(\d+)/.exec(html)?.[1]);
      const offset = Number(/ddOffset\s*=\s*(\d+)/.exec(html)?.[1]);
      if (!token) throw Park.error('PARSE', '短视频分页数据无效');
      const session = ++this.nextSession;
      this.sessions.set(session, token);
      while (this.sessions.size > 8) this.sessions.delete(this.sessions.keys().next().value);
      return {items: this.data(html).map(v => this.item(v)).filter(Boolean), page, hasNext: true, cursor: this.cursor(seed, offset, session, 1)};
    }
    let cursor;
    try { cursor = JSON.parse(req.cursor); } catch (_) { throw Park.error('CONFIG', '短视频分页数据无效'); }
    this.cursor(cursor.seed, cursor.offset, cursor.session, cursor.batch);
    const token = this.sessions.get(cursor.session);
    if (!token) throw Park.error('CONFIG', '请刷新短视频列表');
    const html = await this.page('/shorties/get', {params: {seed: cursor.seed, offset: cursor.offset, token, orientation: 'straight'},
      headers: {'X-Request-Token': token, Accept: 'application/json', Referer: this.BASE + '/shorties'}});
    let data;
    try { data = JSON.parse(html); } catch (_) { throw Park.error('PARSE', '短视频数据解析失败'); }
    if (!Array.isArray(data.videos)) throw Park.error('PARSE', '短视频数据解析失败');
    const hasNext = !data.isEmpty && data.videos.length > 0;
    return {items: data.videos.map(v => this.item(v)).filter(Boolean), page, hasNext,
      cursor: hasNext ? this.cursor(Number(data.seed), Number(data.offset), cursor.session, cursor.batch + 1) : undefined};
  },
  async video(id) {
    id = this.validId(id);
    const entries = this.data(await this.page('/shorties/' + id));
    const v = entries.find(v => v && v.vkey === id);
    if (!v) throw Park.error('NOT_FOUND', '影片不存在');
    return v;
  },
  async detail(id) { return {...this.item(await this.video(id)), tags: [], chapters: null}; },
  mediaUrl(value) { return Park.url.parse(value, this.BASE, this.media.domains)?.href || ''; },
  async videos(id) {
    const v = await this.video(id), videos = [], seen = new Set();
    for (const m of v.mediaDefinitions || []) {
      const url = m.format === 'hls' && this.mediaUrl(m.videoUrl), quality = Number(m.quality);
      if (!url || !Number.isInteger(quality) || quality < 144 || quality > 4320 || seen.has(url)) continue;
      seen.add(url); videos.push({quality, label: quality + 'P', format: 'hls', url, headers: {Referer: this.BASE + '/shorties'}});
    }
    if (!videos.length) throw Park.error('UNSUPPORTED', '此影片暂无可用播放地址');
    videos.sort((a, b) => b.quality - a.quality);
    (videos.find(v => v.quality <= (Number(this.config.quality) || 720)) || videos[videos.length - 1]).preferred = true;
    return videos;
  },
});

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"}]});
