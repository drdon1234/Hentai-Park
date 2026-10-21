Park.register({
  i18n: {
    'zh-Hant': {'PopkonTV 录播': 'PopkonTV 錄播', '韩国主播录播，支持推荐、分页与 MP4 播放': '韓國主播錄播，支援推薦、分頁與 MP4 播放', '录播数据无效': '錄播資料無效', '录播请求失败': '錄播請求失敗', '录播不存在': '錄播不存在', '录播暂无可用播放地址': '錄播暫無可用播放位址'},
    ja: {'PopkonTV 录播': 'PopkonTV 録画', '韩国主播录播，支持推荐、分页与 MP4 播放': '韓国配信者の録画をおすすめ・ページ送り・MP4再生に対応', '录播数据无效': '録画データが無効です', '录播请求失败': '録画の取得に失敗しました', '录播不存在': '録画が見つかりません', '录播暂无可用播放地址': '再生可能な録画がありません'},
    ko: {'PopkonTV 录播': 'PopkonTV 다시보기', '韩国主播录播，支持推荐、分页与 MP4 播放': '한국 BJ 다시보기 추천, 페이지 이동 및 MP4 재생 지원', '录播数据无效': '다시보기 데이터가 올바르지 않습니다', '录播请求失败': '다시보기 요청에 실패했습니다', '录播不存在': '다시보기를 찾을 수 없습니다', '录播暂无可用播放地址': '재생 가능한 다시보기가 없습니다'},
    en: {'PopkonTV 录播': 'PopkonTV Recordings', '韩国主播录播，支持推荐、分页与 MP4 播放': 'Korean creator recordings with recommendations, pagination and MP4 playback', '录播数据无效': 'Invalid recording data', '录播请求失败': 'Recording request failed', '录播不存在': 'Recording not found', '录播暂无可用播放地址': 'No playable recording is available'},
    es: {'PopkonTV 录播': 'PopkonTV Grabaciones', '韩国主播录播，支持推荐、分页与 MP4 播放': 'Grabaciones de creadores coreanos con recomendaciones, páginas y reproducción MP4', '录播数据无效': 'Datos de grabación no válidos', '录播请求失败': 'Error al solicitar la grabación', '录播不存在': 'Grabación no encontrada', '录播暂无可用播放地址': 'No hay una grabación reproducible'},
    ru: {'PopkonTV 录播': 'PopkonTV Записи', '韩国主播录播，支持推荐、分页与 MP4 播放': 'Записи корейских авторов: рекомендации, страницы и воспроизведение MP4', '录播数据无效': 'Некорректные данные записи', '录播请求失败': 'Ошибка запроса записи', '录播不存在': 'Запись не найдена', '录播暂无可用播放地址': 'Нет доступной записи для воспроизведения'},
    ar: {'PopkonTV 录播': 'PopkonTV تسجيلات', '韩国主播录播，支持推荐、分页与 MP4 播放': 'تسجيلات منشئي المحتوى الكوريين مع التوصيات والصفحات وتشغيل MP4', '录播数据无效': 'بيانات التسجيل غير صالحة', '录播请求失败': 'فشل طلب التسجيل', '录播不存在': 'التسجيل غير موجود', '录播暂无可用播放地址': 'لا يوجد تسجيل متاح للتشغيل'},
  },
  key: 'popkontv_recording', name: 'PopkonTV 录播', version: '0.0.2', minAppVersion: '0.9.2', type: 'video', category: 'recording',
  color: '#F04A55', description: '韩国主播录播，支持推荐、分页与 MP4 播放', language: 'ko',
  homepage: 'https://www.popkontv.com/vod', domains: ['popkontv.com'],
  network: {mode: 'native', origin: 'https://www.popkontv.com', vpnHint: true},
  imageHeaders: {Referer: 'https://www.popkontv.com/'},
  media: {mode: 'native', origin: 'https://www.popkontv.com', domains: ['popkontv.hscdn.com']},
  idPattern: '^[1-9]\\d{0,8}$', linkPatterns: ['popkontv\\.com/vod/([1-9]\\d{0,8})(?:[/?#]|$)'],
  defaultFeed: 'recommend', feeds: [{key: 'recommend', label: '推荐'}],
  BASE: 'https://www.popkontv.com', API: 'https://www.popkontv.com/api/proxy/vod/v1',
  validId(value) { const id = String(value); if (!/^[1-9]\d{0,8}$/.test(id)) throw Park.error('NOT_FOUND', '录播不存在'); return id; },
  async api(path, body) {
    const r = await this.http.post(this.API + path, {json: {...body, partnerCode: 'P-00001', signId: ''}, headers: {Origin: this.BASE, Referer: this.BASE + '/'}, timeout: 15000});
    if (!r.ok) throw Park.error('HTTP', '录播请求失败', {status: r.status});
    let data; try { data = r.json(); } catch (_) { throw Park.error('PARSE', '录播数据无效'); }
    if (data?.statusCd !== 'S2000') throw Park.error('PARSE', '录播数据无效');
    return data.data;
  },
  listItem(v) {
    const id = String(v?.idx || ''), title = String(v?.vodTitle || '').trim();
    let cover;
    try { const u = new URL(v?.thumbnailUrl); if (u.protocol !== 'https:' || u.hostname !== 'vod2.popkontv.hscdn.com') return null; cover = u.href; } catch (_) { return null; }
    if (!/^[1-9]\d{0,8}$/.test(id) || !title) return null;
    const count = Number(String(v.viewCntComma || '').replace(/,/g, ''));
    return {id, title, cover, coverAspect: 16/9, views: Number.isFinite(count) ? count : undefined, uploaded: v.ago || undefined, url: this.BASE + '/vod/' + id};
  },
  async feed(key, req = {}) {
    if (key !== 'recommend') throw Park.error('CONFIG', '未知视频列表');
    const page = Math.max(1, Math.floor(Number(req.page) || 1));
    const data = await this.api('/list', {category: 9, groupCode: 1, pageNum: page, pageSize: 20, sortType: 2});
    if (!Array.isArray(data?.vodList) || !Number.isFinite(Number(data.totalCnt))) throw Park.error('PARSE', '录播数据无效');
    const items = data.vodList.map(v => this.listItem(v)).filter(Boolean);
    if (data.vodList.length && !items.length) throw Park.error('PARSE', '录播数据无效');
    return {items, page, hasNext: page * 20 < Number(data.totalCnt)};
  },
  async detail(value) {
    const id = this.validId(value), data = await this.api('/detail', {idx: Number(id)});
    if (!data || String(data.pk_code) !== id || !data.vodTitle || !data.vodPoster) throw Park.error('NOT_FOUND', '录播不存在');
    let cover; try { const u = new URL(data.vodPoster); if (u.protocol !== 'https:' || u.hostname !== 'vod2.popkontv.hscdn.com') throw 0; cover = u.href; } catch (_) { throw Park.error('PARSE', '录播数据无效'); }
    const tags = (Array.isArray(data.hashTags) ? data.hashTags : []).filter(t => typeof t === 'string' && t.trim()).map(t => ({name: t.trim(), keyword: t.trim()}));
    return {id, title: data.vodTitle, cover, coverAspect: 16/9, url: this.BASE + '/vod/' + id, description: data.contentTxt || '', authors: data.nickName ? [data.nickName] : [], uploaded: data.rdate || data.ago, views: Number(data.viewCnt) || undefined, tags: tags.length ? [{namespace: 'tag', label: '标签', tags}] : [], chapters: null};
  },
  async videos(value) {
    const id = this.validId(value), data = await this.api('/detail', {idx: Number(id)});
    if (!data || String(data.pk_code) !== id) throw Park.error('NOT_FOUND', '录播不存在');
    let u; try { u = new URL(data.vodAddress); } catch (_) { throw Park.error('UNSUPPORTED', '录播暂无可用播放地址'); }
    if (u.protocol !== 'https:' || u.hostname !== 'vod2.popkontv.hscdn.com' || !/\.mp4$/i.test(u.pathname)) throw Park.error('UNSUPPORTED', '录播暂无可用播放地址');
    return [{url: u.href, format: 'mp4', label: '原画', preferred: true, headers: {Referer: this.BASE + '/'}}];
  },
});
