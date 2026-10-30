Park.register({
  i18n: {
  "zh-Hant": {
    "直播": "直播",
    "直播间暂无可用播放地址": "直播間暫無可用播放位址",
    "公开直播间": "公開直播間",
    "直播间不存在": "直播間不存在",
    "直播间不存在或已下线": "直播間不存在或已下線",
    "直播请求失败": "直播請求失敗",
    "直播数据无效": "直播資料無效",
    "未知直播列表": "未知直播列表",
    "直播分页参数无效": "直播分頁參數無效"
  },
  "en": {
    "直播": "Live",
    "直播间暂无可用播放地址": "No playable live stream is available",
    "公开直播间": "Public live rooms",
    "直播间不存在": "Live room not found",
    "直播间不存在或已下线": "Live room is offline or unavailable",
    "直播请求失败": "Live request failed",
    "直播数据无效": "Invalid live data",
    "未知直播列表": "Unknown live feed",
    "直播分页参数无效": "Invalid live pagination"
  },
  "ja": {
    "直播": "ライブ",
    "直播间暂无可用播放地址": "再生可能なライブ配信がありません",
    "公开直播间": "公開ライブ配信",
    "直播间不存在": "ライブ配信が見つかりません",
    "直播间不存在或已下线": "ライブ配信が終了したか見つかりません",
    "直播请求失败": "ライブ配信の取得に失敗しました",
    "直播数据无效": "ライブデータが無効です",
    "未知直播列表": "不明なライブ一覧",
    "直播分页参数无效": "ライブ一覧のページ指定が無効です"
  },
  "ko": {
    "直播": "라이브",
    "直播间暂无可用播放地址": "재생 가능한 라이브 방송이 없습니다",
    "公开直播间": "공개 라이브 방송",
    "直播间不存在": "라이브 방송을 찾을 수 없습니다",
    "直播间不存在或已下线": "라이브 방송이 종료되었거나 없습니다",
    "直播请求失败": "라이브 요청에 실패했습니다",
    "直播数据无效": "라이브 데이터가 올바르지 않습니다",
    "未知直播列表": "알 수 없는 라이브 목록",
    "直播分页参数无效": "라이브 페이지 매개변수가 올바르지 않습니다"
  },
  "es": {
    "直播": "Directo",
    "直播间暂无可用播放地址": "No hay una emisión reproducible disponible",
    "公开直播间": "Salas de emisión públicas",
    "直播间不存在": "Sala de directo no encontrada",
    "直播间不存在或已下线": "La sala no existe o está desconectada",
    "直播请求失败": "Error al solicitar el directo",
    "直播数据无效": "Datos de directo no válidos",
    "未知直播列表": "Lista de directos desconocida",
    "直播分页参数无效": "Paginación de directos no válida"
  },
  "ru": {
    "直播": "Эфир",
    "直播间暂无可用播放地址": "Нет доступного потока для воспроизведения",
    "公开直播间": "Открытые эфиры",
    "直播间不存在": "Эфир не найден",
    "直播间不存在或已下线": "Эфир недоступен или завершён",
    "直播请求失败": "Ошибка запроса эфира",
    "直播数据无效": "Некорректные данные эфира",
    "未知直播列表": "Неизвестный список эфиров",
    "直播分页参数无效": "Некорректные параметры страницы эфиров"
  },
  "ar": {
    "直播": "بث مباشر",
    "直播间暂无可用播放地址": "لا يوجد بث متاح للتشغيل",
    "公开直播间": "غرف بث عامة",
    "直播间不存在": "غرفة البث غير موجودة",
    "直播间不存在或已下线": "غرفة البث غير متاحة أو غير متصلة",
    "直播请求失败": "فشل طلب البث",
    "直播数据无效": "بيانات البث غير صالحة",
    "未知直播列表": "قائمة بث غير معروفة",
    "直播分页参数无效": "معلمات صفحات البث غير صالحة"
  }
},
  key: 'xlovecam', name: 'XloveCam', version: '0.0.8', minAppVersion: '0.9.2', type: 'video', category: 'live', language: 'en',
  chat: {domains: ['spg1-eu-nl.wlresources.com']},
  color: '#990000', description: '公开直播间', homepage: 'https://www.xlovecam.com/en/', domains: ['xlovecam.com'],
  network: {mode: 'native', origin: 'https://www.xlovecam.com', vpnHint: true},
  media: {mode: 'native', scope: 'session', origin: 'https://www.xlovecam.com', domains: ['wlresources.com']},
  imageHeaders: {Referer: 'https://www.xlovecam.com/en/'}, idPattern: '^[A-Za-z0-9_-]{2,80}$', defaultFeed: 'popular', feeds: [{key: 'popular', label: '热门', options: [
    {key: 'group', label: '分类', default: '10', dynamic: true, values: []},
    {key: 'category', label: '分类', default: '', dynamic: true, dependsOn: ['group'], values: []},
  ]}],
  async filterOptions(req) {
    if (req.scope !== 'feed' || req.feed !== 'popular') return [];
    const data = await this.page('/en/'), groups = data?.online?.filter?.data;
    if (!Array.isArray(groups)) throw Park.error('PARSE', '直播数据无效');
    const usable = g => Array.isArray(g.itemList) && g.itemList.some(x => /^\/en\/models\/[a-z0-9-]+\/$/.test(x.uri));
    if (req.filter === 'group') return groups.filter(usable).map(g => ({value: String(g.id), label: g.title}));
    if (req.filter !== 'category') return [];
    const group = groups.find(g => String(g.id) === String(req.values?.group || '10'));
    return [{value: '', label: '全部'}, ...(group?.itemList || []).filter(x => /^\/en\/models\/[a-z0-9-]+\/$/.test(x.uri)).map(x => ({value: x.uri, label: x.title}))];
  },
  parse(html) { const m = String(html).match(/<script[^>]+id=["']app-data["'][^>]*>([\s\S]*?)<\/script>/i); if (!m) throw Park.error('PARSE', '直播数据无效'); try { return JSON.parse(m[1]); } catch (_) { throw Park.error('PARSE', '直播数据无效'); } },
  item(x) { const id = String(x?.nickname || ''), cover = String(x?.profileImg || ''), hls = String(x?.hlsPlaylist || ''); if (!/^[A-Za-z0-9_-]{2,80}$/.test(id) || !cover || !hls || x.showType !== 1) return null; return {id, title: id, cover, coverAspect: 4/3, rating: Number(x.rating) || undefined, url: 'https://www.xlovecam.com/en/model/' + encodeURIComponent(id.toLowerCase()) + '/', mediaKind: 'video', chapters: null}; },
  async page(path) { const r = await this.http.get('https://www.xlovecam.com' + path, {timeout: 30000}); if (!r.ok) throw Park.error('HTTP', '直播请求失败', {status: r.status}); return this.parse(r.body); },
  rows(data) { const rows = data?.online?.performerList?.performerList; if (!Array.isArray(rows)) throw Park.error('PARSE', '直播数据无效'); return rows.map(x => this.item(x)).filter(Boolean); },
  async feed(key, req = {}) {
    if (key !== 'popular') throw Park.error('CONFIG', '未知直播列表');
    const path = String(req.options?.category || '/en/');
    if (path !== '/en/' && !/^\/en\/models\/[a-z0-9-]{1,100}\/$/.test(path)) throw Park.error('CONFIG', '筛选参数无效');
    const page = Math.max(1, Number(req.page) || 1), data = await this.page(path);
    let result = data?.online?.performerList;
    if (page > 1) {
      let next; try { next = JSON.parse(String(req.cursor || '')); } catch (_) { throw Park.error('CONFIG', '直播分页参数无效'); }
      if (next?.path !== path || !Number.isInteger(next?.from) || next.from < 25 || next.from > 10000 || !Number.isInteger(next.time)) throw Park.error('CONFIG', '直播分页参数无效');
      delete next.path;
      const token = data?.Config?.csrfProtectionToken;
      if (typeof token !== 'string' || !token) throw Park.error('PARSE', '直播数据无效');
      const input = {config: {filter: data?.online?.filter?.selected || {}, nickname: '', favorite: 0, recent: 0, vip: 0, sort: {id: data?.online?.sort?.selected || 35}}, offset: {from: next.from, length: 25}, origin: 'btn-more', stat: 0, data: next, csrfProtectionToken: token};
      const pairs = [];
      function add(path, value) { if (value && typeof value === 'object') { for (const [k, v] of Object.entries(value)) add(path ? path + '[' + k + ']' : k, v); } else if (value !== undefined) pairs.push(encodeURIComponent(path) + '=' + encodeURIComponent(value == null ? '' : String(value))); }
      for (const [k, v] of Object.entries(input)) add(k, v);
      const r = await this.http.post('https://www.xlovecam.com/performerAction/onlineList/?x-req=' + page + '&x-off-s=' + next.from, {readOnly: true, body: pairs.join('&'), headers: {'Content-Type': 'application/x-www-form-urlencoded', 'X-Requested-With': 'XMLHttpRequest', Referer: 'https://www.xlovecam.com/en/'}, timeout: 30000});
      if (!r.ok) throw Park.error('HTTP', '直播请求失败', {status: r.status});
      try { result = r.json()?.content; } catch (_) { throw Park.error('PARSE', '直播数据无效'); }
    }
    if (!Array.isArray(result?.performerList)) throw Park.error('PARSE', '直播数据无效');
    const next = result.nextQuery, hasNext = result.moreItemAvailable === true && Number.isInteger(next?.from) && Number.isInteger(next?.time);
    return {items: result.performerList.map(x => this.item(x)).filter(Boolean), page, hasNext, cursor: hasNext ? JSON.stringify({path, from: next.from, time: next.time, off: next.off ?? null}) : null};
  },
  performer(data, id) { const p = data?.chat?.performerInfo?.performer || data?.bioPageData?.performer; if (!p || String(p.nickname || '').toLowerCase() !== id.toLowerCase()) return null; const stream = p.liveStreamInfo || p.streamInfo || {}; return {nickname: p.nickname, profileImg: p.profileImg || stream.profileImg, hlsPlaylist: stream.hlsPlaylist || p.hlsPlaylistFree, rating: stream.rating, showType: stream.showType ?? p.showType, online: p.online ?? p.isOnline}; },
  async detail(value) { const id = String(value || ''); if (!/^[A-Za-z0-9_-]{2,80}$/.test(id)) throw Park.error('NOT_FOUND', '直播间不存在'); const data = await this.page('/en/model/' + encodeURIComponent(id.toLowerCase()) + '/'); const x = this.performer(data, id); if (!x || x.showType !== 1 || !(x.online === 1 || x.online === true)) throw Park.error('NOT_FOUND', '直播间不存在或已下线'); const row = this.item(x) || {id, title: id, cover: String(x.profileImg || ''), url: 'https://www.xlovecam.com/en/model/' + encodeURIComponent(id.toLowerCase()) + '/', mediaKind: 'video', chapters: null}; return {...row, tags: [], description: ''}; },
  async liveChat(value) {
    const id = String(value || '');
    if (!/^[A-Za-z0-9_-]{2,80}$/.test(id)) throw Park.error('NOT_FOUND', '直播间不存在');
    const data = await this.page('/en/model/' + encodeURIComponent(id.toLowerCase()) + '/');
    const auth = data?.chat?.performerInfo?.performer?.rtmpWs;
    let target; try { target = new URL(auth?.websocketUrl); } catch (_) { throw Park.error('PARSE', '直播数据无效'); }
    if (target.protocol !== 'wss:' || !this.chat.domains.includes(target.hostname) || !Park.url.parse(target.href.replace(/^wss:/, 'https:'), undefined, this.chat.domains) ||
        !['nickname','tokenAccessControl','securityPayload','channelToJoin'].every(key => typeof auth[key] === 'string' && auth[key])) throw Park.error('PARSE', '直播数据无效');
    return {transport: 'websocket', url: target.href, state: {auth: {nickname: auth.nickname, tokenAccessControl: auth.tokenAccessControl, securityPayload: auth.securityPayload, channelToJoin: auth.channelToJoin}}};
  },
  liveChatEvent(state, event) {
    const out = {state: {...state}, send: [], messages: []};
    if (event.type === 'open') {
      const a = state.auth;
      if (!a) return {...out, error: true};
      out.send.push(JSON.stringify({cmd: 1, argList: [a.nickname, a.tokenAccessControl, a.securityPayload, a.channelToJoin], msg: 'WebChatSocket/1.0', tag: 256}));
      out.state = {channel: a.channelToJoin, authenticated: false};
      return out;
    }
    if (event.type !== 'message' || typeof event.data !== 'string') return out;
    for (const line of event.data.split('\n').filter(Boolean).slice(0, 100)) {
      let m; try { m = JSON.parse(line); } catch (_) { continue; }
      if (m.cmd === 1 && !out.state.authenticated && Array.isArray(m.argList) && m.argList.length) {
        out.state.authenticated = true;
        out.send.push(JSON.stringify({cmd: 4, argList: [out.state.channel], tag: 512}));
      } else if (m.cmd === 4) out.connected = true;
      else if (m.cmd === 11) out.send.push(JSON.stringify({cmd: 12, tag: m.tag, msg: m.msg}));
      else if (m.cmd === 13) out.error = true;
      else if (m.cmd === 2 && !m.argIntList?.[0] && typeof m.msg === 'string' && m.msg.trim() && typeof m.uid === 'string' && typeof m.prefix === 'string' && m.prefix.includes('!')) {
        if (out.state.channel && m.argList?.[0] !== out.state.channel) continue;
        out.messages.push({id: m.uid, text: m.msg.slice(0, 2000), author: m.prefix.split('!')[0].slice(0, 100), isHistory: Number(m.ts) > 0});
      }
    }
    return out;
  },
  publicUrl(value, base = this.BASE) {
    // CDN 主机会更换，只要求是公网 HTTPS 地址；作品身份仍按站点域名校验。
    try { const url = new URL(String(value).trim(), base); return Park.url.parse(url.href, base, [url.hostname]); } catch (_) { return null; }
  },
  async videos(value) { const id = String(value || ''); if (!/^[A-Za-z0-9_-]{2,80}$/.test(id)) throw Park.error('NOT_FOUND', '直播间不存在'); const data = await this.page('/en/model/' + encodeURIComponent(id.toLowerCase()) + '/'); const x = this.performer(data, id); const url = this.publicUrl(x?.hlsPlaylist, 'https://www.xlovecam.com')?.href; if (!url || x.showType !== 1 || !(x.online === 1 || x.online === true)) throw Park.error('UNSUPPORTED', '直播间暂无可用播放地址'); return [{url, format: 'hls', label: '直播', preferred: true, headers: {Referer: 'https://www.xlovecam.com/en/'}}]; },
});

