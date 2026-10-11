[簡體中文](../../SOURCE_API.md) · [繁體中文](SOURCE_API.md) · [日本語](../ja/SOURCE_API.md) · [한국어](../ko/SOURCE_API.md) · [English](../en/SOURCE_API.md) · [Español](../es/SOURCE_API.md) · [Русский](../ru/SOURCE_API.md) · [العربية](../ar/SOURCE_API.md)

# 源外掛開發指南

HentaiPark 的每個源站都是一個獨立的 JavaScript 檔案。App 在執行時載入它們：可以從源倉庫安裝、更新、啟用 / 停用，**不需要重新編譯 App**。
內建源位於 [`assets/sources/`](../../../assets/sources/)，可以直接當作示例參考。

## 執行環境

- 源指令碼執行在 App 內的無介面 WebView 中（完整的現代 JS 與 `DOMParser`）。原生層提供加解密、Cookie 和原生 HTTP 請求；原生 HTTP 沒有 CORS 限制，瀏覽器網路與媒體請求遵循下文的獨立規則。
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
  media: { mode: 'browser', origin: 'https://example.com', domains: ['media.example.com'] },  // 可選 HLS 媒體權限，見下文

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

`text()` / `json()` 遇到非 2xx 回應會自動拋錯（404 → `NOT_FOUND`）。Cookie 會自動儲存，並按每次重新導向的目標位址重新選擇。跨來源重新導向不會攜帶原來源的驗證標頭；保留請求本文的跨來源重新導向會被拒絕。

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

**影片**（`videos`）：`[{ quality: 1080, label: '1080P', url, headers?, format?, preferred? }]`。影片直鏈通常有時效，App 每次播放 / 下載前都會重新獲取。

- 省略 `format` 時沿用直 MP4 播放與下載路徑。HLS 必須明確傳回 `format: 'hls'`，並在 manifest 中宣告下文的 `media` 權限。
- HLS 主清單（`#EXT-X-STREAM-INF`）會先由宿主展開為各路獨立的分段清單，依 `RESOLUTION` 取得實際畫質，再交給播放器或下載器。傳回主清單時，`quality` 表示期望畫質：預設選擇不高於該值的最高實際畫質，沒有符合項目時選擇最高檔。每路必須包含音訊與視訊多工封裝的 MPEG-TS；獨立的 `AUDIO`、`VIDEO` 或 `SUBTITLES` renditions，以及超出 `media.domains` 的網址均拒絕。
- 展開後的 HLS 僅支援含 `#EXT-X-ENDLIST` 的完整、連續 MPEG-TS 隨選播放清單。不支援直播、加密、位元組範圍、fMP4、discontinuity 或 gap；MissAV 的非標準 `#EXT-X-TOKEN` 會被移除，不傳給播放器。
- 播放時使用僅綁定 `127.0.0.1` 的隨機連接埠和隨機權杖，透過有限 URL 註冊表按需讀取已驗證的分段；關閉工作階段會取消請求。HLS 離線下載目前僅支援 Android：逐段驗證、儲存 SHA-256 並驗證續傳資料，支援取消，最後由本機 Media3 封裝為 MP4，只有完整成品才加入離線資料庫。iOS/macOS 的 HLS 播放未經本輪驗證，不能據此宣稱已驗證可用。

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
- `network.mode: 'browser'` + `network.origin`：請求在一個開啟於 `origin` 的隱藏瀏覽器頁面中以同源 `fetch()` 發出，帶有真實瀏覽器指紋。適用於 Cloudflare 防護較嚴的站點（例如 Hanime1）。 同源 GET 請求收到 Cloudflare 質詢回應時，隱藏瀏覽器會導向該文件完成自動驗證，並重試一次原請求；未通過時仍丟出 `CLOUDFLARE`，沿用「去驗證」流程。

## 瀏覽器媒體（HLS）

瀏覽器媒體權限獨立於 `this.http`、`network` 和站點 Cookie 同步。MissAV 範例：

```js
domains: ['missav.ai'],
network: { mode: 'browser', origin: 'https://missav.ai' },
media: { mode: 'browser', origin: 'https://missav.ai', domains: ['surrit.com'] },
```

- `media.origin` 必須屬於來源宣告的站點，並使用 HTTPS 預設連接埠 443，不得包含使用者憑據。隱藏瀏覽器在該同源頁面建立媒體工作階段。
- `media.domains` 是獨立的媒體允許網域清單，包含其子網域，不授予來源站點 Cookie 權限。清單和分段均僅允許 HTTPS 443，拒絕 URL 使用者憑據、片段識別碼、IP 位址、localhost（含子網域）和 `.local`。媒體請求使用 `credentials: 'omit'`、`mode: 'cors'`、`redirect: 'error'`，遵循 CDN 的 CORS 規則，不跟隨重新導向。
- 回應採用串流大小限制，並重新驗證回應網址。清單最多 2 MiB，單個分段最多 32 MiB；超限、空回應或網址變化均拒絕。來源所屬的 `domains` 與 `network` 同源、帶 Cookie 規則保持不變，不能透過媒體網域共享站點登入狀態。

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

## 來源倉庫

一個倉庫就是一個 `index.json`，可以放在靜態託管上（例如 GitHub raw）。使用者在「來源站管理 → 新增來源」中輸入倉庫位址即可瀏覽、安裝與更新：

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

`url` 是腳本完整位址；也可以用相對於 `index.json` 的 `file`。第三方倉庫透過使用者確認後手動安裝，`sha256` 可選，提供時會校驗下載內容。

官方自動更新採用嚴格規則：版本必須是由點分隔、無前導零的三段非負整數（例如 `0.0.1`、`0.1.0`），逐段按數字比較；不接受缺段、多段或預發布後綴。必須提供腳本 UTF-8 原文的 `sha256`，不修剪空白、不轉換換行；腳本聲明的 `key`、`version` 必須與索引一致。 `apiVersion` 必須與目前 App 執行階段完全匹配，不匹配時拒絕自動更新，需要先使用支援該 API 的 App；不提供相容分支。

### App 中的官方更新

“源站管理”預設開啟“自動更新官方來源”，啟動或回到前台時每隔 12 小時檢查一次；失敗也記錄檢查時間，避免頻繁重試。關閉自動更新後仍可使用「立即檢查更新」。只升級已安裝的內建來源和官方線上來源，不自動安裝新來源，也不接管使用者自行安裝的同名第三方來源。

安裝時驗證身分、版本、API 和摘要，等待初始化及狀態持久化成功才完成更新。失敗保留舊腳本與使用者狀態；應用程式在安裝期間中斷時，下次啟動先恢復。線上新版優先於較舊或相同版本的內建腳本，新安裝包攜帶更高版本時可正常升級。 「恢復內建來源」可以主動回退到目前安裝套件版本；後續開啟自動更新時仍會繼續取得官方新版。

### 官方來源的發布

官方源沿用公開主倉庫 [drdon1234/Hentai-Park](https://github.com/drdon1234/Hentai-Park)，客戶端固定入口為：

```text
https://raw.githubusercontent.com/drdon1234/Hentai-Park/sources/index.json
```

`assets/sources/index.json` 是唯一維護的來源清單，其中的 `file` 指向同目錄下的唯一腳本原始碼。檔案名稱必須符合 `[A-Za-z0-9_-]+.js`，不接受子目錄、符號連結或檔案名稱主體中的點號，與客戶端官方來源位址校驗保持一致。 `tools/publish_sources.mjs` 產生發布索引：每筆記錄包含`key`、`name`、`version` 、`description`、`url`、`sha256`和 `apiVersion`。腳本 URL 固定到本次原始碼的完整 40 位元提交號碼：

```text
https://raw.githubusercontent.com/drdon1234/Hentai-Park/<源码提交 SHA>/assets/sources/<file>
```

`sources` 分支只保存產生的根目錄 `index.json`，不複製腳本，也不手動維護第二份來源清單。更新腳本時必須同時提升腳本和清單中的版本；發佈器拒絕降版，也拒絕相同版本對應不同腳本內容。相同版本且內容未變可重複發布，正常升版不受舊索引版本影響。

發佈器只依賴 Node.js 內建模組，可在 Node.js 22 或更新版本中離線運作。它檢查清單、檔案存在性與目錄邊界，在不提供網路和儲存介面的獨立上下文中載入共享執行時間及腳本，然後採用 App 安裝預覽相同的 `Park.__pending` / `Park.manifest` 探測方式核對`key`、`version` 和 API。探測不呼叫 `setup`、`init`、登入或網站業務方法，不能取代來源站聯網可用性測試。

本機預覽範例（輸出位於已忽略的 `test/`，不會發布；提交號碼應使用對應來源碼的真實 SHA）：

```powershell
node tools/publish_sources.mjs --commit '<完整 40 位源码提交 SHA>' --output 'test/official-source-index.json'
```

需檢查已有發佈時，再傳入 `--previous '旧索引本地路径'`。舊索引無效時校驗失敗，不會靜默跳過版本保護。工作區存在未提交修改時，本地結果只用於預覽；正式發布由工作流程檢出的原始碼提交產生。

`.github/workflows/publish-sources.yml` 僅在主倉庫預設 `main` 分支相關檔案推送，或從 `main` 手動觸發時運行。工作流程序列執行，每個任務開始時檢出最新 `main`，以實際檢出的提交號碼固定腳本地址和發布記錄。任務運行中後續文件提交不會阻止發布；後續來源文件提交會觸發下一個串行任務。工作流程先下載現有穩定索引並完成所有離線校驗，再用一次普通 Git 推送原子更新 `sources` 分支；校驗失敗或 `sources` 分支發生並發變更時不會覆蓋線上索引。首次沒有穩定索引時可以建立發布。發布只說明腳本與索引經過上述校驗，網站存取、帳號登入與圖片或影片載入仍需單獨驗證。
