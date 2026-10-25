/*
 * E-Hentai / ExHentai.
 * - Lists (search / popular / toplist) are HTML; only (gid, token) pairs are scraped from them and all
 *   metadata comes from the JSON gdata API, which keeps us independent of list layouts.
 * - Search pagination is cursor based (next=<gid>); the cursor is handed back to the host.
 * - Images: gallery thumbnail pages (?p=N) give per-page links /s/{key}/{gid}-{n}; the first single page
 *   gives the image plus a `showkey`, later pages use the faster `showpage` API. Retries pass the `nl`
 *   token so the server hands out a different H@H node. 509.gif means the image quota is exhausted.
 * - All requests are rate limited to avoid temporary IP bans.
 */
(function () {
const browseFilters = [
    {
      key: 'categories',
      label: '分类',
      type: 'multi',
      default: [],
      values: [
        { value: 'Doujinshi', label: '同人志', color: '#9E2720' },
        { value: 'Manga', label: '漫画', color: '#DB6C24' },
        { value: 'Artist CG', label: '画师CG', color: '#D38F1D' },
        { value: 'Game CG', label: '游戏CG', color: '#617C63' },
        { value: 'Western', label: '西方', color: '#AB9F60' },
        { value: 'Non-H', label: '非H', color: '#5FA9CF' },
        { value: 'Image Set', label: '图集', color: '#325CA2' },
        { value: 'Cosplay', label: 'Cosplay', color: '#6A32A2' },
        { value: 'Asian Porn', label: '亚洲', color: '#A23282' },
        { value: 'Misc', label: '杂项', color: '#777777' },
      ],
    },
    {
      key: 'language',
      label: '语言',
      default: '',
      values: [
        { value: '', label: '不限' },
        { value: 'chinese', label: '中文' },
        { value: 'japanese', label: '日文' },
        { value: 'english', label: '英文' },
      ],
    },
    {
      key: 'minRating',
      label: '最低评分',
      default: '0',
      values: [
        { value: '0', label: '不限' },
        { value: '2', label: '2 星' },
        { value: '3', label: '3 星' },
        { value: '4', label: '4 星' },
        { value: '5', label: '5 星' },
      ],
    },
    { key: 'minPages', label: '最少页数', type: 'number', default: 0 },
  ];
Park.register({
  i18n: {
    "zh-Hant": {"0.2 秒（激进）": "0.2 秒（激進）", "0.4 秒（推荐）": "0.4 秒（推薦）", "0.8 秒（保守）": "0.8 秒（保守）", "2 星": "2 星", "3 星": "3 星", "32 位十六进制字符": "32 位十六進位制字元", "4 星": "4 星", "5 星": "5 星", "E-Hentai 只能按顺序翻页": "E-Hentai 只能按順序翻頁", "E-Hentai 图片配额已用尽（509），请稍后再试或登录后重置配额": "E-Hentai 圖片配額已用盡（509），請稍後再試或登入後重置配額", "E-Hentai 账号": "E-Hentai 賬號", "E-Hentai（表站）": "E-Hentai（表站）", "ExHentai 返回空页面：请先登录，或该账号没有里站权限": "ExHentai 返回空頁面：請先登入，或該賬號沒有裡站許可權", "ExHentai（里站）": "ExHentai（裡站）", "IP 被 E-Hentai 临时封禁，请稍后再试或更换网络": "IP 被 E-Hentai 臨時封禁，請稍後再試或更換網路", "临时": "臨時", "亚洲": "亞洲", "会员 ID，一串数字": "會員 ID，一串數字", "会员 {value0}": "會員 {value0}", "历史最悠久的画廊站，标签体系完善；登录后可切换里站 ExHentai": "歷史最悠久的畫廊站，標籤體系完善；登入後可切換裡站 ExHentai", "女性": "女性", "当前热门": "當前熱門", "找不到第 {value0} 页": "找不到第 {value0} 頁", "支持标签语法：female:\"big breasts\"$、artist:xxx、language:chinese": "支援標籤語法：female:\"big breasts\"$、artist:xxx、language:chinese", "无效的画廊 ID：{value0}": "無效的畫廊 ID：{value0}", "昨日": "昨日", "最低评分": "最低評分", "杂项": "雜項", "没有符合条件的画廊": "沒有符合條件的畫廊", "混合": "混合", "游戏CG": "遊戲CG", "男性": "男性", "画师CG": "畫師CG", "画廊不存在或已被删除": "畫廊不存在或已被刪除", "画廊没有图片": "畫廊沒有圖片", "登录后可以访问里站 ExHentai，并解除部分画廊的访问限制。": "登入後可以訪問裡站 ExHentai，並解除部分畫廊的訪問限制。", "私有": "私有", "第 {value0} 页没有图片": "第 {value0} 頁沒有圖片", "缺少 ipb_member_id 或 ipb_pass_hash": "缺少 ipb_member_id 或 ipb_pass_hash", "西方": "西方", "访问里站时需要": "訪問裡站時需要", "请求间隔": "請求間隔", "近一年": "近一年", "近一月": "近一月", "里站 ExHentai 需要登录且账号有访问权限": "裡站 ExHentai 需要登入且賬號有訪問許可權", "重分类": "重分類", "间隔过短容易被临时封禁 IP": "間隔過短容易被臨時封禁 IP", "非H": "非H", "韩文": "韓文"},
    "ja": {"0.2 秒（激进）": "0.2 秒 (アグレッシブ)", "0.4 秒（推荐）": "0.4秒（推奨）", "0.8 秒（保守）": "0.8 秒 (保守的)", "2 星": "2つ星", "3 星": "3つ星", "32 位十六进制字符": "32ビットの16進文字", "4 星": "星4つ", "5 星": "5つ星", "E-Hentai 只能按顺序翻页": "E-Hentai のページは順番に読み込む必要があります", "E-Hentai 图片配额已用尽（509），请稍后再试或登录后重置配额": "E-Hentai 画像の割り当て量がなくなりました (509)。後でもう一度試すか、ログイン後に割り当て量をリセットしてください。", "E-Hentai 账号": "E-Hentai アカウント", "E-Hentai（表站）": "E-Hentai（公開サイト）", "ExHentai 返回空页面：请先登录，或该账号没有里站权限": "ExHentai が空のページを返しました。ログインしていないか、アカウントにアクセス権がありません", "ExHentai（里站）": "ExHentai（アクセス制限あり）", "IP 被 E-Hentai 临时封禁，请稍后再试或更换网络": "IP は E-Hentai によって一時的にブロックされています。後でもう一度試すか、ネットワークを変更してください。", "临时": "一時的な", "亚洲": "アジア", "会员 ID，一串数字": "会員ID、数字の列", "会员 {value0}": "会員 {value0}", "历史最悠久的画廊站，标签体系完善；登录后可切换里站 ExHentai": "長い歴史と豊富なタグを持つギャラリーサイト。アクセス権のあるアカウントでログインすると ExHentai に切り替えられます", "女性": "女性", "当前热门": "現在のホットトピック", "找不到第 {value0} 页": "ページ {value0} が見つかりません", "支持标签语法：female:\"big breasts\"$、artist:xxx、language:chinese": "タグ構文：female:\"big breasts\"$、artist:xxx、language:chinese", "无效的画廊 ID：{value0}": "無効なギャラリー ID: {value0}", "昨日": "昨日", "最低评分": "最低スコア", "杂项": "その他", "没有符合条件的画廊": "一致するギャラリーがありません", "混合": "ミックス", "游戏CG": "ゲームCG", "男性": "男性", "画师CG": "ペインターCG", "画廊不存在或已被删除": "ギャラリーが存在しないか、削除されています", "画廊没有图片": "ギャラリーには写真がありません", "登录后可以访问里站 ExHentai，并解除部分画廊的访问限制。": "ログイン後、ExHentai サイトにアクセスし、一部のギャラリーへのアクセス制限を解除できます。", "私有": "プライベート", "第 {value0} 页没有图片": "ページ {value0} には画像がありません", "缺少 ipb_member_id 或 ipb_pass_hash": "ipb_member_id または ipb_pass_hash がありません", "西方": "ウェスト", "访问里站时需要": "サイト訪問時に必要", "请求间隔": "リクエスト間隔", "近一年": "ほぼ１年", "近一月": "ほぼ一ヶ月", "里站 ExHentai 需要登录且账号有访问权限": "ExHentai の利用には、アクセス権のあるアカウントでのログインが必要です", "重分类": "再分類", "间隔过短容易被临时封禁 IP": "間隔が短すぎる場合、IP が一時的に禁止される可能性があります。", "非H": "Hではない", "韩文": "韓国人"},
    "ko": {"0.2 秒（激进）": "0.2초(공격적)", "0.4 秒（推荐）": "0.4초(권장)", "0.8 秒（保守）": "0.8초(보수적)", "2 星": "별 2개", "3 星": "별 3개", "32 位十六进制字符": "16진수 문자 32개", "4 星": "별 4개", "5 星": "별 5개", "E-Hentai 只能按顺序翻页": "E-Hentai 페이지는 순서대로만 불러올 수 있습니다", "E-Hentai 图片配额已用尽（509），请稍后再试或登录后重置配额": "E-Hentai 사진 할당량이 소진되었습니다(509). 나중에 다시 시도하거나 로그인 후 할당량을 재설정하십시오.", "E-Hentai 账号": "E-Hentai 계정", "E-Hentai（表站）": "E-Hentai (공개 사이트)", "ExHentai 返回空页面：请先登录，或该账号没有里站权限": "ExHentai가 빈 페이지를 반환했습니다. 로그인하지 않았거나 계정에 접근 권한이 없습니다", "ExHentai（里站）": "ExHentai (접근 제한 사이트)", "IP 被 E-Hentai 临时封禁，请稍后再试或更换网络": "IP가 E-Hentai에 의해 일시적으로 차단되었습니다. 나중에 다시 시도하거나 네트워크를 변경하세요.", "临时": "일시적인", "亚洲": "아시아", "会员 ID，一串数字": "회원 ID, 일련의 숫자", "会员 {value0}": "회원 {value0}", "历史最悠久的画廊站，标签体系完善；登录后可切换里站 ExHentai": "오랜 역사를 가진 갤러리 사이트로 태그가 풍부합니다. 접근 권한이 있는 계정으로 로그인하면 ExHentai로 전환할 수 있습니다", "女性": "여성", "当前热门": "현재 인기 있는", "找不到第 {value0} 页": "페이지 {value0}를 찾을 수 없습니다", "支持标签语法：female:\"big breasts\"$、artist:xxx、language:chinese": "태그 구문: female:\"big breasts\"$, artist:xxx, language:chinese", "无效的画廊 ID：{value0}": "잘못된 갤러리 ID: {value0}", "昨日": "어제", "最低评分": "최저 등급", "杂项": "여러 가지 잡다한", "没有符合条件的画廊": "일치하는 갤러리가 없습니다.", "混合": "혼합", "游戏CG": "게임 CG", "男性": "남성", "画师CG": "화가 CG", "画廊不存在或已被删除": "갤러리가 존재하지 않거나 삭제되었습니다.", "画廊没有图片": "갤러리에 사진이 없습니다", "登录后可以访问里站 ExHentai，并解除部分画廊的访问限制。": "로그인한 후 ExHentai 사이트에 액세스하고 일부 갤러리에 대한 액세스 제한을 제거할 수 있습니다.", "私有": "사적인", "第 {value0} 页没有图片": "페이지 {value0}에 이미지가 없습니다.", "缺少 ipb_member_id 或 ipb_pass_hash": "ipb_member_id 또는 ipb_pass_hash 누락", "西方": "서쪽", "访问里站时需要": "사이트 접속 시 필수", "请求间隔": "요청 간격", "近一年": "거의 1년", "近一月": "거의 한 달", "里站 ExHentai 需要登录且账号有访问权限": "ExHentai를 이용하려면 접근 권한이 있는 계정으로 로그인해야 합니다", "重分类": "재분류", "间隔过短容易被临时封禁 IP": "간격이 너무 짧을 경우 해당 IP가 일시적으로 차단될 수 있습니다.", "非H": "H 아님", "韩文": "한국인"},
    "en": {"0.2 秒（激进）": "0.2 seconds (aggressive)", "0.4 秒（推荐）": "0.4 seconds (recommended)", "0.8 秒（保守）": "0.8 seconds (conservative)", "2 星": "2 stars", "3 星": "3 stars", "32 位十六进制字符": "32-bit hexadecimal characters", "4 星": "4 stars", "5 星": "5 stars", "E-Hentai 只能按顺序翻页": "E-Hentai pages can only be loaded sequentially", "E-Hentai 图片配额已用尽（509），请稍后再试或登录后重置配额": "E-Hentai picture quota has been exhausted (509), please try again later or reset the quota after logging in", "E-Hentai 账号": "E-Hentai account", "E-Hentai（表站）": "E-Hentai (public site)", "ExHentai 返回空页面：请先登录，或该账号没有里站权限": "ExHentai returned an empty page: sign in first, or check that your account has access", "ExHentai（里站）": "ExHentai (restricted site)", "IP 被 E-Hentai 临时封禁，请稍后再试或更换网络": "The IP is temporarily blocked by E-Hentai, please try again later or change the network", "临时": "Temporary", "亚洲": "Asia", "会员 ID，一串数字": "Member ID, a string of numbers", "会员 {value0}": "Member {value0}", "历史最悠久的画廊站，标签体系完善；登录后可切换里站 ExHentai": "A long-established gallery site with extensive tags; sign in to switch to ExHentai if your account has access", "女性": "Female", "当前热门": "Current hot topics", "找不到第 {value0} 页": "Page {value0} not found", "支持标签语法：female:\"big breasts\"$、artist:xxx、language:chinese": "Tag syntax: female:\"big breasts\"$, artist:xxx, language:chinese", "无效的画廊 ID：{value0}": "Invalid gallery ID: {value0}", "昨日": "Yesterday", "最低评分": "lowest score", "杂项": "Miscellaneous", "没有符合条件的画廊": "No matching galleries", "混合": "Mix", "游戏CG": "Game CG", "男性": "Male", "画师CG": "Painter CG", "画廊不存在或已被删除": "The gallery does not exist or has been deleted", "画廊没有图片": "There are no pictures in the gallery", "登录后可以访问里站 ExHentai，并解除部分画廊的访问限制。": "After logging in, you can access ExHentai, and lift access restrictions on some galleries.", "私有": "Private", "第 {value0} 页没有图片": "Page {value0} has no picture", "缺少 ipb_member_id 或 ipb_pass_hash": "Missing ipb_member_id or ipb_pass_hash", "西方": "West", "访问里站时需要": "Needed when visiting the site", "请求间隔": "Request interval", "近一年": "Nearly one year", "近一月": "Nearly one month", "里站 ExHentai 需要登录且账号有访问权限": "ExHentai requires sign-in with an account that has access permission", "重分类": "Reclassification", "间隔过短容易被临时封禁 IP": "If the interval is too short, the IP will be temporarily blocked.", "非H": "Not H", "韩文": "Korean"},
    "es": {"0.2 秒（激进）": "0,2 segundos (agresivo)", "0.4 秒（推荐）": "0,4 segundos (recomendado)", "0.8 秒（保守）": "0,8 segundos (conservador)", "2 星": "2 estrellas", "3 星": "3 estrellas", "32 位十六进制字符": "Caracteres hexadecimales de 32 bits", "4 星": "4 estrellas", "5 星": "5 estrellas", "E-Hentai 只能按顺序翻页": "Las páginas de E-Hentai solo se pueden cargar en orden", "E-Hentai 图片配额已用尽（509），请稍后再试或登录后重置配额": "La cuota de imágenes E-Hentai se ha agotado (509), inténtelo de nuevo más tarde o restablezca la cuota después de iniciar sesión", "E-Hentai 账号": "Cuenta de E-Hentai", "E-Hentai（表站）": "E-Hentai (sitio público)", "ExHentai 返回空页面：请先登录，或该账号没有里站权限": "ExHentai devolvió una página vacía: inicia sesión o comprueba los permisos de tu cuenta", "ExHentai（里站）": "ExHentai (acceso restringido)", "IP 被 E-Hentai 临时封禁，请稍后再试或更换网络": "La IP está bloqueada temporalmente por E-Hentai, inténtelo nuevamente más tarde o cambie la red", "临时": "Temporal", "亚洲": "Asia", "会员 ID，一串数字": "ID de miembro, una cadena de números", "会员 {value0}": "Miembro {value0}", "历史最悠久的画廊站，标签体系完善；登录后可切换里站 ExHentai": "Sitio de galerías de larga trayectoria con etiquetas detalladas; inicia sesión para cambiar a ExHentai si tu cuenta tiene acceso", "女性": "Mujer", "当前热门": "Temas candentes actuales", "找不到第 {value0} 页": "Página {value0} no encontrada", "支持标签语法：female:\"big breasts\"$、artist:xxx、language:chinese": "Sintaxis de etiquetas: female:\"big breasts\"$, artist:xxx, language:chinese", "无效的画廊 ID：{value0}": "ID de galería no válida: {value0}", "昨日": "Ayer", "最低评分": "puntuación más baja", "杂项": "Varios", "没有符合条件的画廊": "No hay galerías coincidentes", "混合": "Mezclar", "游戏CG": "Juego CG", "男性": "Masculino", "画师CG": "Pintor CG", "画廊不存在或已被删除": "La galería no existe o ha sido eliminada", "画廊没有图片": "No hay imágenes en la galería.", "登录后可以访问里站 ExHentai，并解除部分画廊的访问限制。": "Después de iniciar sesión, puede acceder a ExHentai y eliminar las restricciones de acceso en algunas galerías.", "私有": "Privado", "第 {value0} 页没有图片": "La página {value0} no tiene imagen", "缺少 ipb_member_id 或 ipb_pass_hash": "Falta ipb_member_id o ipb_pass_hash", "西方": "Oeste", "访问里站时需要": "Necesario al visitar el sitio", "请求间隔": "Intervalo de solicitud", "近一年": "Casi un año", "近一月": "Casi un mes", "里站 ExHentai 需要登录且账号有访问权限": "ExHentai requiere iniciar sesión con una cuenta que tenga permiso de acceso", "重分类": "Reclasificación", "间隔过短容易被临时封禁 IP": "Si el intervalo es demasiado corto, la IP se bloqueará temporalmente.", "非H": "No H", "韩文": "coreano"},
    "ru": {"0.2 秒（激进）": "0,2 секунды (агрессивный)", "0.4 秒（推荐）": "0,4 секунды (рекомендуется)", "0.8 秒（保守）": "0,8 секунды (консервативный)", "2 星": "2 звезды", "3 星": "3 звезды", "32 位十六进制字符": "32-битные шестнадцатеричные символы", "4 星": "4 звезды", "5 星": "5 звезд", "E-Hentai 只能按顺序翻页": "Страницы E-Hentai можно загружать только последовательно", "E-Hentai 图片配额已用尽（509），请稍后再试或登录后重置配额": "Квота изображений E-Hentai исчерпана (509), повторите попытку позже или сбросьте квоту после входа в систему.", "E-Hentai 账号": "Аккаунт E-Hentai", "E-Hentai（表站）": "E-Hentai (открытый сайт)", "ExHentai 返回空页面：请先登录，或该账号没有里站权限": "ExHentai вернул пустую страницу: войдите в аккаунт или проверьте разрешение на доступ", "ExHentai（里站）": "ExHentai (ограниченный доступ)", "IP 被 E-Hentai 临时封禁，请稍后再试或更换网络": "IP-адрес временно заблокирован E-Hentai, повторите попытку позже или измените сеть.", "临时": "Временный", "亚洲": "Азия", "会员 ID，一串数字": "Идентификатор участника, строка цифр.", "会员 {value0}": "Участник {value0}", "历史最悠久的画廊站，标签体系完善；登录后可切换里站 ExHentai": "Галерея с долгой историей и развитой системой тегов; после входа можно перейти на ExHentai при наличии доступа", "女性": "Женский", "当前热门": "Текущая популярность", "找不到第 {value0} 页": "Страница {value0} не найдена", "支持标签语法：female:\"big breasts\"$、artist:xxx、language:chinese": "Синтаксис тегов: female:\"big breasts\"$, artist:xxx, language:chinese", "无效的画廊 ID：{value0}": "Неверный идентификатор галереи: {value0}.", "昨日": "Вчера", "最低评分": "самый низкий балл", "杂项": "Разное", "没有符合条件的画廊": "Нет подходящих галерей.", "混合": "Микс", "游戏CG": "Игровая компьютерная графика", "男性": "Мужчина", "画师CG": "Художник компьютерной графики", "画廊不存在或已被删除": "Галерея не существует или была удалена", "画廊没有图片": "В галерее нет фотографий", "登录后可以访问里站 ExHentai，并解除部分画廊的访问限制。": "После входа в систему вы можете получить доступ к ExHentai и снять ограничения доступа к некоторым галереям.", "私有": "Частное", "第 {value0} 页没有图片": "Страница {value0} не имеет изображения", "缺少 ipb_member_id 或 ipb_pass_hash": "Отсутствует ipb_member_id или ipb_pass_hash.", "西方": "Запад", "访问里站时需要": "Требуется при посещении сайта", "请求间隔": "Интервал запроса", "近一年": "Почти год", "近一月": "Почти месяц", "里站 ExHentai 需要登录且账号有访问权限": "Для ExHentai необходимо войти в аккаунт с разрешением на доступ", "重分类": "Реклассификация", "间隔过短容易被临时封禁 IP": "Если интервал слишком короткий, IP будет временно заблокирован.", "非H": "Не Н", "韩文": "Корейский"},
    "ar": {"0.2 秒（激进）": "0.2 ثانية (عدوانية)", "0.4 秒（推荐）": "0.4 ثانية (مستحسن)", "0.8 秒（保守）": "0.8 ثانية (محافظ)", "2 星": "نجمتان", "3 星": "3 نجوم", "32 位十六进制字符": "أحرف سداسية عشرية 32 بت", "4 星": "4 نجوم", "5 星": "5 نجوم", "E-Hentai 只能按顺序翻页": "يمكن تحميل صفحات E-Hentai بالترتيب فقط", "E-Hentai 图片配额已用尽（509），请稍后再试或登录后重置配额": "تم استنفاد حصة صور E-Hentai (509)، يرجى المحاولة مرة أخرى لاحقًا أو إعادة ضبط الحصة بعد تسجيل الدخول", "E-Hentai 账号": "حساب E-Hentai", "E-Hentai（表站）": "E-Hentai (الموقع العام)", "ExHentai 返回空页面：请先登录，或该账号没有里站权限": "أعاد ExHentai صفحة فارغة: سجّل الدخول أولًا أو تحقق من صلاحية وصول حسابك", "ExHentai（里站）": "ExHentai (وصول مقيّد)", "IP 被 E-Hentai 临时封禁，请稍后再试或更换网络": "تم حظر عنوان IP مؤقتًا بواسطة E-Hentai، يرجى المحاولة مرة أخرى لاحقًا أو تغيير الشبكة", "临时": "مؤقت", "亚洲": "آسيا", "会员 ID，一串数字": "معرف العضو، سلسلة من الأرقام", "会员 {value0}": "عضو {value0}", "历史最悠久的画廊站，标签体系完善；登录后可切换里站 ExHentai": "موقع معارض عريق بنظام وسوم شامل؛ سجّل الدخول للتبديل إلى ExHentai إذا كان حسابك يملك صلاحية الوصول", "女性": "أنثى", "当前热门": "الشعبية الحالية", "找不到第 {value0} 页": "الصفحة {value0} غير موجودة", "支持标签语法：female:\"big breasts\"$、artist:xxx、language:chinese": "صيغة الوسوم: female:\"big breasts\"$, artist:xxx, language:chinese", "无效的画廊 ID：{value0}": "معرف المعرض غير صالح: {value0}", "昨日": "أمس", "最低评分": "أدنى درجة", "杂项": "متنوعة", "没有符合条件的画廊": "لا توجد معارض مؤهلة", "混合": "ميكس", "游戏CG": "لعبة CG", "男性": "ذكر", "画师CG": "الرسام سي جي", "画廊不存在或已被删除": "المعرض غير موجود أو تم حذفه", "画廊没有图片": "لا توجد صور في المعرض", "登录后可以访问里站 ExHentai，并解除部分画廊的访问限制。": "بعد تسجيل الدخول، يمكنك الوصول إلى ExHentai، ورفع قيود الوصول عن بعض المعارض.", "私有": "خاص", "第 {value0} 页没有图片": "الصفحة {value0} لا تحتوي على صور", "缺少 ipb_member_id 或 ipb_pass_hash": "ipb_member_id أو ipb_pass_hash مفقود", "西方": "الغرب", "访问里站时需要": "مطلوب عند زيارة الموقع", "请求间隔": "الفاصل الزمني للطلب", "近一年": "سنة واحدة تقريبًا", "近一月": "ما يقرب من شهر واحد", "里站 ExHentai 需要登录且账号有访问权限": "يتطلب ExHentai تسجيل الدخول بحساب لديه إذن الوصول", "重分类": "إعادة التصنيف", "间隔过短容易被临时封禁 IP": "إذا كان الفاصل الزمني قصيرًا جدًا، فسيتم حظر IP مؤقتًا.", "非H": "ليس ح", "韩文": "الكورية"},
  },
  key: 'ehentai',
  name: 'E-Hentai',
  version: '0.0.12', minAppVersion: '0.9.2',
  type: 'comic',
  category: 'doujin',
  color: '#9C2A2A',
  icon: 'https://e-hentai.org/favicon.ico',
  description: '历史最悠久的画廊站，标签体系完善；登录后可切换里站 ExHentai',
  homepage: 'https://e-hentai.org',
  domains: ['e-hentai.org', 'exhentai.org'],
  language: 'multi',
  linkPatterns: ['(?:e-hentai|exhentai)\\.org/g/(\\d+/[0-9a-f]{10})'],
  idPattern: '^(\\d+)[_/ ]([0-9a-f]{10})/?$',
  idExample: '2345678/abcdef1234',
  imageHeaders: { Referer: 'https://e-hentai.org/' },
  network: { vpnHint: true },

  settings: [
    {
      key: 'site',
      type: 'select',
      label: '站点',
      description: '里站 ExHentai 需要登录且账号有访问权限',
      default: 'e-hentai',
      options: [
        { value: 'e-hentai', label: 'E-Hentai（表站）' },
        { value: 'exhentai', label: 'ExHentai（里站）' },
      ],
    },
    {
      key: 'interval',
      type: 'select',
      label: '请求间隔',
      description: '间隔过短容易被临时封禁 IP',
      default: '400',
      options: [
        { value: '200', label: '0.2 秒（激进）' },
        { value: '400', label: '0.4 秒（推荐）' },
        { value: '800', label: '0.8 秒（保守）' },
      ],
    },
  ],

  async interaction(id, req = {}) {
    if (req.value !== undefined && !['rating', 'favorite'].includes(req.type)) throw Park.error('CONFIG', '原站互动数据无效');
    const [gid, token] = this.splitId(id);
    let html = await this.page(`${this.base}/g/${gid}/${token}/`);
    const uid = /\bapiuid\s*=\s*(-?\d+)/.exec(html);
    const key = /\bapikey\s*=\s*["']([^"']+)["']/.exec(html);
    if (!uid || Number(uid[1]) < 0 || !key) throw Park.error('LOGIN_REQUIRED', '请先登录');
    let personalRating = null;
    const states = () => {
      const link = Park.html.parse(html).querySelector('#favoritelink');
      const label = link && Park.html.text(link);
      return [...(label ? [{type: 'favorite', value: !/^Add to Favorites$/i.test(label)}] : []), {type: 'rating', value: personalRating}];
    };
    // display_rating 也可能是平均分，不能把它显示为用户的评分。
    if (req.value === undefined) return states();
    if (req.type === 'favorite') {
      if (typeof req.value !== 'boolean') throw Park.error('CONFIG', '原站互动数据无效');
      const current = states().find(state => state.type === 'favorite');
      if (!current) throw Park.error('PARSE', '原站互动数据无效');
      if (current.value === req.value) return states();
      const popbase = /\bpopbase\s*=\s*["']([^"']+)["']/.exec(html);
      if (!popbase) throw Park.error('PARSE', '原站互动数据无效');
      const url = new URL(popbase[1] + 'addfav', this.base);
      if (url.origin !== this.base || url.pathname !== '/gallerypopups.php' || url.searchParams.get('gid') !== String(gid) || url.searchParams.get('t') !== token || url.searchParams.get('act') !== 'addfav') throw Park.error('PARSE', '原站互动数据无效');
      const doc = Park.html.parse(await this.page(url.href));
      const form = doc.querySelector('form:has(select[name="favcat"])');
      if (!form) throw Park.error('LOGIN_REQUIRED', '请先登录');
      const action = new URL(form.getAttribute('action') || url.href, url);
      if (action.href !== url.href || (form.getAttribute('method') || '').toLowerCase() !== 'post') throw Park.error('PARSE', '原站互动数据无效');
      const choices = [...form.querySelectorAll('select[name="favcat"] option')].map(option => option.getAttribute('value'));
      const category = req.value ? choices.find(value => /^[0-9]$/.test(value)) : 'favdel';
      if (!category || !choices.includes(category)) throw Park.error('PARSE', '原站互动数据无效');
      const fields = {};
      for (const input of form.querySelectorAll('input[name], textarea[name]')) {
        const type = input.getAttribute('type');
        if (['radio', 'checkbox'].includes(type) && !input.hasAttribute('checked')) continue;
        fields[input.getAttribute('name')] = input.tagName.toLowerCase() === 'textarea' ? input.textContent : input.getAttribute('value') || '';
      }
      fields.favcat = category;
      await this.wait();
      const response = await this.http.post(action.href, {form: fields, headers: {Referer: url.href}});
      if (!response.ok) throw Park.error('AUTH', '原站操作未成功，请重试');
      html = await this.page(`${this.base}/g/${gid}/${token}/`);
      if (states().find(state => state.type === 'favorite')?.value !== req.value) throw Park.error('AUTH', '原站操作未成功，请重试');
      return states();
    }
    const value = req.value;
    if (typeof value !== 'number' || value < 0.5 || value > 5 || !Number.isInteger(value * 2)) {
      throw Park.error('CONFIG', '原站互动数据无效');
    }
    await this.wait();
    const res = await this.http.json(this.apiUrl, {method: 'POST', json: {
      method: 'rategallery', apiuid: Number(uid[1]), apikey: key[1], gid, token, rating: value * 2,
    }});
    if (res.login !== undefined) throw Park.error('LOGIN_REQUIRED', '请先登录');
    if (res.error || typeof res.rating_usr !== 'number' || res.rating_usr !== value) {
      throw Park.error('AUTH', '原站操作未成功，请重试');
    }
    personalRating = res.rating_usr;
    return states();
  },

  account: {
    type: 'cookies',
    title: 'E-Hentai 账号',
    hint: '登录后可以访问里站 ExHentai，并解除部分画廊的访问限制。',
    loginUrl: 'https://forums.e-hentai.org/index.php?act=Login&CODE=00',
    cookieUrl: 'https://e-hentai.org',
    requiredCookies: ['ipb_member_id', 'ipb_pass_hash'],
    fields: [
      { key: 'ipb_member_id', label: 'ipb_member_id', hint: '会员 ID，一串数字' },
      { key: 'ipb_pass_hash', label: 'ipb_pass_hash', hint: '32 位十六进制字符', secret: true },
      { key: 'igneous', label: 'igneous', hint: '访问里站时需要', secret: true, optional: true },
    ],
    async login(values) {
      const cookies = {};
      for (const k of ['ipb_member_id', 'ipb_pass_hash', 'igneous']) if (values[k]) cookies[k] = String(values[k]).trim();
      if (!cookies.ipb_member_id || !cookies.ipb_pass_hash) throw Park.error('LOGIN_REQUIRED', '缺少 ipb_member_id 或 ipb_pass_hash');
      for (const host of ['https://e-hentai.org', 'https://exhentai.org', 'https://forums.e-hentai.org']) {
        await this.cookies.set(host, cookies);
      }
      this.store.set('account', { id: cookies.ipb_member_id, igneous: !!cookies.igneous });
      return { name: `会员 ${cookies.ipb_member_id}` };
    },
    async logout() {
      for (const host of ['https://e-hentai.org', 'https://exhentai.org', 'https://forums.e-hentai.org']) {
        await this.cookies.clear(host);
      }
      this.store.set('account', null);
    },
    async status() {
      const acc = this.store.get('account');
      return acc ? { loggedIn: true, name: `会员 ${acc.id}` } : { loggedIn: false };
    },
  },

  rankings: [{ key: 'toplist', label: '排行榜', category: 'doujin', metric: '站内热度', feed: 'toplist' }],
  defaultFeed: 'toplist',
  feeds: [
    {key: 'category', label: '分类', options: browseFilters.filter(option => option.type !== 'number'), commonFilters: {pages: {range: ['min']}}},
    { key: 'latest', label: '最新', commonFilters: {pages: {range: ['min']}} },
    { key: 'popular', label: '当前热门' },
    {
      key: 'toplist',
      label: '排行榜',
      options: [
        {
          key: 'period',
          label: '周期',
          default: '15',
          values: [
            { value: '15', label: '昨日' },
            { value: '13', label: '近一月' },
            { value: '12', label: '近一年' },
            { value: '11', label: '总榜' },
          ],
        },
      ],
    },
  ],

  searchHint: '支持标签语法：female:"big breasts"$、artist:xxx、language:chinese',
  searchFilters: browseFilters,
  searchCommonFilters: {pages: {range: ['min']}},
  CATEGORY_BITS: {
    Misc: 1,
    Doujinshi: 2,
    Manga: 4,
    'Artist CG': 8,
    'Game CG': 16,
    'Image Set': 32,
    Cosplay: 64,
    'Asian Porn': 128,
    'Non-H': 256,
    Western: 512,
  },
  CATEGORY_LABELS: {
    Doujinshi: ['同人志', '#9E2720'],
    Manga: ['漫画', '#DB6C24'],
    'Artist CG': ['画师CG', '#D38F1D'],
    'Game CG': ['游戏CG', '#617C63'],
    Western: ['西方', '#AB9F60'],
    'Non-H': ['非H', '#5FA9CF'],
    'Image Set': ['图集', '#325CA2'],
    Cosplay: ['Cosplay', '#6A32A2'],
    'Asian Porn': ['亚洲', '#A23282'],
    Misc: ['杂项', '#777777'],
    'Private': ['私有', '#777777'],
  },
  LANGUAGE_LABELS: { chinese: '中文', japanese: '日文', english: '英文', korean: '韩文' },
  NAMESPACES: [
    ['language', '语言'],
    ['parody', '原作'],
    ['character', '角色'],
    ['artist', '作者'],
    ['group', '社团'],
    ['cosplayer', 'Coser'],
    ['female', '女性'],
    ['male', '男性'],
    ['mixed', '混合'],
    ['other', '其他'],
    ['reclass', '重分类'],
    ['temp', '临时'],
  ],

  init() {
    this.wait = Park.utils.rateLimiter(Number(this.config.interval) || 400);
    this.galleries = Park.utils.lruMap(30); // origin/gid/token → thumbnail state
    this.showkeys = Park.utils.lruMap(30);
    this.nls = Park.utils.lruMap(500);
  },

  onSettingsChanged() {
    this.init();
  },

  get base() {
    return this.config.site === 'exhentai' ? 'https://exhentai.org' : 'https://e-hentai.org';
  },

  get apiUrl() {
    return this.config.site === 'exhentai' ? 'https://exhentai.org/api.php' : 'https://api.e-hentai.org/api.php';
  },

  async page(url, params) {
    await this.wait();
    const res = await this.http.get(url, { params });
    const body = String(res.body || '');
    if (body.includes('Your IP address has been temporarily banned')) {
      throw Park.error('BLOCKED', 'IP 被 E-Hentai 临时封禁，请稍后再试或更换网络');
    }
    if (res.status === 404 || /Key missing, or incorrect key provided|This gallery has been removed/.test(body)) {
      throw Park.error('NOT_FOUND', '画廊不存在或已被删除');
    }
    if (!res.ok) throw Park.error('HTTP', 'HTTP {status}', { params: {status: res.status}, status: res.status });
    if (!body.trim()) {
      throw Park.error('LOGIN_REQUIRED', 'ExHentai 返回空页面：请先登录，或该账号没有里站权限');
    }
    return body;
  },

  async ensureNoWarning(base = this.base) {
    if (!(this.nwSet instanceof Set)) this.nwSet = new Set();
    if (this.nwSet.has(base)) return;
    await this.cookies.set(base, { nw: '1' });
    this.nwSet.add(base);
  },

  parseListing(html) {
    const seen = new Set();
    const pairs = [];
    const re = /\/g\/(\d+)\/([0-9a-f]{10})/g;
    let m;
    while ((m = re.exec(html))) {
      if (!seen.has(m[1])) {
        seen.add(m[1]);
        pairs.push([Number(m[1]), m[2]]);
      }
    }
    const next = /id="unext"\s+href="[^"]*?(?:[?&]|&amp;)next=(\d+)/.exec(html);
    const found = /Found(?: about)? ([\d,]+) results?/.exec(html);
    return {
      pairs,
      next: next ? next[1] : null,
      total: found ? Park.utils.toInt(found[1]) : null,
    };
  },

  async gdata(pairs, base = this.base) {
    const out = [];
    for (let i = 0; i < pairs.length; i += 25) {
      await this.wait();
      const data = await this.http.json(base === 'https://exhentai.org' ? base + '/api.php' : 'https://api.e-hentai.org/api.php', {
        method: 'POST',
        json: { method: 'gdata', gidlist: pairs.slice(i, i + 25), namespace: 1 },
      });
      for (const meta of data.gmetadata || []) if (!meta.error) out.push(meta);
    }
    const order = new Map(pairs.map(([gid], i) => [gid, i]));
    return out.sort((a, b) => order.get(a.gid) - order.get(b.gid));
  },

  thumb(url) {
    return String(url || '').replace('s.exhentai.org', 'ehgt.org');
  },

  tagGroups(tags) {
    const groups = {};
    for (const raw of tags || []) {
      const t = String(raw);
      const idx = t.indexOf(':');
      const ns = idx > 0 ? t.slice(0, idx) : 'misc';
      const name = idx > 0 ? t.slice(idx + 1) : t;
      (groups[ns] = groups[ns] || []).push(name);
    }
    return groups;
  },

  toItem(meta) {
    const groups = this.tagGroups(meta.tags);
    const lang = (groups.language || []).find((l) => l !== 'translated' && l !== 'rewrite') || '';
    const cat = this.CATEGORY_LABELS[meta.category] || [meta.category, '#777777'];
    return {
      id: `${meta.gid}/${meta.token}`,
      title: Park.html.unescape(meta.title),
      subtitle: Park.html.unescape(meta.title_jpn || ''),
      authors: (groups.artist || []).concat(groups.group || []),
      uploader: Park.html.unescape(meta.uploader || ''),
      cover: this.thumb(meta.thumb),
      pages: Number(meta.filecount) || 0,
      rating: Park.utils.toFloat(meta.rating),
      language: this.LANGUAGE_LABELS[lang] || lang,
      category: cat[0],
      badgeColor: cat[1],
      uploaded: Park.utils.formatDate(meta.posted),
      tags: (groups.female || []).concat(groups.male || [], groups.other || []).slice(0, 6),
    };
  },

  async listPage(url, params, page) {
    await this.ensureNoWarning();
    const listing = this.parseListing(await this.page(url, params));
    const metas = await this.gdata(listing.pairs);
    return {
      items: metas.map((m) => this.toItem(m)),
      page,
      totalPages: listing.total ? Math.ceil(listing.total / 25) : null,
      total: listing.total,
      hasNext: !!listing.next,
      cursor: listing.next,
    };
  },

  async feed(key, req) {
    if (key === 'category') return this.search({keyword: '', page: req.page, cursor: req.cursor, filters: req.options || {}, common: req.common});
    const page = Math.max(1, req.page || 1);
    if (key === 'popular') {
      const res = await this.listPage(`${this.base}/popular`, null, 1);
      return Object.assign(res, { hasNext: false, cursor: null, totalPages: 1 });
    }
    if (key === 'toplist') {
      const tl = (req.options && req.options.period) || '15';
      const params = { tl };
      if (page > 1) params.p = String(page - 1);
      const res = await this.listPage('https://e-hentai.org/toplist.php', params, page);
      return Object.assign(res, { hasNext: res.items.length > 0 && page < 200, cursor: null, totalPages: 200 });
    }
    return this.search({ keyword: '', page, cursor: req.cursor, filters: {}, common: req.common });
  },

  searchParams(req) {
    const f = req.filters || {};
    const common = req.common || {};
    const params = {};
    const words = [String(req.keyword || '').trim()];
    if (f.language && !/language:/i.test(words[0])) words.push(`language:${f.language}`);
    const search = words.filter(Boolean).join(' ');
    if (search) params.f_search = search;
    const cats = Array.isArray(f.categories) ? f.categories : f.categories ? [f.categories] : [];
    if (cats.length) {
      let mask = 1023;
      for (const c of cats) mask &= ~(this.CATEGORY_BITS[c] || 0);
      params.f_cats = String(mask);
    }
    const rating = Number(f.minRating) || 0;
    if (rating >= 2) Object.assign(params, { advsearch: '1', f_sr: 'on', f_srdd: String(Math.min(rating, 5)) });
    const minPages = common.pages?.min ?? Number(f.minPages);
    if (minPages > 1) Object.assign(params, { advsearch: '1', f_sp: 'on', f_spf: String(minPages) });
    return params;
  },

  async searchSuggestions(keyword) {
    keyword = String(keyword || '').trim();
    if (!keyword) return [];
    await this.wait();
    const response = await this.http.post('https://api.e-hentai.org/api.php', {
      json: { method: 'tagsuggest', text: keyword },
    });
    if (!response.ok) throw Park.error('HTTP', 'HTTP {status}', { params: { status: response.status }, status: response.status });
    let data;
    try { data = JSON.parse(response.body); } catch (_) { throw Park.error('PARSE', '媒体数据无效'); }
    if (!data?.tags || typeof data.tags !== 'object') throw Park.error('PARSE', '媒体数据无效');
    return Object.values(data.tags).filter(t => typeof t.ns === 'string' && typeof t.tn === 'string').slice(0, 10)
      .map(t => ({ keyword: t.ns + ':"' + t.tn + '"$', label: t.tn, subtitle: t.ns }));
  },

  async search(req) {
    const page = Math.max(1, req.page || 1);
    const params = this.searchParams(req);
    if (page > 1 && !req.cursor) {
      throw Park.error('UNSUPPORTED', 'E-Hentai 只能按顺序翻页');
    }
    if (req.cursor) params.next = String(req.cursor);
    return this.listPage(`${this.base}/`, params, page);
  },

  contentUrl(value) {
    try {
      const url = new URL(String(value));
      if (!['https:', 'http:'].includes(url.protocol) || url.username || url.password || url.port ||
          !['e-hentai.org', 'exhentai.org'].includes(url.hostname)) return null;
      url.protocol = 'https:';
      return url;
    } catch (_) { return null; }
  },

  resolveContentLink(value) {
    const url = this.contentUrl(value);
    if (!url) return null;
    if (/^\/g\/\d+\/[0-9a-f]{10}\/?$/.test(url.pathname))
      return {type: 'work', id: url.origin + url.pathname.replace(/\/?$/, '/')};
    if (url.pathname === '/' || /^\/tag\/[^/]+(?:\/\d+)?\/?$/.test(url.pathname)) {
      // Read-only listing paths; reject query parameters used by account/write routes.
      const allowed = /^(?:f_[a-z_]+|advsearch|next|prev|seek|range|page)$/;
      if ([...url.searchParams.keys()].some(key => !allowed.test(key))) return {type: 'external', url: url.href};
      url.hash = '';
      return {type: 'search', url: url.href};
    }
    return {type: 'external', url: url.href};
  },

  async searchLink(value, req = {}) {
    const target = this.resolveContentLink(value);
    if (target?.type !== 'search') throw Park.error('CONFIG', '站点链接无效');
    const url = new URL(target.url), page = Math.max(1, Math.floor(Number(req.page) || 1));
    if (page > 1 && !req.cursor) throw Park.error('UNSUPPORTED', 'E-Hentai 只能按顺序翻页');
    if (req.cursor) {
      if (!/^\d+$/.test(String(req.cursor))) throw Park.error('CONFIG', '分页链接无效');
      url.searchParams.delete('prev'); url.searchParams.delete('page');
      url.searchParams.set('next', String(req.cursor));
    }
    await this.ensureNoWarning(url.origin);
    const listing = this.parseListing(await this.page(url.href));
    const metas = await this.gdata(listing.pairs, url.origin);
    return {items: metas.map(meta => ({...this.toItem(meta), id: `${url.origin}/g/${meta.gid}/${meta.token}/`,
      url: `${url.origin}/g/${meta.gid}/${meta.token}/`})), page, total: listing.total,
      hasNext: !!listing.next, cursor: listing.next};
  },

  async comments(id, req = {}) {
    if (req.parentId || Number(req.page) > 1) return {items: [], hasNext: false};
    const [gid, token, base] = this.splitId(id), url = `${base}/g/${gid}/${token}/`;
    await this.ensureNoWarning(base);
    const doc = Park.html.parse(await this.page(url, {hc: '1'}));
    if (!doc.querySelector('#cdiv')) throw Park.error('PARSE', '评论数据无效');
    const items = [...doc.querySelectorAll('#cdiv .c1')].map(row => {
      const content = row.querySelector('.c6'), author = row.querySelector('.c3 a'),
        commentId = (content?.getAttribute('id') || row.getAttribute('id') || '').match(/\d+/)?.[0];
      if (!commentId || !content) throw Park.error('PARSE', '评论数据无效');
      const score = Park.html.text(row.querySelector('.c5'));
      return {id: commentId, author: {name: Park.html.text(author), url: author?.getAttribute('href')},
        body: Park.comments.html(content.innerHTML, url),
        date: Park.html.text(row.querySelector('.c3')).replace(/Posted on\s*/i, '').split(' by:')[0].trim(),
        likes: Number(score.match(/-?\d+/)?.[0]) || 0};
    }).filter(c => c.body.length);
    return {items, hasNext: false};
  },

  async random(req) {
    // gid grows over time: jump to a random cursor between the newest and oldest galleries.
    const params = this.searchParams(req || {});
    await this.ensureNoWarning();
    const newest = this.parseListing(await this.page(`${this.base}/`, params));
    if (!newest.pairs.length) throw Park.error('NOT_FOUND', '没有符合条件的画廊');
    let pairs = newest.pairs;
    if (newest.next) {
      const oldest = this.parseListing(await this.page(`${this.base}/`, Object.assign({}, params, { prev: '1' })));
      const low = Math.min(...(oldest.pairs.length ? oldest.pairs : pairs).map((p) => p[0]));
      const high = Math.max(...pairs.map((p) => p[0]));
      if (high > low) {
        const cursor = low + 1 + Math.floor(Math.random() * (high - low));
        const jumped = this.parseListing(await this.page(`${this.base}/`, Object.assign({}, params, { next: String(cursor) })));
        if (jumped.pairs.length) pairs = jumped.pairs;
      }
    }
    const pick = pairs[Math.floor(Math.random() * pairs.length)];
    return `${pick[0]}/${pick[1]}`;
  },

  splitId(id) {
    const url = this.contentUrl(id);
    const m = url ? /^\/g\/(\d+)\/([0-9a-f]{10})\/?$/.exec(url.pathname) : /^(\d+)[_/ ]([0-9a-f]{10})\/?$/.exec(String(id));
    if (!m) throw Park.error('NOT_FOUND', '无效的画廊 ID：{value0}', { params: {value0: id} });
    return [Number(m[1]), m[2], url ? url.origin : this.base];
  },

  /** Parses one gallery thumbnail page: page links and (sprite) thumbnails keyed by 0-based index. */
  parseGalleryPage(html, gid) {
    const doc = Park.html.parse(html);
    const entries = [];
    for (const a of doc.querySelectorAll('#gdt a')) {
      const href = a.getAttribute('href') || '';
      const m = new RegExp(`/s/[0-9a-f]{10}/${gid}-(\\d+)`).exec(href);
      if (!m) continue;
      const div = a.querySelector('div[style]');
      const img = a.querySelector('img');
      let thumb = null;
      if (div) {
        const style = div.getAttribute('style') || '';
        const url = /url\(([^)]+)\)/.exec(style);
        const w = /width:\s*(\d+)px/.exec(style);
        const h = /height:\s*(\d+)px/.exec(style);
        const pos = /\)\s*(-?\d+)(?:px)?\s+(-?\d+)(?:px)?/.exec(style);
        if (url) {
          thumb = {
            url: url[1],
            width: w ? Number(w[1]) : null,
            height: h ? Number(h[1]) : null,
            offsetX: pos ? -Number(pos[1]) : 0,
            offsetY: pos ? -Number(pos[2]) : 0,
          };
        }
      } else if (img) {
        thumb = { url: img.getAttribute('src') || '' };
      }
      entries.push({ index: Number(m[1]) - 1, link: href, thumb });
    }
    const pageNums = [...doc.querySelectorAll('table.ptt td a')].map((a) => Number(a.textContent)).filter((n) => n > 0);
    return { entries, thumbPages: pageNums.length ? Math.max(...pageNums) : 1, doc };
  },

  async galleryPage(gid, token, p, base = this.base) {
    const key = `${base}/${gid}/${token}`;
    let state = this.galleries.get(key);
    if (!state) {
      state = { links: new Map(), thumbs: new Map(), loaded: new Set(), perPage: 0, thumbPages: 1 };
      this.galleries.set(key, state);
    }
    if (state.loaded.has(p)) return state;
    await this.ensureNoWarning(base);
    const html = await this.page(`${base}/g/${gid}/${token}/`, p ? { p: String(p) } : null);
    const parsed = this.parseGalleryPage(html, gid);
    for (const e of parsed.entries) {
      state.links.set(e.index, e.link);
      if (e.thumb) state.thumbs.set(e.index, e.thumb);
    }
    if (p === 0) {
      state.perPage = parsed.entries.length || 20;
      state.thumbPages = parsed.thumbPages;
      state.doc = parsed.doc;
    }
    state.loaded.add(p);
    return state;
  },

  async detail(id) {
    const [gid, token, base] = this.splitId(id);
    const [metas, state] = await Promise.all([this.gdata([[gid, token]], base), this.galleryPage(gid, token, 0, base)]);
    const meta = metas[0];
    if (!meta) throw Park.error('NOT_FOUND', '画廊不存在或已被删除');
    const item = this.toItem(meta);
    const groups = this.tagGroups(meta.tags);
    const known = new Set(this.NAMESPACES.map(([ns]) => ns));
    const tags = this.NAMESPACES.filter(([ns]) => groups[ns])
      .concat(Object.keys(groups).filter((ns) => !known.has(ns)).map((ns) => [ns, ns]))
      .map(([ns, label]) => ({
        namespace: ns,
        label,
        tags: groups[ns].map((name) => ({ name, keyword: `${ns}:"${name}$"` })),
      }));
    const thumbs = [];
    for (let i = 0; i < state.perPage && i < item.pages; i++) thumbs.push(state.thumbs.get(i) || null);
    return Object.assign(item, {
      id: this.contentUrl(id) ? `${base}/g/${gid}/${token}/` : item.id,
      url: `${base}/g/${gid}/${token}/`,
      authors: (groups.artist || []).concat(groups.group || []),
      uploader: Park.html.unescape(meta.uploader || ''),
      size: meta.filesize ? `${(meta.filesize / 1048576).toFixed(1)} MB` : '',
      expunged: !!meta.expunged,
      tags,
      chapters: null,
      thumbnails: thumbs.filter(Boolean),
      thumbnailsTotal: item.pages,
    });
  },

  /** Thumbnails for the preview grid, one gallery thumbnail page at a time. */
  async thumbnails(id, page) {
    const [gid, token, base] = this.splitId(id);
    const first = await this.galleryPage(gid, token, 0, base);
    const p = Math.max(0, Number(page) || 0);
    const state = p === 0 ? first : await this.galleryPage(gid, token, p, base);
    const start = p * state.perPage;
    const list = [];
    for (let i = start; i < start + state.perPage; i++) {
      if (state.thumbs.has(i)) list.push(Object.assign({ index: i }, state.thumbs.get(i)));
    }
    return { thumbnails: list, page: p, hasNext: p + 1 < state.thumbPages };
  },

  async chapter(id) {
    const [gid, token, base] = this.splitId(id);
    const [metas] = await Promise.all([this.gdata([[gid, token]], base), this.galleryPage(gid, token, 0, base)]);
    const count = metas[0] ? Number(metas[0].filecount) : 0;
    if (!count) throw Park.error('NOT_FOUND', '画廊没有图片');
    // Images are resolved lazily one page at a time by resolveImage.
    return { pages: Array.from({ length: count }, (_, i) => ({ token: String(i) })) };
  },

  async pageLink(gid, token, index, base = this.base) {
    const first = await this.galleryPage(gid, token, 0, base);
    if (!first.links.has(index)) await this.galleryPage(gid, token, Math.floor(index / (first.perPage || 20)), base);
    const link = first.links.get(index);
    if (!link) throw Park.error('NOT_FOUND', '找不到第 {value0} 页', { params: {value0: index + 1} });
    return link;
  },

  parseSinglePage(html) {
    const img = /<img id="img" src="([^"]+)"[^>]*?(?:style="width:(\d+)px;height:(\d+)px")?/.exec(html);
    const nl = /nl\('([^']+)'\)/.exec(html);
    const showkey = /showkey\s*=\s*"([^"]+)"/.exec(html);
    return {
      url: img ? Park.html.unescape(img[1]) : '',
      width: img && img[2] ? Number(img[2]) : null,
      height: img && img[3] ? Number(img[3]) : null,
      nl: nl ? nl[1] : null,
      showkey: showkey ? showkey[1] : null,
    };
  },

  async resolveImage(req) {
    const [gid, token, base] = this.splitId(req.id);
    const index = Number(req.token !== undefined ? req.token : req.index);
    const link = await this.pageLink(gid, token, index, base);
    const galleryKey = `${base}/${gid}/${token}`, nlKey = `${galleryKey}-${index}`;
    let result;
    const showkey = this.showkeys.get(galleryKey);
    if (req.retry > 0 && this.nls.get(nlKey)) {
      result = this.parseSinglePage(await this.page(link, { nl: this.nls.get(nlKey) }));
    } else if (showkey) {
      await this.wait();
      const imgkey = /\/s\/([0-9a-f]{10})\//.exec(link)[1];
      const res = await this.http.post(base === 'https://exhentai.org' ? base + '/api.php' : 'https://api.e-hentai.org/api.php', {
        json: { method: 'showpage', gid, page: index + 1, imgkey, showkey },
      });
      if (res.ok) {
        const data = res.json();
        const parsed = this.parseSinglePage(`${data.i3 || ''}${data.i6 || ''}`);
        if (parsed.url) result = Object.assign(parsed, { width: Number(data.x) || null, height: Number(data.y) || null });
      }
      if (!result) result = this.parseSinglePage(await this.page(link));
    } else {
      result = this.parseSinglePage(await this.page(link));
    }
    if (result.showkey) this.showkeys.set(galleryKey, result.showkey);
    if (result.nl) this.nls.set(nlKey, result.nl);
    if (!result.url) throw Park.error('PARSE', '第 {value0} 页没有图片', { params: {value0: index + 1} });
    if (/\/509s?\.gif$/.test(result.url)) {
      throw Park.error('BLOCKED', 'E-Hentai 图片配额已用尽（509），请稍后再试或登录后重置配额');
    }
    return {
      url: result.url,
      width: result.width,
      height: result.height,
      headers: { Referer: `${base}/` },
      cacheKey: `eh-${gid}-${index}`,
    };
  },
});

})();

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"}]});
