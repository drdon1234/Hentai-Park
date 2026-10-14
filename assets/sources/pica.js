/*
 * PicACG (哔咔漫画) — app API at picaapi.picacomic.com.
 * Every request is signed: HMAC-SHA256(secret, lower(path + time + nonce + METHOD + apiKey)), where
 * `path` is the exact path + query used in the request (no leading slash). Headers must mimic the app
 * or sign-in fails with misleading errors. Everything requires an account; the token lasts ~7 days and
 * is refreshed automatically on 401 using the saved credentials.
 */
Park.register({
  i18n: {
    "zh-Hant": {"24 小时": "24 小時", "30 天": "30 天", "7 天": "7 天", "CG雜圖": "CG雜圖", "SAO 刀劍神域": "SAO 刀劍神域", "中": "中", "低（省流量）": "低（省流量）", "使用专用自动维护账号": "使用專用自動維護賬號", "偽娘哲學": "偽娘哲學", "关键词为普通文字，可配合分区筛选": "關鍵詞為普通文字，可配合分割槽篩選", "分区": "分割槽", "分区丰富的老牌漫画社区，支持多话连载（需要账号）": "分割槽豐富的老牌漫畫社群，支援多話連載（需要賬號）", "分流": "分流", "原图": "原圖", "哔咔作品 {value0} 不存在": "嗶咔作品 {value0} 不存在", "哔咔所有内容都需要登录；密码只保存在本机，用于 Token 过期后自动重新登录。": "嗶咔所有內容都需要登入；密碼只儲存在本機，用於 Token 過期後自動重新登入。", "哔咔注册失败：{value0}": "嗶咔註冊失敗：{value0}", "哔咔漫画": "嗶咔漫畫", "哔咔登录失败：{value0}": "嗶咔登入失敗：{value0}", "哔咔登录状态失效": "嗶咔登入狀態失效", "哔咔请求失败：HTTP {value0} {value1}": "嗶咔請求失敗：HTTP {value0} {value1}", "哔咔账号": "嗶咔賬號", "哔咔账号正在冷却，请在 {value0} 分钟后重试": "嗶咔賬號正在冷卻，請在 {value0} 分鐘後重試", "哔咔随机接口没有返回作品": "嗶咔隨機介面沒有返回作品", "哔咔需要登录后才能使用": "嗶咔需要登入後才能使用", "哔咔：{value0}": "嗶咔：{value0}", "單行本": "單行本", "嗶咔漢化": "嗶咔漢化", "图片质量": "圖片質量", "圓神領域": "圓神領域", "大家都在看": "大家都在看", "大濕推薦": "大濕推薦", "妹妹系": "妹妹系", "姐姐系": "姐姐系", "完结": "完結", "官方都在看": "官方都在看", "密码": "密碼", "強暴": "強暴", "後宮閃光": "後宮閃光", "性轉換": "性轉換", "扶他樂園": "扶他樂園", "最多爱心": "最多愛心", "東方": "東方", "歐美": "歐美", "生肉": "生肉", "用户名 / 邮箱": "使用者名稱 / 郵箱", "百合花園": "百合花園", "确认后自动注册专用账号，凭据保存在本机并自动重新登录。": "確認後自動註冊專用賬號，憑據儲存在本機並自動重新登入。", "碧藍幻想": "碧藍幻想", "禁書目錄": "禁書目錄", "純愛": "純愛", "耽美花園": "耽美花園", "艦隊收藏": "艦隊收藏", "英語 ENG": "英語 ENG", "请先关闭专用自动维护账号，再配置自己的账号": "請先關閉專用自動維護賬號，再配置自己的賬號", "请先确认启用专用自动维护账号": "請先確認啟用專用自動維護賬號", "请输入账号和密码": "請輸入賬號和密碼", "足の恋": "足の戀", "那年今天": "那年今天", "重口地帶": "重口地帶", "長篇": "長篇", "随便看看": "隨便看看", "非人類": "非人類", "高": "高"},
    "ja": {"24 小时": "24時間", "30 天": "30日", "7 天": "7日間", "CG雜圖": "CG雑画", "SAO 刀劍神域": "SAO ソードアート・オンライン", "中": "中", "低（省流量）": "少ない（地方の交通量）", "使用专用自动维护账号": "自動管理の専用アカウントを使用", "偽娘哲學": "女装哲学", "关键词为普通文字，可配合分区筛选": "キーワードは通常のテキストであり、パーティションでフィルタリングできます。", "分区": "パーティション", "分区丰富的老牌漫画社区，支持多话连载（需要账号）": "豊富なパーティションを備えた確立されたコミックコミュニティで、複数章の連載をサポートしています（アカウントが必要です）", "分流": "サーバー", "原图": "原画", "哔咔作品 {value0} 不存在": "PicACG の作品 {value0} は存在しません", "哔咔所有内容都需要登录；密码只保存在本机，用于 Token 过期后自动重新登录。": "PicACG のコンテンツにはログインが必要です。パスワードはこの端末だけに保存され、トークンの期限切れ時に自動で再ログインします。", "哔咔注册失败：{value0}": "PicACG の登録に失敗しました：{value0}", "哔咔漫画": "PicACG", "哔咔登录失败：{value0}": "PicACG へのログインに失敗しました：{value0}", "哔咔登录状态失效": "PicACG のログイン期限が切れました", "哔咔请求失败：HTTP {value0} {value1}": "PicACG のリクエストに失敗しました：HTTP {value0} {value1}", "哔咔账号": "PicACG アカウント", "哔咔账号正在冷却，请在 {value0} 分钟后重试": "この PicACG アカウントでは {value0} 分後に再試行してください", "哔咔随机接口没有返回作品": "PicACG からランダム作品を取得できませんでした", "哔咔需要登录后才能使用": "PicACG を利用するにはログインしてください", "哔咔：{value0}": "PicACG：{value0}", "單行本": "単行本", "嗶咔漢化": "ビカ中国語版", "图片质量": "画質", "圓神領域": "サークル神界", "大家都在看": "みんなが見ている", "大濕推薦": "ウェットの素晴らしい推奨事項", "妹妹系": "姉妹シリーズ", "姐姐系": "姉妹シリーズ", "完结": "完了", "官方都在看": "役人が見守っている", "密码": "パスワード", "強暴": "強姦", "後宮閃光": "ハーレムフラッシュ", "性轉換": "性転換", "扶他樂園": "フタパラダイス", "最多爱心": "一番の愛", "東方": "東", "歐美": "ヨーロッパとアメリカ", "生肉": "生肉", "用户名 / 邮箱": "ユーザー名/メールアドレス", "百合花園": "ユリ園", "确认后自动注册专用账号，凭据保存在本机并自动重新登录。": "確認後に専用アカウントを自動登録します。ログイン情報はこの端末に保存され、自動再ログインに使われます。", "碧藍幻想": "グランブルーファンタジー", "禁書目錄": "発禁図書リスト", "純愛": "純愛", "耽美花園": "弾明庭園", "艦隊收藏": "艦隊これくしょん", "英語 ENG": "英語ENG", "请先关闭专用自动维护账号，再配置自己的账号": "自分のアカウントを設定する前に専用アカウントの自動管理を無効にしてください", "请先确认启用专用自动维护账号": "先に専用アカウントの自動管理を有効にすることを確認してください", "请输入账号和密码": "ユーザー名とパスワードを入力してください", "足の恋": "フットラブ", "那年今天": "その年の今日", "重口地帶": "ヘビーエリア", "長篇": "長い話", "随便看看": "ちょっと見てください", "非人類": "非人間", "高": "高い"},
    "ko": {"24 小时": "24시간", "30 天": "30일", "7 天": "7일", "CG雜圖": "CG 잡화", "SAO 刀劍神域": "SAO 소드 아트 온라인", "中": "중간", "低（省流量）": "낮음(트래픽 절약)", "使用专用自动维护账号": "자동 관리 전용 계정 사용", "偽娘哲學": "복장 도착자 철학", "关键词为普通文字，可配合分区筛选": "키워드는 일반 텍스트이며 파티션으로 필터링할 수 있습니다.", "分区": "분할", "分区丰富的老牌漫画社区，支持多话连载（需要账号）": "풍부한 부서를 갖추고 다장 연재를 지원하는 탄탄한 만화 커뮤니티(계정 필요)", "分流": "서버", "原图": "원본 사진", "哔咔作品 {value0} 不存在": "PicACG 작품 {value0}이(가) 존재하지 않습니다", "哔咔所有内容都需要登录；密码只保存在本机，用于 Token 过期后自动重新登录。": "PicACG의 모든 콘텐츠는 로그인이 필요합니다. 비밀번호는 이 기기에만 저장되며 토큰 만료 시 자동으로 다시 로그인하는 데 사용됩니다.", "哔咔注册失败：{value0}": "PicACG 가입 실패: {value0}", "哔咔漫画": "PicACG", "哔咔登录失败：{value0}": "PicACG 로그인 실패: {value0}", "哔咔登录状态失效": "PicACG 로그인 세션이 만료되었습니다", "哔咔请求失败：HTTP {value0} {value1}": "PicACG 요청 실패: HTTP {value0} {value1}", "哔咔账号": "PicACG 계정", "哔咔账号正在冷却，请在 {value0} 分钟后重试": "이 PicACG 계정은 {value0}분 후에 다시 시도하세요", "哔咔随机接口没有返回作品": "PicACG에서 무작위 작품을 반환하지 않았습니다", "哔咔需要登录后才能使用": "PicACG를 사용하려면 로그인하세요", "哔咔：{value0}": "PicACG: {value0}", "單行本": "별도의 책", "嗶咔漢化": "비카 중국어 버전", "图片质量": "화질", "圓神領域": "서클 갓 영역", "大家都在看": "모두가보고있다", "大濕推薦": "다웨이가 추천하는 곳", "妹妹系": "자매 시리즈", "姐姐系": "자매 시리즈", "完结": "끝", "官方都在看": "관계자들이 지켜보고 있다", "密码": "비밀번호", "強暴": "강간", "後宮閃光": "하렘 플래시", "性轉換": "성적 전환", "扶他樂園": "후타 파라다이스", "最多爱心": "대부분의 사랑", "東方": "동양인", "歐美": "유럽과 미국", "生肉": "생고기", "用户名 / 邮箱": "사용자 이름/이메일", "百合花園": "백합정원", "确认后自动注册专用账号，凭据保存在本机并自动重新登录。": "확인하면 전용 계정에 자동으로 가입합니다. 로그인 정보는 이 기기에 저장되며 자동 재로그인에 사용됩니다.", "碧藍幻想": "그랑블루 판타지", "禁書目錄": "금지 도서 목록", "純愛": "순수한 사랑", "耽美花園": "단메이 정원", "艦隊收藏": "함대 수집", "英語 ENG": "영어 ENG", "请先关闭专用自动维护账号，再配置自己的账号": "개인 계정을 설정하려면 먼저 전용 계정 자동 관리를 끄세요", "请先确认启用专用自动维护账号": "먼저 전용 계정 자동 관리 활성화를 확인하세요", "请输入账号和密码": "아이디와 비밀번호를 입력하세요", "足の恋": "발 사랑", "那年今天": "그해 오늘", "重口地帶": "무거운 지역", "長篇": "긴 이야기", "随便看看": "그냥 보세요", "非人類": "인간이 아닌", "高": "높은"},
    "en": {"24 小时": "24 hours", "30 天": "30 days", "7 天": "7 days", "CG雜圖": "CG miscellaneous pictures", "SAO 刀劍神域": "SAO Sword Art Online", "中": "Medium", "低（省流量）": "Low (province traffic)", "使用专用自动维护账号": "Use an automatically managed dedicated account", "偽娘哲學": "Transvestite philosophy", "关键词为普通文字，可配合分区筛选": "Keywords are ordinary text and can be filtered with partitions", "分区": "Partition", "分区丰富的老牌漫画社区，支持多话连载（需要账号）": "A well-established comic community with rich partitions, supporting multi-chapter serialization (account required)", "分流": "Server", "原图": "Original picture", "哔咔作品 {value0} 不存在": "PicACG work {value0} does not exist", "哔咔所有内容都需要登录；密码只保存在本机，用于 Token 过期后自动重新登录。": "All PicACG content requires sign-in. Your password is stored only on this device to sign in again automatically when the token expires.", "哔咔注册失败：{value0}": "PicACG registration failed: {value0}", "哔咔漫画": "PicACG", "哔咔登录失败：{value0}": "PicACG sign-in failed: {value0}", "哔咔登录状态失效": "Your PicACG session has expired", "哔咔请求失败：HTTP {value0} {value1}": "PicACG request failed: HTTP {value0} {value1}", "哔咔账号": "PicACG account", "哔咔账号正在冷却，请在 {value0} 分钟后重试": "Please wait {value0} minutes before retrying this PicACG account", "哔咔随机接口没有返回作品": "PicACG returned no random works", "哔咔需要登录后才能使用": "Sign in to use PicACG", "哔咔：{value0}": "PicACG: {value0}", "單行本": "Single book", "嗶咔漢化": "Bika Chinese version", "图片质量": "Picture quality", "圓神領域": "Circle God Realm", "大家都在看": "Everyone is watching", "大濕推薦": "Great wet recommendation", "妹妹系": "Sister series", "姐姐系": "Sister system", "完结": "Complete", "官方都在看": "Officials are watching", "密码": "Password", "強暴": "Rape", "後宮閃光": "Harem flash", "性轉換": "Sexual conversion", "扶他樂園": "Futa Paradise", "最多爱心": "The most love", "東方": "East", "歐美": "Europe and America", "生肉": "Untranslated", "用户名 / 邮箱": "User name/email", "百合花園": "Lily Garden", "确认后自动注册专用账号，凭据保存在本机并自动重新登录。": "After confirmation, a dedicated account is registered automatically. Credentials stay on this device for automatic sign-in.", "碧藍幻想": "Granblue Fantasy", "禁書目錄": "List of banned books", "純愛": "Pure love", "耽美花園": "Danmei Garden", "艦隊收藏": "Fleet Collection", "英語 ENG": "English ENG", "请先关闭专用自动维护账号，再配置自己的账号": "Disable automatic account management before configuring your own account", "请先确认启用专用自动维护账号": "Confirm that you want to enable automatic account management first", "请输入账号和密码": "Enter your username and password", "足の恋": "Foot love", "那年今天": "That year today", "重口地帶": "Heavy area", "長篇": "Long story", "随便看看": "Just take a look", "非人類": "Non-human", "高": "High"},
    "es": {"24 小时": "24 horas", "30 天": "30 días", "7 天": "7 días", "CG雜圖": "Imágenes diversas CG", "SAO 刀劍神域": "Arte de espada SAO en línea", "中": "Medio", "低（省流量）": "Bajo (tráfico provincial)", "使用专用自动维护账号": "Usar una cuenta dedicada de gestión automática", "偽娘哲學": "Filosofía travesti", "关键词为普通文字，可配合分区筛选": "Las palabras clave son texto normal y se pueden filtrar con particiones.", "分区": "Partición", "分区丰富的老牌漫画社区，支持多话连载（需要账号）": "Una comunidad de cómics bien establecida con particiones ricas, que admite la serialización de varios capítulos (se requiere cuenta)", "分流": "Servidor", "原图": "imagen original", "哔咔作品 {value0} 不存在": "La obra {value0} no existe en PicACG", "哔咔所有内容都需要登录；密码只保存在本机，用于 Token 过期后自动重新登录。": "Todo el contenido de PicACG requiere iniciar sesión. La contraseña se guarda solo en este dispositivo para volver a iniciar sesión automáticamente cuando caduque el token.", "哔咔注册失败：{value0}": "Error al registrarse en PicACG: {value0}", "哔咔漫画": "PicACG", "哔咔登录失败：{value0}": "Error al iniciar sesión en PicACG: {value0}", "哔咔登录状态失效": "La sesión de PicACG ha caducado", "哔咔请求失败：HTTP {value0} {value1}": "Error de solicitud de PicACG: HTTP {value0} {value1}", "哔咔账号": "Cuenta de PicACG", "哔咔账号正在冷却，请在 {value0} 分钟后重试": "Espera {value0} minutos antes de reintentar con esta cuenta de PicACG", "哔咔随机接口没有返回作品": "PicACG no devolvió ninguna obra aleatoria", "哔咔需要登录后才能使用": "Inicia sesión para usar PicACG", "哔咔：{value0}": "PicACG: {value0}", "單行本": "Libro único", "嗶咔漢化": "Bika versión china", "图片质量": "Calidad de imagen", "圓神領域": "Círculo del Reino de Dios", "大家都在看": "Todos están mirando", "大濕推薦": "Gran recomendación húmeda", "妹妹系": "Serie hermana", "姐姐系": "Sistema hermano", "完结": "Completo", "官方都在看": "Los funcionarios están observando", "密码": "Contraseña", "強暴": "Violación", "後宮閃光": "Destello del harén", "性轉換": "Conversión sexual", "扶他樂園": "Paraíso Futa", "最多爱心": "El más amor", "東方": "Este", "歐美": "Europa y América", "生肉": "Carne cruda", "用户名 / 邮箱": "Nombre de usuario/correo electrónico", "百合花園": "Jardín de lirios", "确认后自动注册专用账号，凭据保存在本机并自动重新登录。": "Tras confirmar, se registrará una cuenta dedicada automáticamente. Las credenciales se guardan en este dispositivo para iniciar sesión de nuevo.", "碧藍幻想": "Fantasía Granblue", "禁書目錄": "Lista de libros prohibidos", "純愛": "Amor puro", "耽美花園": "Jardín Danmei", "艦隊收藏": "Colección de flotas", "英語 ENG": "Inglés ENG", "请先关闭专用自动维护账号，再配置自己的账号": "Desactiva la gestión automática antes de configurar tu propia cuenta", "请先确认启用专用自动维护账号": "Confirma primero que deseas activar la gestión automática de la cuenta", "请输入账号和密码": "Introduce tu usuario y contraseña", "足の恋": "Amor de pies", "那年今天": "Ese año hoy", "重口地帶": "Área pesada", "長篇": "Larga historia", "随便看看": "Sólo echa un vistazo", "非人類": "No humano", "高": "Alto"},
    "ru": {"24 小时": "24 часа", "30 天": "30 дней", "7 天": "7 дней", "CG雜圖": "Разные изображения компьютерной графики", "SAO 刀劍神域": "САО Мастера Меча Онлайн", "中": "Средний", "低（省流量）": "Низкий (провинциальный трафик)", "使用专用自动维护账号": "Использовать отдельный аккаунт с автоматическим обслуживанием", "偽娘哲學": "Философия трансвеститов", "关键词为普通文字，可配合分区筛选": "Ключевые слова представляют собой обычный текст и могут фильтроваться с помощью разделов.", "分区": "Перегородка", "分区丰富的老牌漫画社区，支持多话连载（需要账号）": "Хорошо зарекомендовавшее себя комическое сообщество с богатыми разделами, поддерживающими сериализацию из нескольких глав (требуется учетная запись)", "分流": "Сервер", "原图": "Исходное изображение", "哔咔作品 {value0} 不存在": "Произведение {value0} не найдено в PicACG", "哔咔所有内容都需要登录；密码只保存在本机，用于 Token 过期后自动重新登录。": "Для всего содержимого PicACG нужен вход. Пароль хранится только на этом устройстве для автоматического повторного входа после истечения токена.", "哔咔注册失败：{value0}": "Ошибка регистрации PicACG: {value0}", "哔咔漫画": "PicACG", "哔咔登录失败：{value0}": "Ошибка входа в PicACG: {value0}", "哔咔登录状态失效": "Сеанс PicACG истёк", "哔咔请求失败：HTTP {value0} {value1}": "Ошибка запроса PicACG: HTTP {value0} {value1}", "哔咔账号": "Аккаунт PicACG", "哔咔账号正在冷却，请在 {value0} 分钟后重试": "Повторите попытку с этим аккаунтом PicACG через {value0} мин.", "哔咔随机接口没有返回作品": "PicACG не вернул случайных произведений", "哔咔需要登录后才能使用": "Войдите, чтобы использовать PicACG", "哔咔：{value0}": "PicACG: {value0}", "單行本": "Отдельная книга", "嗶咔漢化": "Бика, китайская версия", "图片质量": "Качество изображения", "圓神領域": "Круг Царства Бога", "大家都在看": "Все смотрят", "大濕推薦": "Отличная рекомендация для влажной уборки.", "妹妹系": "Сестра серии", "姐姐系": "Родственная система", "完结": "Завершено", "官方都在看": "Чиновники наблюдают", "密码": "Пароль", "強暴": "Изнасилование", "後宮閃光": "Гаремная вспышка", "性轉換": "Сексуальное обращение", "扶他樂園": "Фута-рай", "最多爱心": "Самая любовь", "東方": "Восток", "歐美": "Европа и Америка", "生肉": "Сырое мясо", "用户名 / 邮箱": "Имя пользователя/адрес электронной почты", "百合花園": "Лилиевый сад", "确认后自动注册专用账号，凭据保存在本机并自动重新登录。": "После подтверждения создаётся отдельный аккаунт. Данные хранятся на этом устройстве для автоматического повторного входа.", "碧藍幻想": "Гранблю Фэнтези", "禁書目錄": "Каталог запрещенных книг", "純愛": "Чистая любовь", "耽美花園": "Сад Данмэй", "艦隊收藏": "Сбор флота", "英語 ENG": "английский АНГЛ", "请先关闭专用自动维护账号，再配置自己的账号": "Отключите автоматическое обслуживание перед настройкой своего аккаунта", "请先确认启用专用自动维护账号": "Сначала подтвердите включение автоматического обслуживания аккаунта", "请输入账号和密码": "Введите имя пользователя и пароль", "足の恋": "Любовь ног", "那年今天": "Сегодня того же года", "重口地帶": "Тяжелая зона", "長篇": "Длинная история", "随便看看": "Взгляните невзначай", "非人類": "Нечеловеческий", "高": "Высокий"},
    "ar": {"24 小时": "24 ساعة", "30 天": "30 يومًا", "7 天": "7 أيام", "CG雜圖": "صور CG متنوعة", "SAO 刀劍神域": "SAO Sword Art Online", "中": "متوسط", "低（省流量）": "منخفض (حركة المرور في المقاطعة)", "使用专用自动维护账号": "استخدام حساب مخصص يُدار تلقائيًا", "偽娘哲學": "فلسفة المتخنثين", "关键词为普通文字，可配合分区筛选": "الكلمات الرئيسية هي نص عادي ويمكن تصفيتها باستخدام الأقسام", "分区": "التقسيم", "分区丰富的老牌漫画社区，支持多话连载（需要账号）": "مجتمع فكاهي راسخ بأقسام غنية، يدعم التسلسل متعدد الفصول (الحساب مطلوب)", "分流": "الخادم", "原图": "الصورة الأصلية", "哔咔作品 {value0} 不存在": "العمل {value0} غير موجود في PicACG", "哔咔所有内容都需要登录；密码只保存在本机，用于 Token 过期后自动重新登录。": "يتطلب كل محتوى PicACG تسجيل الدخول. تُحفظ كلمة المرور على هذا الجهاز فقط لإعادة تسجيل الدخول تلقائيًا عند انتهاء صلاحية الرمز.", "哔咔注册失败：{value0}": "فشل التسجيل في PicACG: {value0}", "哔咔漫画": "PicACG", "哔咔登录失败：{value0}": "فشل تسجيل الدخول إلى PicACG: {value0}", "哔咔登录状态失效": "انتهت صلاحية جلسة PicACG", "哔咔请求失败：HTTP {value0} {value1}": "فشل طلب PicACG: HTTP {value0} {value1}", "哔咔账号": "حساب PicACG", "哔咔账号正在冷却，请在 {value0} 分钟后重试": "انتظر {value0} دقيقة قبل إعادة المحاولة بهذا الحساب في PicACG", "哔咔随机接口没有返回作品": "لم يُرجع PicACG أي أعمال عشوائية", "哔咔需要登录后才能使用": "سجّل الدخول لاستخدام PicACG", "哔咔：{value0}": "PicACG: {value0}", "單行本": "كتاب واحد", "嗶咔漢化": "نسخة بيكا الصينية", "图片质量": "جودة الصورة", "圓神領域": "دائرة عالم الله", "大家都在看": "الجميع يراقب", "大濕推薦": "توصية رطبة رائعة", "妹妹系": "سلسلة الأخت", "姐姐系": "النظام الشقيق", "完结": "كامل", "官方都在看": "المسؤولون يراقبون", "密码": "كلمة المرور", "強暴": "الاغتصاب", "後宮閃光": "فلاش الحريم", "性轉換": "التحويل الجنسي", "扶他樂園": "فوتا الجنة", "最多爱心": "أكثر الحب", "東方": "الشرق", "歐美": "أوروبا وأمريكا", "生肉": "اللحوم النيئة", "用户名 / 邮箱": "اسم المستخدم/البريد الإلكتروني", "百合花園": "حديقة الزنبق", "确认后自动注册专用账号，凭据保存在本机并自动重新登录。": "بعد التأكيد، يُسجّل حساب مخصص تلقائيًا. تُحفظ بيانات الدخول على هذا الجهاز لإعادة تسجيل الدخول تلقائيًا.", "碧藍幻想": "جرانبلو فانتاسي", "禁書目錄": "فهرس الكتب المحرمة", "純愛": "الحب الخالص", "耽美花園": "حديقة دانمي", "艦隊收藏": "مجموعة الأسطول", "英語 ENG": "الإنجليزية ENG", "请先关闭专用自动维护账号，再配置自己的账号": "عطّل إدارة الحساب التلقائية قبل إعداد حسابك الخاص", "请先确认启用专用自动维护账号": "أكد أولًا رغبتك في تفعيل إدارة الحساب تلقائيًا", "请输入账号和密码": "أدخل اسم المستخدم وكلمة المرور", "足の恋": "حب القدم", "那年今天": "اليوم من ذلك العام", "重口地帶": "منطقة ثقيلة", "長篇": "قصة طويلة", "随便看看": "ألق نظرة عرضية", "非人類": "غير بشري", "高": "عالية"},
  },
  key: 'pica',
  name: '哔咔漫画',
  version: '0.0.6',
  type: 'comic',
  category: 'doujin',
  color: '#EC97B6',
  icon: 'https://manhuabika.com/favicon.ico',
  description: '分区丰富的老牌漫画社区，支持多话连载（需要账号）',
  homepage: 'https://manhuabika.com',
  language: 'zh',
  linkPatterns: ['(?:picacomic|manhuabika|bika)[\\w.-]*/[\\w/#?=&-]*?([0-9a-f]{24})'],
  idPattern: '^([0-9a-f]{24})$',
  idExample: '5821859b5f6b9a4f93dbf6e9',
  imageHeaders: {},
  network: { vpnHint: true },

  settings: [
    {
      key: 'managedAccount',
      type: 'switch',
      label: '使用专用自动维护账号',
      description: '确认后自动注册专用账号，凭据保存在本机并自动重新登录。',
      default: false,
    },
    {
      key: 'channel',
      type: 'select',
      label: '分流',
      default: '1',
      options: [
        { value: '1', label: '分流 1' },
        { value: '2', label: '分流 2' },
        { value: '3', label: '分流 3' },
      ],
    },
    {
      key: 'quality',
      type: 'select',
      label: '图片质量',
      default: 'original',
      options: [
        { value: 'original', label: '原图' },
        { value: 'high', label: '高' },
        { value: 'medium', label: '中' },
        { value: 'low', label: '低（省流量）' },
      ],
    },
  ],

  account: {
    type: 'password',
    title: '哔咔账号',
    hint: '哔咔所有内容都需要登录；密码只保存在本机，用于 Token 过期后自动重新登录。',
    required: true,
    managedAccount: true,
    registerUrl: 'https://manhuabika.com/pregister/?',
    fields: [
      { key: 'email', label: '用户名 / 邮箱' },
      { key: 'password', label: '密码', secret: true },
    ],
    async login(values) {
      const email = String(values.email || '').trim();
      const password = String(values.password || '');
      if (!email || !password) throw Park.error('LOGIN_REQUIRED', '请输入账号和密码');
      if (this.config.managedAccount) throw Park.error('CONFIG', '请先关闭专用自动维护账号，再配置自己的账号');
      const token = await this.signIn(email, password);
      this.store.set('credentials', { email, password });
      this.store.set('token', token);
      const profile = await this.request('users/profile').catch(() => null);
      const name = (profile && profile.user && profile.user.name) || email;
      this.store.set('name', name);
      await this.store.flush();
      return { name };
    },
    async enableManaged() {
      if (!this.config.managedAccount) throw Park.error('CONFIG', '请先确认启用专用自动维护账号');
      if (this.store.get('credentials')) throw Park.error('CONFIG', '已有手动账号，请先退出登录再启用专用账号');
      await this.ensureSession(undefined, true);
      return { name: this.activeAccount().name || this.activeAccount().email };
    },
    async logout() {
      if (this.config.managedAccount) {
        const account = this.store.get('managedAccount');
        if (account) this.store.set('managedAccount', { ...account, token: null });
        await this.store.flush();
        return;
      }
      this.store.set('token', null);
      this.store.set('credentials', null);
      this.store.set('name', null);
      await this.store.flush();
    },
    async status() {
      const account = this.activeAccount();
      return { loggedIn: !!(account && account.token), configured: !!(account && account.email && account.password), name: account && (account.name || account.email) || '' };
    },
  },

  defaultFeed: 'ranking',
  feeds: [
    {
      key: 'ranking',
      label: '排行榜',
      options: [
        {
          key: 'period',
          label: '周期',
          default: 'H24',
          values: [
            { value: 'H24', label: '24 小时' },
            { value: 'D7', label: '7 天' },
            { value: 'D30', label: '30 天' },
          ],
        },
      ],
    },
    { key: 'random', label: '随便看看' },
    {
      key: 'category',
      label: '分区',
      options: [
        {
          key: 'category',
          label: '分区',
          default: '全彩',
          values: [
            '大家都在看', '大濕推薦', '那年今天', '官方都在看', '嗶咔漢化', '全彩', '長篇', '同人', '短篇',
            '圓神領域', '碧藍幻想', 'CG雜圖', '英語 ENG', '生肉', '純愛', '百合花園', '耽美花園', '偽娘哲學',
            '後宮閃光', '扶他樂園', '單行本', '姐姐系', '妹妹系', 'SM', '性轉換', '足の恋', '人妻', 'NTR',
            '強暴', '非人類', '艦隊收藏', 'Love Live', 'SAO 刀劍神域', 'Fate', '東方', 'WEBTOON', '禁書目錄',
            '歐美', 'Cosplay', '重口地帶',
          ].map((c) => ({ value: c, label: c })),
        },
        {
          key: 'sort',
          label: '排序',
          default: 'dd',
          values: [
            { value: 'dd', label: '新到旧' },
            { value: 'da', label: '旧到新' },
            { value: 'ld', label: '最多爱心' },
            { value: 'vd', label: '最多观看' },
          ],
        },
      ],
    },
  ],

  searchHint: '关键词为普通文字，可配合分区筛选',
  searchFilters: [
    {
      key: 'sort',
      label: '排序',
      default: 'dd',
      values: [
        { value: 'dd', label: '新到旧' },
        { value: 'da', label: '旧到新' },
        { value: 'ld', label: '最多爱心' },
        { value: 'vd', label: '最多观看' },
      ],
    },
  ],

  BASE: 'https://picaapi.picacomic.com/',
  API_KEY: 'C69BAF41DA5ABD1FFEDC6D2FEA56B',
  SECRET: '~d}$Q7$eIni=V)9\\RK/P.RM4;9[7|@/CA}b~OW!3?EV`:<>M7pddUBL5n|0/*Cn',

  async headersFor(method, path) {
    const time = String(Math.floor(Date.now() / 1000));
    const nonce = (await Park.crypto.uuid()).replace(/-/g, '');
    const raw = `${path}${time}${nonce}${method}${this.API_KEY}`.toLowerCase();
    const headers = {
      'api-key': this.API_KEY,
      accept: 'application/vnd.picacomic.com.v1+json',
      // Authentication goes directly to the API hostname: app-channel 2/3 can return 1023.
      'app-channel': path.startsWith('auth/') ? '1' : this.config.channel || '1',
      time,
      nonce,
      signature: await Park.crypto.hmacSha256Hex(this.SECRET, raw),
      'app-version': '2.2.1.3.3.4',
      'app-uuid': 'defaultUuid',
      'image-quality': this.config.quality || 'original',
      'app-platform': 'android',
      'app-build-version': '45',
      'User-Agent': 'okhttp/3.8.1',
      'Content-Type': 'application/json; charset=UTF-8',
    };
    const account = this.activeAccount();
    const token = account && account.token;
    if (token) headers.authorization = token;
    return headers;
  },

  async send(method, path, body) {
    const res = await this.http.request({
      url: this.BASE + path,
      method,
      headers: await this.headersFor(method, path),
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    let json = {};
    try {
      json = res.json();
    } catch (e) {
      /* non-JSON error page */
    }
    if (!json || typeof json !== 'object' || Array.isArray(json)) json = {};
    if (path === 'auth/register' || path === 'auth/sign-in') {
      const stage = path === 'auth/register' ? '注册' : '登录';
      const code = Number.isInteger(json.code) ? json.code : '未知';
      const error = /^\d{1,6}$/.test(String(json.error || '')) ? String(json.error) : '无';
      this.log(`哔咔${stage}响应：HTTP ${res.status}，业务码 ${code}，错误码 ${error}`);
    }
    return { status: res.status, json };
  },

  async signIn(email, password) {
    const { status, json } = await this.send('POST', 'auth/sign-in', { email, password });
    const token = json && json.data && json.data.token;
    if (status !== 200 || !token) {
      throw Park.error('LOGIN_REQUIRED', '哔咔登录失败：{value0}', { params: {value0: (json && (json.message || json.error)) || 'HTTP ' + status},
        status,
        rateLimited: status === 429 || String(json.error) === '1023',
        invalidCredentials: status === 400 && (String(json.error) === '1004' || /invalid (?:email|account) or password/i.test(String(json.message || ''))),
      });
    }
    return token;
  },

  activeAccount() {
    if (this.config.managedAccount && !this.store.get('credentials')) return this.store.get('managedAccount');
    const credentials = this.store.get('credentials');
    return credentials ? { ...credentials, token: this.store.get('token'), name: this.store.get('name', '') } : null;
  },

  /** Shared login promise prevents concurrent feed/detail requests from repeatedly refreshing. */
  async ensureSession(staleToken, force = false) {
    const current = this.activeAccount();
    if (current && current.token && (staleToken === undefined || current.token !== staleToken)) return;
    if (this._sessionPending) return this._sessionPending;
    const run = this.restoreSession(force);
    this._sessionPending = run;
    try { await run; } finally { this._sessionPending = null; }
  },

  async restoreSession(force) {
    const managed = this.config.managedAccount && !this.store.get('credentials');
    const account = managed && this.store.get('managedAccount');
    if (account && account.retryAt > Date.now() && (!force || account.rateLimited)) {
      const minutes = Math.max(1, Math.ceil((account.retryAt - Date.now()) / 60000));
      throw Park.error('LOGIN_REQUIRED', '哔咔账号正在冷却，请在 {value0} 分钟后重试', { params: {value0: minutes} });
    }
    try {
      await this.loginSession();
    } catch (error) {
      if (managed) {
        const saved = this.store.get('managedAccount');
        if (saved) {
          const failures = (Number(saved.failures) || 0) + 1;
          const delay = Math.min(24 * 3600000, (error.rateLimited ? 6 * 3600000 : 600000) * Math.pow(2, failures - 1));
          this.store.set('managedAccount', { ...saved, failures, retryAt: Date.now() + delay, rateLimited: !!error.rateLimited });
          // Preserve the original failure; persistence failure still prohibits external requests.
          await this.store.flush().catch(() => {});
        }
      }
      throw error;
    }
  },

  async loginSession() {
    const manual = this.store.get('credentials');
    const managed = this.config.managedAccount && !manual;
    let account = managed ? this.store.get('managedAccount') : manual;
    if (!account && !managed) throw Park.error('LOGIN_REQUIRED', '哔咔需要登录后才能使用');
    if (managed && !account) {
      const id = (await Park.crypto.uuid()).replace(/-/g, '');
      const password = (await Park.crypto.uuid()).replace(/-/g, '');
      account = { email: 'hp' + id.slice(0, 20), password, registered: false, token: null, name: '' };
      this.store.set('managedAccount', account);
      // Registration must never run unless this account is already recoverable from disk.
      await this.store.flush();
    }
    let token;
    for (let attempt = 0; attempt < 2; attempt++) {
      const registering = managed && !account.registered;
      if (registering) {
        await this.store.flush();
        const { status, json } = await this.send('POST', 'auth/register', {
          // Keep the display name short; the API rejects a 22-character name with error 1009.
          email: account.email, password: account.password, name: account.email.slice(0, 12),
          birthday: '2000-01-01', gender: 'm',
          question1: '1', question2: '2', question3: '3',
          answer1: '1', answer2: '2', answer3: '3',
        });
        const success = status === 200 && json.code === 200 && json.message === 'success' && !json.error;
        const exists = status === 400 && (String(json.error) === '1008' || /(?:email|account) is already exist/i.test(String(json.message || '')));
        if (!success && !exists) {
          throw Park.error('HTTP', '哔咔注册失败：{value0}', { params: {value0: json.message || json.error || 'HTTP ' + status}, status, rateLimited: status === 429 || String(json.error) === '1023' });
        }
        // An existing username alone does not prove these saved credentials belong to it.
        if (success) {
          account = { ...account, registered: true };
          this.store.set('managedAccount', account);
          await this.store.flush();
        }
      }
      if (managed) this.store.set('managedAccount', { ...account, token: null });
      else this.store.set('token', null);
      try {
        token = await this.signIn(account.email, account.password);
        break;
      } catch (error) {
        if (!managed || !error.invalidCredentials) throw error;
        account = { ...account, registered: false, token: null };
        this.store.set('managedAccount', account);
        await this.store.flush();
        // Recover a rejected registration marker once, preserving the same identity.
        // A newly registered account must not cause an immediate registration loop.
        if (registering || attempt > 0) throw error;
      }
    }
    if (managed) {
      account = { ...account, registered: true };
      this.store.set('managedAccount', { ...account, token, failures: 0, retryAt: 0, rateLimited: false });
    } else this.store.set('token', token);
    await this.store.flush();
    const profile = await this.send('GET', 'users/profile').catch(() => null);
    const name = profile && profile.json && profile.json.data && profile.json.data.user && profile.json.data.user.name || account.email;
    if (managed) this.store.set('managedAccount', { ...account, token, name, failures: 0, retryAt: 0, rateLimited: false });
    else this.store.set('name', name);
    await this.store.flush();
  },

  /** Authenticated request; returns `data`. Re-logs in once on 401. */
  async request(path, body) {
    const method = body === undefined ? 'GET' : 'POST';
    await this.ensureSession();
    for (let attempt = 0; attempt < 2; attempt++) {
      const token = this.activeAccount() && this.activeAccount().token;
      const { status, json } = await this.send(method, path, body);
      if (status === 401 && attempt === 0) {
        await this.ensureSession(token);
        continue;
      }
      if (status === 401) {
        const active = this.activeAccount();
        if (active && active.token === token) {
          if (this.config.managedAccount && !this.store.get('credentials')) this.store.set('managedAccount', { ...active, token: null });
          else this.store.set('token', null);
          await this.store.flush();
        }
        throw Park.error('LOGIN_REQUIRED', '哔咔登录状态失效');
      }
      if (status === 400 || status === 404) throw Park.error('NOT_FOUND', '哔咔：{value0}', { params: {value0: json.message || '内容不存在'} });
      if (status !== 200) throw Park.error('HTTP', '哔咔请求失败：HTTP {value0} {value1}', { params: {value0: status, value1: json.message || ''}, status });
      return json.data || {};
    }
    throw Park.error('LOGIN_REQUIRED', '哔咔登录状态失效');
  },

  imageUrl(m) {
    if (!m || !m.path) return '';
    const server = String(m.fileServer || 'https://storage1.picacomic.com').replace(/\/$/, '');
    return m.path.startsWith('http') ? m.path : `${server}/static/${m.path}`;
  },

  toItem(c) {
    return {
      id: String(c._id),
      title: String(c.title || '').trim(),
      subtitle: String(c.author || '').trim(),
      cover: this.imageUrl(c.thumb),
      coverAspect: 0.72,
      pages: Number(c.pagesCount) || 0,
      likes: Number(c.totalLikes !== undefined ? c.totalLikes : c.likesCount) || 0,
      views: Number(c.totalViews !== undefined ? c.totalViews : c.viewsCount) || null,
      category: (c.categories || [])[0] || '', // one category keeps the cover badge readable
      badge: c.finished ? '完结' : '',
      tags: (c.tags || []).slice(0, 6),
    };
  },

  pageOf(comics, page) {
    const docs = (comics && comics.docs) || [];
    const totalPages = Number(comics && comics.pages) || null;
    return {
      items: docs.filter((d) => d && d._id).map((d) => this.toItem(d)),
      page,
      totalPages,
      total: Number(comics && comics.total) || null,
      hasNext: !!totalPages && page < totalPages,
    };
  },

  async feed(key, req) {
    const page = Math.max(1, req.page || 1);
    const o = req.options || {};
    if (key === 'ranking') {
      const data = await this.request(`comics/leaderboard?tt=${o.period || 'H24'}&ct=VC`);
      return { items: (data.comics || []).map((c) => this.toItem(c)), page: 1, totalPages: 1, hasNext: false };
    }
    if (key === 'random') {
      const data = await this.request('comics/random');
      return { items: (data.comics || []).map((c) => this.toItem(c)), page, hasNext: true };
    }
    const c = encodeURIComponent(o.category || '全彩');
    const data = await this.request(`comics?page=${page}&c=${c}&s=${o.sort || 'dd'}`);
    return this.pageOf(data.comics, page);
  },

  async search(req) {
    const page = Math.max(1, req.page || 1);
    const f = req.filters || {};
    const body = { keyword: String(req.keyword || '').trim(), sort: f.sort || 'dd' };
    if (f.category) body.categories = [f.category];
    const data = await this.request(`comics/advanced-search?page=${page}`, body);
    return this.pageOf(data.comics, page);
  },

  async random() {
    const data = await this.request('comics/random');
    const list = data.comics || [];
    if (!list.length) throw Park.error('NOT_FOUND', '哔咔随机接口没有返回作品');
    return String(list[Math.floor(Math.random() * list.length)]._id);
  },

  async episodes(id) {
    const all = [];
    for (let page = 1; page <= 50; page++) {
      const data = await this.request(`comics/${id}/eps?page=${page}`);
      const eps = data.eps || {};
      all.push(...(eps.docs || []));
      if (!eps.pages || page >= eps.pages) break;
    }
    // `order` is what the pages endpoint expects; the list comes newest first.
    return all.sort((a, b) => a.order - b.order).map((e) => ({ id: String(e.order), title: e.title || `第 ${e.order} 话` }));
  },

  async detail(id) {
    const [info, chapters, related] = await Promise.all([
      this.request(`comics/${id}`),
      this.episodes(id),
      this.request(`comics/${id}/recommendation`).catch(() => ({})),
    ]);
    const c = info.comic;
    if (!c || !c._id) throw Park.error('NOT_FOUND', '哔咔作品 {value0} 不存在', { params: {value0: id} });
    const item = this.toItem(c);
    const group = (ns, label, list) =>
      list && list.length ? { namespace: ns, label, tags: list.map((name) => ({ name, keyword: name })) } : null;
    return Object.assign(item, {
      url: '',
      authors: [c.author, c.chineseTeam].filter(Boolean),
      description: String(c.description || '').trim(),
      uploaded: String(c.updated_at || c.created_at || '').slice(0, 10),
      comments: Number(c.totalComments || c.commentsCount) || null,
      tags: [group('categories', '分区', c.categories), group('tags', '标签', c.tags)].filter(Boolean),
      chapters: chapters.length > 1 ? chapters : null,
      singleChapterId: chapters.length === 1 ? chapters[0].id : '1',
      related: (related.comics || []).map((r) => this.toItem(r)),
    });
  },

  async chapter(id, chapterId) {
    const order = chapterId || '1';
    const first = (await this.request(`comics/${id}/order/${order}/pages?page=1`)).pages || {};
    const total = Number(first.pages) || 1;
    const rest = await Park.utils.mapLimit(
      Array.from({ length: Math.max(0, total - 1) }, (_, i) => i + 2),
      4,
      (p) => this.request(`comics/${id}/order/${order}/pages?page=${p}`)
    );
    const docs = (first.docs || []).concat(...rest.map((r) => (r.pages && r.pages.docs) || []));
    return { pages: docs.map((d) => ({ url: this.imageUrl(d.media) })).filter((p) => p.url) };
  },
});

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"},{"key":"filter","label":"标签或作者筛选","hint":"从详情页标签菜单添加"},{"key":"work","label":"作品连载","hint":"作品编号或详情链接"}],"searchFilters":{"sort":"dd"}});
