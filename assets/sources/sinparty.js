Park.register({
  i18n: {
  "zh-Hant": {
    "直播": "直播",
    "直播间暂无可用播放地址": "直播間暫無可用播放位址",
    "自营公开直播间": "自營公開直播間",
    "直播间不存在": "直播間不存在",
    "直播间不存在或已下线": "直播間不存在或已下線",
    "直播请求失败": "直播請求失敗",
    "直播数据无效": "直播資料無效",
    "未知直播列表": "未知直播列表"
  },
  "en": {
    "直播": "Live",
    "直播间暂无可用播放地址": "No playable live stream is available",
    "自营公开直播间": "Public rooms hosted by this site",
    "直播间不存在": "Live room not found",
    "直播间不存在或已下线": "Live room is offline or unavailable",
    "直播请求失败": "Live request failed",
    "直播数据无效": "Invalid live data",
    "未知直播列表": "Unknown live feed"
  },
  "ja": {
    "直播": "ライブ",
    "直播间暂无可用播放地址": "再生可能なライブ配信がありません",
    "自营公开直播间": "サイト運営の公開ライブ配信",
    "直播间不存在": "ライブ配信が見つかりません",
    "直播间不存在或已下线": "ライブ配信が終了したか見つかりません",
    "直播请求失败": "ライブ配信の取得に失敗しました",
    "直播数据无效": "ライブデータが無効です",
    "未知直播列表": "不明なライブ一覧"
  },
  "ko": {
    "直播": "라이브",
    "直播间暂无可用播放地址": "재생 가능한 라이브 방송이 없습니다",
    "自营公开直播间": "사이트 자체 공개 라이브 방송",
    "直播间不存在": "라이브 방송을 찾을 수 없습니다",
    "直播间不存在或已下线": "라이브 방송이 종료되었거나 없습니다",
    "直播请求失败": "라이브 요청에 실패했습니다",
    "直播数据无效": "라이브 데이터가 올바르지 않습니다",
    "未知直播列表": "알 수 없는 라이브 목록"
  },
  "es": {
    "直播": "Directo",
    "直播间暂无可用播放地址": "No hay una emisión reproducible disponible",
    "自营公开直播间": "Salas públicas alojadas por el sitio",
    "直播间不存在": "Sala de directo no encontrada",
    "直播间不存在或已下线": "La sala no existe o está desconectada",
    "直播请求失败": "Error al solicitar el directo",
    "直播数据无效": "Datos de directo no válidos",
    "未知直播列表": "Lista de directos desconocida"
  },
  "ru": {
    "直播": "Эфир",
    "直播间暂无可用播放地址": "Нет доступного потока для воспроизведения",
    "自营公开直播间": "Собственные открытые эфиры сайта",
    "直播间不存在": "Эфир не найден",
    "直播间不存在或已下线": "Эфир недоступен или завершён",
    "直播请求失败": "Ошибка запроса эфира",
    "直播数据无效": "Некорректные данные эфира",
    "未知直播列表": "Неизвестный список эфиров"
  },
  "ar": {
    "直播": "بث مباشر",
    "直播间暂无可用播放地址": "لا يوجد بث متاح للتشغيل",
    "自营公开直播间": "غرف بث عامة يستضيفها الموقع",
    "直播间不存在": "غرفة البث غير موجودة",
    "直播间不存在或已下线": "غرفة البث غير متاحة أو غير متصلة",
    "直播请求失败": "فشل طلب البث",
    "直播数据无效": "بيانات البث غير صالحة",
    "未知直播列表": "قائمة بث غير معروفة"
  }
},
  key: 'sinparty', name: 'SinParty', version: '0.0.6', minAppVersion: '0.9.2', type: 'video', category: 'live', language: 'en',
  color: '#e83e8c', description: '自营公开直播间', homepage: 'https://sinparty.com/', domains: ['sinparty.com'],
  network: {mode: 'native', origin: 'https://sinparty.com', vpnHint: true},
  media: {mode: 'native', scope: 'session', origin: 'https://sinparty.com', domains: ['edge-cdn1.streamparty.online', 'edge-cdn2.streamparty.online']},
  imageHeaders: {Referer: 'https://sinparty.com/'}, idPattern: '^user[0-9a-f]{8,64}$', defaultFeed: 'popular', feeds: [{key: 'popular', label: '热门'}],
  item(x) { if (!x?.creator_user_hash || !x?.model_hash || !x?.slug || (x.live_status !== true && x.isLive !== true) || x.type !== 'public') return null; const cover = String(x.thumbnail_url || ''); if (!cover) return null; return {id: String(x.creator_user_hash), title: String(x.title || x.slug), cover, coverAspect: 16/9, subtitle: String(x.country || ''), viewers: Number(x.viewers) || 0, url: 'https://sinparty.com' + String(x.live_url || '/' + x.slug), mediaKind: 'video', chapters: null}; },
  async api(path, options = {}) { const r = await this.http.get('https://api.sinparty.com/v2/web/live-cams/web-rtc' + path, {...options, timeout: 30000}); if (!r.ok) throw Park.error('HTTP', '直播请求失败', {status: r.status}); try { return r.json()?.data; } catch (_) { throw Park.error('PARSE', '直播数据无效'); } },
  async feed(key, req = {}) {
    if (key !== 'popular') throw Park.error('CONFIG', '未知直播列表');
    const page = Math.max(1, Number(req.page) || 1);
    if (page > 1) return {items: [], page, hasNext: false};
    const data = await this.api('', {params: {page: 1}});
    if (!Array.isArray(data?.items)) throw Park.error('PARSE', '直播数据无效');
    const candidates = data.items.map(x => this.item(x)).filter(Boolean), items = [];
    // 推荐索引可能滞后，展示前核对房间状态；限制并发并保留推荐顺序。
    for (let offset = 0; offset < candidates.length; offset += 4) {
      const batch = await Promise.all(candidates.slice(offset, offset + 4).map(async item => {
        const room = await this.api('/' + encodeURIComponent(item.id));
        if (room?.user_hash !== item.id || room.isLive !== true || room.type !== 'public' ||
            !this.publicUrl(room.playback_url, 'https://sinparty.com')) return null;
        return item;
      }));
      items.push(...batch.filter(Boolean));
    }
    return {items, page, hasNext: false};
  },
  publicUrl(value, base = this.BASE) {
    // CDN 主机会更换，只要求是公网 HTTPS 地址；作品身份仍按站点域名校验。
    try { const url = new URL(String(value).trim(), base); return Park.url.parse(url.href, base, [url.hostname]); } catch (_) { return null; }
  },
  async detail(value) { const id = String(value || ''); if (!/^user[0-9a-f]{8,64}$/.test(id)) throw Park.error('NOT_FOUND', '直播间不存在'); const d = await this.api('/' + encodeURIComponent(id)); if (d?.user_hash !== id || !d.isLive || d.type !== 'public') throw Park.error('NOT_FOUND', '直播间不存在或已下线'); const path = String(d.live_url || ''); return {id, title: path.split('/').filter(Boolean).pop() || id, cover: String(d.thumbnail_url || d.snapshot || ''), coverAspect: 16 / 9, url: Park.url.parse(path, 'https://sinparty.com', this.domains)?.href || '', mediaKind: 'video', chapters: null, description: String(d.details || ''), tags: []}; },
  async videos(value) { const id = String(value || ''); if (!/^user[0-9a-f]{8,64}$/.test(id)) throw Park.error('NOT_FOUND', '直播间不存在'); const d = await this.api('/' + encodeURIComponent(id)); const url = this.publicUrl(d?.playback_url, 'https://sinparty.com')?.href; if (!url || d?.user_hash !== id || d.isLive !== true || d.type !== 'public') throw Park.error('UNSUPPORTED', '直播间暂无可用播放地址'); return [{url, format: 'hls', label: '直播', preferred: true, headers: {Referer: 'https://sinparty.com/'}}]; },
});

