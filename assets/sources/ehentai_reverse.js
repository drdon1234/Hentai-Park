(function () {
'use strict';
const ehUrl = (value, base = 'https://e-hentai.org/', image = false) => {
  if (typeof value !== 'string' || !value.trim()) return '';
  try { const url = new URL(value, base); return !url.username && !url.password && url.protocol === 'https:' && (!url.port || url.port === '443') && (/(^|\.)e-hentai\.org$/i.test(url.hostname) || (image && /(^|\.)ehgt\.org$/i.test(url.hostname))) ? url.href : ''; } catch (_) { return ''; }
};

Park.register({
  i18n: {
    "zh-Hant": {
      "E-Hentai 识图": "E-Hentai 識圖",
      "成人画廊图片反搜；返回匹配画廊与原站标签": "成人畫廊圖片反搜；傳回相符畫廊與原站標籤"
    },
    "ja": {
      "E-Hentai 识图": "E-Hentai 画像検索",
      "成人画廊图片反搜；返回匹配画廊与原站标签": "成人向けギャラリーの逆検索。一致するギャラリーと元のタグを表示"
    },
    "ko": {
      "E-Hentai 识图": "E-Hentai 이미지 검색",
      "成人画廊图片反搜；返回匹配画廊与原站标签": "성인 갤러리 이미지 역검색, 일치하는 갤러리와 원본 태그 표시"
    },
    "en": {
      "E-Hentai 识图": "E-Hentai Image Search",
      "成人画廊图片反搜；返回匹配画廊与原站标签": "Reverse search adult galleries with matching galleries and original tags"
    },
    "es": {
      "E-Hentai 识图": "E-Hentai Imágenes",
      "成人画廊图片反搜；返回匹配画廊与原站标签": "Búsqueda inversa de galerías para adultos con coincidencias y etiquetas originales"
    },
    "ru": {
      "E-Hentai 识图": "E-Hentai Image Search",
      "成人画廊图片反搜；返回匹配画廊与原站标签": "Обратный поиск галерей для взрослых с исходными тегами"
    },
    "ar": {
      "E-Hentai 识图": "E-Hentai Image Search",
      "成人画廊图片反搜；返回匹配画廊与原站标签": "بحث عكسي في معارض البالغين مع المعارض المطابقة والوسوم الأصلية"
    }
  },
  key: 'ehentai_reverse', name: 'E-Hentai 识图', version: '0.0.1', apiVersion: 1,
  type: 'comic', category: 'other', reverseSearchCategory: 'gallery',
  homepage: 'https://e-hentai.org/',
  description: '成人画廊图片反搜；返回匹配画廊与原站标签',
  domains: ['e-hentai.org'], network: { vpnHint: true },
  parseResults(html) {
    const doc = Park.html.parse(html);
    if (/No hits found|No unfiltered results/i.test(html)) return [];
    const nodes = [...doc.querySelectorAll('.itg tr, .itg > .gl1t, .itg > .gl1e')], results = [];
    if (!nodes.length) throw Park.error('PARSE', '反搜服务返回无效数据');
    for (const node of nodes) {
      const titleNode = node.querySelector('.glink');
      const title = Park.html.text(titleNode);
      const linkNode = titleNode?.closest('a') || node.querySelector('a[href*="/g/"]');
      const url = ehUrl(Park.html.attr(linkNode, 'href'));
      if (!titleNode) continue;
      if (!title || !/^https:\/\/e-hentai\.org\/g\/\d+\/[a-f0-9]+\/$/i.test(url)) throw Park.error('PARSE', '反搜服务返回无效数据');
      const image = node.querySelector('.glthumb img, .gl1e img, .gl3t img');
      const thumbnail = ehUrl(Park.html.attr(image, 'data-src') || Park.html.attr(image, 'src'), 'https://e-hentai.org/', true);
      const tags = [...node.querySelectorAll('.gt[title], .gtl[title]')].map(el => Park.html.attr(el, 'title')).filter(Boolean);
      results.push({ title, url, images: thumbnail ? [{ url: thumbnail }] : [], details: { title, tags, category: Park.html.text(node.querySelector('.cs, .cn')), date: Park.html.text(node.querySelector('[id^="posted"]')) } });
    }
    if (!results.length) throw Park.error('PARSE', '反搜服务返回无效数据');
    if (results.length > 200) throw Park.error('PARSE', '反搜服务返回无效数据');
    return results;
  },
  async reverseSearch(image) {
    if (this._searching) throw Park.error('CONFIG', '反搜请求仍在处理中，请稍后重试');
    this._searching = true;
    try {
      // 原站每三秒允许一次搜索；从上次响应结束计时，避免连续上传触发空响应。
      const delay = Math.max(0, 3100 - (Date.now() - (this._searchEnded || 0)));
      if (delay) await new Promise(resolve => setTimeout(resolve, delay));
      return await this.searchImage(image);
    } finally {
      this._searchEnded = Date.now();
      this._searching = false;
    }
  },
  async searchImage(image) {
    const response = await this.http.post('https://upld.e-hentai.org/image_lookup.php', {
      multipart: { fields: { f_sfile: 'File Search', fs_similar: 'on' }, file: { name: 'sfile', filename: 'image.png', mimeType: image.mimeType, base64: image.base64 } },
      timeout: 90000, followRedirects: false,
    });
    // 上传接口未在 Location 中保留勾选项，结果页须显式带上已验证的相似查找参数。
    if ([302, 303].includes(response.status)) {
      const location = ehUrl(response.headers.location);
      if (!location) throw Park.error('PARSE', '反搜服务返回无效数据');
      const url = new URL(location);
      if (url.hostname !== 'e-hentai.org' || url.pathname !== '/' || !/^[a-f0-9]{40}$/i.test(url.searchParams.get('f_shash') || '')) throw Park.error('PARSE', '反搜服务返回无效数据');
      url.searchParams.set('fs_similar', 'on');
      const result = await this.http.get(url.href, {timeout:90000});
      this.http.ensureOk(result);
      return this.parseResults(result.body);
    }
    this.http.ensureOk(response);
    return this.parseResults(response.body);
  },
});
})();
