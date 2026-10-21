Park.register({
  i18n: {
    'zh-Hant': {'Stripchat 亚洲直播': 'Stripchat 亞洲直播', '中国与亚洲公开直播间': '中國與亞洲公開直播間', '未知直播列表': '未知直播列表', '直播请求失败': '直播請求失敗', '直播数据无效': '直播資料無效', '直播间不存在': '直播間不存在', '直播间暂不可用': '直播間暫不可用', '直播间编号无效': '直播間編號無效'},
    ja: {'Stripchat 亚洲直播': 'Stripchat アジアライブ', '中国与亚洲公开直播间': '中国・アジアの公開ライブ配信', '未知直播列表': '不明なライブ一覧', '直播请求失败': 'ライブ配信の取得に失敗しました', '直播数据无效': 'ライブデータが無効です', '直播间不存在': 'ライブ配信が見つかりません', '直播间暂不可用': 'ライブ配信は現在利用できません', '直播间编号无效': '無効なライブ ID'},
    ko: {'Stripchat 亚洲直播': 'Stripchat 아시아 라이브', '中国与亚洲公开直播间': '중국·아시아 공개 라이브 방송', '未知直播列表': '알 수 없는 라이브 목록', '直播请求失败': '라이브 요청에 실패했습니다', '直播数据无效': '라이브 데이터가 올바르지 않습니다', '直播间不存在': '라이브 방송을 찾을 수 없습니다', '直播间暂不可用': '현재 라이브 방송을 사용할 수 없습니다', '直播间编号无效': '잘못된 라이브 ID'},
    en: {'Stripchat 亚洲直播': 'Stripchat Asian Live', '中国与亚洲公开直播间': 'Public Chinese and Asian live rooms', '未知直播列表': 'Unknown live feed', '直播请求失败': 'Live request failed', '直播数据无效': 'Invalid live data', '直播间不存在': 'Live room not found', '直播间暂不可用': 'Live room is currently unavailable', '直播间编号无效': 'Invalid live room ID'},
    es: {'Stripchat 亚洲直播': 'Stripchat Directos asiáticos', '中国与亚洲公开直播间': 'Salas públicas de China y Asia', '未知直播列表': 'Lista de directos desconocida', '直播请求失败': 'Error al solicitar el directo', '直播数据无效': 'Datos de directo no válidos', '直播间不存在': 'Sala de directo no encontrada', '直播间暂不可用': 'El directo no está disponible', '直播间编号无效': 'ID de directo no válido'},
    ru: {'Stripchat 亚洲直播': 'Stripchat Азиатские эфиры', '中国与亚洲公开直播间': 'Открытые эфиры из Китая и Азии', '未知直播列表': 'Неизвестная лента эфиров', '直播请求失败': 'Ошибка запроса эфира', '直播数据无效': 'Некорректные данные эфира', '直播间不存在': 'Эфир не найден', '直播间暂不可用': 'Эфир сейчас недоступен', '直播间编号无效': 'Неверный ID эфира'},
    ar: {'Stripchat 亚洲直播': 'Stripchat بث آسيوي', '中国与亚洲公开直播间': 'غرف بث عامة من الصين وآسيا', '未知直播列表': 'قائمة بث غير معروفة', '直播请求失败': 'فشل طلب البث', '直播数据无效': 'بيانات البث غير صالحة', '直播间不存在': 'غرفة البث غير موجودة', '直播间暂不可用': 'البث غير متاح حالياً', '直播间编号无效': 'معرّف البث غير صالح'}
  },
  key: 'stripchat_asia', name: 'Stripchat 亚洲直播', version: '0.0.2', type: 'video', category: 'live',
  color: '#ff4d7d', description: '中国与亚洲公开直播间', language: 'en', homepage: 'https://zh.stripchat.com/',
  domains: ['stripchat.com'], network: {mode: 'auto', origin: 'https://zh.stripchat.com', vpnHint: true},
  imageHeaders: {Referer: 'https://zh.stripchat.com/'}, imageNetwork: {mode: 'browser', origin: 'https://static-proxy.strpst.com', domains: ['static-proxy.strpst.com']},
  media: {mode: 'native', origin: 'https://zh.stripchat.com', domains: ['edge-hls.doppiocdn.org', 'media-hls.doppiocdn.org']},
  idPattern: '^[1-9]\\d{5,11}$',
  defaultFeed: 'asia', feeds: [{key: 'asia', label: '亚洲'}],
  BASE: 'https://zh.stripchat.com',
  validId(value) { const id=String(value||''); if(!/^[1-9]\d{5,11}$/.test(id)) throw Park.error('NOT_FOUND','直播间编号无效'); return id; },
  async json(path) {
    const r=await this.http.get(this.BASE+path,{headers:{Referer:this.BASE+'/'},timeout:20000});
    if(!r.ok) throw Park.error(r.status===404?'NOT_FOUND':'HTTP',r.status===404?'直播间不存在':'直播请求失败',{status:r.status});
    try{return r.json();}catch(_){throw Park.error('PARSE','直播数据无效');}
  },
  isAsian(row, context = '') {
    const gender = String(row?.broadcastGender || row?.gender || '').toLowerCase();
    if (!['female', 'females'].includes(gender)) return false;
    const country = String(row?.country || '').toLowerCase();
    if (/^(?:cn|tw|jp|kr|hk|mo|sg|my)$/.test(country)) return true;
    const tags = [
      ...(Array.isArray(row?.tags) ? row.tags : []),
      ...(Array.isArray(row?.lastTagsAliases) ? row.lastTagsAliases : []),
      ...(Array.isArray(row?.tagGroups) ? row.tagGroups.flatMap(x => x?.tags || []) : []),
      String(context || '')
    ].join(' ').toLowerCase();
    return /(?:chinese|japanese|korean|taiwan|asian|hong[ -]?kong|singapore|malaysia|中国|中文|日本|韩国|台湾|亞洲|亚洲)/i.test(tags);
  },
  cover(value) {
    try {
      const u = new URL(value, 'https://static-proxy.strpst.com');
      return u.protocol === 'https:' && u.hostname === 'static-proxy.strpst.com' && /^\/(?:avatars|previews)\//.test(u.pathname) ? u.href : '';
    } catch (_) { return ''; }
  },
  item(row, context = '') {
    const id=String(row?.id||''), cover=this.cover(row?.previewUrlThumbSmall||row?.previewUrlThumbBig||row?.avatarUrl);
    if(!/^[1-9]\d{5,11}$/.test(id)||!row?.username||row.status!=='public'||row.isLive!==true||!this.isAsian(row, context)||!cover) return null;
    return {id,title:String(row.username),cover,coverAspect:16/9,url:this.BASE+'/'+encodeURIComponent(row.username),mediaKind:'video',views:Number(row.viewersCount)||undefined,chapters:null};
  },
  async feed(key,req={}) {
    if(key!=='asia') throw Park.error('CONFIG','未知直播列表');
    const page=Math.max(1,Math.floor(Number(req.page)||1));
    const tags = ['tagLanguageChinese', 'tagLanguageJapanese', 'tagLanguageKorean'];
    const responses = await Promise.all(tags.map(async tag => {
      const filter = encodeURIComponent(JSON.stringify([[tag]]));
      const data = await this.json('/api/front/models?limit=20&offset='+((page-1)*20)+'&primaryTag=girls&filterGroupTags='+filter);
      if (!Array.isArray(data?.models)) throw Park.error('PARSE','直播数据无效');
      return {tag, data};
    }));
    const entries = responses.flatMap(({tag, data}) => data.models.map(row => ({row, context: tag})));
    if(!entries.length&&!responses.some(({data}) => Number.isFinite(Number(data?.totalCount)))) throw Park.error('PARSE','直播数据无效');
    const unique = new Map();
    for (const entry of entries) {
      const item = this.item(entry.row, entry.context);
      if (item && !unique.has(item.id)) unique.set(item.id, item);
    }
    return {items:[...unique.values()],page,hasNext:responses.some(({data}) => data.models.length === 20)};
  },
  async detail(value) {
    const id=this.validId(value), d=await this.json('/api/front/v2/models/'+id+'/cam'), user=d?.user?.user, cam=d?.cam;
    if(!user||String(user.id)!==id||user.status!=='public'||user.isLive!==true||!this.isAsian(user)) throw Park.error('NOT_FOUND','直播间不存在');
    return {id,title:String(user.username||user.name||id),cover:this.cover(user.previewUrlThumbBig||user.previewUrlThumbSmall),coverAspect:16/9,url:this.BASE+'/'+encodeURIComponent(user.username||id),description:String(user.description||''),authors:[],tags:[],chapters:null,mediaKind:'video'};
  },
  async videos(value) {
    const id=this.validId(value), d=await this.json('/api/front/v2/models/'+id+'/cam'), user=d?.user?.user, cam=d?.cam;
    if(!user||String(user.id)!==id||user.status!=='public'||user.isLive!==true||!this.isAsian(user)||cam?.isCamAvailable!==true) throw Park.error('UNSUPPORTED','直播间暂不可用');
    const stream=String(cam.streamName||id); if(!/^\d{6,12}$/.test(stream)) throw Park.error('PARSE','直播数据无效');
    const url='https://edge-hls.doppiocdn.org/hls/'+stream+'/master/'+stream+'_auto.m3u8';
    return [{url,format:'hls',label:'直播',preferred:true,headers:{Referer:this.BASE+'/'}}];
  }
});
