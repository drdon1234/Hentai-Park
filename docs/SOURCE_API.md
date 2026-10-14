[简体中文](SOURCE_API.md) · [繁體中文](i18n/zh-Hant/SOURCE_API.md) · [日本語](i18n/ja/SOURCE_API.md) · [한국어](i18n/ko/SOURCE_API.md) · [English](i18n/en/SOURCE_API.md) · [Español](i18n/es/SOURCE_API.md) · [Русский](i18n/ru/SOURCE_API.md) · [العربية](i18n/ar/SOURCE_API.md)

# 源插件开发指南

[运行环境](#运行环境) · [注册一个源](#注册一个源) · [数据结构](#数据结构) · [独立订阅接口](#独立订阅接口) · [主页缓存](#主页缓存与错误语义) · [错误码](#错误码) · [源仓库](#源仓库)

HentaiPark 的每个源站都是一个独立的 JavaScript 文件。App 在运行时加载它们：可以从源仓库安装、更新、启用 / 停用，**不需要重新编译 App**。
内置源位于 [`assets/sources/`](../assets/sources/)，可以直接当作示例参考。

## 运行环境

- 源脚本运行在 App 内的无界面 WebView 中（完整的现代 JS 与 `DOMParser`）。原生层提供加解密、Cookie 和原生 HTTP 请求；原生 HTTP 没有 CORS 限制，浏览器网络与媒体请求遵循下文的独立规则。
- 同一份运行时（[`assets/runtime/park_runtime.js`](../assets/runtime/park_runtime.js)）也能在 Node 中运行，开发时可以直接对真实站点做冒烟测试：

在仓库根安装共享 runner 依赖，按下例创建被忽略的 `test/source-smoke.mjs`。示例只载入 manifest；修改源时须补首页、第二页、搜索、详情、封面解码、章节与媒体实际请求验证。Node 宿主仅用于开发，不是不受信任脚本的安全沙箱。

```js
import { loadSource } from '../tools/source-runner/host.mjs';
const { manifest } = await loadSource('nhentai.js');
console.log(manifest.key, manifest.version);
```

```powershell
npm ci --prefix 'tools/source-runner'
node 'test/source-smoke.mjs'
```

## 注册一个源

```js
Park.register({
  key: 'mysite',              // 唯一标识，安装后不可更改
  name: '我的站点',
  version: '0.0.1',           // 仓库里版本号更高时 App 会提示更新
  type: 'comic',              // comic | video | novel | game
  category: 'doujin',         // doujin 本子 | anime 里番 | aiDrama AI短剧 | jav JAV | adult 成人视频 | shortvideo 短视频 | gallery 美图 | novel 小说 | game 游戏 | other 其他
  color: '#E5355F',           // 品牌色：用于源入口卡片、源页面主题色
  description: '一句话介绍',
  homepage: 'https://example.com',
  domains: ['example.com'],                   // 所属站点，见“隔离与安全”；省略时从 homepage 等地址推导
  linkPatterns: ['example\\.com/g/(\\d+)'],   // 聚合搜索中粘贴链接时用于直达；第 1 个分组是作品 ID
  idPattern: '^(\\d+)$',                      // 直接输入编号时用于直达
  imageHeaders: { Referer: 'https://example.com/' },  // 加载封面与图片时默认携带
  network: { mode: 'native', vpnHint: true },  // 大陆访问可能需要 VPN/代理，加载超过 8 秒时提示
  media: { mode: 'browser', origin: 'https://example.com', domains: ['media.example.com'] },  // 可选 HLS 媒体权限，见下文

  settings: [ /* 选项定义，见下文 */ ],
  account: { /* 可选，见“账号” */ },
  defaultFeed: 'ranking',                     // 打开源站页时默认进入的标签（feeds 中的 key）
  feeds: [ /* 浏览页标签，见下文 */ ],
  searchFilters: [ /* 搜索筛选项 */ ],
  searchHint: '搜索技巧提示',

  async init() {},                            // 可选：加载时调用一次（例如刷新域名列表）
  async onSettingsChanged() {},               // 可选：用户修改源设置后调用

  async feed(key, { page, cursor, options }) {},
  async search({ keyword, page, cursor, filters }) {},
  async random() {},                          // 返回作品 ID
  async detail(id, preview) {},
  async chapter(id, chapterId) {},            // 漫画
  async resolveImage({ id, chapterId, index, token, retry }) {},  // 可选：延迟解析图片
  async thumbnails(id, page) {},              // 可选：分页加载预览缩略图
  async videos(id, episodeId = '_') {},                        // 视频
});
```

`type` 决定阅读、播放或游戏资源行为，`category` 决定首页、源站管理与搜索的内容分组；未知或未声明分类归入“其他”。新增站点默认首页按推荐页 > 排行榜页 > 热门页选择，没有这些入口时才用最新页。

### 游戏资源

游戏源声明 `type:'game', category:'game'`；作品填写 `mediaKind:'game'`，不提供虚构 `chapters`。运行时由方法自动导出 `capabilities.gameResources` 与 `capabilities.resolveGameResource`。默认排序只来自官方清单，当前游戏源顺序 GalgameX → KUN → 次元茶馆。

```js
async gameResources(workId) {
  return [{id:'resource-id',title:'',version:'1.2',size:'2 GB',
    platforms:['Windows'],languages:['SimplifiedChinese'],notes:'原站备注',
    status:'valid',testStatus:'untested',
    channels:[{id:'stable-channel-id',kind:'direct',label:'game.zip',size:'2 GB'}]}];
}
async resolveGameResource(workId, resourceId, channelId) {
  return {kind:'direct',url:'https://files.example/game.zip?temporary-signature',
    filename:'game.zip',extractionCode:'',archivePassword:''};
  // 网盘返回 kind:'external'，urls:[全部备选/分卷链接]，url:urls[0]。
}
```

`gameResources` 只返回稳定编号、元数据和渠道，不能包含签名 URL、密码或伪造下载状态。`testStatus` 为 `tested|untested|unknown`，仅描述原站标记；`status:'expired'` 渠道禁用。`resolveGameResource` 只在用户点击或重试时调用，其 URL 不进入持久化或日志；密码可以随本地下载任务保存，不能写入诊断。多个网盘链接不能丢弃。

需要回复的外部渠道声明 `requiresReply:true, replyText:'实际回复内容'`，宿主显示“回复解锁并获取链接”并展示将发送的文本。站点插件必须在解析前重新检查首楼：已解锁只读；只有用户点击时才提交一次，并在发送前可靠保存账号/帖号状态。结果不明、重复尝试或动态验证用 `CONFIRM_REQUIRED` 返回原帖 URL，禁止自动重发；不在列表、详情、预取、后台更新时执行回复。不同网盘提取码按渠道返回；一次返回多条链接时可填写与 `urls` 等长的 `extractionCodes`，空字符串表示无提取码，宿主逐条展示；`extractionCode` 用于相同密码的链接。框架不根据站名编排回复业务。

直链必须声明 `media:{mode:'native',origin:'https://catalog.example',domains:['files.example']}`；文件传输使用独立、无 Cookie 客户端，HTTPS 和逐跳域名校验、长度检查、流式写入、取消清理及完成文件保护由框架负责。网盘使用外部应用打开，仅允许 HTTP(S)、FTP(S)、magnet、ed2k、thunder，不使用源 Cookie。游戏不生成漫画章节、阅读进度或章节追更；文件不自动安装、解压或运行，重试重新解析地址并从头下载。

`type: 'video', category: 'shortvideo'` 启用全屏竖向连续视频流，作品、搜索、收藏和历史入口直接进入流。每条作品代表单个短视频，`videos(id, '_')` 返回当前有效媒体；不需要额外详情页才能播放。`feed` 的 `hasNext` 和 `cursor` 用于临近尾部自动分页，游标不可包含账号凭据或媒体签名。列表刷新重新从第一页开始；当前条播放、下一条暂停预加载，其余播放器取消并释放。站点没有搜索接口时不声明 `search`。

图片 CDN 需要浏览器请求时，按需声明 `imageNetwork: {mode: 'browser', origin: 'https://image.example.com', domains: ['image.example.com']}`。`origin` 和所有图片域名必须属于源声明的 `domains`，仅允许 HTTPS 和白名单请求头；图片请求不带账号凭据，不跟随重定向，单图最多 20 MiB。图片继续经过解密、格式检查、解码和源分区缓存。默认未声明时沿用原生图片传输。Tik.porn 的页面与推荐 API 分别声明自己的同源 `origin`，无需放宽浏览器跨域限制；媒体使用 MP4，不声明未支持的 fMP4 HLS 或 DASH。

AI短剧域使用 `category: 'aiDrama'`，不接受旧 `drama` 标识。站点自身的频道名称独立于应用分类，原样声明；应用分类不用于自动过滤站点频道。

`adult` 为综合成人视频分类，例如 Pornhub、XVideos、91porn，声明 `type: 'video'`；JAV 专门站使用 `jav`。分类表示内容分组，不替代站点内容标签与用户筛选。

聚合视频源仍声明 `type: 'video', category: 'adult'`，没有经过验证的媒体接口时不实现 `videos`，运行时自动导出 `capabilities.videos: false`。详情页主操作改为打开 `detail.url` 的系统浏览器入口，隐藏播放、下载和分集，不同步虚构章节或检查章节更新；收藏与历史保留。框架不按站名判断。`detail(id, preview)` 的第二参数可选，只有 `preview.source` 和 `preview.id` 与请求一致时传入已显示或存储的作品公开元数据；源仍需核对 ID 并校验 URL。iXXX 使用规范化上游 URL 作为稳定 ID，移除已识别追踪参数，TubeSafari 保留上游 key；二者详情不以源 Cookie 请求外部作品。直接编号入口没有预览时仍可打开原站，标题和封面可能不完整。Thumbzilla 只静态解析 MP4 元数据，拒绝其他协议和未声明的媒体域。

`gallery` 为美图分类，包含插画、Cosplay 和写真；图片源继续声明 `type: 'comic'`，一个图集对应一个作品，单套图片通过 `chapter()` 按顺序返回，可复用阅读、收藏和下载。分类不按图片张数或尺度区分。

加密封面声明 `imageDecrypt`，框架在图片格式检查和缓存前解密，策略参与缓存身份，失败结果不会缓存。当前支持 AES-CBC 与严格 PKCS#7 填充，`key`、`iv` 按 UTF-8 编码；必须限定图片域名，其他域名保持普通图片路径。

```js
imageDecrypt: {
  type: 'aes-cbc',
  key: '0123456789abcdef', // UTF-8 字节长度 16、24 或 32
  iv: '0123456789abcdef',  // UTF-8 字节长度 16
  domains: ['images.example.com'],
},
```

网络异常附带 `diagnostics` 安全字段 `host`、`transport`、`reason`，用于区分 TLS 证书、握手、DNS、连接及超时；自动日志只记录白名单字段，不记录原始消息、凭据、请求体或签名 URL。

`reason: 'TLS_HANDSHAKE_TERMINATED'` 仅表示原生 `HandshakeException.message` 精确等于 `Connection terminated during handshake`：连接在 TLS 握手完成前中断，不代表证书校验失败。只有 HTTPS、无请求体的 GET / HEAD 遇到此精确错误时，宿主自动重试一次；取消、证书校验失败、其他 TLS 错误、HTTP 错误及响应读取错误均不重试。再次失败时显示目标主机与 VPN / 代理线路检查提示，日志仍只记录安全诊断字段。

方法里可以用 `this` 访问：

| 成员 | 说明 |
|------|------|
| `this.http` | `request(opts)`、`get(url, opts)`、`post(url, opts)`、`text(url, opts)`、`json(url, opts)` |
| `this.config` | 用户在源设置中选择的值（未设置时为 `default`） |
| `this.store` | 持久化键值存储：`get(key, fallback)` / `set(key, value)`，用于保存 Token、域名列表等；`await flush()` 确认写盘成功，失败抛错 |
| `this.cookies` | `get(url)` / `set(url, {name: value})` / `clear(url)` |
| `this.log({code, host, transport, reason})` | 写入允许字段；自由文本不保留，避免泄露凭据与请求地址 |

全局工具：

| 工具 | 说明 |
|------|------|
| `Park.html.parse(text)` | 返回标准 `Document`，可以使用 `querySelector` |
| `Park.html.text(node)` / `unescape(s)` / `strip(html)` | 文本处理 |
| `Park.crypto.md5Hex(text \| text[])` | MD5，可以传数组批量计算 |
| `Park.crypto.sha256Hex` / `hmacSha256Hex(key, text)` / `aesEcbDecrypt(base64, key)` / `uuid()` | 原生实现，速度快 |
| `Park.utils.rateLimiter(ms)` | 返回 `wait()`，保证两次请求之间的最小间隔 |
| `Park.utils.mapLimit(items, n, fn)` / `lruMap(n)` / `parseCount('1.2万')` / `formatDate(ts)` | 其他常用工具 |
| `Park.error(code, message)` | 抛出带错误码的错误，见下文 |

### `http.request(opts)`

```js
await this.http.request({
  url, method: 'GET', headers: {}, params: { q: 'x' },   // params 会拼接到 URL
  json: {...} | form: {...} | body: 'raw',
  timeout: 15000,
  responseType: 'text' | 'base64',
});
// → { status, headers, body, url, ok, json() }
```

`text()` / `json()` 遇到非 2xx 响应会自动抛错（404 → `NOT_FOUND`）。Cookie 会自动保存，并按每次重定向的目标地址重新选择。跨来源重定向不会携带原来源的认证头；保留请求体的跨来源重定向会被拒绝。

## 数据结构

**列表页**（`feed` / `search` 的返回值）

```js
{
  items: [WorkItem], page: 1, totalPages: 20, total: 500,
  hasNext: true,
  cursor: '12345',        // 可选：游标翻页的站点（如 E-Hentai）返回下一页游标，App 下次请求时原样传回
}
// 或者返回 sections，由 App 自动显示分区布局：
{ sections: [{ title: '连载更新', items: [WorkItem] }], hasNext: false }
```

**WorkItem**：`{ id, title, subtitle?, cover, coverAspect?, pages?, rating?, likes?, views?, language?, category?, badge?, badgeColor?, duration?, uploaded?, tags? }`

- `coverAspect`（宽 / 高）让网格在图片加载之前就排好版，避免跳动。
- `badgeColor` 用于分类标签的颜色（例如 E-Hentai 各分类的传统配色）。

**详情**（`detail`）：WorkItem 的全部字段，另外包括：

```js
{
  url, authors: [], description, uploader?, size?, comments?,
  tags: [{ namespace: 'artist', label: '作者', tags: [{ name, keyword, filters?, count? }] }],
  chapters: [{ id, title }] | null,   // null 表示单章
  singleChapterId?,                   // 单章作品需要的章节 ID（例如哔咔的 "1"）
  thumbnails?: [url | {url, width, height, offsetX, offsetY}],   // 支持雪碧图
  related?: [WorkItem], series?: [WorkItem],
}
```

点击标签时，App 会在本源中用 `keyword` 与 `filters` 搜索，因此可以把标签映射为站点原生语法（例如 `artist:"xxx"`）或筛选参数（例如 Hanime1 的 `tags[]`）。

**章节**（`chapter`）

```js
{ pages: [
  { url, headers?, fallbacks?: [url], width?, height?, transform? },  // 地址已知
  { token: '12' },                                                      // 延迟解析：App 会调用 resolveImage
]}
```

- `fallbacks`：备用镜像，主地址失败时按顺序尝试。
- `transform: { type: 'unscramble-strips', segments: N }`：图片被横向切成 N 条并倒序存放时（禁漫），App 会在 GPU 上原生还原。下载的离线文件保存原图，显示时再还原。
- `resolveImage` 返回 `{ url, headers?, width?, height?, cacheKey? }`。失败时 App 会递增 `retry` 重新调用，源可以借此换一个服务器（E-Hentai 的 `nl` 参数）。

**小说正文**（`textChapter(id, chapterId)`）

小说源声明 `type: 'novel', category: 'novel'`，实现 `textChapter` 后运行时自动导出 `capabilities.textChapter: true`。列表和详情填写 `mediaKind: 'novel'` 与 `language: 'zh'` 或 `'en'`，保证卸载源之后，离线作品和历史仍使用小说阅读器。无真实封面时返回 `cover: ''`，应用根据标题显示文字封面，不请求虚构图片。

```js
async textChapter(id, chapterId) {
  // 返回本章完整正文；paragraphs 必须是非空字符串数组，不得包含 HTML。
  return { title: '章节标题', paragraphs: ['第一段正文。', '第二段正文。'] };
}
```

多章小说在 `detail.chapters` 返回稳定 ID 和站点确认的阅读顺序；单篇使用 `chapters: null` 和可选 `singleChapterId`。正文内部的分页由插件顺序合并，不能将下一章、论坛回复、广告或推荐作品并入正文。`Park.html.paragraphs(node)` 提供通用纯文本提取，站点边界和正文分页仍由插件确定。登录、付费或访问权限导致正文截断时抛出 `LOGIN_REQUIRED`，不得将预览伪装成完整章节。

正文下载按章节原子写入 `text.json`，只有完整写入才计为下载完成。阅读进度和标注使用 `paragraphs.join('\n\n')` 的 UTF-16 原文位置；字号、字体、缩进、段间距及分页模式只影响展示，不修改正文或已保存的定位。书签和标注独立于下载文件，参与书库备份，删除下载不会删除它们。阅读器不提供 TXT/EPUB 导入导出。

**视频**（`videos`）：`[{ quality: 1080, label: '1080P', url, headers?, format?, preferred? }]`。视频直链通常有时效，App 每次播放 / 下载前都会重新获取。

- 视频源在 `detail(id).chapters` 返回按播放顺序排列的 `[{id, title}]`；每个 `id` 必须稳定，不能用画质或临时媒体 URL 代替。宿主用同一 ID 选集、记录独立进度、下载及续播，并调用 `videos(id, episodeId = '_')` 获取该集资源。单集使用 `singleChapterId`，未提供时使用 `'_'`。
- 省略 `format` 时沿用直 MP4 播放与下载路径。HLS 必须显式返回 `format: 'hls'`，并在 manifest 中声明下文的 `media` 权限。
- HLS 主清单（`#EXT-X-STREAM-INF`）会先由宿主展开为各路独立的分段清单，根据 `RESOLUTION` 得到真实清晰度，再交给播放器或下载器。返回主清单时，`quality` 表示期望清晰度：默认选择不高于该值的最高实际清晰度，没有符合项时选择最高档。每路必须包含音视频复用的 MPEG-TS；独立的 `AUDIO`、`VIDEO` 或 `SUBTITLES` renditions 以及超出 `media.domains` 的播放地址均拒绝。可选的 `#EXT-X-I-FRAME-STREAM-INF` 快进预览轨道会被忽略，其地址不会注册或请求。单路分段清单无法确定分辨率时应提供 `label: '原画'`；标签按界面语言翻译，不应将期望画质当作真实分辨率。
- 展开后的 HLS 只支持含 `#EXT-X-ENDLIST` 的完整、连续 MPEG-TS 点播清单。支持 `METHOD=AES-128`、`KEYFORMAT=identity`（省略时同样为 identity）的 CBC/PKCS7 解密，密钥必须恰好 16 字节；IV 可显式提供 128 位值，也可从分段的媒体序号推导。密钥只保存在当前会话内存中，解密后校验 TS，播放与下载共用处理管线。不支持直播、SAMPLE-AES、其他 KEYFORMAT、`EXT-X-MAP`、`EXT-X-BYTERANGE`、fMP4、discontinuity 或 gap；MissAV 的非标准 `#EXT-X-TOKEN` 会被移除。
- 播放时使用仅绑定 `127.0.0.1` 的随机端口和随机令牌，通过有限 URL 注册表按需读取已验证的分段；关闭会话会取消请求。HLS 离线下载目前仅支持 Android：逐段验证、保存 SHA-256 并校验恢复，支持取消，最后由本机 Media3 封装为 MP4，只有完整成品才发布到离线库。iOS/macOS 的 HLS 播放未经本轮验证，不能据此声称已验证可用。

## 独立订阅接口

### 更新订阅协议

普通源使用独立的 `updateSubscriptions` 对象，运行时只在其 `check` 存在时生成 `capabilities.subscriptionUpdates`。这不改变作品分类或原来的动态浏览能力。元数据包含 `dimensions: [{key,label,hint}]`，标签菜单可传递原始关键词及筛选参数，Dart 不按站点名称特判。

`normalize(dimension,input)` 返回 `{id,label}`；`check({dimension,target},{cursor})` 返回 `{items,hasNext,cursor}`。每项为 `{id,title,kind,workId,chapterId}`，`kind` 仅限 `work|post|chapter`，ID 必须稳定且不可为空，更新结果不得携带媒体 URL、Cookie 或凭据。章节 ID 同时包含作品身份，避免不同作品的“第 1 话”碰撞。

`Park.enableUpdateSubscriptions(Park.__pending,rules)` 提供通用适配。规则必须在每个源脚本末尾明确声明维度，可设置 `searchFilters`、`seriesPattern`。`work` 使用真实章节目录；`posts` 使用现有频道接口；`search` 和 `filter` 使用搜索，`code` 严格匹配完整番号，`series` 使用经过本站域名校验的系列路径。搜索游标同时保存页号与源游标。生成脚本仍由源构建器负责，修改后提升插件及清单版本。

通用搜索和动态适配返回 `windowed:true`，代表检查最近三页结果窗口；首次基线记录窗口，后续按稳定 ID 产生“新发现内容”事件，不声称知道发布日期。其余分页协议三页预算后保存游标及候选项，完整结束再事务提交。章节目录不允许窗口截断。网络、权限、验证页面、空目录或不完整解析应抛明确错误，不能伪造空成功掩盖故障。

前后台共用源运行时、Cookie 分区、网络域名约束和检查器；后台只初始化目标源，不登录、订阅原站、下载媒体或绕过权限。检查失败保存白名单错误码并退避。账号或插件上下文变化重新建立基线，账号状态摘要不进入日志或通知。

订阅源声明 `subscription` 对象，运行时依据 `normalize` 和 `posts` 方法同时存在生成 `capabilities.subscription`，由“发现 → 订阅”展示。同时声明 `feeds` 的源也展示在普通分类中，供推荐与站内搜索使用。站点业务全部留在插件内。

普通 `feed`/`search` 的作品可携带 `presentation:'post'`、`text`、`date`、`url` 与上述 `media` 数组，以帖子卡片展示；`presentation:'media'` 则使用媒体网格，点击进入作品中的媒体。`mediaKind:'comic'|'video'` 与 `coverAspect` 描述该作品媒体，不能仅凭源的 `type` 把图片当成视频。帖子正文允许无媒体；图片可在相册中逐张浏览，媒体地址仍受源声明域名和权限约束。

需要用户明确确认的站点在插件内声明 `network.confirmation:{selector,readySelector,requiredCookies,message}`。`selector` 匹配确认弹窗，`readySelector` 匹配可访问的页面内容，`requiredCookies` 为确认完成后必须落地的 Cookie 名称。插件遇到未确认页面抛出 `Park.error('CONFIRM_REQUIRED',message,{url})`；框架提供“去确认”入口，等待弹窗消失、内容出现、Cookie 写入且导航稳定后返回。框架不会代替用户点击确认；该声明也约束通用人机验证页面，避免年龄确认被误当成已通过。

```js
subscription: {
  hint: '无需登录即可保存订阅；媒体访问取决于原站权限。',
  normalize(input) { return {id: validatedTarget, label: displayName}; },
  async resolve(input) { return {id: validatedTarget, label: displayName}; },
  async targets() { return [{id: joinedChannelId, label: channelName}]; },
  async posts(target, {cursor}) {
    return {items: [{id, title, text, date, url, locked,
      media: [{type:'image', url, preview, previewOnly:false},
              {type:'video', url, preview, format:'mp4', headers:{}}]}],
      cursor: nextCursor, hasNext: true};
  }
}
```

`normalize` 必须纯本地验证，未登录/网络不可用仍可保存目标；只接受当前站点用户名或受控主页 URL。`resolve`、`targets` 可选；`targets` 存在时清单输出 `subscription.joinedTargets:true`。`posts` 的游标为不透明字符串，终页 `hasNext:false`，无媒体页仍允许继续翻页。`locked` 表示权限不足，`previewOnly` 明示只是公开预览，不得把缩略图冒充全文。

不能提供直链的授权附件使用 `media[].resource`，并实现 `subscription.mediaChunk(resource,offset)`，返回 `{base64,done}`；每次至多 128 KiB，offset 按 128 KiB 对齐，resource 必须含整数 `size` 与稳定、非秘密的字符串 `cacheKey`；cacheKey 不随授权凭据或临时文件引用变化。框架校验总大小与块完整性，原子写入自身缓存路径；当前单附件最大 512 MiB。资源不能决定本地路径。签名链接和 resource 不保存到订阅记录。

已有授权会话导入可以声明 `account.type:'session'` 和单个保密字段（如 `session`），剪贴板保留完整内容后由插件校验，不当成账号密码或 Cookie 分拆。登录必须真实确认授权，不凭输入格式假报成功。自动关注/加入不是订阅保存的副作用；未经验证的写操作必须引导用户手动操作。

原生 HTTP 请求支持 `bodyBase64`（原始二进制请求体，最多 2 MiB），不得同时传 `body` 或浏览器模式；回复仍使用 `responseType:'base64'`。与文本请求使用相同域名隔离、TLS 和重定向策略。`Park.crypto.digestBytes('sha1'|'sha256',bytes)` 接受至多 2 MiB 的 0–255 整数字节数组；`Park.crypto.randomBytes(length)` 返回系统安全随机字节数组，length 为 1–65536 的整数。订阅不得自行开放浏览器网络、WS 或任意文件访问。

当前接入范围、真实请求证据及设备验证边界见 [订阅能力](SUBSCRIPTIONS.md)。

## 主页缓存与错误语义

`feed` 的实时结果保留源返回字段。磁盘主页缓存仅保存作品 ID、标题、封面、标签、上传者、媒体类型、内容域与展示统计等白名单元数据；`url`、访问凭据、媒体列表与动态帖子不落入该缓存。不要把授权凭据放入 ID、封面地址或分页游标。需要动态媒体或帖子呈现的结果不缓存，访问权限仍由原站决定。

过期缓存只在明确的 `NETWORK` / `TIMEOUT` 错误时作为离线内容展示，并标明缓存状态。登录、确认、人机验证、解析和配置失败必须抛对应错误；框架不会将这些错误伪装为网络失败。用户主动刷新失败也保留真实错误。封面与媒体缓存使用各自的权限与解密流程，不受主页元数据清理影响。

## 选项定义

`feeds[].options`、`searchFilters`、`settings` 使用同一种格式：

```js
{ key: 'sort', label: '排序', type: 'select', default: 'date',
  values: [{ value: 'date', label: '最新' }, { value: 'popular', label: '热门', color: '#f00' }] }
// type：select（单选） | multi（多选） | number | text | password | switch
// settings 中用 options 代替 values 也可以
```

`feeds` 的每一项是源页面里的一个标签页：`{ key, label, options?: [...] }`。

`defaultFeed` 指定打开源站页时默认进入哪个标签。未填写或找不到对应的 key 时，App 按 推荐 > 排行榜 > 热门 的顺序，根据 key 自动选择（key 包含 `promote` / `recommend` / `featured`，然后是 `rank` / `toplist`，然后是 `popular` / `hot` / `trending`），都没有就进入第一个标签。

## 网络

- `network.mode: 'native'`（默认）：原生 HTTP 请求，使用持久化 Cookie，可以走用户设置的代理。若检测到 Cloudflare 质询，会抛出 `CLOUDFLARE`，App 会引导用户在内置浏览器中完成验证，并把通行 Cookie 同步回原生请求。
- `network.mode: 'browser'` + `network.origin`：请求在一个打开于 `origin` 的隐藏浏览器页面中以同源 `fetch()` 发出，带有真实浏览器指纹。适用于 Cloudflare 防护较严的站点（例如 Hanime1）。 同源 GET 请求收到 Cloudflare 质询响应时，隐藏浏览器会导航到该文档完成自动验证，并重试一次原请求；未通过时仍抛出 `CLOUDFLARE`，沿用“去验证”流程。

## 媒体权限（HLS）

`media` 权限独立于 `this.http`、`network` 和站点 Cookie 同步，两种传输方式使用相同的域名规则：

```js
domains: ['example.com'],
network: { mode: 'native' },
media: { mode: 'native', origin: 'https://example.com', domains: ['media.example.com'] },
```

- `media.mode` 支持 `'native'` 与 `'browser'`。两者的 `media.origin` 都必须属于源声明的站点，并使用 HTTPS 默认端口 443，不得包含用户凭据、查询或片段。
- `media.domains` 是独立的媒体允许域名列表，包含其子域名，不授予源站 Cookie 权限。清单、分段和密钥均只允许 HTTPS 443，拒绝 URL 用户凭据、片段、IP 地址、localhost（含子域）和 `.local`。
- `media.mode: 'native'` 使用独立、无凭据的原生客户端，不读取或发送站点 Cookie、Authorization 或代理认证；重定向每一跳均先校验目标域名。仅允许 `Referer`、`Origin`、`Accept`、`Accept-Language` 请求头，前两者必须匹配 `media.origin`。
- `media.mode: 'browser'` 在 `media.origin` 的隐藏浏览器建立媒体会话，使用 `credentials: 'omit'`、`mode: 'cors'`、`redirect: 'error'`；遵循 CDN 的 CORS 规则，不跟随重定向。
- 响应采用流式大小限制，并重新校验响应地址。清单最多 2 MiB，单个分段最多 32 MiB，AES-128 密钥必须为 16 字节；超限、空响应或不允许的地址均拒绝。源所属 `domains` 与带 Cookie 的 `network` 规则保持独立。

## 隔离与安全

- 每个源运行在**独立的** JS 环境（各自一个无界面 WebView）中，源之间看不到彼此的全局对象；原生桥只认调用来自哪个环境，脚本无法冒充其他源。
- 每个源有**独立的 Cookie 罐**：源发出的请求只会带上、也只会保存到它自己的 Cookie，不会读到其他源的登录状态。
- Secure Cookie 不会随 HTTP 请求发送。验证页打开与浏览器 Cookie 导入均按已安装源的 `domains` 校验；导入保留可获取的安全属性及有效期。清除源 Cookie 或卸载时，同时关闭对应浏览器会话并清理该站点的浏览器 Cookie。浏览器站点 Cookie 存储由系统共享，因此声明同一站点的源会受到该站点清理的影响。
- `domains` 声明源所属的站点（可注册域名，子域名自动包含）。只有这些站点的 Cookie 会同步到内置浏览器（Cloudflare 验证、网页登录共用），浏览器模式的 `network.origin` 也必须属于它们。省略时从 `homepage`、`network.origin`、`account.cookieUrl/loginUrl` 推导。
- 从网址或仓库安装源时，App 会先在不能联网的沙盒中读取脚本信息，向用户展示名称、版本、SHA-256、声明的站点及风险提示，确认后才安装。源仓库的 `index.json` 条目可以带 `sha256` 字段，下载内容不匹配时拒绝安装。

## 账号

```js
account: {
  type: 'password' | 'cookies',
  title, hint, required: false,
  fields: [{ key: 'email', label: '邮箱' }, { key: 'password', label: '密码', secret: true }],
  loginUrl?, cookieUrl?, requiredCookies?: ['ipb_member_id'],   // 提供后可以在网页中登录，App 自动获取 Cookie
  loginDomains: ['accounts.google.com', 'appleid.apple.com'], // 可选：第三方授权页域名，仅用于登录导航
  async login(values) { return { name } },
  async logout() {},
  async status() { return { loggedIn, name, configured } },
  managedAccount: true,                 // 可选：提供专用自动维护账号
  async enableManaged() {},             // 仅在用户确认注册后调用
}
```

`account.loginDomains` 由源插件声明实际使用的第三方授权域名，包含其子域名；仅在用户打开网页登录页时放行 HTTPS 默认端口 443 的跳转，拒绝 URL 用户凭据、IP、localhost 及 `.local`。普通验证页、访问确认、源请求与 Cookie 导入仍按 `domains` 校验，不能把第三方授权域名加入 `domains` 来扩大权限。登录页支持原窗口跳转及保留 `window.opener` 的授权弹窗，弹窗继续使用相同域名检查。停留在授权页时不判断源站登录完成，回到源站后才同步源站 Cookie。第三方身份提供商仍可能限制内嵌浏览器登录。

当前官方源：Pixiv 声明 Google、Apple、Facebook、微博及微博 SSO 域名；X 声明 Google、Apple；StoriesOnline 声明独立账号服务 `login.wlpc.com`。第三方 Cookie 不导入源的 Cookie 罐，也不随清除源 Cookie 自动删除；第三方网页登录态由系统 WebView 管理。

`configured` 表示已有账号配置，独立于当前是否成功登录。`managedAccount: true` 声明源支持专用自动维护账号；源设置使用同名 `managedAccount` 开关。宿主必须先展示自动注册说明并取得用户确认，再保存启用设置并调用 `account.enableManaged()`。注册前应保存候选凭据并 `await this.store.flush()`，确保失败或应用重启后仍可恢复同一账号。

哔咔示例将手动凭据与专用账号分开保存，现有手动账号不得被专用账号覆盖。关闭开关保留专用账号，重新开启复用；Token 过期只重新登录，不重复注册。注册失败或响应丢失后重试原候选账号，避免产生多余账号。账号密码、Token 和源状态都是用户本机数据，文档和日志中不要输出真实凭据。

## 国际化

应用界面支持 `zh-Hans`、`zh-Hant`、`ja`、`ko`、`en`、`es`、`ru`、`ar`。Material、Cupertino 以及系统控件使用对应语言；阿拉伯语界面从右到左。界面语言设置立即生效并持久保存，默认跟随系统；中文的脚本和地区决定使用简体或繁体。

Flutter 界面统一调用 `tr('已选 {count}', {'count': count})`，或 `context.tr`。消息使用中文原文作资源键，参数采用 `{name}`，八语言资源位于 `assets/i18n/`。新增或修改可见文案时必须同步更新全部资源并保持占位符一致。插件静态名称、说明、浏览标签、选项和错误提示在应用展示时进行资源映射；远端作品标题、作者、标签、用户输入和持久化协议键保持原文。

## 错误码

用 `throw Park.error(code, message)` 抛出错误，App 会根据错误码给出对应的引导：

| code | App 的处理 |
|------|-----------|
| `CLOUDFLARE` | “去验证”按钮：打开内置浏览器 |
| `CONFIRM_REQUIRED` | “去确认”按钮：等待用户完成源声明的访问确认 |
| `LOGIN_REQUIRED` | “去登录”按钮：打开源设置的账号区 |
| `NOT_FOUND` | 显示“内容不存在” |
| `BLOCKED` | 显示“访问受限”（例如 IP 被封、配额用尽），图片不再重试 |
| `NETWORK` / `HTTP` / `PARSE` | 显示错误信息与“重试”按钮 |

## 源仓库

一个仓库就是一个 `index.json`，可以放在静态托管上（例如 GitHub raw）。用户在“源站管理 → 添加源”中输入仓库地址即可浏览、安装和更新：

```json
{
  "name": "我的源仓库",
  "apiVersion": 1,
  "sources": [
    {
      "key": "mysite",
      "name": "我的站点",
      "version": "0.0.1",
      "description": "一句话介绍",
      "url": "https://example.com/sources/mysite.js",
      "sha256": "脚本 UTF-8 原文的 64 位十六进制 SHA-256",
      "apiVersion": 1
    }
  ]
}
```

`url` 是脚本完整地址；也可以用相对于 `index.json` 的 `file`。第三方仓库通过用户确认后手动安装，`sha256` 可选，提供时会校验下载内容。

官方更新采用严格规则：版本必须是由点分隔、无前导零的三段非负整数（例如 `0.0.1`、`0.1.0`），逐段按数字比较；不接受缺段、多段或预发布后缀。必须提供脚本 UTF-8 原文的 `sha256`，不修剪空白、不转换换行；脚本声明的 `key`、`version` 必须与索引一致。`apiVersion` 必须与当前 App 运行时完全匹配，不匹配时拒绝更新，需要先使用支持该 API 的 App；不提供兼容分支。

### App 中的官方更新

“我的 → 软件与插件更新”和“源站管理”默认开启“启动时检查插件更新”。每次启动只读取官方索引，发现新版本后提示；用户确认后才下载、校验并安装。回到前台时保留 12 小时检查间隔，失败也记录检查时间，避免频繁重试。关闭自动检查后仍可使用“立即检查更新”。只检查已安装的内置源和官方在线源，不自动安装新源，也不接管用户自行安装的同名第三方源。

确认安装时再次验证源身份、版本、来源、API 和摘要，等待初始化及状态持久化成功才完成更新。失败保留旧脚本与用户状态；应用在安装期间中断时，下次启动先恢复。启动不会用安装包内置脚本覆盖已有插件；只有未安装过的插件才首次加载内置脚本。已有插件脚本缺失时保留登记信息与用户数据，等待用户明确恢复或确认更新。“恢复内置源”经用户确认后可以主动回退到当前安装包版本；后续检查发现官方新版时仍需再次确认升级。

软件检查默认开启。Android 用户确认后在应用内下载适合设备的官方 APK，验证大小、SHA-256、包名、版本与签名后调起系统安装界面，安装仍需用户确认。需要安装权限时，用户授权并返回后点击“继续安装”。支持下载进度、取消与失败重试，官方发布页作为失败时的备用入口；其他平台使用官方发布页手动下载。

### 官方源的发布

官方源沿用公开主仓库 [drdon1234/Hentai-Park](https://github.com/drdon1234/Hentai-Park)，客户端固定入口为：

```text
https://raw.githubusercontent.com/drdon1234/Hentai-Park/sources/index.json
```

源 `key` 只允许 `[A-Za-z0-9_-]`，长度为 1–100，保留 `_app` 不可使用；脚本文件名必须是 `{key}.js`。

`assets/sources/index.json` 是唯一维护的源清单，其中的 `file` 指向同目录下的唯一脚本源码。文件名必须符合 `[A-Za-z0-9_-]+.js`，不接受子目录、符号链接或文件名主体中的点号，与客户端官方源地址校验保持一致。`tools/publish_sources.mjs` 生成发布索引：每条记录包含 `key`、`name`、`version`、`category`、`description`、`url`、`sha256` 和 `apiVersion`。脚本 URL 固定到本次源码的完整 40 位提交号：

```text
https://raw.githubusercontent.com/drdon1234/Hentai-Park/<源码提交 SHA>/assets/sources/<file>
```

`sources` 分支只保存生成的根目录 `index.json`，不复制脚本，也不手工维护第二份源清单。更新脚本时必须同时提升脚本和清单中的版本；发布器拒绝降版，也拒绝相同版本对应不同脚本内容。相同版本且内容未变可以重复发布，正常升版不受旧索引版本影响。

发布器只依赖 Node.js 内置模块，可在 Node.js 22 或更新版本中离线运行。它检查清单、文件存在性与目录边界，在不提供网络和存储接口的独立上下文中加载共享运行时及脚本，然后采用 App 安装预览相同的 `Park.__pending` / `Park.manifest` 探测方式核对 `key`、`version` 和 API。探测不调用 `setup`、`init`、登录或站点业务方法，不能代替源站联网可用性测试。

本地预览示例（输出位于已忽略的 `test/`，不会发布；提交号应使用对应源码的真实 SHA）：

```powershell
node tools/publish_sources.mjs --commit '<完整 40 位源码提交 SHA>' --output 'test/official-source-index.json'
```

需要检查已有发布时，再传入 `--previous '旧索引本地路径'`。旧索引无效时校验失败，不会静默跳过版本保护。工作区存在未提交修改时，本地结果只用于预览；正式发布由工作流检出的源码提交生成。

`.github/workflows/publish-sources.yml` 仅在主仓库默认 `main` 分支相关文件推送，或从 `main` 手动触发时运行。工作流串行执行，每个任务开始时检出最新 `main`，以实际检出的提交号固定脚本地址和发布记录。任务运行中后续文档提交不会阻止发布；后续源文件提交会触发下一个串行任务。工作流先下载现有稳定索引并完成所有离线校验，再用一次普通 Git 推送原子更新 `sources` 分支；校验失败或 `sources` 分支发生并发变更时不会覆盖线上索引。首次没有稳定索引时可以创建发布。发布只说明脚本与索引通过上述校验，站点访问、账号登录和图片或视频加载仍需单独验证。
