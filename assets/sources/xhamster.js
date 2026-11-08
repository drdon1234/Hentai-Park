/* xHamster 的页面数据同时覆盖桌面和移动端；播放器地址只做静态解码。 */
Park.register({
  i18n: {
    'zh-Hant': {'综合成人视频，支持推荐、搜索和多清晰度播放': '綜合成人影片，支援推薦、搜尋和多畫質播放'},
    ja: {'综合成人视频，支持推荐、搜索和多清晰度播放': 'おすすめ・検索・複数画質再生に対応した成人向け動画'},
    ko: {'综合成人视频，支持推荐、搜索和多清晰度播放': '추천, 검색 및 다양한 화질 재생을 지원하는 성인 동영상'},
    en: {'综合成人视频，支持推荐、搜索和多清晰度播放': 'Adult videos with recommendations, search and multiple playback qualities'},
    es: {'综合成人视频，支持推荐、搜索和多清晰度播放': 'Vídeos para adultos con recomendaciones, búsqueda y varias calidades'},
    ru: {'综合成人视频，支持推荐、搜索和多清晰度播放': 'Видео для взрослых с рекомендациями, поиском и выбором качества'},
    ar: {'综合成人视频，支持推荐、搜索和多清晰度播放': 'فيديوهات للبالغين مع توصيات وبحث وخيارات جودة متعددة'},
  },
  key: 'xhamster', name: 'xHamster', version: '0.0.1', minAppVersion: '0.9.2',
  type: 'video', category: 'adult', language: 'en', color: '#F15B2A',
  homepage: 'https://xhamster.com', description: '综合成人视频，支持推荐、搜索和多清晰度播放',
  domains: ['xhamster.com'], network: {mode: 'auto', vpnHint: true},
  imageHeaders: {Referer: 'https://xhamster.com/'},
  media: {mode: 'native', scope: 'session', origin: 'https://xhamster.com', domains: ['xhcdn.com']},
  linkPatterns: ['\\b(?:[a-z0-9-]+\\.)*xhamster\\.com/videos/([A-Za-z0-9_%.-]+-[A-Za-z0-9]+)(?:/)?(?:[?#]|$)'],
  idPattern: '^[A-Za-z0-9][A-Za-z0-9_%.-]*-[A-Za-z0-9]{1,32}$',
  defaultFeed: 'recommended', feeds: [{key: 'recommended', label: '推荐'}, {key: 'latest', label: '最新'}],
  searchHint: '搜索作品名或标签', BASE: 'https://xhamster.com',

  validId(value) {
    const id = String(value || '');
    if (id.length > 500 || !/^[A-Za-z0-9][A-Za-z0-9_%.-]*-[A-Za-z0-9]{1,32}$/.test(id)) {
      throw Park.error('NOT_FOUND', '影片编号无效');
    }
    let decoded;
    try { decoded = decodeURIComponent(id); } catch (_) { throw Park.error('NOT_FOUND', '影片编号无效'); }
    if (/[\\/\x00-\x1f\x7f]/.test(decoded)) throw Park.error('NOT_FOUND', '影片编号无效');
    return id;
  },
  itemId(value) {
    const url = Park.url.site(this, value);
    if (!url) return '';
    const path = url.pathname.replace(/\/$/, '');
    if (!path.startsWith('/videos/')) return '';
    try { return this.validId(path.slice('/videos/'.length)); } catch (_) { return ''; }
  },
  publicUrl(value) {
    if (typeof value !== 'string' || !value.trim()) return '';
    try {
      const url = new URL(value, this.BASE);
      return Park.url.parse(url.href, this.BASE, [url.hostname])?.href || '';
    } catch (_) { return ''; }
  },
  duration(value) {
    const seconds = Math.floor(Number(value));
    if (!Number.isFinite(seconds) || seconds <= 0) return '';
    const pad = n => String(n).padStart(2, '0');
    return seconds >= 3600 ? Math.floor(seconds / 3600) + ':' + pad(Math.floor(seconds / 60) % 60) + ':' + pad(seconds % 60)
      : Math.floor(seconds / 60) + ':' + pad(seconds % 60);
  },
  async page(url) {
    if (!Park.url.site(this, url)) throw Park.error('CONFIG', '视频列表地址无效');
    const response = await this.http.get(url, {timeout: 30000});
    if (response.status === 404) throw Park.error('NOT_FOUND', '影片不存在');
    if (!response.ok) throw Park.error('HTTP', '成人视频请求失败', {status: response.status});
    const finalUrl = Park.url.response(this, response, url);
    if (response.body.length > 4 * 1024 * 1024) throw Park.error('PARSE', '成人视频详情解析失败');
    const doc = Park.html.parse(response.body);
    const script = doc.querySelector('#initials-script')?.textContent || '';
    const match = /^\s*window\.initials\s*=\s*([\s\S]+?)\s*;\s*$/.exec(script);
    let data;
    try { data = JSON.parse(match?.[1] || ''); } catch (_) { throw Park.error('PARSE', '成人视频详情解析失败'); }
    if (!data || typeof data !== 'object' || Array.isArray(data)) throw Park.error('PARSE', '成人视频详情解析失败');
    return {data, url: finalUrl.href};
  },
  items(rows) {
    const items = [], seen = new Set();
    for (const row of rows) {
      if (!row || row.videoType !== 'video') continue;
      const id = this.itemId(row.pageURL), title = typeof row.title === 'string' ? row.title.trim() : '';
      if (!id || !title || seen.has(id)) continue;
      seen.add(id);
      items.push({id, title, cover: this.publicUrl(row.thumbURL || row.imageURL), coverAspect: 16 / 9,
        url: this.BASE + '/videos/' + id, duration: this.duration(row.duration),
        views: Number.isFinite(row.views) && row.views >= 0 ? row.views : undefined});
    }
    if (rows.length && !items.length) throw Park.error('PARSE', '成人视频详情解析失败');
    return items;
  },
  pageNumber(value) {
    const page = value == null ? 1 : Number(value);
    if (!Number.isSafeInteger(page) || page < 1 || page > 1000000) throw Park.error('CONFIG', '筛选参数无效');
    return page;
  },
  async listing(url, page, search) {
    const {data} = await this.page(url);
    const rows = search ? data.searchResult?.videoThumbProps : data.layoutPage?.videoListProps?.videoThumbProps;
    if (!Array.isArray(rows)) throw Park.error('PARSE', '成人视频详情解析失败');
    let current, last, hasNext;
    if (search) {
      const pagination = data.pagination;
      if (!pagination && !rows.length && typeof data.searchResult?.emptyMessageProp === 'string') {
        return {items: [], page, hasNext: false};
      }
      current = Number(pagination?.active);
      last = Number(pagination?.maxPages);
      const next = Number(pagination?.next || 0);
      if (!Number.isSafeInteger(next) || (next && next !== page + 1)) throw Park.error('PARSE', '成人视频详情解析失败');
      hasNext = next === page + 1;
    } else {
      const pagination = data.layoutPage?.paginationProps || data.layout?.layoutBottomMobileProps?.paginationProps;
      current = Number(pagination?.currentPageNumber);
      last = Number(pagination?.lastPageNumber);
      hasNext = page < last;
    }
    if (!Number.isSafeInteger(current) || current !== page || !Number.isSafeInteger(last) || last < page) {
      throw Park.error('PARSE', '成人视频详情解析失败');
    }
    return {items: this.items(rows), page, hasNext};
  },
  async feed(key, req = {}) {
    if (key !== 'recommended' && key !== 'latest') throw Park.error('CONFIG', '未知列表');
    const page = this.pageNumber(req.page), path = key === 'recommended' ? '' : '/newest';
    return this.listing(this.BASE + path + (page > 1 ? '/' + page : '/'), page, false);
  },
  async search(req = {}) {
    const keyword = String(req.keyword || '').trim();
    if (!keyword) return {items: [], page: 1, hasNext: false};
    const page = this.pageNumber(req.page), query = new URLSearchParams({q: keyword, page: String(page)});
    return this.listing(this.BASE + '/search?' + query, page, true);
  },
  resolveContentLink(value) {
    try { if (new URL(value, this.BASE).hash) return null; } catch (_) { return null; }
    const url = Park.url.site(this, value);
    if (!url) return null;
    const id = this.itemId(url.href);
    return id ? {type: 'work', id} : null;
  },
  async detail(value) {
    const id = this.validId(value), url = this.BASE + '/videos/' + id, {data} = await this.page(url);
    const video = data.videoModel || {}, info = data.xplayerSettings?.videoInfo || {};
    const canonicalId = this.itemId(info.url || video.pageURL);
    if (!canonicalId || canonicalId.split('-').pop() !== id.split('-').pop()) throw Park.error('PARSE', '成人视频详情解析失败');
    const title = typeof info.title === 'string' ? info.title.trim() : String(video.title || '').trim();
    if (!title) throw Park.error('PARSE', '成人视频详情解析失败');
    const tags = [], seen = new Set();
    const tagRows = data.videoTagsComponent?.tags;
    for (const tag of Array.isArray(tagRows) ? tagRows : []) {
      const name = typeof tag?.name === 'string' ? tag.name.trim() : '';
      if ((!tag?.isTag && !tag?.isCategory) || !name || seen.has(name)) continue;
      seen.add(name); tags.push({name, keyword: name});
    }
    const author = typeof video.author?.name === 'string' ? video.author.name.trim() : '';
    const relatedRows = data.relatedVideosComponent?.videoTabInitialData?.videoListProps?.videoThumbProps;
    const related = Array.isArray(relatedRows) ? this.items(relatedRows).filter(item => item.id !== id) : [];
    return {id, title, cover: this.publicUrl(info.thumbUrl || video.thumbURL), coverAspect: 16 / 9, url,
      duration: this.duration(info.duration || video.duration), views: Number.isFinite(info.views) ? info.views : undefined,
      authors: author ? [author] : [], uploader: author,
      description: typeof video.description === 'string' ? video.description : '',
      tags: tags.length ? [{namespace: 'tag', label: '标签', tags}] : [], chapters: null, related};
  },

  // 首字节选择站点的字节流算法，随后四字节是小端种子。
  decodeHex(value) {
    if (typeof value !== 'string' || value.length < 12 || value.length > 10000 || value.length % 2 || !/^[0-9a-f]+$/i.test(value)) return '';
    const byte = index => parseInt(value.slice(index * 2, index * 2 + 2), 16);
    const algorithm = byte(0);
    let state = (byte(1) | byte(2) << 8 | byte(3) << 16 | byte(4) << 24) | 0;
    if (algorithm < 1 || algorithm > 7) return '';
    let output = '';
    for (let i = 5; i < value.length / 2; i++) {
      let n;
      if (algorithm === 1) n = state = (Math.imul(state, 1664525) + 1013904223) | 0;
      else if (algorithm === 2) {
        n = state ^ state << 13; n ^= n >>> 17; n ^= n << 5; state = n;
      } else if (algorithm === 3) {
        state = (state + 0x9e3779b9) | 0;
        n = state ^ state >>> 16; n = Math.imul(n, 0x85ebca77);
        n ^= n >>> 13; n = Math.imul(n, 0xc2b2ae3d); n ^= n >>> 16;
      } else if (algorithm === 4) {
        state = (state + 0x6d2b79f5) | 0;
        n = ((state << 7 | state >>> 25) + 0x9e3779b9) | 0;
        n ^= n >>> 11; n = Math.imul(n, 0x27d4eb2d);
      } else if (algorithm === 5) {
        n = state ^ state << 7; n ^= n >>> 9; n ^= n << 8; n = state = (n + 0xa5a5a5a5) | 0;
      } else if (algorithm === 6) {
        state = (Math.imul(state, 0x2c9277b5) + 0xac564b05) | 0;
        n = (state ^ state >>> 18) >>> (state >>> 27 & 31);
      } else {
        state = (state + 0x9e3779b9) | 0;
        n = Math.imul(state ^ state << 5, 0x7feb352d);
        n = Math.imul(n ^ n >>> 15, 0x846ca68b);
      }
      output += String.fromCharCode(byte(i) ^ (n & 255));
    }
    return output;
  },
  mediaUrl(value) {
    if (typeof value !== 'string') return '';
    let text = value;
    if (/^[0-9a-f]+$/i.test(text)) text = this.decodeHex(text);
    else {
      let url;
      try { url = new URL(text); } catch (_) { return ''; }
      const match = /^\/([0-9a-f]{12,})([\/,].+)$/.exec(url.pathname);
      if (match) {
        const prefix = this.decodeHex(match[1]);
        if (!prefix) return '';
        url.pathname = '/' + prefix + match[2]; text = url.href;
      }
    }
    try { if (new URL(text).hash) return ''; } catch (_) { return ''; }
    const safe = this.publicUrl(text);
    if (!safe) return '';
    const url = new URL(safe);
    return !url.hash && /\.(?:m3u8|mp4)$/i.test(url.pathname) ? url.href : '';
  },
  async videos(value) {
    const id = this.validId(value), referer = this.BASE + '/videos/' + id, {data} = await this.page(referer);
    const infoId = this.itemId(data.xplayerSettings?.videoInfo?.url);
    if (!infoId || infoId.split('-').pop() !== id.split('-').pop()) throw Park.error('PARSE', '媒体数据无效');
    const sources = data.xplayerSettings?.sources, result = [], seen = new Set();
    const add = (raw, quality, format, preferred = false) => {
      const url = this.mediaUrl(raw);
      if (!url || seen.has(url) || (format === 'hls') !== /\.m3u8$/i.test(new URL(url).pathname)) return;
      seen.add(url);
      result.push({url, quality, label: quality ? quality + 'P' : '原画', format, preferred, headers: {Referer: referer}});
    };
    for (const codec of ['h264', 'av1']) {
      const hls = sources?.hls?.[codec];
      if (!hls || typeof hls !== 'object') continue;
      add(hls.url, 1080, 'hls', true);
      add(hls.fallback, 1080, 'hls');
      if (result.length) break;
    }
    if (!result.length) throw Park.error('PARSE', '媒体数据无效');
    if (!result.some(item => item.preferred)) result[0].preferred = true;
    return result;
  },
});

Park.enableUpdateSubscriptions(Park.__pending, {dimensions: [
  {key: 'search', label: '搜索关键词', hint: '输入作品、作者或话题关键词'},
]});
