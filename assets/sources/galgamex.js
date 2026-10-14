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
    key: 'galgamex', name: 'GalgameX', version: '0.0.5', type: 'game', category: 'game', color: '#E984AE',
    description: '游戏目录、版本资源与直链和网盘渠道', homepage: BASE, language: 'chinese',
    domains: ['galgamex.net', 'imgs.galgamex.win', 'shared.fastly.steamstatic.com', 'cdn.akamai.steamstatic.com'],
    media: { mode: 'native', origin: BASE, domains: ['game.galgamex.com'] },
    network: { mode: 'native', vpnHint: true },
    linkPatterns: ['https?://(?:www\\.)?galgamex\\.net/game/([a-z0-9]{8})'], idPattern: '^([a-z0-9]{8})$', idExample: '9476825d',
    defaultFeed: 'ranking', feeds: [{ key: 'ranking', label: '本周热门' }, { key: 'latest', label: '资源更新' }],
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
    async init() { this.actionCache = null; this.gameIds = new Map(); },
    async filter() {
      await this.http.json(BASE + '/api/content-filter', { method: 'POST', json: { value: this.config.nsfw ? 'all' : 'sfw' } });
    },
    async page(path) { await this.filter(); return this.http.text(BASE + path); },
    async gamesAction(refresh = false) {
      if (!refresh && this.actionCache && Date.now() - this.actionCache.time < 900000) return this.actionCache.id;
      const html = await this.page('/games');
      const scripts = [...new Set([...html.matchAll(/<script[^>]+src="([^\"]+)"/g)].map(m => m[1]).filter(p => p.startsWith('/_next/static/chunks/')))];
      let found;
      for (let start = 0; start < scripts.length && !found; start += 4) {
        const texts = await Promise.all(scripts.slice(start, start + 4).map(p => this.http.text(BASE + p)));
        for (const text of texts) {
          const match = /createServerReference\)\("([0-9a-f]{40,42})",[^;]{0,250}?"getGames"\)/.exec(text);
          if (match) { found = match[1]; break; }
        }
      }
      if (!found) throw fail();
      this.actionCache = { id: found, time: Date.now() }; return found;
    },
    async list(args, retry = false) {
      await this.filter();
      const id = await this.gamesAction(retry);
      const response = await this.http.post(BASE + '/games', { body: JSON.stringify([args]), headers: {
        'Next-Action': id, Accept: 'text/x-component', 'Content-Type': 'text/plain;charset=UTF-8' } });
      if (response.status >= 400 && !retry) return this.list(args, true);
      this.http.ensureOk(response);
      const line = /(?:^|\n)1:/.exec(response.body);
      const value = line ? valueAt(response.body, line.index + line[0].length) : null;
      if (!value || !Array.isArray(value.games)) throw fail();
      return { items: value.games.map(item), page: args.pageIndex, total: value.total,
        hasNext: args.pageIndex * args.limit < value.total };
    },
    async feed(key, { page = 1 } = {}) {
      if (key === 'ranking') {
        if (page > 1) return { items: [], page, hasNext: false };
        const games = field(flight(await this.page('/games/ranking')), 'weekly');
        if (!Array.isArray(games)) throw fail();
        return { items: games.map(item), page: 1, hasNext: false };
      }
      return this.list({ limit: 24, pageIndex: page, sortBy: 'resource_updated', onlyWithResources: true });
    },
    async search({ keyword, page = 1 }) {
      return this.list({ limit: 24, keyword: String(keyword), pageIndex: page, sortBy: 'resource_updated', onlyWithResources: true });
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
