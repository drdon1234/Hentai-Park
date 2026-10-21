Park.register({
  key: 'trace_moe', name: 'trace.moe', version: '0.0.4', minAppVersion: '0.9.2', apiVersion: 2,
  type: 'comic', category: 'other', reverseSearchCategory: 'anime', homepage: 'https://trace.moe/',
  description: '动画截图定位作品、集数与时间点；免费额度有限',
  domains: ['trace.moe'], network: { vpnHint: true },
  i18n: {
    "zh-Hant": {
      "动画截图定位作品、集数与时间点；免费额度有限": "動畫截圖定位作品、集數與時間點；免費額度有限"
    },
    "ja": {
      "动画截图定位作品、集数与时间点；免费额度有限": "アニメの画像から作品・話数・時刻を検索。無料枠には制限があります"
    },
    "ko": {
      "动画截图定位作品、集数与时间点；免费额度有限": "애니메이션 장면으로 작품·회차·시간 검색, 무료 할당량 제한"
    },
    "en": {
      "动画截图定位作品、集数与时间点；免费额度有限": "Find anime titles, episodes and timestamps from screenshots; limited free quota"
    },
    "es": {
      "动画截图定位作品、集数与时间点；免费额度有限": "Encuentra anime, episodios y tiempos por captura; cuota gratuita limitada"
    },
    "ru": {
      "动画截图定位作品、集数与时间点；免费额度有限": "Поиск аниме, серии и времени по кадру; бесплатная квота ограничена"
    },
    "ar": {
      "动画截图定位作品、集数与时间点；免费额度有限": "تحديد الأنمي والحلقة والتوقيت من لقطة؛ حصة مجانية محدودة"
    }
  },
  async reverseSearch(image) {
    if (this._searching) throw Park.error('CONFIG', '反搜请求仍在处理中，请稍后重试');
    this._searching = true;
    try {
      const response = await this.http.post('https://api.trace.moe/search?anilistInfo', {
        bodyBase64: image.base64, headers: { 'Content-Type': image.mimeType }, timeout: 75000,
      });
      if (response.status === 429 || response.status === 402) throw Park.error('HTTP', '请求过于频繁或额度已用尽，请稍后重试', { status: response.status });
      this.http.ensureOk(response);
      const data = response.json();
      if (data.error || !Array.isArray(data.result)) throw Park.error('PARSE', '反搜服务返回无效数据');
      return data.result.map(row => {
        if (!row || typeof row.similarity !== 'number' || !Number.isFinite(row.similarity) ||
            row.similarity < 0 || row.similarity > 1 || !row.anilist || !row.anilist.id || !row.anilist.title) {
          throw Park.error('PARSE', '反搜服务返回无效数据');
        }
        return {
          title: row.anilist.title.native || row.anilist.title.romaji || row.anilist.title.english || row.filename,
          keyword: row.anilist.title.native || row.anilist.title.romaji || row.anilist.title.english || '',
          url: 'https://anilist.co/anime/' + row.anilist.id,
          similarity: row.similarity * 100, episode: row.episode, from: row.from, to: row.to,
          images: row.image ? [{ url: row.image }] : [],
          details: row,
        };
      }).sort((a, b) => b.similarity - a.similarity);
    } finally { this._searching = false; }
  },
});
