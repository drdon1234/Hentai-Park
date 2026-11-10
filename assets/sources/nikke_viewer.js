(function () {
  'use strict';
  const URL = "https://nikke-db.pages.dev/visualiser";
  let checkedAt = 0;
  const work = {id: 'viewer', title: "Nikke Database", cover: '', url: URL,
    mediaKind: 'interactive', contentDomain: 'interactiveArt'};
  Park.register({
    key: "nikke_viewer", name: "Nikke Database", version: '0.0.2', minAppVersion: '1.12.1',
    interactiveEntry: 'viewer',
    type: 'interactive', category: 'interactiveArt', color: "#E584A1",
    description: "NIKKE 互动立绘，在查看器内选择角色", homepage: "https://nikke-db.pages.dev", language: 'multi',
    domains: ["nikke-db.pages.dev"], network: {mode: 'auto', vpnHint: true},
    defaultFeed: 'all', feeds: [{key: 'all', label: '全部'}],
    i18n: {
      "zh-Hant": {"NIKKE 互动立绘，在查看器内选择角色": "NIKKE 互動立繪，在檢視器內選擇角色"},
      "ja": {"NIKKE 互动立绘，在查看器内选择角色": "NIKKE のインタラクティブ立ち絵、ビューアでキャラクターを選択"},
      "ko": {"NIKKE 互动立绘，在查看器内选择角色": "NIKKE 인터랙티브 일러스트, 뷰어에서 캐릭터 선택"},
      "en": {"NIKKE 互动立绘，在查看器内选择角色": "Interactive NIKKE art; choose a character in the viewer"},
      "es": {"NIKKE 互动立绘，在查看器内选择角色": "Ilustraciones interactivas de NIKKE; elige el personaje en el visor"},
      "ru": {"NIKKE 互动立绘，在查看器内选择角色": "Интерактивные иллюстрации NIKKE: выберите персонажа в просмотрщике"},
      "ar": {"NIKKE 互动立绘，在查看器内选择角色": "رسوم NIKKE تفاعلية؛ اختر الشخصية في العارض"}
    },
    async check() {
      if (Date.now() - checkedAt < 10 * 60 * 1000) return;
      const response = this.http.ensureOk(await this.http.get(URL));
      if (!/<html[\s>]/i.test(response.body)) throw Park.error('PARSE', '媒体数据无效');
      checkedAt = Date.now();
    },
    async feed(key, {page = 1} = {}) {
      if (key !== 'all' || !Number.isSafeInteger(Number(page)) || Number(page) < 1) throw Park.error('CONFIG', '访问受限');
      await this.check();
      return {items: Number(page) === 1 ? [work] : [], page: Number(page), hasNext: false};
    },
    async detail(id) {
      if (id !== 'viewer') throw Park.error('NOT_FOUND', '内容不存在');
      await this.check();
      return work;
    },
    async interactiveViewer(id) {
      await this.detail(id);
      return {url: URL, storageId: 'viewer'};
    },
  });
})();
