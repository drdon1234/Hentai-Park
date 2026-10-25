(function () {
'use strict';
const DAN_API = 'https://danbooru.donmai.us';
const DAN_UA = 'HentaiPark (Danbooru image source)';
const danImage = (value) => {
  if (typeof value !== 'string' || !value.trim()) return '';
  try { const url = new URL(value); return url.protocol === 'https:' && !url.username && !url.password && (!url.port || url.port === '443') && url.hostname === 'cdn.donmai.us' ? url.href : ''; } catch (_) { return ''; }
};
const ratingOf = rating => ({g:'safe',s:'sensitive',q:'r18',e:'r18'})[rating] || 'unknown';
const pageOf = value => Math.max(1, Math.floor(Number(value) || 1));
const ratingOption = {key: 'rating', label: '站点分级', default: '', values: [
  {value: '', label: '全部'}, {value: 'g', label: 'General'}, {value: 's', label: 'Sensitive'},
  {value: 'q', label: 'Questionable'}, {value: 'e', label: 'Explicit'},
]};
const sortOption = {key: 'sort', label: '排序', default: '', values: [
  {value: '', label: '默认'}, {value: 'date', label: '最新'}, {value: 'score', label: '评分'},
]};
function filterTags(keyword, filters = {}) {
  const rating = String(filters.rating || ''), sort = String(filters.sort || '');
  if (!['', 'g', 's', 'q', 'e'].includes(rating) || !['', 'date', 'score'].includes(sort)) {
    throw Park.error('CONFIG', '筛选参数无效');
  }
  let words = String(keyword || '').trim().split(/\s+/).filter(Boolean);
  if (rating) words = words.filter(word => !/^-?rating:/i.test(word));
  if (sort) words = words.filter(word => !/^-?order:/i.test(word));
  if (rating) words.push('rating:' + rating);
  if (sort) words.push('order:' + (sort === 'date' ? 'id_desc' : 'score'));
  return words.join(' ');
}
const idOf = value => { const id=String(value); if (!/^[1-9]\d{0,11}$/.test(id)) throw Park.error('NOT_FOUND','内容不存在或已被删除'); return id; };
const tagsFrom = (post) => {
  const groups = [['artist', '画师', 'tag_string_artist'], ['copyright', '作品', 'tag_string_copyright'], ['character', '角色', 'tag_string_character'], ['general', '标签', 'tag_string_general']];
  return [{namespace:'rating',label:'原站分级',tags:[{name:'rating:'+post.rating,keyword:'rating:'+post.rating}]}, ...groups.map(([namespace, label, key]) => ({ namespace, label, tags: String(post[key] || '').split(/\s+/).filter(Boolean).map(name => ({ name: name.replace(/_/g, ' '), keyword: name })) })).filter(group => group.tags.length)];
};
const readable = post => !post.is_deleted && !post.is_banned && ['jpg','jpeg','png','gif','webp','avif'].includes(post.file_ext) && !!post.file_url;
const postItem = (post) => {
  if (!post || !post.id) throw Park.error('PARSE', 'Danbooru 返回无效数据');
  const cover = danImage(post.preview_file_url || post.large_file_url || post.file_url);
  if (!cover) throw Park.error('PARSE', 'Danbooru 返回无效数据');
  const characters = String(post.tag_string_character || '').split(/\s+/).filter(Boolean);
  const copyright = String(post.tag_string_copyright || '').split(/\s+/).filter(Boolean);
  return {
    id: idOf(post.id), title: characters.concat(copyright).map(name=>name.replace(/_/g,' ')).join('、') || 'Danbooru ' + post.id,
    cover, url: DAN_API + '/posts/' + post.id,
    subtitle: 'rating:' + post.rating, likes: Number(post.fav_count) || 0, contentRating: ratingOf(post.rating), coverRating: ratingOf(post.rating),
    coverAspect: post.image_width && post.image_height ? post.image_width/post.image_height : null,
    authors: String(post.tag_string_artist || '').split(/\s+/).filter(Boolean), uploaded: post.created_at || '',
    tags: tagsFrom(post), pages: 1,
  };
};

Park.register({
  i18n: {
    "zh-Hant": {
      "二次元图片图集，保留站内安全、擦边与 R18 分级": "二次元圖片圖集，保留站內安全、擦邊與 R18 分級",
      "支持原站标签及 rating:g/s/q/e；匿名搜索最多两个普通标签，标签内空格请用下划线": "支援原站標籤及 rating:g/s/q/e；匿名搜尋最多兩個一般標籤，標籤內空格請用底線",
      "原站分级": "原站分級",
      "画师": "繪師",
      "作品": "作品",
      "Danbooru 返回无效数据": "Danbooru 傳回無效資料",
      "未知 Danbooru 列表": "未知 Danbooru 清單",
      "Danbooru 帖子没有可用原图": "Danbooru 貼文沒有可用原圖"
    },
    "ja": {
      "二次元图片图集，保留站内安全、擦边与 R18 分级": "イラスト集。元サイトの一般・センシティブ・R18 区分を維持",
      "支持原站标签及 rating:g/s/q/e；匿名搜索最多两个普通标签，标签内空格请用下划线": "元サイトのタグと rating:g/s/q/e に対応。匿名検索は通常タグ 2 個まで。タグ内の空白は _ を使用",
      "原站分级": "元サイトの区分",
      "画师": "絵師",
      "作品": "作品",
      "Danbooru 返回无效数据": "Danbooru の応答データが無効です",
      "未知 Danbooru 列表": "不明な Danbooru リスト",
      "Danbooru 帖子没有可用原图": "Danbooru の投稿に利用可能な原寸画像がありません"
    },
    "ko": {
      "二次元图片图集，保留站内安全、擦边与 R18 分级": "애니메이션 이미지 갤러리, 원본 사이트의 일반·민감·R18 등급 유지",
      "支持原站标签及 rating:g/s/q/e；匿名搜索最多两个普通标签，标签内空格请用下划线": "원본 태그와 rating:g/s/q/e 지원. 익명 검색은 일반 태그 두 개까지, 태그의 공백은 밑줄 사용",
      "原站分级": "원본 사이트 등급",
      "画师": "일러스트레이터",
      "作品": "작품",
      "Danbooru 返回无效数据": "Danbooru가 잘못된 데이터를 반환했습니다",
      "未知 Danbooru 列表": "알 수 없는 Danbooru 목록",
      "Danbooru 帖子没有可用原图": "Danbooru 게시물에 사용 가능한 원본 이미지가 없습니다"
    },
    "en": {
      "二次元图片图集，保留站内安全、擦边与 R18 分级": "Illustration galleries preserving the original general, sensitive and R18 ratings",
      "支持原站标签及 rating:g/s/q/e；匿名搜索最多两个普通标签，标签内空格请用下划线": "Use original tags and rating:g/s/q/e. Anonymous searches allow two regular tags; use underscores within tags",
      "原站分级": "Original rating",
      "画师": "Artist",
      "作品": "Series",
      "Danbooru 返回无效数据": "Danbooru returned invalid data",
      "未知 Danbooru 列表": "Unknown Danbooru feed",
      "Danbooru 帖子没有可用原图": "This Danbooru post has no available original image"
    },
    "es": {
      "二次元图片图集，保留站内安全、擦边与 R18 分级": "Galerías de ilustraciones con las clasificaciones originales general, sensible y R18",
      "支持原站标签及 rating:g/s/q/e；匿名搜索最多两个普通标签，标签内空格请用下划线": "Usa etiquetas originales y rating:g/s/q/e. Las búsquedas anónimas admiten dos etiquetas normales; usa guiones bajos dentro de ellas",
      "原站分级": "Clasificación original",
      "画师": "Artista",
      "作品": "Obra",
      "Danbooru 返回无效数据": "Danbooru devolvió datos no válidos",
      "未知 Danbooru 列表": "Lista de Danbooru desconocida",
      "Danbooru 帖子没有可用原图": "Esta publicación de Danbooru no tiene una imagen original disponible"
    },
    "ru": {
      "二次元图片图集，保留站内安全、擦边与 R18 分级": "Галереи иллюстраций с исходными рейтингами: общие, чувствительные и R18",
      "支持原站标签及 rating:g/s/q/e；匿名搜索最多两个普通标签，标签内空格请用下划线": "Используйте теги сайта и rating:g/s/q/e. Анонимный поиск: до двух обычных тегов; пробелы внутри тега заменяйте подчёркиванием",
      "原站分级": "Рейтинг сайта",
      "画师": "Художник",
      "作品": "Произведение",
      "Danbooru 返回无效数据": "Danbooru вернул некорректные данные",
      "未知 Danbooru 列表": "Неизвестный список Danbooru",
      "Danbooru 帖子没有可用原图": "Для этой публикации Danbooru нет доступного оригинала"
    },
    "ar": {
      "二次元图片图集，保留站内安全、擦边与 R18 分级": "معارض رسوم تحافظ على تصنيفات الموقع الأصلية: عام وحساس وR18",
      "支持原站标签及 rating:g/s/q/e；匿名搜索最多两个普通标签，标签内空格请用下划线": "استخدم وسوم الموقع وrating:g/s/q/e. البحث المجهول يسمح بوسمين عاديين؛ استبدل المسافات داخل الوسم بشرطات سفلية",
      "原站分级": "تصنيف الموقع الأصلي",
      "画师": "الفنان",
      "作品": "العمل",
      "Danbooru 返回无效数据": "أعاد Danbooru بيانات غير صالحة",
      "未知 Danbooru 列表": "قائمة Danbooru غير معروفة",
      "Danbooru 帖子没有可用原图": "لا تتوفر صورة أصلية لهذا المنشور في Danbooru"
    }
  },
  key: 'danbooru', name: 'Danbooru', version: '0.0.6', minAppVersion: '0.9.2', apiVersion: 2,
  type: 'comic', category: 'illustration', color: '#3B73AF',
  homepage: DAN_API, description: '二次元图片图集，保留站内安全、擦边与 R18 分级',
  domains: ['donmai.us'], imageHeaders: {'User-Agent': DAN_UA},
  network: { vpnHint: true, headers: { 'User-Agent': DAN_UA, Accept: 'application/json' } },
  defaultFeed: 'popular', feeds: [{ key: 'popular', label: '热门' }, { key: 'latest', label: '最新' },
    {key: 'category', label: '分类', options: [ratingOption, {...sortOption, default: 'date'}]}],
  searchFilters: [ratingOption, sortOption],
  linkPatterns: ['danbooru\\.donmai\\.us/posts/(\\d+)'], idPattern: '^(\\d{1,12})$',
  searchHint: '支持原站标签及 rating:g/s/q/e；匿名搜索最多两个普通标签，标签内空格请用下划线',
  async listing(path, params, page) {
    const data = await this.http.json(DAN_API + path, { params: { ...params, page: pageOf(page), limit: 20 } });
    if (!Array.isArray(data)) throw Park.error('PARSE', 'Danbooru 返回无效数据');
    const items=[];
    for (const post of data) {
      if (!post || !Number.isSafeInteger(post.id) || !['g','s','q','e'].includes(post.rating)) throw Park.error('PARSE','Danbooru 返回无效数据');
      if (!readable(post)) continue;
      if (!danImage(post.file_url)) throw Park.error('PARSE','Danbooru 返回无效数据');
      items.push(postItem(post));
    }
    return {items,page:pageOf(page),hasNext:data.length>=20};
  },
  async feed(key, req) {
    if (key === 'category') return this.listing('/posts.json', {tags: filterTags('', {sort: 'date', ...req.options})}, req.page);
    if (!['popular', 'latest'].includes(key)) throw Park.error('CONFIG', '未知 Danbooru 列表');
    return this.listing('/posts.json', key === 'popular' ? {tags: 'order:rank'} : {}, req.page);
  },
  async search(req) {
    const keyword = filterTags(req.keyword, req.filters);
    if (!keyword) return { items: [], page: 1, hasNext: false };
    return this.listing('/posts.json', {tags:keyword}, req.page);
  },
  async post(value) {
    const id = idOf(value);
    const post = await this.http.json(DAN_API + '/posts/' + id + '.json');
    if (!post || String(post.id)!==id || !['g','s','q','e'].includes(post.rating)) throw Park.error('PARSE','Danbooru 返回无效数据');
    if (!readable(post)) throw Park.error('NOT_FOUND','Danbooru 帖子没有可用原图');
    if (!danImage(post.file_url)) throw Park.error('PARSE','Danbooru 返回无效数据');
    return post;
  },
  async comments(value, req = {}) {
    const id = idOf(value), page = pageOf(req.page);
    if (req.parentId) return {items: [], hasNext: false};
    const rows = await this.http.json(DAN_API + '/comments.json', {params: {
      group_by: 'comment', 'search[post_id]': id, limit: 20, page,
    }});
    if (!Array.isArray(rows) || rows.some(c => !c.id || String(c.post_id) !== id || typeof c.body !== 'string'))
      throw Park.error('PARSE', '评论数据无效');
    return {items: rows.filter(c => !c.is_deleted).map(c => ({id: String(c.id),
      author: {name: String(c.creator?.name || c.creator_name || c.creator_id || ''),
        url: c.creator_id ? DAN_API + '/users/' + c.creator_id : undefined},
      body: Park.comments.text(c.body), date: c.created_at, likes: Number(c.score) || 0,
    })).filter(c => c.body.length), hasNext: rows.length === 20};
  },

  async detail(id) {
    const post = await this.post(id);
    const item = postItem(post);
    return { ...item, chapters: null, description: ['rating:' + post.rating, Number.isFinite(post.score) ? 'score:' + post.score : '', String(post.source || '')].filter(Boolean).join('\n'), tags: tagsFrom(post) };
  },
  async chapter(id, chapterId) {
    if (chapterId && chapterId !== '_') throw Park.error('NOT_FOUND', '内容不存在或已被删除');
    const post = await this.post(id);
    const url = danImage(post.file_url);
    if (!url) throw Park.error('PARSE', 'Danbooru 帖子没有可用原图');
    return { pages: [{ url, width: Number(post.image_width) || undefined, height: Number(post.image_height) || undefined }] };
  },
});
})();
