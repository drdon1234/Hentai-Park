(function () {
  'use strict';
  const SITE = 'https://character-tavern.com';
  const CDN = 'ct-cards.storage.character-tavern.com';
  function path(id) {
    const value = String(id || '');
    if (!/^[A-Za-z0-9._~-]{1,80}\/[A-Za-z0-9._~-]{1,160}$/.test(value) ||
        value.split('/').some(x => x === '.' || x === '..')) throw Park.error('NOT_FOUND', '内容不存在');
    return value;
  }
  function detailUrl(id) { return SITE + '/character/' + path(id).split('/').map(encodeURIComponent).join('/'); }
  function safeImage(value, base) {
    try {
      const u = new URL(value, base);
      return u.protocol === 'https:' && u.hostname === CDN && !u.username && !u.password && !u.port ? u.href : '';
    } catch (_) { return ''; }
  }
  async function html(source, url) {
    const response = await source.http.get(url);
    source.http.ensureOk(response);
    if (response.body.length > 6 * 1024 * 1024) throw Park.error('PARSE', '站点返回了无效结果');
    return Park.html.parse(response.body);
  }
  function list(doc, base, number) {
    const seen = new Set(), items = [];
    for (const a of doc.querySelectorAll('a[href]')) {
      let url;
      try { url = new URL(a.getAttribute('href'), base); } catch (_) { continue; }
      if (url.hostname !== 'character-tavern.com') continue;
      const match = /^\/character\/([^/]+)\/([^/]+)\/?$/.exec(url.pathname);
      if (!match || !a.querySelector('h3')) continue;
      let id;
      try { id = path(decodeURIComponent(match[1]) + '/' + decodeURIComponent(match[2])); } catch (_) { continue; }
      const title = Park.html.text(a.querySelector('h3'));
      if (!title || seen.has(id)) continue;
      seen.add(id);
      items.push({id, title, subtitle: Park.html.text(a.querySelector('p')),
        cover: safeImage(a.querySelector('img')?.getAttribute('src'), base),
        authors: [id.split('/')[0]], mediaKind: 'tavern', tavernKind: 'character'});
    }
    const hasNext = [...doc.querySelectorAll('a[href]')].some((a) => {
      try {
        const url = new URL(a.getAttribute('href'), base);
        return url.hostname === 'character-tavern.com' &&
          url.pathname === '/search/cards' &&
          Number(url.searchParams.get('page') || 1) > number;
      } catch (_) { return false; }
    });
    return {items, page: number, hasNext};
  }
  const sorts = new Set([
    'best', 'new_noteworthy', 'popular', 'most_liked',
    'hidden_gems', 'newest', 'recently_updated',
  ]);
  function filterText(value) {
    return String(value || '').trim().slice(0, 200);
  }
  function filterNumber(value) {
    const number = Number(value);
    return Number.isSafeInteger(number) && number > 0 ? number : 0;
  }
  function applyFilters(url, filters) {
    const sort = sorts.has(filters.sort) ? filters.sort : '';
    if (sort && sort !== 'best') url.searchParams.set('sort', sort);
    for (const key of ['tags', 'exclude_tags']) {
      const value = filterText(filters[key]);
      if (value) url.searchParams.set(key, value.split(/[\s,]+/).filter(Boolean).join(','));
    }
    for (const key of ['minimum_tokens', 'maximum_tokens']) {
      const value = filterNumber(filters[key]);
      if (value) url.searchParams.set(key, String(value));
    }
    if (filters.hasLorebook === true) url.searchParams.set('hasLorebook', 'true');
    if (filters.isOC === true) url.searchParams.set('isOC', 'true');
  }
  Park.register({
    i18n: {
      'zh-Hant': {
        '角色卡': '角色卡', '热门': '熱門', '最佳': '最佳', '最新推荐': '最新推薦', '最高评价': '最高評價', '隐藏佳作': '隱藏佳作', '最近更新': '最近更新', '最新': '最新', '排序': '排序', '标签': '標籤',
        '排除标签': '排除標籤', '最少令牌': '最少令牌', '最多令牌': '最多令牌',
        '包含世界书': '包含世界書', '原创内容': '原創內容',
      },
      ja: {
        '角色卡': 'キャラクターカード', '热门': '人気', '最佳': 'ベスト', '最新推荐': '新着おすすめ', '最高评价': '高評価', '隐藏佳作': '隠れた名作', '最近更新': '最近更新', '最新': '最新', '排序': '並べ替え', '标签': 'タグ',
        '排除标签': '除外タグ', '最少令牌': '最小トークン数', '最多令牌': '最大トークン数',
        '包含世界书': 'ワールドブックを含む', '原创内容': 'オリジナルコンテンツ',
      },
      ko: {
        '角色卡': '캐릭터 카드', '热门': '인기', '最佳': '최고', '最新推荐': '최신 추천', '最高评价': '최고 평점', '隐藏佳作': '숨은 명작', '最近更新': '최근 업데이트', '最新': '최신', '排序': '정렬', '标签': '태그',
        '排除标签': '제외 태그', '最少令牌': '최소 토큰', '最多令牌': '최대 토큰',
        '包含世界书': '세계관 책 포함', '原创内容': '오리지널 콘텐츠',
      },
      en: {
        '角色卡': 'Character cards', '热门': 'Popular', '最佳': 'Best', '最新推荐': 'New & noteworthy', '最高评价': 'Top rated', '隐藏佳作': 'Hidden gems', '最近更新': 'Recently updated', '最新': 'Newest', '排序': 'Sort', '标签': 'Tags',
        '排除标签': 'Exclude tags', '最少令牌': 'Minimum tokens', '最多令牌': 'Maximum tokens',
        '包含世界书': 'Has lorebook', '原创内容': 'Original content',
      },
      es: {
        '角色卡': 'Tarjetas de personajes', '热门': 'Popular', '最佳': 'Mejor', '最新推荐': 'Novedades recomendadas', '最高评价': 'Mejor valorado', '隐藏佳作': 'Joyas ocultas', '最近更新': 'Actualizado recientemente', '最新': 'Más recientes', '排序': 'Ordenar', '标签': 'Etiquetas',
        '排除标签': 'Excluir etiquetas', '最少令牌': 'Tokens mínimos', '最多令牌': 'Tokens máximos',
        '包含世界书': 'Tiene libro de mundo', '原创内容': 'Contenido original',
      },
      ru: {
        '角色卡': 'Карточки персонажей', '热门': 'Популярное', '最佳': 'Лучшее', '最新推荐': 'Новое и рекомендуемое', '最高评价': 'Лучшие оценки', '隐藏佳作': 'Скрытые жемчужины', '最近更新': 'Недавно обновлённые', '最新': 'Новое', '排序': 'Сортировка', '标签': 'Теги',
        '排除标签': 'Исключить теги', '最少令牌': 'Минимум токенов', '最多令牌': 'Максимум токенов',
        '包含世界书': 'Есть книга мира', '原创内容': 'Оригинальный контент',
      },
      ar: {
        '角色卡': 'بطاقات الشخصيات', '热门': 'الشائع', '最佳': 'الأفضل', '最新推荐': 'جديد وموصى به', '最高评价': 'الأعلى تقييماً', '隐藏佳作': 'جواهر مخفية', '最近更新': 'مُحدّث مؤخراً', '最新': 'الأحدث', '排序': 'الترتيب', '标签': 'الوسوم',
        '排除标签': 'استبعاد الوسوم', '最少令牌': 'الحد الأدنى للرموز', '最多令牌': 'الحد الأقصى للرموز',
        '包含世界书': 'يتضمن كتاب عالم', '原创内容': 'محتوى أصلي',
      },
    },
    key: 'character_tavern', name: 'Character Tavern', version: '0.0.3', minAppVersion: '0.14.0',
    type: 'tavern', category: 'tavern', color: '#805F9A', description: '角色卡',
    homepage: SITE, domains: ['character-tavern.com'], network: {vpnHint: true},
    defaultFeed: 'popular', feeds: [{key: 'popular', label: '热门'}],
    searchFilters: [
      {key: 'sort', label: '排序', default: 'best', values: [
        {value: 'best', label: '最佳'},
        {value: 'new_noteworthy', label: '最新推荐'},
        {value: 'popular', label: '热门'},
        {value: 'most_liked', label: '最高评价'},
        {value: 'hidden_gems', label: '隐藏佳作'},
        {value: 'newest', label: '最新'},
        {value: 'recently_updated', label: '最近更新'},
      ]},
      {key: 'tags', label: '标签', type: 'text'},
      {key: 'exclude_tags', label: '排除标签', type: 'text'},
      {key: 'minimum_tokens', label: '最少令牌', type: 'number', default: 0},
      {key: 'maximum_tokens', label: '最多令牌', type: 'number', default: 0},
      {key: 'hasLorebook', label: '包含世界书', type: 'switch', default: false},
      {key: 'isOC', label: '原创内容', type: 'switch', default: false},
    ],
    async feed(key, {page = 1} = {}) {
      return this.search({keyword: '', page, filters: {sort: 'popular'}});
    },
    async search({keyword = '', page = 1, filters = {}} = {}) {
      if (!Number.isInteger(page) || page < 1 || page > 1000 || String(keyword).length > 200) throw Park.error('CONFIG', '访问受限');
      const url = new URL('/search/cards', SITE);
      if (keyword) url.searchParams.set('query', keyword);
      if (page > 1) url.searchParams.set('page', String(page));
      applyFilters(url, filters);
      return list(await html(this, url.href), url.href, page);
    },
    async detail(id) {
      const url = detailUrl(id), doc = await html(this, url);
      const title = Park.html.text(doc.querySelector('h1'));
      if (!title) throw Park.error('PARSE', '站点返回了无效结果');
      return {id: path(id), title, url, mediaKind: 'tavern', tavernKind: 'character',
        cover: safeImage(doc.querySelector('meta[property="og:image"]')?.getAttribute('content'), url),
        description: doc.querySelector('meta[property="og:description"]')?.getAttribute('content') || '', authors: [id.split('/')[0]]};
    },
    async tavernAsset(id) {
      const url = detailUrl(id), doc = await html(this, url);
      for (const a of doc.querySelectorAll('a[href]')) {
        const candidate = safeImage(a.getAttribute('href'), url);
        if (candidate && new URL(candidate).searchParams.get('action') === 'download') {
          return {kind: 'character', format: 'png', url: candidate};
        }
      }
      throw Park.error('UNSUPPORTED', '此作品不提供下载');
    },
  });
})();
