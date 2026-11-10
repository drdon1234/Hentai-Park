Park.register({
  ...Park.createVoiceArchive({base: 'https://www.asmrgay.com', feeds: {
    chinese: '/asmr/中文音声', translated: '/asmr/橙澄子汉化组', english: '/asmr/英语音声', all: '/',
  }, languageRoots: {'/asmr/中文音声': 'chineseSpoken'}, subtitleRoots: {'/asmr/橙澄子汉化组': 'zh'}}),
  i18n: {
    'zh-Hant': {'中文及汉化音声归档，支持多层目录与搜索': '中文及漢化音聲歸檔，支援多層目錄與搜尋', '汉化音声': '漢化音聲'},
    ja: {'中文及汉化音声归档，支持多层目录与搜索': '中国語・中国語訳音声のアーカイブ。階層表示と検索に対応', '汉化音声': '中国語訳音声'},
    ko: {'中文及汉化音声归档，支持多层目录与搜索': '중국어 및 중국어 번역 음성 보관함. 폴더와 검색 지원', '汉化音声': '중국어 번역 음성'},
    en: {'中文及汉化音声归档，支持多层目录与搜索': 'Chinese and translated voice archive with folders and search', '汉化音声': 'Chinese translations'},
    es: {'中文及汉化音声归档，支持多层目录与搜索': 'Archivo de audios chinos y traducidos con carpetas y búsqueda', '汉化音声': 'Traducciones al chino'},
    ru: {'中文及汉化音声归档，支持多层目录与搜索': 'Архив китайских и переведённых аудио с папками и поиском', '汉化音声': 'Переводы на китайский'},
    ar: {'中文及汉化音声归档，支持多层目录与搜索': 'أرشيف صوتيات صينية ومترجمة مع مجلدات وبحث', '汉化音声': 'ترجمات صينية'},
  },
  key: 'asmrgay', name: 'ASMR Gay', version: '0.0.2', minAppVersion: '0.13.0',
  type: 'voice', category: 'asmr', color: '#6A5E82',
  description: '中文及汉化音声归档，支持多层目录与搜索',
  homepage: 'https://www.asmrgay.com', domains: ['asmrgay.com'],
  network: {vpnHint: true},
  media: {mode: 'native', scope: 'session', origin: 'https://www.asmrgay.com'},
  defaultFeed: 'chinese',
  feeds: [{key: 'chinese', label: '中文'}, {key: 'translated', label: '汉化音声'}, {key: 'english', label: '英语'}, {key: 'all', label: '全部'}],
  searchFilters: [
    {key: 'section', label: '分类', default: 'all', values: [{value: 'all', label: '全部'},
      {value: 'chinese', label: '中文'}, {value: 'translated', label: '汉化音声'}, {value: 'english', label: '英语'}]},
    {key: 'scope', label: '类型', default: 'all', values: [{value: 'all', label: '全部'},
      {value: 'directory', label: '目录'}, {value: 'file', label: '文件'}]},
  ],
});
