(function () {
'use strict';
const bingUrl = (value, base = 'https://www.bing.com/') => {
  if (typeof value !== 'string' || !/^(https?:)?\/\//i.test(value)) return '';
  try { const url = new URL(value, base); return !url.username && !url.password && /^https?:\/\//i.test(url.href) ? url.href : ''; } catch (_) { return ''; }
};
const bingMultipart = async (fields) => {
  const boundary = 'Park' + await Park.crypto.uuid();
  let body = '';
  for (const [name, value] of Object.entries(fields)) body += '--' + boundary + '\r\nContent-Disposition: form-data; name="' + name + '"\r\n\r\n' + String(value) + '\r\n';
  body += '--' + boundary + '--\r\n';
  return { body, headers: { 'Content-Type': 'multipart/form-data; boundary=' + boundary } };
};

Park.register({
  i18n: {
    "zh-Hant": {
      "通用图片反搜；提供网页出处与视觉相似结果": "通用圖片反搜；提供網頁出處與視覺相似結果",
      "Bing 当前地区未提供图片反搜，请尝试 VPN 或代理": "Bing 目前地區未提供圖片反搜，請嘗試 VPN 或代理"
    },
    "ja": {
      "通用图片反搜；提供网页出处与视觉相似结果": "画像の逆検索。掲載ページと見た目が似た画像を表示",
      "Bing 当前地区未提供图片反搜，请尝试 VPN 或代理": "この地域の Bing は画像の逆検索を提供していません。VPN またはプロキシをお試しください"
    },
    "ko": {
      "通用图片反搜；提供网页出处与视觉相似结果": "이미지 역검색으로 출처 페이지와 시각적으로 유사한 결과 제공",
      "Bing 当前地区未提供图片反搜，请尝试 VPN 或代理": "현재 지역의 Bing은 이미지 역검색을 제공하지 않습니다. VPN 또는 프록시를 사용해 보세요"
    },
    "en": {
      "通用图片反搜；提供网页出处与视觉相似结果": "Reverse image search with source pages and visually similar results",
      "Bing 当前地区未提供图片反搜，请尝试 VPN 或代理": "Bing does not offer reverse image search in this region. Try a VPN or proxy"
    },
    "es": {
      "通用图片反搜；提供网页出处与视觉相似结果": "Búsqueda inversa con páginas de origen y resultados visualmente similares",
      "Bing 当前地区未提供图片反搜，请尝试 VPN 或代理": "Bing no ofrece búsqueda inversa en esta región. Prueba una VPN o un proxy"
    },
    "ru": {
      "通用图片反搜；提供网页出处与视觉相似结果": "Обратный поиск страниц-источников и визуально похожих изображений",
      "Bing 当前地区未提供图片反搜，请尝试 VPN 或代理": "В этом регионе Bing не предоставляет обратный поиск. Попробуйте VPN или прокси"
    },
    "ar": {
      "通用图片反搜；提供网页出处与视觉相似结果": "بحث عكسي مع صفحات المصدر ونتائج متشابهة بصريًا",
      "Bing 当前地区未提供图片反搜，请尝试 VPN 或代理": "لا يوفر Bing البحث العكسي في هذه المنطقة. جرّب VPN أو وكيلًا"
    }
  },
  key: 'bing', name: 'Bing', version: '0.0.1', apiVersion: 1,
  type: 'comic', category: 'other', reverseSearchCategory: 'general',
  homepage: 'https://www.bing.com/images/',
  description: '通用图片反搜；提供网页出处与视觉相似结果',
  domains: ['bing.com'], network: { vpnHint: true },
  parseKnowledge(data) {
    if (!data || !Array.isArray(data.tags)) throw Park.error('PARSE', '反搜服务返回无效数据');
    let recognized = data.tags.length === 0;
    const results = [], add = (item, actionType) => {
      if (!item || typeof item !== 'object') throw Park.error('PARSE', '反搜服务返回无效数据');
      const url = bingUrl(item.hostPageUrl), title = typeof item.name === 'string' ? Park.html.strip(item.name) : '';
      if (!title || !url) throw Park.error('PARSE', '反搜服务返回无效数据');
      const thumbnail = bingUrl(item.thumbnailUrl), image = bingUrl(item.contentUrl);
      results.push({ title, url, images: [...new Set([thumbnail, image].filter(Boolean))].map(url => ({url})), details: { actionType, name: item.name, hostPageUrl: url, contentUrl: image, thumbnailUrl: thumbnail, width: item.width, height: item.height, encodingFormat: item.encodingFormat, datePublished: item.datePublished } });
    };
    for (const tag of data.tags) {
      if (!Array.isArray(tag?.actions)) throw Park.error('PARSE', '反搜服务返回无效数据');
      for (const action of tag.actions) {
        if (!['PagesIncluding', 'VisualSearch'].includes(action?.actionType)) continue;
        recognized = true;
        if (!Array.isArray(action.data?.value)) throw Park.error('PARSE', '反搜服务返回无效数据');
        for (const item of action.data.value) add(item, action.actionType);
      }
    }
    if (!recognized || results.length > 200) throw Park.error('PARSE', '反搜服务返回无效数据');
    return results;
  },
  async reverseSearch(image) {
    const form = await bingMultipart({cbir: 'sbi', imageBin: image.base64});
    const upload = await this.http.post('https://www.bing.com/images/search', {
      params: { view: 'detailv2', iss: 'sbiupload' },
      ...form, timeout: 80000,
    });
    this.http.ensureOk(upload);
    const bcid = /bcid_[A-Za-z0-9.-]{4,200}/.exec(upload.body)?.[0];
    if (!bcid) {
      if (upload.url && new URL(upload.url).hostname === 'cn.bing.com') throw Park.error('BLOCKED', 'Bing 当前地区未提供图片反搜，请尝试 VPN 或代理');
      throw Park.error('PARSE', '反搜服务返回无效数据');
    }
    const request = await bingMultipart({ knowledgeRequest: JSON.stringify({ imageInfo: { imageInsightsToken: bcid, source: 'Gallery' } }) });
    const response = await this.http.post('https://www.bing.com/images/api/custom/knowledge', {
      params: { rshighlight: 'true', textDecorations: 'true', internalFeatures: 'similarproducts,share', nbl: '1', FORM: 'SBIHMP', safeSearch: 'off', mkt: 'en-us', setLang: 'en-us', iss: 'sbi', IID: 'idpins', SFX: '1', insightsToken: bcid },
      headers: { Referer: upload.url || 'https://www.bing.com/images/search?insightsToken=' + bcid, ...request.headers },
      body: request.body, timeout: 80000,
    });
    this.http.ensureOk(response);
    return this.parseKnowledge(response.json());
  },
});
})();
