(function () {
  'use strict';

  const SITE = 'https://realm.risuai.net';
  const API = SITE + '/api/v1/download';
  const CDN = 'sv.risuai.xyz';
  const idPattern = /^[A-Fa-f0-9-]{16,100}$/;

  function identity(value) {
    const match = /^(?:(character|lorebook):)?([A-Fa-f0-9-]{16,100})$/.exec(String(value || ''));
    if (!match || !idPattern.test(match[2])) throw Park.error('NOT_FOUND', '内容不存在');
    return {kind: match[1] || 'character', id: match[2].toLowerCase()};
  }

  function safeImage(value, base) {
    try {
      const url = new URL(value || '', base);
      return url.protocol === 'https:' && url.hostname === CDN &&
        !url.username && !url.password && !url.port && !url.hash ? url.href : '';
    } catch (_) {
      return '';
    }
  }

  function tagsOf(card) {
    const tags = [];
    for (const link of card.querySelectorAll('a[href]')) {
      try {
        const url = new URL(link.getAttribute('href'), SITE);
        const value = url.searchParams.get('q') || '';
        if (value.startsWith('tag:')) {
          const tag = value.slice(4).trim();
          if (tag && !tags.includes(tag)) tags.push(tag);
        }
      } catch (_) {}
    }
    return tags;
  }

  function explicit(text) {
    return /(?:\+18|🔞|\bnsfw\b)/i.test(text);
  }

  function cardItem(card, base, requestedKind) {
    let url;
    try { url = new URL(card.getAttribute('href'), base); } catch (_) { return null; }
    if (url.hostname !== 'realm.risuai.net') return null;
    const match = /^\/character\/([A-Fa-f0-9-]{16,100})\/?$/.exec(url.pathname);
    if (!match) return null;
    const title = Park.html.text(card.querySelector('h2'));
    if (!title) return null;
    const tags = tagsOf(card);
    const body = Park.html.text(card);
    const isNsfw = explicit(body) || tags.includes('nsfw');
    const kind = requestedKind === 'lorebook' ||
      (requestedKind === 'all' && tags.includes('lorebooks')) ? 'lorebook' : 'character';
    const author = [...card.querySelectorAll('a[href]')]
      .map((link) => {
        try {
          const linkUrl = new URL(link.getAttribute('href'), base);
          return linkUrl.pathname.startsWith('/creator/') ? Park.html.text(link) : '';
        } catch (_) { return ''; }
      })
      .find((value) => value) || '';
    return {
      id: kind + ':' + match[1].toLowerCase(),
      title,
      url: url.href,
      subtitle: body.slice(0, 512),
      cover: safeImage(card.querySelector('img')?.getAttribute('src'), base),
      authors: author.replace(/^By\s+/i, '').trim() ? [author.replace(/^By\s+/i, '').trim()] : [],
      tags,
      mediaKind: 'tavern',
      tavernKind: kind,
      ...(isNsfw ? {isNsfw: true, contentRating: 'nsfw'} : {}),
    };
  }

  async function html(source, url) {
    const response = await source.http.get(url);
    source.http.ensureOk(response);
    if (response.body.length > 6 * 1024 * 1024) throw Park.error('PARSE', '站点返回了无效结果');
    return {doc: Park.html.parse(response.body), body: response.body};
  }

  function searchUrl(keyword, kind) {
    const query = [];
    if (kind === 'lorebook') query.push('tag:lorebooks');
    if (keyword) query.push(String(keyword).trim());
    const url = new URL('/', SITE);
    if (query.length) url.searchParams.set('q', query.join(' '));
    return url;
  }

  async function list(source, keyword, kind, page) {
    if (!Number.isInteger(page) || page < 1 || page > 1) {
      throw Park.error('UNSUPPORTED', '该站点只公开第一页搜索结果');
    }
    const url = searchUrl(keyword, kind);
    const {doc, body} = await html(source, url.href);
    const items = [];
    const seen = new Set();
    for (const card of doc.querySelectorAll('a[href^="/character/"]')) {
      const item = cardItem(card, url.href, kind);
      if (!item || seen.has(item.id)) continue;
      seen.add(item.id);
      items.push(item);
    }
    if (!items.length && body.length > 10000) {
      throw Park.error('PARSE', '站点返回了无效结果');
    }
    return {items, page: 1, hasNext: false};
  }

  async function detailPage(source, id) {
    const entry = identity(id);
    const url = new URL('/character/' + entry.id, SITE);
    const {doc} = await html(source, url.href);
    const headings = [...doc.querySelectorAll('h1')];
    const titleHeading = headings.find((heading) =>
      String(heading.getAttribute('class') || '').includes('font-semibold'),
    ) || headings[1] || headings[0];
    const title = Park.html.text(titleHeading);
    if (!title || title === 'RisuRealm') throw Park.error('PARSE', '站点返回了无效结果');
    const tags = tagsOf(doc);
    const body = Park.html.text(doc);
    const isNsfw = explicit(body) || tags.includes('nsfw');
    const author = [...doc.querySelectorAll('a[href^="/creator/"]')]
      .map((link) => Park.html.text(link).replace(/^By\s+/i, '').trim())
      .find((value) => value) || '';
    const kind = entry.kind === 'lorebook' || tags.includes('lorebooks') ? 'lorebook' : 'character';
    return {
      id: kind + ':' + entry.id,
      title,
      url: url.href,
      cover: safeImage(doc.querySelector('img[src*="sv.risuai.xyz"]')?.getAttribute('src'), url.href),
      authors: author ? [author] : [],
      tags,
      mediaKind: 'tavern',
      tavernKind: kind,
      description: doc.querySelector('meta[property="og:description"]')?.getAttribute('content') || '',
      ...(isNsfw ? {isNsfw: true, contentRating: 'nsfw'} : {}),
    };
  }

  function downloadUrl(format, id) {
    const url = new URL(format + '/' + id, API + '/');
    url.searchParams.set('cors', 'true');
    url.searchParams.set('access_token', 'guest');
    return url.href;
  }

  async function jsonDownload(source, format, id) {
    const text = await source.http.text(downloadUrl(format, id));
    if (text.length > 12 * 1024 * 1024) throw Park.error('PARSE', '酒馆资源过大');
    try { return JSON.parse(text); } catch (_) { throw Park.error('PARSE', '酒馆资源格式无效'); }
  }

  Park.register({
    i18n: {
      'zh-Hant': {
        '匿名角色卡与世界书': '匿名角色卡與世界書',
        '支持官方搜索语法；站点未公开独立 NSFW 筛选，保留原站成人标记': '支援官方搜尋語法；站點未公開獨立 NSFW 篩選，保留原站成人標記',
        '角色卡': '角色卡', '世界书': '世界書', '类型': '類型', '全部': '全部', '推荐': '推薦', '最新': '最新',
      },
      ja: {
        '匿名角色卡与世界书': '匿名のキャラクターカードと世界設定集',
        '支持官方搜索语法；站点未公开独立 NSFW 筛选，保留原站成人标记': '公式検索構文に対応。独立した NSFW フィルターは公開されていないため、原サイトの成人表示を保持します',
        '角色卡': 'キャラクターカード', '世界书': '世界設定集', '类型': '種類', '全部': 'すべて', '推荐': 'おすすめ', '最新': '最新',
      },
      ko: {
        '匿名角色卡与世界书': '익명 캐릭터 카드와 세계관 설정집',
        '支持官方搜索语法；站点未公开独立 NSFW 筛选，保留原站成人标记': '공식 검색 문법을 지원합니다. 별도 NSFW 필터는 공개되지 않아 원 사이트의 성인 표시를 유지합니다',
        '角色卡': '캐릭터 카드', '世界书': '세계관 설정집', '类型': '유형', '全部': '전체', '推荐': '추천', '最新': '최신',
      },
      en: {
        '匿名角色卡与世界书': 'Anonymous character cards and lorebooks',
        '支持官方搜索语法；站点未公开独立 NSFW 筛选，保留原站成人标记': 'Uses the documented search syntax; no separate NSFW filter is published, so original adult markers are preserved',
        '角色卡': 'Character cards', '世界书': 'Lorebooks', '类型': 'Type', '全部': 'All', '推荐': 'Recommended', '最新': 'Latest',
      },
      es: {
        '匿名角色卡与世界书': 'Tarjetas y libros de mundo anónimos',
        '支持官方搜索语法；站点未公开独立 NSFW 筛选，保留原站成人标记': 'Usa la sintaxis de búsqueda documentada; no hay un filtro NSFW independiente publicado y se conservan las marcas de adultos',
        '角色卡': 'Tarjetas', '世界书': 'Libros de mundo', '类型': 'Tipo', '全部': 'Todos', '推荐': 'Recomendado', '最新': 'Último',
      },
      ru: {
        '匿名角色卡与世界书': 'Анонимные карточки персонажей и книги мира',
        '支持官方搜索语法；站点未公开独立 NSFW 筛选，保留原站成人标记': 'Используется документированный синтаксис поиска; отдельный NSFW-фильтр не опубликован, поэтому сохраняются отметки источника',
        '角色卡': 'Карточки персонажей', '世界书': 'Книги мира', '类型': 'Тип', '全部': 'Все', '推荐': 'Рекомендуемое', '最新': 'Новое',
      },
      ar: {
        '匿名角色卡与世界书': 'بطاقات شخصيات وكتب عالم مجهولة',
        '支持官方搜索语法；站点未公开独立 NSFW 筛选，保留原站成人标记': 'يستخدم صيغة البحث الموثقة؛ لا يوجد مرشح NSFW مستقل منشور، لذلك تُحفظ علامات المحتوى الأصلي',
        '角色卡': 'بطاقات الشخصيات', '世界书': 'كتب العالم', '类型': 'النوع', '全部': 'الكل', '推荐': 'موصى به', '最新': 'الأحدث',
      },
    },
    key: 'risu_realm',
    name: 'RisuRealm',
    version: '0.0.2',
    minAppVersion: '0.14.0',
    type: 'tavern',
    category: 'tavern',
    color: '#2F6FB0',
    homepage: SITE,
    domains: ['risuai.net'],
    imageNetwork: {mode: 'browser', origin: SITE, domains: [CDN]},
    network: {mode: 'auto', origin: SITE, vpnHint: true},
    linkPatterns: ['realm\\.risuai\\.net/character/([A-Fa-f0-9-]{16,100})'],
    idPattern: '^(?:(?:character|lorebook):)?[A-Fa-f0-9-]{16,100}$',
    description: '匿名角色卡与世界书',
    searchHint: '支持官方搜索语法；站点未公开独立 NSFW 筛选，保留原站成人标记',
    defaultFeed: 'characters',
    feeds: [
      {key: 'characters', label: '角色卡'},
      {key: 'lorebooks', label: '世界书'},
    ],
    searchFilters: [
      {key: 'kind', label: '类型', default: 'character', values: [
        {value: 'character', label: '角色卡'},
        {value: 'lorebook', label: '世界书'},
        {value: 'all', label: '全部'},
      ]},
    ],
    async feed(key, {page = 1} = {}) {
      return list(this, '', key === 'lorebooks' ? 'lorebook' : 'character', page);
    },
    async search({keyword = '', page = 1, filters = {}} = {}) {
      const kind = filters.kind === 'lorebook' || filters.kind === 'all' ? filters.kind : 'character';
      if (String(keyword).length > 200) throw Park.error('CONFIG', '访问受限');
      return list(this, String(keyword).trim(), kind, page);
    },
    async detail(id) {
      return detailPage(this, id);
    },
    async tavernAsset(id) {
      const entry = identity(id);
      if (entry.kind === 'character') {
        const data = await jsonDownload(this, 'json-v3', entry.id);
        if (!data || typeof data !== 'object' || !data.data || typeof data.data.name !== 'string') {
          throw Park.error('PARSE', '酒馆资源格式无效');
        }
        return {kind: 'character', format: 'json', data};
      }
      const data = await jsonDownload(this, 'module-v1', entry.id);
      const book = data && data.data && data.data.character_book;
      if (!book || !Array.isArray(book.entries) || !book.entries.length) {
        throw Park.error('PARSE', '酒馆资源格式无效');
      }
      return {kind: 'lorebook', format: 'json', data: {...data, entries: book.entries}};
    },
  });
})();
