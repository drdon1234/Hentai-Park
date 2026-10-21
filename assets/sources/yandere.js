/* yande.re：Moebooru JSON API，所有图片请求带站点 Referer。 */
Park.register({
  i18n: {
    "zh-Hant": {"成人插画图库，支持评分排序、搜索与原图": "成人插畫圖庫，支援評分排序、搜尋與原圖"}, ja: {"成人插画图库，支持评分排序、搜索与原图": "成人イラストギャラリー。評価順・検索・原寸画像に対応"}, ko: {"成人插画图库，支持评分排序、搜索与原图": "성인 일러스트 갤러리, 점수순 정렬·검색·원본 이미지 지원"}, en: {"成人插画图库，支持评分排序、搜索与原图": "Adult illustration gallery with score sorting, search and originals"}, es: {"成人插画图库，支持评分排序、搜索与原图": "Galería de ilustraciones para adultos con puntuación, búsqueda y originales"}, ru: {"成人插画图库，支持评分排序、搜索与原图": "Галерея иллюстраций для взрослых с рейтингом, поиском и оригиналами"}, ar: {"成人插画图库，支持评分排序、搜索与原图": "معرض رسوم للبالغين مع الترتيب والبحث والصور الأصلية"},
  },
  key: 'yandere', name: 'yande.re', version: '0.0.7', minAppVersion: '0.9.2', type: 'comic', category: 'illustration', language: 'en', color: '#6b7ea8',
  homepage: 'https://yande.re/', description: '成人插画图库，支持评分排序、搜索与原图', domains: ['yande.re'], network: {mode: 'native', vpnHint: true},
  imageHeaders: {Referer: 'https://yande.re/'},
  idPattern: '^\\d{1,12}$', defaultFeed: 'popular', feeds: [{key: 'popular', label: '热门', options: [
    {key: 'rating', label: '站点分级', default: 'safe', values: [{value: '', label: '全部'}, {value: 'safe', label: 'Safe'}, {value: 'questionable', label: 'Questionable'}, {value: 'explicit', label: 'Explicit'}]},
    {key: 'sort', label: '排序', default: 'score', values: [{value: 'score', label: '评分'}, {value: 'date', label: '最新'}]},
  ]}],
  searchFilters: [
    {key: 'rating', label: '站点分级', default: '', values: [{value: '', label: '全部'}, {value: 'safe', label: 'Safe'}, {value: 'questionable', label: 'Questionable'}, {value: 'explicit', label: 'Explicit'}]},
    {key: 'sort', label: '排序', default: '', values: [{value: '', label: '默认'}, {value: 'score', label: '评分'}, {value: 'date', label: '最新'}]},
  ],
  validId(v) { const id = String(v || ''); if (!/^\d{1,12}$/.test(id)) throw Park.error('NOT_FOUND', '图片编号无效'); return id; },
  async api(params) { const r = await this.http.get('https://yande.re/post.json', {params, headers: {Referer: 'https://yande.re/'}}); if (!r.ok) throw Park.error('HTTP', 'yande.re 请求失败', {status: r.status}); try { const d = r.json(); if (!Array.isArray(d)) throw 0; return d; } catch (_) { throw Park.error('PARSE', 'yande.re 返回的数据无效'); } },
  item(p) { const id = this.validId(p?.id), cover = String(p?.preview_url || p?.sample_url || ''), original = String(p?.file_url || p?.jpeg_url || ''); if (!cover || !original) return null; const tags = String(p.tags || '').split(/\s+/).filter(Boolean); return {id, title: tags.slice(0, 8).join(' ') || 'yande.re #' + id, cover, coverAspect: Number(p.preview_width) && Number(p.preview_height) ? Number(p.preview_width) / Number(p.preview_height) : 1, url: 'https://yande.re/post/show/' + id, pages: 1, description: 'rating:' + String(p.rating || 'unknown') + (Number.isFinite(Number(p.score)) ? '\nscore:' + p.score : ''), tags: tags.map(name => ({name, keyword: name}))}; },
  async listing(req = {}, feed = false) {
    const options = feed ? req.options : req.filters;
    const rating = String(options?.rating ?? (feed ? 'safe' : '')), sort = String(options?.sort ?? (feed ? 'score' : ''));
    if (!['', 'safe', 'questionable', 'explicit'].includes(rating) || !['', 'score', 'date'].includes(sort)) throw Park.error('CONFIG', '筛选参数无效');
    let words = String(feed ? '' : req.keyword || '').trim().split(/\s+/).filter(Boolean);
    if (rating) words = words.filter(w => !/^-?rating:/i.test(w));
    if (sort) words = words.filter(w => !/^-?order:/i.test(w));
    if (rating) words.push('rating:' + rating); if (sort) words.push('order:' + (sort === 'date' ? 'id' : 'score'));
    const page = Math.max(1, Math.floor(Number(req.page) || 1)), rows = await this.api({limit: 20, tags: words.join(' '), page});
    return {items: rows.map(x => this.item(x)).filter(Boolean), page, hasNext: rows.length >= 20};
  },
  async feed(key, req) { if (key !== 'popular') throw Park.error('CONFIG', '未知热门列表'); return this.listing(req, true); },
  async search(req) { return this.listing(req); },
  async detail(value) { const id = this.validId(value), rows = await this.api({tags: 'id:' + id, limit: 1}), item = rows.map(x => this.item(x)).find(Boolean); if (!item) throw Park.error('NOT_FOUND', '图片不存在'); return {...item, chapters: [{id: '_', title: '原图', count: 1}]}; },
  async chapter(value) { const d = await this.detail(value); const rows = await this.api({tags: 'id:' + d.id, limit: 1}), p = rows[0]; return {pages: [{url: String(p?.file_url || p?.jpeg_url || d.cover), width: Number(p?.width) || undefined, height: Number(p?.height) || undefined}]}; },
});
