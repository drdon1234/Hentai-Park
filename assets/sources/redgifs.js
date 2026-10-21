/* RedGifs：临时授权 API，令牌只保存在当前运行时内存。 */
Park.register({
  i18n: {
    "zh-Hant": {"短视频热门、搜索与 MP4 播放": "短影片熱門、搜尋與 MP4 播放"}, ja: {"短视频热门、搜索与 MP4 播放": "ショート動画の人気・検索・MP4再生"}, ko: {"短视频热门、搜索与 MP4 播放": "짧은 동영상 인기, 검색 및 MP4 재생"}, en: {"短视频热门、搜索与 MP4 播放": "Trending short videos, search and MP4 playback"}, es: {"短视频热门、搜索与 MP4 播放": "Vídeos cortos populares, búsqueda y reproducción MP4"}, ru: {"短视频热门、搜索与 MP4 播放": "Популярные короткие видео, поиск и воспроизведение MP4"}, ar: {"短视频热门、搜索与 MP4 播放": "مقاطع قصيرة رائجة مع البحث وتشغيل MP4"},
  },
  key: 'redgifs', name: 'RedGifs', version: '0.0.4', type: 'video', category: 'shortvideo', language: 'en',
  color: '#e52d27', homepage: 'https://www.redgifs.com/', description: '短视频热门、搜索与 MP4 播放',
  domains: ['redgifs.com'], network: {mode: 'native', vpnHint: true}, media: {mode: 'native', origin: 'https://www.redgifs.com', domains: ['redgifs.com']},
  imageNetwork: {mode: 'browser', origin: 'https://www.redgifs.com', domains: ['redgifs.com']},
  idPattern: '^[A-Za-z0-9]{4,32}$', defaultFeed: 'trending', feeds: [{key: 'trending', label: '热门', options: [{key: 'sort', label: '排序', default: 'trending', values: [{value: 'trending', label: '热门'}, {value: 'latest', label: '最新'}]}]},
    {key: 'categories', label: '标签', options: [
      {key: 'tagGroup', label: '索引', default: 'popular', dynamic: true, values: []},
      {key: 'tagRange', label: '范围', dynamic: true, dependsOn: ['tagGroup'], values: []},
      {key: 'tag', label: '标签', default: '', dynamic: true, dependsOn: ['tagGroup', 'tagRange'], values: []},
      {key: 'sort', label: '排序', default: 'trending', values: [{value: 'trending', label: '热门'}, {value: 'latest', label: '最新'}]},
    ]}],
  searchFilters: [{key: 'sort', label: '排序', default: 'trending', values: [{value: 'trending', label: '热门'}, {value: 'latest', label: '最新'}]}],
  token: null,
  async tagDirectory() {
    if (this.tagCache && Date.now() - this.tagCache.time < 300000) return this.tagCache.rows;
    const data = await this.http.json('https://api.redgifs.com/v1/tags');
    if (!Array.isArray(data?.tags)) throw Park.error('PARSE', '分类列表解析失败');
    const seen = new Set(), rows = [];
    for (const row of data.tags) {
      const name = String(row?.name || '').trim();
      if (!name || name.length > 100 || seen.has(name.toLowerCase())) continue;
      seen.add(name.toLowerCase()); rows.push({name, count: Number(row.count) || 0});
    }
    if (!rows.length) throw Park.error('PARSE', '未找到分类');
    this.tagCache = {time: Date.now(), rows};
    return rows;
  },
  async filterOptions(req) {
    if (req.scope !== 'feed' || req.feed !== 'categories') return [];
    const rows = await this.tagDirectory(), group = String(req.values?.tagGroup || 'popular');
    const bucket = name => /^[a-z]/i.test(name) ? name[0].toLowerCase() : '09';
    if (req.filter === 'tagGroup') {
      const groups = new Set(rows.map(row => bucket(row.name)));
      return [{value: 'popular', label: '热门'}, ...['09', ...'abcdefghijklmnopqrstuvwxyz'].filter(x => groups.has(x)).map(x => ({value: x, label: x === '09' ? '0–9 / #' : x.toUpperCase()}))];
    }
    if (!/^(popular|09|[a-z])$/.test(group)) throw Park.error('CONFIG', '筛选参数无效');
    const selected = group === 'popular' ? [...rows].sort((a, b) => b.count - a.count || a.name.localeCompare(b.name)) : rows.filter(row => bucket(row.name) === group).sort((a, b) => a.name.localeCompare(b.name));
    const count = Math.ceil(selected.length / 100);
    if (count > 500) throw Park.error('PARSE', '分类列表解析失败');
    if (req.filter === 'tagRange') return Array.from({length: count}, (_, i) => ({value: String(i + 1), label: String(i * 100 + 1) + '–' + Math.min((i + 1) * 100, selected.length)}));
    if (req.filter !== 'tag') return [];
    const range = Number(req.values?.tagRange);
    if (!Number.isInteger(range) || range < 1 || range > count) throw Park.error('CONFIG', '筛选参数无效');
    return [{value: '', label: '全部'}, ...selected.slice((range - 1) * 100, range * 100).map(row => ({value: row.name, label: row.name}))];
  },
  async auth() { const r = await this.http.get('https://api.redgifs.com/v2/auth/temporary', {timeout: 30000}); if (!r.ok) throw Park.error('HTTP', 'RedGifs 授权失败', {status: r.status}); const d = r.json(); if (!d?.token) throw Park.error('PARSE', 'RedGifs 返回的数据无效'); this.token = String(d.token); return this.token; },
  async api(path, params, retry = true) { if (!this.token) await this.auth(); const r = await this.http.get('https://api.redgifs.com' + path, {params, headers: {Authorization: 'Bearer ' + this.token}, timeout: 30000}); if (r.status === 401 && retry) { this.token = null; return this.api(path, params, false); } if (!r.ok) throw Park.error('HTTP', 'RedGifs 请求失败', {status: r.status}); try { return r.json(); } catch (_) { throw Park.error('PARSE', 'RedGifs 返回的数据无效'); } },
  item(g) { const id = String(g?.id || ''); const title = String(g?.title || g?.name || id).trim(); const cover = String(g?.urls?.thumbnail || g?.urls?.sd || ''); if (!/^[A-Za-z0-9]{4,32}$/.test(id) || !title || !/^https:\/\//i.test(cover)) return null; return {id, title, cover, coverAspect: Number(g.width) && Number(g.height) ? Number(g.width) / Number(g.height) : 1, duration: Number(g.duration) || 0, url: 'https://www.redgifs.com/watch/' + id}; },
  async listing(req = {}, keyword) { const page = Math.max(1, Number(req.page) || 1), order = String(req.options?.sort || 'trending'); if (!['trending', 'latest'].includes(order)) throw Park.error('CONFIG', '筛选参数无效'); const d = await this.api('/v2/gifs/search', {search_text: keyword === undefined ? '' : String(keyword).slice(0, 100), order, count: 20, page}); const rows = Array.isArray(d?.gifs) ? d.gifs : []; return {items: rows.map(x => this.item(x)).filter(Boolean), page, hasNext: Number(d?.pages || 0) > page || !!d?.cursor}; },
  async feed(key, req = {}) { if (!['trending', 'categories'].includes(key)) throw Park.error('CONFIG', '未知热门列表'); const tag = String(req.options?.tag || ''); if (key === 'categories' && tag && !(await this.tagDirectory()).some(row => row.name === tag)) throw Park.error('CONFIG', '筛选参数无效'); return this.listing(req, key === 'categories' ? tag : undefined); }, async search(req) { const q = String(req?.keyword || '').trim(); return this.listing({...req, options: req.filters}, q); },
  async detail(value) { const id = String(value || ''); if (!/^[A-Za-z0-9]{4,32}$/.test(id)) throw Park.error('NOT_FOUND', '短视频编号无效'); const d = await this.api('/v2/gifs/' + id), item = this.item(d?.gif || d); if (!item) throw Park.error('NOT_FOUND', '短视频不存在'); return {...item, description: String(d?.gif?.description || ''), chapters: null, tags: []}; },
  async videos(value) { const d = await this.api('/v2/gifs/' + String(value)); const g = d?.gif || d, urls = g?.urls || {}, out = []; for (const [label, url] of [['HD', urls.hd], ['SD', urls.sd]]) if (/^https:\/\//i.test(String(url))) out.push({url: String(url), format: 'mp4', label, headers: {Referer: 'https://www.redgifs.com/'}}); if (out[0]) out[0].preferred = true; if (!out.length) throw Park.error('UNSUPPORTED', '此短视频没有可用 MP4'); return out; },
});
