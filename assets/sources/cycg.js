/* 次元茶馆：列表只读，隐藏资源仅在用户点击时回复；提交结果不明不重发。 */
(function () {
  const BASE = 'https://www.cycg.xyz';
  const REPLY = '感谢分享，好人一生平安';
  const pending = new Map();
  const covers = new Map();
  const wait = Park.utils.rateLimiter(400);
  const text = Park.html.text;
  const parse = Park.html.parse;
  const idOf = value => {
    const id = String(value);
    if (!/^[1-9]\d{0,11}$/.test(id)) throw Park.error('CONFIG', '帖子编号无效');
    return id;
  };
  const threadUrl = id => BASE + '/forum.php?mod=viewthread&tid=' + idOf(id) + '&mobile=2';
  const sameSite = value => {
    const u = new URL(value, BASE + '/');
    if (u.origin !== BASE || u.username || u.password) throw Park.error('PARSE', '站点表单地址无效');
    return u;
  };
  const mobileUrl = value => {
    const u = sameSite(value);
    u.searchParams.set('mobile', '2');
    u.hash = '';
    return u;
  };
  const accountIdOf = doc => {
    for (const a of doc.querySelectorAll('header #usermsg a[href], .footer a[href]')) {
      try {
        const u = sameSite(a.getAttribute('href'));
        if (u.pathname === '/home.php' && u.searchParams.get('mod') === 'space' &&
            u.searchParams.get('mycenter') === '1' && /^[1-9]\d*$/.test(u.searchParams.get('uid') || '')) return u.searchParams.get('uid');
      } catch (_) {}
    }
    return '';
  };
  const loggedIn = doc => !!accountIdOf(doc);
  const bodyOf = doc => doc.querySelector('.postlist .plc')?.querySelector('.message');
  const titleOf = doc => {
    const title = doc.querySelector('.postlist > h2')?.cloneNode(true);
    title?.querySelectorAll('a').forEach(a => a.remove());
    return text(title);
  };
  const gameForum = value => {
    try {
      const u = sameSite(value);
      return /^\/forum-2-\d+\.html$/.test(u.pathname) || u.pathname === '/forum.php' &&
        u.searchParams.get('fid') === '2' && (u.searchParams.get('mod') === 'forumdisplay' ||
          u.searchParams.get('mod') === 'post' && u.searchParams.get('action') === 'reply');
    } catch (_) { return false; }
  };
  const nonGameText = value => /(?:\[|【|^|（|\()\s*(?:AI\s*)?(?:漫画|插画|图集|画集|小说|轻小说|壁纸|写真|摄影|COS|MMD|动画)(?:\]|】|）|\)|\s|$)/i.test(String(value || ''));
  const gameText = value => /\b(?:RPG|SLG|ADV|ACT|ARPG|AVG|STG|VN|GALGAME|PC)\b|游戏|汉化|官中|新游|Steam|Windows|安卓版|游戏资源/i.test(String(value || ''));
  const checkGame = doc => {
    const title = titleOf(doc), body = bodyOf(doc), content = title + ' ' + text(body);
    if (nonGameText(title) || nonGameText(text(body)) || (!Array.from(doc.querySelectorAll('header a[href], .postlist a[href], .postlist input[href]')).some(a => gameForum(a.getAttribute('href'))) && !gameText(content))) throw Park.error('NOT_FOUND', '该帖子不属于游戏资源区');
  };
  const coverOf = node => {
    for (const img of node?.querySelectorAll('img') || []) {
      const raw = img.getAttribute('file') || img.getAttribute('zoomfile') || img.getAttribute('data-src') || img.getAttribute('src');
      try { const u = sameSite(raw || ''); if (/^\/data\/attachment\//.test(u.pathname)) return u.href; } catch (_) {}
    }
    return '';
  };
  const rowsOf = doc => {
    const rows = [], seen = new Set();
    for (const row of doc.querySelectorAll('.threadlist li, #threadlist li.pbw')) {
      const anchors = Array.from(row.querySelectorAll('h3 a[href], a[href]'));
      for (const a of anchors) {
        let id;
        try {
          const u = sameSite(a.getAttribute('href'));
          id = /^\/thread-([1-9]\d*)-\d+-\d+\.html$/.exec(u.pathname)?.[1] ||
            (u.pathname === '/forum.php' && u.searchParams.get('mod') === 'viewthread' ? u.searchParams.get('tid') : '');
          if (!id) continue;
          id = idOf(id);
        } catch (_) { continue; }
        const titleNode = a.cloneNode(true);
        titleNode.querySelectorAll('.by, .num, .icon, img').forEach(n => n.remove());
        const title = text(titleNode);
        const summary = text(Array.from(row.querySelectorAll('p')).find(p => !p.classList.contains('xg1')) || row.querySelector('.by'));
        if (nonGameText(title) || !gameText(title + ' ' + summary) || seen.has(id)) continue;
        seen.add(id);
        rows.push({id, title, cover: coverOf(row), subtitle: summary || text(row.querySelector('.by'))});
        break;
      }
    }
    return rows;
  };
  const replyUrlOf = (value, id) => {
    const u = mobileUrl(value);
    const allowed = ['mod', 'action', 'fid', 'tid', 'replysubmit', 'mobile'];
    if (u.pathname !== '/forum.php' || u.searchParams.get('mod') !== 'post' || u.searchParams.get('action') !== 'reply' ||
        u.searchParams.get('tid') !== id || !/^[1-9]\d*$/.test(u.searchParams.get('fid') || '') ||
        Array.from(u.searchParams.keys()).some(k => !allowed.includes(k)) ||
        Array.from(u.searchParams.keys()).some(k => u.searchParams.getAll(k).length !== 1)) throw Park.error('PARSE', '站点表单地址无效');
    return u;
  };
  const cursorUrl = (value, search = false, firstPage = false) => {
    const u = mobileUrl(value);
    if (firstPage && !u.searchParams.has('page')) u.searchParams.set('page', '1');
    const allowed = search ? ['mod', 'searchid', 'orderby', 'ascdesc', 'page', 'mobile', 'searchsubmit'] :
      ['mod', 'view', 'fid', 'page', 'mobile', 'filter', 'orderby'];
    const valid = search ? u.pathname === '/search.php' && u.searchParams.get('mod') === 'forum' && /^\d+$/.test(u.searchParams.get('searchid') || '') :
      u.pathname === '/forum.php' && (u.searchParams.get('mod') === 'guide' && ['hot', 'digest', 'new', 'newthread', 'sofa'].includes(u.searchParams.get('view')) ||
        u.searchParams.get('mod') === 'forumdisplay' && u.searchParams.get('fid') === '2');
    if (!valid || !/^[1-9]\d*$/.test(u.searchParams.get('page') || '') ||
        Array.from(u.searchParams.keys()).some(k => !allowed.includes(k)) ||
        Array.from(u.searchParams.keys()).some(k => u.searchParams.getAll(k).length !== 1)) throw Park.error('CONFIG', search ? '搜索分页无效' : '游戏列表无法读取');
    return u;
  };
  const nextOf = (doc, current, search = false) => {
    const href = doc.querySelector('.pg .nxt, .pg a[rel="next"]')?.getAttribute('href');
    if (!href) return null;
    const next = cursorUrl(href, search);
    if (Number(next.searchParams.get('page')) <= current) throw Park.error('PARSE', '搜索分页无效');
    return next.href;
  };
  const hidden = body => Array.from(body?.querySelectorAll('.locked') || []).some(node =>
    /隐藏内容/.test(text(node)) && !!node.querySelector('a[href*="action=reply"]'));
  const codeIn = value => /(?:提取码|提取碼|访问码|訪問碼)\s*[:：=]?\s*([a-z0-9]{4})(?![a-z0-9])/i.exec(value)?.[1] || '';
  const archiveIn = body => /(?:解压密码|解壓密碼|解压码)\s*(?:为|為|是|[:：=])?\s*([^\s，。；]+)/.exec(Park.html.paragraphs(body).join('\n'))?.[1] || '';
  const providerOf = u => ({
    'pan.baidu.com': '百度网盘', 'pan.quark.cn': '夸克网盘', 'drive.uc.cn': 'UC网盘',
    'pan.xunlei.com': '迅雷云盘', 'pan.cycg.xyz': 'OneDrive', '1drv.ms': 'OneDrive',
    'onedrive.live.com': 'OneDrive', 'drive.google.com': 'Google Drive', 'mega.nz': 'MEGA',
    '115.com': '115网盘', 'cloud.189.cn': '天翼云盘', 'www.123pan.com': '123云盘', 'www.123865.com': '123云盘',
  })[u.hostname] || (/^(?:[a-z0-9-]+\.)?lanzou[a-z]*\.com$/i.test(u.hostname) ? '蓝奏云' : '');

  async function shares(body) {
    const links = [], seen = new Set();
    for (const a of body?.querySelectorAll('a[href]') || []) {
      let u;
      try { u = new URL(a.getAttribute('href'), BASE + '/'); } catch (_) { continue; }
      const label = providerOf(u);
      if (!label || !['https:', 'http:'].includes(u.protocol) || u.username || u.password || seen.has(u.href)) continue;
      seen.add(u.href);
      // Restrict a code to the text after this link, before the next link/block.
      let vicinity = '';
      for (let n = a.nextSibling; n; n = n.nextSibling) {
        if (n.nodeType === 1 && (n.querySelector?.('a[href]') || n.tagName === 'A')) break;
        vicinity += n.textContent || '';
        if (n.tagName === 'BR') vicinity += '\n';
        if (codeIn(vicinity)) break;
      }
      if (!codeIn(vicinity)) {
        for (let container = a.parentNode, depth = 0; container && container !== body && depth < 3; container = container.parentNode, depth++) {
          if (container.querySelectorAll('a[href]').length !== 1) break;
          const value = text(container);
          if (codeIn(value)) { vicinity = value; break; }
        }
      }
      const code = u.searchParams.get('pwd') || codeIn(vicinity);
      const identity = new URL(u.href);
      identity.searchParams.delete('pwd'); identity.hash = '';
      const id = (await Park.crypto.sha256Hex(identity.href)).slice(0, 24);
      const previous = links.find(l => l.id === id);
      if (previous) {
        if (code && previous.code && code !== previous.code) throw Park.error('PARSE', '网盘提取码不一致，请检查原帖');
        if (code) previous.code = code;
      } else links.push({id, label, url: u.href, code});
    }
    return links;
  }

  function item(doc, id, title) {
    return {id, title: titleOf(doc) || title || id, cover: coverOf(bodyOf(doc)), coverAspect: 16 / 9,
      mediaKind: 'game', contentDomain: 'game', contentRating: 'unknown', coverRating: 'unknown'};
  }

  Park.register({
    i18n: {
      "zh-Hant": {"115网盘": "115網盤", "123云盘": "123雲盤", "UC网盘": "UC網盤", "回复结果待确认，请在原帖检查，应用不会重复发送": "回覆結果待確認，請在原帖檢查，應用不會重複發送", "在打开的网页中登录，看到账号或退出按钮后点击完成；若已是正常资源页，无需寻找人机验证。点击回复解锁会发送“感谢分享，好人一生平安”": "在開啟的網頁中登入，看到帳號或登出按鈕後點擊完成；若已是正常資源頁，無需尋找人機驗證。點擊回覆解鎖會傳送「感謝分享，好人一生平安」", "天翼云盘": "天翼雲盤", "夸克网盘": "夸克網盤", "帖子分享": "帖子分享", "帖子未提供可读取的网盘链接": "無法讀取遊戲帖子或表單，請檢查原站後重試。", "帖子编号无效": "無法讀取遊戲帖子或表單，請檢查原站後重試。", "搜索分页无效": "無法讀取遊戲帖子或表單，請檢查原站後重試。", "搜索结果无法读取": "無法讀取遊戲帖子或表單，請檢查原站後重試。", "搜索表单无法读取": "無法讀取遊戲帖子或表單，請檢查原站後重試。", "次元茶馆": "次元茶館", "次元茶馆账号": "次元茶館帳號", "游戏列表无法读取": "無法讀取遊戲帖子或表單，請檢查原站後重試。", "游戏帖子首楼无法读取": "無法讀取遊戲帖子或表單，請檢查原站後重試。", "社区游戏分享，登录后按需回复解锁网盘资源": "社群遊戲分享，登入後按需回覆解鎖網盤資源", "站点表单地址无效": "無法讀取遊戲帖子或表單，請檢查原站後重試。", "网盘提取码不一致，请检查原帖": "無法讀取遊戲帖子或表單，請檢查原站後重試。", "若已看到正常页面，请点击完成；如资源仍被隐藏，请在原帖或回复页完成验证与回复，再返回重试": "若已看到正常頁面，請點擊完成；如資源仍被隱藏，請在原帖或回覆頁完成驗證與回覆，再返回重試", "蓝奏云": "藍奏雲", "该帖子不属于游戏资源区": "無法讀取遊戲帖子或表單，請檢查原站後重試。", "请在回复页完成验证并手动回复，返回后重试读取资源": "請在回覆頁完成驗證並手動回覆，返回後重試讀取資源", "请在应用内登录次元茶馆": "請在應用內登入次元茶館", "请在站点页面完成搜索验证后重试": "請在站點頁面完成搜尋驗證後重試", "资源权限已改变，请刷新资源列表": "無法讀取遊戲帖子或表單，請檢查原站後重試。", "资源编号无效": "無法讀取遊戲帖子或表單，請檢查原站後重試。", "迅雷云盘": "迅雷雲盤"},
      "ja": {"115网盘": "115 Drive", "123云盘": "123 Cloud", "UC网盘": "UC Drive", "回复结果待确认，请在原帖检查，应用不会重复发送": "返信結果を元の投稿で確認してください。アプリは再送信しません。", "在打开的网页中登录，看到账号或退出按钮后点击完成；若已是正常资源页，无需寻找人机验证。点击回复解锁会发送“感谢分享，好人一生平安”": "開いたページでログインし、アカウントかログアウトボタンが表示されたら「完了」を押してください。通常のリソースページなら追加の認証は不要です。返信で解除すると「感谢分享，好人一生平安」を送信します。", "天翼云盘": "Tianyi Cloud", "夸克网盘": "Quark Drive", "帖子分享": "投稿の共有リンク", "帖子未提供可读取的网盘链接": "ゲーム投稿またはフォームを読み取れません。元のページを確認して再試行してください。", "帖子编号无效": "ゲーム投稿またはフォームを読み取れません。元のページを確認して再試行してください。", "搜索分页无效": "ゲーム投稿またはフォームを読み取れません。元のページを確認して再試行してください。", "搜索结果无法读取": "ゲーム投稿またはフォームを読み取れません。元のページを確認して再試行してください。", "搜索表单无法读取": "ゲーム投稿またはフォームを読み取れません。元のページを確認して再試行してください。", "次元茶馆": "次元茶館", "次元茶馆账号": "次元茶館アカウント", "游戏列表无法读取": "ゲーム投稿またはフォームを読み取れません。元のページを確認して再試行してください。", "游戏帖子首楼无法读取": "ゲーム投稿またはフォームを読み取れません。元のページを確認して再試行してください。", "社区游戏分享，登录后按需回复解锁网盘资源": "コミュニティのゲーム共有。ログイン後、返信でクラウドリンクを取得", "站点表单地址无效": "ゲーム投稿またはフォームを読み取れません。元のページを確認して再試行してください。", "网盘提取码不一致，请检查原帖": "ゲーム投稿またはフォームを読み取れません。元のページを確認して再試行してください。", "若已看到正常页面，请点击完成；如资源仍被隐藏，请在原帖或回复页完成验证与回复，再返回重试": "通常のページが表示されたら「完了」を押してください。リソースが非表示なら、元の投稿または返信ページで認証と返信を済ませて再試行してください", "蓝奏云": "Lanzou Cloud", "该帖子不属于游戏资源区": "ゲーム投稿またはフォームを読み取れません。元のページを確認して再試行してください。", "请在回复页完成验证并手动回复，返回后重试读取资源": "返信ページで認証と手動返信を済ませ、戻ってリソースの読み込みを再試行してください", "请在应用内登录次元茶馆": "アプリ内で次元茶館にログインしてください", "请在站点页面完成搜索验证后重试": "サイトで検索認証を完了して再試行してください", "资源权限已改变，请刷新资源列表": "ゲーム投稿またはフォームを読み取れません。元のページを確認して再試行してください。", "资源编号无效": "ゲーム投稿またはフォームを読み取れません。元のページを確認して再試行してください。", "迅雷云盘": "Xunlei Drive"},
      "ko": {"115网盘": "115 Drive", "123云盘": "123 Cloud", "UC网盘": "UC Drive", "回复结果待确认，请在原帖检查，应用不会重复发送": "댓글 결과가 불확실합니다. 원문을 확인하세요. 앱은 다시 보내지 않습니다.", "在打开的网页中登录，看到账号或退出按钮后点击完成；若已是正常资源页，无需寻找人机验证。点击回复解锁会发送“感谢分享，好人一生平安”": "열린 웹페이지에서 로그인하고 계정 또는 로그아웃 버튼이 보이면 완료를 누르세요. 정상 자료 페이지에서는 별도 인증을 찾을 필요가 없습니다. 답글 잠금 해제는 “感谢分享，好人一生平安”을 전송합니다.", "天翼云盘": "Tianyi Cloud", "夸克网盘": "Quark Drive", "帖子分享": "게시물 공유", "帖子未提供可读取的网盘链接": "게임 게시물 또는 양식을 읽을 수 없습니다. 원문을 확인하고 재시도하세요.", "帖子编号无效": "게임 게시물 또는 양식을 읽을 수 없습니다. 원문을 확인하고 재시도하세요.", "搜索分页无效": "게임 게시물 또는 양식을 읽을 수 없습니다. 원문을 확인하고 재시도하세요.", "搜索结果无法读取": "게임 게시물 또는 양식을 읽을 수 없습니다. 원문을 확인하고 재시도하세요.", "搜索表单无法读取": "게임 게시물 또는 양식을 읽을 수 없습니다. 원문을 확인하고 재시도하세요.", "次元茶馆": "차원 찻집", "次元茶馆账号": "차원 찻집 계정", "游戏列表无法读取": "게임 게시물 또는 양식을 읽을 수 없습니다. 원문을 확인하고 재시도하세요.", "游戏帖子首楼无法读取": "게임 게시물 또는 양식을 읽을 수 없습니다. 원문을 확인하고 재시도하세요.", "社区游戏分享，登录后按需回复解锁网盘资源": "커뮤니티 게임 공유. 로그인 후 댓글로 클라우드 링크 해제", "站点表单地址无效": "게임 게시물 또는 양식을 읽을 수 없습니다. 원문을 확인하고 재시도하세요.", "网盘提取码不一致，请检查原帖": "게임 게시물 또는 양식을 읽을 수 없습니다. 원문을 확인하고 재시도하세요.", "若已看到正常页面，请点击完成；如资源仍被隐藏，请在原帖或回复页完成验证与回复，再返回重试": "정상 페이지가 보이면 완료를 누르세요. 자료가 숨겨져 있으면 원글 또는 답글 페이지에서 인증과 답글을 완료한 후 다시 시도하세요", "蓝奏云": "Lanzou Cloud", "该帖子不属于游戏资源区": "게임 게시물 또는 양식을 읽을 수 없습니다. 원문을 확인하고 재시도하세요.", "请在回复页完成验证并手动回复，返回后重试读取资源": "답글 페이지에서 인증과 직접 답글 작성을 완료한 후 돌아와 자료를 다시 불러오세요", "请在应用内登录次元茶馆": "앱에서 차원 찻집에 로그인하세요", "请在站点页面完成搜索验证后重试": "사이트에서 검색 인증을 완료하고 재시도하세요", "资源权限已改变，请刷新资源列表": "게임 게시물 또는 양식을 읽을 수 없습니다. 원문을 확인하고 재시도하세요.", "资源编号无效": "게임 게시물 또는 양식을 읽을 수 없습니다. 원문을 확인하고 재시도하세요.", "迅雷云盘": "Xunlei Drive"},
      "en": {"115网盘": "115 Drive", "123云盘": "123 Cloud", "UC网盘": "UC Drive", "回复结果待确认，请在原帖检查，应用不会重复发送": "Reply status is uncertain. Check the original post; the app will not send it again.", "在打开的网页中登录，看到账号或退出按钮后点击完成；若已是正常资源页，无需寻找人机验证。点击回复解锁会发送“感谢分享，好人一生平安”": "Sign in on the opened page and tap Done when your account or a logout button appears. A normal resource page needs no extra challenge. Reply to unlock sends “感谢分享，好人一生平安”.", "天翼云盘": "Tianyi Cloud", "夸克网盘": "Quark Drive", "帖子分享": "Post shares", "帖子未提供可读取的网盘链接": "Unable to read the game post or form. Check the original page and retry.", "帖子编号无效": "Unable to read the game post or form. Check the original page and retry.", "搜索分页无效": "Unable to read the game post or form. Check the original page and retry.", "搜索结果无法读取": "Unable to read the game post or form. Check the original page and retry.", "搜索表单无法读取": "Unable to read the game post or form. Check the original page and retry.", "次元茶馆": "Dimension Tea House", "次元茶馆账号": "Tea House account", "游戏列表无法读取": "Unable to read the game post or form. Check the original page and retry.", "游戏帖子首楼无法读取": "Unable to read the game post or form. Check the original page and retry.", "社区游戏分享，登录后按需回复解锁网盘资源": "Community games; sign in to unlock cloud links with a reply", "站点表单地址无效": "Unable to read the game post or form. Check the original page and retry.", "网盘提取码不一致，请检查原帖": "Unable to read the game post or form. Check the original page and retry.", "若已看到正常页面，请点击完成；如资源仍被隐藏，请在原帖或回复页完成验证与回复，再返回重试": "If the normal page is visible, tap Done. If resources are still hidden, complete verification and reply in the original thread or reply page, then retry", "蓝奏云": "Lanzou Cloud", "该帖子不属于游戏资源区": "Unable to read the game post or form. Check the original page and retry.", "请在回复页完成验证并手动回复，返回后重试读取资源": "Complete verification and reply manually on the reply page, then return and retry loading resources", "请在应用内登录次元茶馆": "Sign in to Tea House inside the app", "请在站点页面完成搜索验证后重试": "Complete search verification on the site and retry", "资源权限已改变，请刷新资源列表": "Unable to read the game post or form. Check the original page and retry.", "资源编号无效": "Unable to read the game post or form. Check the original page and retry.", "迅雷云盘": "Xunlei Drive"},
      "es": {"115网盘": "115 Drive", "123云盘": "123 Cloud", "UC网盘": "UC Drive", "回复结果待确认，请在原帖检查，应用不会重复发送": "El resultado es incierto. Revisa el post original; la app no volverá a enviarlo.", "在打开的网页中登录，看到账号或退出按钮后点击完成；若已是正常资源页，无需寻找人机验证。点击回复解锁会发送“感谢分享，好人一生平安”": "Inicia sesión y pulsa Listo cuando aparezca tu cuenta o el botón de salir. Una página normal de recursos no requiere otra verificación. Desbloquear mediante respuesta envía “感谢分享，好人一生平安”.", "天翼云盘": "Tianyi Cloud", "夸克网盘": "Quark Drive", "帖子分享": "Enlaces del post", "帖子未提供可读取的网盘链接": "No se puede leer el post o formulario. Revisa la página original y reintenta.", "帖子编号无效": "No se puede leer el post o formulario. Revisa la página original y reintenta.", "搜索分页无效": "No se puede leer el post o formulario. Revisa la página original y reintenta.", "搜索结果无法读取": "No se puede leer el post o formulario. Revisa la página original y reintenta.", "搜索表单无法读取": "No se puede leer el post o formulario. Revisa la página original y reintenta.", "次元茶馆": "Salón de té dimensional", "次元茶馆账号": "Cuenta del salón de té", "游戏列表无法读取": "No se puede leer el post o formulario. Revisa la página original y reintenta.", "游戏帖子首楼无法读取": "No se puede leer el post o formulario. Revisa la página original y reintenta.", "社区游戏分享，登录后按需回复解锁网盘资源": "Juegos de la comunidad; inicia sesión y responde para desbloquear enlaces", "站点表单地址无效": "No se puede leer el post o formulario. Revisa la página original y reintenta.", "网盘提取码不一致，请检查原帖": "No se puede leer el post o formulario. Revisa la página original y reintenta.", "若已看到正常页面，请点击完成；如资源仍被隐藏，请在原帖或回复页完成验证与回复，再返回重试": "Si ves la página normal, pulsa Listo. Si los recursos siguen ocultos, completa la verificación y responde en el hilo o página de respuesta; luego reinténtalo", "蓝奏云": "Lanzou Cloud", "该帖子不属于游戏资源区": "No se puede leer el post o formulario. Revisa la página original y reintenta.", "请在回复页完成验证并手动回复，返回后重试读取资源": "Completa la verificación y responde manualmente en la página de respuesta; vuelve y carga los recursos de nuevo", "请在应用内登录次元茶馆": "Inicia sesión en el salón de té desde la app", "请在站点页面完成搜索验证后重试": "Completa la verificación de búsqueda en el sitio y reintenta", "资源权限已改变，请刷新资源列表": "No se puede leer el post o formulario. Revisa la página original y reintenta.", "资源编号无效": "No se puede leer el post o formulario. Revisa la página original y reintenta.", "迅雷云盘": "Xunlei Drive"},
      "ru": {"115网盘": "115 Drive", "123云盘": "123 Cloud", "UC网盘": "UC Drive", "回复结果待确认，请在原帖检查，应用不会重复发送": "Результат ответа неизвестен. Проверьте публикацию; приложение не отправит ответ повторно.", "在打开的网页中登录，看到账号或退出按钮后点击完成；若已是正常资源页，无需寻找人机验证。点击回复解锁会发送“感谢分享，好人一生平安”": "Войдите на открытой странице и нажмите «Готово», когда появится аккаунт или кнопка выхода. На обычной странице ресурсов дополнительная проверка не нужна. Разблокировка ответом отправляет «感谢分享，好人一生平安».", "天翼云盘": "Tianyi Cloud", "夸克网盘": "Quark Drive", "帖子分享": "Ссылки публикации", "帖子未提供可读取的网盘链接": "Не удалось прочитать публикацию или форму. Проверьте исходную страницу и повторите.", "帖子编号无效": "Не удалось прочитать публикацию или форму. Проверьте исходную страницу и повторите.", "搜索分页无效": "Не удалось прочитать публикацию или форму. Проверьте исходную страницу и повторите.", "搜索结果无法读取": "Не удалось прочитать публикацию или форму. Проверьте исходную страницу и повторите.", "搜索表单无法读取": "Не удалось прочитать публикацию или форму. Проверьте исходную страницу и повторите.", "次元茶馆": "Чайная измерений", "次元茶馆账号": "Аккаунт чайной", "游戏列表无法读取": "Не удалось прочитать публикацию или форму. Проверьте исходную страницу и повторите.", "游戏帖子首楼无法读取": "Не удалось прочитать публикацию или форму. Проверьте исходную страницу и повторите.", "社区游戏分享，登录后按需回复解锁网盘资源": "Игры сообщества: войдите и ответьте для доступа к облачным ссылкам", "站点表单地址无效": "Не удалось прочитать публикацию или форму. Проверьте исходную страницу и повторите.", "网盘提取码不一致，请检查原帖": "Не удалось прочитать публикацию или форму. Проверьте исходную страницу и повторите.", "若已看到正常页面，请点击完成；如资源仍被隐藏，请在原帖或回复页完成验证与回复，再返回重试": "Если видна обычная страница, нажмите «Готово». Если ресурсы скрыты, пройдите проверку и ответьте в исходной теме или на странице ответа, затем повторите попытку", "蓝奏云": "Lanzou Cloud", "该帖子不属于游戏资源区": "Не удалось прочитать публикацию или форму. Проверьте исходную страницу и повторите.", "请在回复页完成验证并手动回复，返回后重试读取资源": "Пройдите проверку и ответьте вручную на странице ответа, затем вернитесь и повторите загрузку ресурсов", "请在应用内登录次元茶馆": "Войдите в чайную через приложение", "请在站点页面完成搜索验证后重试": "Пройдите проверку поиска на сайте и повторите", "资源权限已改变，请刷新资源列表": "Не удалось прочитать публикацию или форму. Проверьте исходную страницу и повторите.", "资源编号无效": "Не удалось прочитать публикацию или форму. Проверьте исходную страницу и повторите.", "迅雷云盘": "Xunlei Drive"},
      "ar": {"115网盘": "115 Drive", "123云盘": "123 Cloud", "UC网盘": "UC Drive", "回复结果待确认，请在原帖检查，应用不会重复发送": "نتيجة الرد غير مؤكدة. راجع المنشور الأصلي؛ لن يرسل التطبيق الرد مرة أخرى.", "在打开的网页中登录，看到账号或退出按钮后点击完成；若已是正常资源页，无需寻找人机验证。点击回复解锁会发送“感谢分享，好人一生平安”": "سجّل الدخول في الصفحة المفتوحة واضغط تم عند ظهور الحساب أو زر الخروج. صفحة الموارد العادية لا تحتاج إلى تحقق إضافي. الرد لفتح الموارد يرسل “感谢分享，好人一生平安”.", "天翼云盘": "Tianyi Cloud", "夸克网盘": "Quark Drive", "帖子分享": "روابط المنشور", "帖子未提供可读取的网盘链接": "تعذر قراءة منشور اللعبة أو النموذج. تحقق من الصفحة الأصلية وأعد المحاولة.", "帖子编号无效": "تعذر قراءة منشور اللعبة أو النموذج. تحقق من الصفحة الأصلية وأعد المحاولة.", "搜索分页无效": "تعذر قراءة منشور اللعبة أو النموذج. تحقق من الصفحة الأصلية وأعد المحاولة.", "搜索结果无法读取": "تعذر قراءة منشور اللعبة أو النموذج. تحقق من الصفحة الأصلية وأعد المحاولة.", "搜索表单无法读取": "تعذر قراءة منشور اللعبة أو النموذج. تحقق من الصفحة الأصلية وأعد المحاولة.", "次元茶馆": "مقهى الأبعاد", "次元茶馆账号": "حساب المقهى", "游戏列表无法读取": "تعذر قراءة منشور اللعبة أو النموذج. تحقق من الصفحة الأصلية وأعد المحاولة.", "游戏帖子首楼无法读取": "تعذر قراءة منشور اللعبة أو النموذج. تحقق من الصفحة الأصلية وأعد المحاولة.", "社区游戏分享，登录后按需回复解锁网盘资源": "ألعاب المجتمع؛ سجّل الدخول ورد لفتح الروابط السحابية", "站点表单地址无效": "تعذر قراءة منشور اللعبة أو النموذج. تحقق من الصفحة الأصلية وأعد المحاولة.", "网盘提取码不一致，请检查原帖": "تعذر قراءة منشور اللعبة أو النموذج. تحقق من الصفحة الأصلية وأعد المحاولة.", "若已看到正常页面，请点击完成；如资源仍被隐藏，请在原帖或回复页完成验证与回复，再返回重试": "إذا ظهرت الصفحة العادية، اضغط تم. إذا بقيت الموارد مخفية، أكمل التحقق والرد في الموضوع الأصلي أو صفحة الرد ثم أعد المحاولة", "蓝奏云": "Lanzou Cloud", "该帖子不属于游戏资源区": "تعذر قراءة منشور اللعبة أو النموذج. تحقق من الصفحة الأصلية وأعد المحاولة.", "请在回复页完成验证并手动回复，返回后重试读取资源": "أكمل التحقق وأرسل الرد يدوياً في صفحة الرد، ثم عد وأعد تحميل الموارد", "请在应用内登录次元茶馆": "سجّل الدخول إلى المقهى داخل التطبيق", "请在站点页面完成搜索验证后重试": "أكمل التحقق من البحث في الموقع وأعد المحاولة", "资源权限已改变，请刷新资源列表": "تعذر قراءة منشور اللعبة أو النموذج. تحقق من الصفحة الأصلية وأعد المحاولة.", "资源编号无效": "تعذر قراءة منشور اللعبة أو النموذج. تحقق من الصفحة الأصلية وأعد المحاولة.", "迅雷云盘": "Xunlei Drive"},
    },
    key: 'cycg', name: '次元茶馆', version: '0.0.11', minAppVersion: '0.9.2', type: 'game', category: 'game', language: 'zh', color: '#BD916B',
    homepage: BASE, domains: ['cycg.xyz'], icon: BASE + '/favicon.ico',
    description: '社区游戏分享，登录后按需回复解锁网盘资源',
    network: {mode: 'browser', origin: BASE, vpnHint: true},
    imageHeaders: {Referer: BASE + '/'},
    imageNetwork: {mode: 'browser', origin: BASE, domains: ['cycg.xyz']},
    linkPatterns: ['https?://(?:www\\.)?cycg\\.xyz/thread-(\\d+)-', 'https?://(?:www\\.)?cycg\\.xyz/forum\\.php\\?mod=viewthread&tid=(\\d+)'],
    idPattern: '^(\\d+)$', idExample: '20602',
    defaultFeed: 'recommended', feeds: [{key: 'recommended', label: '推荐'}, {key: 'popular', label: '热门'}, {key: 'latest', label: '最新'}],
    account: {
      type: 'cookies', title: '次元茶馆账号', required: true,
      hint: '在打开的网页中登录，看到账号或退出按钮后点击完成；若已是正常资源页，无需寻找人机验证。点击回复解锁会发送“感谢分享，好人一生平安”',
      loginUrl: BASE + '/member.php?mod=logging&action=login&mobile=2', cookieUrl: BASE + '/', requiredCookies: [],
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
          if (/^[A-Za-z0-9_-]{1,100}$/.test(key) && typeof value === 'string' && !/[\r\n;]/.test(value)) safe[key] = value;
        }
        if (!Object.keys(safe).length) throw Park.error('LOGIN_REQUIRED', '请在应用内登录次元茶馆');
        await this.cookies.set(BASE + '/', safe);
        const doc = await this.page(BASE + '/');
        if (!loggedIn(doc)) throw Park.error('LOGIN_REQUIRED', '请在应用内登录次元茶馆');
        return {name: '次元茶馆账号'};
      },
      async logout() { await this.cookies.clear(BASE + '/'); },
      async status() {
        const doc = await this.page(BASE + '/', undefined, false);
        return {loggedIn: loggedIn(doc), name: loggedIn(doc) ? '次元茶馆账号' : ''};
      },
    },
    async page(url, options, requireAccount = true) {
      await wait();
      const doc = parse(await this.http.text(mobileUrl(url).href, options));
      if (requireAccount && !loggedIn(doc)) throw Park.error('LOGIN_REQUIRED', '请在应用内登录次元茶馆');
      if (!bodyOf(doc) && /抱歉.*(?:不存在|删除)/.test(text(doc))) throw Park.error('NOT_FOUND', '内容不存在');
      return doc;
    },
    async hydrate(rows) {
      const output = [];
      for (const row of rows) {
        let cached = row.cover ? {at: Date.now(), cover: row.cover} : covers.get(row.id);
        if (!cached || Date.now() - cached.at > 600000) {
          const doc = await this.page(threadUrl(row.id));
          const metadata = item(doc, row.id, row.title);
          cached = {at: Date.now(), cover: metadata.cover};
          if (covers.size >= 100) covers.delete(covers.keys().next().value);
          covers.set(row.id, cached);
        }
        output.push({id: row.id, title: row.title, mediaKind: 'game', contentDomain: 'game', contentRating: 'unknown', coverRating: 'unknown', coverAspect: 16 / 9, ...row, cover: cached.cover});
      }
      return output;
    },
    async feed(key, {page = 1, cursor} = {}) {
      page = Math.max(1, Number(page) || 1);
      let url;
      if (cursor) url = cursorUrl(cursor).href;
      else if (key === 'recommended') {
        if (page > 1) throw Park.error('CONFIG', '游戏列表无法读取');
        url = BASE + '/';
      } else url = BASE + '/forum.php?mod=forumdisplay&fid=2&page=' + page + (key === 'latest' ? '&orderby=dateline' : '&filter=heat&orderby=heats');
      const doc = await this.page(url);
      if (!doc.querySelector('.threadlist, #threadlist')) throw Park.error('PARSE', '游戏列表无法读取');
      const next = nextOf(doc, Number(new URL(url).searchParams.get('page')) || page);
      return {items: await this.hydrate(rowsOf(doc)), page, hasNext: !!next, cursor: next};
    },
    async search({keyword, page = 1, cursor}) {
      if (!String(keyword || '').trim()) return this.feed('recommended', {page, cursor});
      let doc;
      if (cursor) {
        const u = cursorUrl(cursor, true);
        doc = await this.page(u.href);
      } else {
        if (Number(page) > 1) throw Park.error('CONFIG', '搜索分页无效');
        const landing = await this.page(BASE + '/search.php?mod=forum');
        const form = landing.querySelector('#searchform');
        if (!form) {
          if (!loggedIn(landing)) throw Park.error('LOGIN_REQUIRED', '请在应用内登录次元茶馆');
          throw Park.error('PARSE', '搜索表单无法读取');
        }
        const hash = form.querySelector('[name="formhash"]')?.getAttribute('value');
        if (!hash) throw Park.error('LOGIN_REQUIRED', '请在应用内登录次元茶馆');
        const action = mobileUrl(form.getAttribute('action'));
        if (action.pathname !== '/search.php' || action.searchParams.get('mod') !== 'forum') throw Park.error('PARSE', '站点表单地址无效');
        doc = await this.page(action.href, {method: 'POST', form: {
          formhash: hash, srchtxt: String(keyword).trim(), srchfilter: 'all', searchsubmit: 'yes', orderby: 'lastpost', ascdesc: 'desc',
        }});
        const redirect = doc.querySelector('#messagetext a[href*="searchid="]')?.getAttribute('href');
        if (redirect) {
          const target = cursorUrl(redirect, true, true);
          doc = await this.page(target.href);
        }
      }
      if (doc.querySelector('[name^="secqa"],[name^="seccode"]') || /验证问答|验证码/.test(text(doc.querySelector('#messagetext')))) {
        throw Park.error('CONFIRM_REQUIRED', '请在站点页面完成搜索验证后重试', {url: BASE + '/search.php?mod=forum&mobile=2&srchtxt=' + encodeURIComponent(String(keyword)) + '&searchsubmit=yes'});
      }
      if (!doc.querySelector('.threadlist, #threadlist')) {
        if (/登录/.test(text(doc.querySelector('#messagetext')))) throw Park.error('LOGIN_REQUIRED', '请在应用内登录次元茶馆');
        if (!/没有找到|未找到|相关内容 0|相关内容.*0 个/.test(text(doc))) throw Park.error('PARSE', '搜索结果无法读取');
      }
      const next = nextOf(doc, Number(page) || 1, true);
      return {items: await this.hydrate(rowsOf(doc)), page, hasNext: !!next, cursor: next};
    },
    async comments(value, req = {}) {
      const id = idOf(value), page = Math.max(1, Math.floor(Number(req.page) || 1));
      if (req.parentId) return {items: [], page, hasNext: false};
      // 桌面帖的公开回复独立于移动版资源解锁，不进入 page() 的账号门槛或回复表单。
      const url = BASE + '/forum.php?mod=viewthread&tid=' + id + '&page=' + page + '&mobile=no';
      await wait();
      const doc = parse(this.http.ensureOk(await this.http.get(url)).body);
      const nodes = [...doc.querySelectorAll('[id^="postmessage_"]')];
      if (!nodes.length) {
        if (/登录|权限|无权/.test(text(doc.querySelector('#messagetext')))) throw Park.error('LOGIN_REQUIRED', '请在应用内登录次元茶馆');
        throw Park.error('PARSE', '评论数据无效');
      }
      if (![...doc.querySelectorAll('#pt a[href]')].some(a => gameForum(a.getAttribute('href')))) throw Park.error('NOT_FOUND', '该帖子不属于游戏资源区');
      const current = Number(text(doc.querySelector('.pg strong')) || 1);
      if (current !== page) throw Park.error('PARSE', '评论数据无效');
      const seen = new Set(), items = [];
      for (const node of nodes.slice(page === 1 ? 1 : 0)) {
        const cid = /^postmessage_([1-9]\d*)$/.exec(node.getAttribute('id'))?.[1], row = node.closest('[id^="post_"]');
        if (!cid || !row) throw Park.error('PARSE', '评论数据无效');
        if (seen.has(cid)) continue;
        seen.add(cid);
        const author = row.querySelector('.pls .authi a'), date = row.querySelector('[id^="authorposton"]');
        const content = node.cloneNode(true);
        content.querySelectorAll('.pstatus, script, style').forEach(n => n.remove());
        // Discuz 的延迟图片用 file/zoomfile，引用正文保持为独立引用片段。
        for (const img of content.querySelectorAll('img')) {
          const image = img.getAttribute('file') || img.getAttribute('zoomfile');
          if (image) img.setAttribute('src', image);
        }
        for (const quote of [...content.querySelectorAll('.quote')]) {
          const block = parse('<blockquote>' + quote.innerHTML + '</blockquote>').querySelector('blockquote');
          quote.replaceWith(block);
        }
        const body = Park.comments.html(content.innerHTML, url);
        if (!body.length) continue;
        items.push({id: cid, author: {name: text(author), url: Park.comments.url(author?.getAttribute('href'), url) || undefined,
          avatar: Park.comments.url(row.querySelector('.pls .avatar img')?.getAttribute('src'), url) || undefined},
          body, date: date?.querySelector('[title]')?.getAttribute('title') || text(date)});
      }
      const next = doc.querySelector('.pg a.nxt')?.getAttribute('href');
      let hasNext = false;
      if (next) {
        const u = sameSite(next), path = /^\/thread-(\d+)-(\d+)-\d+\.html$/.exec(u.pathname);
        const nextId = path?.[1] || (u.pathname === '/forum.php' && u.searchParams.get('mod') === 'viewthread' ? u.searchParams.get('tid') : null);
        const nextPage = Number(path?.[2] || u.searchParams.get('page'));
        if (nextId !== id || nextPage !== page + 1) throw Park.error('PARSE', '评论数据无效');
        hasNext = true;
      }
      return {items, page, hasNext};
    },
    async detail(id) {
      id = idOf(id);
      const doc = await this.page(threadUrl(id)), body = bodyOf(doc);
      if (!body) throw Park.error('PARSE', '游戏帖子首楼无法读取');
      checkGame(doc);
      const paragraphs = Park.html.paragraphs(body).filter(p => !/提取码|解压密码|https?:\/\//.test(p));
      return {...item(doc, id), url: threadUrl(id), description: paragraphs.join('\n\n'),
        authors: [text(doc.querySelector('.postlist .plc .authi a'))].filter(Boolean), tags: []};
    },
    async gameResources(id) {
      id = idOf(id);
      const doc = await this.page(threadUrl(id)), body = bodyOf(doc);
      if (!body) throw Park.error('PARSE', '游戏帖子首楼无法读取');
      checkGame(doc);
      const locked = hidden(body), links = await shares(body);
      if (!locked && !links.length) return [];
      return [{id, title: titleOf(doc), testStatus: 'unknown',
        channels: locked ? [{id: 'unlock', kind: 'external', label: '帖子分享', requiresReply: true, replyText: REPLY}] : links.map(l => ({id: l.id, kind: 'external', label: l.label}))}];
    },
    async resolveGameResource(id, resourceId, channelId) {
      id = idOf(id);
      if (String(resourceId) !== id) throw Park.error('CONFIG', '资源编号无效');
      const key = id;
      if (pending.has(key)) { await pending.get(key); return this.resolveGameResource(id, resourceId, channelId); }
      const operation = this.resolveShares(id, String(channelId));
      pending.set(key, operation);
      try { return await operation; } finally { if (pending.get(key) === operation) pending.delete(key); }
    },
    async resolveShares(id, channelId) {
      let doc = await this.page(threadUrl(id)), body = bodyOf(doc);
      if (!body) throw Park.error('PARSE', '游戏帖子首楼无法读取');
      checkGame(doc);
      const confirm = () => Park.error('CONFIRM_REQUIRED', '回复结果待确认，请在原帖检查，应用不会重复发送', {url: threadUrl(id)});
      if (hidden(body)) {
        if (!loggedIn(doc)) throw Park.error('LOGIN_REQUIRED', '请在应用内登录次元茶馆');
        if (channelId !== 'unlock') throw Park.error('PARSE', '资源权限已改变，请刷新资源列表');
        const attempts = this.store.get('replyAttempts', {});
        const accountId = accountIdOf(doc);
        const attemptKey = accountId + ':' + id;
        if (attempts[attemptKey]) throw confirm();
        const replyLink = body.querySelector('a[href*="action=reply"]');
        const replyUrl = replyUrlOf(replyLink?.getAttribute('href') || '', id);
        const verifyReply = () => Park.error('CONFIRM_REQUIRED', '请在回复页完成验证并手动回复，返回后重试读取资源', {url: replyUrl.href});
        // Touch reply pages omit the account footer; identity comes from the thread, not its author.
        const reply = await this.page(replyUrl.href, undefined, false), form = reply.querySelector('#postform');
        if (!form) throw verifyReply();
        const action = replyUrlOf(form.getAttribute('action'), id);
        if (action.searchParams.get('fid') !== replyUrl.searchParams.get('fid')) throw Park.error('PARSE', '站点表单地址无效');
        const values = {};
        for (const name of ['formhash', 'posttime', 'noticeauthor', 'noticetrimstr', 'noticeauthormsg', 'subject']) {
          const input = form.querySelector(`[name="${name}"]`);
          if (input) values[name] = input.getAttribute('value') || '';
        }
        if (!values.formhash) throw verifyReply();
        const scripts = Array.from(reply.querySelectorAll('script')).map(s => s.textContent || '').join('\n');
        if (form.querySelector('[name^="seccode"], [name^="secanswer"]') ||
            /(?:seccodecheck|secqaacheck)\s*=\s*(?:parseInt\(['"]1['"]\)|1)/.test(scripts)) throw verifyReply();
        Object.assign(values, {message: REPLY, replysubmit: 'true', wysiwyg: '0', usesig: '0', htmlon: '0'});
        this.store.set('replyAttempts', {...this.store.get('replyAttempts', {}), [attemptKey]: 'submitted'});
        await this.store.flush();
        await wait();
        try { await this.http.post(action.href, {form: values}); } catch (_) { /* Read after ambiguous delivery. */ }
        try { doc = await this.page(threadUrl(id)); body = bodyOf(doc); } catch (_) { throw confirm(); }
        if (!body || hidden(body)) throw confirm();
      }
      const links = await shares(body);
      const selected = channelId === 'unlock' ? links : links.filter(l => l.id === channelId);
      if (!selected.length) throw Park.error('PARSE', '帖子未提供可读取的网盘链接');
      const codes = [...new Set(selected.map(l => l.code).filter(Boolean))];
      const urls = selected.map(l => l.url);
      return {kind: 'external', url: urls[0], urls, extractionCodes: selected.map(l => l.code),
        extractionCode: codes.length === 1 ? codes[0] : '', archivePassword: archiveIn(body)};
    },
  });
})();
