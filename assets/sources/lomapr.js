(function () {
  'use strict';
  const BASE = 'https://lo.altterisk.cc';
  const DATA = 'https://lo-assets.altterisk.cc/global/split';
  const PAGE_SIZE = 40;
  let cached;
  function pageNumber(value) {
    const page = Number(value || 1);
    if (!Number.isSafeInteger(page) || page < 1 || page > 100000) throw Park.error('CONFIG', '访问受限');
    return page;
  }
  function validId(value) {
    const id = String(value || '');
    if (!/^Char_[a-z0-9_]{1,100}$/i.test(id)) throw Park.error('NOT_FOUND', '内容不存在');
    return id;
  }
  function item(id, unit) {
    const icon = unit.icon || '';
    return {id, title: unit.canonName || unit.profile?.engName || id,
      cover: /^[a-z0-9_]+$/i.test(icon) ? `${BASE}/images/_w/icons/${icon}.webp` : '',
      url: `${BASE}/units/detail/?id=${encodeURIComponent(id)}&tab=skin`,
      mediaKind: 'interactive', contentDomain: 'interactiveArt'};
  }
  Park.register({
    key: 'lomapr', name: 'LOMapR', version: '0.0.1', minAppVersion: '1.12.1',
    type: 'interactive', category: 'interactiveArt', color: '#D19977',
    description: 'Last Origin 角色立绘，在角色页选择 Skin 查看',
    homepage: BASE, language: 'multi', domains: ['altterisk.cc'], network: {mode: 'auto', vpnHint: true},
    defaultFeed: 'all', feeds: [{key: 'all', label: '全部'}],
    linkPatterns: ['https?://lo\\.altterisk\\.cc/units/detail/?\\?(?:[^#]*&)?id=(Char_[A-Za-z0-9_]+)'],
    idPattern: '^(Char_[A-Za-z0-9_]+)$', idExample: 'Char_BR_PA00EL_N',
    i18n: {
      'zh-Hant': {'Last Origin 角色立绘，在角色页选择 Skin 查看': 'Last Origin 角色立繪，在角色頁選擇 Skin 查看'},
      ja: {'Last Origin 角色立绘，在角色页选择 Skin 查看': 'Last Origin の立ち絵、キャラクターページで Skin を選択'},
      ko: {'Last Origin 角色立绘，在角色页选择 Skin 查看': 'Last Origin 캐릭터 일러스트, 캐릭터 페이지에서 Skin 선택'},
      en: {'Last Origin 角色立绘，在角色页选择 Skin 查看': 'Last Origin character art; select Skin on the character page'},
      es: {'Last Origin 角色立绘，在角色页选择 Skin 查看': 'Ilustraciones de Last Origin; selecciona Skin en la página del personaje'},
      ru: {'Last Origin 角色立绘，在角色页选择 Skin 查看': 'Иллюстрации Last Origin: выберите Skin на странице персонажа'},
      ar: {'Last Origin 角色立绘，在角色页选择 Skin 查看': 'رسوم شخصيات Last Origin؛ اختر Skin في صفحة الشخصية'},
    },
    async data() {
      if (cached && Date.now() - cached.time < 10 * 60 * 1000) return cached.value;
      const unitsResponse = this.http.ensureOk(await this.http.get(DATA + '/units/unit_list.json'));
      const skinsResponse = this.http.ensureOk(await this.http.get(DATA + '/skins/skin_list.json'));
      const units = unitsResponse.json(), skins = skinsResponse.json();
      if (!units || Array.isArray(units) || !Array.isArray(skins)) throw Park.error('PARSE', '媒体数据无效');
      const animated = new Set(skins.filter(s => s.viewerKind === 'skinned' || s.viewerKind === 'spine').map(s => s.unitId));
      const rows = Object.entries(units).filter(([id, unit]) =>
        /^Char_[a-z0-9_]{1,100}$/i.test(id) && unit.body === 'Bioroid' && animated.has(id));
      if (!rows.length) throw Park.error('PARSE', '媒体数据无效');
      cached = {time: Date.now(), value: rows};
      return rows;
    },
    async results(page, keyword) {
      page = pageNumber(page);
      const q = String(keyword || '').trim().toLowerCase();
      if (q.length > 200) throw Park.error('CONFIG', '访问受限');
      const rows = (await this.data()).filter(([id, unit]) => !q ||
        [id, unit.canonName, unit.profile?.engName].some(value => String(value || '').toLowerCase().includes(q)));
      const offset = (page - 1) * PAGE_SIZE;
      return {items: rows.slice(offset, offset + PAGE_SIZE).map(([id, unit]) => item(id, unit)),
        page, hasNext: offset + PAGE_SIZE < rows.length};
    },
    async feed(key, {page = 1} = {}) {
      if (key !== 'all') throw Park.error('CONFIG', '访问受限');
      return this.results(page, '');
    },
    async search({keyword, page = 1} = {}) { return this.results(page, keyword); },
    async detail(value) {
      const id = validId(value), row = (await this.data()).find(([key]) => key === id);
      if (!row) throw Park.error('NOT_FOUND', '内容不存在');
      return item(row[0], row[1]);
    },
    async interactiveViewer(value) {
      const detail = await this.detail(value);
      return {url: detail.url, storageId: 'viewer'};
    },
  });
})();
