/* GalgameX: public catalogue + click-time download resolution. No signed links in metadata. */
(function () {
  const BASE = 'https://www.galgamex.net';
  const fail = () => Park.error('PARSE', '游戏站点返回的数据无效');
  const loginRequired = () => Park.error('LOGIN_REQUIRED', '该游戏需要登录，请在应用内登录 GalgameX 后重试');
  const idOf = value => { const id = String(value); if (!/^[a-z0-9]{8}$/.test(id)) throw fail(); return id; };
  const flight = html => [...html.matchAll(/self\.__next_f\.push\(\[1,("(?:[^"\\]|\\.)*")\]\)/g)].map(m => JSON.parse(m[1])).join('');
  // Flight records may contain length-prefixed text with embedded newlines.
  // Read the JSON value itself, without executing remote JavaScript or assuming line boundaries.
  function valueAt(text, start) {
    const first = text[start];
    if (first !== '{' && first !== '[') return null;
    let depth = 0, quoted = false, escaped = false;
    for (let i = start; i < text.length; i++) {
      const c = text[i];
      if (quoted) { if (escaped) escaped = false; else if (c === '\\') escaped = true; else if (c === '"') quoted = false; continue; }
      if (c === '"') quoted = true;
      else if (c === '{' || c === '[') depth++;
      else if ((c === '}' || c === ']') && --depth === 0) { try { return JSON.parse(text.slice(start, i + 1)); } catch (_) { return null; } }
    }
    return null;
  }
  function field(text, name) {
    const pattern = new RegExp('"' + name + '":([\\[{])', 'g');
    for (const match of text.matchAll(pattern)) { const value = valueAt(text, match.index + name.length + 3); if (value != null) return value; }
    return null;
  }
  function commentItems(rows, gameId, workId, targetId) {
    const raw = new Map();
    const visit = (list, depth = 0) => {
      if (!Array.isArray(list) || depth > 30) throw fail();
      for (const row of list) {
        if (!Number.isSafeInteger(row?.id) || row.id < 1 || row.gameId !== gameId ||
            (row.parentId != null && (!Number.isSafeInteger(row.parentId) || row.parentId < 1)) ||
            typeof row.content !== 'string' || !Array.isArray(row.children)) throw fail();
        if (raw.has(row.id)) continue;
        raw.set(row.id, row);
        visit(row.children, depth + 1);
      }
    };
    visit(rows);
    if (targetId && !raw.has(targetId)) throw Park.error('NOT_FOUND', '内容不存在或已被删除');
    const nodes = new Map();
    for (const row of raw.values()) {
      const path = new Set([row.id]);
      let ancestor = row.parentId, descendant = !targetId;
      while (ancestor != null) {
        if (path.has(ancestor)) throw fail();
        path.add(ancestor);
        if (ancestor === targetId) descendant = true;
        ancestor = raw.get(ancestor)?.parentId;
      }
      if (!descendant || row.isDeleted === true) continue;
      const body = Park.comments.html(row.content, BASE + '/game/' + workId);
      if (!body.length) continue;
      nodes.set(row.id, {id: workId + '/' + row.id,
        author: {name: typeof row.user?.name === 'string' ? row.user.name : '',
          avatar: Park.comments.url(row.user?.image, BASE) || undefined},
        body, date: row.createdAt || undefined, likes: Math.max(0, Number(row.likeCount) || 0),
        parentId: row.parentId == null ? undefined : workId + '/' + row.parentId,
        replyCount: 0, repliesAvailable: false, replies: []});
    }
    // 原站 children 同时包含直接回复和扁平孙楼，必须按 parentId 还原层级。
    const items = [];
    for (const [id, node] of nodes) {
      const parent = nodes.get(raw.get(id).parentId);
      if (parent) { parent.replies.push(node); parent.replyCount++; }
      else items.push(node);
    }
    return items;
  }
  function catalogue(html, namespace) {
    const text = flight(html), found = [];
    function visit(value) {
      if (!value || typeof value !== 'object') return;
      if (value.queryOptions?.namespace === namespace && Array.isArray(value.games)) found.push(value);
      for (const child of Object.values(value)) visit(child);
    }
    for (const match of text.matchAll(/(?:^|\n)[0-9a-f]+:([\[{])/g)) {
      visit(valueAt(text, match.index + match[0].length - 1));
    }
    if (found.length !== 1) throw fail();
    return found[0];
  }
  const platforms = ['windows', 'mac', 'linux', 'android', 'ios', 'ps', 'switch', 'xbox'];
  const languages = ['SimplifiedChinese', 'TraditionalChinese', 'English', 'Japanese', 'Korean', 'French', 'German', 'Spanish', 'Russian', 'Italian', 'Thai', 'Vietnamese'];
  const sorts = ['resource_updated', 'newest', 'recently_added', 'rating', 'downloads'];
  const filters = [
    {key: 'platform', label: '平台', type: 'select', default: '', values: [{value: '', label: '全部'},
      ...platforms.map((value, i) => ({value, label: ['Windows', 'macOS', 'Linux', 'Android', 'iOS', 'PlayStation', 'Nintendo Switch', 'Xbox'][i]}))]},
    {key: 'language', label: '语言', type: 'select', default: '', values: [{value: '', label: '全部'},
      ...languages.map((value, i) => ({value, label: ['简体中文', '繁體中文', 'English', '日本語', '한국어', 'Français', 'Deutsch', 'Español', 'Русский', 'Italiano', 'ไทย', 'Tiếng Việt'][i]}))]},
    {key: 'sort', label: '排序', type: 'select', default: 'resource_updated', values:
      sorts.map((value, i) => ({value, label: ['资源更新', '最新', '最近收录', '评分', '下载量'][i]}))},
    {key: 'tagRange', label: '索引', type: 'select', default: '1', dynamic: true, values: []},
    {key: 'tag', label: '标签', type: 'select', default: '', dynamic: true, dependsOn: ['tagRange'], values: []},
  ];
  const item = g => ({ id: String(g.uniqueId), title: g.name || '', subtitle: (g.altNames || []).join(' / '),
    cover: g.coverImage || g.headerImage || '', coverAspect: g.coverImage ? 0.67 : 16 / 9,
    rating: g.ratingStats?.averageRating, views: g.viewCount, likes: g._count?.favorites,
    uploaded: String(g.resourceUpdatedAt || '').replace(/^\$D/, ''),
    tags: (g.tags || []).map(t => t.name), mediaKind: 'game', contentDomain: 'game',
    // Site visibility flag is separate from game content tags.
    contentRating: (g.tags || []).some(t => /^r-?18$/i.test(t.name)) ? 'r18' : 'unknown', isNsfw: !!g.isNsfw });
  const channel = (url, index, size) => {
    let parsed; try { parsed = new URL(url); } catch (_) { return null; }
    if (!['https:', 'http:'].includes(parsed.protocol) || parsed.username || parsed.password) return null;
    const direct = parsed.protocol === 'https:' && parsed.hostname === 'game.galgamex.com';
    const filename = decodeURIComponent(parsed.pathname.split('/').pop() || '');
    return { id: String(index), kind: direct ? 'direct' : 'external',
      label: direct ? filename : parsed.hostname === 'pan.baidu.com' ? '百度网盘' : parsed.hostname, size: size || '' };
  };
  // Public direct links omit the storage directory; Baidu links omit /s/.
  // Match the selected file/share rather than trusting resolver array order.
  const linkIdentity = value => {
    let parsed; try { parsed = new URL(value); } catch (_) { return null; }
    if (!channel(value, 0)) return null;
    const tail = decodeURIComponent(parsed.pathname.split('/').pop() || '');
    return parsed.origin + (parsed.hostname === 'game.galgamex.com' || parsed.hostname === 'pan.baidu.com' ? '/' + tail : parsed.pathname);
  };
  Park.register({
    i18n: {
      "zh-Hant": {"GalgameX 账号": "GalgameX 帳號", "无法获取游戏资源，请在原站检查权限": "遊戲資源或下載回應無效，請檢查原站權限後重試。", "游戏目录、版本资源与直链和网盘渠道": "遊戲目錄、版本資源與直連和網盤管道", "该游戏需要登录，请在应用内登录 GalgameX 后重试": "該遊戲需要登入，請在應用程式內登入 GalgameX 後重試", "部分游戏需要登录；打开网页后点击右上角账号按钮登录，完成后返回重试。Cookie 仅保存在本机。": "部分遊戲需要登入；開啟網頁後點擊右上角帳號按鈕登入，完成後返回重試。Cookie 僅儲存在本機。"},
      "ja": {"GalgameX 账号": "GalgameX アカウント", "无法获取游戏资源，请在原站检查权限": "ゲームリソースまたは応答が無効です。元サイトの権限を確認して再試行してください。", "游戏目录、版本资源与直链和网盘渠道": "ゲームカタログ、バージョン、直接・クラウドダウンロード", "该游戏需要登录，请在应用内登录 GalgameX 后重试": "このゲームにはログインが必要です。アプリ内で GalgameX にログインして再試行してください", "部分游戏需要登录；打开网页后点击右上角账号按钮登录，完成后返回重试。Cookie 仅保存在本机。": "一部のゲームはログインが必要です。ページ右上のアカウントボタンでログイン後、戻って再試行してください。Cookie は端末内にのみ保存されます。"},
      "ko": {"GalgameX 账号": "GalgameX 계정", "无法获取游戏资源，请在原站检查权限": "게임 자료 또는 응답이 올바르지 않습니다. 원본 사이트 권한을 확인하고 재시도하세요.", "游戏目录、版本资源与直链和网盘渠道": "게임 목록, 버전, 직접 및 클라우드 다운로드", "该游戏需要登录，请在应用内登录 GalgameX 后重试": "이 게임은 로그인이 필요합니다. 앱에서 GalgameX에 로그인한 후 다시 시도하세요", "部分游戏需要登录；打开网页后点击右上角账号按钮登录，完成后返回重试。Cookie 仅保存在本机。": "일부 게임은 로그인이 필요합니다. 웹페이지 오른쪽 위 계정 버튼으로 로그인 후 돌아와 다시 시도하세요. 쿠키는 이 기기에만 저장됩니다."},
      "en": {"GalgameX 账号": "GalgameX account", "无法获取游戏资源，请在原站检查权限": "Invalid game resource or download response. Check access on the original site and retry.", "游戏目录、版本资源与直链和网盘渠道": "Game catalogue, versions, direct and cloud downloads", "该游戏需要登录，请在应用内登录 GalgameX 后重试": "This game requires sign-in. Sign in to GalgameX within the app, then retry", "部分游戏需要登录；打开网页后点击右上角账号按钮登录，完成后返回重试。Cookie 仅保存在本机。": "Some games require sign-in. Open the page and use the account button at the top right, then return and retry. Cookies stay on this device."},
      "es": {"GalgameX 账号": "Cuenta de GalgameX", "无法获取游戏资源，请在原站检查权限": "Recurso o respuesta de descarga no válido. Comprueba los permisos del sitio y reintenta.", "游戏目录、版本资源与直链和网盘渠道": "Catálogo de juegos, versiones y descargas directas y en la nube", "该游戏需要登录，请在应用内登录 GalgameX 后重试": "Este juego requiere iniciar sesión. Accede a GalgameX desde la app y reinténtalo", "部分游戏需要登录；打开网页后点击右上角账号按钮登录，完成后返回重试。Cookie 仅保存在本机。": "Algunos juegos requieren iniciar sesión. Usa el botón de cuenta arriba a la derecha y vuelve a intentarlo. Las cookies solo se guardan en este dispositivo."},
      "ru": {"GalgameX 账号": "Аккаунт GalgameX", "无法获取游戏资源，请在原站检查权限": "Недействительный ресурс или ответ загрузки. Проверьте доступ на сайте и повторите.", "游戏目录、版本资源与直链和网盘渠道": "Каталог игр, версии, прямые и облачные загрузки", "该游戏需要登录，请在应用内登录 GalgameX 后重试": "Для этой игры нужен вход. Войдите в GalgameX через приложение и повторите попытку", "部分游戏需要登录；打开网页后点击右上角账号按钮登录，完成后返回重试。Cookie 仅保存在本机。": "Некоторые игры требуют входа. Нажмите кнопку аккаунта справа вверху страницы, войдите и повторите попытку. Cookie хранятся только на устройстве."},
      "ar": {"GalgameX 账号": "حساب GalgameX", "无法获取游戏资源，请在原站检查权限": "مورد أو استجابة تنزيل غير صالحة. تحقق من صلاحيات الموقع وأعد المحاولة.", "游戏目录、版本资源与直链和网盘渠道": "دليل ألعاب وإصدارات وتنزيلات مباشرة وسحابية", "该游戏需要登录，请在应用内登录 GalgameX 后重试": "تتطلب هذه اللعبة تسجيل الدخول. سجّل الدخول إلى GalgameX داخل التطبيق ثم أعد المحاولة", "部分游戏需要登录；打开网页后点击右上角账号按钮登录，完成后返回重试。Cookie 仅保存在本机。": "تتطلب بعض الألعاب تسجيل الدخول. افتح الصفحة واستخدم زر الحساب أعلى اليمين ثم عد وأعد المحاولة. تُحفظ ملفات تعريف الارتباط على هذا الجهاز فقط."},
    },
    key: 'galgamex', name: 'GalgameX', version: '0.0.11', minAppVersion: '0.9.2', type: 'game', category: 'game', color: '#E984AE',
    description: '游戏目录、版本资源与直链和网盘渠道', homepage: BASE, language: 'chinese',
    domains: ['galgamex.net'],
    imageHeaders: {Referer: BASE + '/'},
    media: { mode: 'native', origin: BASE, domains: ['game.galgamex.com'] },
    network: { mode: 'native', vpnHint: true },
    linkPatterns: ['https?://(?:www\\.)?galgamex\\.net/game/([a-z0-9]{8})'], idPattern: '^([a-z0-9]{8})$', idExample: '9476825d',
    defaultFeed: 'ranking', feeds: [{ key: 'ranking', label: '本周热门' }, { key: 'latest', label: '资源更新', options: [
      {key: 'section', label: '分区', type: 'select', default: 'gal', values: [{value: 'gal', label: 'Galgame'}, {value: 'tr', label: '同人'}]}, ...filters,
    ] }],
    searchFilters: filters,
    settings: [{ key: 'nsfw', type: 'switch', label: '显示 NSFW 内容', default: true }],
    account: {
      type: 'cookies', title: 'GalgameX 账号', required: false,
      hint: '部分游戏需要登录；打开网页后点击右上角账号按钮登录，完成后返回重试。Cookie 仅保存在本机。',
      loginUrl: BASE, cookieUrl: BASE + '/', requiredCookies: [],
      fields: [{key: 'cookie', label: 'Cookie', secret: true}],
      async login(values) {
        const cookies = {};
        if (values.cookie) {
          for (const part of String(values.cookie).split(';')) {
            const at = part.indexOf('=');
            if (at > 0) cookies[part.slice(0, at).trim()] = part.slice(at + 1).trim();
          }
        } else Object.assign(cookies, values);
        const safe = {};
        for (const [key, value] of Object.entries(cookies)) {
          if (/^[A-Za-z0-9_.-]{1,100}$/.test(key) && typeof value === 'string' && !/[\r\n;]/.test(value)) safe[key] = value;
        }
        if (!Object.keys(safe).length) throw loginRequired();
        await this.cookies.set(BASE + '/', safe);
        const session = await this.http.json(BASE + '/api/auth/get-session');
        if (!session?.user?.id) throw loginRequired();
        return {name: session.user.name || 'GalgameX'};
      },
      async logout() { await this.cookies.clear(BASE + '/'); },
      async status() {
        const session = await this.http.json(BASE + '/api/auth/get-session');
        return {loggedIn: !!session?.user?.id, name: session?.user?.name || ''};
      },
    },
    async init() { this.actionCache = new Map(); this.gameIds = new Map(); this.tagCache = new Map(); },
    async filter() {
      await this.http.json(BASE + '/api/content-filter', { method: 'POST', json: { value: this.config.nsfw ? 'all' : 'sfw' } });
    },
    async page(path) { await this.filter(); return this.http.text(BASE + path); },
    async serverActions(path, names, refresh = false) {
      const cached = this.actionCache.get(path);
      if (!refresh && cached && Date.now() - cached.time < 900000 && names.every(name => cached.ids[name])) return cached.ids;
      const html = await this.page(path);
      const scripts = [...new Set([...html.matchAll(/<script[^>]+src="([^\"]+)"/g)].map(m => m[1]).filter(p => p.startsWith('/_next/static/chunks/')))];
      const ids = {};
      for (let start = 0; start < scripts.length && !names.every(name => ids[name]); start += 4) {
        const texts = await Promise.all(scripts.slice(start, start + 4).map(p => this.http.text(BASE + p)));
        for (const text of texts) {
          for (const name of names) {
            const match = new RegExp('createServerReference\\)\\("([0-9a-f]{40,42})",[^;]{0,250}?"' + name + '"\\)').exec(text);
            if (match) ids[name] = match[1];
          }
        }
      }
      if (!names.every(name => ids[name])) throw fail();
      this.actionCache.set(path, { ids, time: Date.now() }); return ids;
    },
    async interactionAction(path, name, args) {
      const actions = await this.serverActions(path, ['getGameInteractionStatus', 'toggleGameFavorite', 'getUserCollections']);
      const response = await this.http.post(BASE + path, { readOnly: ['getGameInteractionStatus', 'getUserCollections'].includes(name), body: JSON.stringify(args), headers: {
        'Next-Action': actions[name], Accept: 'text/x-component', 'Content-Type': 'text/plain;charset=UTF-8' } });
      if ([401, 403].includes(response.status)) throw loginRequired();
      this.http.ensureOk(response);
      const line = /(?:^|\n)1:/.exec(response.body);
      const result = line ? valueAt(response.body, line.index + line[0].length) : null;
      if (result == null) throw fail();
      return result;
    },
    async interaction(id, req = {}) {
      id = idOf(id);
      const session = await this.http.json(BASE + '/api/auth/get-session');
      if (!session?.user?.id) throw loginRequired();
      if (req.value !== undefined && (req.type !== 'favorite' || typeof req.value !== 'boolean')) throw Park.error('CONFIG', '原站互动数据无效');
      if (!this.gameIds.has(id)) await this.detail(id);
      const gameId = this.gameIds.get(id), path = '/game/' + id;
      const read = async () => {
        const data = await this.interactionAction(path, 'getGameInteractionStatus', [gameId]);
        if (typeof data.isFavorited !== 'boolean' || !Array.isArray(data.favoritedCollectionIds) ||
            data.isFavorited !== (data.favoritedCollectionIds.length > 0)) throw fail();
        return data;
      };
      let data = await read();
      if (req.value !== undefined && data.isFavorited !== req.value) {
        let collections = data.favoritedCollectionIds;
        if (req.value) {
          const available = await this.interactionAction(path, 'getUserCollections', []);
          if (!Array.isArray(available)) throw fail();
          if (!available.length) throw Park.error('UNSUPPORTED', '请先在原站创建收藏夹');
          if (!['number', 'string'].includes(typeof available[0]?.id) || String(available[0].id).length > 128) throw fail();
          collections = [available[0].id];
        }
        // Every toggle is user requested and sent once; never retry an uncertain write.
        for (const collection of collections) await this.interactionAction(path, 'toggleGameFavorite', [gameId, collection]);
        data = await read();
        if (data.isFavorited !== req.value) throw Park.error('AUTH', '原站操作未成功，请重试');
      }
      return [{ type: 'favorite', value: data.isFavorited }];
    },
    async tagPage(page) {
      if (!Number.isInteger(page) || page < 1 || page > 500) throw Park.error('CONFIG', '筛选参数无效');
      const cached = this.tagCache.get(page);
      if (cached && Date.now() - cached.time < 300000) return cached.data;
      const result = await this.http.json(BASE + '/api/game/tags', {params: {pageIndex: page, pageSize: 100}}), data = result?.data;
      if (!Array.isArray(data?.tags) || !Number.isSafeInteger(data.total) || data.total < 0 || data.total > 50000) throw fail();
      this.tagCache.set(page, {time: Date.now(), data});
      while (this.tagCache.size > 8) this.tagCache.delete(this.tagCache.keys().next().value);
      return data;
    },
    async filterOptions(req) {
      if (req.filter === 'tagRange') {
        const data = await this.tagPage(1);
        return Array.from({length: Math.max(1, Math.ceil(data.total / 100))}, (_, i) =>
          ({value: String(i + 1), label: (i * 100 + 1) + '–' + Math.min((i + 1) * 100, data.total)}));
      }
      if (req.filter !== 'tag') return [];
      const data = await this.tagPage(Number(req.values.tagRange || '1'));
      return [{value: '', label: '全部'}, ...data.tags.map(t => {
        if (typeof t.slug !== 'string' || !t.slug || t.slug.length > 240 || /[,\r\n]/.test(t.slug) || !t.name) throw fail();
        return {value: t.slug, label: String(t.name)};
      })];
    },
    async list(namespace, page, values = {}, keyword) {
      if (!Number.isInteger(page) || page < 1 || page > 1000000) throw Park.error('CONFIG', '分页参数无效');
      const params = new URLSearchParams();
      if (keyword !== undefined) params.set('q', String(keyword));
      params.set(namespace + '_page', String(page));
      for (const [key, allowed, fallback] of [['platform', platforms, ''], ['language', languages, ''], ['sort', sorts, 'resource_updated']]) {
        const value = values[key] || fallback;
        if (value && !allowed.includes(value)) throw Park.error('CONFIG', '筛选参数无效');
        if (value) params.set(namespace + '_' + key, value);
      }
      if (values.tag) {
        if (typeof values.tag !== 'string' || values.tag.length > 240 || /[,\r\n]/.test(values.tag)) throw Park.error('CONFIG', '筛选参数无效');
        params.set(namespace + '_tags', values.tag);
      }
      const value = catalogue(await this.page((keyword === undefined ? '/games?' : '/search?') + params), namespace);
      if (!Number.isSafeInteger(value.total) || !Number.isSafeInteger(value.limit) || value.limit < 1 || value.page !== page) throw fail();
      return {items: value.games.map(item), page, total: value.total, hasNext: page * value.limit < value.total};
    },
    async feed(key, { page = 1, options = {} } = {}) {
      if (key === 'ranking') {
        if (page > 1) return { items: [], page, hasNext: false };
        const games = field(flight(await this.page('/games/ranking')), 'weekly');
        if (!Array.isArray(games)) throw fail();
        return { items: games.map(item), page: 1, hasNext: false };
      }
      if (key !== 'latest' || !['gal', 'tr'].includes(options.section || 'gal')) throw Park.error('CONFIG', '未知列表');
      return this.list(options.section || 'gal', page, options);
    },
    async search({ keyword, page = 1, filters = {} }) {
      return this.list('game-list-search-default', page, filters, String(keyword || '').trim());
    },
    async detail(id) {
      id = idOf(id);
      const html = await this.page('/game/' + id);
      if (/该内容需要登录后才可以访问|此游戏包含\s*NSFW\s*内容，请登录后查看/.test(Park.html.strip(html))) throw loginRequired();
      const g = field(flight(html), 'game');
      if (!g || g.uniqueId !== id || !Number.isInteger(g.id)) throw fail();
      this.gameIds.set(id, g.id);
      return { ...item(g), url: BASE + '/game/' + id,
        description: Park.html.strip(g.detail?.detailedDesc || g.shortDesc || ''),
        authors: (g.developers || []).map(d => d.name),
        tags: [{ namespace: 'tags', label: '标签', tags: (g.tags || []).map(t => ({ name: t.name, keyword: t.name })) }] };
    },
    async comments(value, req = {}) {
      const id = idOf(value), page = Number(req.cursor || req.page || 1), parentId = String(req.parentId || '');
      if (!Number.isInteger(page) || page < 1 || page > 100000 || !['default', 'newest'].includes(req.sort || 'default')) {
        throw Park.error('CONFIG', '分页参数无效');
      }
      let targetId;
      if (parentId) {
        const parts = parentId.split('/');
        if (parts.length !== 2 || parts[0] !== id || !/^[1-9][0-9]{0,14}$/.test(parts[1])) throw Park.error('CONFIG', '分页参数无效');
        targetId = Number(parts[1]);
        if (page > 1) return {items: [], page, hasNext: false};
      }
      // 每次重新检查详情权限，不能因上次缓存了 gameId 而越过本次登录要求。
      await this.detail(id);
      const gameId = this.gameIds.get(id), path = '/game/' + id;
      const actions = await this.serverActions(path, ['getGameComments']);
      const response = await this.http.post(BASE + path, {readOnly: true, body: JSON.stringify([gameId, 'newest', page, ...(targetId ? [targetId] : [])]), headers: {
        'Next-Action': actions.getGameComments, Accept: 'text/x-component', 'Content-Type': 'text/plain;charset=UTF-8'}});
      if ([401, 403].includes(response.status)) throw loginRequired();
      this.http.ensureOk(response);
      const line = /(?:^|\n)1:/.exec(response.body), data = line ? valueAt(response.body, line.index + line[0].length) : null;
      if (!data || !Array.isArray(data.comments) || typeof data.hasMore !== 'boolean' || data.page !== page ||
          !Number.isSafeInteger(data.totalRootComments) || data.totalRootComments < 0) throw fail();
      const items = commentItems(data.comments, gameId, id, targetId);
      const hasNext = !targetId && data.hasMore && data.comments.length > 0;
      // total 仅为这页根楼和回复数量；全局分页数量应取 totalRootComments。
      return {items, page, hasNext, cursor: hasNext ? String(page + 1) : undefined,
        total: targetId ? items.length : data.totalRootComments};
    },
    async resources(id) {
      id = idOf(id);
      if (!this.gameIds.has(id)) await this.detail(id);
      const data = await this.resourceJson('/api/game/resources', { params: { gameId: this.gameIds.get(id), status: 'approved' } });
      if (!Array.isArray(data?.data?.resources)) throw fail();
      return data.data.resources;
    },
    async resourceJson(path, options = {}) {
      const response = await this.http.request({url: BASE + path, ...options});
      if (response.status === 401 || response.status === 403) throw loginRequired();
      this.http.ensureOk(response);
      return response.json();
    },
    async gameResources(id) {
      return Promise.all((await this.resources(id)).map(async r => ({ id: String(r.id), title: r.name || '', version: r.version || '', size: r.size || '',
        platforms: r.platforms || [], languages: r.language || [], notes: r.remark || '', status: 'valid',
        testStatus: r.tested === 'tested' ? 'tested' : 'untested',
        channels: (await Promise.all((r.urls || []).map(async (u, i) => {
          const entry = channel(u, i, r.linkSizes?.[i]);
          if (!entry) return null;
          const parsed = new URL(u);
          entry.id = await Park.crypto.sha256Hex(parsed.origin + parsed.pathname);
          return entry;
        }))).filter(Boolean) })));
    },
    async resolveGameResource(id, resourceId, channelId) {
      const resource = (await this.resources(id)).find(r => String(r.id) === String(resourceId));
      if (!resource || !/^[a-f0-9]{64}$/.test(channelId)) throw fail();
      let index = -1;
      for (let i = 0; i < (resource.urls || []).length; i++) {
        const parsed = new URL(resource.urls[i]);
        if (await Park.crypto.sha256Hex(parsed.origin + parsed.pathname) === channelId) { index = i; break; }
      }
      if (index < 0) throw fail();
      const original = channel(resource.urls?.[index], index);
      if (!original) throw fail();
      const result = await this.resourceJson('/api/game/resource/' + encodeURIComponent(resourceId) + '/download', { method: 'POST' });
      const resolved = result?.data?.resource;
      if (!Array.isArray(resolved?.urls) || !resolved.urls.length) throw Park.error('LOGIN_REQUIRED', '无法获取游戏资源，请在原站检查权限');
      const identity = linkIdentity(resource.urls[index]);
      const matches = resolved.urls.filter(u => linkIdentity(u) === identity);
      if (!identity || matches.length !== 1) throw fail();
      const url = matches[0];
      const target = channel(url, index);
      if (!target || target.kind !== original.kind) throw fail();
      return { url, kind: target.kind, filename: original.kind === 'direct' ? original.label : '',
        extractionCode: resolved.code || resource.code || '', archivePassword: resolved.unzipCode || resource.unzipCode || 'galgamex.com' };
    },
  });
})();

// 更新订阅维度由本站插件声明，保留原有浏览入口。
Park.enableUpdateSubscriptions(Park.__pending, {"dimensions":[{"key":"search","label":"搜索关键词","hint":"输入作品、作者或话题关键词"}]});
