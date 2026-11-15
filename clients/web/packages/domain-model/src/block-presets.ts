/** Original built-in blocking groups from tag_blocklist.dart. */
export const blockPresets = [
  {
    "id": "ai",
    "name": "AI 生成",
    "entries": [
      "tag:ai",
      "regex:(?<![A-Za-z0-9])ai[ _-]?(?:generated|art|cg)(?![A-Za-z0-9])",
      "regex:AI[ _-]?(?:生成|绘画|繪畫|作画|作畫|イラスト)",
      "ai_generated",
      "生成AI"
    ],
    "strongEntries": []
  },
  {
    "id": "guro",
    "name": "重口",
    "entries": [
      "guro",
      "ryona",
      "snuff",
      "vore",
      "gore",
      "regex:(?<![A-Za-z0-9])necrophili(?:a|ac)(?![A-Za-z0-9])",
      "scat",
      "torture",
      "dismemberment",
      "重口",
      "regex:[猎獵]奇",
      "regex:死[奸姦]",
      "regex:肢[体體]切[断斷]",
      "グロ",
      "リョナ"
    ],
    "strongEntries": []
  },
  {
    "id": "loli",
    "name": "未成年女孩",
    "entries": [
      "regex:(?<![A-Za-z0-9])loli(?:[ _-]?con)?(?![A-Za-z0-9])",
      "toddlercon",
      "regex:[萝蘿]莉",
      "regex:ロリ(?:コン)?",
      "regex:로리(?:콘)?",
      "幼女"
    ],
    "strongEntries": []
  },
  {
    "id": "shota",
    "name": "未成年男孩",
    "entries": [
      "regex:(?<![A-Za-z0-9])shota(?:[ _-]?con)?(?![A-Za-z0-9])",
      "shota",
      "正太",
      "regex:ショタ(?:コン)?",
      "regex:쇼타(?:콘)?"
    ],
    "strongEntries": []
  },
  {
    "id": "futa",
    "name": "扶她",
    "entries": [
      "regex:(?<![A-Za-z0-9])futa(?:nari)?(?![A-Za-z0-9])",
      "regex:(?<![A-Za-z0-9])dick[ _-]?girl(?![A-Za-z0-9])",
      "regex:扶[她他]",
      "tag:regex:^扶[上下]扶?$",
      "regex:(?:ふたなり|フタナリ)",
      "후타나리",
      "dickgirl"
    ],
    "strongEntries": []
  },
  {
    "id": "ntr",
    "name": "NTR",
    "entries": [
      "netorare",
      "netori",
      "ntr",
      "cheating",
      "regex:(?<![A-Za-z0-9])cuckold(?:ing)?(?![A-Za-z0-9])",
      "寝取られ",
      "寝取り",
      "regex:牛[头頭]人",
      "regex:[绿綠]帽",
      "regex:出[轨軌]",
      "regex:네토(?:라레|리)"
    ],
    "strongEntries": []
  },
  {
    "id": "furry",
    "name": "Furry",
    "entries": [
      "regex:(?<![A-Za-z0-9])furr(?:y|ies)(?![A-Za-z0-9])",
      "kemono",
      "regex:(?<![A-Za-z0-9])anthro(?:pomorphic)?(?![A-Za-z0-9])",
      "regex:[兽獸獣][人控]",
      "福瑞",
      "ケモノ"
    ],
    "strongEntries": []
  }
] as const;
