(function () {
'use strict';
const absoluteUrl = (value, base = 'https://yandex.com/') => {
  if (typeof value !== 'string' || !/^(https?:)?\/\//i.test(value)) return '';
  let url;
  try { const parsed = new URL(value, base); if (parsed.username || parsed.password) return ''; url = parsed.href; } catch (_) { return ''; }
  return /^https?:\/\//i.test(url) ? url : '';
};

Park.register({
  i18n: {
    "zh-Hant": {
      "通用图片反搜；可查找网页出处与相似图片": "通用圖片反搜；可查找網頁出處與相似圖片"
    },
    "ja": {
      "通用图片反搜；可查找网页出处与相似图片": "画像の逆検索。掲載ページや類似画像を検索"
    },
    "ko": {
      "通用图片反搜；可查找网页出处与相似图片": "이미지 역검색으로 출처 페이지와 유사 이미지 검색"
    },
    "en": {
      "通用图片反搜；可查找网页出处与相似图片": "Reverse image search for source pages and similar images"
    },
    "es": {
      "通用图片反搜；可查找网页出处与相似图片": "Búsqueda inversa de páginas de origen e imágenes similares"
    },
    "ru": {
      "通用图片反搜；可查找网页出处与相似图片": "Обратный поиск источников и похожих изображений"
    },
    "ar": {
      "通用图片反搜；可查找网页出处与相似图片": "بحث عكسي عن صفحات المصدر والصور المشابهة"
    }
  },
  key: 'yandex', name: 'Yandex', version: '0.0.1', apiVersion: 1,
  type: 'comic', category: 'other', reverseSearchCategory: 'general',
  homepage: 'https://yandex.com/images/',
  description: '通用图片反搜；可查找网页出处与相似图片',
  domains: ['yandex.com'], network: { vpnHint: true },
  async reverseSearch(image) {
    const response = await this.http.post('https://yandex.com/images/search', {
      params: { rpt: 'imageview', cbir_page: 'sites' },
      multipart: { fields: { prg: '1' }, file: { name: 'upfile', filename: 'image.png', mimeType: image.mimeType, base64: image.base64 } },
      timeout: 80000,
    });
    this.http.ensureOk(response);
    const doc = Park.html.parse(response.body);
    const root = doc.querySelector('div.Root[id^="ImagesApp-"]');
    const stateText = Park.html.attr(root, 'data-state');
    if (!stateText) throw Park.error('PARSE', '反搜服务返回无效数据');
    let state;
    try { state = JSON.parse(stateText); } catch (_) { throw Park.error('PARSE', '反搜服务返回无效数据'); }
    const sites = state?.initialState?.cbirSites?.sites;
    if (!Array.isArray(sites) || sites.length > 200) throw Park.error('PARSE', '反搜服务返回无效数据');
    const results = [];
    for (const site of sites) {
      if (!site || typeof site !== 'object') throw Park.error('PARSE', '反搜服务返回无效数据');
      const title = typeof site.title === 'string' ? Park.html.strip(site.title) : '';
      const url = absoluteUrl(site.url);
      if (!title || !url) throw Park.error('PARSE', '反搜服务返回无效数据');
      const thumbnail = absoluteUrl(site.thumb?.url, 'https://yandex.com/');
      const original = site.originalImage && typeof site.originalImage === 'object' ? site.originalImage : {};
      const originalUrl = absoluteUrl(original.url);
      results.push({
        title, url,
        description: String(site.description || site.domain || '').trim() || undefined,
        images: [...new Set([thumbnail, originalUrl].filter(Boolean))].map(url => ({url})),
        details: { title: site.title, domain: site.domain, description: site.description, originalImage: {width: original.width, height: original.height, url: originalUrl}, thumb: thumbnail },
      });
    }
    return results;
  },
});
})();
