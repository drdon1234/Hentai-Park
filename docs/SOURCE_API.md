[简体中文](SOURCE_API.md) · [繁體中文](i18n/zh-Hant/SOURCE_API.md) · [日本語](i18n/ja/SOURCE_API.md) · [한국어](i18n/ko/SOURCE_API.md) · [English](i18n/en/SOURCE_API.md) · [Español](i18n/es/SOURCE_API.md) · [Русский](i18n/ru/SOURCE_API.md) · [العربية](i18n/ar/SOURCE_API.md)

# 站点插件接口

[快速开始](#快速开始) · [manifest 字段](#manifest-字段) · [方法](#方法) · [运行时 API](#运行时-api) · [错误码](#错误码) · [国际化](#国际化) · [发布](#发布)

HentaiPark 的每个站点都是一个独立的 JavaScript 插件。应用在运行时加载插件，可以从仓库安装、更新、启用或停用，**不需要重新编译应用**。官方插件位于 [`assets/sources/`](../assets/sources/)，可以直接当作示例。

本文是插件协议的唯一说明。站点业务规则留在插件里，通用网络、缓存和图片能力由框架提供；框架不按站点名称做特例。

## 快速开始

### 运行环境

- 插件运行在应用内的无界面 WebView 中，有完整的现代 JS 与 `DOMParser`。原生层提供加解密、Cookie 和原生 HTTP；原生 HTTP 没有 CORS 限制，浏览器网络和媒体请求遵循下文各自的规则。
- 每个插件第一次被使用时才启动自己的运行时，空闲约 5 分钟或同时运行超过 6 个时回收。manifest 按“脚本 SHA-256 + 运行时版本”缓存，应用启动时不执行插件。不要依赖“应用一启动插件就在运行”。
- 同一份运行时（[`assets/runtime/park_runtime.js`](../assets/runtime/park_runtime.js)）也能在 Node 中运行，开发时可以直接对真实站点做冒烟测试。Node 宿主只用于开发，不是不受信任脚本的安全沙箱。

### 最小插件

```js
Park.register({
  key: 'mysite',
  name: '我的站点',
  version: '0.0.1',
  minAppVersion: '0.9.2',
  type: 'comic',
  category: 'doujin',
  homepage: 'https://example.com',
  domains: ['example.com'],
  defaultFeed: 'popular',
  feeds: [{ key: 'popular', label: '热门' }],

  async feed(key, { page }) {
    const doc = Park.html.parse(await this.http.text(`https://example.com/popular?page=${page}`));
    return {
      items: [...doc.querySelectorAll('.gallery')].map((el) => ({
        id: el.dataset.id,
        title: Park.html.text(el.querySelector('.title')),
        cover: el.querySelector('img').src,
      })),
      hasNext: !!doc.querySelector('.next'),
    };
  },
  async detail(id) { /* … */ },
  async chapter(id, chapterId) { /* … */ },
});
```

### 在 Node 中试跑

在本地安装共享 runner 依赖，并在被忽略的本地验证目录中创建临时冒烟脚本。示例只载入 manifest；修改插件时还要用真实请求验证首页、第二页、搜索、详情、封面解码，以及章节或视频媒体。

```js
import { loadSource } from '../tools/source-runner/host.mjs';
const { manifest } = await loadSource('nhentai.js');
console.log(manifest.key, manifest.version);
```

```powershell
npm ci --prefix 'tools/source-runner'
node <local-validation-script>
```

## manifest 字段

```js
Park.register({
  key: 'mysite',              // 唯一标识，安装后不可更改；只允许 [A-Za-z0-9_-]，1–100 位，不能是 _app
  name: '我的站点',
  version: '0.0.1',
  minAppVersion: '0.9.2',     // 最低本体版本，三段数字；与官方清单一致
  type: 'comic',              // comic | video | novel | game：决定阅读、播放或游戏资源行为
  category: 'doujin',         // doujin | anime | aiDrama | jav | adult | shortvideo | recording | live | gallery | illustration | novel | game | other
  color: '#E5355F',           // 品牌色：站点头像与站点页
  description: '一句话介绍',
  homepage: 'https://example.com',
  domains: ['example.com'],                   // 所属站点，见“隔离与安全”；省略时从 homepage 等地址推导
  linkPatterns: ['example\\.com/g/(\\d+)'],   // 搜索框粘贴链接时直达；第 1 个分组是作品 ID
  idPattern: '^(\\d+)$',                      // 直接输入编号时直达
  imageHeaders: { Referer: 'https://example.com/' },  // 封面与图片默认请求头
  network: { mode: 'auto', vpnHint: true },  // 见“网络”
  media: { mode: 'browser', origin: 'https://example.com', domains: ['media.example.com'] },  // 视频与直链媒体权限
  imageNetwork: { mode: 'browser', origin: 'https://img.example.com', domains: ['img.example.com'] }, // 可选
  imageDecrypt: { /* 可选，见“加密图片” */ },

  settings: [ /* 选项，见“选项定义” */ ],
  account: { /* 可选，见“账号” */ },
  defaultFeed: 'ranking',     // 打开站点页时默认进入的标签（feeds 中的 key）
  feeds: [ /* 站点页标签 */ ],
  searchFilters: [ /* 搜索筛选项 */ ],
  searchHint: '搜索技巧提示',
  i18n: { /* 插件自带的界面文案翻译，见“国际化” */ },

  subscription: { /* 可选：订阅频道/创作者，见“订阅” */ },
  postShortVideos: true,      // 可选：把 feed/订阅帖子内的视频作为短视频流播放
  updateSubscriptions: { /* 可选：更新订阅，见“更新订阅” */ },

  async init() {},              // 可选：运行时启动时调用一次（例如刷新域名列表）
  async onSettingsChanged() {}, // 可选：用户修改站点设置后调用
  // 以及下文“方法”中的各个方法
});
```

能力（`capabilities`）由运行时根据实现了哪些方法自动导出，插件不手写。

### 图片反搜

实现 `reverseSearch(image)` 自动导出 `capabilities.reverseSearch: true`，显示在独立的“图片反搜”页。仅反搜插件声明 `type: 'comic', category: 'other'` 作为清单归类，不声明 `feeds`、`search`、`detail` 或章节／媒体方法；此处的 `type` 不产生可读作品。没有首页的反搜服务不填写 `defaultFeed`。可同时为普通站点提供反搜能力。

`reverseSearchCategory` 声明反搜用途，与作品 `category` 独立，可选 `general`（通用）、`gallery`（本子）、`anime`（里番）、`jav`（JAV），未声明时归入通用。脚本与官方清单使用相同值。服务选择区按此顺序纵向分组，直接显示各组，不折叠；同组保留站点排序，允许跨组多选。

输入为 `{base64, mimeType: 'image/png'}`，由应用在内存中解码、缩放、可选裁剪并重新编码，大小不超过 1,800,000 字节，不含原文件名或本机路径。用户点击搜索才上传到所选服务，换图、切换服务、取消与销毁会取消请求并丢弃旧结果。图片和查询响应不持久化、不进入诊断日志。

返回最多 1000 条出处候选。应用首次最多解析和显示前 20 条；更多候选可按需提供 `{matches, continuation}`，其中 `matches` 是首批候选，`continuation` 仅保存在当前查询内存中。实现 `reverseSearchMore(continuation)` 后，用户点击“查看全部结果”才解析和返回完整候选。普通列表响应也会先显示前 20 条，展开时才转换剩余候选。上限是传输保护，不按分数筛选或静默截断；未知结构、无效字段及超限必须报错。

```js
[{ title: '作品名称', keyword: '用于继续搜索的作品名或番号',
   description: '可选角色或其他原站信息', url: 'https://example.org/original',
   similarity: 91.2, uncertain: false, episode: 1, from: 272.2, to: 282.6,
   images: [{ url: 'https://example.org/frame.jpg', label: '原站图片名称', similarity: 89.5 }],
   details: { filename: '原始文件名', tags: ['原始标签'], detection: { box: [0.1, 0.2, 0.3, 0.4] } } }]
```

`title` 必填，`keyword` 和 `url` 至少提供一个，其余可省略。只有明确识别出作品名或番号才填 `keyword`；只有标签或出处链接时不要伪造作品名称，不提供资源搜索按钮。`url` 仅允许无凭据的 HTTP(S) 网页；没有明确的原站详情链接时省略，不能伪造。`similarity` 为服务提供的 0–100 相似度，服务以 0–1 返回时仅做比例转换；没有分数不填，不同服务分数不能混排为统一可信度。`uncertain` 只传递服务明确给出的低可信标记，不能自定置信度。`episode` 为字符串或数值，`from/to` 为秒。候选不是 `WorkItem`，不能直接下载、收藏或播放；用户可用 `keyword` 继续聚合搜索资源。

插件只解析并诚实保留服务返回的有效候选，不增加分数门槛、不截取前几条，不跨识别区域去重或合并不同时间片段；有分数时按该服务分数降序，无分数时保留原站顺序。相同网页的重复链接可以合并，但必须合并保留其可用图片与说明。空匹配和解析失败必须区分，未知结构、无效字段或超过保护上限应报错，不能伪装成无结果。

支持延迟解析的插件可仅从 `reverseSearch` 或 `reverseSearchResult(page)` 返回以下续载结构，并实现 `reverseSearchMore`。续载数据必须是可 JSON 序列化的本次查询数据，不得保存上传图、账号凭据、Cookie 或持久化：

```js
return { matches: firstTwenty, continuation: { candidates: remainingCandidates } };
async reverseSearchMore(continuation) {
  return parseRemaining(continuation.candidates);
}
```

`images` 最多 50 张，保留每张相关图片、原站名称与独立分数；仅接受无凭据 HTTP(S) 图片或 PNG/JPEG/WebP/GIF 的 base64 data URL（最多 512 KiB 字符）。相关图片在当前页面使用本站 Cookie 分区及通用网络策略加载，支持放大与失败重试，不写入磁盘缓存，换图、换站或离开页面后取消并释放。`details` 为原站候选的完整 JSON 对象，保留标题变体、角色与识别区域、逐帧分数、元数据及可用链接等原始维度，在「原站信息」中按原字段展开；不包含账号凭据、上传图片、整个响应的跟踪标识或请求会话。上限为 128 KiB、12 层、4096 个节点，原始字段值不作为界面文案翻译。不要将图片或候选数据写入日志或持久存储。

需要浏览器会话的服务可从 `reverseSearch(image)` 返回声明式上传条件，而非候选列表：

```js
return { browser: {
  url: 'https://example.org/',
  uploadUrl: 'https://example.org/upload', fileField: 'image',
  resultPath: '/search', resultQuery: 'session',
  resultParams: { mode: 'exact' },
  resultSelector: '#results a',
  emptySelector: '#results', emptyText: 'No results found',
} };
```

应用打开可见浏览器，在初始页面加载完成后创建 multipart 表单，将同一份 PNG 上传到 `uploadUrl`。上传与结果加载保留同一浏览器会话；需要人机验证时由用户在页面内完成。`url`、`uploadUrl`、所有导航与最终页必须为源 `domains` 内无凭据的 HTTPS 地址、使用 443 端口，不授予其他域名权限。插件仅声明条件，不能提供浏览器脚本。

结果页必须满足 `resultPath` 精确匹配且 `resultQuery` 参数非空，应用在现有会话参数上合并 `resultParams`，等待结果链接或明确无结果文案稳定后返回。`resultParams` 最多 8 项、值最多 256 字符；选择器最长 1024 字符，`emptyText` 最长 256 字符。浏览器返回最多 4 MiB 的 `{url, html}`，由同一插件的 `reverseSearchResult(page)` 解析为上述候选列表；它不会自动导出新能力。解析异常必须报错，不能当作无结果。上传和结果网页在后台处理，所有服务的进度、错误和候选结果统一显示在应用自建的反搜界面；站点验证在后台尝试完成，未完成时在应用内提示重试，不显示原站验证区域。临时网页禁用缓存；Cookie 使用本站分区，清理会话时关闭浏览器，图片与 HTML 不进入应用持久存储或日志。取消、返回及旧结果丢弃规则同普通反搜。

### 类型与分类

`type` 决定阅读、播放或游戏资源行为，`category` 决定发现页、站点管理与搜索中的分组；未知或未声明的分类归入“其他”。新增站点必须准确声明类型、分类和能力。

| 分类 | 说明 |
| --- | --- |
| `doujin` | 本子与漫画 |
| `gallery` | 三次元美图：Cosplay、写真与真人图集。图片站声明 `type: 'comic'`，一个图集是一个作品，图片通过 `chapter()` 按顺序返回，复用阅读、收藏和下载；分类不按张数或尺度区分 |
| `illustration` | 二次元美图：插画与动漫图片。图片站声明 `type: 'comic'`，一个图集是一个作品，图片通过 `chapter()` 按顺序返回，复用阅读、收藏和下载；分类不按张数或尺度区分 |
| `anime` | 里番 |
| `aiDrama` | AI 短剧。不接受旧的 `drama` 标识；站点自身的频道名照原样声明，应用分类不用来过滤站点频道 |
| `jav` | JAV 专门站 |
| `adult` | 综合成人视频（如 Pornhub、XVideos、91porn），`type: 'video'`。分类是内容分组，不替代站点标签和用户筛选 |
| `shortvideo` | 短视频：全屏竖向连续流，见下 |
| `recording` | 在线录播视频（点播归档），`type: 'video'` |
| `live` | 直播, `type: 'video'` |
| `novel` | 小说，`type: 'novel'` |
| `game` | 游戏，`type: 'game'` |
| `other` | 创作社区 |

- **短视频**（`type: 'video', category: 'shortvideo'`）：作品、搜索、收藏和历史入口直接进入连续流。每个作品是一个短视频，`videos(id, '_')` 返回当前有效媒体，不需要详情页。`feed` 的 `hasNext` 和 `cursor` 用于临近末尾时自动翻页，游标不能包含账号凭据或媒体签名。刷新从第一页开始；当前条播放，下一条暂停预加载，其余释放。站点没有搜索接口时不声明 `search`。
- **帖子短视频模式**（`postShortVideos: true`）：站点主页和订阅目标页提供入口，提取 `media[]` 中 `type: 'video'` 且有直链 `url` 或非空 `episodeId` 的附件。需要延迟解析的外链视频只返回 `episodeId`，播放或预加载时调用 `videos(原帖 id, episodeId)`，不得把网页地址当作媒体直链。同帖多个视频分别播放，图片不进入播放池；附件支持 `preview`、`format` 和 `headers`。主页沿当前 feed 和筛选分页，订阅目标始终调用该目标的 `subscription.posts`，刷新仍停留在同一范围。播放身份区分帖内视频，收藏、历史和原站互动使用原帖子 ID。此能力不改变站点分类，也不表示原站提供独立随机视频接口。
- **只能在原站播放的聚合视频站**：仍声明 `type: 'video', category: 'adult'`；没有经过验证的媒体接口时不实现 `videos`，运行时导出 `capabilities.videos: false`。详情页主按钮改为用系统浏览器打开 `detail.url`，隐藏播放、下载和分集，不同步虚构章节、不检查章节更新；收藏与历史照常。
- **应用内网页播放的视频站**：实现 `webVideo(id, episodeId)`，返回 `{ url, navigationDomains?, frameDomains? }`。应用在受控 WebView 中打开 `url`，仅允许 HTTPS、无凭据的声明域名主框架导航和 iframe；它不等同于 `videos`，不提供原生播放、下载或媒体嗅探能力。
- **小说**和**游戏**的协议见“方法”中的对应小节。

`defaultFeed` 按 **推荐页 > 排行榜页 > 热门页** 选择，站点确实没有这些入口时才用最新页或其他有效入口，不得伪造未验证的接口。未填写或找不到 key 时，应用按 key 自动选择（先 `promote` / `recommend` / `featured`，再 `rank` / `toplist`，再 `popular` / `hot` / `trending`），都没有就进第一个标签。

支持匿名访问、但推荐需要登录的源声明 `anonymousDefaultFeed: 'ranking'`，值必须指向 `feeds` 中真实可匿名访问的入口，优先排行榜。主页和站点页在未登录时使用该入口；已登录时使用 `defaultFeed`，用户显式选择的标签保持原选择。不要把空列表或网络失败一概当作匿名状态。

### 选项定义

`feeds[].options`、`searchFilters`、`settings` 使用同一种格式：

```js
{ key: 'sort', label: '排序', type: 'select', default: 'date',
  values: [{ value: 'date', label: '最新' }, { value: 'popular', label: '热门', color: '#f00' }] }
// type：select（单选） | multi（多选） | number | text | password | switch
// settings 中用 options 代替 values 也可以
```

`feeds` 的每一项是站点页的一个标签：`{ key, label, options?: [...] }`。

### 动态与级联筛选

`feeds[].options` 和 `searchFilters` 的单选项可声明 `dynamic: true, values: []`。动态子项用 `dependsOn: ['range']` 引用同组上级；key 必须唯一，依赖必须存在且无环，只有动态项可声明依赖。

`filterOptions(request)` 返回候选数组。请求含 `scope: 'feed' | 'search'`、`filter`、`values`；浏览另传 `feed`，搜索可传 `keyword`。`values` 只包含声明的直接上级，不传账号、设置或其他筛选项。上级未选择或为空时不加载子项。

搜索候选依赖关键词时声明 `keywordDependent: true`；关键词变化会重置该项及其后代，其他筛选保持选择。`values` 的上级值只能是字符串、数值或布尔值，不能是多选数组。远端候选名称不作为固定界面文案翻译，可使用应用的内容与标签翻译功能。

候选最多 500 项，每项为 `{value, label, color?}`；value 为唯一字符串或有限数字，label 为非空、无控制字符且不超过 256 字符的原站名称，color 为六位十六进制颜色。大型目录应分组后级联加载，不静默截断。原站候选名称不自动翻译。

选择通过 `feed` 的 `options` 或 `search` 的 `filters` 传递。插件必须校验实际目录成员并保持分页条件；目录解析失败应抛出错误。应用按站点、浏览/搜索、标签或关键词及上级值缓存两分钟；上级变化时清除下级选择并丢弃旧请求结果，加载失败可重试。

每个域的插件只读取本站目录。同品牌不同域不得互相调用插件或共享 Cookie；通用解析可在构建期复用模板，再生成自包含脚本。导航目录模板使用 `node tools/build_catalog_sources.mjs` 生成，`--check` 检查产物一致性。

```js
{key: 'category', label: '分类', type: 'select', default: '',
 dynamic: true, dependsOn: ['range'], values: []}

async filterOptions({scope, feed, filter, keyword, values}) {
  return [{value: 'site-category-id', label: 'Site category'}];
}
```

### 网络

- `network.mode: 'auto'`（默认）：先使用原生 HTTP；HTTPS 同源 GET / HEAD 且无请求体的请求遇到 Cloudflare、HTTP 403、429 或可恢复的连接错误时，自动重试一次浏览器请求。DNS、TLS、超时、响应流和普通 5xx 不触发浏览器回退，避免把不可恢复的故障放大为额外等待。目标必须属于源声明的域名，浏览器回退仍受同源和重定向限制。
- `network.mode: 'native'`: 强制使用原生 HTTP、持久化 Cookie 和用户代理。检测到 Cloudflare 时返回 `CLOUDFLARE`，应用内提供重试；错误带有站内验证地址时，可通过“去确认”打开页面。
- `network.mode: 'browser'` + `network.origin`: 请求在 `origin` 的隐藏浏览器页中通过同源 `fetch()` 发出，使用真实浏览器会话。只读请求遇到 Cloudflare 挑战（包括 HTTP 200 挑战页），或年龄门响应缺少声明 Cookie/内容时，最多导航验证一次，通过后再读取；写请求不重放。年龄门按 `network.confirmation` 自动处理。Android 和 Windows 对唯一标准 Cloudflare 复选框发送浏览器输入，其他平台等待站点自动验证；失败可在应用内重试，或在提供站内验证地址时选择“去确认”。

  文档可在声明范围内进行同协议、同端口导航。未显式传入请求 `origin` 时，共享运行时使用目标站点 URL 的 origin。响应 `url` 保留最终地址。

  自动回退不用于 `followRedirects: false`、`connectAddress` 或未分类的网络错误。浏览器对无请求体的 GET / HEAD 普通请求最多尝试三次，验证通过后至多额外重发一次；仅恢复连接故障或 HTTP 408、500、502、503、504；429 和超时不重复请求。一次逻辑请求最多主动导航验证一次，外层重试不重置次数。浏览器启动、请求、文档读取和释放均有等待上限。带自定义 API 请求头的读取通过真实 `fetch()` 执行，不用普通导航结果替代；复用 HTML 文档时保留其错误状态，`responseType: 'base64'` 返回原始字节的 base64。

- `network.vpnHint: true`：在中国大陆可能需要 VPN 或代理的站点声明它，等待超过 8 秒和失败时提示“可能需要 VPN 或代理”。不要把所有错误都归因于 VPN。
- `network.confirmation: { selector, readySelector, requiredCookies, auto: { clickSelector }, message }`: 站点年龄门声明。`selector` 匹配年龄弹窗，`auto.clickSelector` 匹配弹窗内唯一的确认按钮，`readySelector` 匹配可访问内容，`requiredCookies` 列出确认后必须存在的 Cookie 名。只有用户已在应用入口确认成年，隐藏浏览器才会模拟点击；随后检查弹窗消失、内容出现、Cookie 写入及导航稳定。规则不完整、不匹配或未自动完成时可重试；错误提供站内验证地址时可选择“去确认”，在页面中手动处理后点击完成。确认页仍受源域名及 Cookie 分区限制，操作提示不会自动重放原操作。仅声明年龄确认，不可用于登录、付费或回复等操作。
- 网络异常附带安全的 `diagnostics` 字段 `host`、`transport`、`reason`，区分 TLS 证书、握手、DNS、连接和超时。框架在调用失败时自动记录站点、方法名、错误代码、HTTP 状态和这些字段；错误消息只有在属于插件 `i18n` 或应用文案键时才以模板形式记录，占位符的值不进日志。`reason: 'TLS_HANDSHAKE_TERMINATED'` 仅表示原生 `HandshakeException.message` 恰好是 `Connection terminated during handshake`（握手完成前连接中断，不是证书校验失败）；只有 HTTPS、无请求体的 GET / HEAD 遇到它时自动重试一次，其他错误都不重试。

### 图片

- `imageNetwork: { mode: 'browser', origin, domains }`：图片域（含子域）独立于站点 Cookie 权限，`origin` 可属于站点域或图片域。使用 HTTPS 443 和允许的请求头，当 origin 属于站点声明域时，同源图片复用浏览器站点会话，跨域请求不携带凭据；外部图片域和视频请求始终省略凭据，允许授权图片域之间的重定向。保留单图 20 MiB 上限、解密、格式检查、解码和站点分区缓存；未声明时使用原生图片传输。 浏览器重定向的平台限制见“媒体权限”。
- **加密图片**：声明 `imageDecrypt`，框架在格式检查和缓存之前解密，解密策略参与缓存身份，失败结果不缓存。当前支持 AES-CBC 与严格 PKCS#7 填充，`key`、`iv` 按 UTF-8 编码；必须限定图片域名，其他域名走普通路径。

```js
imageDecrypt: {
  type: 'aes-cbc',
  key: '0123456789abcdef', // UTF-8 字节长度 16、24 或 32
  iv: '0123456789abcdef',  // UTF-8 字节长度 16
  domains: ['images.example.com'],
},
```

封面 HTTP 200 不等于可用，验证时必须确认能解码。

### 媒体权限（HLS 与直链文件）

`media` 权限独立于 `this.http`、`network` 和站点 Cookie：

```js
domains: ['example.com'],
network: { mode: 'native' },
media: { mode: 'native', origin: 'https://example.com', domains: ['media.example.com'] },
```

- `media.mode` 为 `'native'` 或 `'browser'`。`media.origin` 必须属于插件声明的站点，使用 HTTPS 默认端口 443，不含用户凭据、查询或片段。
- `media.domains` 是独立的媒体域名白名单（含子域），不授予站点 Cookie 权限。清单、分段和密钥都只允许 HTTPS 443，拒绝 URL 用户凭据、片段、IP、localhost（含子域）和 `.local`。
- 所有实现 `videos()` 的插件都必须声明 `media`，包括仅返回 MP4 的插件。`scope: 'session'` 可同时声明静态 `domains`：HLS 使用本次会话的确切地址授权，MP4 仍须匹配静态域名白名单；不能用会话授权代替 MP4 白名单。官方发布检查会拒绝缺失或无效的媒体声明。
- MP4 必须声明 `media.mode: 'native'`。播放器通过独立的本地流式会话访问远端文件，使用应用内代理并支持 `GET`、`HEAD` 和单段 `Range`，不缓存整部影片；每次重定向仍须匹配静态媒体域名白名单，关闭播放会话会终止上游请求。`media.mode: 'browser'` 用于 HLS。
- `'native'`：使用独立、无凭据的客户端，不读写站点 Cookie、Authorization 或代理认证，每次重定向前先校验目标。只允许 `Referer`、`Origin`、`Accept`、`Accept-Language`；前两者须属于声明的站点域（含语言子域），`Origin` 只能包含来源 origin。
- `media.referrerDomains` 可选，仅限原生视频媒体，最多 16 个有效公网域名（含子域）。它仅为 `Referer` 增加允许的来源，作为上述站点域限制的明确例外；不扩大 `Origin`、媒体地址、文档导航或 Cookie 权限，不允许用于 `imageNetwork` 或浏览器媒体。
- 动态 HLS CDN 可声明 `media.scope: 'session'`（仅限 `mode: 'native'`）。授权只覆盖当前播放或下载会话中解析的地址、清单资源及允许的重定向，关闭会话即失效，不扩大 Cookie 权限或持久化域名白名单。请求仍受 HTTPS、无凭据、目标地址和响应大小限制；直连 MP4 与浏览器媒体继续使用静态域名白名单。
- `'browser'`：在 `media.origin` 建立隐藏会话，文档可在声明的站点域内导航。请求使用 `credentials: 'omit'`、`mode: 'cors'`，Origin/Referer 由真实文档和浏览器生成。Windows 通过 WebView2 在每次连接前校验资源域，允许授权域间重定向，并复核最终地址；其他内核缺少逐跳拦截接口，使用 `redirect: 'error'`。CORS 和原站 CSP 仍然生效，不能用只检查最终 URL 的方式放开跳转。
- 响应流式限长并重新校验响应地址：清单最多 2 MiB，单个分段最多 32 MiB，AES-128 密钥必须 16 字节；超限、空响应或不允许的地址一律拒绝。

### 隔离与安全

- 每个插件运行在**独立的** JS 环境（各自一个无界面 WebView）中，彼此看不到全局对象；原生桥只认调用来自哪个环境，插件无法冒充其他插件。
- 每个插件有**独立的 Cookie 罐**：请求只会带上、也只会保存到自己的 Cookie。
- Secure Cookie 不随 HTTP 请求发送。验证页打开与浏览器 Cookie 导入都按已安装插件的 `domains` 校验，导入保留可获取的安全属性与有效期。清除站点 Cookie 或卸载时，同时关闭对应浏览器会话并清理该站点的浏览器 Cookie；浏览器的站点 Cookie 由系统共享，因此声明同一站点的插件会受该站点清理的影响。
- `domains` 声明插件所属站点（可注册域名，自动包含子域）。只有这些站点的 Cookie 会同步到内置浏览器（Cloudflare 验证与网页登录共用），浏览器模式的 `network.origin` 也必须属于它们。省略时从 `homepage`、`network.origin`、`account.cookieUrl/loginUrl` 推导。
- 跨来源重定向不携带原来源的认证头；带请求体的跨来源重定向被拒绝。TLS 证书校验始终开启。
- 从网址或仓库安装插件时，应用先在不能联网的沙盒中读取脚本信息，向用户展示名称、版本、SHA-256、声明的站点和风险提示，确认后才安装。

### 账号

```js
account: {
  type: 'password' | 'cookies' | 'session',
  title, hint, required: false,
  fields: [{ key: 'email', label: '邮箱' }, { key: 'password', label: '密码', secret: true }],
  loginUrl?, cookieUrl?, requiredCookies?: ['session_id'],   // 提供后可以在网页中登录，应用自动获取 Cookie
  localStorageKeys?: ['session_key'],  // 网页登录时读取、退出登录时移除这些明确列出的 localStorage 键
  loginDomains?: ['accounts.google.com', 'appleid.apple.com'],  // 第三方授权页域名，仅用于登录导航
  async login(values) { return { name } },
  async logout() {},
  async status() { return { loggedIn, name, configured } },
  managedAccount: true,                 // 可选：提供专用自动维护账号
  async enableManaged() {},             // 仅在用户确认注册后调用
}
```

- 账号状态只在首次使用、登录、退出、网页登录后以及距上次检查超过 10 分钟时刷新，不会在每次调用后检查。`configured` 表示已有账号配置，与当前是否登录成功无关。
- `loginDomains`：插件声明站点实际使用的第三方授权域名（含子域）。只在用户打开网页登录页时放行 HTTPS 443 的跳转，拒绝 URL 用户凭据、IP、localhost 和 `.local`。站内登录页及回调同样要求 HTTPS 443，并且主机必须属于 `domains`；第三方主机不能加入 `domains` 来扩大 Cookie 权限。普通验证页、访问确认、插件请求和 Cookie 导入仍按 `domains` 校验。登录页支持原窗口跳转和保留 `window.opener` 的授权弹窗，弹窗里沿用同一检查，空白初始页不授予外部导航权限。停留在授权页时不判断登录完成，回到站点后才同步 Cookie。第三方 Cookie 不导入插件的 Cookie 罐，也不随清除站点 Cookie 删除；其浏览器登录态由系统 WebView 管理。第三方平台仍可能限制内嵌浏览器登录。
- `localStorageKeys`：可选白名单，网页登录结束时从 `cookieUrl` 所属站点页面读取对应的本地存储字符串，并与 Cookie 一并交给 `account.login(values)`；退出登录时移除该站点声明的这些键，其他本地存储不受影响。声明后须至少取得一个对应值才自动尝试登录；必需的具体键同时列入 `requiredCookies`，该字段检查合并后的凭证。未声明的键不会读取或传入插件；不得在清单、日志或诊断输出中暴露存储值。`account.login()` 必须真实校验凭证；提供 `account.status()` 时，应用仅在后续状态为 `loggedIn: true` 时报告登录成功。
- `type: 'session'` 用于导入已有的授权会话：声明单个保密字段（如 `session`），剪贴板内容完整保留，由插件校验，不拆成账号密码或 Cookie。登录必须真实确认授权，不凭输入格式假报成功。
- `managedAccount: true` 与 `account.enableManaged()` 提供可选的账号管理能力，只在用户知情确认后启用。手动账号与托管账号分别保存，不能覆盖已有凭据；账号数据仅在本机使用，不进入文档、诊断或发布产物。
- 账号密码、Token 和插件状态都是用户本机数据，文档和日志里不要出现真实凭据。

## 方法

方法里的 `this` 见“运行时 API”。所有方法都可以是 `async`。

```js
async feed(key, { page, cursor, options }) {}      // 站点页标签
async search({ keyword, page, cursor, filters }) {}
async searchSuggestions(keyword) {}               // 可选：当前站点关键词联想
async interaction(workId, { type, value } = {}) {} // 可选：读取或保存当前账号的独立原站互动
async related(workId, { page, cursor } = {}) {}    // 可选：分页关联作品，返回 WorkPage
resolveLink(id) {}                                // 可选：将分享跳转标识转换为规范作品 ID
async random() {}                                  // 返回作品 ID
async detail(id, preview) {}
async chapter(id, chapterId) {}                    // 漫画、图集
async resolveImage({ id, chapterId, index, token, retry }) {}  // 可选：延迟解析图片
async thumbnails(id, page) {}                      // 可选：分页加载预览缩略图
async videos(id, episodeId = '_') {}               // 视频
async textChapter(id, chapterId) {}                // 小说
async gameResources(workId) {}                     // 游戏
async resolveGameResource(workId, resourceId, channelId) {}
```

### 关键词联想：`searchSuggestions`

声明方法后运行时导出 `capabilities.searchSuggestions: true`。站内搜索框在输入暂停后调用，清空、提交搜索或销毁页面时取消请求；失败不打断正常搜索。只返回本站真实支持的候选，最多十条，形如 `[{keyword: '原站查询词', label: '候选标签', subtitle: '可选翻译或命名空间'}]`。点击后用 `keyword` 提交本站搜索，框架不拼接站点查询语法。Pixiv 使用原标签，EH 保留命名空间与完整匹配语法。

### 原站互动：`interaction`

声明方法后运行时导出 `capabilities.interaction: true`。`interaction(workId, {})` 只读当前登录账号的全部可用状态；用户选择具体项后调用 `interaction(workId, {type, value})` 写入。读写均返回非空数组 `[{type: 'like'|'favorite'|'rating', value, canUnset?}]`，同一类型不能重复，不能返回站点不支持的项。`like` 为原站点赞，`favorite` 为原站收藏或书签（X 书签即此类型），值为布尔值。原站单向点赞设置 `canUnset: false`，已点赞时隐藏取消操作。评分为 0.5 到 5 的半星值，无法可靠读取个人评分时返回 `null`，不能用站点平均分冒充个人评分。写入只修改指定类型，必须验证服务端结果，不能将请求发出当作成功。未登录或登录失效返回 `LOGIN_REQUIRED`；Cookie、CSRF 与原站接口规则在插件内处理，框架不保存凭证副本。应用内收藏独立保存在本地书库；原站是否利用互动数据改善推荐由原站决定。没有原站互动的匿名站点不实现此方法。

### 关联作品与分享链接

`detail.related` 为普通静态推荐列表；`detail.relatedSections` 为独立关联分组 `[{title, items: [WorkItem]}]`，例如作者其他作品，不能将其误标为同系列。分组标题使用插件文案，条目按原站返回保留。实现 `related(workId, {page, cursor})` 后导出 `capabilities.related: true`，返回与 `feed` 相同的 `WorkPage`。应用在关联列表首次展示及横向滚到末尾时请求，失败保留已有内容并允许重试；成功点赞或收藏当前页的关联作品后，可用该作品作为种子追加一批推荐。分页游标不包含账号凭证，重复作品按作品 ID 去重，取消与旧请求处理同普通列表。

作品链接继续通过 `linkPatterns` 的第一个捕获组提取 ID。分享跳转链接包含编码 ID 时，可实现 `resolveLink(id)`（同步或异步），运行时导出 `capabilities.resolveLink: true`；应用在打开详情前调用它，使用返回的非空规范 ID 访问详情、收藏及进度。只能解析本站声明的分享链接，保持作品原有身份；不得把普通关键词或任意外站链接当成本站作品。框架不按站点名称硬编码转换规则。作品链接在聚合或站内搜索提交时优先直达；多作品链接保留选择入口。没有作品详情的排行榜、反搜和只读订阅源不强制声明作品链接。

### 列表：`feed` / `search`

```js
{
  items: [WorkItem], page: 1, totalPages: 20, total: 500,
  hasNext: true,
  cursor: '12345',        // 可选：游标翻页的站点返回下一页游标，应用下次原样传回
}
// 或者返回分区，应用按分区布局显示：
{ sections: [{ title: '连载更新', items: [WorkItem] }], hasNext: false }
```

**WorkItem**：`{ id, title, subtitle?, cover, coverBlurred?, coverAspect?, pages?, rating?, likes?, views?, language?, category?, badge?, badgeColor?, duration?, uploaded?, tags?, authors?, uploader?, mediaKind?, workCode?, editions? }`

- `authors` 为原站提供的作者名称数组，`uploader` 为上传者标识，用于源内作者屏蔽。列表应尽量提供这些字段；不得从标题或含义不明的副标题猜测作者。列表缺失时，长按屏蔽作者会尝试从详情补充。

- 小说列表统一提供 `id`、`title`、`cover: ''`、`mediaKind: 'novel'`、`language`、`authors: []`、`subtitle`（简介或摘要）、`category`、`tags: []`、`uploaded`（原站日期）。缺失文本用空字符串，缺失集合用空数组；不补造作者、日期、分类或简介，不为列表逐项请求详情。插件负责把原站明确标注的作者、分类从标题中分离，保留作品名和原始 ID；论坛回帖标记、字节数、导航链接与占位简介不作为作品内容。共用小说行按标题、作者、简介、日期及分类标签展示真实信息。

- `workCode` 是原站确认的番号或共同检索码，仅用于查找同作品；不替代 `id`，不合并作品身份、收藏、进度或下载。
- `editions` 是原站明确标注的固定版本标签（如“中文字幕”“无码流出”）；没有标记时不得推断为原版。显示译文不改变原始标签。

- `coverAspect`（宽 / 高）让网格在图片加载前就排好版。
- `badgeColor` 用于分类角标的颜色。
- `mediaKind: 'comic' | 'video' | 'novel' | 'game'` 描述作品本身的类型。插件只有一种类型时可以省略；混合类型时必须填写，不能凭插件的 `type` 把图片当成视频。小说和游戏作品总是填写，这样卸载插件后离线作品和历史仍能用正确的阅读器打开。
- 帖子类结果可以带 `presentation: 'post'`、`text`、`date`、`url` 和 `media` 数组，以帖子卡片显示；`presentation: 'media'` 用媒体网格显示，点击进入作品中的媒体。帖子正文允许没有媒体；媒体地址仍受插件声明的域名和权限约束。

### 详情：`detail`

WorkItem 的全部字段，再加：

```js
{
  url, authors: [], description, uploader?, size?, comments?,
  tags: [{ namespace: 'artist', label: '作者', tags: [{ name, keyword, filters?, count? }] }],
  chapters: [{ id, title }] | null,   // null 表示单章
  singleChapterId?,                   // 单章作品需要的章节 ID
  thumbnails?: [url | { url, width, height, offsetX, offsetY }],   // 支持雪碧图
  related?: [WorkItem], relatedSections?: [{ title, items: [WorkItem] }],
  series?: [WorkItem], variants?: [WorkItem],
}
```

- `variants` 只包含原站提供的同源、同作品实际版本链接，各版本必须保留独立 `id`；不得猜测 URL。跨站版本通过 `workCode` 查找，各自保留收藏、进度与下载。

- 点击标签时，应用在本站点用 `keyword` 与 `filters` 搜索，因此可以把标签映射成站点原生语法（如 `artist:"xxx"`）或筛选参数。
- 第二个参数 `preview` 可选：只有 `preview.source`、`preview.id` 与请求一致时，才传入已显示或已存储的作品公开元数据。插件仍要核对 ID 并校验 URL。直接输入编号打开时没有预览，标题和封面可能不完整。

### 章节：`chapter` / `resolveImage` / `thumbnails`

```js
{ pages: [
  { url, headers?, fallbacks?: [url], width?, height?, transform? },  // 地址已知
  { token: '12' },                                                      // 延迟解析：应用会调用 resolveImage
]}
```

- `fallbacks`：备用镜像，主地址失败时依次尝试。
- `transform: { type: 'unscramble-strips', segments: N }`：图片被横切成 N 条倒序存放时，应用在 GPU 上还原。离线文件保存原图，显示时再还原。
- `resolveImage` 返回 `{ url, headers?, width?, height?, cacheKey? }`。失败时应用递增 `retry` 再调用，插件可以借此换服务器。
- `thumbnails(id, page)` 返回 `{ thumbnails: [...], hasNext }`。

### 视频：`videos`

返回 `[{ quality: 1080, label: '1080P', url, headers?, format?, preferred?, hls? }]`。直链通常有时效，应用每次播放或下载前都会重新获取。

- `format: 'hls'` 可附 `hls: {manifest, keys}`：`url` 是该分段清单的真实 HTTPS 基址，`manifest` 是已解析好的完整点播分段清单（UTF-8 最多 2 MiB），`keys` 将清单引用的绝对密钥 URL 映射为 16 字节密钥的 Base64，最多 32 项。仅支持原生媒体模式；清单、分片、密钥地址仍经过原有媒体授权及内容校验，未引用的密钥被拒绝。携带此字段的播放结果不写入磁盘缓存，密钥只用于会话内存；插件不得将其写入 store、日志、作品或游标。

- 多集视频在 `detail(id).chapters` 按播放顺序返回 `[{ id, title }]`，每个 `id` 必须稳定，不能用画质或临时媒体 URL 代替。应用用同一个 ID 选集、记录进度、下载和续播，并调用 `videos(id, episodeId)` 获取该集资源。单集用 `singleChapterId`，没有时用 `'_'`。
- 省略 `format` 时按直链 MP4 播放和下载。HLS 必须返回 `format: 'hls'`，并声明 `media` 权限。
- HLS 主清单（`#EXT-X-STREAM-INF`）先由应用展开成各路分段清单，按 `RESOLUTION` 得到真实清晰度。返回主清单时 `quality` 表示期望清晰度：默认选不高于它的最高实际清晰度，没有符合项时选最高档。每路必须是音视频复用的 MPEG-TS 或 fMP4；独立的 `AUDIO`、`VIDEO`、`SUBTITLES` 和未通过静态域名或会话授权的地址一律拒绝。`#EXT-X-I-FRAME-STREAM-INF` 预览轨道被忽略。单路清单无法确定分辨率时提供 `label: '原画'`，不要把期望画质当成真实分辨率。 主清单省略 `RESOLUTION` 时必须提供有效 `BANDWIDTH`，应用保留各码率并显示 kbps，默认选择最高码率，不把码率当作分辨率。
- `type: 'video', category: 'live'` 表示公开直播，归入三次元，主页和域页仅展示图片卡片。实现 `videos()` 返回当前公开房间的 HLS 地址；私密、收费或下线房间不得返回伪造可播结果。应用为直播启用滚动清单播放，不恢复或保存点播进度，也不提供下载。录制由用户显式开始，只保存初始直播窗口之后的新分片，用户停止或应用退出后结束，重启不续录。录制复用独立媒体会话与后台任务，逐段验证、解密并保存本地完整清单；断线重新解析媒体，编码边界与长录制可分卷，失败保留已提交内容。支持音视频复用的 MPEG-TS 和带单个 MAP 初始化段的 fMP4，fMP4 录制保留初始化段，窗口间初始化段变化时分卷；不支持低延迟 PART、BYTERANGE 或 GAP。
- 点播要求带 `#EXT-X-ENDLIST` 的完整、连续 MPEG-TS 或 fMP4 清单；fMP4 只支持媒体分片之前的单个 `#EXT-X-MAP` 初始化段，不支持单个清单内初始化段切换或范围读取。初始化段与媒体分片都经过地址授权、内容校验及本地重写，离线播放与导出必须保留初始化段。直播允许滚动清单及 discontinuity，每次刷新独立注册并保留当前及上一窗口的初始化段与分片。两者支持 `METHOD=AES-128`、`KEYFORMAT=identity` 的 CBC/PKCS7 解密，密钥恰好 16 字节，媒体 IV 显式提供或由序号推导；加密初始化段必须显式提供 IV。密钥仅留在会话内存。不支持 SAMPLE-AES、其他 KEYFORMAT、BYTERANGE、GAP；点播另不支持 discontinuity。非标准的 `#EXT-X-TOKEN` 会被移除。
- HLS 清单和 MPEG-TS 分段支持 PNG `roUd` 封装（原始或 zlib 压缩）；框架先解包再解析、校验或解密，解包后仍遵守清单 2 MiB、分段 32 MiB 的限制。插件继续返回 `format: 'hls'`，无需额外权限。
- 播放时使用只绑定 `127.0.0.1` 的随机端口和随机令牌，通过有限 URL 注册表按需读取已验证的分段，关闭会话即取消请求。HLS 离线下载目前只支持 Android：逐段验证并保存 SHA-256，可恢复、可取消，MPEG-TS 最后由 Media3 封装为 MP4，fMP4 按顺序保存初始化段与媒体分片，完整成品才进入离线库。

### 应用内网页视频：`webVideo`

网页播放器在独立临时会话内处理 Cloudflare 验证，只允许精确的 `challenges.cloudflare.com` 验证子框架，不开放其主框架导航。年龄确认仅在源声明域名内使用 `network.confirmation`，不将源规则用于外部播放器。无法自动完成时保留网页供用户处理；不会导入或导出播放器 Cookie。`CONFIRM_REQUIRED` 保留插件提示，通过应用内“去确认”页面完成手动处理并同步源会话；用户点击完成后不自动重放原操作。

当站点只提供真实播放网页、没有可验证的媒体资源时，实现 `webVideo(id, episodeId)`，不要虚构 `videos` 或章节。返回：

```js
return {
  url: 'https://player.example.com/watch/1',
  navigationDomains: ['player.example.com'],
  frameDomains: [],
};
```

- 运行时自动导出 `capabilities.webVideo`。仅实现 `webVideo` 时，详情和历史进入应用内网页，隐藏应用下载与虚构选集，不承诺精确断点续播；页面控制由上游提供。
- 同时实现 `videos` 和 `webVideo` 时优先原生播放。只有插件返回 `UNSUPPORTED` 时自动回退网页；`HTTP`、`NETWORK`、`CLOUDFLARE`、登录、解析、下架和取消错误照常显示，不触发回退。下载只支持成功解析的原生媒体，不回退网页。
- 地址必须为 HTTPS、公网域名、无用户凭据且仅使用 443 端口。默认允许目标注册域及子域；额外主框架跳转和 iframe 只允许返回的域及子域，必须根据真实请求声明。域声明不扩大插件 HTTP、媒体或 Cookie 权限。弹窗、下载、文件访问和页面调用原生桥接均被拒绝。
- Android 使用独立临时 WebView Profile，不读写默认浏览器或插件 Cookie。需要设备 WebView 支持 `MULTI_PROFILE`，否则提示更新 Android System WebView。退出清除该 Profile 的 Cookie 和网站存储并销毁 WebView；若设备暂不允许删除已载入的 Profile，下一次进程启动播放时清理遗留目录。Apple 使用临时会话，其他平台暂不支持。应用进入后台或上锁时暂停播放。
- 播放页可能需要单独完成年龄或站点确认；不导入源凭据。聚合站解析跳转时可用原生 HTTP 的 `followRedirects: false` 读取 `Location`，不携带源凭据访问上游。

### 小说：`textChapter`

小说插件声明 `type: 'novel', category: 'novel'`，实现 `textChapter` 后运行时导出 `capabilities.textChapter: true`。列表和详情填写 `mediaKind: 'novel'` 和 `language: 'zh'` 或 `'en'`。没有真实封面时返回 `cover: ''`，应用显示文字封面，不请求虚构图片。

```js
async textChapter(id, chapterId) {
  // 返回本章完整正文；paragraphs 必须是非空字符串数组，不得包含 HTML。
  return { title: '章节标题', paragraphs: ['第一段正文。', '第二段正文。'] };
}
```

- 多章小说在 `detail.chapters` 返回稳定 ID 和站点确认的阅读顺序；单篇用 `chapters: null` 和可选的 `singleChapterId`。
- 正文内部分页由插件按顺序合并，不能把下一章、论坛回复、广告或推荐作品并入正文。`Park.html.paragraphs(node)` 提供通用的纯文本提取，站点边界和分页仍由插件决定。
- 登录、付费或权限导致正文截断时抛 `LOGIN_REQUIRED`，不得把预览伪装成完整章节。
- 应用按章原子写入 `text.json`，完整写入才算下载完成。阅读进度和标注使用 `paragraphs.join('\n\n')` 的 UTF-16 位置；字号、字体、缩进等排版只影响显示，不改正文和已保存的定位。书签和标注独立于下载文件，参与备份，删除下载不会删除它们。

### 游戏：`gameResources` / `resolveGameResource`

游戏插件声明 `type: 'game', category: 'game'`，作品填写 `mediaKind: 'game'`，不提供虚构的 `chapters`。运行时根据方法导出 `capabilities.gameResources` 和 `capabilities.resolveGameResource`。

```js
async gameResources(workId) {
  return [{ id: 'resource-id', title: '', version: '1.2', size: '2 GB',
    platforms: ['Windows'], languages: ['SimplifiedChinese'], notes: '原站备注',
    status: 'valid', testStatus: 'untested',
    channels: [{ id: 'stable-channel-id', kind: 'direct', label: 'game.zip', size: '2 GB' }] }];
}
async resolveGameResource(workId, resourceId, channelId) {
  return { kind: 'direct', url: 'https://files.example/game.zip?temporary-signature',
    filename: 'game.zip', extractionCode: '', archivePassword: '' };
  // 网盘返回 kind: 'external'，urls: [全部备选/分卷链接]，url: urls[0]。
}
```

- `gameResources` 只返回稳定编号、元数据和渠道，不能包含签名 URL、密码或伪造的下载状态。`testStatus` 为 `tested | untested | unknown`，只照搬原站标记；`status: 'expired'` 的渠道禁用。
- `resolveGameResource` 只在用户点击或重试时调用，返回的 URL 不持久化、不进日志；密码可以随本地下载任务保存，但不能写进诊断。多个网盘链接不能丢弃；一次返回多条链接时可以给出与 `urls` 等长的 `extractionCodes`（空字符串表示无提取码），`extractionCode` 用于共用的密码。
- 需要回复才能获取的渠道声明 `requiresReply: true, replyText: '实际回复内容'`，应用显示“回复解锁并获取链接”并先展示将发送的文本，经用户确认后才调用。插件在解析前必须重新检查首楼：已解锁则只读；只有用户点击时才提交一次，并在发送前可靠保存账号/帖号状态。结果不明、重复尝试或需要动态验证时，用 `CONFIRM_REQUIRED` 返回原帖 URL，禁止自动重发；列表、详情、预取和后台更新中都不执行回复。
- 直链必须声明 `media: { mode: 'native', origin, domains }`。文件用独立、无 Cookie 的客户端流式下载，HTTPS、逐跳域名、长度检查、取消清理和完成文件保护由框架负责；不提供断点续传，重试会重新解析地址并从头下载。网盘用外部应用打开，只允许 HTTP(S)、FTP(S)、magnet、ed2k、thunder，不使用站点 Cookie。游戏不生成章节、阅读进度或章节追更；应用不自动安装、解压或运行文件。

### 订阅：`subscription`

订阅类插件（关注频道、创作者）声明 `subscription` 对象；运行时在 `normalize` 和 `posts` 都存在时导出 `capabilities.subscription`，在“发现 → 订阅”中显示。同时声明了 `feeds` 的插件也出现在普通分类中。

```js
subscription: {
  hint: '无需登录即可保存订阅；媒体访问取决于原站权限。',
  normalize(input) { return { id: validatedTarget, label: displayName }; },
  async resolve(input) { return { id: validatedTarget, label: displayName }; },
  async targets() { return [{ id: joinedChannelId, label: channelName }]; },
  async posts(target, { cursor }) {
    return { items: [{ id, title, text, date, url, locked,
      media: [{ type: 'image', url, preview, previewOnly: false },
              { type: 'video', url, preview, format: 'mp4', headers: {} }] }],
      cursor: nextCursor, hasNext: true };
  },
  async mediaChunk(resource, offset) { return { base64, done }; }, // 可选
}
```

- `normalize` 必须纯本地校验：未登录、无网络时也能保存目标；只接受当前站点的用户名或受控的主页 URL。`resolve`、`targets` 可选；有 `targets` 时清单输出 `subscription.joinedTargets: true`。
- 支持社群独立入口时声明 `communities: true`、界面说明 `communityHint` 与输入示例 `communityExample`；运行时原样导出这些元数据。社群目标返回 `{ id, label, kind: 'community' }`，ID 必须能区分作者目标。框架通过 `targets({ kind: 'community' })` 请求已加入社群，通过无参数 `targets()` 请求默认列表；插件应分别处理，不能因社群接口失败而破坏作者列表。`resolve` 可只读确认社群名称与访问权限，不应自动加入社群。
- `posts` 的游标是不透明字符串，最后一页 `hasNext: false`，没有媒体的页面也允许继续翻页。`locked` 表示权限不足；`previewOnly` 明示只是公开预览，不能把缩略图冒充全文。

### 公共相册：`subscription.media`

相册是独立能力，不根据当前页面已加载的帖子拼装，也不回退调用 `subscription.posts`。源需声明 `subscription.media(scope, { page, cursor })`；拥有公开 feed、但没有可订阅目标的源也可以在 `subscription` 对象下单独声明此方法。运行时据此导出 `capabilities.album`，它与 `capabilities.subscription` 分离。

`scope` 只能是 `{ feed, options }` 或 `{ target }`：前者列出指定 feed 及筛选项对应的作品，后者列出用户、社区、频道或群组目标的帖子。目标如何识别、遍历和补全由源负责；页面不按站点名称添加条件。相册返回 `{ items, cursor, hasNext }`，即使当前页没有匹配媒体，只要源还有下一页就继续返回有效游标。

每个条目必须提供稳定的字符串 `id`、`presentation: 'post' | 'work'`、日期（有值时为可解析的 ISO 8601 字符串）和完整的 `media` 数组。媒体顺序遵循原站，数组内每项都有唯一稳定字符串 `id`、`type: 'image' | 'video'`，并提供实际内容 `url` 或受控 `resource`。`preview` 是预览图；无法提供图片 URL 时可返回独立的 `previewResource`。不要用作品封面、视频地址或尚未公开的全文伪装预览。受限内容仅能返回明确标注 `previewOnly: true`、保留原站模糊处理的公开预览，并设置 `locked: true`（原站锁定整帖时）。

源负责将其支持的所有可访问帖子和作品转换为这一协议，包括帖子跨页时的媒体补全和源站媒体组归并。相册会在客户端按本地日期闭区间和图片/视频过滤；同帖收起只影响显示，不改变作品或媒体身份。`presentation: 'work'` 进入该作品详情，`'post'` 进入完整帖子页。相册封面只加载图片或显式缩略图资源；不可把视频播放地址用作封面。

同一作品跨页返回时，客户端按媒体 `id` 合并；需要恢复附件顺序的源可提供有限数值 `order`（同一作品全部媒体都需提供）。`previewResource` 使用下述受控附件格式，最大 2 MiB，必须指向独立图片缩略图。每页的继续游标必须前进，重复游标会明确报错。未知日期的条目在指定日期范围时排除；筛选无结果时自动加载有限页数，仍可手动继续加载。

- `coverBlurred: true` 与媒体的 `blurred: true` 分别保留原站封面和图片的模糊预览，适用于缩略图与完整图片查看；插件不得把受限写真作为未模糊的完整内容展示。视频预览与全片均先展开 HLS 主清单，再播放所选清晰度的点播清单。
- 不能提供直链的授权附件使用 `media[].resource`，并实现 `mediaChunk(resource, offset)`：每次最多 128 KiB，offset 按 128 KiB 对齐；resource 必须含整数 `size` 和稳定、非秘密的字符串 `cacheKey`（不随授权凭据或临时引用变化）。框架校验总大小和每块完整性，原子写入自己的缓存路径，单个附件最大 512 MiB；资源不能决定本地路径。签名链接和 resource 不保存到订阅记录。
- 涉及原站关注或加入的订阅，必须在保存前明确告知用户并由用户确认；未经验证的写操作必须引导用户到原站手动操作，不得静默关注、加入或付费。

### 更新订阅：`updateSubscriptions`

普通插件可以用独立的 `updateSubscriptions` 对象支持“关注更新”。运行时只在 `check` 存在时导出 `capabilities.subscriptionUpdates`，不改变作品分类，也不影响上面的 `capabilities.subscription`。元数据包含 `dimensions: [{ key, label, hint }]`；标签菜单可以传递原始关键词和筛选参数。

- `normalize(dimension, input)` 返回 `{ id, label }`；`check({ dimension, target }, { cursor })` 返回 `{ items, hasNext, cursor }`。每项为 `{ id, title, kind, workId, chapterId }`，`kind` 只能是 `work | post | chapter`，ID 稳定且非空，不携带媒体 URL、Cookie 或凭据。章节 ID 要包含作品身份，避免不同作品的“第 1 话”冲突。
- `Park.enableUpdateSubscriptions(Park.__pending, rules)` 提供通用适配，规则在插件脚本末尾明确声明维度，可以设置 `searchFilters`、`seriesPattern`。`work` 用真实章节目录；`posts` 用现有频道接口；`search` 和 `filter` 用搜索，`code` 严格匹配完整番号，`series` 用经过本站域名校验的系列路径。搜索游标同时保存页号与站点游标。
- 搜索和动态返回 `windowed: true`，表示检查最近三页的结果窗口：首次只建立基线，之后按稳定 ID 产生“新发现内容”事件，不声称知道发布时间。其他分页协议每轮最多三页，保存游标与候选项，完整结束后再事务提交；章节目录不允许窗口截断，候选上限 20,000，超限报错。网络、权限、验证页、空目录或不完整解析都要抛明确错误，不能用空结果掩盖。
- 前后台共用插件运行时、Cookie 分区、域名约束和检查器。后台只启动相关插件，不登录、不在原站订阅、不下载媒体、不绕过权限。账号或插件配置变化时重建基线（Token 续期不算）。

## 运行时 API

方法里可以用 `this` 访问：

| 成员 | 说明 |
| --- | --- |
| `this.http` | `request(opts)`、`get(url, opts)`、`post(url, opts)`、`text(url, opts)`、`json(url, opts)` |
| `this.config` | 用户在站点设置中选择的值（未设置时为 `default`） |
| `this.store` | 持久化键值存储：`get(key, fallback)` / `set(key, value)`，用于保存 Token、域名列表等；`await flush()` 确认写盘成功，失败抛错 |
| `this.cookies` | `get(url)` / `set(url, { name: value })` / `clear(url)` |
| `this.log({ code, status, host, transport, reason, action })` | 只写入这些允许的字段；自由文本不保留，避免泄露凭据与请求地址 |

空列表可通过固定 `reason` 诊断：`UPSTREAM_EMPTY` 表示上游列表为空，`NO_VIDEO` 表示插件未选出视频。应用使用 `EMPTY_RESULT` 表示加载后仍无内容，`CONTENT_FILTERED` 表示内容被显示规则过滤，`SEARCH_ONLY` 表示省流设置跳过推荐请求。正常成功列表不逐页记录，应用只在空列表状态变化和恢复时记录；不得把标题、搜索词、作品编号、会话或媒体地址加入日志。

全局工具：

| 工具 | 说明 |
| --- | --- |
| `Park.html.parse(text)` | 返回标准 `Document`，可以用 `querySelector` |
| `Park.html.text(node)` / `unescape(s)` / `strip(html)` / `paragraphs(node)` | 文本处理 |
| `Park.crypto.md5Hex(text \| text[])` | MD5，可以传数组批量计算 |
| `Park.crypto.sha256Hex` / `hmacSha256Hex(key, text)` / `aesEcbDecrypt(base64, key)` / `uuid()` | 原生实现 |
| `Park.crypto.digestBytes('sha1' \| 'sha256', bytes)` | 最多 2 MiB 的 0–255 整数字节数组 |
| `Park.crypto.randomBytes(length)` | 系统安全随机字节，length 为 1–65536 |
| `Park.url.parse(value, base, domains)` / `site(source, value, base?)` / `response(source, response, requested)` | 解析授权域及子域内的 HTTPS 443 地址，拒绝用户凭据，移除片段，失败返回 `null`。`site` 使用源 `domains`；`response` 校验最终地址，不匹配时抛 `BLOCKED`，不会修改共享的源基地址。插件继续检查路径、页号、作品和搜索身份，不使用封闭查询键列表或 CDN 节点名称限制。 |
| `Park.utils.rateLimiter(ms)` | 返回 `wait()`，保证两次请求之间的最小间隔 |
| `Park.utils.mapLimit(items, n, fn)` / `lruMap(n)` / `parseCount('1.2万')` / `formatDate(ts)` | 其他常用工具 |
| `Park.error(code, message, extra?)` | 创建带错误码的错误，见“错误码” |

`Park.crypto.aesGcmEncrypt(plaintext, key, iv, aad)` / `aesGcmDecrypt(ciphertext, key, iv, aad)` 接受十六进制数据、16/24/32 字节密钥、12 字节 IV，以及可选的十六进制附加认证数据 `aad`（最多 4096 字节，默认空），返回字节数组。明文最多 4080 字节，密文包含末尾 16 字节认证标签、最多 4096 字节；每次加密必须使用新的安全随机 IV。解密认证失败即抛错，不返回未认证明文。

### `http.request(opts)`

```js
await this.http.request({
  url, method: 'GET', headers: {}, params: { q: 'x' },   // params 拼接到 URL
  json: {...} | form: {...} | body: 'raw' | bodyBase64: '...',
  timeout: 15000,
  responseType: 'text' | 'base64',
  followRedirects: false, // 可选，默认 true；仅原生网络支持
  connectAddress: '<站点公布的公网 IPv4>', // 可选；仅 HTTPS 443 原生请求
});
// → { status, headers, body, url, ok, json() }
```

- `text()` / `json()` 遇到非 2xx 自动抛错（404 → `NOT_FOUND`）。Cookie 自动保存，并按每次重定向的目标地址重新选择。
- `connectAddress` 仅替换声明域名的 TCP 连接地址，保留原 URL、Host、SNI、系统证书校验、Cookie 分区与重定向策略；不允许私网、保留地址、HTTP 或非 443 端口。不自动回退浏览器。设置代理时仍经代理连接，不绕过用户代理；跨主机重定向恢复正常解析。插件可使用源站公布的地址提示，不能关闭 TLS 校验或向明文地址发送凭据。
- 原生网络设置 `followRedirects: false` 时返回原始 30x 响应和 `Location`，不访问跳转目标；浏览器网络不支持该选项并返回 `CONFIG`。需要检查 30x 时用 `request()` / `get()`，不要用要求 2xx 的 `text()` / `json()`。
- `bodyBase64` 是原始二进制请求体（最多 2 MiB），不能与 `body` 或浏览器模式同时使用；与文本请求使用相同的域名隔离、TLS 和重定向规则。插件不能自行开放浏览器网络、WebSocket 或任意文件访问。
- 文件上传使用 `multipart: {fields: {name: '文本'}, file: {name: 'file', filename: 'image.png', mimeType: 'image/png', base64: '...'}}`，与 `json/form/body/bodyBase64` 互斥，仅用于原生网络。运行时生成边界、编码 UTF-8 字段和二进制文件，并通过 `bodyBase64` 发送；完整请求体上限仍为 2 MiB。字段名、文件名仅允许 1–100 位 ASCII 字母、数字、下划线、点或短横线，文本字段最多 4096 字符，文件类型限 PNG、JPEG、WebP、GIF。不要上传本机路径、原始文件名或凭据。

## 错误码

用 `throw Park.error(code, message, extra)` 抛错，应用按错误码给出引导：

| code | 应用的处理 |
| --- | --- |
| `CLOUDFLARE` | “去验证”：打开内置浏览器 |
| `CONFIRM_REQUIRED` | “去确认”：等待用户完成插件声明的访问确认（`extra.url` 指向确认页） |
| `LOGIN_REQUIRED` | “去登录”：打开站点设置的账号区 |
| `NOT_FOUND` | 显示“内容不存在” |
| `BLOCKED` | 显示“访问受限”（如 IP 被封、配额用尽），图片不再重试 |
| `NETWORK` | 显示“网络连接失败”与具体原因，附“重试” |
| `HTTP` / `PARSE` / `UNSUPPORTED` / `CONFIG` | 显示插件给出的消息与“重试” |

### 结构化消息

`message` 是**中文模板**，同时也是翻译键；可变的部分放在 `extra.params` 里，不要拼进字符串：

```js
throw Park.error('HTTP', '站点返回 HTTP {status}', { params: { status: res.status }, status: res.status });
throw Park.error('NOT_FOUND', '影片不存在');
```

应用先用插件自己的 `i18n` 翻译模板，再用应用的通用词汇，最后把 `params` 填进占位符。拼接后的字符串无法翻译，非中文用户会看到中文。`extra` 中的 `status`、`url`、`diagnostics` 照常使用。

### 主页缓存与错误语义

- `feed` 实时结果保留全部字段。应用私有、可重建的磁盘缓存保存白名单作品信息、帖子文字、附件访问数据及支持的详情字段，让缓存条目在刷新前也可打开；其中可能包含会过期的媒体 URL 和资源引用。缓存不替代下载或备份，过期链接需要刷新。缓存身份区分站点、账号、配置和请求范围；账号凭据不得放入返回内容、ID 或游标，也不得把缓存访问数据复制到诊断或订阅记录。
- 过期缓存只在明确的 `NETWORK` / `TIMEOUT` 错误时作为离线内容显示，并标明是缓存。登录、确认、人机验证、解析和配置失败必须抛对应错误，框架不会把它们伪装成网络失败；用户主动刷新失败也显示真实错误。

## 国际化

应用界面支持 `zh-Hans`、`zh-Hant`、`ja`、`ko`、`en`、`es`、`ru`、`ar`（阿拉伯语从右到左）。插件里所有给人看的静态文案（名称、说明、标签名、选项、搜索提示、账号说明、错误消息）都用**简体中文原文**书写，原文就是翻译键。

插件在 manifest 的 `i18n` 中自带自己的翻译：

```js
Park.register({
  i18n: {
    'zh-Hant': { '发行日期': '發行日期', '影片不存在': '影片不存在' },
    'en': { '发行日期': 'Release date', '影片不存在': 'Video not found', '站点返回 HTTP {status}': 'The site returned HTTP {status}' },
    // ja、ko、es、ru、ar 同理
  },
  key: 'mysite',
  // …
});
```

- 查找顺序：插件 `i18n` 中当前语言 → 插件 `i18n` 中的 `en`（简体中文界面除外）→ 应用的通用词汇（`assets/i18n/`，如“排序”“最新”“热门”）→ 原文。
- 只有插件自己用到、应用里没有的词才需要写进 `i18n`；通用词直接复用应用的翻译。占位符写法 `{name}` 必须与原文一致。
- 远端内容（作品标题、作者、标签、简介）、用户输入和持久化的协议键保持原文，不当作界面文案翻译。
- 修改 `i18n` 也是修改插件，需要提高插件版本。已安装旧版插件的用户在更新前会看到旧文案。

应用自身的界面文案通过 `tr('已选 {count}', { 'count': count })` 或 `context.tr` 调用，八种语言资源位于 `assets/i18n/`，新增或修改时必须同步全部语言并保持占位符一致。

## 排行榜

源通过 `rankings` 声明作品榜、女优榜、卖家榜或动态分类榜；`capabilities.rankings` 由运行时根据声明生成。仅提供商业榜的源设置 `rankingOnly: true`，不声明 `feeds`，不伪造详情、阅读或播放能力。它只出现在独立排行榜页和站点管理中。

```js
rankings: [{
  key: 'sales', label: '排行榜', category: 'doujin', section: 'market', metric: '官方销量榜',
  options: [{ key: 'period', label: '周期', default: 'week', values: [
    { value: 'week', label: '周榜' }, { value: 'month', label: '月榜' },
  ] }],
}],
async ranking(board, { page = 1, offset = 0, cursor, options = {} }) {
  return { items: [{ id: '商品标识', rank: 1, title: '远端作品名', cover: 'https://example.com/cover.jpg',
    keyword: '作品检索词', url: 'https://example.com/product/1', subtitle: '作者或番号' }],
    page, hasNext: false };
},
```

- `section` 可为 `market`（市场榜，`rankingOnly` 默认）或 `site`（站点榜，普通内容源默认），页面分区显示。`kind` 可为 `work`、`actress`、`seller`、`genre`；人物榜须返回人物或卖家条目，不可伪装成作品。动态选项标记 `dynamic: true`，由 `rankingOptions(board)` 返回真实选择项，运行时会在请求前校验。`category` 决定搜索范围；页面按用户的域顺序显示已有榜单的分类，包括创作社区。`metric` 明确标示销量、人气或站内热度；站点默认热门不能称为销量榜。
- `rank` 保留原站名次，包括并列名次；官网只有有序列表时使用其原始位置。`offset` 是此前收到的原始条目数，不受本地去重和屏蔽影响。`keyword` 可选，缺省按标题搜索；`url` 是无凭据的 HTTPS 商品链接。
- 既有内容源可声明 `{ key: 'hot', label: '排行榜', category: 'doujin', metric: '站内热度', feed: 'hot' }`。省略 `options` 时继承对应 feed 的选项；无需实现 `ranking()`，运行时复用 `feed()`，保留作品字段，补 `workId` 和缺失的 `rank`。页面由此打开真实作品详情。作品可打开详情；人物榜按姓名搜索并保留原站入口，卖家榜只打开原站。独立排行榜插件通过 `rankings` 分支发布，普通内容源（包括带排行榜声明的源）仍通过 `sources` 分支分发。
- 运行时在请求前拒绝未声明榜单或选项值。每个榜单与选项组合独立分页、刷新与会话复用；插件版本变化后使用新会话。列表按用户已有的内容屏蔽规则过滤，保留原始名次。
- 排行榜结果不使用普通首页磁盘缓存，避免丢失名次、检索词和商品链接。所有站点业务规则留在插件内。

## 发布

### 源仓库

一个仓库就是一个 `index.json`，可以放在任何静态托管上。用户在“我的 → 站点 → 添加站点”中输入仓库地址即可浏览、安装和更新：

```json
{
  "name": "我的站点仓库",
  "apiVersion": 2,
  "sources": [
    {
      "key": "mysite",
      "name": "我的站点",
      "version": "0.0.1",
      "minAppVersion": "0.9.1",
      "description": "一句话介绍",
      "url": "https://example.com/sources/mysite.js",
      "sha256": "脚本 UTF-8 原文的 64 位十六进制 SHA-256",
      "apiVersion": 2
    }
  ]
}
```

`url` 是脚本完整地址，也可以用相对 `index.json` 的 `file`。第三方仓库由用户确认后手动安装；`sha256` 可选，提供时校验下载内容。

### 版本与更新规则

- 插件必须声明 `minAppVersion`（如 `0.9.1`），表示最低本体版本；官方清单与脚本声明必须一致。当前协议为 `apiVersion: 2`。官方更新与手动 URL 安装均在替换旧插件前校验，不满足要求时保留旧插件。发布器不允许缺失、格式错误或不一致的声明。
- 自动提示分别显示可直接更新的插件数量，以及按最低本体版本分组的受限插件数量。只有兼容的插件参与安装。
- 本体与插件更新均可选择“不再提醒”，只忽略当前提示中的版本，重启后保留；后续新版本重新提示，手动检查不受影响。

- 版本必须是三段、点分隔、无前导零的非负整数（如 `0.0.1`），逐段按数字比较；不接受缺段、多段或预发布后缀。
- 官方更新必须提供脚本 UTF-8 原文的 `sha256`（不修剪空白、不转换换行），脚本声明的 `key`、`version` 必须与索引一致；`apiVersion` 必须与当前应用运行时完全一致，否则拒绝更新。
- 插件版本与应用版本分开管理。修改插件脚本（包括 `i18n`）时，同时提高脚本和 `assets/sources/index.json` 中的版本；发布器拒绝降版，也拒绝同一版本对应不同内容。

### 应用内的官方更新

- “我的 → 站点”和“我的 → 关于 → 更新”中的“启动时检查插件更新”默认开启：每次启动只读取官方索引，发现新版本后提示，用户确认后才下载、校验并安装。回到前台时保留 12 小时间隔，失败也记录检查时间。关闭自动检查后仍可手动检查。只检查已安装的内置插件和官方插件，不自动安装新插件，也不接管用户自装的同名第三方插件。
- 确认安装时再次验证身份、版本、来源、API 和摘要，等待初始化和状态持久化成功才算完成；失败保留旧脚本和用户状态，安装期间中断的话下次启动先恢复。启动不会用安装包内置的脚本覆盖已有插件；脚本缺失时保留登记信息和用户数据，等用户明确恢复或更新。“恢复内置版本”经用户确认后回退到当前安装包中的版本。
- 应用自身更新同样默认检查：Android 上用户确认后在应用内下载适合设备的官方 APK，校验大小、SHA-256、包名、版本与签名后调起系统安装界面；支持进度、取消与重试，官方发布页作为备用入口。

### 官方插件的发布

官方插件维护 `assets/sources/index.json`，使用 `tools/publish_sources.mjs` 离线校验清单与运行时声明，再生成带不可变脚本地址和 SHA-256 的发布索引。离线校验不执行登录或站点方法，不能代替真实请求验证。构建与发布操作见 [开发说明](DEVELOPMENT.md)。

### 构建生成的插件

Telegram 插件的唯一实现是 `assets/sources/telegram_entry.mjs`，`assets/sources/telegram.js` 由构建生成，不得手改：

```powershell
npm ci --prefix 'tools/source-runner'
node tools/build_subscription_sources.mjs
```

它使用 [@mtproto/core 6.3.0](https://github.com/alik0211/mtproto-core)（GPL-3.0，[许可证](licenses/mtproto-core.txt)，依赖汇总见 [第三方许可](licenses/telegram-dependencies.txt)）。站点适配替换了传输、密码学和存储，不开放库默认的 WebSocket、浏览器 localStorage 或调试日志。
