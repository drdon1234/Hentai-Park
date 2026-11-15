/** Generated from ../../../assets/public-contract.json. Do not edit values here. */
export const sourceProtocol = {"apiVersion":2,"types":["comic","video","voice","novel","tavern","game","article"],"mediaKinds":["comic","video","voice","novel","tavern","game","article","mixed","unknown"],"categories":["feed","gallery","illustration","doujin","anime","jav","adult","shortvideo","aiDrama","recording","live","asmr","novel","tavern","onlineGame","game","other"],"reverseSearchCategories":["general","gallery","anime","jav"]} as const;
export const domainOrder: readonly string[] = ["feed","gallery","illustration","doujin","anime","jav","adult","shortvideo","aiDrama","recording","live","asmr","novel","tavern","onlineGame","game","other"];
export const domainDimension = {"twoD":["doujin","anime","illustration","game"],"threeD":["gallery","aiDrama","jav","adult","shortvideo","recording","live","novel"]} as const;
export const domainMedia = {"image":["doujin","gallery","illustration"],"video":["anime","aiDrama","jav","adult","shortvideo","recording","live"],"voice":["asmr"]} as const;
export const languages = {"zh-Hans":{"name":"简体中文","translationId":"zh-CN"},"zh-Hant":{"name":"繁體中文","translationId":"zh-TW"},"ja":{"name":"日本語","translationId":"ja"},"ko":{"name":"한국어","translationId":"ko"},"en":{"name":"English","translationId":"en"},"es":{"name":"Español","translationId":"es"},"ru":{"name":"Русский","translationId":"ru"},"ar":{"name":"العربية","translationId":"ar"}} as const;
export const officialRepositories = {"base":"https://raw.githubusercontent.com/drdon1234/Hentai-Park","channels":["sources","reverse-search","metadata"],"tagTranslations":"tag-translations"} as const;
export type PublicLanguage = keyof typeof languages;
export type PublicMediaKind = typeof sourceProtocol.mediaKinds[number];
export type PublicCategory = typeof sourceProtocol.categories[number];
