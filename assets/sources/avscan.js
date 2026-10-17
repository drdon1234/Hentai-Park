Park.register({
  key: 'avscan', name: 'AVScan', version: '0.0.1', apiVersion: 1,
  type: 'comic', category: 'other', homepage: 'https://avscan.cc/',
  description: 'JAV 截图查番号；仅显示高分候选，限个人非商业使用',
  domains: ['avscan.cc'], network: { vpnHint: true },
  i18n: {
    "zh-Hant": {
      "JAV 截图查番号；仅显示高分候选，限个人非商业使用": "JAV 截圖查番號；僅顯示高分候選，限個人非商業使用"
    },
    "ja": {
      "JAV 截图查番号；仅显示高分候选，限个人非商业使用": "JAV画像から品番を検索。高スコア候補のみ、個人の非商用利用限定"
    },
    "ko": {
      "JAV 截图查番号；仅显示高分候选，限个人非商业使用": "JAV 장면으로 품번 검색, 높은 점수 후보만 표시, 개인 비상업 용도 한정"
    },
    "en": {
      "JAV 截图查番号；仅显示高分候选，限个人非商业使用": "Find JAV catalog numbers from screenshots; high-score candidates only, personal non-commercial use"
    },
    "es": {
      "JAV 截图查番号；仅显示高分候选，限个人非商业使用": "Busca códigos JAV por captura; solo candidatos de alta puntuación, uso personal no comercial"
    },
    "ru": {
      "JAV 截图查番号；仅显示高分候选，限个人非商业使用": "Поиск кодов JAV по кадрам; только высокие оценки, личное некоммерческое использование"
    },
    "ar": {
      "JAV 截图查番号；仅显示高分候选，限个人非商业使用": "البحث عن أرقام JAV باللقطات؛ مرشحون بدرجات عالية فقط، للاستخدام الشخصي غير التجاري"
    }
  },
  async reverseSearch(image) {
    const response = await this.http.post('https://avscan.cc/search', {
      multipart: { file: { name: 'file', filename: 'image.png', mimeType: image.mimeType, base64: image.base64 } }, timeout: 75000,
    });
    this.http.ensureOk(response);
    const data = response.json();
    if (!Array.isArray(data.results)) throw Park.error('PARSE', '反搜服务返回无效数据');
    return data.results.filter(row => typeof row.best_similarity === 'number' && row.best_similarity >= 90 && row.best_similarity <= 100 && /^[A-Za-z0-9_-]{2,80}$/.test(row.video_code)).slice(0, 10).map(row => ({
      title: row.video_code, keyword: row.video_code, similarity: row.best_similarity,
    }));
  },
});
