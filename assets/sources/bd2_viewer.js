(function () {
  'use strict';
  const URL = "https://jelosus2.github.io/BD2-L2D-Viewer/";
  let checkedAt = 0;
  const work = {id: 'viewer', title: "Brown Dust 2 Viewer", cover: '', url: URL,
    mediaKind: 'interactive', contentDomain: 'interactiveArt'};
  Park.register({
    key: "bd2_viewer", name: "Brown Dust 2 Viewer", version: '0.0.3', minAppVersion: '0.13.0',
    interactiveEntry: 'viewer',
    type: 'interactive', category: 'interactiveArt', color: "#AA85C4",
    description: "棕色尘埃 2 动态立绘，在查看器内选择角色和服装", homepage: "https://jelosus2.github.io/BD2-L2D-Viewer/", language: 'multi',
    domains: ["jelosus2.github.io"], network: {mode: 'auto', vpnHint: true},
    defaultFeed: 'all', feeds: [{key: 'all', label: '全部'}],
    i18n: {
      "zh-Hant": {"棕色尘埃 2 动态立绘，在查看器内选择角色和服装": "棕色塵埃 2 動態立繪，在檢視器內選擇角色和服裝"},
      "ja": {"棕色尘埃 2 动态立绘，在查看器内选择角色和服装": "ブラウンダスト 2 の動く立ち絵、ビューアでキャラクターと衣装を選択"},
      "ko": {"棕色尘埃 2 动态立绘，在查看器内选择角色和服装": "브라운더스트 2 애니메이션 일러스트, 뷰어에서 캐릭터와 의상 선택"},
      "en": {"棕色尘埃 2 动态立绘，在查看器内选择角色和服装": "Animated Brown Dust 2 art; choose a character and costume in the viewer"},
      "es": {"棕色尘埃 2 动态立绘，在查看器内选择角色和服装": "Ilustraciones animadas de Brown Dust 2; elige personaje y traje en el visor"},
      "ru": {"棕色尘埃 2 动态立绘，在查看器内选择角色和服装": "Анимированные иллюстрации Brown Dust 2: выберите персонажа и костюм в просмотрщике"},
      "ar": {"棕色尘埃 2 动态立绘，在查看器内选择角色和服装": "رسوم Brown Dust 2 متحركة؛ اختر الشخصية والزي في العارض"}
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
