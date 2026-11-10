(function () {
  'use strict';
  const BASE = 'https://live2d-dcg.github.io';
  const PAGE_SIZE = 40;
  let cached;
  function pageNumber(value) {
    const page = Number(value || 1);
    if (!Number.isSafeInteger(page) || page < 1 || page > 100000) throw Park.error('CONFIG', '访问受限');
    return page;
  }
  function validId(value) {
    const id = String(value || '');
    if (!/^[a-z0-9_]{1,100}$/i.test(id)) throw Park.error('NOT_FOUND', '内容不存在');
    return id;
  }
  function item(row) {
    const id = validId(row[0]);
    const title = [row[1] || id, row[2]].filter(Boolean).join(' · ');
    const region = String(row[4] || '').includes('k') ? 'kr' : 'gl';
    return {id, title, subtitle: id, cover: '', url: `${BASE}/?m=${encodeURIComponent(id)}&r=${region}`,
      mediaKind: 'interactive', contentDomain: 'interactiveArt'};
  }
  Park.register({
    key: 'destiny_child_live2d', name: 'Destiny Child Live2D', version: '0.0.2', minAppVersion: '0.13.0',
    type: 'interactive', category: 'interactiveArt', color: '#D580AC',
    description: '天命之子 Live2D 模型归档，支持角色和服装搜索',
    homepage: BASE, language: 'multi', domains: ['live2d-dcg.github.io'], network: {mode: 'auto', vpnHint: true},
    defaultFeed: 'all', feeds: [{key: 'all', label: '全部'}],
    linkPatterns: ['https?://live2d-dcg\\.github\\.io/\\?(?:[^#]*&)?m=([a-z0-9_]+)'],
    idPattern: '^([a-z]+[0-9]+_[0-9]+)$', idExample: 'c000_01',
    i18n: {
      'zh-Hant': {'天命之子 Live2D 模型归档，支持角色和服装搜索': '天命之子 Live2D 模型歸檔，支援角色和服裝搜尋'},
      ja: {'天命之子 Live2D 模型归档，支持角色和服装搜索': 'デスティニーチャイルドの Live2D アーカイブ、キャラクターと衣装を検索'},
      ko: {'天命之子 Live2D 模型归档，支持角色和服装搜索': '데스티니 차일드 Live2D 모델 아카이브, 캐릭터와 의상 검색 지원'},
      en: {'天命之子 Live2D 模型归档，支持角色和服装搜索': 'Destiny Child Live2D archive with character and costume search'},
      es: {'天命之子 Live2D 模型归档，支持角色和服装搜索': 'Archivo Live2D de Destiny Child con búsqueda de personajes y trajes'},
      ru: {'天命之子 Live2D 模型归档，支持角色和服装搜索': 'Архив Live2D Destiny Child с поиском персонажей и костюмов'},
      ar: {'天命之子 Live2D 模型归档，支持角色和服装搜索': 'أرشيف Live2D للعبة Destiny Child مع بحث عن الشخصيات والأزياء'},
    },
    async data() {
      if (cached && Date.now() - cached.time < 10 * 60 * 1000) return cached.value;
      const response = this.http.ensureOk(await this.http.get(BASE + '/data/models.json'));
      const rows = response.json();
      if (!Array.isArray(rows) || !rows.length) throw Park.error('PARSE', '媒体数据无效');
      const valid = rows.filter(row => Array.isArray(row) && /^[a-z0-9_]{1,100}$/i.test(row[0] || '') && /[kg]/.test(row[4] || ''));
      if (!valid.length) throw Park.error('PARSE', '媒体数据无效');
      cached = {time: Date.now(), value: valid};
      return valid;
    },
    async results(page, keyword) {
      page = pageNumber(page);
      const q = String(keyword || '').trim().toLowerCase();
      if (q.length > 200) throw Park.error('CONFIG', '访问受限');
      const rows = (await this.data()).filter(row => !q || row.slice(0, 3).some(value => String(value || '').toLowerCase().includes(q)));
      const offset = (page - 1) * PAGE_SIZE;
      return {items: rows.slice(offset, offset + PAGE_SIZE).map(item), page, hasNext: offset + PAGE_SIZE < rows.length};
    },
    async feed(key, {page = 1} = {}) {
      if (key !== 'all') throw Park.error('CONFIG', '访问受限');
      return this.results(page, '');
    },
    async search({keyword, page = 1} = {}) { return this.results(page, keyword); },
    async detail(value) {
      const id = validId(value), row = (await this.data()).find(entry => entry[0] === id);
      if (!row) throw Park.error('NOT_FOUND', '内容不存在');
      return item(row);
    },
    async interactiveViewer(value) {
      const detail = await this.detail(value);
      return {url: detail.url, storageId: 'viewer'};
    },
  });
})();
