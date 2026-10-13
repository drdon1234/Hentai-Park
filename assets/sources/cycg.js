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
  const threadUrl = id => BASE + '/thread-' + idOf(id) + '-1-1.html';
  const sameSite = value => {
    const u = new URL(value, BASE + '/');
    if (u.origin !== BASE || u.username || u.password) throw Park.error('PARSE', '站点表单地址无效');
    return u;
  };
  const loggedIn = doc => !!doc.querySelector('a[href*="action=logout"]');
  const bodyOf = doc => doc.querySelector('[id^="postmessage_"]');
  const checkGame = doc => {
    if (!Array.from(doc.querySelectorAll('#pt a[href]')).some(a => /forum-2-1\.html|[?&]fid=2(?:&|$)/.test(a.getAttribute('href')))) {
      throw Park.error('NOT_FOUND', '该帖子不属于游戏资源区');
    }
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
    const body = bodyOf(doc), img = body?.querySelector('img[file],img[zoomfile],img[src*="attachment"]');
    const raw = img?.getAttribute('file') || img?.getAttribute('zoomfile') || img?.getAttribute('src');
    let cover = '';
    try { if (raw) { const u = sameSite(raw); if (/\/data\/attachment\//.test(u.pathname)) cover = u.href; } } catch (_) {}
    return {id, title: text(doc.querySelector('#thread_subject')) || title || id, cover, coverAspect: 16 / 9,
      mediaKind: 'game', contentDomain: 'game', contentRating: 'unknown', coverRating: 'unknown'};
  }

  Park.register({
    key: 'cycg', name: '次元茶馆', version: '0.0.2', type: 'game', category: 'game', language: 'zh', color: '#BD916B',
    homepage: BASE, domains: ['cycg.xyz'], icon: BASE + '/favicon.ico',
    description: '社区游戏分享，登录后按需回复解锁网盘资源',
    network: {mode: 'browser', origin: BASE, vpnHint: true,
      confirmation: {readySelector: '#ct,#threadlisttableid,#postlist,#thread_subject,.showhide,.slst li.pbw', message: '若已看到正常页面，请点击完成；如资源仍被隐藏，请在原帖或回复页完成验证与回复，再返回重试'}},
    imageHeaders: {Referer: BASE + '/'},
    linkPatterns: ['https?://(?:www\\.)?cycg\\.xyz/thread-(\\d+)-', 'https?://(?:www\\.)?cycg\\.xyz/forum\\.php\\?mod=viewthread&tid=(\\d+)'],
    idPattern: '^(\\d+)$', idExample: '20602',
    defaultFeed: 'popular', feeds: [{key: 'popular', label: '热门'}, {key: 'latest', label: '最新'}],
    account: {
      type: 'cookies', title: '次元茶馆账号', required: false,
      hint: '在打开的网页中登录，看到账号或退出按钮后点击完成；若已是正常资源页，无需寻找人机验证。点击回复解锁会发送“感谢分享，好人一生平安”',
      loginUrl: BASE + '/member.php?mod=logging&action=login', cookieUrl: BASE + '/', requiredCookies: [],
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
        const doc = await this.page(BASE + '/');
        return {loggedIn: loggedIn(doc), name: loggedIn(doc) ? '次元茶馆账号' : ''};
      },
    },
    async page(url, options) {
      await wait();
      const doc = parse(await this.http.text(sameSite(url).href, options));
      if (!bodyOf(doc) && /抱歉.*(?:不存在|删除)/.test(text(doc))) throw Park.error('NOT_FOUND', '内容不存在');
      return doc;
    },
    async hydrate(rows) {
      const output = [];
      for (const row of rows) {
        let cached = covers.get(row.id);
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
    async feed(key, {page = 1} = {}) {
      page = Math.max(1, Number(page) || 1);
      const url = BASE + '/forum.php?mod=forumdisplay&fid=2&page=' + page + (key === 'latest' ? '&orderby=dateline' : '&filter=heat&orderby=heats');
      const doc = await this.page(url), table = doc.querySelector('#threadlisttableid');
      if (!table) throw Park.error('PARSE', '游戏列表无法读取');
      const rows = [];
      for (const row of table.querySelectorAll('tbody[id^="normalthread_"]')) {
        const a = row.querySelector('a.xst'), title = text(a), id = row.id.replace('normalthread_', '');
        if (!a || !/^(?:【(?:汉化|生肉)|\[(?:汉化|生肉))/.test(title)) continue;
        rows.push({id: idOf(id), title, subtitle: text(row.querySelector('.acgifby1')), uploaded: text(row.querySelector('.acgifby1 span'))});
      }
      return {items: await this.hydrate(rows), page, hasNext: !!doc.querySelector('.pg .nxt')};
    },
    async search({keyword, page = 1, cursor}) {
      if (!String(keyword || '').trim()) return this.feed('popular', {page});
      let doc;
      if (cursor) {
        const u = sameSite(cursor);
        if (u.pathname !== '/search.php' || !/^\d+$/.test(u.searchParams.get('searchid') || '')) throw Park.error('CONFIG', '搜索分页无效');
        doc = await this.page(u.href);
      } else {
        if (Number(page) > 1) throw Park.error('CONFIG', '搜索分页无效');
        const landing = await this.page(BASE + '/search.php?mod=forum&adv=yes');
        const form = Array.from(landing.querySelectorAll('form')).find(f => f.querySelector('[name="srchfid[]"]'));
        if (!form) {
          if (!loggedIn(landing)) throw Park.error('LOGIN_REQUIRED', '请在应用内登录次元茶馆');
          throw Park.error('PARSE', '搜索表单无法读取');
        }
        const hash = form.querySelector('[name="formhash"]')?.getAttribute('value');
        if (!hash) throw Park.error('LOGIN_REQUIRED', '请在应用内登录次元茶馆');
        const action = sameSite(form.getAttribute('action'));
        if (action.pathname !== '/search.php' || action.searchParams.get('mod') !== 'forum') throw Park.error('PARSE', '站点表单地址无效');
        doc = await this.page(action.href, {method: 'POST', form: {
          formhash: hash, srchtxt: String(keyword).trim(), 'srchfid[]': '2', srchfilter: 'all', searchsubmit: 'yes', orderby: 'lastpost', ascdesc: 'desc',
        }});
        const redirect = doc.querySelector('#messagetext a[href*="searchid="]')?.getAttribute('href');
        if (redirect) {
          const target = sameSite(redirect);
          if (target.pathname !== '/search.php' || !/^\d+$/.test(target.searchParams.get('searchid') || '')) throw Park.error('PARSE', '搜索分页无效');
          doc = await this.page(target.href);
        }
      }
      if (doc.querySelector('[name^="secqa"],[name^="seccode"]') || /验证问答|验证码/.test(text(doc.querySelector('#messagetext')))) {
        throw Park.error('CONFIRM_REQUIRED', '请在站点页面完成搜索验证后重试', {url: BASE + '/search.php?mod=forum&srchtxt=' + encodeURIComponent(String(keyword)) + '&searchsubmit=yes'});
      }
      const rows = [];
      if (!doc.querySelector('.slst')) {
        if (/登录/.test(text(doc.querySelector('#messagetext')))) throw Park.error('LOGIN_REQUIRED', '请在应用内登录次元茶馆');
        if (!/没有找到|未找到|相关内容 0|相关内容.*0 个/.test(text(doc))) throw Park.error('PARSE', '搜索结果无法读取');
      }
      for (const row of doc.querySelectorAll('.slst li.pbw')) {
        const forum = Array.from(row.querySelectorAll('a[href]')).find(a => /forum-2-1\.html|[?&]fid=2(?:&|$)/.test(a.getAttribute('href')));
        const a = row.querySelector('h3 a');
        if (forum && a && /^\d+$/.test(row.id)) rows.push({id: idOf(row.id), title: text(a)});
      }
      const next = doc.querySelector('.pg .nxt')?.getAttribute('href');
      return {items: await this.hydrate(rows), page, hasNext: !!next, cursor: next ? sameSite(next).href : null};
    },
    async detail(id) {
      id = idOf(id);
      const doc = await this.page(threadUrl(id)), body = bodyOf(doc);
      if (!body) throw Park.error('PARSE', '游戏帖子首楼无法读取');
      checkGame(doc);
      const paragraphs = Park.html.paragraphs(body).filter(p => !/提取码|解压密码|https?:\/\//.test(p));
      return {...item(doc, id), url: threadUrl(id), description: paragraphs.join('\n\n'),
        authors: [text(doc.querySelector('#postlist .authi a'))].filter(Boolean), tags: []};
    },
    async gameResources(id) {
      id = idOf(id);
      const doc = await this.page(threadUrl(id)), body = bodyOf(doc);
      if (!body) throw Park.error('PARSE', '游戏帖子首楼无法读取');
      checkGame(doc);
      const locked = hidden(body), links = await shares(body);
      if (!locked && !links.length) return [];
      return [{id, title: text(doc.querySelector('#thread_subject')), testStatus: 'unknown',
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
        const profile = doc.querySelector('#toptb a[href*="space-uid-"],#um a[href*="space-uid-"]') || doc.querySelector('a[href*="space-uid-"]');
        const accountId = /space-uid-(\d+)\.html/.exec(profile?.getAttribute('href') || '')?.[1] || 'unknown';
        const attemptKey = accountId + ':' + id;
        if (attempts[attemptKey]) throw confirm();
        const replyUrl = BASE + '/forum.php?mod=post&action=reply&fid=2&tid=' + id;
        const verifyReply = () => Park.error('CONFIRM_REQUIRED', '请在回复页完成验证并手动回复，返回后重试读取资源', {url: replyUrl});
        const reply = await this.page(replyUrl), form = reply.querySelector('#postform');
        if (!form) throw verifyReply();
        const action = sameSite(form.getAttribute('action'));
        if (action.pathname !== '/forum.php' || action.searchParams.get('mod') !== 'post' || action.searchParams.get('action') !== 'reply' || action.searchParams.get('tid') !== id || action.searchParams.get('fid') !== '2') throw Park.error('PARSE', '站点表单地址无效');
        const values = {};
        for (const name of ['formhash', 'posttime', 'noticeauthor', 'noticetrimstr', 'noticeauthormsg', 'subject']) {
          const input = form.querySelector(`[name="${name}"]`);
          if (input) values[name] = input.getAttribute('value') || '';
        }
        if (!values.formhash) throw verifyReply();
        const question = form.querySelector('[name^="secanswer"]');
        const scripts = Array.from(reply.querySelectorAll('script')).map(s => s.textContent || '').join('\n');
        if (form.querySelector('[name^="seccode"]') || /(?:seccodecheck|secqaacheck)\s*=\s*(?:parseInt\(['"]1['"]\)|1)/.test(scripts) && !question) throw verifyReply();
        if (question) {
          const context = text(question.parentNode);
          const m = /(?:^|\s)(\d{1,3})\s*([+\-×*÷/])\s*(\d{1,3})\s*=\s*\?/.exec(context);
          if (!m) throw verifyReply();
          const a = Number(m[1]), b = Number(m[3]), op = m[2];
          const answer = op === '+' ? a + b : op === '-' ? a - b : /[×*]/.test(op) ? a * b : b ? a / b : NaN;
          if (!Number.isInteger(answer)) throw verifyReply();
          values[question.getAttribute('name')] = String(answer);
          for (const input of form.querySelectorAll('input[type="hidden"][name^="sec"]')) values[input.getAttribute('name')] = input.getAttribute('value') || '';
        }
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
