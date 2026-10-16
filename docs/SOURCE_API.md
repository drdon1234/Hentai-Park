[简体中文](SOURCE_API.md) · [繁體中文](i18n/zh-Hant/SOURCE_API.md) · [日本語](i18n/ja/SOURCE_API.md) · [한국어](i18n/ko/SOURCE_API.md) · [English](i18n/en/SOURCE_API.md) · [Español](i18n/es/SOURCE_API.md) · [Русский](i18n/ru/SOURCE_API.md) · [العربية](i18n/ar/SOURCE_API.md)

# 站点插件接口

[快速开始](#快速开始) · [manifest 字段](#manifest-字段) · [方法](#方法) · [运行时 API](#运行时-api) · [错误码](#错误码) · [国际化](#国际化) · [发布](#发布) · [附录：官方站点备注](#附录官方站点备注)

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

在仓库根安装共享 runner 依赖，按下例创建被忽略的 `test/source-smoke.mjs`。示例只载入 manifest；修改插件时还要用真实请求验证首页、第二页、搜索、详情、封面解码，以及章节或视频媒体。

```js
import { loadSource } from '../tools/source-runner/host.mjs';
const { manifest } = await loadSource('nhentai.js');
console.log(manifest.key, manifest.version);
```

```powershell
npm ci --prefix 'tools/source-runner'
node 'test/source-smoke.mjs'
```

## manifest 字段

```js
Park.register({
  key: 'mysite',              // 唯一标识，安装后不可更改；只允许 [A-Za-z0-9_-]，1–100 位，不能是 _app
  name: '我的站点',
  version: '0.0.1',           // 三段数字，仓库版本更高时应用提示更新
  type: 'comic',              // comic | video | novel | game：决定阅读、播放或游戏资源行为
  category: 'doujin',         // doujin | anime | aiDrama | jav | adult | shortvideo | gallery | novel | game | other
  color: '#E5355F',           // 品牌色：站点头像与站点页
  description: '一句话介绍',
  homepage: 'https://example.com',
  domains: ['example.com'],                   // 所属站点，见“隔离与安全”；省略时从 homepage 等地址推导
  linkPatterns: ['example\\.com/g/(\\d+)'],   // 搜索框粘贴链接时直达；第 1 个分组是作品 ID
  idPattern: '^(\\d+)$',                      // 直接输入编号时直达
  imageHeaders: { Referer: 'https://example.com/' },  // 封面与图片默认请求头
  network: { mode: 'native', vpnHint: true },  // 见“网络”
  media: { mode: 'browser', origin: 'https://example.com', domains: ['media.example.com'] },  // 可选 HLS 媒体权限
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
  updateSubscriptions: { /* 可选：更新订阅，见“更新订阅” */ },

  async init() {},              // 可选：运行时启动时调用一次（例如刷新域名列表）
  async onSettingsChanged() {}, // 可选：用户修改站点设置后调用
  // 以及下文“方法”中的各个方法
});
```

能力（`capabilities`）由运行时根据实现了哪些方法自动导出，插件不手写。

### 类型与分类

`type` 决定阅读、播放或游戏资源行为，`category` 决定发现页、站点管理与搜索中的分组；未知或未声明的分类归入“其他”。新增站点必须准确声明类型、分类和能力。

| 分类 | 说明 |
| --- | --- |
| `doujin` | 本子与漫画 |
| `gallery` | 美图：插画、Cosplay、写真。图片站仍声明 `type: 'comic'`，一个图集是一个作品，图片通过 `chapter()` 按顺序返回，可复用阅读、收藏和下载。分类不按张数或尺度区分 |
| `anime` | 里番 |
| `aiDrama` | AI 短剧。不接受旧的 `drama` 标识；站点自身的频道名照原样声明，应用分类不用来过滤站点频道 |
| `jav` | JAV 专门站 |
| `adult` | 综合成人视频（如 Pornhub、XVideos、91porn），`type: 'video'`。分类是内容分组，不替代站点标签和用户筛选 |
| `shortvideo` | 短视频：全屏竖向连续流，见下 |
| `novel` | 小说，`type: 'novel'` |
| `game` | 游戏，`type: 'game'` |
| `other` | 其他（订阅类站点等） |

- **短视频**（`type: 'video', category: 'shortvideo'`）：作品、搜索、收藏和历史入口直接进入连续流。每个作品是一个短视频，`videos(id, '_')` 返回当前有效媒体，不需要详情页。`feed` 的 `hasNext` 和 `cursor` 用于临近末尾时自动翻页，游标不能包含账号凭据或媒体签名。刷新从第一页开始；当前条播放，下一条暂停预加载，其余释放。站点没有搜索接口时不声明 `search`。
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

### 网络

- `network.mode: 'native'`（默认）：原生 HTTP，使用持久化 Cookie，走用户设置的代理。检测到 Cloudflare 质询时抛 `CLOUDFLARE`，应用引导用户在内置浏览器中完成验证，并把通行 Cookie 同步回原生请求。
- `network.mode: 'browser'` + `network.origin`：请求在打开于 `origin` 的隐藏浏览器页中以同源 `fetch()` 发出，带真实浏览器指纹，适合 Cloudflare 防护较严的站点。同源 GET 收到 Cloudflare 质询时，隐藏浏览器先导航到该文档完成自动验证，再重试一次原请求；仍未通过时抛 `CLOUDFLARE`。
- `network.vpnHint: true`：在中国大陆可能需要 VPN 或代理的站点声明它，等待超过 8 秒和失败时提示“可能需要 VPN 或代理”。不要把所有错误都归因于 VPN。
- `network.confirmation: { selector, readySelector, requiredCookies, message }`：需要用户明确确认（如年龄确认）的站点声明。`selector` 匹配确认弹窗，`readySelector` 匹配可访问的页面内容，`requiredCookies` 是确认后必须落地的 Cookie 名。插件遇到未确认页面时抛 `Park.error('CONFIRM_REQUIRED', message, { url })`；应用提供“去确认”入口，等弹窗消失、内容出现、Cookie 写入且导航稳定后返回。应用不会代替用户点击确认；这项声明也约束通用人机验证页，避免把年龄确认误当成已通过。
- 网络异常附带安全的 `diagnostics` 字段 `host`、`transport`、`reason`，区分 TLS 证书、握手、DNS、连接和超时。框架在调用失败时自动记录站点、方法名、错误代码、HTTP 状态和这些字段；错误消息只有在属于插件 `i18n` 或应用文案键时才以模板形式记录，占位符的值不进日志。`reason: 'TLS_HANDSHAKE_TERMINATED'` 仅表示原生 `HandshakeException.message` 恰好是 `Connection terminated during handshake`（握手完成前连接中断，不是证书校验失败）；只有 HTTPS、无请求体的 GET / HEAD 遇到它时自动重试一次，其他错误都不重试。

### 图片

- `imageNetwork: { mode: 'browser', origin, domains }`：图片 CDN 需要浏览器请求时声明。`origin` 和所有图片域名必须属于 `domains`，只允许 HTTPS 和白名单请求头；图片请求不带账号凭据、不跟随重定向，单图最多 20 MiB，仍经过解密、格式检查、解码和按站点分区的缓存。未声明时用原生图片传输。
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
- `'native'` 使用独立、无凭据的原生客户端，不读写站点 Cookie、Authorization 或代理认证；每一跳重定向都先校验目标域名。只允许 `Referer`、`Origin`、`Accept`、`Accept-Language`，前两者必须匹配 `media.origin`。
- 动态 HLS CDN 可声明 `media.scope: 'session'`（仅限 `mode: 'native'`）。框架授权插件本次解析的播放地址，再逐项授权清单内的子清单、分片、密钥及最多 8 跳重定向；授权仅存在于当前播放或下载会话，不写入 manifest、Cookie 权限或持久化白名单。所有地址保持 HTTPS 443、无凭据和片段，DNS 解析必须全部为公网地址；`198.18.0.0/15` 视为允许，它是不分配给局域网主机的基准测试保留段，Clash、sing-box、Surge 等系统 VPN 的 Fake-IP 模式把域名映射到这里。直连固定到检查后的 IP，同时保留原主机的 TLS 校验；解析到内网或其他保留地址时报“媒体主机解析到了内网或保留地址”，诊断原因为 `PRIVATE_ADDRESS`。显式配置 HTTP 代理时，仅连接用户指定的代理，媒体域名由代理解析；公网 DNS 检查由可信代理承担（支持 Fake-IP 网络），应用仍检查每一跳 URL 的 HTTPS、端口与主机格式。关闭会话会销毁授权。`media.domains` 继续约束静态会话及非 HLS 资源；动态授权不适用于直接交给系统播放器的 MP4。
- `'browser'` 在 `media.origin` 的隐藏浏览器建立媒体会话，使用 `credentials: 'omit'`、`mode: 'cors'`、`redirect: 'error'`。
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
  loginUrl?, cookieUrl?, requiredCookies?: ['ipb_member_id'],   // 提供后可以在网页中登录，应用自动获取 Cookie
  loginDomains?: ['accounts.google.com', 'appleid.apple.com'],  // 第三方授权页域名，仅用于登录导航
  async login(values) { return { name } },
  async logout() {},
  async status() { return { loggedIn, name, configured } },
  managedAccount: true,                 // 可选：提供专用自动维护账号
  async enableManaged() {},             // 仅在用户确认注册后调用
}
```

- 账号状态只在首次使用、登录、退出、网页登录后以及距上次检查超过 10 分钟时刷新，不会在每次调用后检查。`configured` 表示已有账号配置，与当前是否登录成功无关。
- `loginDomains`：插件声明站点实际使用的第三方授权域名（含子域）。只在用户打开网页登录页时放行 HTTPS 443 的跳转，拒绝 URL 用户凭据、IP、localhost 和 `.local`。普通验证页、访问确认、插件请求和 Cookie 导入仍按 `domains` 校验，不能把第三方授权域名加进 `domains` 扩大权限。登录页支持原窗口跳转和保留 `window.opener` 的授权弹窗，弹窗里沿用同一检查，空白初始页不授予外部导航权限。停留在授权页时不判断登录完成，回到站点后才同步 Cookie。第三方 Cookie 不导入插件的 Cookie 罐，也不随清除站点 Cookie 删除；其浏览器登录态由系统 WebView 管理。第三方平台仍可能限制内嵌浏览器登录。
- `type: 'session'` 用于导入已有的授权会话：声明单个保密字段（如 `session`），剪贴板内容完整保留，由插件校验，不拆成账号密码或 Cookie。登录必须真实确认授权，不凭输入格式假报成功。
- `managedAccount: true` 声明插件支持专用自动维护账号，站点设置中用同名开关。应用必须先展示自动注册说明并取得用户确认，再保存设置并调用 `account.enableManaged()`。注册前先保存候选凭据并 `await this.store.flush()`，保证失败或重启后还能恢复同一个账号。手动凭据与专用账号分开保存，专用账号不能覆盖现有手动账号；关闭开关保留专用账号，重新开启复用；Token 过期只重新登录，不重复注册。
- 账号密码、Token 和插件状态都是用户本机数据，文档和日志里不要出现真实凭据。

## 方法

方法里的 `this` 见“运行时 API”。所有方法都可以是 `async`。

```js
async feed(key, { page, cursor, options }) {}      // 站点页标签
async search({ keyword, page, cursor, filters }) {}
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

**WorkItem**：`{ id, title, subtitle?, cover, coverAspect?, pages?, rating?, likes?, views?, language?, category?, badge?, badgeColor?, duration?, uploaded?, tags?, mediaKind?, workCode?, editions? }`

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
  related?: [WorkItem], series?: [WorkItem], variants?: [WorkItem],
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

返回 `[{ quality: 1080, label: '1080P', url, headers?, format?, preferred? }]`。直链通常有时效，应用每次播放或下载前都会重新获取。

- 多集视频在 `detail(id).chapters` 按播放顺序返回 `[{ id, title }]`，每个 `id` 必须稳定，不能用画质或临时媒体 URL 代替。应用用同一个 ID 选集、记录进度、下载和续播，并调用 `videos(id, episodeId)` 获取该集资源。单集用 `singleChapterId`，没有时用 `'_'`。
- 省略 `format` 时按直链 MP4 播放和下载。HLS 必须返回 `format: 'hls'`，并声明 `media` 权限。
- HLS 主清单（`#EXT-X-STREAM-INF`）先由应用展开成各路分段清单，按 `RESOLUTION` 得到真实清晰度。返回主清单时 `quality` 表示期望清晰度：默认选不高于它的最高实际清晰度，没有符合项时选最高档。每路必须是音视频复用的 MPEG-TS；独立的 `AUDIO`、`VIDEO`、`SUBTITLES` 和未通过静态域名或会话授权的地址一律拒绝。`#EXT-X-I-FRAME-STREAM-INF` 预览轨道被忽略。单路清单无法确定分辨率时提供 `label: '原画'`，不要把期望画质当成真实分辨率。
- 只支持带 `#EXT-X-ENDLIST` 的完整、连续 MPEG-TS 点播清单；支持 `METHOD=AES-128`、`KEYFORMAT=identity` 的 CBC/PKCS7 解密，密钥恰好 16 字节，IV 可显式提供或由媒体序号推导。密钥只保存在当前会话内存。不支持直播、SAMPLE-AES、其他 KEYFORMAT、`EXT-X-MAP`、`EXT-X-BYTERANGE`、fMP4、discontinuity 和 gap；非标准的 `#EXT-X-TOKEN` 会被移除。
- 播放时使用只绑定 `127.0.0.1` 的随机端口和随机令牌，通过有限 URL 注册表按需读取已验证的分段，关闭会话即取消请求。HLS 离线下载目前只支持 Android：逐段验证并保存 SHA-256，可恢复、可取消，最后由 Media3 封装为 MP4，完整成品才进入离线库。

### 应用内网页视频：`webVideo`

当站点只提供真实播放网页、没有可验证的媒体资源时，实现 `webVideo(id, episodeId)`，不要虚构 `videos` 或章节。返回：

```js
return {
  url: 'https://player.example.com/watch/1',
  navigationDomains: ['player.example.com'],
  frameDomains: [],
};
```

- 运行时自动导出 `capabilities.webVideo`。同时实现 `videos` 时优先原生播放器。详情和历史入口均进入应用内网页，隐藏应用的下载与虚构选集，不承诺精确断点续播；页面控制由上游提供。
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
- `posts` 的游标是不透明字符串，最后一页 `hasNext: false`，没有媒体的页面也允许继续翻页。`locked` 表示权限不足；`previewOnly` 明示只是公开预览，不能把缩略图冒充全文。
- 不能提供直链的授权附件使用 `media[].resource`，并实现 `mediaChunk(resource, offset)`：每次最多 128 KiB，offset 按 128 KiB 对齐；resource 必须含整数 `size` 和稳定、非秘密的字符串 `cacheKey`（不随授权凭据或临时引用变化）。框架校验总大小和每块完整性，原子写入自己的缓存路径，单个附件最大 512 MiB；资源不能决定本地路径。签名链接和 resource 不保存到订阅记录。
- 保存订阅不会自动关注或加入；未经验证的写操作必须引导用户到原站手动操作，不执行静默关注、加入或付费操作。

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

全局工具：

| 工具 | 说明 |
| --- | --- |
| `Park.html.parse(text)` | 返回标准 `Document`，可以用 `querySelector` |
| `Park.html.text(node)` / `unescape(s)` / `strip(html)` / `paragraphs(node)` | 文本处理 |
| `Park.crypto.md5Hex(text \| text[])` | MD5，可以传数组批量计算 |
| `Park.crypto.sha256Hex` / `hmacSha256Hex(key, text)` / `aesEcbDecrypt(base64, key)` / `uuid()` | 原生实现 |
| `Park.crypto.digestBytes('sha1' \| 'sha256', bytes)` | 最多 2 MiB 的 0–255 整数字节数组 |
| `Park.crypto.randomBytes(length)` | 系统安全随机字节，length 为 1–65536 |
| `Park.utils.rateLimiter(ms)` | 返回 `wait()`，保证两次请求之间的最小间隔 |
| `Park.utils.mapLimit(items, n, fn)` / `lruMap(n)` / `parseCount('1.2万')` / `formatDate(ts)` | 其他常用工具 |
| `Park.error(code, message, extra?)` | 创建带错误码的错误，见“错误码” |

### `http.request(opts)`

```js
await this.http.request({
  url, method: 'GET', headers: {}, params: { q: 'x' },   // params 拼接到 URL
  json: {...} | form: {...} | body: 'raw' | bodyBase64: '...',
  timeout: 15000,
  responseType: 'text' | 'base64',
  followRedirects: false, // 可选，默认 true；仅原生网络支持
});
// → { status, headers, body, url, ok, json() }
```

- `text()` / `json()` 遇到非 2xx 自动抛错（404 → `NOT_FOUND`）。Cookie 自动保存，并按每次重定向的目标地址重新选择。
- 原生网络设置 `followRedirects: false` 时返回原始 30x 响应和 `Location`，不访问跳转目标；浏览器网络不支持该选项并返回 `CONFIG`。需要检查 30x 时用 `request()` / `get()`，不要用要求 2xx 的 `text()` / `json()`。
- `bodyBase64` 是原始二进制请求体（最多 2 MiB），不能与 `body` 或浏览器模式同时使用；与文本请求使用相同的域名隔离、TLS 和重定向规则。插件不能自行开放浏览器网络、WebSocket 或任意文件访问。

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

- `feed` 的实时结果保留插件返回的全部字段；磁盘上的主页缓存只保存作品 ID、标题、封面、标签、上传者、媒体类型、分类和展示用统计等白名单元数据，`url`、访问凭据、媒体列表和帖子不落盘。不要把凭据放进 ID、封面地址或分页游标。需要动态媒体或帖子展示的结果不缓存。
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

- `section` 可为 `market`（市场榜，`rankingOnly` 默认）或 `site`（站点榜，普通内容源默认），页面分区显示。`kind` 可为 `work`、`actress`、`seller`、`genre`；人物榜须返回人物或卖家条目，不可伪装成作品。动态选项标记 `dynamic: true`，由 `rankingOptions(board)` 返回真实选择项，运行时会在请求前校验。`category` 决定搜索范围，首批支持 `jav`、`doujin`、`anime`。`metric` 明确标示销量、人气或站内热度；站点默认热门不能称为销量榜。
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

`url` 是脚本完整地址，也可以用相对 `index.json` 的 `file`。第三方仓库由用户确认后手动安装；`sha256` 可选，提供时校验下载内容。

### 版本与更新规则

- 版本必须是三段、点分隔、无前导零的非负整数（如 `0.0.1`），逐段按数字比较；不接受缺段、多段或预发布后缀。
- 官方更新必须提供脚本 UTF-8 原文的 `sha256`（不修剪空白、不转换换行），脚本声明的 `key`、`version` 必须与索引一致；`apiVersion` 必须与当前应用运行时完全一致，否则拒绝更新。
- 插件版本与应用版本分开管理。修改插件脚本（包括 `i18n`）时，同时提高脚本和 `assets/sources/index.json` 中的版本；发布器拒绝降版，也拒绝同一版本对应不同内容。

### 应用内的官方更新

- “我的 → 站点”和“我的 → 关于 → 更新”中的“启动时检查插件更新”默认开启：每次启动只读取官方索引，发现新版本后提示，用户确认后才下载、校验并安装。回到前台时保留 12 小时间隔，失败也记录检查时间。关闭自动检查后仍可手动检查。只检查已安装的内置插件和官方插件，不自动安装新插件，也不接管用户自装的同名第三方插件。
- 确认安装时再次验证身份、版本、来源、API 和摘要，等待初始化和状态持久化成功才算完成；失败保留旧脚本和用户状态，安装期间中断的话下次启动先恢复。启动不会用安装包内置的脚本覆盖已有插件；脚本缺失时保留登记信息和用户数据，等用户明确恢复或更新。“恢复内置版本”经用户确认后回退到当前安装包中的版本。
- 应用自身更新同样默认检查：Android 上用户确认后在应用内下载适合设备的官方 APK，校验大小、SHA-256、包名、版本与签名后调起系统安装界面；支持进度、取消与重试，官方发布页作为备用入口。

### 官方插件的发布

官方插件发布在主仓库 [drdon1234/Hentai-Park](https://github.com/drdon1234/Hentai-Park)，应用固定读取：

```text
https://raw.githubusercontent.com/drdon1234/Hentai-Park/sources/index.json
https://raw.githubusercontent.com/drdon1234/Hentai-Park/rankings/index.json
```

- `assets/sources/index.json` 是唯一维护的清单，`file` 指向同目录下的脚本，文件名必须是 `{key}.js`（`[A-Za-z0-9_-]+.js`，不接受子目录、符号链接或文件名中的点号）。
- `tools/publish_sources.mjs` 生成发布索引，每条记录包含 `key`、`name`、`version`、`category`、`description`、`rankingOnly`、`url`、`sha256`、`apiVersion`，脚本 URL 固定到本次源码的完整提交号：`https://raw.githubusercontent.com/drdon1234/Hentai-Park/<提交 SHA>/assets/sources/<file>`。源码始终在主分支维护；`sources` 和 `rankings` 分支各只保存生成的 `index.json`，按 `rankingOnly` 分流，不重复维护源码。清单标记必须与运行时 manifest 一致。
- 发布器只依赖 Node.js 22+ 内置模块，可以离线运行：检查清单、文件和目录边界，在不提供网络和存储的上下文中加载运行时和脚本，用与安装预览相同的 `Park.__pending` / `Park.manifest` 方式核对 `key`、`version` 和 API。它不调用 `init`、登录或站点方法，不能代替真实请求验证。

```powershell
node tools/publish_sources.mjs --commit '<完整 40 位提交 SHA>' --output 'test/official-source-index.json'
node tools/publish_sources.mjs --commit '<完整 40 位提交 SHA>' --channel rankings --output 'test/official-ranking-index.json'
```

需要对比已有发布时加 `--previous '旧索引路径'`，使用对应频道的旧索引；旧索引无效时校验失败。`.github/workflows/publish-sources.yml` 只在主仓库 `main` 分支相关文件推送或手动触发时运行，工作流排队，通过矩阵分别校验并用普通推送原子更新两个频道；校验失败或分支有并发变更时不会覆盖线上索引。应用独立读取两个索引，一个失败仍检查另一个；频道标记不符或跨索引重复 key 的条目不能安装或覆盖其他条目。下载时仍验证固定提交 URL、SHA-256、版本、API 和频道，确认安装后才生效。

### 构建生成的插件

Telegram 插件的唯一实现是 `assets/sources/telegram_entry.mjs`，`assets/sources/telegram.js` 由构建生成，不得手改：

```powershell
npm ci --prefix 'tools/source-runner'
node tools/build_subscription_sources.mjs
```

它使用 [@mtproto/core 6.3.0](https://github.com/alik0211/mtproto-core)（GPL-3.0，[许可证](licenses/mtproto-core.txt)，依赖汇总见 [第三方许可](licenses/telegram-dependencies.txt)）。站点适配替换了传输、密码学和存储，不开放库默认的 WebSocket、浏览器 localStorage 或调试日志。

## 附录：官方站点备注

维护官方插件时需要知道的站点约定。站点会改版，以插件代码为准。

**游戏**

- 默认顺序 KUN Galgame → GalgameX → 次元茶馆。GalgameX 与 KUN 默认开启 NSFW（分别用游客 `content-filter` 接口和 `include_nsfw` 参数）。
- GalgameX 默认本周热门。资源更新列表使用前端动态发现的 Next Server Action，动作编号缓存 15 分钟，失效后重新发现，不执行远端脚本；详情从 SSR Flight 数据解析。公开资源用主机与路径哈希作为稳定渠道编号，解析后按主机及文件名/分享编号匹配，拒绝不匹配或重复匹配，不依赖临时链接的顺序。
- KUN 默认七日浏览排行，使用公开原生 API；下载接口只在点击时调用，避免预取增加站点下载计数。按接口总数遍历资源页，重复页或提前空页报错。
- 次元茶馆使用浏览器模式和独立登录，默认 Galgame 资源区热门；列表从首楼附件补封面，请求间隔 400ms。资源列表只读；只有用户确认回复后才按完整表单发送“感谢分享，好人一生平安”。已解锁不发帖；响应不明时保留状态并引导检查原帖，重启也不重复发送。

**小说**

| 站点 | 默认入口 | 范围与限制 |
| --- | --- | --- |
| Book18 | 推荐 | 中文长篇与短篇，目录沿站点顺序 |
| Cool18 | 精华 | 仅禁忌书屋；每个主帖是独立作品，不合并回复或同名帖子；部分内容需要账号权限 |
| Canovel | 最新 | 支持文章内正文分页 |
| Literotica | 排行 | 英文；搜索排除非英文、有声、教程、评论与随笔分类 |
| Lush Stories | 推荐 | 英文；排除有声与诗歌分类 |
| StoriesOnline | 作者推荐 | 英文；匿名正文被截断时提示登录，不把预览存为完整章节 |
| 69story | 最新 | 中文；支持分类、搜索、目录及分章阅读 |

**订阅**

| 平台 | 内容 | 登录 |
| --- | --- | --- |
| X / Twitter | 匿名公开媒体；登录后的授权动态与媒体 | 网页登录，或填写 `auth_token`、`ct0` |
| Telegram | 公开频道预览；登录后的频道历史与附件 | 导入已有 Telegram WebK 本地存储会话 |
| myfans.jp | 创作者目录、公开图片、公开视频与试看预览 | 会员登录未验证 |
| pixivFANBOX | 公开目录与封面预览 | 会员登录未验证 |

- X 的 `ct0` 必须与 `X-CSRF-Token` 对应，会话可能过期或被撤销。登录后从当前网页加载操作编号和 feature flags，再读取 UserTweets，只保留目标作者的媒体（排除转推和引用）。匿名第三方代理不会收到 X Cookie。
- Telegram 的本地存储不是 Cookie：导入内容需要 `dc` 和对应的 `dcN_auth_key`（512 位十六进制），可以是 JSON 或 `key=value` 文本。插件只恢复已有 WebK 会话，不发起验证码登录、不注册自有客户端；退出只删除本应用保存的会话。附件按 128 KiB 分块读取，单个最多 512 MiB；媒体引用过期时刷新一次。网络走原生隔离 HTTP 桥，不开放 WebView fetch / WebSocket。
- OnlyFans、Fantia、Patreon、Fansly 未完成媒体读取链路，没有加入官方清单。首页能打开不等于可以订阅媒体，也不提供付费权限绕过。
