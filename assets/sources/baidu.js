(function () {
'use strict';
const baiduUrl = (value, base = 'https://graph.baidu.com/') => {
  if (typeof value !== 'string' || !/^(https?:)?\/\//i.test(value)) return '';
  try { const url = new URL(value, base); return !url.username && !url.password && /^https?:\/\//i.test(url.href) ? url.href : ''; } catch (_) { return ''; }
};
const serviceUrl = value => { const url = baiduUrl(value); return /^https:\/\/graph\.baidu\.com\//.test(url) ? url : ''; };
const baiduCards = (doc) => {
  for (const script of doc.querySelectorAll('script')) {
    const text = script.textContent || '';
    if (!text.includes('window.cardData')) continue;
    const assignment = /window\.cardData\s*=\s*/.exec(text);
    if (!assignment || text[assignment.index + assignment[0].length] !== '[') throw Park.error('PARSE', '反搜服务返回无效数据');
    const start = assignment.index + assignment[0].length;
    let depth = 0, quoted = false, escaped = false;
    for (let i = start; i < text.length; i++) {
      const char = text[i];
      if (quoted) { if (escaped) escaped = false; else if (char === '\\') escaped = true; else if (char === '"') quoted = false; continue; }
      if (char === '"') quoted = true;
      else if (char === '[') depth++;
      else if (char === ']' && --depth === 0) {
        try { return JSON.parse(text.slice(start, i + 1)); } catch (_) { break; }
      }
    }
    throw Park.error('PARSE', '反搜服务返回无效数据');
  }
  return null;
};

Park.register({
  i18n: {
    "zh-Hant": {
      "百度识图": "百度識圖",
      "通用图片反搜；结果覆盖取决于百度识图索引": "通用圖片反搜；結果涵蓋範圍取決於百度識圖索引",
      "百度识图拒绝了图片上传，请稍后重试或更换图片": "百度識圖拒絕了圖片上傳，請稍後重試或更換圖片"
    },
    "ja": {
      "百度识图": "Baidu 画像検索",
      "通用图片反搜；结果覆盖取决于百度识图索引": "画像の逆検索。検索範囲は Baidu のインデックスに依存",
      "百度识图拒绝了图片上传，请稍后重试或更换图片": "Baidu が画像のアップロードを拒否しました。後で再試行するか別の画像をお試しください"
    },
    "ko": {
      "百度识图": "Baidu 이미지 검색",
      "通用图片反搜；结果覆盖取决于百度识图索引": "일반 이미지 역검색, 검색 범위는 Baidu 색인에 따라 달라짐",
      "百度识图拒绝了图片上传，请稍后重试或更换图片": "Baidu에서 이미지 업로드를 거부했습니다. 나중에 다시 시도하거나 다른 이미지를 사용하세요"
    },
    "en": {
      "百度识图": "Baidu Images",
      "通用图片反搜；结果覆盖取决于百度识图索引": "General reverse image search; coverage depends on the Baidu index",
      "百度识图拒绝了图片上传，请稍后重试或更换图片": "Baidu rejected the image upload. Try again later or choose another image"
    },
    "es": {
      "百度识图": "Baidu Imágenes",
      "通用图片反搜；结果覆盖取决于百度识图索引": "Búsqueda inversa general; la cobertura depende del índice de Baidu",
      "百度识图拒绝了图片上传，请稍后重试或更换图片": "Baidu rechazó la imagen. Inténtalo más tarde o elige otra imagen"
    },
    "ru": {
      "百度识图": "Baidu Images",
      "通用图片反搜；结果覆盖取决于百度识图索引": "Обратный поиск изображений; охват зависит от индекса Baidu",
      "百度识图拒绝了图片上传，请稍后重试或更换图片": "Baidu отклонил загрузку. Повторите позже или выберите другое изображение"
    },
    "ar": {
      "百度识图": "Baidu Images",
      "通用图片反搜；结果覆盖取决于百度识图索引": "بحث عكسي عام؛ تعتمد التغطية على فهرس Baidu",
      "百度识图拒绝了图片上传，请稍后重试或更换图片": "رفض Baidu رفع الصورة. أعد المحاولة لاحقًا أو اختر صورة أخرى"
    }
  },
  key: 'baidu', name: '百度识图', version: '0.0.1', apiVersion: 1,
  type: 'comic', category: 'other', reverseSearchCategory: 'general',
  homepage: 'https://graph.baidu.com/',
  description: '通用图片反搜；结果覆盖取决于百度识图索引',
  domains: ['baidu.com'],
  parseResults(data) {
    if (!Array.isArray(data)) throw Park.error('PARSE', '反搜服务返回无效数据');
    if (data.some(card => card?.cardName === 'noresult')) return [];
    const cards = [];
    for (const card of data) {
      if (!card || typeof card !== 'object') continue;
      if (!['same','simipic'].includes(card.cardName)) continue;
      const list = card?.tplData?.list;
      if (!Array.isArray(list)) throw Park.error('PARSE', '反搜服务返回无效数据');
      cards.push(...list);
    }
    if (cards.length > 200) throw Park.error('PARSE', '反搜服务返回无效数据');
    return cards.map(item => {
      if (!item || typeof item !== 'object') throw Park.error('PARSE', '反搜服务返回无效数据');
      if (item.title != null && typeof item.title !== 'string' && !(Array.isArray(item.title) && item.title.every(value => typeof value === 'string'))) throw Park.error('PARSE', '反搜服务返回无效数据');
      const url = baiduUrl(item.url || item.fromUrl, 'https://www.baidu.com/');
      // 当前相似图接口不再返回网页标题，直接显示真实出处 URL，不推断作品名。
      const title = Park.html.strip(Array.isArray(item.title) ? String(item.title[0] || '') : String(item.title || '')) || url;
      if (!url) throw Park.error('PARSE', '反搜服务返回无效数据');
      const thumbnail = baiduUrl(item.image_src || item.thumbUrl, 'https://www.baidu.com/');
      return { title, url, images: thumbnail ? [{ url: thumbnail }] : [], details: { title: item.title, url, image: thumbnail, source: String(item.site_name || item.from || '') } };
    });
  },
  async reverseSearch(image) {
    const upload = await this.http.post('https://graph.baidu.com/upload', {
      headers: {'Acs-Token':'', Referer:'https://graph.baidu.com/', Origin:'https://graph.baidu.com'},
      multipart: { fields: { from: 'pc' }, file: { name: 'image', filename: 'image.png', mimeType: image.mimeType, base64: image.base64 } },
      timeout: 80000,
    });
    this.http.ensureOk(upload);
    let payload;
    try { payload = upload.json(); } catch (_) { throw Park.error('PARSE', '反搜服务返回无效数据'); }
    if (payload?.status === 1 && payload?.msg === 'Reject') throw Park.error('BLOCKED', '百度识图拒绝了图片上传，请稍后重试或更换图片');
    if (payload?.status !== 0) throw Park.error('PARSE', '反搜服务返回无效数据');
    const resultUrl = serviceUrl(payload?.data?.url);
    if (!resultUrl) throw Park.error('PARSE', '反搜服务返回无效数据');
    const result = await this.http.get(resultUrl, { timeout: 80000 });
    this.http.ensureOk(result);
    const cards = baiduCards(Park.html.parse(result.body));
    if (cards === null) throw Park.error('PARSE', '反搜服务返回无效数据');
    if (cards.some(card => card?.cardName === 'noresult')) return [];
    const similar = cards.find(card => card?.cardName === 'simipic')?.tplData?.firstUrl;
    if (similar) {
      const nextUrl = serviceUrl(similar);
      if (!nextUrl) throw Park.error('PARSE', '反搜服务返回无效数据');
      const next = await this.http.get(nextUrl, { timeout: 80000 });
      this.http.ensureOk(next);
      const more = next.json();
      if (!Array.isArray(more?.data?.list)) throw Park.error('PARSE', '反搜服务返回无效数据');
      return this.parseResults([{ cardName: 'same', tplData: { list: cards.find(card => card?.cardName === 'same')?.tplData?.list || [] } }, {cardName:'simipic',tplData:{list:more.data.list}}]);
    }
    if (!cards.some(card => ['same','simipic','noresult'].includes(card?.cardName))) throw Park.error('PARSE', '反搜服务返回无效数据');
    return this.parseResults(cards);
  },
});
})();
