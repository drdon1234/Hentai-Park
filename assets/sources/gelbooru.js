/* Gelbooru：HTML 列表与详情，原图取详情页 Original image 链接。 */
Park.register({
  i18n: {
    "zh-Hant": {"成人美图画廊，支持评分排序、搜索与原图": "成人美圖畫廊，支援評分排序、搜尋與原圖"}, ja: {"成人美图画廊，支持评分排序、搜索与原图": "成人イラストギャラリー。評価順・検索・原寸画像に対応"}, ko: {"成人美图画廊，支持评分排序、搜索与原图": "성인 이미지 갤러리, 점수순 정렬·검색·원본 이미지 지원"}, en: {"成人美图画廊，支持评分排序、搜索与原图": "Adult image gallery with score sorting, search and originals"}, es: {"成人美图画廊，支持评分排序、搜索与原图": "Galería de imágenes para adultos con puntuación, búsqueda y originales"}, ru: {"成人美图画廊，支持评分排序、搜索与原图": "Галерея изображений для взрослых с рейтингом, поиском и оригиналами"}, ar: {"成人美图画廊，支持评分排序、搜索与原图": "معرض صور للبالغين مع الترتيب والبحث والصور الأصلية"},
  },
  key: 'gelbooru', name: 'Gelbooru', version: '0.0.4', type: 'comic', category: 'illustration', language: 'en', color: '#657b83',
  homepage: 'https://gelbooru.com/', description: '成人美图画廊，支持评分排序、搜索与原图', domains: ['gelbooru.com'], network: {mode: 'native', vpnHint: true},
  imageNetwork: {mode: 'browser', origin: 'https://gelbooru.com', domains: ['gelbooru.com']}, imageHeaders: {Referer: 'https://gelbooru.com/'},
  idPattern: '^\\d{1,12}$', defaultFeed: 'popular', feeds: [{key: 'popular', label: '热门', options: [
    {key: 'rating', label: '站点分级', default: '', values: [{value: '', label: '全部'}, {value: 'general', label: 'General'}, {value: 'sensitive', label: 'Sensitive'}, {value: 'questionable', label: 'Questionable'}, {value: 'explicit', label: 'Explicit'}]},
    {key: 'sort', label: '排序', default: 'score', values: [{value: 'score', label: '评分'}, {value: 'date', label: '最新'}]},
  ]}],
  searchFilters: [
    {key: 'rating', label: '站点分级', default: '', values: [{value: '', label: '全部'}, {value: 'general', label: 'General'}, {value: 'sensitive', label: 'Sensitive'}, {value: 'questionable', label: 'Questionable'}, {value: 'explicit', label: 'Explicit'}]},
    {key: 'sort', label: '排序', default: '', values: [{value: '', label: '默认'}, {value: 'score', label: '评分'}, {value: 'date', label: '最新'}]},
  ], PAGE_SIZE: 42,
  validId(v) { const id = String(v || ''); if (!/^\d{1,12}$/.test(id)) throw Park.error('NOT_FOUND', '图片编号无效'); return id; },
  siteUrl(v) { try { const u = new URL(String(v), 'https://gelbooru.com/'); return u.protocol === 'https:' && (u.hostname === 'gelbooru.com' || u.hostname.endsWith('.gelbooru.com')) ? u : null; } catch (_) { return null; } },
  async page(req = {}, keyword) {
    const page = Math.max(1, Math.floor(Number(req.page) || 1)), pid = (page - 1) * this.PAGE_SIZE;
    const rating = String(req.options?.rating || ''), sort = String(req.options?.sort ?? (keyword === undefined ? 'score' : ''));
    if (!['', 'general', 'sensitive', 'questionable', 'explicit'].includes(rating) || !['', 'score', 'date'].includes(sort)) throw Park.error('CONFIG', '筛选参数无效');
    let words = String(keyword || '').trim().split(/\s+/).filter(Boolean);
    if (rating) words = words.filter(w => !/^-?rating:/i.test(w)); if (sort) words = words.filter(w => !/^-?sort:/i.test(w));
    if (rating) words.push('rating:' + rating); if (sort) words.push(sort === 'score' ? 'sort:score:desc' : 'sort:id:desc');
    const u = 'https://gelbooru.com/index.php?page=post&s=list&tags=' + encodeURIComponent(words.join(' ')) + '&pid=' + pid, r = this.http.ensureOk(await this.http.get(u));
    return {doc: Park.html.parse(r.body), url: u, page};
  },
  cards(doc) { const out = [], seen = new Set(); for (const a of doc.querySelectorAll('a[href*="page=post"][href*="s=view"][href*="id="]')) { const u = this.siteUrl(a.getAttribute('href')), id = u && u.searchParams.get('id'), img = a.querySelector('img'); if (!id || !img || seen.has(id)) continue; const src = img.getAttribute('src') || img.getAttribute('data-src') || '', cover = this.siteUrl(src); if (!cover) continue; seen.add(id); out.push({id, title: img.getAttribute('alt') || 'Gelbooru #' + id, cover: cover.href, coverAspect: Number(img.getAttribute('width')) && Number(img.getAttribute('height')) ? Number(img.getAttribute('width')) / Number(img.getAttribute('height')) : 1, url: 'https://gelbooru.com/index.php?page=post&s=view&id=' + id}); } return out; },
  async feed(key, req) { if (key !== 'popular') throw Park.error('CONFIG', '未知热门列表'); const x = await this.page(req); return {items: this.cards(x.doc), page: x.page, hasNext: this.cards(x.doc).length >= this.PAGE_SIZE, cursor: x.page + 1}; },
  async search(req) { const q = String(req?.keyword || '').trim(), x = await this.page(req, q), items = this.cards(x.doc); return {items, page: x.page, hasNext: items.length >= this.PAGE_SIZE}; },
  async detail(value) { const id = this.validId(value), u = 'https://gelbooru.com/index.php?page=post&s=view&id=' + id, r = await this.http.get(u); if (!r.ok) throw Park.error('NOT_FOUND', '图片不存在'); const doc = Park.html.parse(r.body), image = doc.querySelector('#image'); let original = ''; for (const a of doc.querySelectorAll('a[href]')) if (/original image/i.test(Park.html.text(a))) { original = a.getAttribute('href'); break; } const pageTitle = Park.html.text(doc.querySelector('title')) || ''; const title = (pageTitle.split(' - Image View')[0].trim() || Park.html.text(image) || 'Gelbooru #' + id); const cover = this.siteUrl(original || image?.getAttribute('src')); if (!cover) throw Park.error('NOT_FOUND', '图片不存在'); const rating = Park.html.text(doc.querySelector('#tag-sidebar, .tag-list')) || ''; return {id, title, cover: cover.href, url: u, pages: 1, description: rating, tags: [], chapters: [{id: '_', title: '原图', count: 1}]}; },
  async chapter(value) { const d = await this.detail(value); return {pages: [{url: d.cover, width: undefined, height: undefined}]}; },
});
