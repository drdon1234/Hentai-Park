Park.register({
  key: 'iqdb', name: 'IQDB', version: '0.0.4', minAppVersion: '0.9.2', apiVersion: 2,
  type: 'comic', category: 'other', reverseSearchCategory: 'gallery', homepage: 'https://iqdb.org/',
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
    for (const table of doc.querySelectorAll('#pages table, #more1 table, #more2 table')) {
      const anchor = table.querySelector('td.image a');
      if (!anchor) continue;
      const score = Number((Park.html.text(table).match(/(\d+(?:\.\d+)?)% similarity/) || [])[1]);
      if (!Number.isFinite(score) || score < 0 || score > 100) throw Park.error('PARSE', '反搜服务返回无效数据');
      const href = Park.html.attr(anchor, 'href');
      if (!/^(https?:)?\/\//i.test(href)) throw Park.error('PARSE', '反搜服务返回无效数据');
      const url = href.startsWith('//') ? 'https:' + href : href;
      const label = Park.html.text(table.querySelectorAll('tr')[2]) || url;
      const tags = Park.html.attr(table.querySelector('td.image img'), 'alt').replace(/^.*?Tags:\s*/, '').replace(/^\[IMG\]$/, '');
      const thumbnail = Park.html.attr(table.querySelector('td.image img'), 'src');
      const links = Array.from(table.querySelectorAll('a[href]')).map(a => ({
        label: Park.html.text(a) || label,
        url: new URL(Park.html.attr(a, 'href'), 'https://iqdb.org/').href,
      })).filter(link => /^https?:\/\//i.test(link.url));
      results.push({
        title: label, description: tags, url, similarity: score,
        images: thumbnail ? [{ url: new URL(thumbnail, 'https://iqdb.org/').href }] : [],
        details: {
          matchType: Park.html.text(table.querySelector('th')) || 'Other results',
          metadata: Park.html.text(table), tags, links,
        },
      });
    }
    if (!results.length && !/No relevant matches|No matches found/i.test(response.body)) throw Park.error('PARSE', '反搜服务返回无效数据');
    return results.sort((a, b) => b.similarity - a.similarity);
  },
});
