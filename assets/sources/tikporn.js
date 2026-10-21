/* 读取站点页面提供的推荐数据，媒体走原生传输。 */
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
  key: 'tikporn', name: 'Tik.porn', version: '0.0.6', type: 'video', category: 'shortvideo',
  color: '#FF427B', description: '竖屏短视频推荐，支持连续播放和搜索', language: 'en',
  homepage: 'https://tik.porn/', domains: ['tik.porn'],
  network: {mode: 'browser', origin: 'https://tik.porn', vpnHint: true},
  imageHeaders: {Referer: 'https://image-cdn.tik.porn/'},
  imageNetwork: {mode: 'browser', origin: 'https://image-cdn.tik.porn', domains: ['image-cdn.tik.porn']},
  media: {mode: 'native', origin: 'https://tik.porn', domains: ['video-cdn.tik.porn']},
  idPattern: '^[1-9]\\d{0,11}$', linkPatterns: ['tik\\.porn/video/([1-9]\\d{0,11})(?:[/?#]|$)'],
  defaultFeed: 'recommend', feeds: [{key: 'recommend', label: '推荐'}], searchHint: '搜索作品名或标签',
  BASE: 'https://tik.porn',
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
  cursor(ids, next) {
    return JSON.stringify({ids: [...new Set(ids)].slice(-200), next: this.validId(next)});
  },
  async feed(key, req = {}) {
    if (key !== 'recommend') throw Park.error('CONFIG', '未知视频列表');
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    if (!req.cursor) {
      const p = await this.page('/'), videos = p.videos?.data;
      if (!Array.isArray(videos)) throw Park.error('PARSE', '短视频数据解析失败');
      const rows = [...videos, ...(Array.isArray(p.initialRelatedVideos?.data) ? p.initialRelatedVideos.data : [])];
      const items = [...new Map(rows.map(v => this.item(v)).filter(Boolean).map(v => [v.id, v])).values()];
      if (!items.length) throw Park.error('PARSE', '短视频数据解析失败');
      return {items, page, hasNext: true, cursor: this.cursor(items.map(v => v.id), items[items.length - 1].id)};
    }
    let c;
    try { c = JSON.parse(req.cursor); } catch (_) { throw Park.error('CONFIG', '短视频分页数据无效'); }
    if (!c || !Array.isArray(c.ids) || !c.ids.length || c.ids.length > 200
      || c.ids.some(id => typeof id !== 'string' || !/^[1-9]\d{0,11}$/.test(id))
      || typeof c.next !== 'string' || !c.ids.includes(c.next)) throw Park.error('CONFIG', '短视频分页数据无效');
    const p = await this.page('/video/' + this.validId(c.next)), rows = p.initialRelatedVideos?.data;
    if (!Array.isArray(rows)) throw Park.error('PARSE', '短视频数据解析失败');
    const items = [...new Map(rows.map(v => this.item(v)).filter(v => v && !c.ids.includes(v.id)).map(v => [v.id, v])).values()];
    const hasNext = items.length > 0;
    return {items, page, hasNext, cursor: hasNext ? this.cursor([...c.ids, ...items.map(i => i.id)], items[items.length - 1].id) : undefined};
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
  async detail(id) {
    const video = await this.video(id), seen = new Set(), tags = [];
    for (const tag of [video.action, ...(Array.isArray(video.tags) ? video.tags : [])]) {
      const name = typeof tag?.name === 'string' ? tag.name.trim() : '';
      if (!name || name.length > 240 || seen.has(name.toLowerCase())) continue;
      seen.add(name.toLowerCase());
      tags.push({name, keyword: name});
    }
    return {...this.item(video), tags: tags.length ? [{namespace: 'tag', label: '标签', tags}] : [], chapters: null};
  },
  mediaUrl(value) {
    try {
      const u = new URL(value);
      return u.protocol === 'https:' && u.hostname === 'video-cdn.tik.porn' && !u.port && !u.username && !u.password && !u.hash
        && /\.(?:mp4|m3u8)$/i.test(u.pathname) ? u.href : null;
    } catch (_) { return null; }
  },
  async videos(id) {
    const v = await this.video(id), result = [];
    for (const s of [v.source, ...(Array.isArray(v.sources) ? v.sources : [])]) {
      const url = this.mediaUrl(s?.src);
      if (!url || result.some(s => s.url === url)) continue;
      const format = /\.m3u8$/i.test(new URL(url).pathname) ? 'hls' : 'mp4';
      result.push({url, quality: 0, label: '原画', format,
        headers: {Referer: this.BASE + '/'}, preferred: result.length === 0});
    }
    if (!result.length) throw Park.error('UNSUPPORTED', '此影片暂无可用播放地址');
    return result;
  },
});

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"}]});
