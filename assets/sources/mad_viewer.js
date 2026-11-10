(function () {
  'use strict';
  const BASE = 'https://mad.altterisk.cc';
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
  function item(skin, character, icons) {
    const id = validId(skin.key);
    const name = character?.nameEn || character?.name || skin.character || id;
    const thumbnail = `Thumbnail_${id.toUpperCase()}`;
    const icon = [character?.iconPath, `Icon_${skin.character}`].find(value => icons.char.has(value));
    const cover = icons.skin.has(thumbnail) ? `${BASE}/icons/skin/${thumbnail}.webp`
      : icon && /^[a-z0-9_]+$/i.test(icon) ? `${BASE}/icons/char/${icon}.webp` : '';
    return {
      id, title: `${name} · ${skin.kind}`, subtitle: id,
      cover,
      url: `${BASE}/viewer/?skin=${encodeURIComponent(id)}`,
      mediaKind: 'interactive', contentDomain: 'interactiveArt',
    };
  }
  Park.register({
    key: 'mad_viewer', name: 'MAD Viewer', version: '0.0.1', minAppVersion: '1.12.1',
    type: 'interactive', category: 'interactiveArt', color: '#C77C9C',
    description: 'MAke Drama 互动立绘，支持服装和动作',
    homepage: BASE, language: 'multi', domains: ['altterisk.cc'], network: {mode: 'auto', vpnHint: true},
    defaultFeed: 'all', feeds: [{key: 'all', label: '全部'}],
    linkPatterns: ['https?://mad\\.altterisk\\.cc/viewer/?\\?(?:[^#]*&)?skin=([a-z0-9_]+)'],
    idPattern: '^((?:af|ds|pl|dm|st)_[a-z0-9_]+)$', idExample: 'af_ch0009',
    i18n: {
      'zh-Hant': {'MAke Drama 互动立绘，支持服装和动作': 'MAke Drama 互動立繪，支援服裝和動作'},
      ja: {'MAke Drama 互动立绘，支持服装和动作': 'MAke Drama のインタラクティブ立ち絵、衣装とアニメーションに対応'},
      ko: {'MAke Drama 互动立绘，支持服装和动作': 'MAke Drama 인터랙티브 일러스트, 의상과 동작 지원'},
      en: {'MAke Drama 互动立绘，支持服装和动作': 'Interactive MAke Drama art with costumes and animations'},
      es: {'MAke Drama 互动立绘，支持服装和动作': 'Ilustraciones interactivas de MAke Drama con trajes y animaciones'},
      ru: {'MAke Drama 互动立绘，支持服装和动作': 'Интерактивные иллюстрации MAke Drama с костюмами и анимацией'},
      ar: {'MAke Drama 互动立绘，支持服装和动作': 'رسوم MAke Drama تفاعلية مع الأزياء والحركات'},
    },
    async data() {
      if (cached && Date.now() - cached.time < 10 * 60 * 1000) return cached.value;
      const paths = ['/data/skin_list.json', '/data/characters.json', '/data/events.json', '/data/icons.json'];
      const values = [];
      for (const path of paths) {
        const response = this.http.ensureOk(await this.http.get(BASE + path));
        if (response.body.length > 5 * 1024 * 1024) throw Park.error('PARSE', '媒体数据无效');
        values.push(response.json());
      }
      const [skinData, charData, events, iconData] = values;
      if (!Array.isArray(skinData?.skins) || !charData?.characters || !Array.isArray(events?.banners) ||
          !Array.isArray(iconData?.groups?.char) || !Array.isArray(iconData?.groups?.skin)) {
        throw Park.error('PARSE', '媒体数据无效');
      }
      const icons = {char: new Set(iconData.groups.char), skin: new Set(iconData.groups.skin)};
      const banned = new Set(), started = new Set();
      for (const banner of events.banners) {
        for (const code of banner.codes || []) {
          banned.add(code);
          if (Date.parse(banner.start) <= Date.now()) started.add(code);
        }
      }
      const rows = skinData.skins.filter(skin => {
        const c = charData.characters[skin.character];
        return /^[a-z0-9_]{1,100}$/i.test(skin.key || '') && !c?.unreleased &&
          !(banned.has(skin.character) && !started.has(skin.character));
      }).map(skin => ({skin, character: charData.characters[skin.character], icons}));
      if (!rows.length) throw Park.error('PARSE', '媒体数据无效');
      cached = {time: Date.now(), value: rows};
      return rows;
    },
    async results(page, keyword) {
      page = pageNumber(page);
      const q = String(keyword || '').trim().toLowerCase();
      if (q.length > 200) throw Park.error('CONFIG', '访问受限');
      const rows = (await this.data()).filter(({skin, character}) => !q ||
        [skin.key, skin.character, character?.name, character?.nameEn].some(value => String(value || '').toLowerCase().includes(q)));
      const offset = (page - 1) * PAGE_SIZE;
      return {items: rows.slice(offset, offset + PAGE_SIZE).map(({skin, character, icons}) => item(skin, character, icons)),
        page, hasNext: offset + PAGE_SIZE < rows.length};
    },
    async feed(key, {page = 1} = {}) {
      if (key !== 'all') throw Park.error('CONFIG', '访问受限');
      return this.results(page, '');
    },
    async search({keyword, page = 1} = {}) { return this.results(page, keyword); },
    async detail(value) {
      const id = validId(value);
      const row = (await this.data()).find(entry => entry.skin.key === id);
      if (!row) throw Park.error('NOT_FOUND', '内容不存在');
      return item(row.skin, row.character, row.icons);
    },
    async interactiveViewer(value) {
      const detail = await this.detail(value);
      return {url: detail.url, storageId: 'viewer'};
    },
  });
})();
