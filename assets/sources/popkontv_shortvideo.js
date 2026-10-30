Park.register({
  i18n: {
    'zh-Hant': {'PopkonTV 短视频': 'PopkonTV 短影片', '韩国主播短视频，支持推荐、分页与 MP4 播放': '韓國主播短影片，支援推薦、分頁與 MP4 播放', '短视频数据无效': '短影片資料無效', '短视频请求失败': '短影片請求失敗', '短视频不存在': '短影片不存在', '短视频暂无可用播放地址': '短影片暫無可用播放位址'},
    ja: {'PopkonTV 短视频': 'PopkonTV ショート動画', '韩国主播短视频，支持推荐、分页与 MP4 播放': '韓国配信者の短編動画をおすすめ・ページ送り・MP4再生に対応', '短视频数据无效': '短編動画データが無効です', '短视频请求失败': '短編動画の取得に失敗しました', '短视频不存在': '短編動画が見つかりません', '短视频暂无可用播放地址': '再生可能な短編動画がありません'},
    ko: {'PopkonTV 短视频': 'PopkonTV 숏폼', '韩国主播短视频，支持推荐、分页与 MP4 播放': '한국 BJ 숏폼 추천, 페이지 이동 및 MP4 재생 지원', '短视频数据无效': '숏폼 데이터가 올바르지 않습니다', '短视频请求失败': '숏폼 요청에 실패했습니다', '短视频不存在': '숏폼을 찾을 수 없습니다', '短视频暂无可用播放地址': '재생 가능한 숏폼이 없습니다'},
    en: {'PopkonTV 短视频': 'PopkonTV Short Videos', '韩国主播短视频，支持推荐、分页与 MP4 播放': 'Korean creator short videos with recommendations, pagination and MP4 playback', '短视频数据无效': 'Invalid short video data', '短视频请求失败': 'Short video request failed', '短视频不存在': 'Short video not found', '短视频暂无可用播放地址': 'No playable short video is available'},
    es: {'PopkonTV 短视频': 'PopkonTV Vídeos cortos', '韩国主播短视频，支持推荐、分页与 MP4 播放': 'Vídeos cortos de creadores coreanos con recomendaciones, páginas y reproducción MP4', '短视频数据无效': 'Datos del vídeo corto no válidos', '短视频请求失败': 'Error al solicitar el vídeo corto', '短视频不存在': 'Vídeo corto no encontrado', '短视频暂无可用播放地址': 'No hay un vídeo corto reproducible'},
    ru: {'PopkonTV 短视频': 'PopkonTV Короткие видео', '韩国主播短视频，支持推荐、分页与 MP4 播放': 'Короткие видео корейских авторов: рекомендации, страницы и MP4', '短视频数据无效': 'Некорректные данные короткого видео', '短视频请求失败': 'Ошибка запроса короткого видео', '短视频不存在': 'Короткое видео не найдено', '短视频暂无可用播放地址': 'Нет короткого видео для воспроизведения'},
    ar: {'PopkonTV 短视频': 'PopkonTV مقاطع قصيرة', '韩国主播短视频，支持推荐、分页与 MP4 播放': 'مقاطع قصيرة لمنشئي المحتوى الكوريين مع التوصيات والصفحات وتشغيل MP4', '短视频数据无效': 'بيانات المقطع القصير غير صالحة', '短视频请求失败': 'فشل طلب المقطع القصير', '短视频不存在': 'المقطع القصير غير موجود', '短视频暂无可用播放地址': 'لا يوجد مقطع قصير متاح للتشغيل'},
  },
  key: 'popkontv_shortvideo', name: 'PopkonTV 短视频', version: '0.0.5', minAppVersion: '0.9.2', type: 'video', category: 'shortvideo',
  color: '#F04A55', description: '韩国主播短视频，支持推荐、分页与 MP4 播放', language: 'ko',
  homepage: 'https://www.popkontv.com/', domains: ['popkontv.com'],
  network: {mode: 'native', origin: 'https://www.popkontv.com', vpnHint: true},
  imageHeaders: {Referer: 'https://www.popkontv.com/'},
  media: {mode: 'native', scope: 'session', origin: 'https://www.popkontv.com', domains: ['popkontv.hscdn.com']},
  idPattern: '^[1-9]\\d{0,8}$', linkPatterns: ['popkontv\\.com/clip/([1-9]\\d{0,8})(?:[/?#]|$)'],
  defaultFeed: 'recommend', feeds: [{key: 'recommend', label: '推荐'}],
  BASE: 'https://www.popkontv.com', API: 'https://www.popkontv.com/api/proxy/vod/v1',
  validId(value) { const id = String(value); if (!/^[1-9]\d{0,8}$/.test(id)) throw Park.error('NOT_FOUND', '短视频不存在'); return id; },
  publicUrl(value, base = this.BASE) {
    // CDN 主机会更换，只要求是公网 HTTPS 地址；作品身份仍按站点域名校验。
    try { const url = new URL(String(value).trim(), base); return Park.url.parse(url.href, base, [url.hostname]); } catch (_) { return null; }
  },
  async api(path, body) {
    const r = await this.http.post(this.API + path, {readOnly: ['/list', '/detail', '/comments', '/recomments'].includes(path), json: {...body, partnerCode: 'P-00001', signId: ''}, headers: {Origin: this.BASE, Referer: this.BASE + '/'}, timeout: 15000});
    if (!r.ok) throw Park.error('HTTP', '短视频请求失败', {status: r.status});
    let data; try { data = r.json(); } catch (_) { throw Park.error('PARSE', '短视频数据无效'); }
    if (data?.statusCd !== 'S2000') throw Park.error('PARSE', '短视频数据无效');
    return data.data;
  },
  listItem(v) {
    const id = String(v?.idx || ''), title = String(v?.vodTitle || '').trim();
    let cover;
    cover = this.publicUrl(v?.thumbnailUrl)?.href || '';
    if (!/^[1-9]\d{0,8}$/.test(id) || !title) return null;
    const count = Number(String(v.viewCntComma || '').replace(/,/g, ''));
    return {id, title, cover, coverAspect: 9/16, views: Number.isFinite(count) ? count : undefined, uploaded: v.ago || undefined, url: this.BASE + '/clip/' + id};
  },
  async feed(key, req = {}) {
    if (key !== 'recommend') throw Park.error('CONFIG', '未知视频列表');
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    const data = await this.api('/list', {category: 1, groupCode: 20, pageNum: page, pageSize: 20, sortType: 2});
    if (!Array.isArray(data?.vodList) || !Number.isFinite(Number(data.totalCnt))) throw Park.error('PARSE', '短视频数据无效');
    const items = data.vodList.map(v => this.listItem(v)).filter(Boolean);
    if (data.vodList.length && !items.length) throw Park.error('PARSE', '短视频数据无效');
    return {items, page, hasNext: page * 20 < Number(data.totalCnt)};
  },
  async comments(value, req = {}) {
    const work = this.validId(value), page = Math.max(1, Math.floor(Number(req.page) || 1));
    const parent = req.parentId == null ? null : String(req.parentId);
    if (parent && !/^[1-9]\d*$/.test(parent)) throw Park.error('CONFIG', '评论参数无效');
    if (req.sort && req.sort !== 'default') throw Park.error('UNSUPPORTED', '评论暂不支持此操作');
    let previous = [];
    if (req.cursor) {
      let state; try { state = JSON.parse(req.cursor); } catch (_) {}
      if (!state || state.work !== work || state.parent !== parent || state.page !== page || !Array.isArray(state.ids)) throw Park.error('CONFIG', '评论参数无效');
      previous = state.ids;
    }
    // 回复接口的 ref 是原评论号；列表接口在部分作品忽略页号，按总量及已见 ID 收口。
    const data = await this.api(parent ? '/recomments' : '/comments', {idx: Number(work), pageNum: page, pageSize: 10, ...(parent ? {ref: Number(parent)} : {})});
    const rows = parent ? data : data?.vodCommentList;
    if (!Array.isArray(rows) || (!parent && !Number.isFinite(Number(data.totalCnt)))) throw Park.error('PARSE', '评论数据无效');
    const seen = new Set(previous), items = [];
    for (const row of rows) {
      const id = String(row.pkCode || '');
      if (!/^[1-9]\d*$/.test(id) || seen.has(id)) continue;
      const body = Park.comments.html(String(row.ntext || ''), this.BASE);
      if (!body.length) continue;
      seen.add(id);
      items.push({id, parentId: parent || undefined, author: {name: String(row.nickName || ''), avatar: Park.comments.url(row.profileImage, this.BASE)},
        body, date: row.ago || undefined, likes: Number(row.goodCnt) || 0, replyCount: parent ? 0 : Number(row.totalCnt) || 0, repliesAvailable: !parent});
    }
    if (rows.length && !items.length && !rows.every(row => previous.includes(String(row.pkCode)))) throw Park.error('PARSE', '评论数据无效');
    const total = parent ? items.length : Number(data.totalCnt);
    // 原站回复响应为完整数组，没有经过验证的续页标记。
    const hasNext = !parent && items.length > 0 && seen.size < total;
    return {items, page, total, hasNext, cursor: hasNext ? JSON.stringify({work, parent, page: page + 1, ids: [...seen]}) : null};
  },
  async detail(value) {
    const id = this.validId(value), data = await this.api('/detail', {idx: Number(id)});
    if (!data || String(data.pk_code) !== id || !data.vodTitle) throw Park.error('NOT_FOUND', '短视频不存在');
    const cover = this.publicUrl(data.vodPoster)?.href || '';
    const tags = (Array.isArray(data.hashTags) ? data.hashTags : []).filter(t => typeof t === 'string' && t.trim()).map(t => ({name: t.trim(), keyword: t.trim()}));
    return {id, title: data.vodTitle, cover, coverAspect: 9/16, url: this.BASE + '/clip/' + id, description: data.contentTxt || '', authors: data.nickName ? [data.nickName] : [], uploaded: data.rdate || data.ago, views: Number(data.viewCnt) || undefined, tags: tags.length ? [{namespace: 'tag', label: '标签', tags}] : [], chapters: null};
  },
  async videos(value) {
    const id = this.validId(value), data = await this.api('/detail', {idx: Number(id)});
    if (!data || String(data.pk_code) !== id) throw Park.error('NOT_FOUND', '短视频不存在');
    const u = this.publicUrl(data.vodAddress);
    if (!u || !/\.mp4$/i.test(u.pathname)) throw Park.error('UNSUPPORTED', '短视频暂无可用播放地址');
    return [{url: u.href, format: 'mp4', label: '原画', preferred: true, headers: {Referer: this.BASE + '/'}}];
  },
});
