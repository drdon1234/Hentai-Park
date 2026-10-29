Park.register({
  key: 'google_lens', name: 'Google Lens', version: '0.0.8', minAppVersion: '0.9.2', apiVersion: 2,
  type: 'comic', category: 'other', reverseSearchCategory: 'general', homepage: 'https://lens.google.com/',
  description: '综合图片反搜；在应用内浏览器上传并查找完全匹配出处',
  domains: ['google.com'], network: { vpnHint: true },
  i18n: {
    'zh-Hant': { '综合图片反搜；在应用内浏览器上传并查找完全匹配出处': '綜合圖片反搜；在應用程式內瀏覽器上傳並查找完全相符出處' },
    en: { '综合图片反搜；在应用内浏览器上传并查找完全匹配出处': 'General reverse image search; upload in the in-app browser and find exact sources' },
    ja: { '综合图片反搜；在应用内浏览器上传并查找完全匹配出处': '総合画像検索。アプリ内ブラウザでアップロードし、完全一致の出典を検索' },
    ko: { '综合图片反搜；在应用内浏览器上传并查找完全匹配出处': '종합 이미지 역검색, 앱 내 브라우저에서 업로드하여 정확한 출처 검색' },
    es: { '综合图片反搜；在应用内浏览器上传并查找完全匹配出处': 'Búsqueda inversa general; sube la imagen en el navegador integrado y busca fuentes exactas' },
    ru: { '综合图片反搜；在应用内浏览器上传并查找完全匹配出处': 'Обратный поиск изображений: загрузка во встроенном браузере и поиск точных источников' },
    ar: { '综合图片反搜；在应用内浏览器上传并查找完全匹配出处': 'بحث عكسي شامل؛ ارفع الصورة في المتصفح المدمج للعثور على مصادر مطابقة' },
  },
  reverseSearch() {
    return { browser: {
      url: 'https://www.google.com/?hl=en',
      uploadUrl: 'https://lens.google.com/v3/upload?hl=en&re=df&stcs=' + Date.now() + '&vpw=1920&vph=1080&ep=subb',
      fileField: 'encoded_image', resultPath: '/search', resultQuery: 'vsrid',
      resultParams: { udm: '48', hl: 'en' },
      resultSelector: '#rso a[href], #search a[href^="/goto?"], #search a[href^="/url?"], #search a[href^="/imgres?"], #search a[href^="http"]',
      emptySelector: 'body', emptyText: 'No matches for your search',
    } };
  },
  async reverseSearchResult(page) {
    const parsed = Park.html.parse(page.html);
    // HTML 含不可见的脚本和 noscript 文案，不能据此判定正常结果页失效。
    for (const node of parsed.querySelectorAll('script, style, noscript, template')) node.remove();
    const text = Park.html.text(parsed.querySelector('body') || parsed.documentElement);
    if (!/^https:\/\/www\.google\.com\/search\?/.test(page.url) || !/[?&]vsrid=/.test(page.url)) {
      throw Park.error('PARSE', '反搜服务返回无效数据');
    }
    if (/unusual traffic|expired visual search|enable javascript/i.test(text)) {
      throw Park.error('PARSE', '反搜服务返回无效数据');
    }
    const candidates = [], seen = new Map();
    for (const anchor of parsed.querySelectorAll('#rso a[href], #search a[href]')) {
      const raw = Park.html.attr(anchor, 'href');
      const thumbnail = anchor.querySelector('img');
      const title = (Park.html.text(anchor) || Park.html.attr(anchor, 'aria-label') || Park.html.attr(thumbnail, 'alt')).trim();
      if (title.length > 4096) throw Park.error('PARSE', '反搜服务返回无效数据');
      let url = '', redirect = '';
      if (/^\/(goto|url|imgres)\?/.test(raw)) {
        for (const name of ['imgrefurl', 'url', 'q']) {
          const value = (raw.match(new RegExp('[?&]' + name + '=([^&]+)')) || [])[1];
          if (!value) continue;
          let decoded;
          try { decoded = decodeURIComponent(value.replace(/\+/g, ' ')); } catch (_) { continue; }
          if (/^https?:\/\//i.test(decoded)) { url = decoded; break; }
        }
        if (!url) redirect = 'https://www.google.com' + raw;
      } else if (/^https?:\/\//i.test(raw)) { url = raw; }
      else continue;
      if (url && (!/^https?:\/\/(?![^/]*@)[^/\s?#]+(?:[/?#]|$)/i.test(url) ||
          /^https?:\/\/(?:[^/]+\.)?google\.com(?:[/:?#]|$)/i.test(url))) continue;
      const key = url || redirect;
      const image = Park.html.attr(thumbnail, 'src') || Park.html.attr(thumbnail, 'data-src');
      if (seen.has(key)) {
        const existing = seen.get(key);
        if (image && !existing.images.includes(image)) existing.images.push(image);
        if (title && !existing.titles.includes(title)) existing.titles.push(title);
        continue;
      }
      const candidate = { title: title || key, url, redirect, images: image ? [image] : [], titles: title ? [title] : [] };
      seen.set(key, candidate); candidates.push(candidate);
      if (candidates.length > 1000) throw Park.error('PARSE', '反搜服务返回无效数据');
    }
    if (!candidates.length) {
      if (/No matches for your search|No exact matches found|No results found|No matching images found|couldn't find any results/i.test(text)) return [];
      throw Park.error('PARSE', '反搜服务返回无效数据');
    }
    // 已含出处的链接直接显示，跳板解析留给“加载全部”，不阻塞首批结果。
    const direct = candidates.filter(candidate => candidate.url);
    const ordered = [...direct, ...candidates.filter(candidate => !candidate.url)];
    let matches = [], offset = 0, failure;
    while (offset < ordered.length && !matches.length) {
      const batch = offset < direct.length ? Math.min(20, direct.length - offset) : 4;
      const end = Math.min(ordered.length, offset + batch);
      try {
        matches = await this.resolveCandidates(ordered.slice(offset, end), matches);
      } catch (error) { failure = failure || error; }
      offset = end;
    }
    if (!matches.length) throw failure || Park.error('PARSE', '反搜服务返回无效数据');
    return offset < ordered.length
      ? { matches, continuation: { candidates: ordered.slice(offset), matches } }
      : matches;
  },
  async reverseSearchMore(continuation) {
    if (!Array.isArray(continuation?.candidates) || !Array.isArray(continuation.matches)) {
      throw Park.error('PARSE', '反搜服务返回无效数据');
    }
    return this.resolveCandidates(continuation.candidates, continuation.matches);
  },
  async resolveCandidates(candidates, previous = []) {
    const resolved = new Array(candidates.length);
    let next = 0, failure;
    // 限制并发与单次等待，个别跳板失败不丢弃已经得到的出处。
    await Promise.all(Array.from({ length: Math.min(4, candidates.length) }, async () => {
      while (next < candidates.length) {
        const index = next++, candidate = candidates[index];
        try {
          let url = candidate.url;
          if (!url) {
            const response = await this.http.get(candidate.redirect, { followRedirects: false, timeout: 8000 });
            if ([301, 302, 303, 307, 308].includes(response.status)) url = response.headers.location || '';
          }
          resolved[index] = { ...candidate, url };
        } catch (error) { failure = failure || error; }
      }
    }));
    const matches = previous.map(match => ({ ...match, images: [...match.images],
      details: { ...match.details, titles: [...match.details.titles] } }));
    const urls = new Map(matches.map(match => [match.url, match]));
    for (const candidate of resolved) {
      if (!candidate) continue;
      const url = candidate.url;
      if (!/^https?:\/\/(?![^/]*@)[^/\s?#]+(?:[/?#]|$)/i.test(url) ||
          /^https?:\/\/(?:[^/]+\.)?google\.com(?:[/:?#]|$)/i.test(url)) continue;
      const images = candidate.images.filter(image => /^(https?:\/\/|data:image\/(?:png|jpeg|webp|gif);base64,)/i.test(image)).map(url => ({ url }));
      if (urls.has(url)) {
        const existing = urls.get(url);
        for (const image of images) {
          if (!existing.images.some(i => i.url === image.url)) existing.images.push(image);
        }
        for (const title of candidate.titles) {
          if (!existing.details.titles.includes(title)) existing.details.titles.push(title);
        }
        continue;
      }
      const match = {
        title: candidate.title, url,
        images, details: { title: candidate.title, titles: candidate.titles, url },
      };
      urls.set(url, match); matches.push(match);
    }
    if (!matches.length) throw failure || Park.error('PARSE', '反搜服务返回无效数据');
    return matches;
  },
});
