Park.register({
  i18n: {
  "zh-Hant": {
    "直播": "直播",
    "直播间暂无可用播放地址": "直播間暫無可用播放位址",
    "公开直播间": "公開直播間",
    "直播间不存在": "直播間不存在",
    "直播请求失败": "直播請求失敗",
    "直播数据无效": "直播資料無效",
    "未知直播列表": "未知直播列表"
  },
  "en": {
    "直播": "Live",
    "直播间暂无可用播放地址": "No playable live stream is available",
    "公开直播间": "Public live rooms",
    "直播间不存在": "Live room not found",
    "直播请求失败": "Live request failed",
    "直播数据无效": "Invalid live data",
    "未知直播列表": "Unknown live feed"
  },
  "ja": {
    "直播": "ライブ",
    "直播间暂无可用播放地址": "再生可能なライブ配信がありません",
    "公开直播间": "公開ライブ配信",
    "直播间不存在": "ライブ配信が見つかりません",
    "直播请求失败": "ライブ配信の取得に失敗しました",
    "直播数据无效": "ライブデータが無効です",
    "未知直播列表": "不明なライブ一覧"
  },
  "ko": {
    "直播": "라이브",
    "直播间暂无可用播放地址": "재생 가능한 라이브 방송이 없습니다",
    "公开直播间": "공개 라이브 방송",
    "直播间不存在": "라이브 방송을 찾을 수 없습니다",
    "直播请求失败": "라이브 요청에 실패했습니다",
    "直播数据无效": "라이브 데이터가 올바르지 않습니다",
    "未知直播列表": "알 수 없는 라이브 목록"
  },
  "es": {
    "直播": "Directo",
    "直播间暂无可用播放地址": "No hay una emisión reproducible disponible",
    "公开直播间": "Salas de emisión públicas",
    "直播间不存在": "Sala de directo no encontrada",
    "直播请求失败": "Error al solicitar el directo",
    "直播数据无效": "Datos de directo no válidos",
    "未知直播列表": "Lista de directos desconocida"
  },
  "ru": {
    "直播": "Эфир",
    "直播间暂无可用播放地址": "Нет доступного потока для воспроизведения",
    "公开直播间": "Открытые эфиры",
    "直播间不存在": "Эфир не найден",
    "直播请求失败": "Ошибка запроса эфира",
    "直播数据无效": "Некорректные данные эфира",
    "未知直播列表": "Неизвестный список эфиров"
  },
  "ar": {
    "直播": "بث مباشر",
    "直播间暂无可用播放地址": "لا يوجد بث متاح للتشغيل",
    "公开直播间": "غرف بث عامة",
    "直播间不存在": "غرفة البث غير موجودة",
    "直播请求失败": "فشل طلب البث",
    "直播数据无效": "بيانات البث غير صالحة",
    "未知直播列表": "قائمة بث غير معروفة"
  }
},
  key: 'cam4', name: 'CAM4', version: '0.0.4', type: 'video', category: 'live', language: 'en',
  color: '#ff5a5f', description: '公开直播间', homepage: 'https://www.cam4.com/',
  domains: ['cam4.com'], network: {mode: 'auto', origin: 'https://www.cam4.com', vpnHint: true},
  media: {mode: 'native', origin: 'https://www.cam4.com', domains: ['cam4-hls.xcdnpro.com', 'stackvaults-hls.xcdnpro.com']},
  imageHeaders: {Referer: 'https://www.cam4.com/'}, idPattern: '^[A-Za-z0-9_]{1,80}$',
  defaultFeed: 'popular', feeds: [{key: 'popular', label: '热门', options: [{key: 'gender', label: '分类', default: 'female', dynamic: true, values: []}]}],
  async filterOptions(req) {
    if (req.scope !== 'feed' || req.feed !== 'popular' || req.filter !== 'gender') throw Park.error('CONFIG', '筛选参数无效');
    const r = this.http.ensureOk(await this.http.get('https://www.cam4.com/')), doc = Park.html.parse(r.body), values = new Map();
    for (const a of doc.querySelectorAll('a[href]')) {
      let u; try { u = new URL(a.getAttribute('href'), 'https://www.cam4.com'); } catch (_) { continue; }
      const m = u.origin === 'https://www.cam4.com' && /^\/(female|male|transgender|couple)$/.exec(u.pathname);
      if (m && Park.html.text(a)) values.set(m[1], Park.html.text(a));
    }
    if (values.size < 2) throw Park.error('PARSE', '分类列表解析失败');
    return [...values].map(([value,label]) => ({value,label}));
  },
  validId(value) { const id = String(value || ''); if (!/^[A-Za-z0-9_]{1,80}$/.test(id)) throw Park.error('NOT_FOUND', '直播间不存在'); return id; },
  item(row) {
    const id = String(row?.username || ''), cover = String(row?.preview?.poster || '');
    if (!/^[A-Za-z0-9_]{1,80}$/.test(id) || !cover || row.showType !== 'PUBLIC_SHOW') return null;
    return {id, title: id, cover, coverAspect: 16 / 9,
      url: 'https://www.cam4.com/' + id, mediaKind: 'video', chapters: null};
  },
  async list(page = 1, gender = 'female') {
    if (!['female', 'male', 'transgender', 'couple'].includes(gender)) throw Park.error('CONFIG', '筛选参数无效');
    const r = await this.http.post('https://www.cam4.com/graph', {json: {query: 'query getTrendingCamsData($input: BroadcastsInput) { broadcasts(input: $input) {total items {id username showType viewers preview {src poster}}} }', variables: {input: {cursor: {first: 20, offset: (page - 1) * 20}, filters: [], gender, orderBy: 'trending'}}}, timeout: 30000});
    if (!r.ok) throw Park.error('HTTP', '直播请求失败', {status: r.status});
    let data; try { data = r.json(); } catch (_) { throw Park.error('PARSE', '直播数据无效'); }
    const rows = data?.data?.broadcasts?.items;
    if (!Array.isArray(rows)) throw Park.error('PARSE', '直播数据无效');
    return {items: rows.map(x => this.item(x)).filter(Boolean), page, hasNext: page * 20 < Number(data.data.broadcasts.total)};
  },
  async feed(key, req = {}) { if (key !== 'popular') throw Park.error('CONFIG', '未知直播列表'); return this.list(Math.max(1, Math.floor(Number(req.page) || 1)), String(req.options?.gender || 'female')); },
  async detail(value) {
    const id = this.validId(value), r = await this.http.get('https://www.cam4.com/rest/v1.0/profile/' + encodeURIComponent(id) + '/streamInfo', {timeout: 30000});
    if (r.status === 404) throw Park.error('NOT_FOUND', '直播间不存在'); if (!r.ok) throw Park.error('HTTP', '直播请求失败', {status: r.status});
    let d; try { d = r.json(); } catch (_) { throw Park.error('PARSE', '直播数据无效'); }
    const media = Park.url.parse(d?.cdnURL || d?.edgeURL, 'https://www.cam4.com', this.media.domains); if (!media) throw Park.error('UNSUPPORTED', '直播间暂无可用播放地址');
    return {id, title: id, url: 'https://www.cam4.com/' + id, cover: '', description: '', tags: [], chapters: null, mediaKind: 'video'};
  },
  async videos(value) {
    const id = this.validId(value), r = await this.http.get('https://www.cam4.com/rest/v1.0/profile/' + encodeURIComponent(id) + '/streamInfo', {timeout: 30000});
    if (!r.ok) throw Park.error(r.status === 404 ? 'NOT_FOUND' : 'HTTP', r.status === 404 ? '直播间不存在' : '直播请求失败', {status: r.status});
    let d; try { d = r.json(); } catch (_) { throw Park.error('PARSE', '直播数据无效'); }
    const url = Park.url.parse(d?.cdnURL || d?.edgeURL, 'https://www.cam4.com', this.media.domains)?.href;
    if (!url) throw Park.error('UNSUPPORTED', '直播间暂无可用播放地址');
    return [{url, format: 'hls', label: '直播', preferred: true, headers: {Referer: 'https://www.cam4.com/'}}];
  },
});

