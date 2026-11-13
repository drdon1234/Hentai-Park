(() => {
const filters = defaultSort => [
  {key: 'age', label: '分级', type: 'multi', default: ['general', 'r15', 'r18'], values: [
    {value: 'general', label: '全年龄'}, {value: 'r15', label: 'R15'}, {value: 'r18', label: 'R18'}]},
  {key: 'date', label: '发布时间', default: 'alltime', values: [
    {value: 'alltime', label: '全部'}, {value: 'week', label: '本周'}, {value: 'month', label: '本月'}, {value: 'year', label: '近一年'}]},
  {key: 'sort', label: '排序', default: defaultSort, values: [
    {value: 'relevanceDescending', label: '相关度'}, {value: 'dateDescending', label: '最新'},
    {value: 'viewsDescending', label: '热门'}, {value: 'likesDescending', label: '点赞数'}]},
  {key: 'min', label: '最短时长（分钟）', type: 'number', default: 0},
  {key: 'max', label: '最长时长（分钟）', type: 'number', default: 0},
  {key: 'tracks', label: '搜索曲目名称', type: 'switch', default: false},
];
Park.register({
  i18n: {
    'zh-Hant': {'日语同人音声与视频，外挂字幕暂不可用': '日語同人音聲與影片，外掛字幕暫無法使用', '分级':'分級', '全年龄':'全年齡', '发布时间':'發佈時間', '近一年':'近一年', '最短时长（分钟）':'最短時長（分鐘）', '最长时长（分钟）':'最長時長（分鐘）', '搜索曲目名称':'搜尋曲目名稱'},
    ja: {'日语同人音声与视频，外挂字幕暂不可用': '日本語の同人音声・動画。外部字幕は現在利用できません', '分级':'年齢区分', '全年龄':'全年齢', '发布时间':'公開日', '近一年':'過去1年', '最短时长（分钟）':'最短時間（分）', '最长时长（分钟）':'最長時間（分）', '搜索曲目名称':'トラック名を検索'},
    ko: {'日语同人音声与视频，外挂字幕暂不可用': '일본 동인 음성과 영상. 외부 자막은 현재 사용할 수 없습니다', '分级':'연령 등급', '全年龄':'전체 연령', '发布时间':'게시일', '近一年':'최근 1년', '最短时长（分钟）':'최소 길이(분)', '最长时长（分钟）':'최대 길이(분)', '搜索曲目名称':'트랙 이름 검색'},
    en: {'日语同人音声与视频，外挂字幕暂不可用': 'Japanese voice works and videos; external subtitles are unavailable', '分级':'Age rating', '全年龄':'All ages', '发布时间':'Upload date', '近一年':'Past year', '最短时长（分钟）':'Minimum duration (minutes)', '最长时长（分钟）':'Maximum duration (minutes)', '搜索曲目名称':'Search track names'},
    es: {'日语同人音声与视频，外挂字幕暂不可用': 'Audios y vídeos japoneses; los subtítulos externos no están disponibles', '分级':'Clasificación', '全年龄':'Todas las edades', '发布时间':'Fecha de publicación', '近一年':'Último año', '最短时长（分钟）':'Duración mínima (minutos)', '最长时长（分钟）':'Duración máxima (minutos)', '搜索曲目名称':'Buscar nombres de pistas'},
    ru: {'日语同人音声与视频，外挂字幕暂不可用': 'Японские аудио и видео; внешние субтитры недоступны', '分级':'Возрастной рейтинг', '全年龄':'Для всех возрастов', '发布时间':'Дата публикации', '近一年':'За год', '最短时长（分钟）':'Минимальная длительность (мин)', '最长时长（分钟）':'Максимальная длительность (мин)', '搜索曲目名称':'Искать названия дорожек'},
    ar: {'日语同人音声与视频，外挂字幕暂不可用': 'أعمال صوتية وفيديو يابانية؛ الترجمات الخارجية غير متاحة حاليًا', '分级':'التصنيف العمري', '全年龄':'جميع الأعمار', '发布时间':'تاريخ النشر', '近一年':'العام الماضي', '最短时长（分钟）':'الحد الأدنى للمدة (دقائق)', '最长时长（分钟）':'الحد الأقصى للمدة (دقائق)', '搜索曲目名称':'البحث في أسماء المقاطع'},
  },
  key: 'jasmr', name: 'JASMR', version: '0.0.3', minAppVersion: '0.13.6',
  type: 'voice', category: 'asmr', color: '#675B83',
  description: '日语同人音声与视频，外挂字幕暂不可用',
  homepage: 'https://www.jasmr.net', domains: ['jasmr.net'],
  network: {vpnHint: true},
  media: {mode: 'native', scope: 'session', origin: 'https://www.jasmr.net'},
  imageHeaders: {Referer: 'https://www.jasmr.net/'},
  defaultFeed: 'popular', feeds: [{key: 'popular', label: '热门', options: filters('viewsDescending')},
    {key: 'new', label: '最新', options: filters('dateDescending')}],
  searchFilters: filters('relevanceDescending'),
  linkPatterns: ['jasmr\\.net/watch/((?:RJ|BJ)[0-9]+)(?:/|[?#]|$)'],
  idPattern: '^((?:RJ|BJ)[0-9]{5,12})$', idExample: 'RJ416386',
  BASE: 'https://www.jasmr.net',

  validId(value) {
    const id = String(value).toUpperCase();
    if (!/^(?:RJ|BJ)[0-9]{5,12}$/.test(id)) throw Park.error('NOT_FOUND', '内容不存在或已被删除');
    return id;
  },
  publicUrl(raw) {
    if (typeof raw !== 'string' || !raw) return '';
    let value;
    try { value = new URL(raw, this.BASE); } catch (_) { return ''; }
    if (value.protocol !== 'https:' || value.username || value.password || value.port || value.hash ||
        !(value.hostname === 'jasmr.net' || value.hostname.endsWith('.jasmr.net'))) return '';
    return value.href;
  },
  async json(path, params) {
    const result = await this.http.get(this.BASE + path, {params});
    if (result.status === 401 || result.status === 403) throw Park.error('LOGIN_REQUIRED', '需要登录');
    if (!result.ok) throw Park.error('HTTP', 'HTTP {status}', {params: {status: result.status}, status: result.status});
    if (result.body.length > 4 * 1024 * 1024) throw Park.error('PARSE', '媒体数据无效');
    return result.json();
  },
  title(value) {
    if (typeof value === 'string') return value;
    return value?.japanese || value?.english || value?.chinese || '';
  },
  item(value) {
    const id = this.validId(value.rjCode);
    const title = this.title(value.title);
    if (!title) throw Park.error('PARSE', '媒体数据无效');
    const language = {JP: 'ja', CN: 'zh', EN: 'en', KO: 'ko', ES: 'es'}[value.language] || '';
    const voiceLanguageStatus = value.language === 'CN' ? 'chineseSpoken'
      : language && value.subtitled === false ? 'foreignOriginal' : 'unknown';
    // 搜索结果不提供媒体地址；详情页可依据实际文件扩展名区分音频和视频。
    const source = this.publicUrl(value.source);
    const ext = source ? new URL(source).pathname.split('.').pop().toLowerCase() : '';
    const form = ['mp3', 'm4a', 'wav', 'flac'].includes(ext) ? 'audioOnly'
      : ['mp4', 'm3u8'].includes(ext) ? 'videoOnly'
      : value.type === 'audio' ? 'audioOnly' : value.type === 'video' ? 'videoOnly' : '';
    return {id, title, cover: this.publicUrl(value.image || value.thumbnail), coverAspect: 1,
      mediaKind: 'voice', workCode: id, duration: String(value.duration || ''),
      ...(language ? {language, voiceLanguageStatus} : {}),
      ...(form ? {voiceMediaForm: form} : {})};
  },
  async listing(request, defaultSort, keyword = '') {
    const page = Math.max(1, Math.floor(Number(request.page) || 1));
    const selected = request.filters || request.options || {};
    const ages = selected.age ?? ['general', 'r15', 'r18'];
    const date = selected.date || 'alltime', sort = selected.sort || defaultSort;
    const min = Number(selected.min || 0), max = Number(selected.max || 6000);
    const tracks = selected.tracks === true;
    if (!Array.isArray(ages) || ages.some(age => !['general', 'r15', 'r18'].includes(age)) ||
        !['alltime', 'week', 'month', 'year'].includes(date) ||
        !['relevanceDescending', 'dateDescending', 'viewsDescending', 'likesDescending'].includes(sort) ||
        !Number.isSafeInteger(min) || !Number.isSafeInteger(max) || min < 0 || max > 6000 || min > max) {
      throw Park.error('CONFIG', '筛选参数无效');
    }
    if (!ages.length) return {items: [], page, hasNext: false};
    const data = await this.json('/api/v1/search', {page, limit: 24, r18: ages.includes('r18'), r15: ages.includes('r15'),
      all: ages.includes('general'), type: 'video', date, min, max, tracks, exclude: '', sort,
      ...(keyword ? {search: keyword} : {})});
    if (!Array.isArray(data.results) || !Number.isFinite(Number(data.totalCount))) throw Park.error('PARSE', '媒体数据无效');
    return {items: data.results.map(value => this.item(value)), page, total: Number(data.totalCount),
      hasNext: page * 24 < Number(data.totalCount)};
  },
  async feed(key, request) {
    if (key !== 'popular' && key !== 'new') throw Park.error('CONFIG', '筛选参数无效');
    return this.listing(request, key === 'popular' ? 'viewsDescending' : 'dateDescending');
  },
  async search(request) {
    const keyword = String(request.keyword || '').trim();
    if (!keyword) return {items: [], page: 1, hasNext: false};
    return this.listing(request, 'relevanceDescending', keyword);
  },
  async work(id) {
    id = this.validId(id);
    const value = await this.json('/api/v1/videos', {code: id});
    if (value.rjCode !== id || !this.title(value.title)) throw Park.error('PARSE', '媒体数据无效');
    return value;
  },
  async detail(id, preview) {
    const value = await this.work(id);
    const item = this.item(value);
    const circle = value.circle && typeof value.circle === 'object' ? value.circle : {};
    const knownLanguage = preview?.id === item.id ? {language: preview.language, voiceLanguageStatus: preview.voiceLanguageStatus} : {};
    return {...knownLanguage, ...item, url: this.BASE + '/watch/' + item.id,
      authors: [circle.kana || circle.romaji].filter(Boolean),
      description: typeof value.description === 'string' ? value.description : ''};
  },
  async videos(id) {
    const value = await this.work(id);
    if (value.earlyAccessLocked === true) throw Park.error('LOGIN_REQUIRED', '需要登录');
    const url = this.publicUrl(value.source);
    if (!url) throw Park.error('UNSUPPORTED', '此影片暂无可用播放地址');
    const ext = new URL(url).pathname.split('.').pop().toLowerCase();
    if (!['mp3', 'm4a', 'wav', 'flac', 'mp4', 'm3u8'].includes(ext)) throw Park.error('UNSUPPORTED', '媒体格式不支持');
    return [{url, format: ext === 'm3u8' ? 'hls' : ext, label: '原画', preferred: true}];
  },
});
})();
