Park.register({
  i18n: {
    'zh-Hant': {'CamwhoresBay 亞洲錄播': 'CamwhoresBay 亞洲錄播', '韓國': '韓國', '日本': '日本', '中國': '中國', '錄播請求失敗': '錄播請求失敗', '錄播資料無效': '錄播資料無效', '錄播不存在': '錄播不存在', '錄播暫不可用': '錄播暫不可用'},
    ja: {'CamwhoresBay 亚洲录播': 'CamwhoresBay アジア録画', '韩国': '韓国', '日本': '日本', '中国': '中国', '录播请求失败': '録画の取得に失敗しました', '录播数据无效': '録画データが無効です', '录播不存在': '録画が見つかりません', '录播暂不可用': '録画は現在利用できません'},
    ko: {'CamwhoresBay 亚洲录播': 'CamwhoresBay 아시아 녹화', '韩国': '한국', '日本': '일본', '中国': '중국', '录播请求失败': '녹화 요청에 실패했습니다', '录播数据无效': '녹화 데이터가 올바르지 않습니다', '录播不存在': '녹화를 찾을 수 없습니다', '录播暂不可用': '현재 녹화를 사용할 수 없습니다'},
    en: {'CamwhoresBay 亚洲录播': 'CamwhoresBay Asian Recordings', '韩国': 'Korea', '日本': 'Japan', '中国': 'China', '录播请求失败': 'Recording request failed', '录播数据无效': 'Invalid recording data', '录播不存在': 'Recording not found', '录播暂不可用': 'Recording is currently unavailable'},
    es: {'CamwhoresBay 亚洲录播': 'Grabaciones asiáticas de CamwhoresBay', '韩国': 'Corea', '日本': 'Japón', '中国': 'China', '录播请求失败': 'Error al solicitar la grabación', '录播数据无效': 'Datos de grabación no válidos', '录播不存在': 'Grabación no encontrada', '录播暂不可用': 'Grabación no disponible'},
    ru: {'CamwhoresBay 亚洲录播': 'Азиатские записи CamwhoresBay', '韩国': 'Корея', '日本': 'Япония', '中国': 'Китай', '录播请求失败': 'Ошибка запроса записи', '录播数据无效': 'Некорректные данные записи', '录播不存在': 'Запись не найдена', '录播暂不可用': 'Запись сейчас недоступна'},
    ar: {'CamwhoresBay 亚洲录播': 'تسجيلات CamwhoresBay الآسيوية', '韩国': 'كوريا', '日本': 'اليابان', '中国': 'الصين', '录播请求失败': 'فشل طلب التسجيل', '录播数据无效': 'بيانات التسجيل غير صالحة', '录播不存在': 'التسجيل غير موجود', '录播暂不可用': 'التسجيل غير متاح حالياً'},
  },
  key: 'camwhoresbay_recording', name: 'CamwhoresBay 亚洲录播', version: '0.0.4', minAppVersion: '0.9.2', type: 'video', category: 'recording',
  color: '#c93443', description: '韩国、日本与中国主播录播，支持搜索和 MP4 播放', language: 'en',
  homepage: 'https://www.camwhoresbay.com/', domains: ['camwhoresbay.com'],
  network: {mode: 'native', origin: 'https://www.camwhoresbay.com', vpnHint: true},
  imageHeaders: {Referer: 'https://www.camwhoresbay.com/'},
  media: {mode: 'native', origin: 'https://www.camwhoresbay.com', domains: ['camwhoresbay.com', 'cdntrex.com']},
  idPattern: '^[1-9]\\d{0,8}/[a-z0-9-]+$', linkPatterns: ['camwhoresbay\\.com/videos/(([1-9]\\d{0,8})/[a-z0-9-]+)/'],
  defaultFeed: 'korean', feeds: [{key: 'korean', label: '韩国'}, {key: 'japanese', label: '日本'}, {key: 'chinese', label: '中国'}],
  BASE: 'https://www.camwhoresbay.com',
  async text(path) {
    const r = await this.http.get(this.BASE + path, {timeout: 15000, headers: {'User-Agent': 'Mozilla/5.0', Referer: this.BASE + '/'}});
    if (!r.ok) throw Park.error('HTTP', '录播请求失败', {status: r.status});
    return r.body;
  },
  document(html) { return Park.html.parse(html); },
  card(a) {
    const img = a?.querySelector('img');
    if (!a || !img) return null;
    let url, cover;
    try {
      url = new URL(a.getAttribute('href'), this.BASE);
      cover = new URL(img.getAttribute('data-original') || img.getAttribute('data-src') || img.getAttribute('src'), this.BASE);
    } catch (_) { return null; }
    const match = url.pathname.match(/^\/videos\/([1-9]\d{0,8})\/([a-z0-9-]+)\/$/);
    if (url.hostname !== 'www.camwhoresbay.com' || !match ||
        cover.protocol !== 'https:' || cover.hostname !== 'cwb.cdntrex.com') return null;
    const id = match[1] + '/' + match[2], title = String(a.getAttribute('title') || img.getAttribute('alt') || '').trim();
    if (!title) return null;
    return {id, title, cover: cover.href, coverAspect: 16/9, url: url.href, mediaKind: 'video'};
  },
  async feed(key, req = {}) {
    if (!this.feeds.some(x => x.key === key)) throw Park.error('CONFIG', '录播数据无效');
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    return this.list('/search/' + key + '/', key, page);
  },
  async search(req = {}) {
    const keyword = String(req.keyword || '').trim().slice(0, 80);
    if (!keyword) return {items: [], page: 1, hasNext: false};
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    return this.list('/search/' + encodeURIComponent(keyword).replace(/%20/g, '+') + '/', keyword, page);
  },
  async list(path, keyword, page) {
    let requestPath = path;
    if (page > 1) {
      const params = new URLSearchParams({
        mode: 'async', function: 'get_block', block_id: 'list_videos_videos_list_search_result',
        q: keyword, category_ids: '', sort_by: '',
        from_videos: String(page).padStart(2, '0'), from_albums: String(page).padStart(2, '0'),
      });
      requestPath += '?' + params.toString();
    }
    const doc = this.document(await this.text(requestPath));
    const items = [...doc.querySelectorAll('a.thumb[href*="/videos/"]')].map(a => this.card(a)).filter(Boolean);
    if (!items.length && !doc.querySelector('.pagination')) throw Park.error('PARSE', '录播数据无效');
    const hasNext = !![...doc.querySelectorAll('.pagination a')].find(a => /next/i.test(a.textContent));
    return {items, page, hasNext};
  },
  path(value) {
    const id = String(value || '');
    if (!/^[1-9]\d{0,8}\/[a-z0-9-]+$/.test(id)) throw Park.error('NOT_FOUND', '录播不存在');
    return '/videos/' + id + '/';
  },
  async detail(value) {
    const path = this.path(value);
    const doc = this.document(await this.text(path));
    const title = String(doc.querySelector('h1')?.textContent || '').trim();
    const poster = doc.querySelector('meta[property="og:image"]')?.getAttribute('content') ||
      doc.querySelector('meta[itemprop="thumbnailUrl"]')?.getAttribute('content');
    let cover;
    try { cover = new URL(poster, this.BASE); } catch (_) {}
    if (!title || !cover || cover.protocol !== 'https:' || cover.hostname !== 'cwb.cdntrex.com') throw Park.error('NOT_FOUND', '录播不存在');
    return {id: value, title, cover: cover.href, coverAspect: 16/9, url: this.BASE + path, mediaKind: 'video', chapters: null};
  },
  async videos(value) {
    const path = this.path(value);
    const html = await this.text(path);
    const match = html.match(/video_url:\s*'([^']+)'/);
    if (!match) throw Park.error('UNSUPPORTED', '录播暂不可用');
    let url; try { url = new URL(match[1]); } catch (_) { throw Park.error('PARSE', '录播数据无效'); }
    if (url.protocol !== 'https:' || url.hostname !== 'www.camwhoresbay.com' || !/^\/get_file\/\d+\/[a-f0-9]+\/\d+\/\d+\/[^/]+\.mp4\/$/i.test(url.pathname)) {
      throw Park.error('UNSUPPORTED', '录播暂不可用');
    }
    return [{url: url.href, format: 'mp4', label: '原画', preferred: true, headers: {Referer: this.BASE + '/'}}];
  },
});
