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
  key: 'stripchat_asia', name: 'Stripchat 亚洲直播', version: '0.0.7', minAppVersion: '0.9.2', type: 'video', category: 'live',
  color: '#ff4d7d', description: '中国与亚洲公开直播间', language: 'en', homepage: 'https://zh.stripchat.com/',
  domains: ['stripchat.com'], network: {mode: 'auto', origin: 'https://zh.stripchat.com', vpnHint: true},
  imageHeaders: {Referer: 'https://zh.stripchat.com/'},
  media: {mode: 'native', scope: 'session', origin: 'https://zh.stripchat.com', domains: ['edge-hls.doppiocdn.org', 'media-hls.doppiocdn.org']},
  chat: {domains: ['websocket-sp-v6.stripchat.com']},
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
    // 预览图 CDN 会更换主机，只要求是公网 HTTPS 地址。
    try {
      const base = 'https://static-proxy.strpst.com';
      const url = new URL(String(value).trim(), base);
      return Park.url.parse(url.href, base, [url.hostname])?.href || '';
    } catch (_) { return ''; }
  },
  item(row, context = '') {
    const id=String(row?.id||''), cover=this.cover(row?.previewUrlThumbSmall||row?.previewUrlThumbBig||row?.avatarUrl);
    if(!/^[1-9]\d{5,11}$/.test(id)||!row?.username||row.status!=='public'||row.isLive!==true||!this.isAsian(row, context)) return null;
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
    this.remember(entries.map(entry => entry.row).filter(row => unique.has(String(row?.id||''))));
    return {items:[...unique.values()],page,hasNext:responses.some(({data}) => data.models.length === 20)};
  },
  // 单间接口常被 Cloudflare 挑战；列表接口已给出流名称和原站当前的播放主机，短时缓存后直接使用。
  remember(rows) {
    const saved = this.store.get('rooms') || {};
    for (const row of rows) {
      const id = String(row?.id || ''), stream = String(row?.streamName || id);
      if (!/^[1-9]\d{5,11}$/.test(id) || !/^\d{6,12}$/.test(stream)) continue;
      delete saved[id];
      saved[id] = {stream, hls: String(row?.hlsPlaylist || ''), at: Date.now()};
    }
    const ids = Object.keys(saved);
    for (const id of ids.slice(0, Math.max(0, ids.length - 300))) delete saved[id];
    this.store.set('rooms', saved);
  },
  cachedRoom(id) {
    const room = (this.store.get('rooms') || {})[id];
    return room && Date.now() - room.at < 15 * 60 * 1000 ? room : null;
  },
  async room(value) {
    const id = this.validId(value), data = await this.json('/api/front/v2/models/' + id + '/cam');
    const profile = data?.user, user = profile?.user, cam = data?.cam;
    if (!user || String(user.id) !== id || user.isDeleted === true) throw Park.error('NOT_FOUND', '直播间不存在');
    const tagged = {...user, tags: profile.tags || user.tags, tagGroups: profile.tagGroups || user.tagGroups,
      lastTagsAliases: profile.lastTagsAliases || user.lastTagsAliases};
    if (user.status !== 'public' || user.isLive !== true || !this.isAsian(tagged) || cam?.isCamAvailable !== true) {
      throw Park.error('UNSUPPORTED', '直播间暂不可用');
    }
    return {id, user, cam};
  },
  async detail(value, preview) {
    const id = this.validId(value);
    if (preview?.id === id && preview.title && this.cachedRoom(id)) {
      return {id,title:String(preview.title),cover:this.cover(preview.cover),coverAspect:16/9,url:this.BASE+'/'+encodeURIComponent(preview.title),description:'',authors:[],tags:[],chapters:null,mediaKind:'video'};
    }
    const {user} = await this.room(value);
    return {id,title:String(user.username||user.name||id),cover:this.cover(user.previewUrlThumbBig||user.previewUrlThumbSmall),coverAspect:16/9,url:this.BASE+'/'+encodeURIComponent(user.username||id),description:String(user.description||''),authors:[],tags:[],chapters:null,mediaKind:'video'};
  },
  async liveChat(value) {
    // 聊天每次重新核对公开房间，不使用播放缓存代替当前权限。
    const {id, user} = await this.room(value);
    const config = await this.json('/api/front/v3/config/initial-dynamic?requestPath=' + encodeURIComponent('/' + user.username));
    const auth = config?.initialDynamic?.websocket;
    let target; try { target = new URL(auth?.url); } catch (_) { throw Park.error('PARSE', '直播数据无效'); }
    if (target.protocol !== 'wss:' || !this.chat.domains.includes(target.hostname) || target.port || target.username || target.password || target.hash ||
        target.pathname !== '/connection/websocket' || !Park.url.parse(target.href.replace(/^wss:/, 'https:'), undefined, this.chat.domains) ||
        typeof auth?.token !== 'string' || !auth.token || auth.token.length > 16384) throw Park.error('PARSE', '直播数据无效');
    const history = await this.json('/api/front/v2/models/' + id + '/chat');
    if (!Array.isArray(history?.messages)) throw Park.error('PARSE', '直播数据无效');
    // 只保留历史身份，既不重放进房历史，也不把正文放入协议状态。
    const seen = [...new Set(history.messages.slice(-100).filter(m => String(m?.modelId) === id)
      .map(m => String(m?.id || '')).filter(x => x && x.length <= 256))];
    return {transport: 'websocket', url: target.href, state: {roomId: id, channel: 'newChatMessage@' + id, token: auth.token, seen, stage: 'initial'}};
  },
  liveChatEvent(state, event) {
    const out = {state: {...state, seen: [...(state.seen || [])]}, send: [], messages: []};
    if (event.type === 'open') {
      if (state.stage !== 'initial' || typeof state.token !== 'string' || !state.token) return {...out, error: true};
      out.send.push(JSON.stringify({id: 1, connect: {token: state.token}}));
      delete out.state.token;
      out.state.stage = 'connecting';
      return out;
    }
    if (event.type !== 'message' || typeof event.data !== 'string') return out;
    for (const line of event.data.split('\n').filter(Boolean).slice(0, 100)) {
      let packet; try { packet = JSON.parse(line); } catch (_) { continue; }
      if (!packet || typeof packet !== 'object' || Array.isArray(packet)) continue;
      if (!Object.keys(packet).length) {
        if (!out.send.includes('{}')) out.send.push('{}');
        continue;
      }
      if (packet.error || packet.push?.disconnect || (packet.push?.unsubscribe && packet.push.channel === state.channel)) return {...out, error: true, messages: []};
      if (packet.id === 1 && packet.connect && out.state.stage === 'connecting') {
        out.state.stage = 'subscribing';
        out.send.push(JSON.stringify({id: 2, subscribe: {channel: state.channel}}));
      } else if (packet.id === 2 && packet.subscribe && out.state.stage === 'subscribing') {
        out.state.stage = 'connected';
        out.connected = true;
      }
      if (out.state.stage !== 'connected' || packet.push?.channel !== state.channel) continue;
      const m = packet.push.pub?.data?.message;
      if (!m || String(m.modelId) !== state.roomId || m.type !== 'text' || m.isDeleted || typeof m.details?.body !== 'string' || !m.details.body.trim()) continue;
      const id = String(m.id || '');
      if (!id || id.length > 256 || out.state.seen.includes(id)) continue;
      out.state.seen.push(id);
      if (out.state.seen.length > 512) out.state.seen.shift();
      out.messages.push({id: state.roomId + ':' + id, text: m.details.body.slice(0, 2000)});
    }
    return out;
  },
  async hlsDomains() {
    // 原站配置给出 HLS 备用域，与原站播放器一样在主域不可用时切换。
    const cached = this.store.get('hlsDomains');
    if (cached && Date.now() - cached.at < 6 * 3600 * 1000) return cached.domains;
    let fallback = [];
    try {
      const config = JSON.stringify(await this.json('/api/front/v3/config/static'));
      fallback = JSON.parse(config.match(/"fallbackDomains":(\[[^\]]*\])/)?.[1] || '[]')
        .filter(d => typeof d === 'string' && /^[a-z0-9-]+(?:\.[a-z0-9-]+)+$/i.test(d));
    } catch (_) {}
    const domains = [...new Set([...fallback, 'doppiocdn.org'])];
    this.store.set('hlsDomains', {at: Date.now(), domains});
    return domains;
  },
  async videos(value) {
    const id = this.validId(value), cached = this.cachedRoom(id);
    const stream = cached ? cached.stream : String((await this.room(value)).cam.streamName || id);
    if(!/^\d{6,12}$/.test(stream)) throw Park.error('PARSE','直播数据无效');
    // 原站列表给出的播放主机优先，其次是原站配置的备用域。
    let current = '';
    try { const u = new URL(cached?.hls || ''); if (u.protocol === 'https:' && /^[a-z0-9.-]+$/i.test(u.hostname)) current = u.hostname; } catch (_) {}
    const hosts = [...new Set([current, ...(await this.hlsDomains()).map(domain => 'edge-hls.' + domain)].filter(Boolean))];
    // 原站原生播放器的公开协议参数；主清单会将它传给各清晰度。同名线路是镜像，应用按顺序取第一个可用的。
    return hosts.map((host, index) => ({
      url:'https://'+host+'/hls/'+stream+'/master/'+stream+'_auto.m3u8?pkey=B0p93vi8Uj6AYyZb',
      format:'hls',label:'直播',preferred:index===0,headers:{Referer:this.BASE+'/'},
    }));
  }
});
