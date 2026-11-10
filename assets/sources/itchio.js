(function () {
  'use strict';
  const BASE = 'https://itch.io';
  const fail = () => Park.error('PARSE', '加载失败');
  const options = [
    {key: 'language', label: '语言', default: '', values: [{value: '', label: '全部'}, {value: 'zh', label: '中文'}, {value: 'en', label: '英文'}]},
    {key: 'tag', label: '标签', default: '', values: [{value: '', label: '全部'}, {value: 'adult', label: 'Adult'}, {value: 'hentai', label: 'Hentai'}, {value: 'eroge', label: 'Eroge'}]},
  ];
  function pageOf(value) {
    const page = Number(value || 1);
    if (!Number.isSafeInteger(page) || page < 1 || page > 10000) throw Park.error('CONFIG', '访问受限');
    return page;
  }
  function idOf(value) {
    const id = String(value || '');
    if (!/^[a-z0-9][a-z0-9-]{0,62}\/[a-z0-9][a-z0-9-]{0,127}$/i.test(id)) throw Park.error('NOT_FOUND', '内容不存在');
    return id.toLowerCase();
  }
  function idFromUrl(value) {
    try {
      const url = new URL(value, BASE), owner = /^([a-z0-9][a-z0-9-]{0,62})\.itch\.io$/i.exec(url.hostname);
      const slug = /^\/([a-z0-9][a-z0-9-]{0,127})\/?$/i.exec(url.pathname);
      if (url.protocol !== 'https:' || url.port || url.username || url.password || !owner || !slug) return '';
      return idOf(owner[1] + '/' + slug[1]);
    } catch (_) { return ''; }
  }
  function detailUrl(id) {
    const [owner, slug] = idOf(id).split('/');
    return 'https://' + owner + '.itch.io/' + slug;
  }
  function imageUrl(value) {
    try {
      if (!value) return '';
      const url = new URL(value, BASE);
      return url.protocol === 'https:' && !url.port && !url.username && !url.password &&
        (url.hostname === 'img.itch.zone' || url.hostname.endsWith('.img.itch.zone')) ? url.href : '';
    } catch (_) { return ''; }
  }
  function cards(doc) {
    return [...doc.querySelectorAll('.game_cell')].map(row => {
      const link = row.querySelector('.game_title a.game_link');
      const id = idFromUrl(link?.getAttribute('href') || '');
      const title = (link?.textContent || '').trim();
      if (!id || !title || !row.querySelector('.web_flag')) return null;
      const image = row.querySelector('.game_thumb img');
      return {id, title, url: detailUrl(id), subtitle: (row.querySelector('.game_text')?.textContent || '').trim(),
        cover: imageUrl(image?.getAttribute('data-lazy_src') || image?.getAttribute('src')),
        authors: [(row.querySelector('.game_author')?.textContent || '').trim()].filter(Boolean),
        mediaKind: 'game', contentDomain: 'onlineGame'};
    }).filter(Boolean);
  }
  function results(doc, page) {
    const body = doc.querySelector('.game_grid_widget, .results_column, .browse_games_page');
    if (!body) throw fail();
    const rows = cards(doc);
    if (!rows.length && !body.querySelector('.empty_message')) throw fail();
    const next = [...doc.querySelectorAll('a[href], link[rel="next"]')].some(a => {
      try { return new URL(a.getAttribute('href'), BASE).searchParams.get('page') === String(page + 1); }
      catch (_) { return false; }
    });
    return {items: rows, page, hasNext: next};
  }
  Park.register({
    key: 'itchio', name: 'itch.io', version: '0.0.2', minAppVersion: '0.13.0',
    type: 'game', category: 'onlineGame', color: '#FA5C5C',
    description: '独立网页游戏，支持语言和标签浏览', homepage: BASE, language: 'multi',
    domains: ['itch.io'], network: {mode: 'auto', vpnHint: true, confirmation: {
      selector: '.content_warning_widget form[action="/content-warning"]',
      readySelector: '.browse_games_page, .facet_explorer_page_page, .view_game_page',
      requiredCookies: ['itchio'],
      auto: {
        clickSelector: '.content_warning_widget form[action="/content-warning"] button',
        checkSelector: '.content_warning_widget form[action="/content-warning"] input[name="remember"]',
        birthDate: {
          yearSelector: 'select[name="birth_year"]',
          monthSelector: 'select[name="birth_month"]',
          daySelector: 'select[name="birth_day"]',
        },
      },
    }},
    linkPatterns: ['https?://([a-z0-9-]+\\.itch\\.io/[a-z0-9-]+)'],
    defaultFeed: 'popular', feeds: [{key: 'popular', label: '热门', options}],
    searchHint: '原站搜索可能包含非成人网页作品',
    i18n: {
      'zh-Hant': {'独立网页游戏，支持语言和标签浏览': '獨立網頁遊戲，支援語言和標籤瀏覽', '原站搜索可能包含非成人网页作品': '原站搜尋可能包含非成人網頁作品'},
      ja: {'独立网页游戏，支持语言和标签浏览': '独立系ブラウザゲーム、言語とタグで閲覧', '原站搜索可能包含非成人网页作品': 'サイトの検索には成人向け以外の作品も含まれる場合があります'},
      ko: {'独立网页游戏，支持语言和标签浏览': '독립 웹 게임, 언어 및 태그 탐색 지원', '原站搜索可能包含非成人网页作品': '원본 사이트 검색에는 성인용이 아닌 웹 작품도 포함될 수 있습니다'},
      en: {'独立网页游戏，支持语言和标签浏览': 'Independent browser games with language and tag browsing', '原站搜索可能包含非成人网页作品': 'Site search may include non-adult browser titles'},
      es: {'独立网页游戏，支持语言和标签浏览': 'Juegos independientes de navegador con idiomas y etiquetas', '原站搜索可能包含非成人网页作品': 'La búsqueda del sitio puede incluir obras de navegador no adultas'},
      ru: {'独立网页游戏，支持语言和标签浏览': 'Независимые браузерные игры с выбором языка и тегов', '原站搜索可能包含非成人网页作品': 'Поиск сайта может включать браузерные работы не для взрослых'},
      ar: {'独立网页游戏，支持语言和标签浏览': 'ألعاب متصفح مستقلة مع تصفح حسب اللغة والوسوم', '原站搜索可能包含非成人网页作品': 'قد يتضمن بحث الموقع أعمال متصفح غير مخصصة للبالغين'},
    },
    async document(url) {
      let response = this.http.ensureOk(await this.http.get(url));
      let doc = Park.html.parse(response.body);
      const gate = '.content_warning_widget form[action="/content-warning"]';
      if (doc.querySelector(gate)) {
        // Native HTTP can receive an age gate with status 200; the shared browser
        // framework handles it only after the app's local adult confirmation.
        response = this.http.ensureOk(await this.http.get(url, {mode: 'browser'}));
        doc = Park.html.parse(response.body);
      }
      if (doc.querySelector(gate)) {
        throw Park.error('CONFIRM_REQUIRED', '请在站点页面完成年龄确认后重试', {url});
      }
      return doc;
    },
    async feed(key, {page = 1, options: selected = {}} = {}) {
      page = pageOf(page);
      if (key !== 'popular' || !['', 'zh', 'en'].includes(selected.language || '') || !['', 'adult', 'hentai', 'eroge'].includes(selected.tag || '')) throw Park.error('CONFIG', '访问受限');
      let path = '/games/html5' + (selected.language ? '/lang-' + selected.language : '') + '/nsfw';
      if (selected.tag) path += '/tag-' + selected.tag;
      const url = new URL(path, BASE);
      if (page > 1) url.searchParams.set('page', page);
      return results(await this.document(url.href), page);
    },
    async search({keyword, page = 1} = {}) {
      page = pageOf(page);
      const q = String(keyword || '').trim();
      if (!q || q.length > 200) throw Park.error('CONFIG', '访问受限');
      const url = new URL('/search', BASE);
      url.searchParams.set('q', q);
      url.searchParams.set('facets', 'p.web');
      if (page > 1) url.searchParams.set('page', page);
      return results(await this.document(url.href), page);
    },
    async resolveLink(value) {
      const id = idFromUrl('https://' + String(value || ''));
      if (!id) throw Park.error('NOT_FOUND', '内容不存在');
      return id;
    },
    async detail(value, preview) {
      const id = idOf(value), url = detailUrl(id), doc = await this.document(url);
      const title = (doc.querySelector('h1.game_title')?.textContent || '').trim() ||
        doc.querySelector('meta[property="og:title"]')?.getAttribute('content') || '';
      if (!title) throw fail();
      return {id, title, url, cover: imageUrl(preview?.cover || doc.querySelector('meta[property="og:image"]')?.getAttribute('content')),
        description: doc.querySelector('meta[property="og:description"]')?.getAttribute('content') || '',
        mediaKind: 'game', contentDomain: 'onlineGame'};
    },
    async onlineGame(value) {
      const id = idOf(value), doc = await this.document(detailUrl(id));
      const stableId = doc.querySelector('[data-game_id]')?.getAttribute('data-game_id') || doc.querySelector('input[name="game_id"]')?.getAttribute('value') || '';
      if (!/^[1-9][0-9]{0,15}$/.test(stableId)) throw fail();
      const encoded = doc.querySelector('.html_embed_widget .iframe_placeholder[data-iframe]')?.getAttribute('data-iframe');
      const iframe = encoded ? Park.html.parse(encoded).querySelector('iframe#game_drop') : doc.querySelector('.html_embed_widget iframe#game_drop');
      let url;
      try { url = new URL(iframe?.getAttribute('src') || ''); } catch (_) { throw Park.error('UNSUPPORTED', '该游戏暂不支持，请在原站打开'); }
      if (url.protocol !== 'https:' || url.port || url.username || url.password || !['html-classic.itch.zone', 'html.itch.zone'].includes(url.hostname)) throw Park.error('UNSUPPORTED', '该游戏暂不支持，请在原站打开');
      return {kind: 'html', url: url.href, storageId: stableId};
    },
  });
})();
