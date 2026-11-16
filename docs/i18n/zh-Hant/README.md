[简体中文](../../../README.md) · [繁體中文](README.md) · [日本語](../ja/README.md) · [한국어](../ko/README.md) · [English](../en/README.md) · [Español](../es/README.md) · [Русский](../ru/README.md) · [العربية](../ar/README.md)

<p align="center"><img src="../../images/banner.svg" alt="HentaiPark · 18+" width="100%"></p>

<p align="center"><strong>成人內容聚合用戶端。探索、閱讀、觀看與收藏，一站完成。</strong></p>

<p align="center">匯聚本子、裏番、JAV、寫真、影片、小說與遊戲，跨站搜尋、閱讀播放與內容管理，一站完成。</p>

<p align="center">
  <a href="https://github.com/drdon1234/Hentai-Park/releases/latest"><img src="https://img.shields.io/github/v/release/drdon1234/Hentai-Park?label=Download&amp;color=C96442" alt="Download"></a>
  <img src="https://img.shields.io/badge/18%2B-Adult_content-C96442" alt="18+">
  <img src="https://img.shields.io/badge/Android_7.0%2B-333333" alt="Android 7.0+">
</p>

<p align="center"><a href="https://github.com/drdon1234/Hentai-Park/releases/latest">下載</a> · <a href="#screenshots">產品展示</a> · <a href="#features">功能</a> · <a href="#faq">常見問題</a> · <a href="https://github.com/drdon1234/Hentai-Park/issues">回報</a></p>

> **18+** 僅限成年人在當地法律允許的範圍內使用。內容來自第三方網站；HentaiPark 不託管原站內容。

## 下載與平台

### Android 獨立安裝包

**[下載 Android 最新安裝包](https://github.com/drdon1234/Hentai-Park/releases/latest)**

支援 **Android 7.0+**。多數手機和平板選擇 `arm64-v8a`。[平台說明與安裝方式](../../PLATFORMS.md)

Android 是獨立的原生安裝包，Android 與 Web 版本號獨立維護。

### Web 服務的不同執行形式

Windows、Linux、Docker 與 Docker Compose 都是同一個 Web 服務的不同執行形式，不是 Android 安裝包的不同版本。Web 目前是獨立的初始版本 **0.0.1**。Windows 可在 `clients\web` 執行 `start-web.bat`；Linux 可執行 `pnpm install --frozen-lockfile`、`pnpm build`、`pnpm start`；Docker 部署請見 [Web 部署文件](../../WEB_DEPLOYMENT.md)。

<a id="screenshots"></a>

## 產品展示

https://github.com/user-attachments/assets/165f1524-9084-4437-bebb-fa9e23ebd316

## 快速上手

1. 在「發現」選擇內容分類並瀏覽網站，或搜尋作品、標籤、連結與番號。
2. 開啟作品閱讀或播放，將作品加入「收藏」，需要離線時選擇下載。
3. 從首頁「繼續看 → 全部」接著看，在「收藏 → 更新」查看新章節。

需要登入或代理的網站，可在「我的 → 站點」與「我的 → 網路」中設定。

### Web 自架（Docker Compose）

Web 可在桌面與手機瀏覽器使用；單使用者實例，Docker 目標為 linux/amd64。首次映像須在程式碼推送、Release platforms 工作流程成功後才能拉取；發布前請使用詳細文件中的本機建置方式。

```sh
git clone https://github.com/drdon1234/Hentai-Park.git
cd Hentai-Park
cp clients/web/.env.example clients/web/.env
```

複製範本後，編輯 `clients/web/.env`：將 `WEB_IMAGE` 設為 `drdon1234/hentai-park:latest`，填入隨機 `AUTH_TOKEN`（至少 16 字元）及實際 HTTPS `WEB_ALLOWED_ORIGIN`。

```sh
docker compose -f clients/web/compose.yaml pull
docker compose -f clients/web/compose.yaml up -d --no-build
```

預設只綁定 `127.0.0.1:8787`，經 HTTPS 反向代理存取並使用 `AUTH_TOKEN` 解鎖；不需預設使用者名稱。`park-data` 命名卷保存 `/data`，下載位於 `/data/downloads`。更新執行 `pull` 與 `up -d --no-build`；停止用 `stop`，不要用 `down -v`。

[詳細部署、發布前本機建置與目錄權限](../../WEB_DEPLOYMENT.md)

<a id="features"></a>

## 功能概覽

| 功能 | 使用體驗 |
| --- | --- |
| 跨站搜尋 | 依二次元、三次元與媒體類型篩選，跨站搜尋，貼上連結或番號直達作品。 |
| 閱讀與觀看 | 吃瓜圖文與影片；漫畫捲動、翻頁與雙頁閱讀；影片選集、倍速與續播；小說書籤、標註與朗讀。 |
| 收藏與追更 | 分組整理收藏、保留進度、查看新章節，訂閱作者、頻道與關鍵字。 |
| 線上遊戲 | 免安裝遊玩網頁遊戲，可切換全螢幕與虛擬按鍵。 |
| 離線與匯出 | 下載漫畫、影片、音聲、小說、貼文與文章附件及遊戲資源；匯入匯出 CBZ，將已完成的圖集章節匯出 PDF。 |
| 榜單與反搜 | 瀏覽本子、裏番與 JAV 榜單，以圖片尋找作品線索。 |
| 作品資料 | 瀏覽、搜尋與篩選作品資料，查看榜單原站詳情，選擇詳情與搜尋站點。 |
| 原站互動資訊 | 查看支援網站的留言、回覆與圖片，在支援的直播間顯示彈幕。 |
| 翻譯與過濾 | 翻譯標題、章節名稱、簡介、標籤、評論、內文、文字字幕和彈幕；優先使用目前語言詞包，依標籤封鎖內容。 |
| 隱私與備份 | 應用程式鎖、無痕瀏覽、封面模糊及支援平台上的防截圖；備份收藏、進度、訂閱與設定。 |

## 支援的站點與服務

[查看完整站點清單、排行榜與圖片反搜服務](SITES.md)

<a id="faq"></a>

## 必要限制與常見問題

酒館需要自行設定相容 OpenAI 的 AI 服務；訊息、角色設定、使用者人格及匹配的世界書內容會傳送至所選服務，可能產生費用。支援規則與匯入匯出方式見[站點與服務](SITES.md)。已儲存資源與會話納入未加密書庫備份，AI 設定與金鑰不納入備份。

各網站的閱讀、播放、留言、訂閱與下載能力不同，以應用程式內顯示為準。網站更新可能要求先升級應用程式。

圖片反搜會將圖片傳送至所選服務；本機反搜歷史未加密。手動登入時密碼與 Cookie 可見，請留意螢幕分享。

**網站打不開或內容不可用？**

先檢查網路，再依提示登入、完成年齡確認或網站驗證。部分地區可能需要 VPN 或代理；內容與權限由原站決定。 可自動處理的生日驗證僅在本機已確認成年後填寫固定日期 1999-12-31，不讀取真實生日。

**留言和彈幕可以發送嗎？**

留言、回覆與直播彈幕僅供閱讀。部分遊戲資源需要回覆解鎖時，會先顯示回覆內容，經你確認後才發送。

**如何保留收藏和進度？**

在「我的 → 備份」匯出或還原 .parkbak。還原會合併資料，不包含下載檔案；可選擇攜帶 Cookie 等網站登入與確認狀態供其他裝置使用，過期或綁定裝置的工作階段可能需要重新驗證。備份未加密，請妥善保管。 線上遊戲存檔不包含在 .parkbak 中；遊戲內的單獨匯入匯出僅涵蓋 localStorage，不含 IndexedDB，匯出檔案未加密。

**如何回報問題？**

透過 Issues 提供應用程式版本、網站與重現步驟。請隱藏帳號、Cookie、Token、備份及完整簽名連結。

[日誌說明](DIAGNOSTICS.md)

---

[AGPL-3.0 · 授權條款](../../../LICENSE) · [第三方聲明](../../licenses/README.md) · [平台說明](../../PLATFORMS.md)
