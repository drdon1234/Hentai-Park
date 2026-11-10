(function () {
  'use strict';
  const BASE = 'https://gamcore.com';
  const feeds = {
    popular: '/best', games: '/games', html: '/html_games', flash: '/flash',
    chinese: '/chinese', hentai: '/hentai_games', rpg: '/rpg_maker',
  };
  const fail = () => Park.error('PARSE', '加载失败');
  function pageOf(value) {
    const page = Number(value || 1);
    if (!Number.isSafeInteger(page) || page < 1 || page > 100000) throw Park.error('CONFIG', '访问受限');
    return page;
  }
  function idOf(value) {
    const id = String(value || '');
    if (!/^[a-z0-9_]{1,150}$/i.test(id)) throw Park.error('NOT_FOUND', '内容不存在');
    return id;
  }
  function siteUrl(value) {
    if (!value) return '';
    try {
      const url = new URL(value, BASE);
      return url.protocol === 'https:' && url.hostname === 'gamcore.com' && !url.port && !url.username && !url.password ? url.href : '';
    } catch (_) { return ''; }
  }
  function gameUrl(value) {
    try {
      const url = new URL(value, BASE);
      return url.protocol === 'https:' && !url.port && !url.username && !url.password &&
        (url.hostname === 'fgn.cdn.serverable.com' || url.hostname.endsWith('.fgn.cdn.serverable.com')) ? url.href : '';
    } catch (_) { return ''; }
  }
  const meta = (doc, name) => doc.querySelector(`meta[${name}]`)?.getAttribute('content')?.trim() || '';
  const text = node => (node?.textContent || '').trim();
  function items(doc) {
    return [...doc.querySelectorAll('.all_items .item')].map(row => {
      const a = row.querySelector('h3 a[href^="/games/"]');
      const match = /^\/games\/([a-z0-9_]+)$/i.exec(a?.getAttribute('href') || '');
      if (!match || !text(a)) return null;
      const image = row.querySelector('.image img[src]');
      return {id: match[1], title: text(a), subtitle: text(row.querySelector('.text p')),
        cover: siteUrl(image?.getAttribute('src') || ''), mediaKind: 'game', contentDomain: 'onlineGame'};
    }).filter(Boolean);
  }
  function results(doc, page, search = false) {
    const container = doc.querySelector('.all_items');
    if (!container) throw fail();
    const rows = items(doc);
    const noResults = search && !!container.querySelector('#search-form') &&
      [...container.querySelectorAll('p')].some(p => /did not match anything/i.test(text(p)));
    if (!rows.length && !noResults) throw fail();
    const hasNext = [...doc.querySelectorAll('a[href]')].some(a => {
      try { return new URL(a.getAttribute('href'), BASE).searchParams.get('page') === String(page + 1); }
      catch (_) { return false; }
    });
    return {items: rows, page, hasNext};
  }
  Park.register({
    key: 'gamcore', name: 'Gamcore', version: '0.0.1', minAppVersion: '1.12.1',
    type: 'game', category: 'onlineGame', color: '#F5681B',
    description: '在线 HTML 与 Flash 游戏，支持分类和搜索', homepage: BASE, language: 'multi',
    domains: ['gamcore.com'], network: {mode: 'auto', vpnHint: true},
    linkPatterns: ['https?://(?:www\\.)?gamcore\\.com/games/([a-z0-9_]+)'],
    idPattern: '^([a-z0-9_]+)$', idExample: 'orbeffect',
    defaultFeed: 'popular',
    feeds: [
      {key: 'popular', label: '热门'}, {key: 'games', label: '全部'},
      {key: 'html', label: 'HTML'}, {key: 'flash', label: 'Flash'},
      {key: 'chinese', label: '中文'}, {key: 'hentai', label: 'Hentai'},
      {key: 'rpg', label: 'RPG Maker'},
    ],
    i18n: {
      'zh-Hant': {'在线 HTML 与 Flash 游戏，支持分类和搜索': '線上 HTML 與 Flash 遊戲，支援分類和搜尋'},
      ja: {'在线 HTML 与 Flash 游戏，支持分类和搜索': 'HTML と Flash のオンラインゲーム、カテゴリと検索に対応'},
      ko: {'在线 HTML 与 Flash 游戏，支持分类和搜索': 'HTML 및 Flash 온라인 게임, 분류와 검색 지원'},
      en: {'在线 HTML 与 Flash 游戏，支持分类和搜索': 'Online HTML and Flash games with categories and search'},
      es: {'在线 HTML 与 Flash 游戏，支持分类和搜索': 'Juegos HTML y Flash en línea con categorías y búsqueda'},
      ru: {'在线 HTML 与 Flash 游戏，支持分类和搜索': 'Онлайн-игры HTML и Flash с категориями и поиском'},
      ar: {'在线 HTML 与 Flash 游戏，支持分类和搜索': 'ألعاب HTML وFlash عبر الإنترنت مع تصنيفات وبحث'},
    },
    async document(url) {
      const response = this.http.ensureOk(await this.http.get(url));
      if (!siteUrl(response.url || url)) throw fail();
      return Park.html.parse(response.body);
    },
    async feed(key, {page = 1} = {}) {
      page = pageOf(page);
      if (!Object.hasOwn(feeds, key)) throw Park.error('CONFIG', '访问受限');
      const url = new URL(feeds[key], BASE);
      if (page > 1) url.searchParams.set('page', page);
      return results(await this.document(url.href), page);
    },
    async search({keyword, page = 1} = {}) {
      page = pageOf(page);
      const q = String(keyword || '').trim();
      if (!q || q.length > 200) throw Park.error('CONFIG', '访问受限');
      const url = new URL('/search', BASE);
      url.searchParams.set('q', q);
      if (page > 1) url.searchParams.set('page', page);
      return results(await this.document(url.href), page, true);
    },
    async detail(value, preview) {
      const id = idOf(value), url = BASE + '/games/' + id;
      const doc = await this.document(url);
      const title = text(doc.querySelector('h1')) || meta(doc, 'property="og:title"');
      if (!title || !doc.querySelector('#game')) throw fail();
      const cover = preview?.id === id && preview.cover ? siteUrl(preview.cover) : '';
      return {id, title, url, cover, description: meta(doc, 'itemprop="description"'),
        mediaKind: 'game', contentDomain: 'onlineGame'};
    },
    async onlineGame(value) {
      const id = idOf(value), doc = await this.document(BASE + '/games/' + id);
      const frame = gameUrl(doc.querySelector('#game iframe#nf_game')?.getAttribute('src') || '');
      if (frame) return {kind: 'html', url: frame};
      const scripts = [...doc.querySelectorAll('#game script')];
      const swf = scripts.map(script => /player\.load\(["']([^"']+\.swf(?:\?[^"']*)?)["']\)/i.exec(script.textContent || '')?.[1]).find(Boolean);
      const ruffle = scripts.map(script => script.getAttribute('src')).find(src => /\/ruffle[^/]*\/ruffle\.js(?:\?|$)/i.test(src || ''));
      const url = gameUrl(swf || ''), player = gameUrl(ruffle || '');
      if (url && player) return {kind: 'flash', url, player};
      throw Park.error('UNSUPPORTED', '该游戏暂不支持，请在原站打开');
    },
  });
})();
