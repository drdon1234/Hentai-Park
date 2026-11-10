Park.register({
  ...Park.createVoiceArchive({base: 'https://asmrmoon.com', feeds: {
    chinese: '/中文音声', japanese: '/日韩音声', english: '/English', all: '/',
  }, languageRoots: {'/中文音声': 'chineseSpoken'}}),
  i18n: {
    'zh-Hant': {'中文、日韩与英语音声归档，支持多层目录与搜索': '中文、日韓與英語音聲歸檔，支援多層目錄與搜尋', '日韩音声': '日韓音聲'},
    ja: {'中文、日韩与英语音声归档，支持多层目录与搜索': '中国語・日韓・英語音声のアーカイブ。階層表示と検索に対応', '日韩音声': '日本語・韓国語音声'},
    ko: {'中文、日韩与英语音声归档，支持多层目录与搜索': '중국어·일본어·한국어·영어 음성 보관함. 폴더와 검색 지원', '日韩音声': '일본어·한국어 음성'},
    en: {'中文、日韩与英语音声归档，支持多层目录与搜索': 'Chinese, Japanese, Korean and English voice archive with folders and search', '日韩音声': 'Japanese and Korean'},
    es: {'中文、日韩与英语音声归档，支持多层目录与搜索': 'Archivo de audios chinos, japoneses, coreanos e ingleses con carpetas y búsqueda', '日韩音声': 'Japonés y coreano'},
    ru: {'中文、日韩与英语音声归档，支持多层目录与搜索': 'Архив китайских, японских, корейских и английских аудио с папками и поиском', '日韩音声': 'Японский и корейский'},
    ar: {'中文、日韩与英语音声归档，支持多层目录与搜索': 'أرشيف صوتيات صينية ويابانية وكورية وإنجليزية مع مجلدات وبحث', '日韩音声': 'اليابانية والكورية'},
  },
  key: 'asmrmoon', name: 'ASMR Moon', version: '0.0.1', minAppVersion: '1.12.1',
  type: 'voice', category: 'asmr', color: '#665D89',
  description: '中文、日韩与英语音声归档，支持多层目录与搜索',
  homepage: 'https://asmrmoon.com', domains: ['asmrmoon.com'],
  network: {vpnHint: true},
  media: {mode: 'native', scope: 'session', origin: 'https://asmrmoon.com'},
  defaultFeed: 'chinese',
  feeds: [{key: 'chinese', label: '中文'}, {key: 'japanese', label: '日韩音声'}, {key: 'english', label: '英语'}, {key: 'all', label: '全部'}],
  searchFilters: [
    {key: 'section', label: '分类', default: 'all', values: [{value: 'all', label: '全部'},
      {value: 'chinese', label: '中文'}, {value: 'japanese', label: '日韩音声'}, {value: 'english', label: '英语'}]},
    {key: 'scope', label: '类型', default: 'all', values: [{value: 'all', label: '全部'},
      {value: 'directory', label: '目录'}, {value: 'file', label: '文件'}]},
  ],
});
