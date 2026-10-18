Park.register({
  key: 'anime_trace', name: 'AnimeTrace', version: '0.0.3', apiVersion: 1,
  type: 'comic', category: 'other', reverseSearchCategory: 'anime', homepage: 'https://www.animetrace.com/',
  description: '识别动画与 Galgame 角色及作品；候选结果需核对',
  domains: ['animetrace.com'], network: { vpnHint: true },
  i18n: {
    "zh-Hant": {
      "识别动画与 Galgame 角色及作品；候选结果需核对": "識別動畫與 Galgame 角色及作品；候選結果需核對"
    },
    "ja": {
      "识别动画与 Galgame 角色及作品；候选结果需核对": "アニメやGalgameのキャラクターと作品を識別。候補は要確認"
    },
    "ko": {
      "识别动画与 Galgame 角色及作品；候选结果需核对": "애니메이션 및 Galgame 캐릭터·작품 인식, 후보 확인 필요"
    },
    "en": {
      "识别动画与 Galgame 角色及作品；候选结果需核对": "Identify anime and Galgame characters and titles; verify candidates"
    },
    "es": {
      "识别动画与 Galgame 角色及作品；候选结果需核对": "Identifica personajes y títulos de anime y Galgame; verifica los candidatos"
    },
    "ru": {
      "识别动画与 Galgame 角色及作品；候选结果需核对": "Распознаёт персонажей и названия аниме и Galgame; проверяйте кандидатов"
    },
    "ar": {
      "识别动画与 Galgame 角色及作品；候选结果需核对": "التعرف على شخصيات وأعمال الأنمي وGalgame؛ تحقق من المرشحين"
    }
  },
  async reverseSearch(image) {
    const response = await this.http.post('https://api.animetrace.com/v1/search', { json: { base64: image.base64 }, timeout: 75000 });
    this.http.ensureOk(response);
    const data = response.json();
    if (data.code !== 0 || !Array.isArray(data.data)) throw Park.error('PARSE', '反搜服务返回无效数据');
    const found = [];
    for (const face of data.data) {
      if (!Array.isArray(face.character)) throw Park.error('PARSE', '反搜服务返回无效数据');
      const { character, ...detection } = face;
      for (const row of character) {
        if (!row.work || !row.character) throw Park.error('PARSE', '反搜服务返回无效数据');
        found.push({
          title: row.work, keyword: row.work, description: row.character,
          uncertain: !!face.not_confident,
          details: { ...row, face: detection, ...(data.ai == null ? {} : { ai: data.ai }) },
        });
      }
    }
    return found;
  },
});
