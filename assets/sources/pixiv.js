/* Pixiv — verified website JSON endpoints; static illustrations and manga only. */
(function () {
  'use strict';
  const HOME = 'https://www.pixiv.net';
  const LOGIN = '请登录 Pixiv；Cookie 可能已过期，R-18 内容还需在站点开启显示权限';
  const PARSE = 'Pixiv 返回的数据无效，请稍后重试';
  const contentOption = {
    key: 'content', label: '作品类型', default: '@setting', values: [
      { value: '@setting', label: '跟随设置' },
      { value: 'manga', label: '漫画' }, { value: 'illust', label: '插画' },
    ],
  };
  const ratingOption = {
    key: 'rating', label: '内容分级', default: 'all', values: [
      { value: 'all', label: '站点默认' }, { value: 'r18', label: 'R-18' },
    ],
  };
  function idValue(value) {
    const id = String(value);
    if (!/^[1-9]\d{0,11}$/.test(id)) throw Park.error('NOT_FOUND', 'Pixiv 作品编号无效');
    return id;
  }
  function pageNumber(value) {
    const page = Number(value === undefined ? 1 : value);
    if (!Number.isSafeInteger(page) || page < 1) throw Park.error('CONFIG', 'Pixiv 筛选参数无效');
    return page;
  }
  function choice(value, values, fallback) {
    const result = value === undefined || value === '' ? fallback : String(value);
    if (!values.includes(result)) throw Park.error('CONFIG', 'Pixiv 筛选参数无效');
    return result;
  }
  function imageUrl(value) {
    try {
      const u = new URL(String(value));
      if (u.protocol === 'https:' && !u.username && !u.password && !u.hash &&
          (!u.port || u.port === '443') && (u.hostname === 'pximg.net' || u.hostname.endsWith('.pximg.net'))) return u.href;
    } catch (_) {}
    throw Park.error('PARSE', PARSE);
  }
  function workType(work) { return Number(work.illustType === undefined ? work.illust_type : work.illustType); }
  function ratingBadge(work) {
    // Ranking's sexual field is a sensitivity level, not the xRestrict enum.
    const tags = Array.isArray(work.tags) ? work.tags : [];
    const rating = work.xRestrict === undefined ? (tags.includes('R-18G') ? 2 : tags.includes('R-18') ? 1 : 0) : Number(work.xRestrict);
    return rating === 2 ? 'R-18G' : rating === 1 ? 'R-18' : undefined;
  }
  function isVisible(work, content) {
    return work && workType(work) === (content === 'manga' ? 1 : 0) && !work.isMasked && !work.is_masked &&
      !(work.isAdContainer) && /^\d+$/.test(String(work.id || work.illust_id || ''));
  }
  function toItem(work, ranking = false) {
    const square = !ranking;
    return {
      id: idValue(work.id || work.illust_id), title: String(work.title || ''),
      subtitle: String(work.userName || work.user_name || ''), cover: imageUrl(work.url),
      authors: [String(work.userName || work.user_name || '')].filter(Boolean),
      coverAspect: square ? 1 : (Number(work.width) && Number(work.height) ? Number(work.width) / Number(work.height) : null),
      pages: Number(work.pageCount || work.illust_page_count) || 0,
      views: ranking ? Number(work.view_count) || 0 : undefined,
      category: workType(work) === 1 ? '漫画' : '插画',
      badge: ratingBadge(work),
      tags: Array.isArray(work.tags) ? work.tags.map(String) : [],
    };
  }
  Park.register({
    i18n: {
      "zh-Hant": {"Pixiv Cookie 格式无效":"Pixiv Cookie 格式無效","Pixiv 作品编号无效":"Pixiv 作品編號無效","Pixiv 动图暂不支持，请在站点查看":"Pixiv 動圖暫不支援，請在站點查看","Pixiv 筛选参数无效":"Pixiv 篩選參數無效","Pixiv 请求失败，请检查网络后重试":"Pixiv 請求失敗，請檢查網路後重試","Pixiv 账号":"Pixiv 帳號","Pixiv 返回的数据无效，请稍后重试":"Pixiv 傳回的資料無效，請稍後重試","作品类型":"作品類型","内容分级":"內容分級","匹配方式":"比對方式","插画":"插畫","插画与漫画社区，支持个性化推荐、排行、搜索和多页原图阅读":"插畫與漫畫社群，支援個人化推薦、排行、搜尋和多頁原圖閱讀","标签完全匹配":"標籤完全比對","标签部分匹配":"標籤部分比對","标题与简介":"標題與簡介","每日":"每日","站点默认":"站點預設","粘贴 Pixiv 的 PHPSESSID 值":"貼上 Pixiv 的 PHPSESSID 值","请登录 Pixiv；Cookie 可能已过期，R-18 内容还需在站点开启显示权限":"請登入 Pixiv；Cookie 可能已過期，R-18 內容還需在站點開啟顯示權限","输入关键词或标签，可筛选漫画、插画与 R-18 内容":"輸入關鍵字或標籤，可篩選漫畫、插畫與 R-18 內容","默认作品类型":"預設作品類型","登录可获得个性化推荐、点赞与收藏；R-18 内容需开启显示权限。Cookie 仅保存在本机。":"登入可獲得個人化推薦、按讚與收藏；R-18 內容需開啟顯示權限。Cookie 僅儲存在本機。","作者其他作品":"作者其他作品","原站不支持取消点赞":"原站不支援取消按讚"},
      "ja": {"Pixiv Cookie 格式无效":"Pixiv Cookie の形式が無効です","Pixiv 作品编号无效":"Pixiv の作品 ID が無効です","Pixiv 动图暂不支持，请在站点查看":"Pixiv のうごイラは未対応です。サイトでご覧ください","Pixiv 筛选参数无效":"Pixiv の絞り込み条件が無効です","Pixiv 请求失败，请检查网络后重试":"Pixiv へのリクエストに失敗しました。ネットワークを確認して再試行してください","Pixiv 账号":"Pixiv アカウント","Pixiv 返回的数据无效，请稍后重试":"Pixiv の応答データが無効です。後でもう一度お試しください","作品类型":"作品種別","内容分级":"対象年齢","匹配方式":"一致方式","插画":"イラスト","插画与漫画社区，支持个性化推荐、排行、搜索和多页原图阅读":"イラスト・漫画コミュニティ。おすすめ、ランキング、検索、複数ページの原寸画像に対応","标签完全匹配":"タグの完全一致","标签部分匹配":"タグの部分一致","标题与简介":"タイトルと説明","每日":"毎日","站点默认":"サイトの既定値","粘贴 Pixiv 的 PHPSESSID 值":"Pixiv の PHPSESSID の値を貼り付け","请登录 Pixiv；Cookie 可能已过期，R-18 内容还需在站点开启显示权限":"Pixiv にログインしてください。Cookie の期限が切れた可能性があります。R-18 はサイト側でも表示を有効にしてください","输入关键词或标签，可筛选漫画、插画与 R-18 内容":"キーワードやタグを入力。漫画、イラスト、R-18 で絞り込めます","默认作品类型":"既定の作品種別","登录可获得个性化推荐、点赞与收藏；R-18 内容需开启显示权限。Cookie 仅保存在本机。":"ログインすると個別のおすすめ、いいね、ブックマークを利用できます。R-18 は表示設定が必要です。Cookie は端末のみに保存されます。","作者其他作品":"作者の他の作品","原站不支持取消点赞":"このサイトではいいねを取り消せません"},
      "ko": {"Pixiv Cookie 格式无效":"Pixiv Cookie 형식이 올바르지 않습니다","Pixiv 作品编号无效":"Pixiv 작품 번호가 올바르지 않습니다","Pixiv 动图暂不支持，请在站点查看":"Pixiv 움직이는 일러스트는 아직 지원하지 않습니다. 사이트에서 확인하세요","Pixiv 筛选参数无效":"Pixiv 필터 값이 올바르지 않습니다","Pixiv 请求失败，请检查网络后重试":"Pixiv 요청에 실패했습니다. 네트워크를 확인한 후 다시 시도하세요","Pixiv 账号":"Pixiv 계정","Pixiv 返回的数据无效，请稍后重试":"Pixiv 응답 데이터가 올바르지 않습니다. 나중에 다시 시도하세요","作品类型":"작품 유형","内容分级":"콘텐츠 등급","匹配方式":"검색 방식","插画":"일러스트","插画与漫画社区，支持个性化推荐、排行、搜索和多页原图阅读":"일러스트·만화 커뮤니티. 맞춤 추천, 랭킹, 검색 및 여러 페이지 원본 감상 지원","标签完全匹配":"태그 완전 일치","标签部分匹配":"태그 부분 일치","标题与简介":"제목과 소개","每日":"매일","站点默认":"사이트 기본값","粘贴 Pixiv 的 PHPSESSID 值":"Pixiv의 PHPSESSID 값을 붙여넣으세요","请登录 Pixiv；Cookie 可能已过期，R-18 内容还需在站点开启显示权限":"Pixiv에 로그인하세요. Cookie가 만료되었을 수 있으며 R-18 콘텐츠는 사이트에서 표시 권한도 켜야 합니다","输入关键词或标签，可筛选漫画、插画与 R-18 内容":"키워드나 태그를 입력하고 만화, 일러스트, R-18 콘텐츠를 선택하세요","默认作品类型":"기본 작품 유형","登录可获得个性化推荐、点赞与收藏；R-18 内容需开启显示权限。Cookie 仅保存在本机。":"로그인하면 맞춤 추천, 좋아요, 북마크를 이용할 수 있습니다. R-18 표시를 설정에서 켜세요. Cookie는 이 기기에만 저장됩니다.","作者其他作品":"작가의 다른 작품","原站不支持取消点赞":"사이트에서 좋아요 취소를 지원하지 않음"},
      "en": {"Pixiv Cookie 格式无效":"Invalid Pixiv cookie format","Pixiv 作品编号无效":"Invalid Pixiv artwork ID","Pixiv 动图暂不支持，请在站点查看":"Pixiv animations are not supported yet. View them on the site","Pixiv 筛选参数无效":"Invalid Pixiv filter parameters","Pixiv 请求失败，请检查网络后重试":"Pixiv request failed. Check your network and try again","Pixiv 账号":"Pixiv account","Pixiv 返回的数据无效，请稍后重试":"Invalid data returned by Pixiv. Try again later","作品类型":"Work type","内容分级":"Content rating","匹配方式":"Match mode","插画":"Illustration","插画与漫画社区，支持个性化推荐、排行、搜索和多页原图阅读":"Illustration and manga community with personalized recommendations, rankings, search and multi-page originals","标签完全匹配":"Exact tag match","标签部分匹配":"Partial tag match","标题与简介":"Title and description","每日":"Daily","站点默认":"Site default","粘贴 Pixiv 的 PHPSESSID 值":"Paste the Pixiv PHPSESSID value","请登录 Pixiv；Cookie 可能已过期，R-18 内容还需在站点开启显示权限":"Sign in to Pixiv. The cookie may have expired; enable R-18 display on the site as well","输入关键词或标签，可筛选漫画、插画与 R-18 内容":"Enter keywords or tags; filter by manga, illustrations and R-18 content","默认作品类型":"Default work type","登录可获得个性化推荐、点赞与收藏；R-18 内容需开启显示权限。Cookie 仅保存在本机。":"Sign in for personalized recommendations, likes and bookmarks. Enable R-18 display in your account settings. Cookies stay on this device.","作者其他作品":"More by this creator","原站不支持取消点赞":"The site does not support undoing likes"},
      "es": {"Pixiv Cookie 格式无效":"Formato de cookie de Pixiv no válido","Pixiv 作品编号无效":"ID de obra de Pixiv no válido","Pixiv 动图暂不支持，请在站点查看":"Las animaciones de Pixiv aún no son compatibles. Ábrelas en el sitio","Pixiv 筛选参数无效":"Parámetros de filtro de Pixiv no válidos","Pixiv 请求失败，请检查网络后重试":"La solicitud a Pixiv falló. Comprueba la red e inténtalo de nuevo","Pixiv 账号":"Cuenta de Pixiv","Pixiv 返回的数据无效，请稍后重试":"Pixiv devolvió datos no válidos. Inténtalo más tarde","作品类型":"Tipo de obra","内容分级":"Clasificación de contenido","匹配方式":"Modo de coincidencia","插画":"Ilustración","插画与漫画社区，支持个性化推荐、排行、搜索和多页原图阅读":"Comunidad de ilustraciones y manga con recomendaciones, rankings, búsqueda y originales de varias páginas","标签完全匹配":"Coincidencia exacta de etiqueta","标签部分匹配":"Coincidencia parcial de etiqueta","标题与简介":"Título y descripción","每日":"Diario","站点默认":"Predeterminado del sitio","粘贴 Pixiv 的 PHPSESSID 值":"Pega el valor PHPSESSID de Pixiv","请登录 Pixiv；Cookie 可能已过期，R-18 内容还需在站点开启显示权限":"Inicia sesión en Pixiv. La cookie puede haber caducado; activa también la visualización de R-18 en el sitio","输入关键词或标签，可筛选漫画、插画与 R-18 内容":"Introduce palabras o etiquetas; filtra manga, ilustraciones y contenido R-18","默认作品类型":"Tipo de obra predeterminado","登录可获得个性化推荐、点赞与收藏；R-18 内容需开启显示权限。Cookie 仅保存在本机。":"Inicia sesión para recomendaciones personalizadas, Me gusta y favoritos. Activa R-18 en los ajustes. Las cookies se guardan solo en este dispositivo.","作者其他作品":"Más del autor","原站不支持取消点赞":"El sitio no permite deshacer Me gusta"},
      "ru": {"Pixiv Cookie 格式无效":"Некорректный формат Cookie Pixiv","Pixiv 作品编号无效":"Некорректный ID произведения Pixiv","Pixiv 动图暂不支持，请在站点查看":"Анимации Pixiv пока не поддерживаются. Смотрите их на сайте","Pixiv 筛选参数无效":"Некорректные параметры фильтра Pixiv","Pixiv 请求失败，请检查网络后重试":"Запрос Pixiv не удался. Проверьте сеть и повторите","Pixiv 账号":"Аккаунт Pixiv","Pixiv 返回的数据无效，请稍后重试":"Pixiv вернул некорректные данные. Повторите позже","作品类型":"Тип произведения","内容分级":"Возрастной рейтинг","匹配方式":"Режим совпадения","插画":"Иллюстрация","插画与漫画社区，支持个性化推荐、排行、搜索和多页原图阅读":"Сообщество иллюстраций и манги: рекомендации, рейтинги, поиск и многостраничные оригиналы","标签完全匹配":"Точное совпадение тега","标签部分匹配":"Частичное совпадение тега","标题与简介":"Название и описание","每日":"Ежедневно","站点默认":"По умолчанию на сайте","粘贴 Pixiv 的 PHPSESSID 值":"Вставьте значение PHPSESSID Pixiv","请登录 Pixiv；Cookie 可能已过期，R-18 内容还需在站点开启显示权限":"Войдите в Pixiv. Возможно, Cookie истёк; для R-18 также разрешите показ на сайте","输入关键词或标签，可筛选漫画、插画与 R-18 内容":"Введите слова или теги; фильтруйте мангу, иллюстрации и контент R-18","默认作品类型":"Тип произведений по умолчанию","登录可获得个性化推荐、点赞与收藏；R-18 内容需开启显示权限。Cookie 仅保存在本机。":"Войдите для персональных рекомендаций, отметок «Нравится» и закладок. Включите показ R-18 в настройках. Cookie хранятся только на устройстве.","作者其他作品":"Другие работы автора","原站不支持取消点赞":"Сайт не поддерживает отмену отметки «Нравится»"},
      "ar": {"Pixiv Cookie 格式无效":"تنسيق Cookie الخاص بـ Pixiv غير صالح","Pixiv 作品编号无效":"معرّف عمل Pixiv غير صالح","Pixiv 动图暂不支持，请在站点查看":"رسوم Pixiv المتحركة غير مدعومة حالياً. شاهدها في الموقع","Pixiv 筛选参数无效":"معلمات تصفية Pixiv غير صالحة","Pixiv 请求失败，请检查网络后重试":"فشل طلب Pixiv. تحقّق من الشبكة وحاول مجدداً","Pixiv 账号":"حساب Pixiv","Pixiv 返回的数据无效，请稍后重试":"أعاد Pixiv بيانات غير صالحة. حاول لاحقاً","作品类型":"نوع العمل","内容分级":"تصنيف المحتوى","匹配方式":"طريقة المطابقة","插画":"رسوم","插画与漫画社区，支持个性化推荐、排行、搜索和多页原图阅读":"مجتمع للرسوم والمانغا مع توصيات شخصية وترتيب وبحث وقراءة الصور الأصلية متعددة الصفحات","标签完全匹配":"مطابقة تامة للوسم","标签部分匹配":"مطابقة جزئية للوسم","标题与简介":"العنوان والوصف","每日":"يومي","站点默认":"الإعداد الافتراضي للموقع","粘贴 Pixiv 的 PHPSESSID 值":"الصق قيمة PHPSESSID من Pixiv","请登录 Pixiv；Cookie 可能已过期，R-18 内容还需在站点开启显示权限":"سجّل الدخول إلى Pixiv. قد تكون صلاحية Cookie انتهت؛ يجب أيضاً تفعيل عرض R-18 في الموقع","输入关键词或标签，可筛选漫画、插画与 R-18 内容":"أدخل كلمات أو وسوماً؛ صفِّ النتائج حسب المانغا والرسوم ومحتوى R-18","默认作品类型":"نوع العمل الافتراضي","登录可获得个性化推荐、点赞与收藏；R-18 内容需开启显示权限。Cookie 仅保存在本机。":"سجّل الدخول للتوصيات الشخصية والإعجابات والمفضلة. فعّل عرض R-18 في إعدادات الحساب. تُحفظ ملفات Cookie على الجهاز فقط.","作者其他作品":"أعمال أخرى للمبدع","原站不支持取消点赞":"لا يدعم الموقع إلغاء الإعجاب"},
    },
    key: 'pixiv', name: 'Pixiv', version: '0.0.11', minAppVersion: '0.9.2', type: 'comic', category: 'other',
    color: '#0096FA', icon: 'https://www.pixiv.net/favicon.ico',
    description: '插画与漫画社区，支持个性化推荐、排行、搜索和多页原图阅读',
    homepage: HOME, domains: ['pixiv.net'], language: 'multi',
    linkPatterns: ['pixiv\\.net/(?:[a-z]{2}/)?artworks/(\\d+)', 'pixiv\\.net/(?:member_illust|i)\\.php\\?[^#]*?illust_id=(\\d+)', 'pixiv\\.net/i/(\\d+)', 'pixiv\\.net/(?:[a-z]{2}/)?artworks\\?[^#]*?illust_id=(\\d+)'],
    idPattern: '^(?:pixiv)?([1-9]\\d{0,11})$', idExample: '150687026',
    // Mobile ranking pages ignore format=json; request the desktop representation.
    network: { vpnHint: true, headers: { Referer: HOME + '/', Accept: 'application/json',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
    } },
    imageHeaders: { Referer: HOME + '/' },
    settings: [{ key: 'content', type: 'select', label: '默认作品类型', default: 'manga', options: [
      { value: 'manga', label: '漫画' }, { value: 'illust', label: '插画' },
    ] }],
    account: {
      type: 'cookies', title: 'Pixiv 账号', required: false,
      hint: '登录可获得个性化推荐、点赞与收藏；R-18 内容需开启显示权限。Cookie 仅保存在本机。',
      loginUrl: 'https://accounts.pixiv.net/login?return_to=https%3A%2F%2Fwww.pixiv.net%2F',
      loginDomains: ['accounts.google.com', 'appleid.apple.com', 'account.apple.com', 'facebook.com', 'api.weibo.com', 'passport.weibo.com', 'passport.weibo.cn', 'login.sina.com.cn', 'x.com'],

      cookieUrl: HOME + '/', requiredCookies: ['PHPSESSID'],
      fields: [{ key: 'PHPSESSID', label: 'PHPSESSID', secret: true, hint: '粘贴 Pixiv 的 PHPSESSID 值' }],
      async login(values) {
        const session = String(values.PHPSESSID || '').trim();
        if (!session) throw Park.error('LOGIN_REQUIRED', LOGIN);
        if (!/^\d+_[A-Za-z0-9_-]+$/.test(session)) throw Park.error('CONFIG', 'Pixiv Cookie 格式无效');
        // Validate the candidate before replacing the current cookie jar.
        const headers = { Cookie: 'PHPSESSID=' + session };
        const extra = await this.request('/ajax/user/extra', { lang: 'zh' }, { auth: true, headers });
        if (!extra || typeof extra.following !== 'number' || !Number.isFinite(extra.following)) throw Park.error('LOGIN_REQUIRED', LOGIN);
        const userId = session.split('_')[0];
        const user = await this.request('/ajax/user/' + userId, { full: 0, lang: 'zh' }, { headers });
        if (!user || String(user.userId) !== userId) throw Park.error('LOGIN_REQUIRED', LOGIN);
        await this.cookies.set(HOME + '/', { PHPSESSID: session });
        this.store.set('account', { id: userId, name: String(user.name || 'Pixiv') });
        await this.store.flush();
        return { name: String(user.name || 'Pixiv') };
      },
      async logout() {
        await this.cookies.clear(HOME + '/');
        this.store.set('account', null);
        await this.store.flush();
      },
      async status() {
        const cookies = await this.cookies.get(HOME + '/');
        if (!/^\d+_[A-Za-z0-9_-]+$/.test(cookies.PHPSESSID || '')) return { loggedIn: false, configured: false, name: '' };
        const account = this.store.get('account') || {};
        try {
          const extra = await this.request('/ajax/user/extra', { lang: 'zh' }, { auth: true });
          if (!extra || typeof extra.following !== 'number' || !Number.isFinite(extra.following)) throw Park.error('LOGIN_REQUIRED', LOGIN);
          return { loggedIn: true, configured: true, name: account.name || 'Pixiv' };
        } catch (e) {
          if (e.code !== 'LOGIN_REQUIRED') throw e;
          return { loggedIn: false, configured: true, name: account.name || '' };
        }
      },
    },
    defaultFeed: 'recommended',
    rankings: [{key:'ranking',label:'排行榜',category:'other',metric:'站内热度',feed:'ranking'}],
    feeds: [
      { key: 'recommended', label: '推荐', options: [contentOption, ratingOption] },
      { key: 'ranking', label: '排行榜', options: [contentOption, ratingOption, {
        key: 'period', label: '周期', default: 'daily', values: [
          { value: 'daily', label: '每日' }, { value: 'weekly', label: '每周' },
        ],
      }] },
    ],
    searchHint: '输入关键词或标签，可筛选漫画、插画与 R-18 内容',
    searchFilters: [contentOption, ratingOption, {
      key: 'match', label: '匹配方式', default: 's_tag', values: [
        { value: 's_tag', label: '标签部分匹配' }, { value: 's_tag_full', label: '标签完全匹配' },
        { value: 's_tc', label: '标题与简介' },
      ],
    }, { key: 'sort', label: '排序', default: 'date_d', values: [
      { value: 'date_d', label: '新到旧' }, { value: 'date', label: '旧到新' },
    ] }],

    contentOf(options) {
      const selected = options && options.content;
      return choice(!selected || selected === '@setting' ? this.config.content : selected, ['manga', 'illust'], 'manga');
    },
    async requireLogin() {
      const cookies = await this.cookies.get(HOME + '/');
      if (!/^\d+_[A-Za-z0-9_-]+$/.test(cookies.PHPSESSID || '')) throw Park.error('LOGIN_REQUIRED', LOGIN);
      const extra = await this.request('/ajax/user/extra', { lang: 'zh' }, { auth: true });
      if (!extra || typeof extra.following !== 'number' || !Number.isFinite(extra.following)) throw Park.error('LOGIN_REQUIRED', LOGIN);
    },
    async searchSuggestions(keyword) {
      keyword = String(keyword || '').trim();
      if (!keyword) return [];
      const response = await this.http.get(HOME + '/rpc/cps.php', { params: { keyword, lang: 'zh' } });
      if (!response.ok) throw Park.error('HTTP', 'Pixiv 请求失败，请检查网络后重试', { status: response.status });
      let data;
      try { data = JSON.parse(response.body); } catch (_) { throw Park.error('PARSE', PARSE); }
      if (!Array.isArray(data?.candidates)) throw Park.error('PARSE', PARSE);
      return data.candidates.filter(c => typeof c.tag_name === 'string').slice(0, 10)
        .map(c => ({ keyword: c.tag_name, label: c.tag_name, subtitle: c.tag_translation || '' }));
    },
    async request(path, params = {}, { auth = false, headers = {} } = {}) {
      const response = await this.http.get(HOME + path, { params, headers });
      if (response.status === 401 || (auth && [400, 403].includes(response.status))) throw Park.error('LOGIN_REQUIRED', LOGIN);
      if (response.status === 404) throw Park.error('NOT_FOUND', '内容不存在或已被删除');
      if (!response.ok) throw Park.error('HTTP', 'Pixiv 请求失败，请检查网络后重试', { status: response.status });
      let data;
      try { data = JSON.parse(response.body); } catch (_) { throw Park.error('PARSE', PARSE); }
      if (!data || typeof data !== 'object') throw Park.error('PARSE', PARSE);
      if (data.error) {
        if (auth || /login|ログイン|登录|登入|age|年齢|年龄|閲覧|浏览|权限/i.test(String(data.message || ''))) throw Park.error('LOGIN_REQUIRED', LOGIN);
        if (/not found|見つか|不存在|已删除|削除/i.test(String(data.message || ''))) throw Park.error('NOT_FOUND', '内容不存在或已被删除');
        throw Park.error('PARSE', PARSE);
      }
      return path === '/ranking.php' ? data : data.body;
    },
    async feed(key, req = {}) {
      const page = pageNumber(req.page), options = req.options || {};
      const content = this.contentOf(options);
      const rating = choice(options.rating, ['all', 'r18'], 'all');
      if (key === 'recommended') {
        if (rating === 'r18') await this.requireLogin();
        // Discovery returns a fresh recommendation batch on every request, including anonymously.
        const data = await this.request('/ajax/illust/discovery', { mode: rating, limit: 60, lang: 'zh' }, { auth: rating === 'r18' });
        if (!data || !Array.isArray(data.illusts)) throw Park.error('PARSE', PARSE);
        const hasNext = data.illusts.length > 0;
        return { items: data.illusts.filter(w => isVisible(w, content)).map(w => toItem(w)), page,
          hasNext, cursor: hasNext ? String(page) : null };
      }
      if (key !== 'ranking') throw Park.error('CONFIG', 'Pixiv 筛选参数无效');
      if (rating === 'r18') await this.requireLogin();
      const period = choice(options.period, ['daily', 'weekly'], 'daily');
      const params = { mode: period + (rating === 'r18' ? '_r18' : ''), content: content === 'manga' ? 'manga' : 'illust', format: 'json', p: page };
      if (req.cursor) {
        if (!/^\d{8}$/.test(String(req.cursor))) throw Park.error('CONFIG', 'Pixiv 筛选参数无效');
        params.date = String(req.cursor);
      }
      const data = await this.request('/ranking.php', params, { auth: rating === 'r18' });
      if (!data || !Array.isArray(data.contents)) throw Park.error('PARSE', PARSE);
      const items = data.contents.filter(w => isVisible(w, content)).map(w => toItem(w, true));
      const hasNext = Number(data.next) > page;
      const date = String(data.date || '');
      if (!/^\d{8}$/.test(date)) throw Park.error('PARSE', PARSE);
      return { items, page, hasNext, cursor: hasNext ? date : null };
    },
    async search(req = {}) {
      const page = pageNumber(req.page), filters = req.filters || {};
      const keyword = String(req.keyword || '').trim();
      if (!keyword) return { items: [], page, hasNext: false };
      const content = this.contentOf(filters), rating = choice(filters.rating, ['all', 'r18'], 'all');
      if (rating === 'r18') await this.requireLogin();
      const params = { word: keyword, order: choice(filters.sort, ['date_d', 'date'], 'date_d'), mode: rating,
        p: page, s_mode: choice(filters.match, ['s_tag', 's_tag_full', 's_tc'], 's_tag'), type: content, lang: 'zh' };
      const data = await this.request('/ajax/search/' + (content === 'manga' ? 'manga' : 'illustrations') + '/' + encodeURIComponent(keyword), params, { auth: rating === 'r18' });
      const list = data && data[content === 'manga' ? 'manga' : 'illust'];
      if (!list || !Array.isArray(list.data) || !Number.isSafeInteger(Number(list.lastPage)) || Number(list.lastPage) < 0) throw Park.error('PARSE', PARSE);
      return { items: list.data.filter(w => isVisible(w, content)).map(w => toItem(w)), page,
        total: Number(list.total) || 0, totalPages: Number(list.lastPage), hasNext: page < Number(list.lastPage) };
    },
    async artwork(id) {
      const key = idValue(id);
      const data = await this.request('/ajax/illust/' + key, { lang: 'zh' });
      if (!data || String(data.id) !== key) throw Park.error('PARSE', PARSE);
      if (![0, 1].includes(Number(data.illustType))) throw Park.error('UNSUPPORTED', 'Pixiv 动图暂不支持，请在站点查看');
      if (data.isMasked || !data.urls || !data.urls.original) throw Park.error('LOGIN_REQUIRED', LOGIN);
      if (data.isLoginOnly || Number(data.xRestrict) > 0) await this.requireLogin();
      return data;
    },
    async related(id, req = {}) {
      id = idValue(id);
      const page = pageNumber(req.page);
      let data, remaining;
      if (page === 1) {
        data = await this.request('/ajax/illust/' + id + '/recommend/init', { limit: 18, lang: 'zh' });
        if (!data || !Array.isArray(data.nextIds)) throw Park.error('PARSE', PARSE);
        remaining = [...new Set(data.nextIds.map(idValue))];
      } else {
        try { remaining = JSON.parse(String(req.cursor)); } catch (_) { throw Park.error('CONFIG', PARSE); }
        if (!Array.isArray(remaining) || !remaining.length || remaining.length > 10000) throw Park.error('CONFIG', PARSE);
        remaining = remaining.map(idValue);
        const ids = remaining.slice(0, 18);
        data = await this.request('/ajax/illust/recommend/illusts?'+ids.map(value => 'illust_ids%5B%5D='+value).join('&'), { lang: 'zh' });
        remaining = remaining.slice(ids.length);
      }
      if (!data || !Array.isArray(data.illusts)) throw Park.error('PARSE', PARSE);
      const works = data.illusts.filter(w => [0, 1].includes(workType(w)) && !w.isMasked && String(w.id) !== id);
      const seen = new Set([id, ...works.map(w => String(w.id))]);
      remaining = remaining.filter(value => !seen.has(value));
      return {items: works.map(w => toItem(w)), page, hasNext: remaining.length > 0,
        cursor: remaining.length ? JSON.stringify(remaining) : null};
    },
    async interaction(id, req = {}) {
      id = idValue(id);
      await this.requireLogin();
      let data = await this.artwork(id);
      if (req.value !== undefined) {
        if (!['like', 'favorite'].includes(req.type) || typeof req.value !== 'boolean') throw Park.error('CONFIG', '原站互动数据无效');
        if (req.type === 'like' && !req.value) throw Park.error('UNSUPPORTED', '原站不支持取消点赞');
        const current = req.type === 'like' ? data.likeData === true : !!data.bookmarkData;
        if (current !== req.value) {
          const page = await this.http.get(HOME + '/artworks/' + id);
          if (!page.ok) throw Park.error('LOGIN_REQUIRED', LOGIN);
          const node = Park.html.parse(page.body).querySelector('meta[name="global-data"], meta[id="meta-global-data"]');
          let token;
          try { token = JSON.parse(node && node.getAttribute('content')).token; } catch (_) {}
          if (typeof token !== 'string' || !token) throw Park.error('LOGIN_REQUIRED', LOGIN);
          const path = req.type === 'like' ? '/ajax/illusts/like' : req.value ? '/ajax/illusts/bookmarks/add' : '/ajax/illusts/bookmarks/delete';
          const json = req.type === 'like' ? {illust_id: id} : req.value ? {illust_id: id, restrict: 0, comment: '', tags: []} : {bookmarkIds: [String(data.bookmarkData.id)]};
          const res = await this.http.post(HOME + path, {json, headers: {'x-csrf-token': token, Referer: HOME + '/artworks/' + id}});
          if ([401, 403].includes(res.status)) throw Park.error('LOGIN_REQUIRED', LOGIN);
          let result; try { result = res.json(); } catch (_) { throw Park.error('PARSE', PARSE); }
          if (!res.ok || result.error) throw Park.error('AUTH', '原站操作未成功，请重试');
          data = await this.artwork(id);
          if ((req.type === 'like' ? data.likeData === true : !!data.bookmarkData) !== req.value) throw Park.error('AUTH', '原站操作未成功，请重试');
        }
      }
      if (typeof data.likeData !== 'boolean') throw Park.error('PARSE', '原站互动数据无效');
      return [{type: 'like', value: data.likeData, canUnset: false}, {type: 'favorite', value: !!data.bookmarkData}];
    },
    async detail(id) {
      const data = await this.artwork(id);
      const tags = (data.tags && data.tags.tags || []).map(t => ({ name: String(t.tag), keyword: String(t.tag), filters: { match: 's_tag_full' } }));
      return {
        id: String(data.id), title: String(data.title || data.illustTitle || ''),
        cover: imageUrl(data.urls.small || data.urls.regular || data.urls.original),
        coverAspect: Number(data.width) && Number(data.height) ? Number(data.width) / Number(data.height) : null,
        url: HOME + '/artworks/' + data.id, authors: [String(data.userName || '')].filter(Boolean),
        description: Park.html.strip(String(data.description || data.illustComment || '').replace(/<br\s*\/?\s*>/gi, '\n')),
        category: Number(data.illustType) === 1 ? '漫画' : '插画', pages: Number(data.pageCount) || 0,
        likes: Number(data.bookmarkCount) || 0, views: Number(data.viewCount) || 0,
        uploaded: data.uploadDate || data.createDate || '',
        badge: ratingBadge(data),
        relatedSections: [{title: '作者其他作品', items: Object.values(data.userIllusts || {})
          .filter(w => w && [0, 1].includes(workType(w)) && !w.isMasked && String(w.id) !== String(data.id))
          .map(w => toItem(w))}],
        tags: [{ namespace: 'tag', label: '标签', tags }], chapters: null,
      };
    },
    subscription: {
      async media(scope, options={}) {
        // 排行游标包含日期与页号；公共相册不依赖站点私有分页语义。
        let state={};
        if(options.cursor){try{state=JSON.parse(options.cursor);}catch(_){throw Park.error('CONFIG','Pixiv 筛选参数无效');}}
        const result=await this.feed(scope.feed,{page:options.page,cursor:state.token,options:scope.options});
        const items=await Park.utils.mapLimit(result.items,3,async item=>{
          const data=await this.artwork(item.id);
          const images=await this.request('/ajax/illust/'+idValue(item.id)+'/pages',{lang:'zh'});
          if(!Array.isArray(images)||images.length!==Number(data.pageCount))throw Park.error('PARSE',PARSE);
          return {...item,presentation:'work',date:data.uploadDate||data.createDate||'',
            media:images.map((p,i)=>({id:String(i),type:'image',url:imageUrl(p.urls?.original),preview:imageUrl(p.urls?.small||p.urls?.regular||p.urls?.original)}))};
        });
        const hasNext=result.hasNext;
        return {...result,items,hasNext,cursor:hasNext?JSON.stringify({page:Number(options.page)||1,token:result.cursor}):null};
      },
    },
    async chapter(id) {
      const data = await this.artwork(id);
      const images = await this.request('/ajax/illust/' + idValue(id) + '/pages', { lang: 'zh' });
      if (!Array.isArray(images) || !images.length || images.length !== Number(data.pageCount)) throw Park.error('PARSE', PARSE);
      return { pages: images.map(p => ({ url: imageUrl(p.urls && p.urls.original), width: Number(p.width) || 0, height: Number(p.height) || 0 })) };
    },
  });
})();

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"}]});
