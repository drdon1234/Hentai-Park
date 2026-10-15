/*
 * Hanime1 — HTML site behind Cloudflare. All requests run inside the in-app browser engine
 * (network.mode = "browser") so they carry a real browser fingerprint and clearance cookies.
 * - Search: /search?query=&genre=&sort=&tags[]=&page=
 * - Watch page: title, artist, views/date, caption, tags, <source size> list, series playlist.
 * - /download?v= lists extra qualities (data-url). Video URLs carry a short-lived `secure` token,
 *   so they are always resolved right before playback / download.
 */
Park.register({
  i18n: {
    "zh-Hant": {"2D動畫": "2D動畫", "AI生成": "AI生成", "Hanime1 影片 {value0} 不存在或需要登录": "Hanime1 影片 {value0} 不存在或需要登入", "Hanime1 返回 HTTP {value0}": "Hanime1 返回 HTTP {value0}", "好评最多": "好評最多", "时长最长": "時長最長", "時長最長": "時長最長", "最新上传": "最新上傳", "最新上傳": "最新上傳", "本日排行": "本日排行", "本月排行": "本月排行", "本週排行": "本週排行", "没有找到可用的视频源（可能需要登录）": "沒有找到可用的影片源（可能需要登入）", "泡麵番": "泡麵番", "相关度": "相關度", "裏番": "裡番", "觀看次數": "觀看次數", "观看最多": "觀看最多", "讚好比例": "讚好比例", "里番、泡面番与 3D 动画，支持多清晰度在线播放与下载": "裡番、泡麵番與 3D 動畫，支援多清晰度線上播放與下載", "默认类型": "預設型別"},
    "ja": {"2D動畫": "2Dアニメーション", "AI生成": "AIの生成", "Hanime1 影片 {value0} 不存在或需要登录": "Hanime1 ビデオ {value0} が存在しないか、ログインが必要です", "Hanime1 返回 HTTP {value0}": "Hanime1はHTTP {value0}を返す", "好评最多": "最も好意的なコメント", "时长最长": "最長持続時間", "時長最長": "最長持続時間", "最新上传": "最新のアップロード", "最新上傳": "最新のアップロード", "本日排行": "今日のランキング", "本月排行": "今月のランキング", "本週排行": "今週のランキング", "没有找到可用的视频源（可能需要登录）": "利用可能なビデオ ソースが見つかりません (ログインが必要な場合があります)", "泡麵番": "即席麺", "相关度": "関連性", "裏番": "リパン", "觀看次數": "ビュー数", "观看最多": "最も閲覧されている", "讚好比例": "いいね比率", "里番、泡面番与 3D 动画，支持多清晰度在线播放与下载": "Ripa、インスタントラーメン、3Dアニメーションはマルチ解像度のオンライン再生とダウンロードをサポート", "默认类型": "デフォルトタイプ"},
    "ko": {"2D動畫": "2D 애니메이션", "AI生成": "AI 생성", "Hanime1 影片 {value0} 不存在或需要登录": "Hanime1 비디오 {value0}가 존재하지 않거나 로그인이 필요합니다", "Hanime1 返回 HTTP {value0}": "Hanime1은 HTTP {value0}를 반환합니다.", "好评最多": "가장 긍정적인 리뷰", "时长最长": "가장 긴 기간", "時長最長": "가장 긴 기간", "最新上传": "최신 업로드", "最新上傳": "최신 업로드", "本日排行": "오늘의 순위", "本月排行": "이번달 순위", "本週排行": "이번주 순위", "没有找到可用的视频源（可能需要登录）": "사용 가능한 비디오 소스를 찾을 수 없습니다(로그인이 필요할 수 있음)", "泡麵番": "인스턴트 국수", "相关度": "관련성", "裏番": "리판", "觀看次數": "조회수", "观看最多": "가장 많이 본", "讚好比例": "좋아요 비율", "里番、泡面番与 3D 动画，支持多清晰度在线播放与下载": "리반(Riban), 라면, 3D 애니메이션, 다중화질 온라인 재생 및 다운로드 지원", "默认类型": "기본 유형"},
    "en": {"2D動畫": "2D animation", "AI生成": "AI generation", "Hanime1 影片 {value0} 不存在或需要登录": "Hanime1 video {value0} does not exist or requires login", "Hanime1 返回 HTTP {value0}": "Hanime1 returns HTTP {value0}", "好评最多": "Most favorable comments", "时长最长": "The longest duration", "時長最長": "The longest duration", "最新上传": "Latest upload", "最新上傳": "Latest upload", "本日排行": "Today's ranking", "本月排行": "This month's ranking", "本週排行": "This week's ranking", "没有找到可用的视频源（可能需要登录）": "No available video source found (may require login)", "泡麵番": "Instant noodles", "相关度": "Relevance", "裏番": "Ripan", "觀看次數": "Number of views", "观看最多": "Most viewed", "讚好比例": "Like ratio", "里番、泡面番与 3D 动画，支持多清晰度在线播放与下载": "Ripa, instant noodles and 3D animation support multi-definition online playback and downloading", "默认类型": "Default type"},
    "es": {"2D動畫": "Animación 2D", "AI生成": "Generación de IA", "Hanime1 影片 {value0} 不存在或需要登录": "El vídeo de Hanime1 {value0} no existe o requiere iniciar sesión", "Hanime1 返回 HTTP {value0}": "Hanime1 devuelve HTTP {value0}", "好评最多": "Comentarios más favorables", "时长最长": "La duración más larga", "時長最長": "La duración más larga", "最新上传": "Última carga", "最新上傳": "Última carga", "本日排行": "Clasificación de hoy", "本月排行": "Clasificación de este mes", "本週排行": "Clasificación de esta semana", "没有找到可用的视频源（可能需要登录）": "No se encontró ninguna fuente de vídeo disponible (puede ser necesario iniciar sesión)", "泡麵番": "Fideos instantáneos", "相关度": "Relevancia", "裏番": "Ripán", "觀看次數": "Número de vistas", "观看最多": "Más vistos", "讚好比例": "Proporción similar", "里番、泡面番与 3D 动画，支持多清晰度在线播放与下载": "Ripa, fideos instantáneos y animación 3D admiten reproducción y descarga en línea multidefinición", "默认类型": "Tipo predeterminado"},
    "ru": {"2D動畫": "2D-анимация", "AI生成": "Генерация ИИ", "Hanime1 影片 {value0} 不存在或需要登录": "Видео Hanime1 {value0} не существует или требует входа в систему", "Hanime1 返回 HTTP {value0}": "Hanime1 возвращает HTTP {value0}", "好评最多": "Самые положительные комментарии", "时长最长": "Самая большая продолжительность", "時長最長": "Самая продолжительная продолжительность", "最新上传": "Последняя загрузка", "最新上傳": "Последняя загрузка", "本日排行": "Сегодняшний рейтинг", "本月排行": "Рейтинг этого месяца", "本週排行": "Рейтинг этой недели", "没有找到可用的视频源（可能需要登录）": "Доступный источник видео не найден (может потребоваться вход в систему)", "泡麵番": "Лапша быстрого приготовления", "相关度": "Актуальность", "裏番": "Рипан", "觀看次數": "Количество просмотров", "观看最多": "Самые просматриваемые", "讚好比例": "Подобное соотношение", "里番、泡面番与 3D 动画，支持多清晰度在线播放与下载": "Рипа, лапша быстрого приготовления и 3D-анимация поддерживают онлайн-воспроизведение и загрузку с несколькими разрешениями.", "默认类型": "Тип по умолчанию"},
    "ar": {"2D動畫": "الرسوم المتحركة ثنائية الأبعاد", "AI生成": "جيل الذكاء الاصطناعي", "Hanime1 影片 {value0} 不存在或需要登录": "فيديو Hanime1 {value0} غير موجود أو يتطلب تسجيل الدخول", "Hanime1 返回 HTTP {value0}": "Hanime1 يُرجع HTTP {value0}", "好评最多": "التعليقات الأكثر إيجابية", "时长最长": "أطول مدة", "時長最長": "أطول مدة", "最新上传": "آخر تحميل", "最新上傳": "آخر تحميل", "本日排行": "ترتيب اليوم", "本月排行": "ترتيب هذا الشهر", "本週排行": "ترتيب هذا الأسبوع", "没有找到可用的视频源（可能需要登录）": "لم يتم العثور على مصدر فيديو متاح (قد يتطلب تسجيل الدخول)", "泡麵番": "المكرونة سريعة التحضير", "相关度": "الصلة", "裏番": "ريبان", "觀看次數": "عدد المشاهدات", "观看最多": "الأكثر مشاهدة", "讚好比例": "نسبة الإعجاب", "里番、泡面番与 3D 动画，支持多清晰度在线播放与下载": "تدعم Ripa والمعكرونة سريعة التحضير والرسوم المتحركة ثلاثية الأبعاد التشغيل والتنزيل عبر الإنترنت متعدد التعريفات", "默认类型": "النوع الافتراضي"},
  },
  key: 'hanime1',
  name: 'Hanime1',
  version: '0.0.5',
  type: 'video',
  category: 'anime',
  color: '#E5355F',
  icon: 'https://hanime1.me/favicon.ico',
  description: '里番、泡面番与 3D 动画，支持多清晰度在线播放与下载',
  homepage: 'https://hanime1.me',
  language: 'zh',
  linkPatterns: ['hanime1\\.(?:me|com)/watch\\?v=(\\d+)'],
  idPattern: '^(\\d{1,8})$',
  idExample: '408297',
  imageHeaders: { Referer: 'https://hanime1.me/' },
  network: { mode: 'browser', origin: 'https://hanime1.me', vpnHint: true },

  settings: [
    {
      key: 'genre',
      type: 'select',
      label: '默认类型',
      default: '裏番',
      options: ['全部', '裏番', '泡麵番', 'Motion Anime', '3DCG', '2.5D', '2D動畫', 'AI生成', 'MMD', 'Cosplay'].map((g) => ({
        value: g,
        label: g,
      })),
    },
    {
      key: 'quality',
      type: 'select',
      label: '默认清晰度',
      default: '1080',
      options: [
        { value: '1080', label: '1080P' },
        { value: '720', label: '720P' },
        { value: '480', label: '480P' },
      ],
    },
  ],

  rankings: [{ key: 'ranking', label: '排行榜', category: 'anime', metric: '站内热度', feed: 'ranking' }],
  defaultFeed: 'ranking',
  feeds: [
    { key: 'latest', label: '最新上市' },
    {
      key: 'ranking',
      label: '排行榜',
      options: [
        {
          key: 'period',
          label: '周期',
          default: '本週排行',
          values: [
            { value: '本日排行', label: '日榜' },
            { value: '本週排行', label: '周榜' },
            { value: '本月排行', label: '月榜' },
            { value: '觀看次數', label: '总榜' },
          ],
        },
      ],
    },
    { key: 'uploads', label: '最新上传' },
  ],

  searchHint: '搜索作品名、标签或作者',
  searchFilters: [
    {
      key: 'genre',
      label: '类型',
      default: '全部', // searches span every genre; the setting only shapes the browse tabs
      values: [{ value: '@setting', label: '跟随设置' }].concat(
        ['全部', '裏番', '泡麵番', 'Motion Anime', '3DCG', '2.5D', '2D動畫', 'AI生成', 'MMD', 'Cosplay'].map((g) => ({
          value: g,
          label: g,
        }))
      ),
    },
    {
      key: 'sort',
      label: '排序',
      default: '',
      values: [
        { value: '', label: '相关度' },
        { value: '最新上市', label: '最新上市' },
        { value: '最新上傳', label: '最新上传' },
        { value: '本日排行', label: '今日热门' },
        { value: '本週排行', label: '本周热门' },
        { value: '本月排行', label: '本月热门' },
        { value: '觀看次數', label: '观看最多' },
        { value: '讚好比例', label: '好评最多' },
        { value: '時長最長', label: '时长最长' },
      ],
    },
  ],

  BASE: 'https://hanime1.me',

  genre(value) {
    const g = value === '@setting' || value === undefined ? this.config.genre : value;
    return g === '全部' ? '' : g || '';
  },

  async getDoc(path, params) {
    const res = await this.http.get(this.BASE + path, { params });
    if (res.status === 404) throw Park.error('NOT_FOUND', '影片不存在');
    if (!res.ok) throw Park.error('HTTP', 'Hanime1 返回 HTTP {value0}', { params: {value0: res.status}, status: res.status });
    return Park.html.parse(res.body);
  },

  parseCards(doc) {
    const items = [];
    const seen = new Set();
    for (const a of doc.querySelectorAll('a[href*="watch?v="]')) {
      const m = /watch\?v=(\d+)/.exec(a.getAttribute('href') || '');
      if (!m || seen.has(m[1])) continue;
      const titleEl = a.querySelector('.home-rows-videos-title, .card-mobile-title, .title');
      const img = a.querySelector('img');
      const title = Park.html.text(titleEl) || (img && (img.getAttribute('alt') || img.getAttribute('title'))) || '';
      if (!title || !img) continue;
      seen.add(m[1]);
      const src = img.getAttribute('src') || img.getAttribute('data-src') || '';
      const duration = Park.html.text(a.querySelector('.card-mobile-duration, .duration'));
      const portrait = /\/image\/cover\//.test(src);
      items.push({
        id: m[1],
        title,
        cover: src,
        coverAspect: portrait ? 268 / 394 : 16 / 9,
        duration: /^\d+:\d+/.test(duration) ? duration.match(/^[\d:]+/)[0] : '',
      });
    }
    return items;
  },

  maxPage(doc) {
    let max = 0;
    for (const a of doc.querySelectorAll('a.page-link')) {
      const m = /[?&]page=(\d+)/.exec(a.getAttribute('href') || '');
      if (m) max = Math.max(max, Number(m[1]));
    }
    return max || null;
  },

  async searchPage(params, page) {
    const query = {};
    for (const [k, v] of Object.entries(params)) if (v) query[k] = v;
    if (page > 1) query.page = String(page);
    const tags = query.tags;
    delete query.tags;
    let path = '/search';
    if (tags && tags.length) path += '?' + tags.map((t) => 'tags%5B%5D=' + encodeURIComponent(t)).join('&');
    const doc = await this.getDoc(path, query);
    const items = this.parseCards(doc);
    const maxPage = this.maxPage(doc);
    const totalPages = items.length ? Math.max(maxPage || 1, page) : maxPage;
    return { items, page, totalPages, hasNext: !!totalPages && page < totalPages };
  },

  async feed(key, req) {
    const page = Math.max(1, req.page || 1);
    const genre = this.genre();
    if (key === 'ranking') return this.searchPage({ genre, sort: (req.options && req.options.period) || '本週排行' }, page);
    if (key === 'uploads') return this.searchPage({ genre, sort: '最新上傳' }, page);
    return this.searchPage({ genre, sort: '最新上市' }, page);
  },

  async search(req) {
    const f = req.filters || {};
    const tags = Array.isArray(f.tags) ? f.tags : f.tags ? [f.tags] : [];
    return this.searchPage(
      { query: String(req.keyword || '').trim(), genre: this.genre(f.genre), sort: f.sort || '', tags },
      Math.max(1, req.page || 1)
    );
  },

  parseSources(doc) {
    const found = new Map();
    for (const s of doc.querySelectorAll('video source[src]')) {
      const q = Number(s.getAttribute('size')) || Number((/-(\d{3,4})p\.mp4/.exec(s.getAttribute('src')) || [])[1]);
      if (q && !found.has(q)) found.set(q, s.getAttribute('src'));
    }
    for (const a of doc.querySelectorAll('[data-url*=".mp4"], a[href*=".mp4"]')) {
      const url = a.getAttribute('data-url') || a.getAttribute('href');
      const m = /-(\d{3,4})p\.mp4/.exec(url);
      if (m && !found.has(Number(m[1]))) found.set(Number(m[1]), url);
    }
    return [...found.entries()].sort((a, b) => b[0] - a[0]).map(([quality, url]) => ({ quality, url }));
  },

  async detail(id) {
    const doc = await this.getDoc('/watch', { v: id });
    const og = (p) => {
      const el = doc.querySelector(`meta[property="og:${p}"]`);
      return el ? el.getAttribute('content') || '' : '';
    };
    const title = Park.html.text(doc.querySelector('#shareBtn-title')) || og('title').replace(/\s*-\s*Hanime1\.me\s*$/i, '');
    if (!title) throw Park.error('NOT_FOUND', 'Hanime1 影片 {value0} 不存在或需要登录', { params: {value0: id} });
    const panel = Park.html.text(doc.querySelector('.video-description-panel'));
    const vd = /(?:觀看次數|观看次数)：\s*([\d.,]+\s*[萬万億亿]?)次\s*(\d{4}-\d{2}-\d{2})?/.exec(panel);
    const tags = [];
    for (const el of doc.querySelectorAll('.single-video-tag a')) {
      const href = el.getAttribute('href') || '';
      const m = /tags%5B%5D=([^&]+)|tags\[\]=([^&]+)/.exec(href);
      const name = (el.childNodes[0] && el.childNodes[0].textContent ? el.childNodes[0].textContent : el.textContent)
        .replace(/ /g, ' ')
        .trim();
      // Only real tag links carry tags[]; the add / remove buttons in the same box do not.
      if (!m || !name) continue;
      const tag = decodeURIComponent(m[1] || m[2]);
      if (!tags.some((t) => t.name === name)) tags.push({ name, keyword: '', filters: { tags: [tag], genre: '全部' } });
    }
    const artist = Park.html.text(doc.querySelector('#video-artist-name'));
    // Each playlist entry is a thumbnail link plus a separate text link with the same href.
    const series = [];
    const seriesTitles = {};
    const playlist = [...doc.querySelectorAll('#playlist-scroll a[href*="watch?v="]')];
    for (const a of playlist) {
      const m = /watch\?v=(\d+)/.exec(a.getAttribute('href'));
      if (m && !a.querySelector('img') && Park.html.text(a)) seriesTitles[m[1]] = Park.html.text(a);
    }
    for (const a of playlist) {
      const m = /watch\?v=(\d+)/.exec(a.getAttribute('href'));
      const img = a.querySelector('img');
      if (!m || !img || series.some((s) => s.id === m[1])) continue;
      series.push({
        id: m[1],
        title: seriesTitles[m[1]] || img.getAttribute('alt') || `#${m[1]}`,
        cover: img.getAttribute('src') || '',
        coverAspect: 16 / 9,
        duration: (Park.html.text(a.querySelector('.duration')).match(/^[\d:]+/) || [''])[0],
      });
    }
    const related = this.parseCards(doc).filter((it) => it.id !== String(id) && !series.some((s) => s.id === it.id));
    const video = doc.querySelector('video');
    const sources = this.parseSources(doc);
    return {
      id: String(id),
      title,
      subtitle: Park.html.text(doc.querySelector('.video-description-panel div:not(.hidden-xs)')) || '',
      cover: (video && video.getAttribute('poster')) || og('image'),
      coverAspect: 16 / 9,
      url: `${this.BASE}/watch?v=${id}`,
      authors: artist ? [artist] : [],
      views: vd ? Park.utils.parseCount(vd[1]) : null,
      uploaded: vd && vd[2] ? vd[2] : '',
      description: Park.html.text(doc.querySelector('.video-caption-text')) || og('description'),
      tags: tags.length ? [{ namespace: 'tag', label: '标签', tags }] : [],
      authorSearch: artist ? { keyword: artist, filters: { genre: '全部' } } : null,
      series,
      related: related.slice(0, 24),
      qualities: sources.map((s) => s.quality),
    };
  },

  /** Fresh, playable sources (URLs expire), best first, with the extra qualities from /download. */
  async videos(id) {
    const [watch, download] = await Promise.all([
      this.getDoc('/watch', { v: id }),
      this.getDoc('/download', { v: id }).catch(() => null),
    ]);
    const merged = new Map();
    for (const s of this.parseSources(watch).concat(download ? this.parseSources(download) : [])) {
      if (!merged.has(s.quality)) merged.set(s.quality, s.url);
    }
    const list = [...merged.entries()]
      .sort((a, b) => b[0] - a[0])
      .map(([quality, url]) => ({ quality, label: `${quality}P`, url, headers: { Referer: `${this.BASE}/` } }));
    if (!list.length) throw Park.error('NOT_FOUND', '没有找到可用的视频源（可能需要登录）');
    const preferred = Number(this.config.quality) || 1080;
    const best = list.find((s) => s.quality <= preferred) || list[list.length - 1];
    best.preferred = true;
    return list;
  },
});

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"}],"searchFilters":{"sort":"最新上市"}});
