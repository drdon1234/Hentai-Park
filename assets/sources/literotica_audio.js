(() => {
  const HOME = 'https://www.literotica.com';
  const SEARCH = 'https://search.literotica.com';
  const API = 'https://literotica.com/api/3';
  const words = {
    'zh-Hant': {'时间': '時間', '近一年': '近一年', '搜索范围': '搜尋範圍', '正文': '全文', '简介': '簡介', '顺序': '順序', '日期': '日期', '一周': '一週', '一个月': '一個月', '三个月': '三個月', '六个月': '六個月', '一年': '一年', '时间范围': '時間範圍', '以内': '以內', '以前': '以前', '编辑推荐': '編輯推薦', '获奖作品': '獲獎作品', '是': '是'},
    ja: {'时间': '期間', '近一年': '過去1年', '搜索范围': '検索対象', '正文': '本文', '简介': '紹介文', '顺序': '順序', '日期': '日付', '一周': '1週間', '一个月': '1か月', '三个月': '3か月', '六个月': '6か月', '一年': '1年', '时间范围': '期間の範囲', '以内': '以内', '以前': '以前', '编辑推荐': '編集部のおすすめ', '获奖作品': '受賞作品', '是': 'はい'},
    ko: {'时间': '기간', '近一年': '최근 1년', '搜索范围': '검색 범위', '正文': '본문', '简介': '소개', '顺序': '순서', '日期': '날짜', '一周': '1주', '一个月': '1개월', '三个月': '3개월', '六个月': '6개월', '一年': '1년', '时间范围': '기간 범위', '以内': '이내', '以前': '이전', '编辑推荐': '편집자 추천', '获奖作品': '수상작', '是': '예'},
    en: {'时间': 'Period', '近一年': 'Past year', '搜索范围': 'Search in', '正文': 'Full text', '简介': 'Description', '顺序': 'Order', '日期': 'Date', '一周': '1 week', '一个月': '1 month', '三个月': '3 months', '六个月': '6 months', '一年': '1 year', '时间范围': 'Date range', '以内': 'Within', '以前': 'Before', '编辑推荐': "Editor's choice", '获奖作品': 'Contest winners', '是': 'Yes'},
    es: {'时间': 'Período', '近一年': 'Último año', '搜索范围': 'Buscar en', '正文': 'Texto completo', '简介': 'Descripción', '顺序': 'Orden', '日期': 'Fecha', '一周': '1 semana', '一个月': '1 mes', '三个月': '3 meses', '六个月': '6 meses', '一年': '1 año', '时间范围': 'Intervalo de fechas', '以内': 'Dentro de', '以前': 'Antes de', '编辑推荐': 'Selección editorial', '获奖作品': 'Ganadores de concursos', '是': 'Sí'},
    ru: {'时间': 'Период', '近一年': 'За год', '搜索范围': 'Искать в', '正文': 'Полный текст', '简介': 'Описание', '顺序': 'Порядок', '日期': 'Дата', '一周': '1 неделя', '一个月': '1 месяц', '三个月': '3 месяца', '六个月': '6 месяцев', '一年': '1 год', '时间范围': 'Диапазон дат', '以内': 'За последние', '以前': 'Ранее', '编辑推荐': 'Выбор редакции', '获奖作品': 'Победители конкурсов', '是': 'Да'},
    ar: {'时间': 'الفترة', '近一年': 'العام الماضي', '搜索范围': 'البحث في', '正文': 'النص الكامل', '简介': 'الوصف', '顺序': 'الترتيب', '日期': 'التاريخ', '一周': 'أسبوع', '一个月': 'شهر', '三个月': '3 أشهر', '六个月': '6 أشهر', '一年': 'سنة', '时间范围': 'النطاق الزمني', '以内': 'خلال', '以前': 'قبل', '编辑推荐': 'اختيار المحرر', '获奖作品': 'الفائزون بالمسابقات', '是': 'نعم'},
  };
  const searchFilters = [
    {key: 'where', label: '搜索范围', default: 'text', values: [
      {value: 'text', label: '正文'}, {value: 'desc', label: '简介'}, {value: 'tags', label: '标签'},
    ]},
    {key: 'sort', label: '排序', default: 'relevancy', values: [
      {value: 'relevancy', label: '相关度'}, {value: 'date', label: '日期'},
      {value: 'vote', label: '评分'}, {value: 'comments', label: '评论'},
    ]},
    {key: 'order', label: '顺序', default: 'desc', values: [
      {value: 'desc', label: '降序'}, {value: 'asc', label: '升序'},
    ]},
    {key: 'period', label: '时间', default: 'all', values: [
      {value: 'all', label: '不限'}, {value: '1 week', label: '一周'},
      {value: '1 month', label: '一个月'}, {value: '3 month', label: '三个月'},
      {value: '6 month', label: '六个月'}, {value: '1 year', label: '一年'},
    ]},
    {key: 'direction', label: '时间范围', default: 'within', values: [
      {value: 'within', label: '以内'}, {value: 'before', label: '以前'},
    ]},
    {key: 'author', label: '作者', type: 'text', default: ''},
    ...[['editor', '编辑推荐'], ['winner', '获奖作品'], ['popular', '热门']].map(([key, label]) =>
      ({key, label, default: 'all', values: [{value: 'all', label: '不限'}, {value: 'yes', label: '是'}]})),
  ];
  Park.register({
    i18n: {
      'zh-Hant': {...words['zh-Hant'], '英语原创音声与有声故事，支持排行和搜索': '英語原創音聲與有聲故事，支援排行和搜尋', '评分最高': '評分最高', '播放最多': '播放最多'},
      ja: {...words.ja, '英语原创音声与有声故事，支持排行和搜索': '英語のオリジナル音声と朗読。ランキングと検索に対応', '评分最高': '高評価順', '播放最多': '再生数順'},
      ko: {...words.ko, '英语原创音声与有声故事，支持排行和搜索': '영어 오리지널 음성과 오디오 스토리, 순위와 검색 지원', '评分最高': '평점순', '播放最多': '재생순'},
      en: {...words.en, '英语原创音声与有声故事，支持排行和搜索': 'Original English audio and narrated stories with rankings and search', '评分最高': 'Top rated', '播放最多': 'Most played'},
      es: {...words.es, '英语原创音声与有声故事，支持排行和搜索': 'Audio original y relatos narrados en inglés, con rankings y búsqueda', '评分最高': 'Mejor valorados', '播放最多': 'Más reproducidos'},
      ru: {...words.ru, '英语原创音声与有声故事，支持排行和搜索': 'Оригинальные английские аудио и рассказы с рейтингами и поиском', '评分最高': 'По рейтингу', '播放最多': 'По прослушиваниям'},
      ar: {...words.ar, '英语原创音声与有声故事，支持排行和搜索': 'صوتيات وقصص إنجليزية أصلية مع ترتيب وبحث', '评分最高': 'الأعلى تقييمًا', '播放最多': 'الأكثر تشغيلًا'},
    },
    key: 'literotica_audio', name: 'Literotica Audio', version: '0.0.1', minAppVersion: '1.12.1',
    type: 'voice', category: 'asmr', color: '#AE3942',
    description: '英语原创音声与有声故事，支持排行和搜索',
    homepage: HOME + '/c/audio-sex-stories', domains: ['literotica.com'],
    network: {mode: 'auto', vpnHint: true},
    media: {mode: 'native', origin: HOME, domains: ['literotica.com']},
    defaultFeed: 'rank', feeds: [
      {key: 'rank', label: '排行', options: [
        {key: 'sort', label: '排序', default: 'top-rated', values: [
          {value: 'top-rated', label: '评分最高'}, {value: 'most-read', label: '播放最多'},
        ]},
        {key: 'period', label: '时间', default: 'all', values: [
          {value: 'all', label: '全部'}, {value: 'week', label: '本周'},
          {value: 'month', label: '本月'}, {value: 'year', label: '近一年'},
        ]},
      ]},
      {key: 'recent', label: '最新'},
    ],
    searchFilters,
    validId(value) {
      const id = String(value || '');
      if (!/^[a-z0-9][a-z0-9-]{0,220}$/.test(id)) throw Park.error('NOT_FOUND', '内容不存在或已被删除');
      return id;
    },
    safePage(raw) {
      let url;
      try { url = new URL(raw, HOME); } catch (_) {}
      if (!url || url.protocol !== 'https:' || url.username || url.password || url.port || url.hash ||
          !['www.literotica.com', 'literotica.com', 'search.literotica.com'].includes(url.hostname)) throw Park.error('CONFIG', '站点链接无效');
      return url;
    },
    safeAudio(raw) {
      let url;
      try { url = new URL(raw, HOME); } catch (_) {}
      if (!url || url.protocol !== 'https:' || url.username || url.password || url.port || url.hash ||
          !(url.hostname === 'uploads.literotica.com' || url.hostname.endsWith('.uploads.literotica.com'))) throw Park.error('PARSE', '媒体数据无效');
      const ext = url.pathname.split('.').pop().toLowerCase();
      if (!['mp3', 'm4a', 'mp4', 'm3u8'].includes(ext)) throw Park.error('UNSUPPORTED', '媒体格式不支持');
      return {url: url.href, format: ext === 'm3u8' ? 'hls' : ext};
    },
    async page(url, params = {}) {
      const target = this.safePage(url);
      const result = await this.http.get(target.href, {params});
      if (result.status === 404) throw Park.error('NOT_FOUND', '内容不存在或已被删除');
      if (!result.ok) throw Park.error('HTTP', 'HTTP {status}', {status: result.status, params: {status: result.status}});
      this.safePage(result.url || target.href);
      if (result.body.length > 4 * 1024 * 1024) throw Park.error('PARSE', '媒体数据无效');
      return Park.html.parse(result.body);
    },
    entries(doc) {
      const items = [], seen = new Set();
      for (const a of doc.querySelectorAll('a[href]')) {
        let url;
        try { url = this.safePage(new URL(a.getAttribute('href'), HOME).href); } catch (_) { continue; }
        const match = /^\/s\/([a-z0-9][a-z0-9-]{0,220})\/?$/.exec(url.pathname);
        if (!match || seen.has(match[1])) continue;
        const row = a.closest('[typeof="CreativeWork"],article,li,[class*="_item_"],[class*="story"]') || a.parentElement;
        if (!row?.querySelector('a[href*="/c/audio-sex-stories"]')) continue;
        const title = Park.html.text(a);
        if (!title || /^(?:Page \d+|Next|Previous)$/i.test(title)) continue;
        const authorNode = row.querySelector('[property~="author"],a[href*="/authors/"]');
        const author = authorNode?.querySelector('meta[property="name"]')?.getAttribute('content') ||
          Park.html.text(authorNode).replace(/^by\s+/i, '');
        seen.add(match[1]);
        items.push({id: match[1], title, cover: '', mediaKind: 'voice', language: 'en', voiceMediaForm: 'audioOnly',
          ...(author ? {authors: [author]} : {}),
          uploaded: row.querySelector('[property="datePublished"]')?.getAttribute('content') || ''});
      }
      return items;
    },
    async htmlListing(url, request, params = {}, audioSearch = false) {
      const page = Math.max(1, Math.floor(Number(request.page) || 1));
      let doc;
      for (let attempt = 0; attempt < (audioSearch ? 3 : 1); attempt++) {
        const candidate = await this.page(url, {...params, ...(page > 1 ? {page} : {})});
        if (audioSearch) {
          const state = [...candidate.querySelectorAll('script')].map(script => script.textContent || '')
            .find(text => text.includes('"search":{'));
          const search = state?.slice(state.indexOf('"search":{')) || '';
          // 站点偶尔返回未执行筛选的空初始状态；不能当作真实无结果。
          if (!/"filters"\s*:\s*\{[^{}]*"categories"\s*:\s*\[\s*39\s*\]/.test(search)) continue;
        }
        doc = candidate;
        break;
      }
      if (!doc) throw Park.error('PARSE', '媒体数据无效');
      const items = this.entries(doc);
      let hasNext = false;
      for (const a of doc.querySelectorAll('a[href]')) {
        let next;
        try { next = this.safePage(new URL(a.getAttribute('href'), url).href); } catch (_) { continue; }
        if (next.hostname !== new URL(url).hostname || next.pathname !== new URL(url).pathname) continue;
        if (Number(next.searchParams.get('page') || 0) > page) hasNext = true;
      }
      return {items, page, hasNext, ...(hasNext ? {cursor: String(page + 1)} : {})};
    },
    async feed(key, request) {
      if (key === 'recent') {
        const page = Math.max(1, Math.floor(Number(request.page) || 1));
        const response = await this.http.get(API + '/stories/new', {params: {params: JSON.stringify({category: 39, page, pageSize: 35, language: 1})}});
        if (!response.ok) throw Park.error('HTTP', 'HTTP {status}', {status: response.status, params: {status: response.status}});
        const data = response.json();
        if (!Array.isArray(data?.submissions) || !Number.isSafeInteger(data.meta?.submissions_count)) throw Park.error('PARSE', '媒体数据无效');
        const items = data.submissions.filter(value => value.type === 'audio' && value.language === 1).map(value => ({
          id: this.validId(value.url), title: String(value.title || ''), cover: '', mediaKind: 'voice', language: 'en',
          voiceMediaForm: 'audioOnly', authors: value.authorname ? [String(value.authorname)] : [],
          uploaded: String(value.date_approve || ''), subtitle: String(value.description || ''),
        }));
        return {items, page, total: data.meta.submissions_count, hasNext: page * 35 < data.meta.submissions_count};
      }
      if (key !== 'rank') throw Park.error('CONFIG', '未知列表');
      const sort = String(request.options?.sort || 'top-rated'), period = String(request.options?.period || 'all');
      if (!['top-rated', 'most-read'].includes(sort) || !['all', 'week', 'month', 'year'].includes(period)) throw Park.error('CONFIG', '筛选参数无效');
      return this.htmlListing(HOME + '/top/audio/' + sort + '/audio-39', request, period === 'all' ? {} : {period});
    },
    async search(request) {
      const keyword = String(request.keyword || '').trim();
      if (!keyword) return {items: [], page: 1, hasNext: false};
      if (keyword.length > 200) throw Park.error('CONFIG', '筛选参数无效');
      const selected = request.filters || request.options || {};
      const where = String(selected.where || 'text'), sort = String(selected.sort || 'relevancy');
      const order = String(selected.order || 'desc'), period = String(selected.period || 'all');
      const direction = String(selected.direction || 'within'), author = String(selected.author || '').trim();
      const editor = String(selected.editor || 'all'), winner = String(selected.winner || 'all');
      const popular = String(selected.popular || 'all');
      if (!['text', 'desc', 'tags'].includes(where) || !['relevancy', 'date', 'vote', 'comments'].includes(sort) ||
          !['desc', 'asc'].includes(order) || !['all', '1 week', '1 month', '3 month', '6 month', '1 year'].includes(period) ||
          !['within', 'before'].includes(direction) || author.length > 100 || /[\x00-\x1f\x7f]/.test(author) ||
          [editor, winner, popular].some(value => !['all', 'yes'].includes(value))) throw Park.error('CONFIG', '筛选参数无效');
      return this.htmlListing(SEARCH + '/', request, {
        query: keyword, type: 'story', categories: '39',
        ...(where !== 'text' ? {where} : {}), ...(sort !== 'relevancy' ? {sort} : {}),
        ...(order !== 'desc' ? {sortOrder: order} : {}), ...(period !== 'all' ? {period} : {}),
        ...(period !== 'all' && direction === 'before' ? {timeDirection: 'before'} : {}),
        ...(author ? {author} : {}), ...(editor === 'yes' ? {editorsChoice: 'true'} : {}),
        ...(winner === 'yes' ? {winner: 'true'} : {}), ...(popular === 'yes' ? {popular: 'true'} : {}),
      }, true);
    },
    async work(value) {
      const id = this.validId(value), doc = await this.page(HOME + '/s/' + id);
      const title = Park.html.text(doc.querySelector('h1'));
      if (!title) throw Park.error('PARSE', '媒体数据无效');
      const audio = doc.querySelector('audio[src], audio source[src]')?.getAttribute('src') || '';
      if (!audio) throw Park.error('UNSUPPORTED', '此作品暂无可用播放地址');
      const author = Park.html.text(doc.querySelector('a[rel="author"],a[href*="/authors/"]'));
      return {id, title, author, audio: this.safeAudio(audio), description: doc.querySelector('meta[name="description"]')?.getAttribute('content') || ''};
    },
    async detail(id) {
      const work = await this.work(id);
      return {id: work.id, title: work.title, cover: '', url: HOME + '/s/' + work.id,
        description: work.description, mediaKind: 'voice', language: 'en', voiceMediaForm: 'audioOnly',
        ...(work.author ? {authors: [work.author]} : {})};
    },
    async videos(id) {
      const work = await this.work(id);
      return [{...work.audio, label: '原画', preferred: true, headers: {Referer: HOME + '/'}}];
    },
  });
})();
