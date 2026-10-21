Park.register({
  key: 'avscan', name: 'AVScan', version: '0.0.4', minAppVersion: '0.9.2', apiVersion: 2,
  type: 'comic', category: 'other', reverseSearchCategory: 'jav', homepage: 'https://avscan.cc/',
  description: 'JAV 截图查番号；显示候选和相关图片，限个人非商业使用',
  domains: ['avscan.cc'], network: { vpnHint: true },
  i18n: {
    "zh-Hant": {
      "JAV 截图查番号；显示候选和相关图片，限个人非商业使用": "JAV 截圖查番號；顯示候選和相關圖片，限個人非商業使用"
    },
    "ja": {
      "JAV 截图查番号；显示候选和相关图片，限个人非商业使用": "JAV画像から品番を検索。候補と関連画像を表示、個人の非商用利用限定"
    },
    "ko": {
      "JAV 截图查番号；显示候选和相关图片，限个人非商业使用": "JAV 장면으로 품번 검색, 후보와 관련 이미지 표시, 개인 비상업 용도 한정"
    },
    "en": {
      "JAV 截图查番号；显示候选和相关图片，限个人非商业使用": "Find JAV catalog numbers from screenshots; candidates and related images, personal non-commercial use"
    },
    "es": {
      "JAV 截图查番号；显示候选和相关图片，限个人非商业使用": "Busca códigos JAV por captura; candidatos e imágenes relacionadas, uso personal no comercial"
    },
    "ru": {
      "JAV 截图查番号；显示候选和相关图片，限个人非商业使用": "Поиск кодов JAV по кадрам; кандидаты и связанные изображения, личное некоммерческое использование"
    },
    "ar": {
      "JAV 截图查番号；显示候选和相关图片，限个人非商业使用": "البحث عن أرقام JAV باللقطات؛ مرشحون وصور ذات صلة، للاستخدام الشخصي غير التجاري"
    }
  },
  async reverseSearch(image) {
    const response = await this.http.post('https://avscan.cc/search', {
      multipart: { file: { name: 'file', filename: 'image.png', mimeType: image.mimeType, base64: image.base64 } }, timeout: 75000,
    });
    this.http.ensureOk(response);
    const data = response.json();
    if (!Array.isArray(data.results)) throw Park.error('PARSE', '反搜服务返回无效数据');
    return data.results.map(row => {
      if (!row || typeof row.best_similarity !== 'number' || !Number.isFinite(row.best_similarity) ||
          row.best_similarity < 0 || row.best_similarity > 100 || typeof row.video_code !== 'string' || !/^[A-Za-z0-9_-]{2,80}$/.test(row.video_code) ||
          !Array.isArray(row.frames)) throw Park.error('PARSE', '反搜服务返回无效数据');
      return {
        title: row.video_code, keyword: row.video_code, similarity: row.best_similarity,
        images: row.frames.map(frame => {
          if (!frame || typeof frame.thumb !== 'string' || !frame.thumb.trim()) throw Park.error('PARSE', '反搜服务返回无效数据');
          const url = new URL(frame.thumb, 'https://avscan.cc/').href;
          if (!/^https:\/\/avscan\.cc\//.test(url)) throw Park.error('PARSE', '反搜服务返回无效数据');
          return { url, label: frame.image_name, similarity: frame.similarity };
        }),
        details: row,
      };
    }).sort((a, b) => b.similarity - a.similarity);
  },
});
