Park.register({
  key: 'iqdb', name: 'IQDB', version: '0.0.1', apiVersion: 1,
  type: 'comic', category: 'other', homepage: 'https://iqdb.org/',
  description: '插画出处反搜；高峰期可能需要排队',
  domains: ['iqdb.org'], network: { vpnHint: true },
  i18n: {
    "zh-Hant": {
      "插画出处反搜；高峰期可能需要排队": "插畫出處反搜；尖峰時段可能需要排隊"
    },
    "ja": {
      "插画出处反搜；高峰期可能需要排队": "イラストの出典を逆検索。混雑時は順番待ちの場合があります"
    },
    "ko": {
      "插画出处反搜；高峰期可能需要排队": "일러스트 출처 역검색, 혼잡 시 대기 가능"
    },
    "en": {
      "插画出处反搜；高峰期可能需要排队": "Find illustration sources; requests may queue at busy times"
    },
    "es": {
      "插画出处反搜；高峰期可能需要排队": "Busca el origen de ilustraciones; puede haber cola en horas punta"
    },
    "ru": {
      "插画出处反搜；高峰期可能需要排队": "Поиск источников иллюстраций; при нагрузке возможна очередь"
    },
    "ar": {
      "插画出处反搜；高峰期可能需要排队": "البحث عن مصادر الرسوم؛ قد تكون هناك قائمة انتظار عند الازدحام"
    }
  },
  async reverseSearch(image) {
    const response = await this.http.post('https://iqdb.org/', {
      multipart: { file: { name: 'file', filename: 'image.png', mimeType: image.mimeType, base64: image.base64 } }, timeout: 80000,
    });
    this.http.ensureOk(response);
    const doc = Park.html.parse(response.body);
    if (!doc.querySelector('#pages') && !/No relevant matches|No matches found/i.test(response.body)) throw Park.error('PARSE', '反搜服务返回无效数据');
    const results = [];
    for (const table of doc.querySelectorAll('#pages table')) {
      if (!/^(Best match|Additional match)$/.test(Park.html.text(table.querySelector('th')))) continue;
      const score = Number((Park.html.text(table).match(/(\d+(?:\.\d+)?)% similarity/) || [])[1]);
      if (!Number.isFinite(score) || score < 75) continue;
      const anchor = table.querySelector('td.image a');
      const href = Park.html.attr(anchor, 'href');
      if (!/^(https?:)?\/\//i.test(href)) continue;
      const url = href.startsWith('//') ? 'https:' + href : href;
      const label = Park.html.text(table.querySelectorAll('tr')[2]) || url;
      const tags = Park.html.attr(table.querySelector('td.image img'), 'alt').replace(/^.*?Tags:\s*/, '').replace(/^\[IMG\]$/, '');
      results.push({ title: label, description: tags, url, similarity: score });
    }
    return results;
  },
});
