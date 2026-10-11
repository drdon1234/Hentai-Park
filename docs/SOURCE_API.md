[简体中文](SOURCE_API.md) · [繁體中文](i18n/zh-Hant/SOURCE_API.md) · [日本語](i18n/ja/SOURCE_API.md) · [한국어](i18n/ko/SOURCE_API.md) · [English](i18n/en/SOURCE_API.md) · [Español](i18n/es/SOURCE_API.md) · [Русский](i18n/ru/SOURCE_API.md) · [العربية](i18n/ar/SOURCE_API.md)

# 源插件开发指南

HentaiPark 的每个源站都是一个独立的 JavaScript 文件。App 在运行时加载它们：可以从源仓库安装、更新、启用 / 停用，**不需要重新编译 App**。
内置源位于 [`assets/sources/`](../assets/sources/)，可以直接当作示例参考。

## 运行环境

- 源脚本运行在 App 内的无界面 WebView 中（完整的现代 JS 与 `DOMParser`）。网络、加解密与 Cookie 都由原生层提供，因此**没有 CORS 限制**。
- 同一份运行时（[`assets/runtime/park_runtime.js`](../assets/runtime/park_runtime.js)）也能在 Node 中运行，开发时可以直接对真实站点做冒烟测试：

  ```bash
  cd tools/source-runner && npm install
  node ../../test/source-runner/smoke.mjs nhentai.js --keyword "tag:\"full color\""
  ```

  `smoke.mjs` 是位于 `test/source-runner/` 的本地测试文件，不随仓库分发。它会依次测试：每个 feed（含第 2 页）→ 搜索 → 随机 → 详情 → 封面 → 章节 → 首页与末页图片的实际下载。

## 注册一个源

```js
Park.register({
  key: 'mysite',              // 唯一标识，安装后不可更改
  name: '我的站点',
  version: '0.0.1',           // 仓库里版本号更高时 App 会提示更新
  type: 'comic',              // comic | video
  color: '#E5355F',           // 品牌色：用于源入口卡片、源页面主题色
  description: '一句话介绍',
  homepage: 'https://example.com',
  domains: ['example.com'],                   // 所属站点，见“隔离与安全”；省略时从 homepage 等地址推导
  linkPatterns: ['example\\.com/g/(\\d+)'],   // 聚合搜索中粘贴链接时用于直达；第 1 个分组是作品 ID
  idPattern: '^(\\d+)$',                      // 直接输入编号时用于直达
  imageHeaders: { Referer: 'https://example.com/' },  // 加载封面与图片时默认携带
  network: { mode: 'native' },                // 见“网络”一节

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
  async detail(id) {},
  async chapter(id, chapterId) {},            // 漫画
  async resolveImage({ id, chapterId, index, token, retry }) {},  // 可选：延迟解析图片
  async thumbnails(id, page) {},              // 可选：分页加载预览缩略图
  async videos(id) {},                        // 视频
});
```

方法里可以用 `this` 访问：

| 成员 | 说明 |
|------|------|
| `this.http` | `request(opts)`、`get(url, opts)`、`post(url, opts)`、`text(url, opts)`、`json(url, opts)` |
| `this.config` | 用户在源设置中选择的值（未设置时为 `default`） |
| `this.store` | 持久化键值存储：`get(key, fallback)` / `set(key, value)`，用于保存 Token、域名列表等；`await flush()` 确认写盘成功，失败抛错 |
| `this.cookies` | `get(url)` / `set(url, {name: value})` / `clear(url)` |
| `this.log(...)` | 写入 App 的“运行日志” |

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

`text()` / `json()` 遇到非 2xx 响应会自动抛错（404 → `NOT_FOUND`）。Cookie 会自动保存，并在跟随重定向时保留。

## 数据结构

**列表页**（`feed` / `search` 的返回值）

```js
{
  items: [WorkItem], page: 1, totalPages: 20, total: 500,
  hasNext: true,
  cursor: '12345',        // 可选：游标翻页的站点（如 E-Hentai）返回下一页游标，App 下次请求时原样传回
}
// 或者分区布局（feed 的 layout 为 'sections' 时）：
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

**视频**（`videos`）：`[{ quality: 1080, label: '1080P', url, headers?, preferred? }]`。视频直链通常有时效，App 每次播放 / 下载前都会重新获取。

## 选项定义

`feeds[].options`、`searchFilters`、`settings` 使用同一种格式：

```js
{ key: 'sort', label: '排序', type: 'select', default: 'date',
  values: [{ value: 'date', label: '最新' }, { value: 'popular', label: '热门', color: '#f00' }] }
// type：select（单选） | multi（多选） | number | text | password | switch
// settings 中用 options 代替 values 也可以
```

`feeds` 的每一项是源页面里的一个标签页：`{ key, label, layout?: 'grid' | 'sections', options?: [...] }`。

`defaultFeed` 指定打开源站页时默认进入哪个标签。未填写或找不到对应的 key 时，App 按 推荐 > 排行榜 > 热门 的顺序，根据 key 自动选择（key 包含 `promote` / `recommend` / `featured`，然后是 `rank` / `toplist`，然后是 `popular` / `hot` / `trending`），都没有就进入第一个标签。

## 网络

- `network.mode: 'native'`（默认）：原生 HTTP 请求，使用持久化 Cookie，可以走用户设置的代理。若检测到 Cloudflare 质询，会抛出 `CLOUDFLARE`，App 会引导用户在内置浏览器中完成验证，并把通行 Cookie 同步回原生请求。
- `network.mode: 'browser'` + `network.origin`：请求在一个打开于 `origin` 的隐藏浏览器页面中以同源 `fetch()` 发出，带有真实浏览器指纹。适用于 Cloudflare 防护较严的站点（例如 Hanime1）。

## 隔离与安全

- 每个源运行在**独立的** JS 环境（各自一个无界面 WebView）中，源之间看不到彼此的全局对象；原生桥只认调用来自哪个环境，脚本无法冒充其他源。
- 每个源有**独立的 Cookie 罐**：源发出的请求只会带上、也只会保存到它自己的 Cookie，不会读到其他源的登录状态。
- `domains` 声明源所属的站点（可注册域名，子域名自动包含）。只有这些站点的 Cookie 会同步到内置浏览器（Cloudflare 验证、网页登录共用），浏览器模式的 `network.origin` 也必须属于它们。省略时从 `homepage`、`network.origin`、`account.cookieUrl/loginUrl` 推导。
- 从网址或仓库安装源时，App 会先在不能联网的沙盒中读取脚本信息，向用户展示名称、版本、SHA-256、声明的站点及风险提示，确认后才安装。源仓库的 `index.json` 条目可以带 `sha256` 字段，下载内容不匹配时拒绝安装。

## 账号

```js
account: {
  type: 'password' | 'cookies',
  title, hint, required: false,
  fields: [{ key: 'email', label: '邮箱' }, { key: 'password', label: '密码', secret: true }],
  loginUrl?, cookieUrl?, requiredCookies?: ['ipb_member_id'],   // 提供后可以在网页中登录，App 自动获取 Cookie
  async login(values) { return { name } },
  async logout() {},
  async status() { return { loggedIn, name, configured } },
  managedAccount: true,                 // 可选：提供专用自动维护账号
  async enableManaged() {},             // 仅在用户确认注册后调用
}
```

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
| `LOGIN_REQUIRED` | “去登录”按钮：打开源设置的账号区 |
| `NOT_FOUND` | 显示“内容不存在” |
| `BLOCKED` | 显示“访问受限”（例如 IP 被封、配额用尽），图片不再重试 |
| `NETWORK` / `HTTP` / `PARSE` | 显示错误信息与“重试”按钮 |

## 源仓库

一个仓库就是一个 `index.json`，可以放在任意静态托管上（例如 GitHub raw）：

```json
{ "name": "我的源仓库", "sources": [
  { "key": "mysite", "name": "我的站点", "version": "0.0.1", "type": "comic", "file": "mysite.js", "description": "…" }
] }
```

`file` 是相对于 `index.json` 的路径（也可以写完整的 `url`）。用户在“源站管理 → 添加源”中输入仓库地址即可浏览、安装和更新。
