[簡體中文](../../SOURCE_API.md) · [繁體中文](SOURCE_API.md) · [日本語](../ja/SOURCE_API.md) · [한국어](../ko/SOURCE_API.md) · [English](../en/SOURCE_API.md) · [Español](../es/SOURCE_API.md) · [Русский](../ru/SOURCE_API.md) · [العربية](../ar/SOURCE_API.md)

# 源外掛開發指南

HentaiPark 的每個源站都是一個獨立的 JavaScript 檔案。App 在執行時載入它們：可以從源倉庫安裝、更新、啟用 / 停用，**不需要重新編譯 App**。
內建源位於 [`assets/sources/`](../../../assets/sources/)，可以直接當作示例參考。

## 執行環境

- 源指令碼執行在 App 內的無介面 WebView 中（完整的現代 JS 與 `DOMParser`）。網路、加解密與 Cookie 都由原生層提供，因此**沒有 CORS 限制**。
- 同一份執行時（[`assets/runtime/park_runtime.js`](../../../assets/runtime/park_runtime.js)）也能在 Node 中執行，開發時可以直接對真實站點做冒煙測試：

  ```bash
  cd tools/source-runner && npm install
  node ../../test/source-runner/smoke.mjs nhentai.js --keyword "tag:\"full color\""
  ```

  `smoke.mjs` 是位於 `test/source-runner/` 的本機測試檔案，不隨儲存庫分發。它會依次測試：每個 feed（含第 2 頁）→ 搜尋 → 隨機 → 詳情 → 封面 → 章節 → 首頁與末頁圖片的實際下載。

## 註冊一個源

```js
Park.register({
  key: 'mysite',              // 唯一標識，安裝後不可更改
  name: '我的站點',
  version: '0.0.1',           // 倉庫裡版本號更高時 App 會提示更新
  type: 'comic',              // comic | video
  color: '#E5355F',           // 品牌色：用於源入口卡片、源頁面主題色
  description: '一句話介紹',
  homepage: 'https://example.com',
  domains: ['example.com'],                   // 所屬站點，見“隔離與安全”；省略時從 homepage 等地址推導
  linkPatterns: ['example\\.com/g/(\\d+)'],   // 聚合搜尋中貼上連結時用於直達；第 1 個分組是作品 ID
  idPattern: '^(\\d+)$',                      // 直接輸入編號時用於直達
  imageHeaders: { Referer: 'https://example.com/' },  // 載入封面與圖片時預設攜帶
  network: { mode: 'native' },                // 見“網路”一節

  settings: [ /* 選項定義，見下文 */ ],
  account: { /* 可選，見“賬號” */ },
  defaultFeed: 'ranking',                     // 開啟源站頁時預設進入的標籤（feeds 中的 key）
  feeds: [ /* 瀏覽頁標籤，見下文 */ ],
  searchFilters: [ /* 搜尋篩選項 */ ],
  searchHint: '搜尋技巧提示',

  async init() {},                            // 可選：載入時呼叫一次（例如重新整理域名列表）
  async onSettingsChanged() {},               // 可選：使用者修改源設定後呼叫

  async feed(key, { page, cursor, options }) {},
  async search({ keyword, page, cursor, filters }) {},
  async random() {},                          // 返回作品 ID
  async detail(id) {},
  async chapter(id, chapterId) {},            // 漫畫
  async resolveImage({ id, chapterId, index, token, retry }) {},  // 可選：延遲解析圖片
  async thumbnails(id, page) {},              // 可選：分頁載入預覽縮圖
  async videos(id) {},                        // 影片
});
```

方法裡可以用 `this` 訪問：

| 成員 | 說明 |
|------|------|
| `this.http` | `request(opts)`、`get(url, opts)`、`post(url, opts)`、`text(url, opts)`、`json(url, opts)` |
| `this.config` | 使用者在源設定中選擇的值（未設定時為 `default`） |
| `this.store` | 持久化鍵值儲存：`get(key, fallback)` / `set(key, value)`，用於儲存 Token、域名列表等；`await flush()` 確認寫盤成功，失敗拋錯 |
| `this.cookies` | `get(url)` / `set(url, {name: value})` / `clear(url)` |
| `this.log(...)` | 寫入 App 的“執行日誌” |

全域性工具：

| 工具 | 說明 |
|------|------|
| `Park.html.parse(text)` | 返回標準 `Document`，可以使用 `querySelector` |
| `Park.html.text(node)` / `unescape(s)` / `strip(html)` | 文字處理 |
| `Park.crypto.md5Hex(text \| text[])` | MD5，可以傳陣列批次計算 |
| `Park.crypto.sha256Hex` / `hmacSha256Hex(key, text)` / `aesEcbDecrypt(base64, key)` / `uuid()` | 原生實現，速度快 |
| `Park.utils.rateLimiter(ms)` | 返回 `wait()`，保證兩次請求之間的最小間隔 |
| `Park.utils.mapLimit(items, n, fn)` / `lruMap(n)` / `parseCount('1.2万')` / `formatDate(ts)` | 其他常用工具 |
| `Park.error(code, message)` | 丟擲帶錯誤碼的錯誤，見下文 |

### `http.request(opts)`

```js
await this.http.request({
  url, method: 'GET', headers: {}, params: { q: 'x' },   // params 會拼接到 URL
  json: {...} | form: {...} | body: 'raw',
  timeout: 15000,
  responseType: 'text' | 'base64',
});
// → { status, headers, body, url, ok, json() }
```

`text()` / `json()` 遇到非 2xx 響應會自動拋錯（404 → `NOT_FOUND`）。Cookie 會自動儲存，並在跟隨重定向時保留。

## 資料結構

**列表頁**（`feed` / `search` 的返回值）

```js
{
  items: [WorkItem], page: 1, totalPages: 20, total: 500,
  hasNext: true,
  cursor: '12345',        // 可選：遊標翻頁的站點（如 E-Hentai）返回下一頁遊標，App 下次請求時原樣傳回
}
// 或者分割槽佈局（feed 的 layout 為 'sections' 時）：
{ sections: [{ title: '連載更新', items: [WorkItem] }], hasNext: false }
```

**WorkItem**：`{ id, title, subtitle?, cover, coverAspect?, pages?, rating?, likes?, views?, language?, category?, badge?, badgeColor?, duration?, uploaded?, tags? }`

- `coverAspect`（寬 / 高）讓網格在圖片載入之前就排好版，避免跳動。
- `badgeColor` 用於分類標籤的顏色（例如 E-Hentai 各分類的傳統配色）。

**詳情**（`detail`）：WorkItem 的全部欄位，另外包括：

```js
{
  url, authors: [], description, uploader?, size?, comments?,
  tags: [{ namespace: 'artist', label: '作者', tags: [{ name, keyword, filters?, count? }] }],
  chapters: [{ id, title }] | null,   // null 表示單章
  singleChapterId?,                   // 單章作品需要的章節 ID（例如嗶咔的 "1"）
  thumbnails?: [url | {url, width, height, offsetX, offsetY}],   // 支援雪碧圖
  related?: [WorkItem], series?: [WorkItem],
}
```

點選標籤時，App 會在本源中用 `keyword` 與 `filters` 搜尋，因此可以把標籤對映為站點原生語法（例如 `artist:"xxx"`）或篩選引數（例如 Hanime1 的 `tags[]`）。

**章節**（`chapter`）

```js
{ pages: [
  { url, headers?, fallbacks?: [url], width?, height?, transform? },  // 地址已知
  { token: '12' },                                                      // 延遲解析：App 會呼叫 resolveImage
]}
```

- `fallbacks`：備用映象，主地址失敗時按順序嘗試。
- `transform: { type: 'unscramble-strips', segments: N }`：圖片被橫向切成 N 條並倒序存放時（禁漫），App 會在 GPU 上原生還原。下載的離線檔案儲存原圖，顯示時再還原。
- `resolveImage` 返回 `{ url, headers?, width?, height?, cacheKey? }`。失敗時 App 會遞增 `retry` 重新呼叫，源可以藉此換一個伺服器（E-Hentai 的 `nl` 引數）。

**影片**（`videos`）：`[{ quality: 1080, label: '1080P', url, headers?, preferred? }]`。影片直鏈通常有時效，App 每次播放 / 下載前都會重新獲取。

## 選項定義

`feeds[].options`、`searchFilters`、`settings` 使用同一種格式：

```js
{ key: 'sort', label: '排序', type: 'select', default: 'date',
  values: [{ value: 'date', label: '最新' }, { value: 'popular', label: '熱門', color: '#f00' }] }
// type：select（單選）| multi（多選）| number | text | password | switch
// settings 中也可以用 options 代替 values
```

`feeds` 的每一項是源頁面裡的一個標籤頁：`{ key, label, layout?: 'grid' | 'sections', options?: [...] }`。

`defaultFeed` 指定開啟源站頁時預設進入哪個標籤。未填寫或找不到對應的 key 時，App 按 推薦 > 排行榜 > 熱門 的順序，根據 key 自動選擇（key 包含 `promote` / `recommend` / `featured`，然後是 `rank` / `toplist`，然後是 `popular` / `hot` / `trending`），都沒有就進入第一個標籤。

## 網路

- `network.mode: 'native'`（預設）：原生 HTTP 請求，使用持久化 Cookie，可以走使用者設定的代理。若檢測到 Cloudflare 質詢，會丟擲 `CLOUDFLARE`，App 會引導使用者在內建瀏覽器中完成驗證，並把通行 Cookie 同步回原生請求。
- `network.mode: 'browser'` + `network.origin`：請求在一個開啟於 `origin` 的隱藏瀏覽器頁面中以同源 `fetch()` 發出，帶有真實瀏覽器指紋。適用於 Cloudflare 防護較嚴的站點（例如 Hanime1）。

## 隔離與安全

- 每個源執行在**獨立的** JS 環境（各自一個無介面 WebView）中，源之間看不到彼此的全域性物件；原生橋只認呼叫來自哪個環境，指令碼無法冒充其他源。
- 每個源有**獨立的 Cookie 罐**：源發出的請求只會帶上、也只會儲存到它自己的 Cookie，不會讀到其他源的登入狀態。
- `domains` 宣告源所屬的站點（可註冊域名，子域名自動包含）。只有這些站點的 Cookie 會同步到內建瀏覽器（Cloudflare 驗證、網頁登入共用），瀏覽器模式的 `network.origin` 也必須屬於它們。省略時從 `homepage`、`network.origin`、`account.cookieUrl/loginUrl` 推導。
- 從網址或倉庫安裝源時，App 會先在不能聯網的沙盒中讀取指令碼資訊，向使用者展示名稱、版本、SHA-256、宣告的站點及風險提示，確認後才安裝。源倉庫的 `index.json` 條目可以帶 `sha256` 欄位，下載內容不匹配時拒絕安裝。

## 賬號

```js
account: {
  type: 'password' | 'cookies',
  title, hint, required: false,
  fields: [{ key: 'email', label: '郵箱' }, { key: 'password', label: '密碼', secret: true }],
  loginUrl?, cookieUrl?, requiredCookies?: ['ipb_member_id'],   // 提供後可以在網頁中登入，App 自動獲取 Cookie
  async login(values) { return { name } },
  async logout() {},
  async status() { return { loggedIn, name, configured } },
  managedAccount: true,                 // 可選：提供專用自動維護賬號
  async enableManaged() {},             // 僅在使用者確認註冊後呼叫
}
```

`configured` 表示已有賬號配置，獨立於當前是否成功登入。`managedAccount: true` 宣告源支援專用自動維護賬號；源設定使用同名 `managedAccount` 開關。宿主必須先展示自動註冊說明並取得使用者確認，再儲存啟用設定並呼叫 `account.enableManaged()`。註冊前應儲存候選憑據並 `await this.store.flush()`，確保失敗或應用重啟後仍可恢復同一賬號。

嗶咔示例將手動憑據與專用賬號分開儲存，現有手動賬號不得被專用賬號覆蓋。關閉開關保留專用賬號，重新開啟複用；Token 過期只重新登入，不重複註冊。註冊失敗或響應丟失後重試原候選賬號，避免產生多餘賬號。賬號密碼、Token 和源狀態都是使用者本機資料，文件和日誌中不要輸出真實憑據。

## 國際化

應用介面支援 `zh-Hans`、`zh-Hant`、`ja`、`ko`、`en`、`es`、`ru`、`ar`。Material、Cupertino 以及系統控制元件使用對應語言；阿拉伯語介面從右到左。介面語言設定立即生效並持久儲存，預設跟隨系統；中文的指令碼和地區決定使用簡體或繁體。

Flutter 介面統一呼叫 `tr('已选 {count}', {'count': count})`，或 `context.tr`。訊息使用中文原文作資源鍵，引數採用 `{name}`，八語言資源位於 `assets/i18n/`。新增或修改可見文案時必須同步更新全部資源並保持佔位符一致。外掛靜態名稱、說明、瀏覽標籤、選項和錯誤提示在應用展示時進行資源對映；遠端作品標題、作者、標籤、使用者輸入和持久化協議鍵保持原文。

## 錯誤碼

用 `throw Park.error(code, message)` 丟擲錯誤，App 會根據錯誤碼給出對應的引導：

| code | App 的處理 |
|------|-----------|
| `CLOUDFLARE` | “去驗證”按鈕：開啟內建瀏覽器 |
| `LOGIN_REQUIRED` | “去登入”按鈕：開啟源設定的賬號區 |
| `NOT_FOUND` | 顯示“內容不存在” |
| `BLOCKED` | 顯示“訪問受限”（例如 IP 被封、配額用盡），圖片不再重試 |
| `NETWORK` / `HTTP` / `PARSE` | 顯示錯誤資訊與“重試”按鈕 |

## 源倉庫

一個倉庫就是一個 `index.json`，可以放在任意靜態託管上（例如 GitHub raw）：

```json
{ "name": "我的源倉庫", "sources": [
  { "key": "mysite", "name": "我的站點", "version": "0.0.1", "type": "comic", "file": "mysite.js", "description": "…" }
] }
```

`file` 是相對於 `index.json` 的路徑（也可以寫完整的 `url`）。使用者在“源站管理 → 新增源”中輸入倉庫地址即可瀏覽、安裝和更新。
