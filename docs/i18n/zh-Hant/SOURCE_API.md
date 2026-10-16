[简体中文](../../SOURCE_API.md) · [繁體中文](SOURCE_API.md) · [日本語](../ja/SOURCE_API.md) · [한국어](../ko/SOURCE_API.md) · [English](../en/SOURCE_API.md) · [Español](../es/SOURCE_API.md) · [Русский](../ru/SOURCE_API.md) · [العربية](../ar/SOURCE_API.md)

# 站點外掛介面

[快速開始](#快速開始) · [manifest 欄位](#manifest-欄位) · [方法](#方法) · [執行時 API](#執行時-api) · [錯誤碼](#錯誤碼) · [國際化](#國際化) · [發布](#發布) · [附錄：官方站點備註](#附錄官方站點備註)

HentaiPark 的每個站點都是一個獨立的 JavaScript 外掛。應用在執行時載入外掛，可以從倉庫安裝、更新、啟用或停用，**不需要重新編譯應用**。官方外掛位於 [`assets/sources/`](../../../assets/sources/)，可以直接當作示例。

本文以簡體中文版為準。站點業務規則留在外掛裡，通用網路、快取和圖片能力由框架提供；框架不按站點名稱做特例。

## 快速開始

### 執行環境

- 外掛執行在應用內的無介面 WebView 中，有完整的現代 JS 與 `DOMParser`。原生層提供加解密、Cookie 和原生 HTTP；原生 HTTP 沒有 CORS 限制，瀏覽器網路和媒體請求遵循下文各自的規則。
- 每個外掛第一次被使用時才啟動自己的執行時，空閒約 5 分鐘或同時執行超過 6 個時回收。manifest 按「指令碼 SHA-256 + 執行時版本」快取，應用啟動時不執行外掛。不要依賴「應用一啟動外掛就在執行」。
- 同一份執行時（[`assets/runtime/park_runtime.js`](../../../assets/runtime/park_runtime.js)）也能在 Node 中執行，開發時可以直接對真實站點做冒煙測試。Node 宿主只用於開發，不是不受信任指令碼的安全沙箱。

### 最小外掛

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

### 在 Node 中試跑

在倉庫根安裝共享 runner 依賴，按下例建立被忽略的 `test/source-smoke.mjs`。示例只載入 manifest；修改外掛時還要用真實請求驗證首頁、第二頁、搜尋、詳情、封面解碼，以及章節或影片媒體。

```js
import { loadSource } from '../tools/source-runner/host.mjs';
const { manifest } = await loadSource('nhentai.js');
console.log(manifest.key, manifest.version);
```

```powershell
npm ci --prefix 'tools/source-runner'
node 'test/source-smoke.mjs'
```

## manifest 欄位

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

能力（`capabilities`）由執行時根據實現了哪些方法自動匯出，外掛不手寫。

### 型別與分類

`type` 決定閱讀、播放或遊戲資源行為，`category` 決定發現頁、站點管理與搜尋中的分組；未知或未宣告的分類歸入「其他」。新增站點必須準確宣告型別、分類和能力。

| 分類 | 說明 |
| --- | --- |
| `doujin` | 本子與漫畫 |
| `gallery` | 美圖：插畫、Cosplay、寫真。圖片站仍宣告 `type: 'comic'`，一個圖集是一個作品，圖片透過 `chapter()` 按順序返回，可複用閱讀、收藏和下載。分類不按張數或尺度區分 |
| `anime` | 裡番 |
| `aiDrama` | AI 短劇。不接受舊的 `drama` 標識；站點自身的頻道名照原樣宣告，應用分類不用來過濾站點頻道 |
| `jav` | JAV 專門站 |
| `adult` | 綜合成人影片（如 Pornhub、XVideos、91porn），`type: 'video'`。分類是內容分組，不替代站點標籤和使用者篩選 |
| `shortvideo` | 短影片：全屏豎向連續流，見下 |
| `novel` | 小說，`type: 'novel'` |
| `game` | 遊戲，`type: 'game'` |
| `other` | 其他（訂閱類站點等） |

- **短影片**（`type: 'video', category: 'shortvideo'`）：作品、搜尋、收藏和歷史入口直接進入連續流。每個作品是一個短影片，`videos(id, '_')` 返回當前有效媒體，不需要詳情頁。`feed` 的 `hasNext` 和 `cursor` 用於臨近末尾時自動翻頁，遊標不能包含賬號憑據或媒體簽名。重新整理從第一頁開始；當前條播放，下一條暫停預載入，其餘釋放。站點沒有搜尋介面時不宣告 `search`。
- **只能在原站播放的聚合影片站**：仍宣告 `type: 'video', category: 'adult'`；沒有經過驗證的媒體介面時不實現 `videos`，執行時匯出 `capabilities.videos: false`。詳情頁主按鈕改為用系統瀏覽器開啟 `detail.url`，隱藏播放、下載和分集，不同步虛構章節、不檢查章節更新；收藏與歷史照常。
- **小說**和**遊戲**的協議見「方法」中的對應小節。

`defaultFeed` 按 **推薦頁 > 排行榜頁 > 熱門頁** 選擇，站點確實沒有這些入口時才用最新頁或其他有效入口，不得偽造未驗證的介面。未填寫或找不到 key 時，應用按 key 自動選擇（先 `promote` / `recommend` / `featured`，再 `rank` / `toplist`，再 `popular` / `hot` / `trending`），都沒有就進第一個標籤。

支援匿名存取、但推薦需要登入的源宣告 `anonymousDefaultFeed: 'ranking'`，值必須指向 `feeds` 中實際可匿名存取的入口，優先排行榜。首頁和站點頁在未登入時使用此入口；已登入時使用 `defaultFeed`，使用者明確選擇的分頁維持原選擇。不要把空列表或網路失敗一概視為匿名狀態。

### 選項定義

`feeds[].options`、`searchFilters`、`settings` 使用同一種格式：

```js
{ key: 'sort', label: '排序', type: 'select', default: 'date',
  values: [{ value: 'date', label: '最新' }, { value: 'popular', label: '热门', color: '#f00' }] }
// type：select（单选） | multi（多选） | number | text | password | switch
// settings 中用 options 代替 values 也可以
```

`feeds` 的每一項是站點頁的一個標籤：`{ key, label, options?: [...] }`。

### 網路

- `network.mode: 'native'`（預設）：原生 HTTP，使用持久化 Cookie，走使用者設定的代理。檢測到 Cloudflare 質詢時拋 `CLOUDFLARE`，應用引導使用者在內建瀏覽器中完成驗證，並把通行 Cookie 同步回原生請求。
- `network.mode: 'browser'` + `network.origin`：請求在開啟於 `origin` 的隱藏瀏覽器頁中以同源 `fetch()` 發出，帶真實瀏覽器指紋，適合 Cloudflare 防護較嚴的站點。同源 GET 收到 Cloudflare 質詢時，隱藏瀏覽器先導航到該文件完成自動驗證，再重試一次原請求；仍未透過時拋 `CLOUDFLARE`。
- `network.vpnHint: true`：在中國大陸可能需要 VPN 或代理的站點宣告它，等待超過 8 秒和失敗時提示「可能需要 VPN 或代理」。不要把所有錯誤都歸因於 VPN。
- `network.confirmation: { selector, readySelector, requiredCookies, message }`：需要使用者明確確認（如年齡確認）的站點宣告。`selector` 匹配確認彈窗，`readySelector` 匹配可訪問的頁面內容，`requiredCookies` 是確認後必須落地的 Cookie 名。外掛遇到未確認頁面時拋 `Park.error('CONFIRM_REQUIRED', message, { url })`；應用提供「去確認」入口，等彈窗消失、內容出現、Cookie 寫入且導航穩定後返回。應用不會代替使用者點選確認；這項宣告也約束通用人機驗證頁，避免把年齡確認誤當成已透過。
- 網路異常附帶安全的 `diagnostics` 欄位 `host`、`transport`、`reason`，區分 TLS 證書、握手、DNS、連線和超時；自動日誌只記錄這幾個白名單欄位。`reason: 'TLS_HANDSHAKE_TERMINATED'` 僅表示原生 `HandshakeException.message` 恰好是 `Connection terminated during handshake`（握手完成前連線中斷，不是證書校驗失敗）；只有 HTTPS、無請求體的 GET / HEAD 遇到它時自動重試一次，其他錯誤都不重試。

### 圖片

- `imageNetwork: { mode: 'browser', origin, domains }`：圖片 CDN 需要瀏覽器請求時宣告。`origin` 和所有圖片域名必須屬於 `domains`，只允許 HTTPS 和白名單請求頭；圖片請求不帶賬號憑據、不跟隨重定向，單圖最多 20 MiB，仍經過解密、格式檢查、解碼和按站點分割槽的快取。未宣告時用原生圖片傳輸。
- **加密圖片**：宣告 `imageDecrypt`，框架在格式檢查和快取之前解密，解密策略參與快取身份，失敗結果不快取。當前支援 AES-CBC 與嚴格 PKCS#7 填充，`key`、`iv` 按 UTF-8 編碼；必須限定圖片域名，其他域名走普通路徑。

```js
imageDecrypt: {
  type: 'aes-cbc',
  key: '0123456789abcdef', // UTF-8 字节长度 16、24 或 32
  iv: '0123456789abcdef',  // UTF-8 字节长度 16
  domains: ['images.example.com'],
},
```

封面 HTTP 200 不等於可用，驗證時必須確認能解碼。

### 媒體許可權（HLS 與直鏈檔案）

`media` 許可權獨立於 `this.http`、`network` 和站點 Cookie：

```js
domains: ['example.com'],
network: { mode: 'native' },
media: { mode: 'native', origin: 'https://example.com', domains: ['media.example.com'] },
```

- `media.mode` 為 `'native'` 或 `'browser'`。`media.origin` 必須屬於外掛宣告的站點，使用 HTTPS 預設埠 443，不含使用者憑據、查詢或片段。
- `media.domains` 是獨立的媒體域名白名單（含子域），不授予站點 Cookie 許可權。清單、分段和金鑰都只允許 HTTPS 443，拒絕 URL 使用者憑據、片段、IP、localhost（含子域）和 `.local`。
- `'native'` 使用獨立、無憑據的原生客戶端，不讀寫站點 Cookie、Authorization 或代理認證；每一跳重定向都先校驗目標域名。只允許 `Referer`、`Origin`、`Accept`、`Accept-Language`，前兩者必須匹配 `media.origin`。
- `'browser'` 在 `media.origin` 的隱藏瀏覽器建立媒體會話，使用 `credentials: 'omit'`、`mode: 'cors'`、`redirect: 'error'`。
- 響應流式限長並重新校驗響應地址：清單最多 2 MiB，單個分段最多 32 MiB，AES-128 金鑰必須 16 位元組；超限、空響應或不允許的地址一律拒絕。

### 隔離與安全

- 每個外掛執行在**獨立的** JS 環境（各自一個無介面 WebView）中，彼此看不到全域性物件；原生橋只認呼叫來自哪個環境，外掛無法冒充其他外掛。
- 每個外掛有**獨立的 Cookie 罐**：請求只會帶上、也只會儲存到自己的 Cookie。
- Secure Cookie 不隨 HTTP 請求傳送。驗證頁開啟與瀏覽器 Cookie 匯入都按已安裝外掛的 `domains` 校驗，匯入保留可獲取的安全屬性與有效期。清除站點 Cookie 或解除安裝時，同時關閉對應瀏覽器會話並清理該站點的瀏覽器 Cookie；瀏覽器的站點 Cookie 由系統共享，因此宣告同一站點的外掛會受該站點清理的影響。
- `domains` 宣告外掛所屬站點（可註冊域名，自動包含子域）。只有這些站點的 Cookie 會同步到內建瀏覽器（Cloudflare 驗證與網頁登入共用），瀏覽器模式的 `network.origin` 也必須屬於它們。省略時從 `homepage`、`network.origin`、`account.cookieUrl/loginUrl` 推導。
- 跨來源重定向不攜帶原來源的認證頭；帶請求體的跨來源重定向被拒絕。TLS 證書校驗始終開啟。
- 從網址或倉庫安裝外掛時，應用先在不能聯網的沙盒中讀取指令碼資訊，向使用者展示名稱、版本、SHA-256、宣告的站點和風險提示，確認後才安裝。

### 賬號

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

- 賬號狀態只在首次使用、登入、退出、網頁登入後以及距上次檢查超過 10 分鐘時重新整理，不會在每次呼叫後檢查。`configured` 表示已有賬號配置，與當前是否登入成功無關。
- `loginDomains`：外掛宣告站點實際使用的第三方授權域名（含子域）。只在使用者開啟網頁登入頁時放行 HTTPS 443 的跳轉，拒絕 URL 使用者憑據、IP、localhost 和 `.local`。普通驗證頁、訪問確認、外掛請求和 Cookie 匯入仍按 `domains` 校驗，不能把第三方授權域名加進 `domains` 擴大許可權。登入頁支援原視窗跳轉和保留 `window.opener` 的授權彈窗，彈窗裡沿用同一檢查，空白初始頁不授予外部導航許可權。停留在授權頁時不判斷登入完成，回到站點後才同步 Cookie。第三方 Cookie 不匯入外掛的 Cookie 罐，也不隨清除站點 Cookie 刪除；其瀏覽器登入態由系統 WebView 管理。第三方平臺仍可能限制內嵌瀏覽器登入。
- `type: 'session'` 用於匯入已有的授權會話：宣告單個保密欄位（如 `session`），剪貼簿內容完整保留，由外掛校驗，不拆成賬號密碼或 Cookie。登入必須真實確認授權，不憑輸入格式假報成功。
- `managedAccount: true` 宣告外掛支援專用自動維護賬號，站點設定中用同名開關。應用必須先展示自動註冊說明並取得使用者確認，再儲存設定並呼叫 `account.enableManaged()`。註冊前先儲存候選憑據並 `await this.store.flush()`，保證失敗或重啟後還能恢復同一個賬號。手動憑據與專用賬號分開儲存，專用賬號不能覆蓋現有手動賬號；關閉開關保留專用賬號，重新開啟複用；Token 過期只重新登入，不重複註冊。
- 賬號密碼、Token 和外掛狀態都是使用者本機資料，文件和日誌裡不要出現真實憑據。

## 方法

方法裡的 `this` 見「執行時 API」。所有方法都可以是 `async`。

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

- `workCode` 是原站確認的番號或共同檢索碼，僅用於查找同作品；不取代 `id`，不合併作品身分、收藏、進度或下載。
- `editions` 是原站明確標註的固定版本標籤（如「中文字幕」「無碼流出」）；沒有標記時不得推斷為原版。顯示譯文不改變原始標籤。

- `coverAspect`（寬 / 高）讓網格在圖片載入前就排好版。
- `badgeColor` 用於分類角標的顏色。
- `mediaKind: 'comic' | 'video' | 'novel' | 'game'` 描述作品本身的型別。外掛只有一種型別時可以省略；混合型別時必須填寫，不能憑外掛的 `type` 把圖片當成影片。小說和遊戲作品總是填寫，這樣解除安裝外掛後離線作品和歷史仍能用正確的閱讀器開啟。
- 帖子類結果可以帶 `presentation: 'post'`、`text`、`date`、`url` 和 `media` 陣列，以帖子卡片顯示；`presentation: 'media'` 用媒體網格顯示，點選進入作品中的媒體。帖子正文允許沒有媒體；媒體地址仍受外掛宣告的域名和許可權約束。

### 詳情：`detail`

WorkItem 的全部欄位，再加：

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

- `variants` 只包含原站提供的同來源、同作品實際版本連結，各版本必須保留獨立 `id`；不得猜測 URL。跨站版本透過 `workCode` 查找，各自保留收藏、進度與下載。

- 點選標籤時，應用在本站點用 `keyword` 與 `filters` 搜尋，因此可以把標籤對映成站點原生語法（如 `artist:"xxx"`）或篩選引數。
- 第二個引數 `preview` 可選：只有 `preview.source`、`preview.id` 與請求一致時，才傳入已顯示或已儲存的作品公開後設資料。外掛仍要核對 ID 並校驗 URL。直接輸入編號開啟時沒有預覽，標題和封面可能不完整。

### 章節：`chapter` / `resolveImage` / `thumbnails`

```js
{ pages: [
  { url, headers?, fallbacks?: [url], width?, height?, transform? },  // 地址已知
  { token: '12' },                                                      // 延迟解析：应用会调用 resolveImage
]}
```

- `fallbacks`：備用映象，主地址失敗時依次嘗試。
- `transform: { type: 'unscramble-strips', segments: N }`：圖片被橫切成 N 條倒序存放時，應用在 GPU 上還原。離線檔案儲存原圖，顯示時再還原。
- `resolveImage` 返回 `{ url, headers?, width?, height?, cacheKey? }`。失敗時應用遞增 `retry` 再呼叫，外掛可以藉此換伺服器。
- `thumbnails(id, page)` 返回 `{ thumbnails: [...], hasNext }`。

### 影片：`videos`

返回 `[{ quality: 1080, label: '1080P', url, headers?, format?, preferred? }]`。直鏈通常有時效，應用每次播放或下載前都會重新獲取。

- 多集影片在 `detail(id).chapters` 按播放順序返回 `[{ id, title }]`，每個 `id` 必須穩定，不能用畫質或臨時媒體 URL 代替。應用用同一個 ID 選集、記錄進度、下載和續播，並呼叫 `videos(id, episodeId)` 獲取該集資源。單集用 `singleChapterId`，沒有時用 `'_'`。
- 省略 `format` 時按直鏈 MP4 播放和下載。HLS 必須返回 `format: 'hls'`，並宣告 `media` 許可權。
- HLS 主清單（`#EXT-X-STREAM-INF`）先由應用展開成各路分段清單，按 `RESOLUTION` 得到真實清晰度。返回主清單時 `quality` 表示期望清晰度：預設選不高於它的最高實際清晰度，沒有符合項時選最高檔。每路必須是音影片複用的 MPEG-TS；獨立的 `AUDIO`、`VIDEO`、`SUBTITLES` 和超出 `media.domains` 的地址一律拒絕。`#EXT-X-I-FRAME-STREAM-INF` 預覽軌道被忽略。單路清單無法確定解析度時提供 `label: '原画'`，不要把期望畫質當成真實解析度。
- 只支援帶 `#EXT-X-ENDLIST` 的完整、連續 MPEG-TS 點播清單；支援 `METHOD=AES-128`、`KEYFORMAT=identity` 的 CBC/PKCS7 解密，金鑰恰好 16 位元組，IV 可顯式提供或由媒體序號推導。金鑰只儲存在當前會話記憶體。不支援直播、SAMPLE-AES、其他 KEYFORMAT、`EXT-X-MAP`、`EXT-X-BYTERANGE`、fMP4、discontinuity 和 gap；非標準的 `#EXT-X-TOKEN` 會被移除。
- 播放時使用只繫結 `127.0.0.1` 的隨機埠和隨機令牌，透過有限 URL 登錄檔按需讀取已驗證的分段，關閉會話即取消請求。HLS 離線下載目前只支援 Android：逐段驗證並儲存 SHA-256，可恢復、可取消，最後由 Media3 封裝為 MP4，完整成品才進入離線庫。

### 小說：`textChapter`

小說外掛宣告 `type: 'novel', category: 'novel'`，實現 `textChapter` 後執行時匯出 `capabilities.textChapter: true`。列表和詳情填寫 `mediaKind: 'novel'` 和 `language: 'zh'` 或 `'en'`。沒有真實封面時返回 `cover: ''`，應用顯示文字封面，不請求虛構圖片。

```js
async textChapter(id, chapterId) {
  // 返回本章完整正文；paragraphs 必须是非空字符串数组，不得包含 HTML。
  return { title: '章节标题', paragraphs: ['第一段正文。', '第二段正文。'] };
}
```

- 多章小說在 `detail.chapters` 返回穩定 ID 和站點確認的閱讀順序；單篇用 `chapters: null` 和可選的 `singleChapterId`。
- 正文內部分頁由外掛按順序合併，不能把下一章、論壇回覆、廣告或推薦作品併入正文。`Park.html.paragraphs(node)` 提供通用的純文字提取，站點邊界和分頁仍由外掛決定。
- 登入、付費或許可權導致正文截斷時拋 `LOGIN_REQUIRED`，不得把預覽偽裝成完整章節。
- 應用按章原子寫入 `text.json`，完整寫入才算下載完成。閱讀進度和標註使用 `paragraphs.join('\n\n')` 的 UTF-16 位置；字號、字型、縮排等排版隻影響顯示，不改正文和已儲存的定位。書籤和標註獨立於下載檔案，參與備份，刪除下載不會刪除它們。

### 遊戲：`gameResources` / `resolveGameResource`

遊戲外掛宣告 `type: 'game', category: 'game'`，作品填寫 `mediaKind: 'game'`，不提供虛構的 `chapters`。執行時根據方法匯出 `capabilities.gameResources` 和 `capabilities.resolveGameResource`。

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

- `gameResources` 只返回穩定編號、後設資料和渠道，不能包含簽名 URL、密碼或偽造的下載狀態。`testStatus` 為 `tested | untested | unknown`，只照搬原站標記；`status: 'expired'` 的渠道禁用。
- `resolveGameResource` 只在使用者點選或重試時呼叫，返回的 URL 不持久化、不進日誌；密碼可以隨本地下載任務儲存，但不能寫進診斷。多個網盤連結不能丟棄；一次返回多條連結時可以給出與 `urls` 等長的 `extractionCodes`（空字串表示無提取碼），`extractionCode` 用於共用的密碼。
- 需要回復才能獲取的渠道宣告 `requiresReply: true, replyText: '实际回复内容'`，應用顯示「回覆解鎖並獲取連結」並先展示將傳送的文字，經使用者確認後才呼叫。外掛在解析前必須重新檢查首樓：已解鎖則只讀；只有使用者點選時才提交一次，並在傳送前可靠儲存賬號/帖號狀態。結果不明、重複嘗試或需要動態驗證時，用 `CONFIRM_REQUIRED` 返回原帖 URL，禁止自動重發；列表、詳情、預取和後臺更新中都不執行回覆。
- 直鏈必須宣告 `media: { mode: 'native', origin, domains }`。檔案用獨立、無 Cookie 的客戶端流式下載，HTTPS、逐跳域名、長度檢查、取消清理和完成檔案保護由框架負責；不提供斷點續傳，重試會重新解析地址並從頭下載。網盤用外部應用開啟，只允許 HTTP(S)、FTP(S)、magnet、ed2k、thunder，不使用站點 Cookie。遊戲不生成章節、閱讀進度或章節追更；應用不自動安裝、解壓或執行檔案。

### 訂閱：`subscription`

訂閱類外掛（關注頻道、創作者）宣告 `subscription` 物件；執行時在 `normalize` 和 `posts` 都存在時匯出 `capabilities.subscription`，在「發現 → 訂閱」中顯示。同時宣告瞭 `feeds` 的外掛也出現在普通分類中。

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

- `normalize` 必須純本地校驗：未登入、無網路時也能儲存目標；只接受當前站點的使用者名稱或受控的主頁 URL。`resolve`、`targets` 可選；有 `targets` 時清單輸出 `subscription.joinedTargets: true`。
- `posts` 的遊標是不透明字串，最後一頁 `hasNext: false`，沒有媒體的頁面也允許繼續翻頁。`locked` 表示許可權不足；`previewOnly` 明示只是公開預覽，不能把縮圖冒充全文。
- 不能提供直鏈的授權附件使用 `media[].resource`，並實現 `mediaChunk(resource, offset)`：每次最多 128 KiB，offset 按 128 KiB 對齊；resource 必須含整數 `size` 和穩定、非秘密的字串 `cacheKey`（不隨授權憑據或臨時引用變化）。框架校驗總大小和每塊完整性，原子寫入自己的快取路徑，單個附件最大 512 MiB；資源不能決定本地路徑。簽名連結和 resource 不儲存到訂閱記錄。
- 儲存訂閱不會自動關注或加入；未經驗證的寫操作必須引導使用者到原站手動操作，不執行靜默關注、加入或付費操作。

### 更新訂閱：`updateSubscriptions`

普通外掛可以用獨立的 `updateSubscriptions` 物件支援「關注更新」。執行時只在 `check` 存在時匯出 `capabilities.subscriptionUpdates`，不改變作品分類，也不影響上面的 `capabilities.subscription`。後設資料包含 `dimensions: [{ key, label, hint }]`；標籤選單可以傳遞原始關鍵詞和篩選引數。

- `normalize(dimension, input)` 返回 `{ id, label }`；`check({ dimension, target }, { cursor })` 返回 `{ items, hasNext, cursor }`。每項為 `{ id, title, kind, workId, chapterId }`，`kind` 只能是 `work | post | chapter`，ID 穩定且非空，不攜帶媒體 URL、Cookie 或憑據。章節 ID 要包含作品身份，避免不同作品的「第 1 話」衝突。
- `Park.enableUpdateSubscriptions(Park.__pending, rules)` 提供通用適配，規則在外掛指令碼末尾明確宣告維度，可以設定 `searchFilters`、`seriesPattern`。`work` 用真實章節目錄；`posts` 用現有頻道介面；`search` 和 `filter` 用搜尋，`code` 嚴格匹配完整番號，`series` 用經過本站域名校驗的系列路徑。搜尋遊標同時儲存頁號與站點遊標。
- 搜尋和動態返回 `windowed: true`，表示檢查最近三頁的結果視窗：首次只建立基線，之後按穩定 ID 產生「新發現內容」事件，不聲稱知道發布時間。其他分頁協議每輪最多三頁，儲存遊標與候選項，完整結束後再事務提交；章節目錄不允許視窗截斷，候選上限 20,000，超限報錯。網路、許可權、驗證頁、空目錄或不完整解析都要拋明確錯誤，不能用空結果掩蓋。
- 前後臺共用外掛執行時、Cookie 分割槽、域名約束和檢查器。後臺只啟動相關外掛，不登入、不在原站訂閱、不下載媒體、不繞過許可權。賬號或外掛配置變化時重建基線（Token 續期不算）。

## 執行時 API

方法裡可以用 `this` 訪問：

| 成員 | 說明 |
| --- | --- |
| `this.http` | `request(opts)`、`get(url, opts)`、`post(url, opts)`、`text(url, opts)`、`json(url, opts)` |
| `this.config` | 使用者在站點設定中選擇的值（未設定時為 `default`） |
| `this.store` | 持久化鍵值儲存：`get(key, fallback)` / `set(key, value)`，用於儲存 Token、域名列表等；`await flush()` 確認寫盤成功，失敗拋錯 |
| `this.cookies` | `get(url)` / `set(url, { name: value })` / `clear(url)` |
| `this.log({ code, host, transport, reason })` | 只寫入這些允許的欄位；自由文字不保留，避免洩露憑據與請求地址 |

全域性工具：

| 工具 | 說明 |
| --- | --- |
| `Park.html.parse(text)` | 返回標準 `Document`，可以用 `querySelector` |
| `Park.html.text(node)` / `unescape(s)` / `strip(html)` / `paragraphs(node)` | 文字處理 |
| `Park.crypto.md5Hex(text \| text[])` | MD5，可以傳陣列批次計算 |
| `Park.crypto.sha256Hex` / `hmacSha256Hex(key, text)` / `aesEcbDecrypt(base64, key)` / `uuid()` | 原生實現 |
| `Park.crypto.digestBytes('sha1' \| 'sha256', bytes)` | 最多 2 MiB 的 0–255 整數字節陣列 |
| `Park.crypto.randomBytes(length)` | 系統安全隨機位元組，length 為 1–65536 |
| `Park.utils.rateLimiter(ms)` | 返回 `wait()`，保證兩次請求之間的最小間隔 |
| `Park.utils.mapLimit(items, n, fn)` / `lruMap(n)` / `parseCount('1.2万')` / `formatDate(ts)` | 其他常用工具 |
| `Park.error(code, message, extra?)` | 建立帶錯誤碼的錯誤，見「錯誤碼」 |

### `http.request(opts)`

```js
await this.http.request({
  url, method: 'GET', headers: {}, params: { q: 'x' },   // params 拼接到 URL
  json: {...} | form: {...} | body: 'raw' | bodyBase64: '...',
  timeout: 15000,
  responseType: 'text' | 'base64',
});
// → { status, headers, body, url, ok, json() }
```

- `text()` / `json()` 遇到非 2xx 自動拋錯（404 → `NOT_FOUND`）。Cookie 自動儲存，並按每次重定向的目標地址重新選擇。
- `bodyBase64` 是原始二進位制請求體（最多 2 MiB），不能與 `body` 或瀏覽器模式同時使用；與文字請求使用相同的域名隔離、TLS 和重定向規則。外掛不能自行開放瀏覽器網路、WebSocket 或任意檔案訪問。

## 錯誤碼

用 `throw Park.error(code, message, extra)` 拋錯，應用按錯誤碼給出引導：

| code | 應用的處理 |
| --- | --- |
| `CLOUDFLARE` | 「去驗證」：開啟內建瀏覽器 |
| `CONFIRM_REQUIRED` | 「去確認」：等待使用者完成外掛宣告的訪問確認（`extra.url` 指向確認頁） |
| `LOGIN_REQUIRED` | 「去登入」：開啟站點設定的賬號區 |
| `NOT_FOUND` | 顯示「內容不存在」 |
| `BLOCKED` | 顯示「訪問受限」（如 IP 被封、配額用盡），圖片不再重試 |
| `NETWORK` | 顯示「網路連線失敗」與具體原因，附「重試」 |
| `HTTP` / `PARSE` / `UNSUPPORTED` / `CONFIG` | 顯示外掛給出的訊息與「重試」 |

### 結構化訊息

`message` 是**中文模板**，同時也是翻譯鍵；可變的部分放在 `extra.params` 裡，不要拼進字串：

```js
throw Park.error('HTTP', '站点返回 HTTP {status}', { params: { status: res.status }, status: res.status });
throw Park.error('NOT_FOUND', '影片不存在');
```

應用先用外掛自己的 `i18n` 翻譯模板，再用應用的通用詞彙，最後把 `params` 填進佔位符。拼接後的字串無法翻譯，非中文使用者會看到中文。`extra` 中的 `status`、`url`、`diagnostics` 照常使用。

### 主頁快取與錯誤語義

- `feed` 的實時結果保留外掛返回的全部欄位；磁碟上的主頁快取只儲存作品 ID、標題、封面、標籤、上傳者、媒體型別、分類和展示用統計等白名單後設資料，`url`、訪問憑據、媒體列表和帖子不落盤。不要把憑據放進 ID、封面地址或分頁遊標。需要動態媒體或帖子展示的結果不快取。
- 過期快取只在明確的 `NETWORK` / `TIMEOUT` 錯誤時作為離線內容顯示，並標明是快取。登入、確認、人機驗證、解析和配置失敗必須拋對應錯誤，框架不會把它們偽裝成網路失敗；使用者主動重新整理失敗也顯示真實錯誤。

## 國際化

應用介面支援 `zh-Hans`、`zh-Hant`、`ja`、`ko`、`en`、`es`、`ru`、`ar`（阿拉伯語從右到左）。外掛裡所有給人看的靜態文案（名稱、說明、標籤名、選項、搜尋提示、賬號說明、錯誤訊息）都用**簡體中文原文**書寫，原文就是翻譯鍵。

外掛在 manifest 的 `i18n` 中自帶自己的翻譯：

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

- 查詢順序：外掛 `i18n` 中當前語言 → 外掛 `i18n` 中的 `en`（簡體中文介面除外）→ 應用的通用詞彙（`assets/i18n/`，如「排序」「最新」「熱門」）→ 原文。
- 只有外掛自己用到、應用裡沒有的詞才需要寫進 `i18n`；通用詞直接複用應用的翻譯。佔位符寫法 `{name}` 必須與原文一致。
- 遠端內容（作品標題、作者、標籤、簡介）、使用者輸入和持久化的協議鍵保持原文，不當作介面文案翻譯。
- 修改 `i18n` 也是修改外掛，需要提高外掛版本。已安裝舊版外掛的使用者在更新前會看到舊文案。

應用自身的介面文案透過 `tr('已选 {count}', { 'count': count })` 或 `context.tr` 呼叫，八種語言資源位於 `assets/i18n/`，新增或修改時必須同步全部語言並保持佔位符一致。

## 發布

### 源倉庫

一個倉庫就是一個 `index.json`，可以放在任何靜態託管上。使用者在「我的 → 站點 → 新增站點」中輸入倉庫地址即可瀏覽、安裝和更新：

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

`url` 是指令碼完整地址，也可以用相對 `index.json` 的 `file`。第三方倉庫由使用者確認後手動安裝；`sha256` 可選，提供時校驗下載內容。

### 版本與更新規則

- 版本必須是三段、點分隔、無前導零的非負整數（如 `0.0.1`），逐段按數字比較；不接受缺段、多段或預發布字尾。
- 官方更新必須提供指令碼 UTF-8 原文的 `sha256`（不修剪空白、不轉換換行），指令碼宣告的 `key`、`version` 必須與索引一致；`apiVersion` 必須與當前應用執行時完全一致，否則拒絕更新。
- 外掛版本與應用版本分開管理。修改外掛指令碼（包括 `i18n`）時，同時提高指令碼和 `assets/sources/index.json` 中的版本；發布器拒絕降版，也拒絕同一版本對應不同內容。

### 應用內的官方更新

- 「我的 → 站點」和「我的 → 關於 → 更新」中的「啟動時檢查外掛更新」預設開啟：每次啟動只讀取官方索引，發現新版本後提示，使用者確認後才下載、校驗並安裝。回到前臺時保留 12 小時間隔，失敗也記錄檢查時間。關閉自動檢查後仍可手動檢查。只檢查已安裝的內建外掛和官方外掛，不自動安裝新外掛，也不接管使用者自裝的同名第三方外掛。
- 確認安裝時再次驗證身份、版本、來源、API 和摘要，等待初始化和狀態持久化成功才算完成；失敗保留舊指令碼和使用者狀態，安裝期間中斷的話下次啟動先恢復。啟動不會用安裝包內建的指令碼覆蓋已有外掛；指令碼缺失時保留登記資訊和使用者資料，等使用者明確恢復或更新。「恢復內建版本」經使用者確認後回退到當前安裝包中的版本。
- 應用自身更新同樣預設檢查：Android 上使用者確認後在應用內下載適合裝置的官方 APK，校驗大小、SHA-256、包名、版本與簽名後調起系統安裝介面；支援進度、取消與重試，官方發布頁作為備用入口。

### 官方外掛的發布

官方外掛發布在主倉庫 [drdon1234/Hentai-Park](https://github.com/drdon1234/Hentai-Park)，應用固定讀取：

```text
https://raw.githubusercontent.com/drdon1234/Hentai-Park/sources/index.json
https://raw.githubusercontent.com/drdon1234/Hentai-Park/rankings/index.json
```

- `assets/sources/index.json` 是唯一維護的清單，`file` 指向同目錄下的指令碼，檔名必須是 `{key}.js`（`[A-Za-z0-9_-]+.js`，不接受子目錄、符號連結或檔名中的點號）。
- `tools/publish_sources.mjs` 生成發布索引，每條記錄包含 `key`、`name`、`version`、`category`、`description`、`url`、`sha256`、`apiVersion`，指令碼 URL 固定到本次原始碼的完整提交號：`https://raw.githubusercontent.com/drdon1234/Hentai-Park/<提交 SHA>/assets/sources/<file>`。`sources` 分支只儲存生成的 `index.json`。
- 發布器只依賴 Node.js 22+ 內建模組，可以離線執行：檢查清單、檔案和目錄邊界，在不提供網路和儲存的上下文中載入執行時和指令碼，用與安裝預覽相同的 `Park.__pending` / `Park.manifest` 方式核對 `key`、`version` 和 API。它不呼叫 `init`、登入或站點方法，不能代替真實請求驗證。

```powershell
node tools/publish_sources.mjs --commit '<完整 40 位提交 SHA>' --output 'test/official-source-index.json'
```

原始碼繼續在主分支維護，普通插件由 `sources` 分發，獨立排行榜插件由 `rankings` 分發。兩分支只保存指向固定原始碼提交並含 SHA-256 的索引。工作流分別驗證和發布兩頻道；應用獨立讀取，拒絕頻道標記不符與重複 key，沿用更新確認流程。

### 構建生成的外掛

Telegram 外掛的唯一實現是 `assets/sources/telegram_entry.mjs`，`assets/sources/telegram.js` 由構建生成，不得手改：

```powershell
npm ci --prefix 'tools/source-runner'
node tools/build_subscription_sources.mjs
```

它使用 [@mtproto/core 6.3.0](https://github.com/alik0211/mtproto-core)（GPL-3.0，[許可證](../../licenses/mtproto-core.txt)，依賴彙總見 [第三方許可](../../licenses/telegram-dependencies.txt)）。站點適配替換了傳輸、密碼學和儲存，不開放庫預設的 WebSocket、瀏覽器 localStorage 或除錯日誌。

## 附錄：官方站點備註

維護官方外掛時需要知道的站點約定。站點會改版，以外掛程式碼為準。

**遊戲**

- 預設順序 KUN Galgame → GalgameX → 次元茶館。GalgameX 與 KUN 預設開啟 NSFW（分別用遊客 `content-filter` 介面和 `include_nsfw` 引數）。
- GalgameX 預設本週熱門。資源更新列表使用前端動態發現的 Next Server Action，動作編號快取 15 分鐘，失效後重新發現，不執行遠端指令碼；詳情從 SSR Flight 資料解析。公開資源用主機與路徑雜湊作為穩定渠道編號，解析後按主機及檔名/分享編號匹配，拒絕不匹配或重複匹配，不依賴臨時連結的順序。
- KUN 預設七日瀏覽排行，使用公開原生 API；下載介面只在點選時呼叫，避免預取增加站點下載計數。按介面總數遍歷資源頁，重複頁或提前空頁報錯。
- 次元茶館使用瀏覽器模式和獨立登入，預設 Galgame 資源區熱門；列表從首樓附件補封面，請求間隔 400ms。資源列表只讀；只有使用者確認回覆後才按完整表單傳送「感謝分享，好人一生平安」。已解鎖不發帖；響應不明時保留狀態並引導檢查原帖，重啟也不重複傳送。

**小說**

| 站點 | 預設入口 | 範圍與限制 |
| --- | --- | --- |
| Book18 | 推薦 | 中文長篇與短篇，目錄沿站點順序 |
| Cool18 | 精華 | 僅禁忌書屋；每個主帖是獨立作品，不合並回復或同名帖子；部分內容需要賬號許可權 |
| Canovel | 最新 | 支援文章內正文分頁 |
| Literotica | 排行 | 英文；搜尋排除非英文、有聲、教程、評論與隨筆分類 |
| Lush Stories | 推薦 | 英文；排除有聲與詩歌分類 |
| StoriesOnline | 作者推薦 | 英文；匿名正文被截斷時提示登入，不把預覽存為完整章節 |
| 69story | 最新 | 中文；支援分類、搜尋、目錄及分章閱讀 |

**訂閱**

| 平臺 | 內容 | 登入 |
| --- | --- | --- |
| X / Twitter | 匿名公開媒體；登入後的授權動態與媒體 | 網頁登入，或填寫 `auth_token`、`ct0` |
| Telegram | 公開頻道預覽；登入後的頻道歷史與附件 | 匯入已有 Telegram WebK 本地儲存會話 |
| myfans.jp | 創作者目錄、公開圖片、公開影片與試看預覽 | 會員登入未驗證 |
| pixivFANBOX | 公開目錄與封面預覽 | 會員登入未驗證 |

- X 的 `ct0` 必須與 `X-CSRF-Token` 對應，會話可能過期或被撤銷。登入後從當前網頁載入操作編號和 feature flags，再讀取 UserTweets，只保留目標作者的媒體（排除轉推和引用）。匿名第三方代理不會收到 X Cookie。
- Telegram 的本地儲存不是 Cookie：匯入內容需要 `dc` 和對應的 `dcN_auth_key`（512 位十六進位制），可以是 JSON 或 `key=value` 文字。外掛只恢復已有 WebK 會話，不發起驗證碼登入、不註冊自有客戶端；退出只刪除本應用儲存的會話。附件按 128 KiB 分塊讀取，單個最多 512 MiB；媒體引用過期時重新整理一次。網路走原生隔離 HTTP 橋，不開放 WebView fetch / WebSocket。
- OnlyFans、Fantia、Patreon、Fansly 未完成媒體讀取鏈路，沒有加入官方清單。首頁能開啟不等於可以訂閱媒體，也不提供付費許可權繞過。

動態 HLS CDN 可宣告 `media.scope: 'session'`（僅 native）。本次解析地址、清單資源與最多 8 跳重新導向僅授權給目前播放或下載工作階段，不增加 Cookie 權限。保留 HTTPS 443 與無憑據請求；直連檢查公網 DNS 並固定已驗證 IP，TLS 主機驗證保持啟用。明確設定 HTTP 代理時由可信代理解析及限制上游網路。關閉後銷毀授權；直連 MP4 與 browser 媒體仍使用靜態網域限制。

### `webVideo(id, episodeId)`

iXXX、TubeSafari 使用應用程式內網頁播放。播放頁可能仍需站點確認；播放控制由上游頁面提供，暫不支援應用程式的下載與精確續播。Android 需要支援獨立工作階段的較新版本 Android System WebView。

```js
return { url: "https://player.example.com/watch/1", navigationDomains: ["player.example.com"], frameDomains: [] };
// Native HTTP only: this.http.get(url, { followRedirects: false })
```

## 排行榜與獨立分發

`rankings` 以 `key`、`label`、`category`、`metric`、`options` 宣告榜單。獨立排行榜插件設定 `rankingOnly: true` 且不宣告 `feeds`。`ranking(board, {page, offset, cursor, options})` 回傳作品頁；條目包含 `id`、原站 `rank`、`title`、`cover`，以及可選的 `keyword`、`subtitle`、HTTPS 商品 `url`，保留並列名次。現有內容源可宣告 `feed`：未指定選項時繼承該 feed，執行時複用 `feed()` 並保留作品欄位、補上 `workId` 和缺失名次，開啟作品詳情。商業榜則搜尋指定分類。

原始碼繼續在主分支維護，普通插件由 `sources` 分發，獨立排行榜插件由 `rankings` 分發。兩分支只保存指向固定原始碼提交並含 SHA-256 的索引。工作流分別驗證和發布兩頻道；應用獨立讀取，拒絕頻道標記不符與重複 key，沿用更新確認流程。

```powershell
node tools/publish_sources.mjs --commit '<SHA>' --channel rankings --output 'test/official-ranking-index.json'
```
