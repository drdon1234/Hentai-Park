/*
 * JMComic (禁漫天堂) — mobile app API.
 * - API domains rotate often: the current list is fetched from the official domain server (AES-ECB
 *   encrypted), with built-in fallbacks; failed requests automatically move on to the next domain.
 * - Each request carries token = md5(ts + secret) and tokenparam = "ts,version"; the `data` field of the
 *   response is AES-ECB encrypted with md5(ts + data secret).
 * - Images are scrambled into horizontal strips (count derived from md5(photoId + filename)); the host
 *   reassembles them natively using the `transform` descriptor returned with each page.
 */
Park.register({
  i18n: {
    "zh-Hant": {"API 线路": "API 線路", "JM{value0} 不存在": "JM{value0} 不存在", "中文本子与韩漫资源丰富，支持连载分话、自动切换线路与图片还原": "中文字子與韓漫資源豐富，支援連載分話、自動切換線路與圖片還原", "作品": "作品", "分流 4": "分流 4", "单本": "單本", "可搜索作品名、作者、标签；直接输入车号（如 350234）可跳转作品": "可搜尋作品名、作者、標籤；直接輸入車號（如 350234）可跳轉作品", "图片分流": "圖片分流", "所有禁漫线路均不可用": "所有禁漫線路均不可用", "搜索范围": "搜尋範圍", "最多喜欢": "最多喜歡", "最多图片": "最多圖片", "没有可随机的作品": "沒有可隨機的作品", "登场人物": "登場人物", "禁漫天堂": "禁漫天堂", "禁漫汉化组": "禁漫漢化組", "禁漫漢化組": "禁漫漢化組", "禁漫线路 {value0} 异常（HTTP {value1}）": "禁漫線路 {value0} 異常（HTTP {value1}）", "禁漫：{value0}": "禁漫：{value0}", "章节没有图片": "章節沒有圖片", "线路 1": "線路 1", "线路 2": "線路 2", "线路 3": "線路 3", "线路 4": "線路 4", "美漫": "美漫", "自动模式会在请求失败时依次尝试其他线路": "自動模式會在請求失敗時依次嘗試其他線路"},
    "ja": {"API 线路": "APIライン", "JM{value0} 不存在": "JM{value0}は存在しません", "中文本子与韩漫资源丰富，支持连载分话、自动切换线路与图片还原": "中国語の字幕と韓国語の漫画はリソースが豊富で、シリアル化、自動行切り替え、画像復元をサポートしています。", "作品": "作品", "分流 4": "サーバー 4", "单本": "単一コピー", "可搜索作品名、作者、标签；直接输入车号（如 350234）可跳转作品": "作品名・作者・タグで検索できます。作品 ID（例：350234）を入力すると直接開けます", "图片分流": "画像サーバー", "所有禁漫线路均不可用": "禁止されている漫画のセリフはすべて利用できません", "搜索范围": "検索範囲", "最多喜欢": "ほとんどの場合と同様に、", "最多图片": "ほとんどの写真", "没有可随机的作品": "ランダムな仕事は存在しない", "登场人物": "キャラクター", "禁漫天堂": "JMComic", "禁漫汉化组": "禁断の漫画中国語グループ", "禁漫漢化組": "禁断の漫画中国語グループ", "禁漫线路 {value0} 异常（HTTP {value1}）": "禁止された漫画行 {value0} 例外 (HTTP {value1})", "禁漫：{value0}": "禁断の漫画：{value0}", "章节没有图片": "章には絵がありません", "线路 1": "1行目", "线路 2": "2行目", "线路 3": "3行目", "线路 4": "4行目", "美漫": "アメリカンコミックス", "自动模式会在请求失败时依次尝试其他线路": "自動モードでは、リクエストが失敗した場合に他の行を順番に試行します。"},
    "ko": {"API 线路": "API 라인", "JM{value0} 不存在": "JM{value0}가 존재하지 않습니다.", "中文本子与韩漫资源丰富，支持连载分话、自动切换线路与图片还原": "중국어 자막과 한국 만화의 풍부한 자원, 연재 및 분할 지원, 자동 줄바꿈 및 그림 복원 지원", "作品": "일하다", "分流 4": "서버 4", "单本": "단일 사본", "可搜索作品名、作者、标签；直接输入车号（如 350234）可跳转作品": "제목, 작가, 태그로 검색할 수 있습니다. 작품 ID(예: 350234)를 입력하면 바로 열립니다", "图片分流": "이미지 서버", "所有禁漫线路均不可用": "금지된 만화 대사는 모두 사용할 수 없습니다.", "搜索范围": "검색범위", "最多喜欢": "가장 좋아하는 것", "最多图片": "대부분의 사진", "没有可随机的作品": "임의의 작품이 없습니다", "登场人物": "캐릭터", "禁漫天堂": "JMComic", "禁漫汉化组": "금지된 만화 중국어 그룹", "禁漫漢化組": "금단의 만화 중국어판 그룹", "禁漫线路 {value0} 异常（HTTP {value1}）": "금지된 만화 줄 {value0} 예외(HTTP {value1})", "禁漫：{value0}": "금지된 만화: {value0}", "章节没有图片": "챕터에 사진이 없습니다", "线路 1": "1호선", "线路 2": "2호선", "线路 3": "3호선", "线路 4": "4호선", "美漫": "미국 만화", "自动模式会在请求失败时依次尝试其他线路": "요청이 실패하면 자동 모드는 순차적으로 다른 라인을 시도합니다."},
    "en": {"API 线路": "API line", "JM{value0} 不存在": "JM{value0} does not exist", "中文本子与韩漫资源丰富，支持连载分话、自动切换线路与图片还原": "Chinese subtitles and Korean comics are rich in resources, supporting serialization, automatic line switching and picture restoration.", "作品": "Works", "分流 4": "Server 4", "单本": "Single copy", "可搜索作品名、作者、标签；直接输入车号（如 350234）可跳转作品": "Search by title, author or tag; enter a work ID (e.g. 350234) to open it directly", "图片分流": "Image server", "所有禁漫线路均不可用": "All prohibited comic lines are unavailable", "搜索范围": "Search scope", "最多喜欢": "Like most", "最多图片": "Most pictures", "没有可随机的作品": "There is no random work", "登场人物": "Characters on the stage", "禁漫天堂": "JMComic", "禁漫汉化组": "Forbidden comic Chinese group", "禁漫漢化組": "Forbidden comic Chinese group", "禁漫线路 {value0} 异常（HTTP {value1}）": "Forbidden comic line {value0} exception (HTTP {value1})", "禁漫：{value0}": "Forbidden comics: {value0}", "章节没有图片": "Chapter has no picture", "线路 1": "Line 1", "线路 2": "Line 2", "线路 3": "Line 3", "线路 4": "Line 4", "美漫": "American comics", "自动模式会在请求失败时依次尝试其他线路": "Automatic mode will try other lines in sequence when the request fails."},
    "es": {"API 线路": "Línea API", "JM{value0} 不存在": "JM{value0} no existe", "中文本子与韩漫资源丰富，支持连载分话、自动切换线路与图片还原": "Amplios recursos de subtítulos chinos y cómics coreanos, que admiten serialización y división, cambio automático de líneas y restauración de imágenes.", "作品": "Obras", "分流 4": "Servidor 4", "单本": "Copia única", "可搜索作品名、作者、标签；直接输入车号（如 350234）可跳转作品": "Busca por título, autor o etiqueta; introduce el ID de una obra (p. ej., 350234) para abrirla directamente", "图片分流": "Servidor de imágenes", "所有禁漫线路均不可用": "Todas las líneas cómicas prohibidas no están disponibles", "搜索范围": "Alcance de la búsqueda", "最多喜欢": "Como la mayoría", "最多图片": "La mayoría de las imágenes", "没有可随机的作品": "No hay trabajo aleatorio", "登场人物": "Personajes en el escenario", "禁漫天堂": "JMComic", "禁漫汉化组": "Grupo chino cómico prohibido.", "禁漫漢化組": "Grupo chino cómico prohibido.", "禁漫线路 {value0} 异常（HTTP {value1}）": "Línea cómica prohibida {value0} excepción (HTTP {value1})", "禁漫：{value0}": "Cómics prohibidos: {value0}", "章节没有图片": "El capítulo no tiene imagen.", "线路 1": "Línea 1", "线路 2": "Línea 2", "线路 3": "Línea 3", "线路 4": "Línea 4", "美漫": "Cómics americanos", "自动模式会在请求失败时依次尝试其他线路": "El modo automático probará secuencialmente otras líneas si la solicitud falla"},
    "ru": {"API 线路": "Линия API", "JM{value0} 不存在": "JM{value0} не существует", "中文本子与韩漫资源丰富，支持连载分话、自动切换线路与图片还原": "Китайские субтитры и корейские комиксы богаты ресурсами, поддерживающими сериализацию, автоматическое переключение строк и восстановление изображений.", "作品": "Работы", "分流 4": "Сервер 4", "单本": "Единственный экземпляр", "可搜索作品名、作者、标签；直接输入车号（如 350234）可跳转作品": "Ищите по названию, автору или тегу; введите ID произведения (например, 350234), чтобы открыть его напрямую", "图片分流": "Сервер изображений", "所有禁漫线路均不可用": "Все запрещенные комиксы недоступны.", "搜索范围": "Область поиска", "最多喜欢": "Как и большинство", "最多图片": "Большинство фотографий", "没有可随机的作品": "Случайной работы нет.", "登场人物": "Персонажи на сцене", "禁漫天堂": "JMComic", "禁漫汉化组": "Запрещенная комическая китайская группа", "禁漫漢化組": "Запрещенная комическая китайская группа", "禁漫线路 {value0} 异常（HTTP {value1}）": "Исключение запрещенной строки комикса {value0} (HTTP {value1})", "禁漫：{value0}": "Запрещенные комиксы: {value0}", "章节没有图片": "В главе нет изображений", "线路 1": "Строка 1", "线路 2": "Строка 2", "线路 3": "Строка 3", "线路 4": "Строка 4", "美漫": "Американские комиксы", "自动模式会在请求失败时依次尝试其他线路": "Автоматический режим будет пробовать другие линии последовательно, если запрос не удался."},
    "ar": {"API 线路": "خط API", "JM{value0} 不存在": "JM{value0} غير موجود", "中文本子与韩漫资源丰富，支持连载分话、自动切换线路与图片还原": "الترجمات الصينية والقصص المصورة الكورية غنية بالموارد، وتدعم التسلسل، والتبديل التلقائي للسطور، واستعادة الصورة.", "作品": "يعمل", "分流 4": "الخادم 4", "单本": "نسخة واحدة", "可搜索作品名、作者、标签；直接输入车号（如 350234）可跳转作品": "ابحث بالعنوان أو المؤلف أو الوسم؛ أدخل معرّف العمل (مثل 350234) لفتحه مباشرة", "图片分流": "خادم الصور", "所有禁漫线路均不可用": "جميع الخطوط الكوميدية المحظورة غير متوفرة", "搜索范围": "نطاق البحث", "最多喜欢": "مثل معظم", "最多图片": "معظم الصور", "没有可随机的作品": "لا يوجد عمل عشوائي", "登场人物": "الشخصيات على المسرح", "禁漫天堂": "JMComic", "禁漫汉化组": "مجموعة صينية كوميدية محظورة", "禁漫漢化組": "مجموعة صينية كوميدية محظورة", "禁漫线路 {value0} 异常（HTTP {value1}）": "استثناء الخط الهزلي المحظور {value0} (HTTP {value1})", "禁漫：{value0}": "القصص المصورة المحرمة: {value0}", "章节没有图片": "الفصل ليس به صور", "线路 1": "السطر 1", "线路 2": "السطر 2", "线路 3": "السطر 3", "线路 4": "السطر 4", "美漫": "القصص المصورة الأمريكية", "自动模式会在请求失败时依次尝试其他线路": "سيحاول الوضع التلقائي الأسطر الأخرى بالتسلسل عند فشل الطلب."},
  },
  key: 'jm',
  name: '禁漫天堂',
  version: '0.0.9', minAppVersion: '0.9.2',
  type: 'comic',
  category: 'doujin',
  color: '#F7841E',
  icon: 'https://18comic.vip/favicon.ico',
  description: '中文本子与韩漫资源丰富，支持连载分话、自动切换线路与图片还原',
  homepage: 'https://18comic.vip',
  language: 'zh',
  linkPatterns: [
    '(?:18comic|jmcomic|jm-?comic|18-comic)[\\w.-]*\\.\\w+/(?:album|photo)s?/(\\d{3,9})',
    '(?:^|[^a-zA-Z0-9])[Jj][Mm]\\s*[-_:：#]?\\s*(\\d{3,9})(?!\\d)',
  ],
  idPattern: '^(?:[Jj][Mm])?(\\d{3,9})$',
  idExample: 'JM350234',
  imageHeaders: {
    'X-Requested-With': 'com.example.app',
    Referer: 'https://localhost/',
  },

  settings: [
    {
      key: 'apiDomain',
      type: 'select',
      label: 'API 线路',
      description: '自动模式会在请求失败时依次尝试其他线路',
      default: 'auto',
      options: [
        { value: 'auto', label: '自动' },
        { value: '0', label: '线路 1' },
        { value: '1', label: '线路 2' },
        { value: '2', label: '线路 3' },
        { value: '3', label: '线路 4' },
      ],
    },
    {
      key: 'imageStream',
      type: 'select',
      label: '图片分流',
      default: 'auto',
      options: [
        { value: 'auto', label: '自动' },
        { value: '1', label: '分流 1' },
        { value: '2', label: '分流 2' },
        { value: '3', label: '分流 3' },
        { value: '4', label: '分流 4' },
      ],
    },
  ],

  rankings: [{ key: 'ranking', label: '排行榜', category: 'doujin', metric: '站内热度', feed: 'ranking' }],
  defaultFeed: 'promote',
  feeds: [
    { key: 'promote', label: '推荐' },
    { key: 'latest', label: '最新' },
    {
      key: 'ranking',
      label: '排行榜',
      options: [
        {
          key: 'period',
          label: '周期',
          default: 'mv_w',
          values: [
            { value: 'mv_t', label: '日榜' },
            { value: 'mv_w', label: '周榜' },
            { value: 'mv_m', label: '月榜' },
            { value: 'mv', label: '总榜' },
          ],
        },
      ],
    },
    {
      key: 'category',
      label: '分类',
      options: [
        {
          key: 'category',
          label: '分类',
          default: 'doujin',
          values: [
            { value: 'doujin', label: '同人' },
            { value: 'single', label: '单本' },
            { value: 'short', label: '短篇' },
            { value: 'hanman', label: '韩漫' },
            { value: 'meiman', label: '美漫' },
            { value: 'another', label: '其他' },
            { value: 'doujin_cosplay', label: 'Cosplay' },
            { value: '3D', label: '3D' },
            { value: '禁漫漢化組', label: '禁漫汉化组' },
          ],
        },
        {
          key: 'sort',
          label: '排序',
          default: 'mr',
          values: [
            { value: 'mr', label: '最新' },
            { value: 'mv', label: '最多观看' },
            { value: 'mv_w', label: '本周热门' },
            { value: 'tf', label: '最多喜欢' },
            { value: 'mp', label: '最多图片' },
          ],
        },
      ],
    },
  ],

  searchHint: '可搜索作品名、作者、标签；直接输入车号（如 350234）可跳转作品',
  searchFilters: [
    {
      key: 'sort',
      label: '排序',
      default: 'mr',
      values: [
        { value: 'mr', label: '最新' },
        { value: 'mv', label: '最多观看' },
        { value: 'mv_m', label: '本月热门' },
        { value: 'mv_w', label: '本周热门' },
        { value: 'mv_t', label: '今日热门' },
        { value: 'tf', label: '最多喜欢' },
        { value: 'mp', label: '最多图片' },
      ],
    },
    {
      key: 'mainTag',
      label: '搜索范围',
      default: '0',
      values: [
        { value: '0', label: '全部' },
        { value: '1', label: '作品' },
        { value: '2', label: '作者' },
        { value: '3', label: '标签' },
        { value: '4', label: '登场人物' },
      ],
    },
  ],

  APP_VERSION: '2.0.16',
  TOKEN_SECRET: '18comicAPPContent',
  DATA_SECRET: '185Hcomic3PAPP7R',
  DOMAIN_SECRET: 'diosfjckwpqpdfjkvnqQjsik',
  DOMAIN_SERVERS: [
    'https://rup4a04-c02.tos-cn-hongkong.bytepluses.com/newsvr-2025.txt',
    'https://rup4a04-c01.tos-ap-southeast-1.bytepluses.com/newsvr-2025.txt',
    'https://rup4a04-c03.tos-cn-beijing.bytepluses.com.cn/newsvr-2025.txt',
  ],
  FALLBACK_DOMAINS: ['www.cdnhjk.net', 'www.cdngwc.cc', 'www.cdngwc.net', 'www.cdngwc.club', 'www.cdnutc.me'],
  FALLBACK_IMAGE_HOST: 'https://cdn-msp.jmapinodeudzn.net',
  UA: 'Mozilla/5.0 (Linux; Android 10; K; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/130.0.0.0 Mobile Safari/537.36',

  async init() {
    this.domains = this.store.get('domains') || this.FALLBACK_DOMAINS.slice();
    this.imageHost = this.store.get('imageHost') || this.FALLBACK_IMAGE_HOST;
    this.preferred = 0;
    const lastRefresh = this.store.get('domainsAt', 0);
    if (Date.now() - lastRefresh > 6 * 3600 * 1000) await this.refreshDomains().catch(() => {});
    await this.refreshImageHost().catch(() => {});
  },

  async onSettingsChanged() {
    await this.refreshImageHost().catch(() => {});
  },

  async decrypt(data, secret) {
    const text = await Park.crypto.aesEcbDecrypt(String(data).trim(), await Park.crypto.md5Hex(secret));
    const start = text.search(/[[{]/);
    const end = Math.max(text.lastIndexOf('}'), text.lastIndexOf(']'));
    return JSON.parse(text.slice(start, end + 1));
  },

  async refreshDomains() {
    for (const url of this.DOMAIN_SERVERS) {
      try {
        const res = await this.http.get(url, { timeout: 8000 });
        if (!res.ok) continue;
        const body = String(res.body).replace(/^[^\x00-\x7f]+/, '');
        const json = await this.decrypt(body, this.DOMAIN_SECRET);
        if (Array.isArray(json.Server) && json.Server.length) {
          this.domains = json.Server.slice(0, 6);
          this.store.set('domains', this.domains);
          this.store.set('domainsAt', Date.now());
          return this.domains;
        }
      } catch (e) {
        /* try next server */
      }
    }
    return this.domains;
  },

  async refreshImageHost() {
    const automatic = !this.config.imageStream || this.config.imageStream === 'auto';
    if (automatic && (!this.config.apiDomain || this.config.apiDomain === 'auto')) await this.ensureRoute();
    const stream = automatic ? this.selectedStream || '1' : this.config.imageStream;
    const setting = await this.api('/setting', { app_img_shunt: stream, express: '' });
    if (setting && setting.img_host) {
      this.imageHost = String(setting.img_host).replace(/\/$/, '');
      this.store.set('imageHost', this.imageHost);
      const route = this.store.get('route');
      if (route) this.store.set('route', { ...route, imageHost: this.imageHost });
    }
  },

  async routeFingerprint() {
    const host = this.store.get('route')?.host || this.domains[0];
    try {
      const response = await this.http.get(`https://${host}/cdn-cgi/trace`, { mode: 'native', timeout: 4000 });
      const ip = response.ok && String(response.body).match(/^ip=([0-9a-fA-F:.]+)$/m)?.[1];
      return ip ? Park.crypto.sha256Hex(ip) : null;
    } catch (_) { return null; }
  },

  async ensureRoute() {
    if (this.routePending) return this.routePending;
    this.routePending = (async () => {
      const fingerprint = await this.routeFingerprint();
      const previous = this.store.get('route');
      const signature = `${this.domains.join('|')}:${this.config.imageStream || 'auto'}`;
      const reusable = fingerprint && previous?.fingerprint === fingerprint && previous.signature === signature && this.domains.includes(previous.host);
      const route = reusable
        ? previous : { ...await this.probeRoutes(), fingerprint, signature };
      this.preferred = this.domains.indexOf(route.host);
      this.selectedStream = route.stream;
      if (route.imageHost) { this.imageHost = route.imageHost; this.store.set('imageHost', route.imageHost); }
      this.store.set('route', route);
      if (!reusable) route.fingerprint = await this.routeFingerprint();
      this.store.set('route', route);
      await this.store.flush();
      return route;
    })();
    try { return await this.routePending; } finally { this.routePending = null; }
  },

  async probeRoutes() {
    const stream = this.config.imageStream && this.config.imageStream !== 'auto' ? this.config.imageStream : '1';
    const candidates = (await Promise.all(this.domains.map(async host => {
      const start = Date.now();
      try {
        const setting = await this.requestApi(host, '/setting', { app_img_shunt: stream, express: '' });
        if (!setting || !/^https:\/\//.test(String(setting.img_host))) return null;
        return { host, setting, ms: Date.now() - start };
      } catch (_) { return null; }
    }))).filter(Boolean);
    candidates.sort((a, b) => {
      const mainland = x => x.setting?.is_cn === 1 && x.setting?.cn_base_url === `https://${x.host}` ? 0 : 1;
      return mainland(a) - mainland(b) || a.ms - b.ms;
    });
    const best = candidates[0];
    if (!best) throw Park.error('NETWORK', '所有禁漫线路均不可用');
    let selected = { stream, imageHost: best.setting?.img_host };
    if (!this.config.imageStream || this.config.imageStream === 'auto') {
      const sample = await this.requestApi(best.host, '/categories/filter', { page: 1, order: '', c: '0', o: 'mr' }).catch(() => null);
      const sampleId = (sample?.content || sample?.list || [])[0]?.id;
      const images = (await Promise.all(['1', '2', '3', '4'].map(async value => {
        try {
          if (!/^\d+$/.test(String(sampleId))) return null;
          const setting = await this.requestApi(best.host, '/setting', { app_img_shunt: value, express: '' });
          if (!/^https:\/\//.test(String(setting?.img_host))) return null;
          const start = Date.now();
          const response = await this.http.get(`${String(setting.img_host).replace(/\/$/, '')}/media/albums/${sampleId}_3x4.jpg`, {
            mode: 'native', timeout: 6000, responseType: 'base64', headers: { Range: 'bytes=0-1023' },
          });
          if (!response.ok || !String(response.body).startsWith('/9j/')) return null;
          return { stream: value, imageHost: setting.img_host, ms: Date.now() - start };
        } catch (_) { return null; }
      }))).filter(Boolean).sort((a, b) => a.ms - b.ms);
      if (images.length) selected = images[0];
    }
    return { host: best.host, stream: selected.stream, imageHost: selected.imageHost };
  },

  async requestApi(domain, path, params, form) {
    const ts = Math.floor(Date.now() / 1000);
    const headers = this.headers(ts);
    headers.token = await Park.crypto.md5Hex(`${ts}${this.TOKEN_SECRET}`);
    const res = await this.http.request({ url: `https://${domain}${path}`, method: form ? 'POST' : 'GET', params, form, headers, timeout: 8000, mode: 'native' });
    if (res.status >= 500 || res.status === 403) throw Park.error('NETWORK', '所有禁漫线路均不可用');
    const json = res.json();
    if (res.status === 401) throw Park.error('LOGIN_REQUIRED', json.errorMsg || '需要登录');
    if (json.code !== undefined && json.code !== 200) {
      const msg = json.errorMsg || json.message || `code ${json.code}`;
      if (/不存在|not found|找不到/i.test(msg)) throw Park.error('NOT_FOUND', msg);
      throw Park.error('HTTP', '禁漫：{value0}', { params: {value0: msg} });
    }
    return typeof json.data === 'string' ? this.decrypt(json.data, `${ts}${this.DATA_SECRET}`) : json.data;
  },

  domainOrder() {
    const fixed = this.config.apiDomain;
    if (fixed !== undefined && fixed !== 'auto' && this.domains[Number(fixed)]) return [Number(fixed)];
    const order = [];
    for (let i = 0; i < this.domains.length; i++) order.push((this.preferred + i) % this.domains.length);
    return order;
  },

  headers(ts) {
    return {
      Accept: '*/*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
      Origin: 'https://localhost',
      Referer: 'https://localhost/',
      'X-Requested-With': 'com.example.app',
      'User-Agent': this.UA,
      Authorization: 'Bearer',
      tokenparam: `${ts},${this.APP_VERSION}`,
    };
  },

  /** Calls an API path on the first working domain and returns the decrypted `data`. */
  async api(path, params, form) {
    const automatic = !this.config.apiDomain || this.config.apiDomain === 'auto';
    if (automatic) await this.ensureRoute();
    let lastError = null;
    let refreshed = false;
    while (true) {
      for (const index of this.domainOrder()) {
        const domain = this.domains[index];
        try {
          const data = await this.requestApi(domain, path, params, form);
          this.preferred = index;
          return data;
        } catch (err) {
          if (automatic) this.store.set('route', null);
          if (form || ['LOGIN_REQUIRED', 'NOT_FOUND', 'HTTP'].includes(err?.code)) throw err;
          lastError = err;
          continue;
        }
      }
      // 线路可能在缓存到期前轮换，全部失败后刷新一次再重试。
      if (refreshed) break;
      refreshed = true;
      const before = this.domains.join('|');
      try { await this.refreshDomains(); } catch (_) {}
      if (!this.domains.length || this.domains.join('|') === before) break;
    }
    throw lastError || Park.error('NETWORK', '所有禁漫线路均不可用');
  },

  cover(id) {
    return `${this.imageHost}/media/albums/${id}_3x4.jpg`;
  },

  toItem(e) {
    const cat = (e.category && e.category.title) || '';
    const sub = (e.category_sub && e.category_sub.title) || '';
    return {
      id: String(e.id),
      title: e.name || `JM${e.id}`,
      subtitle: e.author || '',
      cover: this.cover(e.id),
      coverAspect: 0.75,
      category: sub && sub !== cat ? `${cat}·${sub}` : cat,
      likes: Park.utils.toInt(e.likes),
      views: Park.utils.toInt(e.total_views),
      uploaded: e.update_at ? Park.utils.formatDate(e.update_at) : '',
    };
  },

  pageOf(data, page) {
    const items = (data.content || data.list || []).map((e) => this.toItem(e));
    const total = Park.utils.toInt(data.total, 0);
    const totalPages = total ? Math.ceil(total / 80) : null;
    return { items, page, totalPages, total, hasNext: totalPages ? page < totalPages : items.length >= 80 };
  },

  async feed(key, req) {
    const page = Math.max(1, req.page || 1);
    const o = req.options || {};
    if (key === 'promote') {
      const data = await this.api('/promote', { page: 0 });
      const sections = (data || [])
        .filter((s) => !['library', 'novels'].includes(s.type) && Array.isArray(s.content) && s.content.length)
        .map((s) => ({ title: String(s.title || '').replace(/→.*$/, '').trim(), items: s.content.map((e) => this.toItem(e)) }));
      return { sections, page: 1, hasNext: false };
    }
    if (key === 'latest') return this.filter('0', 'mr', page);
    if (key === 'ranking') return this.filter('0', o.period || 'mv_w', page);
    return this.filter(o.category || 'doujin', o.sort || 'mr', page);
  },

  async filter(category, order, page) {
    const data = await this.api('/categories/filter', { page, order: '', c: category, o: order });
    return this.pageOf(data, page);
  },

  async search(req) {
    const page = Math.max(1, req.page || 1);
    const f = req.filters || {};
    const keyword = String(req.keyword || '').trim().replace(/^jm\s*(?=\d+$)/i, '');
    // The search endpoint returns nothing without a keyword: browse everything in the chosen order instead.
    if (!keyword) return this.filter('0', f.sort || 'mr', page);
    const data = await this.api('/search', {
      search_query: keyword,
      page,
      o: f.sort || 'mr',
      main_tag: f.mainTag || '0',
    });
    if (data && data.redirect_aid) {
      const d = await this.detail(String(data.redirect_aid));
      return { items: [d], page: 1, totalPages: 1, hasNext: false };
    }
    return this.pageOf(data, page);
  },

  async random() {
    const first = await this.filter('0', 'mr', 1);
    const pages = Math.max(1, Math.min(first.totalPages || 1, 200));
    const page = 1 + Math.floor(Math.random() * pages);
    const listing = page === 1 ? first : await this.filter('0', 'mr', page);
    const items = listing.items.length ? listing.items : first.items;
    if (!items.length) throw Park.error('NOT_FOUND', '没有可随机的作品');
    return items[Math.floor(Math.random() * items.length)].id;
  },

  async detail(id) {
    const aid = String(id).replace(/^jm/i, '');
    const d = await this.api('/album', { id: aid });
    if (!d || !d.name) throw Park.error('NOT_FOUND', 'JM{value0} 不存在', { params: {value0: aid} });
    const series = (d.series || []).slice().sort((a, b) => Number(a.sort) - Number(b.sort));
    const chapters = series.length
      ? series.map((e) => ({ id: String(e.id), title: String(e.name || '').trim() || `第 ${e.sort} 话` }))
      : null;
    const group = (label, list, mainTag) =>
      list && list.length
        ? { namespace: label, label, tags: list.map((name) => ({ name, keyword: name, filters: { mainTag } })) }
        : null;
    return {
      id: aid,
      title: d.name,
      subtitle: `JM${aid}`,
      cover: this.cover(aid),
      url: `https://18comic.vip/album/${aid}/`,
      authors: d.author || [],
      pages: Park.utils.toInt(d.total_photos, 0),
      likes: Park.utils.toInt(d.likes),
      views: Park.utils.toInt(d.total_views),
      uploaded: Park.utils.formatDate(d.addtime),
      description: String(d.description || '').trim(),
      comments: Park.utils.toInt(d.comment_total),
      tags: [
        group('作者', d.author, '2'),
        group('作品', d.works, '1'),
        group('登场人物', d.actors, '4'),
        group('标签', d.tags, '3'),
      ].filter(Boolean),
      chapters,
      related: (d.related_list || []).map((e) => this.toItem(e)),
    };
  },

  /** Number of strips an image was cut into (0 = not scrambled). */
  segments(photoId, filename, hash) {
    const pid = Number(photoId);
    if (pid < 220980) return 0;
    if (pid < 268850) return 10;
    const mod = pid < 421926 ? 10 : 8;
    return (hash.charCodeAt(hash.length - 1) % mod) * 2 + 2;
  },

  async chapter(id, chapterId) {
    const pid = String(chapterId || id).replace(/^jm/i, '');
    const d = await this.api('/chapter', { id: pid });
    const images = (d && d.images) || [];
    if (!images.length) throw Park.error('NOT_FOUND', '章节没有图片');
    const names = images.map((name) => name.replace(/\.[^.]+$/, ''));
    const hashes = await Park.crypto.md5Hex(names.map((n) => `${pid}${n}`));
    return {
      pages: images.map((name, i) => {
        const n = name.toLowerCase().endsWith('.gif') ? 0 : this.segments(pid, names[i], hashes[i]);
        const page = { url: `${this.imageHost}/media/photos/${pid}/${name}` };
        if (n > 1) page.transform = { type: 'unscramble-strips', segments: n };
        return page;
      }),
    };
  },
});

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"},{"key":"work","label":"作品连载","hint":"作品编号或详情链接"}],"searchFilters":{"sort":"mr"}});
