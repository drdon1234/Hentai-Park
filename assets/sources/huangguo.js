/*
 * 黄果短剧：列表采用站点当前分类 API 与服务端渲染页面。
 * 分集目录来自真实的 data-ep-id 链接；epPlaySrcs 只预载邻集，不是完整目录。
 * 播放地址带时效签名，每次播放重新读取指定分集页面，不缓存媒体地址。
 */
Park.register({
  i18n: {
    "zh-Hant": {"AI 换脸": "AI 換臉", "黄果短剧": "黃果短劇", "黄果短剧作品不存在": "黃果短劇作品不存在", "黄果短剧作品或分集不存在": "黃果短劇作品或分集不存在", "黄果短剧分类无效": "黃果短劇分類無效", "黄果短剧分集不存在": "黃果短劇分集不存在", "黄果短剧列表无效": "黃果短劇清單無效", "黄果短剧列表解析失败": "黃果短劇清單解析失敗", "黄果短剧列表请求失败": "黃果短劇清單請求失敗", "黄果短剧播放地址无效": "黃果短劇播放網址無效", "黄果短剧榜单无效": "黃果短劇榜單無效", "黄果短剧访问受限": "黃果短劇存取受限", "黄果短剧该分集使用暂不支持的播放方式": "黃果短劇此分集使用暫不支援的播放方式", "黄果短剧该分集暂无可用播放地址": "黃果短劇此分集暫無可用播放網址", "黄果短剧详情解析失败": "黃果短劇詳情解析失敗", "黄果短剧请求失败": "黃果短劇請求失敗", "黄果短剧需要登录后访问": "黃果短劇需要登入後存取"},
    "ja": {"AI 换脸": "AI顔交換", "黄果短剧": "黄果ショートドラマ", "黄果短剧作品不存在": "黄果ショートドラマの作品が見つかりません", "黄果短剧作品或分集不存在": "黄果ショートドラマの作品またはエピソードが見つかりません", "黄果短剧分类无效": "黄果ショートドラマのカテゴリが無効です", "黄果短剧分集不存在": "黄果ショートドラマのエピソードが見つかりません", "黄果短剧列表无效": "黄果ショートドラマの一覧が無効です", "黄果短剧列表解析失败": "黄果ショートドラマの一覧を解析できませんでした", "黄果短剧列表请求失败": "黄果ショートドラマの一覧を取得できませんでした", "黄果短剧播放地址无效": "黄果ショートドラマの再生URLが無効です", "黄果短剧榜单无效": "黄果ショートドラマのランキングが無効です", "黄果短剧访问受限": "黄果ショートドラマへのアクセスが制限されています", "黄果短剧该分集使用暂不支持的播放方式": "この黄果ショートドラマのエピソードの再生方式には現在対応していません", "黄果短剧该分集暂无可用播放地址": "この黄果ショートドラマのエピソードには再生可能なURLがありません", "黄果短剧详情解析失败": "黄果ショートドラマの詳細を解析できませんでした", "黄果短剧请求失败": "黄果ショートドラマへのリクエストに失敗しました", "黄果短剧需要登录后访问": "黄果ショートドラマにアクセスするにはログインが必要です"},
    "ko": {"AI 换脸": "AI 얼굴 교체", "黄果短剧": "황궈 숏드라마", "黄果短剧作品不存在": "황궈 숏폼 드라마 작품을 찾을 수 없습니다", "黄果短剧作品或分集不存在": "황궈 숏폼 드라마 작품 또는 회차를 찾을 수 없습니다", "黄果短剧分类无效": "황궈 숏폼 드라마 카테고리가 올바르지 않습니다", "黄果短剧分集不存在": "황궈 숏폼 드라마 회차를 찾을 수 없습니다", "黄果短剧列表无效": "황궈 숏폼 드라마 목록이 올바르지 않습니다", "黄果短剧列表解析失败": "황궈 숏폼 드라마 목록을 분석하지 못했습니다", "黄果短剧列表请求失败": "황궈 숏폼 드라마 목록 요청에 실패했습니다", "黄果短剧播放地址无效": "황궈 숏폼 드라마 재생 주소가 올바르지 않습니다", "黄果短剧榜单无效": "황궈 숏폼 드라마 순위가 올바르지 않습니다", "黄果短剧访问受限": "황궈 숏폼 드라마 접속이 제한되었습니다", "黄果短剧该分集使用暂不支持的播放方式": "이 황궈 숏폼 드라마 회차의 재생 방식은 아직 지원되지 않습니다", "黄果短剧该分集暂无可用播放地址": "이 황궈 숏폼 드라마 회차에는 재생 가능한 주소가 없습니다", "黄果短剧详情解析失败": "황궈 숏폼 드라마 상세 정보를 분석하지 못했습니다", "黄果短剧请求失败": "황궈 숏폼 드라마 요청에 실패했습니다", "黄果短剧需要登录后访问": "황궈 숏폼 드라마에 접속하려면 로그인해야 합니다"},
    "en": {"AI 换脸": "AI face swaps", "黄果短剧": "Huangguo Shorts", "黄果短剧作品不存在": "Huangguo work not found", "黄果短剧作品或分集不存在": "Huangguo work or episode not found", "黄果短剧分类无效": "Invalid Huangguo category", "黄果短剧分集不存在": "Huangguo episode not found", "黄果短剧列表无效": "Invalid Huangguo list", "黄果短剧列表解析失败": "Could not parse the Huangguo list", "黄果短剧列表请求失败": "Could not fetch the Huangguo list", "黄果短剧播放地址无效": "Invalid Huangguo playback URL", "黄果短剧榜单无效": "Invalid Huangguo chart", "黄果短剧访问受限": "Access to Huangguo Shorts is restricted", "黄果短剧该分集使用暂不支持的播放方式": "This Huangguo episode uses an unsupported playback method", "黄果短剧该分集暂无可用播放地址": "No playable URL is currently available for this Huangguo episode", "黄果短剧详情解析失败": "Could not parse Huangguo details", "黄果短剧请求失败": "Huangguo request failed", "黄果短剧需要登录后访问": "Sign in to access Huangguo Shorts"},
    "es": {"AI 换脸": "Intercambio de rostros con IA", "黄果短剧": "Series cortas Huangguo", "黄果短剧作品不存在": "No se encontró la obra de Huangguo", "黄果短剧作品或分集不存在": "No se encontró la obra o el episodio de Huangguo", "黄果短剧分类无效": "Categoría de Huangguo no válida", "黄果短剧分集不存在": "No se encontró el episodio de Huangguo", "黄果短剧列表无效": "Lista de Huangguo no válida", "黄果短剧列表解析失败": "No se pudo interpretar la lista de Huangguo", "黄果短剧列表请求失败": "No se pudo obtener la lista de Huangguo", "黄果短剧播放地址无效": "URL de reproducción de Huangguo no válida", "黄果短剧榜单无效": "Clasificación de Huangguo no válida", "黄果短剧访问受限": "El acceso a Huangguo está restringido", "黄果短剧该分集使用暂不支持的播放方式": "Este episodio de Huangguo utiliza un método de reproducción no compatible", "黄果短剧该分集暂无可用播放地址": "No hay una URL de reproducción disponible para este episodio de Huangguo", "黄果短剧详情解析失败": "No se pudieron interpretar los detalles de Huangguo", "黄果短剧请求失败": "La solicitud a Huangguo falló", "黄果短剧需要登录后访问": "Inicia sesión para acceder a Huangguo"},
    "ru": {"AI 换脸": "Замена лиц с помощью ИИ", "黄果短剧": "Короткие сериалы Huangguo", "黄果短剧作品不存在": "Произведение Huangguo не найдено", "黄果短剧作品或分集不存在": "Произведение или серия Huangguo не найдены", "黄果短剧分类无效": "Недопустимая категория Huangguo", "黄果短剧分集不存在": "Серия Huangguo не найдена", "黄果短剧列表无效": "Недопустимый список Huangguo", "黄果短剧列表解析失败": "Не удалось разобрать список Huangguo", "黄果短剧列表请求失败": "Не удалось загрузить список Huangguo", "黄果短剧播放地址无效": "Недопустимая ссылка на видео Huangguo", "黄果短剧榜单无效": "Недопустимый рейтинг Huangguo", "黄果短剧访问受限": "Доступ к Huangguo ограничен", "黄果短剧该分集使用暂不支持的播放方式": "Эта серия Huangguo использует неподдерживаемый способ воспроизведения", "黄果短剧该分集暂无可用播放地址": "Для этой серии Huangguo пока нет доступной ссылки на видео", "黄果短剧详情解析失败": "Не удалось разобрать сведения Huangguo", "黄果短剧请求失败": "Ошибка запроса к Huangguo", "黄果短剧需要登录后访问": "Войдите, чтобы получить доступ к Huangguo"},
    "ar": {"AI 换脸": "تبديل الوجوه بالذكاء الاصطناعي", "黄果短剧": "مسلسلات Huangguo القصيرة", "黄果短剧作品不存在": "لم يُعثر على العمل في هوانغو", "黄果短剧作品或分集不存在": "لم يُعثر على العمل أو الحلقة في هوانغو", "黄果短剧分类无效": "تصنيف هوانغو غير صالح", "黄果短剧分集不存在": "لم يُعثر على الحلقة في هوانغو", "黄果短剧列表无效": "قائمة هوانغو غير صالحة", "黄果短剧列表解析失败": "تعذّر تحليل قائمة هوانغو", "黄果短剧列表请求失败": "تعذّر جلب قائمة هوانغو", "黄果短剧播放地址无效": "رابط تشغيل هوانغو غير صالح", "黄果短剧榜单无效": "قائمة ترتيب هوانغو غير صالحة", "黄果短剧访问受限": "الوصول إلى هوانغو مقيّد", "黄果短剧该分集使用暂不支持的播放方式": "تستخدم هذه الحلقة من هوانغو طريقة تشغيل غير مدعومة حاليًا", "黄果短剧该分集暂无可用播放地址": "لا يتوفر حاليًا رابط تشغيل لهذه الحلقة من هوانغو", "黄果短剧详情解析失败": "تعذّر تحليل تفاصيل هوانغو", "黄果短剧请求失败": "فشل الطلب إلى هوانغو", "黄果短剧需要登录后访问": "سجّل الدخول للوصول إلى هوانغو"},
  },
  key: 'huangguo',
  name: '黄果短剧',
  version: '0.0.7',
  type: 'video',
  category: 'aiDrama',
  color: '#F2AD24',
  description: 'AI短剧与漫剧，支持分类、排行、搜索和分集播放',
  homepage: 'https://huangguoai.com',
  domains: ['huangguoai.com'],
  language: 'zh',
  linkPatterns: ['huangguoai\\.com/(?:video|detail)/(\\d+)(?:/|[?#]|$)'],
  idPattern: '^(\\d+)$',
  imageHeaders: { Referer: 'https://huangguoai.com/' },
  imageDecrypt: {
    type: 'aes-cbc', key: 'f5d965df75336270', iv: '97b60394abc2fbe1',
    domains: ['pic.drleao.cn'],
  },
  network: { mode: 'native' },
  media: {
    mode: 'native', scope: 'session', origin: 'https://huangguoai.com',
    domains: [
      'yd-hls.hzjvlo.cn', 'tp1.drleao.cn', 'tp2.drleao.cn', 'tp3.drleao.cn',
      'tp4.drleao.cn', 'tp5.drleao.cn', 'tp6.drleao.cn', 'tp7.drleao.cn', 'tp8.drleao.cn',
    ],
  },
  defaultFeed: 'recommend',
  feeds: [
    { key: 'recommend', label: '推荐' },
    { key: 'latest', label: '最新' },
    {
      key: 'category', label: '分类', options: [
        {
          key: 'category', label: '类型', type: 'select', default: 'ai-duanju',
          values: [
            { value: 'ai-duanju', label: 'AI短剧' },
            { value: 'ai-manju', label: 'AI 漫剧' },
            { value: 'ai-huanlian', label: 'AI 换脸' },
            { value: 'ai-mogai', label: 'AI 魔改' },
          ],
        },
      ],
    },
    {
      key: 'ranking', label: '排行榜', options: [
        {
          key: 'ranking', label: '榜单', type: 'select', default: 'hot',
          values: [
            { value: 'hot', label: '热门榜' },
            { value: 'recommend', label: '推荐榜' },
            { value: 'potential', label: '潜力榜' },
          ],
        },
      ],
    },
  ],
  searchHint: '搜索作品名、标签或作者',

  BASE: 'https://huangguoai.com',
  COVER_ASPECT: 374 / 420,

  absolute(value) {
    if (!value || typeof value !== 'string') return '';
    try {
      const url = new URL(value, this.BASE);
      return /^https?:$/.test(url.protocol) ? url.href : '';
    } catch (_) {
      return '';
    }
  },

  cleanText(node) {
    if (!node) return '';
    const copy = node.cloneNode(true);
    for (const hidden of copy.querySelectorAll('.sr-only')) hidden.remove();
    return Park.html.text(copy);
  },

  pageNumber(value) {
    const page = Number(value);
    return Number.isSafeInteger(page) && page > 0 ? page : 1;
  },

  workId(value) {
    const id = String(value || '');
    if (!/^[1-9]\d*$/.test(id)) throw Park.error('NOT_FOUND', '黄果短剧作品不存在');
    return id;
  },

  async request(path, params) {
    const res = await this.http.get(this.BASE + path, {
      params, headers: { Referer: this.BASE + '/', 'Cache-Control': 'no-cache' },
    });
    if (res.status === 401) throw Park.error('LOGIN_REQUIRED', '黄果短剧需要登录后访问');
    if (res.status === 403) throw Park.error('BLOCKED', '黄果短剧访问受限');
    if (res.status === 404) throw Park.error('NOT_FOUND', '黄果短剧作品或分集不存在');
    if (!res.ok) throw Park.error('HTTP', '黄果短剧请求失败', { status: res.status });
    return res;
  },

  async document(path, params) {
    const res = await this.request(path, params);
    return Park.html.parse(res.body);
  },

  parseCards(root, ranking = false) {
    if (!root) return [];
    const seen = new Set();
    const items = [];
    for (const card of root.querySelectorAll(ranking ? '.hg-rank-item' : '.hg-drama-card')) {
      const anchor = card.querySelector(ranking ? '.hg-rank-item__cover' : '.hg-drama-card__cover-link');
      const match = /\/(?:video|detail)\/(\d+)(?:\/|$)/.exec(anchor && anchor.getAttribute('href') || '');
      const img = anchor && anchor.querySelector('img');
      if (!match || !img || seen.has(match[1])) continue;
      const title = this.cleanText(card.querySelector(ranking ? '.hg-rank-item__title' : '.hg-drama-card__title')) || img.getAttribute('alt') || '';
      if (!title) continue;
      seen.add(match[1]);
      const width = Number(img.getAttribute('width'));
      const height = Number(img.getAttribute('height'));
      const item = {
        id: match[1], title,
        cover: this.absolute(img.getAttribute('data-src') || img.getAttribute('src')),
        coverAspect: width > 0 && height > 0 ? width / height : this.COVER_ASPECT,
        subtitle: this.cleanText(card.querySelector('.hg-drama-card__episode')),
      };
      const rating = parseFloat(this.cleanText(card.querySelector('.hg-drama-card__score')));
      if (rating > 0) item.rating = rating;
      items.push(item);
    }
    return items;
  },

  parseList(doc, page, ranking = false) {
    // 页头的搜索建议也有卡片，必须限定到主内容，空搜索才不会返回推荐作品。
    const main = doc.querySelector('main');
    if (!main || !main.querySelector('.hg-list-page, .hg-card-grid, .hg-rank-list')) {
      throw Park.error('PARSE', '黄果短剧列表解析失败');
    }
    const items = this.parseCards(main, ranking);
    let totalPages = page;
    let hasNext = false;
    for (const a of main.querySelectorAll('.hg-pager a[href]')) {
      const href = a.getAttribute('href') || '';
      const match = /\/(\d+)\/?(?:[?#].*)?$/.exec(href) || /[?&]page=(\d+)/.exec(href);
      if (match) {
        const target = Number(match[1]);
        totalPages = Math.max(totalPages, target);
        if (target > page) hasNext = true;
      }
      if (a.getAttribute('rel') === 'next') hasNext = true;
    }
    return { items, page, totalPages, hasNext: items.length > 0 && hasNext };
  },

  async categoryPage(category, page) {
    if (!['ai-duanju', 'ai-manju', 'ai-huanlian', 'ai-mogai'].includes(category)) {
      throw Park.error('CONFIG', '黄果短剧分类无效');
    }
    const res = await this.request('/api/videos/category/' + category, { sort: 'hot', page, size: 20 });
    let payload;
    try { payload = JSON.parse(res.body); } catch (_) {
      throw Park.error('PARSE', '黄果短剧列表解析失败');
    }
    if (Number(payload.status) !== 1) {
      const message = String(payload.msg || '');
      if (/登录|登入|login|unauthorized/i.test(message)) throw Park.error('LOGIN_REQUIRED', '黄果短剧需要登录后访问');
      if (/权限|会员|付费|受限|forbidden/i.test(message)) throw Park.error('BLOCKED', '黄果短剧访问受限');
      throw Park.error('PARSE', '黄果短剧列表请求失败');
    }
    const data = payload.data;
    if (!data || !Array.isArray(data.items) || !data.pagination || Number(data.pagination.page) !== page) {
      throw Park.error('PARSE', '黄果短剧列表解析失败');
    }
    const items = data.items.filter(it => it && /^\d+$/.test(String(it.id)) && it.title).map(it => ({
      id: String(it.id), title: String(it.title), cover: this.absolute(it.cover),
      coverAspect: this.COVER_ASPECT,
      duration: typeof it.duration === 'string' ? it.duration : '',
      rating: Number(it.score) || null,
      likes: Number(it.like_count) || null,
      uploaded: it.created_at || '',
    }));
    const totalPages = Math.max(0, Number(data.pagination.pages) || 0);
    return { items, page, totalPages, total: Number(data.pagination.total) || 0, hasNext: page < totalPages };
  },

  async feed(key, req = {}) {
    const page = this.pageNumber(req.page);
    const options = req.options || {};
    if (key === 'category') return this.categoryPage(options.category || 'ai-duanju', page);
    if (key === 'ranking') {
      // 当前站点榜单为固定条目，没有下一页；不能反复把第一页当作下一页返回。
      if (page > 1) return { items: [], page, totalPages: 1, hasNext: false };
      const ranking = options.ranking || 'hot';
      if (!['hot', 'recommend', 'potential'].includes(ranking)) throw Park.error('CONFIG', '黄果短剧榜单无效');
      return this.parseList(await this.document('/ranks/' + ranking + '/'), page, true);
    }
    const route = { recommend: 'recommend', latest: 'newest' }[key];
    if (!route) throw Park.error('CONFIG', '黄果短剧列表无效');
    return this.parseList(await this.document('/' + route + (page > 1 ? '/' + page : '') + '/'), page);
  },

  async search(req = {}) {
    const page = this.pageNumber(req.page);
    const keyword = String(req.keyword || '').trim();
    if (!keyword) return { items: [], page, totalPages: 0, hasNext: false };
    return this.parseList(await this.document('/search/', { keyword, page }), page);
  },

  initialData(doc, id) {
    const node = doc.querySelector('#videoInitialData');
    if (!node) throw Park.error('PARSE', '黄果短剧详情解析失败');
    let data;
    try { data = JSON.parse(node.textContent || ''); } catch (_) {
      throw Park.error('PARSE', '黄果短剧详情解析失败');
    }
    if (!data || String(data.id) !== id || !data.title) throw Park.error('NOT_FOUND', '黄果短剧作品不存在');
    return data;
  },

  episodes(doc, id) {
    const chapters = [];
    const seen = new Set();
    for (const a of doc.querySelectorAll('a[data-ep-id]')) {
      const ep = a.getAttribute('data-ep-id') || '';
      const match = /\/video\/(\d+)\/(?:ep-(\d+)\/?)?(?:[?#].*)?$/.exec(a.getAttribute('href') || '');
      if (!/^[1-9]\d*$/.test(ep) || !match || match[1] !== id || (match[2] || '1') !== ep || seen.has(ep)) continue;
      seen.add(ep);
      chapters.push({ id: ep, title: '第' + ep + '集' });
    }
    if (!chapters.length && doc.querySelector('[data-ep-id]')) {
      throw Park.error('PARSE', '黄果短剧详情解析失败');
    }
    return chapters.length ? chapters : null;
  },

  async detail(value) {
    const id = this.workId(value);
    const url = this.BASE + '/video/' + id + '/';
    const doc = await this.document('/video/' + id + '/');
    const data = this.initialData(doc, id);
    const names = Array.isArray(data.tags) ? data.tags : [];
    const tags = [...new Set(names.filter(name => typeof name === 'string' && name.trim()))].map(name => ({ name, keyword: name }));
    return {
      id, title: data.title, url,
      cover: this.absolute(data.coverSrc || data.posterSrc), coverAspect: this.COVER_ASPECT,
      authors: data.author ? [String(data.author)] : [],
      description: typeof data.description === 'string' ? data.description : '',
      views: Park.utils.parseCount(data.views || ''),
      likes: Number(data.likesNum) || null,
      uploaded: data.time || '',
      tags: tags.length ? [{ namespace: 'tag', label: '标签', tags }] : [],
      chapters: this.episodes(doc, id),
      related: this.parseCards(doc.querySelector('#related-grid, .hg-play__related')).filter(it => it.id !== id),
    };
  },

  async videos(value, episodeId = '_') {
    const id = this.workId(value);
    const ep = String(episodeId);
    if (ep !== '_' && !/^[1-9]\d*$/.test(ep)) throw Park.error('NOT_FOUND', '黄果短剧分集不存在');
    const path = '/video/' + id + '/' + (ep !== '_' && ep !== '1' ? 'ep-' + ep + '/' : '');
    const doc = await this.document(path);
    const data = this.initialData(doc, id);
    if (ep !== '_' && String(data.ep) !== ep) throw Park.error('NOT_FOUND', '黄果短剧分集不存在');
    // 只读取当前集地址，不从其他集或预览视频回退，避免播错集或把预告当正片。
    if (!data.videoSrc) throw Park.error('NOT_FOUND', '黄果短剧该分集暂无可用播放地址');
    const url = this.absolute(data.videoSrc);
    if (!url) throw Park.error('PARSE', '黄果短剧播放地址无效');
    if (data.videoApi || data.videoKey || data.videoIv) {
      throw Park.error('UNSUPPORTED', '黄果短剧该分集使用暂不支持的播放方式');
    }
    return [{
      quality: 0, label: '原画', url,
      headers: { Referer: this.BASE + path }, preferred: true,
      ...(/\.m3u8(?:[?#]|$)/i.test(url) ? { format: 'hls' } : {}),
    }];
  },
});

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"},{"key":"work","label":"作品连载","hint":"作品编号或详情链接"}]});
