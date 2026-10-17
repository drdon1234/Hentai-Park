/* 页面与 API 分别使用自己的同源浏览器会话，媒体走原生 MP4。 */
Park.register({
  i18n: {
    "zh-Hant": {"竖屏短视频推荐，支持连续播放和搜索": "直式短影片推薦，支援連續播放和搜尋"},
    "ja": {"竖屏短视频推荐，支持连续播放和搜索": "連続再生と検索に対応する縦型動画のおすすめ"},
    "ko": {"竖屏短视频推荐，支持连续播放和搜索": "연속 재생과 검색을 지원하는 세로 동영상 추천"},
    "en": {"竖屏短视频推荐，支持连续播放和搜索": "Vertical video recommendations with continuous playback and search"},
    "es": {"竖屏短视频推荐，支持连续播放和搜索": "Recomendaciones de vídeos verticales con reproducción continua y búsqueda"},
    "ru": {"竖屏短视频推荐，支持连续播放和搜索": "Рекомендации вертикальных видео с непрерывным просмотром и поиском"},
    "ar": {"竖屏短视频推荐，支持连续播放和搜索": "اقتراحات مقاطع عمودية تدعم التشغيل المتواصل والبحث"},
  },
  key: 'tikporn', name: 'Tik.porn', version: '0.0.4', type: 'video', category: 'shortvideo',
  color: '#FF427B', description: '竖屏短视频推荐，支持连续播放和搜索', language: 'en',
  homepage: 'https://tik.porn/', domains: ['tik.porn'],
  network: {mode: 'browser', origin: 'https://tik.porn', vpnHint: true},
  imageHeaders: {Referer: 'https://image-cdn.tik.porn/'},
  imageNetwork: {mode: 'browser', origin: 'https://image-cdn.tik.porn', domains: ['image-cdn.tik.porn']},
  media: {mode: 'native', origin: 'https://tik.porn', domains: ['video-cdn.tik.porn']},
  idPattern: '^[1-9]\\d{0,11}$', linkPatterns: ['tik\\.porn/video/([1-9]\\d{0,11})(?:[/?#]|$)'],
  defaultFeed: 'recommend', feeds: [{key: 'recommend', label: '推荐'}], searchHint: '搜索作品名或标签',
  BASE: 'https://tik.porn', API: 'https://apiv2.tik.porn',
  validId(value) {
    const id = String(value);
    if (!/^[1-9]\d{0,11}$/.test(id)) throw Park.error('NOT_FOUND', '影片编号无效');
    return id;
  },
  async page(path) {
    const r = await this.http.get(this.BASE + path, {origin: this.BASE, timeout: 30000});
    if (r.status === 404) throw Park.error('NOT_FOUND', '影片不存在');
    if (!r.ok) throw Park.error('HTTP', '短视频请求失败');
    const u = new URL(r.url || this.BASE + path);
    if (u.origin !== this.BASE || u.username || u.password || u.hash) throw Park.error('BLOCKED', '访问受限');
    if (r.body.length > 4 * 1024 * 1024) throw Park.error('PARSE', '短视频数据解析失败');
    const text = Park.html.parse(r.body).querySelector('#__NEXT_DATA__')?.textContent;
    try {
      const p = JSON.parse(text).props.pageProps;
      if (!p || typeof p !== 'object') throw new Error();
      return p;
    } catch (_) { throw Park.error('PARSE', '短视频数据解析失败'); }
  },
  item(v) {
    const id = String(v?.id ?? v?.video_id ?? '');
    if (!/^[1-9]\d{0,11}$/.test(id)) return null;
    const title = v.metadata?.title || v.action_name || v.texts?.title;
    const cover = v.poster || v.poster_url;
    if (!title || typeof cover !== 'string') return null;
    let u;
    try { u = new URL(cover); } catch (_) { return null; }
    if (u.protocol !== 'https:' || u.hostname !== 'image-cdn.tik.porn' || u.port || u.username || u.password || u.hash) return null;
    return {id, title, cover: u.href, coverAspect: 9/16, url: this.BASE + '/video/' + id,
      duration: v.duration ? String(v.duration) : undefined, likes: Number(v.likes ?? v.like_count) || null,
      views: Number(v.views ?? v.view_count) || null};
  },
  cursor(ids, recommId) {
    return JSON.stringify({ids: [...new Set(ids)].slice(-200), recommId: typeof recommId === 'string' && recommId.length <= 128 ? recommId : null});
  },
  async feed(key, req = {}) {
    if (key !== 'recommend') throw Park.error('CONFIG', '未知视频列表');
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    if (!req.cursor) {
      const p = await this.page('/'), videos = p.videos?.data;
      if (!Array.isArray(videos)) throw Park.error('PARSE', '短视频数据解析失败');
      const items = videos.map(v => this.item(v)).filter(Boolean);
      if (!items.length) throw Park.error('PARSE', '短视频数据解析失败');
      const first = {items, page, hasNext: true, cursor: this.cursor(items.map(v => v.id), videos[0]?.recommId)};
      // SSR 只负责首个可播放作品；首屏还需要与原站一致地读取推荐批次。
      if (items.length >= 10) return first;
      const next = await this.feed(key, {page, cursor: first.cursor});
      return {...next, page, items: [...new Map([...items, ...next.items].map(v => [v.id, v])).values()]};
    }
    let c;
    try { c = JSON.parse(req.cursor); } catch (_) { throw Park.error('CONFIG', '短视频分页数据无效'); }
    if (!c || !Array.isArray(c.ids) || !c.ids.length || c.ids.length > 200
      || c.ids.some(id => typeof id !== 'string' || !/^[1-9]\d{0,11}$/.test(id))
      || c.recommId != null && (typeof c.recommId !== 'string' || c.recommId.length > 128)) throw Park.error('CONFIG', '短视频分页数据无效');
    const r = await this.http.post(this.API + '/getnextvideos', {
      origin: this.API, timeout: 30000,
      json: {amount: 10, filter: c.ids.map(Number), sfw_mode: 0, forcerand: false, first_chunk: false, recomm_id: c.recommId || null},
    });
    if (!r.ok) throw Park.error('HTTP', '短视频请求失败');
    if (new URL(r.url || this.API + '/getnextvideos').origin !== this.API || r.body.length > 4 * 1024 * 1024) throw Park.error('PARSE', '短视频数据解析失败');
    let data;
    try { data = JSON.parse(r.body); } catch (_) { throw Park.error('PARSE', '短视频数据解析失败'); }
    if (data.code !== 200 || !Array.isArray(data.data)) throw Park.error('PARSE', '短视频数据解析失败');
    const items = data.data.map(v => this.item(v)).filter(Boolean), hasNext = data.data.length > 0;
    return {items, page, hasNext, cursor: hasNext ? this.cursor([...c.ids, ...items.map(i => i.id)], data.extradata?.recommId) : undefined};
  },
  async search(req = {}) {
    const keyword = String(req.keyword || '').trim(), page = Math.max(1, Math.floor(Number(req.page) || 1));
    if (!keyword) return {items: [], page: 1, hasNext: false};
    const p = await this.page('/?s=' + encodeURIComponent(keyword) + '&page=' + page), data = p.initialVideoResults;
    if (!data || !Array.isArray(data.data) || !data.pagination || Number(data.pagination.page) !== page) throw Park.error('PARSE', '短视频数据解析失败');
    return {items: data.data.map(v => this.item(v)).filter(Boolean), page,
      hasNext: data.pagination.hasMore === true, totalPages: Number(data.pagination.totalPages) || undefined};
  },
  async video(id) {
    id = this.validId(id);
    const p = await this.page('/video/' + id), video = p.firstVideo;
    if (!video || String(video.id) !== id) throw Park.error('NOT_FOUND', '影片不存在');
    return video;
  },
  async detail(id) { return {...this.item(await this.video(id)), tags: [], chapters: null}; },
  mediaUrl(value) {
    try {
      const u = new URL(value);
      return u.protocol === 'https:' && u.hostname === 'video-cdn.tik.porn' && !u.port && !u.username && !u.password && !u.hash
        && /\.mp4$/i.test(u.pathname) ? u.href : null;
    } catch (_) { return null; }
  },
  async videos(id) {
    const v = await this.video(id), result = [];
    for (const s of [v.source, ...(v.sources || [])]) {
      const url = s?.type === 'video/mp4' && this.mediaUrl(s.src);
      if (url && !result.some(s => s.url === url)) result.push({url, quality: 0, label: '原画', format: 'mp4',
        headers: {Referer: this.BASE + '/'}, preferred: true});
    }
    if (!result.length) throw Park.error('UNSUPPORTED', '此影片暂无可用播放地址');
    return result;
  },
});

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"}]});
