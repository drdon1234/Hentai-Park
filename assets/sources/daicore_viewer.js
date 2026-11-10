(function () {
  'use strict';
  const URL = "https://daicoreviewer.jelosus1.dev/";
  let checkedAt = 0;
  const work = {id: 'viewer', title: "DaiCoreViewer", cover: '', url: URL,
    mediaKind: 'interactive', contentDomain: 'interactiveArt'};
  Park.register({
    key: "daicore_viewer", name: "DaiCoreViewer", version: '0.0.2', minAppVersion: '1.12.1',
    interactiveEntry: 'viewer',
    type: 'interactive', category: 'interactiveArt', color: "#C3877E",
    description: "Daiblos Core 互动立绘，在查看器内选择角色和服装", homepage: "https://daicoreviewer.jelosus1.dev/", language: 'multi',
    domains: ["jelosus1.dev"], network: {mode: 'auto', vpnHint: true},
    defaultFeed: 'all', feeds: [{key: 'all', label: '全部'}],
    i18n: {
      "zh-Hant": {"Daiblos Core 互动立绘，在查看器内选择角色和服装": "Daiblos Core 互動立繪，在檢視器內選擇角色和服裝"},
      "ja": {"Daiblos Core 互动立绘，在查看器内选择角色和服装": "Daiblos Core のインタラクティブ立ち絵、ビューアでキャラクターと衣装を選択"},
      "ko": {"Daiblos Core 互动立绘，在查看器内选择角色和服装": "Daiblos Core 인터랙티브 일러스트, 뷰어에서 캐릭터와 의상 선택"},
      "en": {"Daiblos Core 互动立绘，在查看器内选择角色和服装": "Interactive Daiblos Core art; choose a character and costume in the viewer"},
      "es": {"Daiblos Core 互动立绘，在查看器内选择角色和服装": "Ilustraciones interactivas de Daiblos Core; elige personaje y traje en el visor"},
      "ru": {"Daiblos Core 互动立绘，在查看器内选择角色和服装": "Интерактивные иллюстрации Daiblos Core: выберите персонажа и костюм в просмотрщике"},
      "ar": {"Daiblos Core 互动立绘，在查看器内选择角色和服装": "رسوم Daiblos Core تفاعلية؛ اختر الشخصية والزي في العارض"}
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
