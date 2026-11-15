/// Generated from assets/public-contract.json. Do not edit values here.
abstract final class PublicContract {
  static const sourceApiVersion = 2;
  static const sourceTypes = <String>[
    "comic",
    "video",
    "voice",
    "novel",
    "tavern",
    "game",
    "article",
  ];
  static const mediaKinds = <String>[
    "comic",
    "video",
    "voice",
    "novel",
    "tavern",
    "game",
    "article",
    "mixed",
    "unknown",
  ];
  static const sourceCategories = <String>[
    "feed",
    "gallery",
    "illustration",
    "doujin",
    "anime",
    "jav",
    "adult",
    "shortvideo",
    "aiDrama",
    "recording",
    "live",
    "asmr",
    "novel",
    "tavern",
    "onlineGame",
    "game",
    "other",
  ];
  static const domainOrder = <String>[
    "feed",
    "gallery",
    "illustration",
    "doujin",
    "anime",
    "jav",
    "adult",
    "shortvideo",
    "aiDrama",
    "recording",
    "live",
    "asmr",
    "novel",
    "tavern",
    "onlineGame",
    "game",
    "other",
  ];
  static const twoD = <String>["doujin", "anime", "illustration", "game"];
  static const threeD = <String>[
    "gallery",
    "aiDrama",
    "jav",
    "adult",
    "shortvideo",
    "recording",
    "live",
    "novel",
  ];
  static const imageCategories = <String>["doujin", "gallery", "illustration"];
  static const videoCategories = <String>[
    "anime",
    "aiDrama",
    "jav",
    "adult",
    "shortvideo",
    "recording",
    "live",
  ];
  static const voiceCategories = <String>["asmr"];
  static const reverseSearchCategories = <String>[
    "general",
    "gallery",
    "anime",
    "jav",
  ];
  static const languages = <String>[
    "zh-Hans",
    "zh-Hant",
    "ja",
    "ko",
    "en",
    "es",
    "ru",
    "ar",
  ];
  static const translationLanguages = <String>[
    "zh-CN",
    "zh-TW",
    "ja",
    "ko",
    "en",
    "es",
    "ru",
    "ar",
  ];
  static const translationLanguageNames = <String, String>{
    "zh-CN": "简体中文",
    "zh-TW": "繁體中文",
    "ja": "日本語",
    "ko": "한국어",
    "en": "English",
    "es": "Español",
    "ru": "Русский",
    "ar": "العربية",
  };
  static const officialBase =
      "https://raw.githubusercontent.com/drdon1234/Hentai-Park";
  static const officialChannels = <String>[
    "sources",
    "reverse-search",
    "metadata",
  ];
  static const sourcesRepository = '$officialBase/sources/index.json';
  static const reverseSearchRepository =
      '$officialBase/reverse-search/index.json';
  static const metadataRepository = '$officialBase/metadata/index.json';
  static const tagTranslationsChannel = "tag-translations";
}
