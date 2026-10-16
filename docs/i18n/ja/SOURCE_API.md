[简体中文](../../SOURCE_API.md) · [繁體中文](../zh-Hant/SOURCE_API.md) · [日本語](SOURCE_API.md) · [한국어](../ko/SOURCE_API.md) · [English](../en/SOURCE_API.md) · [Español](../es/SOURCE_API.md) · [Русский](../ru/SOURCE_API.md) · [العربية](../ar/SOURCE_API.md)

# サイトプラグイン API

[クイックスタート](#クイックスタート) · [manifest のフィールド](#manifest-のフィールド) · [メソッド](#メソッド) · [ランタイム API](#ランタイム-api) · [エラーコード](#エラーコード) · [多言語対応](#多言語対応) · [公開](#公開) · [付録：公式サイトのメモ](#付録公式サイトのメモ)

HentaiPark の各サイトは独立した JavaScript プラグインです。アプリは実行時にプラグインを読み込み、リポジトリからのインストール、更新、有効化・無効化が **アプリを再ビルドせずに** できます。公式プラグインは [`assets/sources/`](../../../assets/sources/) にあり、そのまま例として参考にできます。

本書は簡体字中国語版が正です。サイト固有のルールはプラグインに置き、通信・キャッシュ・画像の共通機能はフレームワークが提供します。フレームワークはサイト名で特別扱いをしません。

## クイックスタート

### 実行環境

- プラグインはアプリ内のヘッドレス WebView で動作し、最新の JS と `DOMParser` が使えます。ネイティブ層が暗号処理、Cookie、ネイティブ HTTP を提供します。ネイティブ HTTP に CORS 制限はなく、ブラウザ通信とメディアは後述の規則に従います。
- 各プラグインのランタイムはサイトが初めて使われたときに起動し、約 5 分使われないか、同時に 6 個を超えると解放されます。manifest は「スクリプトの SHA-256 + ランタイムのバージョン」でキャッシュされるため、アプリ起動時にプラグインは実行されません。起動直後からプラグインが動いている前提にしないでください。
- 同じランタイム（[`assets/runtime/park_runtime.js`](../../../assets/runtime/park_runtime.js)）は Node でも動くので、開発中に実サイトで動作確認できます。Node ホストは開発用で、信頼できないスクリプトのサンドボックスではありません。

### 最小のプラグイン

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

### Node で試す

リポジトリのルートで共有ランナーの依存関係をインストールし、無視される `test/source-smoke.mjs` を次のように作ります。この例は manifest を読むだけです。プラグインを変更したら、トップ、2 ページ目、検索、詳細、表紙のデコード、章または動画メディアも実際のリクエストで確認してください。

```js
import { loadSource } from '../tools/source-runner/host.mjs';
const { manifest } = await loadSource('nhentai.js');
console.log(manifest.key, manifest.version);
```

```powershell
npm ci --prefix 'tools/source-runner'
node 'test/source-smoke.mjs'
```

## manifest のフィールド

```js
Park.register({
  key: 'mysite',              // 一意で変更不可。[A-Za-z0-9_-] のみ、1〜100 文字、_app は不可
  name: '我的站点',
  version: '0.0.1',           // 3 つの数字。リポジトリの方が新しいと更新を案内
  type: 'comic',              // comic | video | novel | game：読み方・再生方法を決める
  category: 'doujin',         // doujin | anime | aiDrama | jav | adult | shortvideo | gallery | novel | game | other
  color: '#E5355F',           // ブランドカラー：サイトのアイコンとサイトページ
  description: '一句话介绍',
  homepage: 'https://example.com',
  domains: ['example.com'],                   // 所属サイト。「分離とセキュリティ」参照。省略時は homepage などから推定
  linkPatterns: ['example\\.com/g/(\\d+)'],   // 貼り付けたリンクで作品を直接開く。1 番目のグループが作品 ID
  idPattern: '^(\\d+)$',                      // 入力した ID で作品を直接開く
  imageHeaders: { Referer: 'https://example.com/' },  // 表紙と画像の既定ヘッダー
  network: { mode: 'native', vpnHint: true },  // 「ネットワーク」参照
  media: { mode: 'browser', origin: 'https://example.com', domains: ['media.example.com'] },  // 任意の HLS メディア権限
  imageNetwork: { mode: 'browser', origin: 'https://img.example.com', domains: ['img.example.com'] }, // 任意
  imageDecrypt: { /* 任意。「暗号化画像」参照 */ },

  settings: [ /* オプション。「オプション定義」参照 */ ],
  account: { /* 任意。「アカウント」参照 */ },
  defaultFeed: 'ranking',     // サイトページで最初に開くタブ（feeds の key）
  feeds: [ /* サイトページのタブ */ ],
  searchFilters: [ /* 検索フィルター */ ],
  searchHint: '搜索技巧提示',
  i18n: { /* プラグイン独自の UI 翻訳。「多言語対応」参照 */ },

  subscription: { /* 任意：チャンネル・クリエイターの購読。「購読」参照 */ },
  updateSubscriptions: { /* 任意：更新の購読。「更新の購読」参照 */ },

  async init() {},              // 任意：ランタイム起動時に 1 回呼ばれる（ドメイン一覧の更新など）
  async onSettingsChanged() {}, // 任意：ユーザーがサイト設定を変えた後に呼ばれる
  // ほかに「メソッド」の各メソッド
});
```

機能（`capabilities`）は実装されたメソッドからランタイムが自動で出力します。手書きしないでください。

### 種類と分類

`type` は作品の読み方・再生・ゲームリソースの扱いを、`category` は「見つける」、サイト管理、検索での分類を決めます。不明または未宣言の分類は「その他」になります。新しいサイトは種類、分類、機能を正確に宣言してください。

| 分類 | 内容 |
| --- | --- |
| `doujin` | 同人誌と漫画 |
| `gallery` | ギャラリー：イラスト、コスプレ、写真集。画像サイトも `type: 'comic'` を宣言し、1 つのギャラリーが 1 作品、画像は `chapter()` で順に返すので、閲覧・お気に入り・ダウンロードがそのまま使えます。枚数や過激さで分けるものではありません |
| `anime` | 成人向けアニメ |
| `aiDrama` | AI ショートドラマ。旧 `drama` は受け付けません。サイト自身のチャンネル名はそのまま宣言し、アプリの分類で絞り込むことはしません |
| `jav` | JAV 専門サイト |
| `adult` | 総合成人向け動画（Pornhub、XVideos、91porn など）、`type: 'video'`。分類はグループ分けで、サイトのタグやユーザーの絞り込みの代わりにはなりません |
| `shortvideo` | ショート動画：全画面の縦スクロールフィード（後述） |
| `novel` | 小説、`type: 'novel'` |
| `game` | ゲーム、`type: 'game'` |
| `other` | その他（購読系サイトなど） |

- **ショート動画**（`type: 'video', category: 'shortvideo'`）：作品、検索、お気に入り、履歴からフィードに直接入ります。1 作品が 1 本の動画で、`videos(id, '_')` が現在のメディアを返し、詳細ページは不要です。`feed` の `hasNext` と `cursor` で終わり付近を自動ページングします。カーソルに認証情報やメディア署名を入れてはいけません。更新すると 1 ページ目から始まり、表示中の 1 本を再生、次の 1 本を一時停止で先読みし、ほかは解放します。検索がないサイトは `search` を宣言しません。
- **元サイトでしか再生できないまとめサイト**：`type: 'video', category: 'adult'` を宣言したまま、検証済みのメディア API がなければ `videos` を実装せず、ランタイムは `capabilities.videos: false` を出力します。詳細ページのメインボタンは `detail.url` をシステムブラウザで開き、再生・ダウンロード・エピソードは非表示、架空の章の保存や章の更新確認はしません。お気に入りと履歴は使えます。
- **小説** と **ゲーム** は「メソッド」で説明します。

`defaultFeed` は **おすすめ > ランキング > 人気** の順で選び、どれもない場合だけ最新ページなどの有効な入口を使います。検証していない API を作ってはいけません。未指定や不明な key の場合、アプリは key から自動で選びます（`promote` / `recommend` / `featured`、次に `rank` / `toplist`、次に `popular` / `hot` / `trending`）。どれもなければ最初のタブです。

匿名アクセスは可能でもおすすめにログインが必要なソースは `anonymousDefaultFeed: 'ranking'` を宣言します。`feeds` 内で匿名アクセスを実際に確認した項目を指定し、ランキングを優先します。ホームとサイト画面では未ログイン時にこの項目、ログイン時に `defaultFeed` を使用し、ユーザーが明示的に選んだタブは保持します。空の一覧やネットワークエラーをすべて未ログインと判断しないでください。

### オプション定義

`feeds[].options`、`searchFilters`、`settings` は同じ形式です。

```js
{ key: 'sort', label: '排序', type: 'select', default: 'date',
  values: [{ value: 'date', label: '最新' }, { value: 'popular', label: '热门', color: '#f00' }] }
// type：select | multi | number | text | password | switch
// settings では values の代わりに options も使える
```

`feeds` の各項目はサイトページのタブです：`{ key, label, options?: [...] }`。

### ネットワーク

- `network.mode: 'native'`（既定）：永続 Cookie を使うネイティブ HTTP で、ユーザーのプロキシを通ります。Cloudflare のチャレンジを検出すると `CLOUDFLARE` を投げ、アプリが内蔵ブラウザで認証を案内し、通過用 Cookie をネイティブリクエストに同期します。
- `network.mode: 'browser'` + `network.origin`：`origin` で開いた隠しブラウザページから同一オリジンの `fetch()` で送信し、本物のブラウザの特徴を持ちます。Cloudflare の保護が厳しいサイト向けです。同一オリジンの GET が Cloudflare のチャレンジを受けると、隠しブラウザがそのページに移動して自動認証し、元のリクエストを 1 回だけ再試行します。それでも通らなければ `CLOUDFLARE` です。
- `network.vpnHint: true`：中国本土で VPN やプロキシが必要かもしれないサイトに宣言します。8 秒を超える待機や失敗時に「VPN またはプロキシが必要な場合があります」と表示します。すべてのエラーを VPN のせいにしないでください。
- `network.confirmation: { selector, readySelector, requiredCookies, message }`：年齢確認などユーザーの明示的な確認が必要なサイト向け。`selector` は確認ダイアログ、`readySelector` は閲覧可能な内容、`requiredCookies` は確認後に必要な Cookie 名です。未確認のページではプラグインが `Park.error('CONFIRM_REQUIRED', message, { url })` を投げ、アプリが「確認する」を表示し、ダイアログが消え、内容が現れ、Cookie が書き込まれ、遷移が落ち着いてから戻ります。アプリがユーザーの代わりに確認を押すことはありません。この宣言は汎用の認証ページが年齢確認を通過済みと誤認しないようにもします。
- ネットワークエラーには安全な `diagnostics` フィールド `host`、`transport`、`reason` が付き、TLS 証明書、ハンドシェイク、DNS、接続、タイムアウトを区別します。自動ログにはこれらの許可されたフィールドだけを記録します。`reason: 'TLS_HANDSHAKE_TERMINATED'` はネイティブの `HandshakeException.message` が `Connection terminated during handshake` と完全一致した場合だけで（ハンドシェイク完了前の切断であり、証明書の失敗ではありません）、本文のない HTTPS の GET / HEAD だけが 1 回再試行され、ほかは再試行しません。

### 画像

- `imageNetwork: { mode: 'browser', origin, domains }`：画像 CDN にブラウザからのリクエストが必要な場合に宣言します。`origin` と画像ドメインはすべて `domains` に含まれている必要があり、HTTPS と許可リストのヘッダーのみ使えます。画像リクエストは認証情報を送らず、リダイレクトに従わず、1 枚最大 20 MiB で、復号、形式チェック、デコード、サイト別キャッシュはそのまま行われます。宣言しない場合はネイティブの画像転送を使います。
- **暗号化画像**：`imageDecrypt` を宣言すると、フレームワークが形式チェックとキャッシュの前に復号します。復号設定はキャッシュの識別に含まれ、失敗結果はキャッシュしません。AES-CBC と厳密な PKCS#7 パディングに対応し、`key` と `iv` は UTF-8 です。画像ドメインを必ず限定し、ほかのドメインは通常の経路を使います。

```js
imageDecrypt: {
  type: 'aes-cbc',
  key: '0123456789abcdef', // UTF-8 で 16、24、32 バイト
  iv: '0123456789abcdef',  // UTF-8 で 16 バイト
  domains: ['images.example.com'],
},
```

表紙が HTTP 200 でも使えるとは限りません。デコードできることを確認してください。

### メディア権限（HLS と直接ファイル）

`media` 権限は `this.http`、`network`、サイトの Cookie から独立しています。

```js
domains: ['example.com'],
network: { mode: 'native' },
media: { mode: 'native', origin: 'https://example.com', domains: ['media.example.com'] },
```

- `media.mode` は `'native'` か `'browser'`。`media.origin` はプラグインの所属サイトに含まれ、HTTPS の既定ポート 443 を使い、認証情報・クエリ・フラグメントを含めません。
- `media.domains` はメディア専用の許可ドメイン一覧（サブドメインを含む）で、サイトの Cookie 権限は与えません。プレイリスト、セグメント、鍵は HTTPS 443 のみで、URL 内の認証情報、フラグメント、IP、localhost（サブドメインを含む）、`.local` は拒否します。
- `'native'` は認証情報を持たない別のネイティブクライアントを使い、サイトの Cookie、Authorization、プロキシ認証を読み書きしません。リダイレクトは 1 ホップごとに先に確認します。使えるヘッダーは `Referer`、`Origin`、`Accept`、`Accept-Language` のみで、前の 2 つは `media.origin` と一致する必要があります。
- `'browser'` は `media.origin` の隠しブラウザでメディアセッションを作り、`credentials: 'omit'`、`mode: 'cors'`、`redirect: 'error'` を使います。
- 応答はストリーミング中にサイズを制限し、最終アドレスを再確認します。プレイリスト最大 2 MiB、セグメント最大 32 MiB、AES-128 の鍵はちょうど 16 バイト。超過、空の応答、許可されないアドレスはすべて拒否します。

### 分離とセキュリティ

- 各プラグインは **独立した** JS 環境（それぞれ専用のヘッドレス WebView）で動き、互いのグローバルは見えません。ネイティブブリッジは呼び出し元の環境を識別するため、別のプラグインになりすませません。
- 各プラグインは **独立した Cookie 保管場所** を持ち、リクエストは自分の Cookie だけを送り、保存します。
- Secure Cookie は HTTP では送りません。認証ページを開くときやブラウザ Cookie の取り込みは、インストール済みプラグインの `domains` で確認し、取得できるセキュリティ属性と有効期限を保持します。サイトの Cookie を消去するかアンインストールすると、対応するブラウザセッションを閉じ、そのサイトのブラウザ Cookie も消去します。ブラウザのサイト Cookie はシステムで共有されるため、同じサイトを宣言したプラグインも影響を受けます。
- `domains` はプラグインの所属サイト（登録可能ドメイン、サブドメインを含む）を宣言します。これらのサイトの Cookie だけが内蔵ブラウザと同期され（Cloudflare 認証とウェブログインで共用）、ブラウザモードの `network.origin` もこれらに属する必要があります。省略時は `homepage`、`network.origin`、`account.cookieUrl/loginUrl` から推定します。
- 異なるオリジンへのリダイレクトでは元のオリジンの認証ヘッダーを送りません。リクエスト本文を伴う異なるオリジンへのリダイレクトは拒否します。TLS 証明書の検証は常に有効です。
- URL やリポジトリからインストールするとき、アプリはまずネットワークのないサンドボックスでスクリプト情報を読み、名前、バージョン、SHA-256、宣言サイト、リスクを表示し、ユーザーが確認してからインストールします。

### アカウント

```js
account: {
  type: 'password' | 'cookies' | 'session',
  title, hint, required: false,
  fields: [{ key: 'email', label: '邮箱' }, { key: 'password', label: '密码', secret: true }],
  loginUrl?, cookieUrl?, requiredCookies?: ['ipb_member_id'],   // ウェブでログインでき、アプリが Cookie を取得
  loginDomains?: ['accounts.google.com', 'appleid.apple.com'],  // 外部ログインのドメイン（ログイン時の遷移のみ）
  async login(values) { return { name } },
  async logout() {},
  async status() { return { loggedIn, name, configured } },
  managedAccount: true,                 // 任意：自動管理の専用アカウントを提供
  async enableManaged() {},             // ユーザーが登録に同意した後だけ呼ばれる
}
```

- アカウントの状態は、初回使用時、ログイン・ログアウト・ウェブログインの後、前回の確認から 10 分を過ぎたときだけ更新し、呼び出しのたびには確認しません。`configured` はアカウントが設定済みであることを示し、現在ログインできているかとは別です。
- `loginDomains`：サイトが実際に使う外部ログインのドメイン（サブドメインを含む）。ユーザーがウェブログインページを開いている間だけ、HTTPS 443 への遷移を許可し、URL 内の認証情報、IP、localhost、`.local` は拒否します。認証ページ、アクセス確認、プラグインのリクエスト、Cookie の取り込みは引き続き `domains` で確認するため、外部ログインのドメインを `domains` に加えて権限を広げてはいけません。ログインページは同じウィンドウでの遷移と `window.opener` を保つポップアップに対応し、ポップアップ内も同じ確認を行い、空白の初期ページは外部遷移を許可しません。外部ページにいる間はログイン完了とみなさず、サイトに戻ってから Cookie を同期します。外部の Cookie はプラグインの保管場所に取り込まず、サイトの Cookie 消去でも消えません。システムの WebView が管理します。外部サービスが組み込みブラウザでのログインを制限する場合もあります。
- `type: 'session'` は既存の認証セッションを取り込みます。秘密のフィールド（例：`session`）を 1 つ宣言し、クリップボードの内容をそのまま保持してプラグインが検証します。ユーザー名・パスワード・Cookie に分割しません。ログインは実際の認可を確認する必要があり、入力形式だけで成功と報告してはいけません。
- `managedAccount: true` は自動管理の専用アカウントを提供することを宣言し、サイト設定の同名スイッチで制御します。アプリはまず自動登録の説明を表示して同意を得てから設定を保存し、`account.enableManaged()` を呼びます。登録前に候補の認証情報を保存して `await this.store.flush()` し、失敗や再起動後も同じアカウントを復元できるようにします。手動の認証情報と専用アカウントは分けて保存し、専用アカウントが手動アカウントを上書きすることはありません。スイッチをオフにしても専用アカウントは残り、再びオンにすると再利用します。トークンの期限切れでは再ログインだけを行い、登録し直しません。
- パスワード、トークン、プラグインの状態はユーザーの端末上のデータです。文書やログに実際の認証情報を書かないでください。

## メソッド

メソッド内の `this` は「ランタイム API」を参照してください。すべてのメソッドは `async` にできます。

```js
async feed(key, { page, cursor, options }) {}      // サイトページのタブ
async search({ keyword, page, cursor, filters }) {}
async random() {}                                  // 作品 ID を返す
async detail(id, preview) {}
async chapter(id, chapterId) {}                    // 漫画、ギャラリー
async resolveImage({ id, chapterId, index, token, retry }) {}  // 任意：画像の遅延解決
async thumbnails(id, page) {}                      // 任意：プレビューサムネイルのページ読み込み
async videos(id, episodeId = '_') {}               // 動画
async textChapter(id, chapterId) {}                // 小説
async gameResources(workId) {}                     // ゲーム
async resolveGameResource(workId, resourceId, channelId) {}
```

### 一覧：`feed` / `search`

```js
{
  items: [WorkItem], page: 1, totalPages: 20, total: 500,
  hasNext: true,
  cursor: '12345',        // 任意：カーソル方式のサイトは次のカーソルを返し、アプリはそのまま返す
}
// またはセクションを返し、セクション表示にする：
{ sections: [{ title: '连载更新', items: [WorkItem] }], hasNext: false }
```

**WorkItem**：`{ id, title, subtitle?, cover, coverAspect?, pages?, rating?, likes?, views?, language?, category?, badge?, badgeColor?, duration?, uploaded?, tags?, mediaKind?, workCode?, editions? }`

- `workCode` は配信元で確認された作品番号または共通検索コードで、同じ作品の検索にのみ使用します。`id` を置き換えず、作品の識別、お気に入り、進捗、ダウンロードを統合しません。
- `editions` は配信元が明記する固定の版ラベル（中国語字幕、無修正版の流出など）です。ラベルがない場合に原版と推測してはいけません。表示の翻訳は元のラベルを変更しません。

- `coverAspect`（幅 / 高さ）があると画像の読み込み前にグリッドを配置できます。
- `badgeColor` は分類バッジの色です。
- `mediaKind: 'comic' | 'video' | 'novel' | 'game'` は作品自体の種類です。種類が 1 つのプラグインは省略できますが、混在するプラグインは必ず指定し、プラグインの `type` だけで画像を動画として扱ってはいけません。小説とゲームの作品は常に指定し、プラグインをアンインストールしてもオフライン作品と履歴が正しいリーダーで開くようにします。
- 投稿形式の結果は `presentation: 'post'`、`text`、`date`、`url` と `media` 配列を持て、投稿カードとして表示されます。`presentation: 'media'` はメディアのグリッドで表示し、タップで作品内のメディアを開きます。投稿にメディアがなくてもかまいません。メディアのアドレスはプラグインが宣言したドメインと権限に従います。

### 詳細：`detail`

WorkItem の全フィールドに加えて：

```js
{
  url, authors: [], description, uploader?, size?, comments?,
  tags: [{ namespace: 'artist', label: '作者', tags: [{ name, keyword, filters?, count? }] }],
  chapters: [{ id, title }] | null,   // null は単一章
  singleChapterId?,                   // 単一章の作品に必要な章 ID
  thumbnails?: [url | { url, width, height, offsetX, offsetY }],   // スプライトに対応
  related?: [WorkItem], series?: [WorkItem], variants?: [WorkItem],
}
```

- `variants` には配信元が提供する、同じ配信元の同一作品の実在する版リンクのみを含め、各版の `id` を独立して保ちます。URL を推測してはいけません。他の配信元の版は `workCode` で検索し、お気に入り、進捗、ダウンロードは独立して保持します。

- タグをタップすると、このサイトで `keyword` と `filters` を使って検索します。タグをサイト独自の構文（例：`artist:"xxx"`）やフィルターのパラメータに対応付けられます。
- 2 番目の引数 `preview` は任意で、`preview.source` と `preview.id` が一致する場合だけ、表示済み・保存済みの公開メタデータが渡されます。プラグインは ID を確認し URL を検証する必要があります。ID を入力して開いた場合は preview がなく、タイトルや表紙が不完全なことがあります。

### 章：`chapter` / `resolveImage` / `thumbnails`

```js
{ pages: [
  { url, headers?, fallbacks?: [url], width?, height?, transform? },  // アドレスが分かっている
  { token: '12' },                                                      // 遅延解決：アプリが resolveImage を呼ぶ
]}
```

- `fallbacks`：予備のミラー。主アドレスが失敗すると順に試します。
- `transform: { type: 'unscramble-strips', segments: N }`：画像が N 本の帯に切られ逆順で保存されている場合に GPU で復元します。オフラインファイルは元画像を保存し、表示時に復元します。
- `resolveImage` は `{ url, headers?, width?, height?, cacheKey? }` を返します。失敗するとアプリは `retry` を増やして再度呼ぶので、プラグインはサーバーを切り替えられます。
- `thumbnails(id, page)` は `{ thumbnails: [...], hasNext }` を返します。

### 動画：`videos`

`[{ quality: 1080, label: '1080P', url, headers?, format?, preferred? }]` を返します。直接リンクは通常期限があるため、アプリは再生やダウンロードのたびに取得し直します。

- 複数話の動画は `detail(id).chapters` で再生順の `[{ id, title }]` を返します。各 `id` は安定している必要があり、画質や一時的なメディア URL で代用してはいけません。アプリは同じ ID でエピソード選択、進捗の保存、ダウンロード、続きからの再生を行い、`videos(id, episodeId)` でその話のリソースを取得します。単話は `singleChapterId`、なければ `'_'` です。
- `format` を省略すると MP4 の直接リンクとして再生・ダウンロードします。HLS は `format: 'hls'` を返し、`media` 権限を宣言する必要があります。
- HLS のマスタープレイリスト（`#EXT-X-STREAM-INF`）はアプリがバリアントごとのプレイリストに展開し、`RESOLUTION` から実際の画質を得ます。マスターを返す場合、`quality` は希望画質で、それ以下で最高の実画質を選び、該当がなければ最高画質を選びます。各バリアントは音声と映像を多重化した MPEG-TS である必要があり、独立した `AUDIO`、`VIDEO`、`SUBTITLES` や `media.domains` 外のアドレスは拒否します。`#EXT-X-I-FRAME-STREAM-INF` は無視します。単一のプレイリストで解像度が分からない場合は `label: '原画'` とし、希望画質を実際の解像度として示さないでください。
- `#EXT-X-ENDLIST` のある完全で連続した MPEG-TS の VOD プレイリストだけに対応します。`METHOD=AES-128`、`KEYFORMAT=identity` の CBC/PKCS7 を復号し、鍵はちょうど 16 バイト、IV は明示されたものかメディアシーケンスから導出したものです。鍵はセッション中のメモリだけに置きます。ライブ、SAMPLE-AES、ほかの KEYFORMAT、`EXT-X-MAP`、`EXT-X-BYTERANGE`、fMP4、discontinuity、gap には対応せず、非標準の `#EXT-X-TOKEN` は取り除きます。
- 再生時は `127.0.0.1` だけにバインドしたランダムなポートとランダムなトークンを使い、限定された URL 登録から検証済みのセグメントを必要に応じて読み出します。セッションを閉じるとリクエストは取り消されます。HLS のオフラインダウンロードは現在 Android のみで、セグメントごとに検証して SHA-256 を保存し、再開と取り消しができ、最後に Media3 で MP4 にまとめます。完全なファイルだけがオフラインライブラリに入ります。

### 小説：`textChapter`

小説プラグインは `type: 'novel', category: 'novel'` を宣言し、`textChapter` を実装すると `capabilities.textChapter: true` が出力されます。一覧と詳細では `mediaKind: 'novel'` と `language: 'zh'` または `'en'` を指定します。本物の表紙がなければ `cover: ''` を返し、アプリは架空の画像を要求せずに文字の表紙を表示します。

```js
async textChapter(id, chapterId) {
  // その章の本文全体を返す。paragraphs は空でない文字列の配列で、HTML を含めない。
  return { title: '章节标题', paragraphs: ['第一段正文。', '第二段正文。'] };
}
```

- 複数章の小説は `detail.chapters` で安定した ID とサイトで確認できる読む順序を返します。単編は `chapters: null` と任意の `singleChapterId` を使います。
- 章内のページ分割はプラグインが順に結合し、次の章、掲示板の返信、広告、おすすめ作品を本文に含めてはいけません。`Park.html.paragraphs(node)` は汎用的なテキスト抽出を提供しますが、サイトの境界とページ分割はプラグインが決めます。
- ログイン、課金、権限で本文が切り詰められる場合は `LOGIN_REQUIRED` を投げ、プレビューを完全な章と偽ってはいけません。
- アプリは章ごとに `text.json` をアトミックに書き込み、完全に書き込めた場合だけダウンロード完了とします。読書の進捗とメモは `paragraphs.join('\n\n')` の UTF-16 の位置を使い、文字サイズ、フォント、字下げなどの表示設定は本文や保存位置を変えません。しおりとメモはダウンロードとは別に保存され、バックアップに含まれ、ダウンロードを削除しても残ります。

### ゲーム：`gameResources` / `resolveGameResource`

ゲームプラグインは `type: 'game', category: 'game'` を宣言し、作品は `mediaKind: 'game'` を指定して架空の `chapters` を持ちません。ランタイムはメソッドから `capabilities.gameResources` と `capabilities.resolveGameResource` を出力します。

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
  // クラウドストレージは kind: 'external'、urls: [すべての予備・分割リンク]、url: urls[0] を返す。
}
```

- `gameResources` は安定した ID、メタデータ、チャンネルだけを返し、署名付き URL、パスワード、架空のダウンロード状態を含めてはいけません。`testStatus` は `tested | untested | unknown` で、サイトの表示をそのまま写したものです。`status: 'expired'` のチャンネルは無効になります。
- `resolveGameResource` はユーザーのタップか再試行のときだけ呼ばれ、返す URL は保存もログもされません。パスワードはローカルのダウンロードタスクと一緒に保存できますが、診断には書きません。複数のクラウドリンクを捨ててはいけません。複数返す場合は `urls` と同じ長さの `extractionCodes`（空文字は取得コードなし）を、共通のコードには `extractionCode` を使えます。
- 返信が必要なチャンネルは `requiresReply: true, replyText: '実際の返信内容'` を宣言し、アプリは「返信してリンクを解除」と送信する文面を表示し、ユーザーの確認後にだけ呼びます。プラグインは解決前に最初の投稿を確認し直し、解除済みなら読むだけにします。ユーザーのタップ時に 1 回だけ送信し、送信前にアカウントとスレッドの状態を確実に保存します。結果が不明、繰り返しの試行、動的な認証が必要な場合は、元の投稿の URL とともに `CONFIRM_REQUIRED` を返し、自動で再送してはいけません。一覧、詳細、先読み、バックグラウンド更新では返信しません。
- 直接リンクは `media: { mode: 'native', origin, domains }` を宣言します。ファイルは Cookie を持たない別のクライアントでストリーミング保存し、HTTPS、ホップごとのドメイン確認、長さの確認、取り消し時の後片付け、完成ファイルの保護はフレームワークが担います。中断からの再開はなく、再試行するとアドレスを解決し直して最初からダウンロードします。クラウドストレージは外部アプリで開き、HTTP(S)、FTP(S)、magnet、ed2k、thunder だけを許可し、サイトの Cookie は使いません。ゲームは章、読書の進捗、章の更新を作らず、アプリがファイルを自動でインストール、展開、実行することはありません。

### 購読：`subscription`

チャンネルやクリエイターを購読するプラグインは `subscription` オブジェクトを宣言します。`normalize` と `posts` が両方あるとランタイムは `capabilities.subscription` を出力し、「見つける → 購読」に表示されます。`feeds` も宣言したプラグインは通常の分類にも表示されます。

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
  async mediaChunk(resource, offset) { return { base64, done }; }, // 任意
}
```

- `normalize` は端末内だけで検証し、未ログインやオフラインでも対象を保存できるようにします。このサイトのユーザー名か管理されたプロフィール URL だけを受け付けます。`resolve` と `targets` は任意で、`targets` があると manifest は `subscription.joinedTargets: true` を出力します。
- `posts` のカーソルは不透明な文字列で、最終ページは `hasNext: false`、メディアのないページでもページングを続けられます。`locked` は権限不足、`previewOnly` は公開プレビューであることを示します。サムネイルを全文と偽ってはいけません。
- 直接リンクを出せない認可済みの添付ファイルは `media[].resource` を使い、`mediaChunk(resource, offset)` を実装します。1 回最大 128 KiB、offset は 128 KiB 単位で、resource には整数の `size` と、認証情報や一時的な参照で変わらない安定した非秘密の文字列 `cacheKey` が必要です。フレームワークは全体サイズと各チャンクを確認し、自分のキャッシュパスにアトミックに書き込みます。1 つの添付は最大 512 MiB で、resource がローカルパスを決めることはできません。署名付きリンクと resource は購読記録に保存しません。
- 購読の保存で自動的にフォローや参加をすることはありません。検証していない書き込み操作は元のサイトでの手動操作に誘導し、黙ってフォロー、参加、支払いをしてはいけません。

### 更新の購読：`updateSubscriptions`

通常のプラグインは独立した `updateSubscriptions` オブジェクトで「更新を追う」に対応できます。ランタイムは `check` がある場合だけ `capabilities.subscriptionUpdates` を出力し、作品の分類や前述の `capabilities.subscription` には影響しません。メタデータは `dimensions: [{ key, label, hint }]` を含み、タグメニューから元のキーワードとフィルターを渡せます。

- `normalize(dimension, input)` は `{ id, label }` を、`check({ dimension, target }, { cursor })` は `{ items, hasNext, cursor }` を返します。各項目は `{ id, title, kind, workId, chapterId }` で、`kind` は `work | post | chapter` のみ、ID は安定していて空でなく、メディア URL、Cookie、認証情報を含めません。章 ID には作品の識別も含め、別の作品の「第 1 話」が衝突しないようにします。
- `Park.enableUpdateSubscriptions(Park.__pending, rules)` が汎用の対応を提供し、ルールはスクリプトの末尾で明示的に宣言し、`searchFilters`、`seriesPattern` を指定できます。`work` は実際の章一覧、`posts` は既存のチャンネル API、`search` と `filter` は検索を使い、`code` は品番に完全一致、`series` はサイトのドメインで検証したシリーズパスを使います。検索のカーソルはページ番号とサイトのカーソルの両方を保存します。
- 検索と投稿の確認は `windowed: true` を返し、最新 3 ページの範囲を確認します。初回は基準を記録するだけで、以降は安定した ID で「新しく見つかった」イベントを出し、公開日時を知っているとは主張しません。ほかのページ方式は 1 回最大 3 ページで、カーソルと候補を保存し、完了したらトランザクションで確定します。章一覧は切り詰めず、候補の上限は 20,000 件（超えるとエラー）です。ネットワーク、権限、認証ページ、空の一覧、不完全な解析では明確なエラーを投げ、空の成功で隠してはいけません。
- フォアグラウンドとバックグラウンドはプラグインのランタイム、Cookie の区画、ドメイン制約、確認処理を共有します。バックグラウンドは関係するプラグインだけを起動し、ログイン、サイトでの購読、メディアのダウンロード、権限の回避は行いません。アカウントやプラグインの設定が変わると基準を作り直します（トークンの更新は含みません）。

## ランタイム API

メソッド内では `this` で次を使えます。

| メンバー | 説明 |
| --- | --- |
| `this.http` | `request(opts)`、`get(url, opts)`、`post(url, opts)`、`text(url, opts)`、`json(url, opts)` |
| `this.config` | ユーザーがサイト設定で選んだ値（未設定なら `default`） |
| `this.store` | 永続的なキーと値の保存：`get(key, fallback)` / `set(key, value)`。トークンやドメイン一覧などに使い、`await flush()` で書き込みを確認（失敗すると例外） |
| `this.cookies` | `get(url)` / `set(url, { name: value })` / `clear(url)` |
| `this.log({ code, host, transport, reason })` | 許可されたフィールドだけを書き込み、自由なテキストは残さないので認証情報やアドレスが漏れません |

グローバルなヘルパー：

| ヘルパー | 説明 |
| --- | --- |
| `Park.html.parse(text)` | 標準の `Document` を返し、`querySelector` が使える |
| `Park.html.text(node)` / `unescape(s)` / `strip(html)` / `paragraphs(node)` | テキスト処理 |
| `Park.crypto.md5Hex(text \| text[])` | MD5。配列で一括計算できる |
| `Park.crypto.sha256Hex` / `hmacSha256Hex(key, text)` / `aesEcbDecrypt(base64, key)` / `uuid()` | ネイティブ実装 |
| `Park.crypto.digestBytes('sha1' \| 'sha256', bytes)` | 最大 2 MiB の 0〜255 の整数配列 |
| `Park.crypto.randomBytes(length)` | 安全な乱数バイト。length は 1〜65536 |
| `Park.utils.rateLimiter(ms)` | `wait()` を返し、リクエスト間の最小間隔を保証 |
| `Park.utils.mapLimit(items, n, fn)` / `lruMap(n)` / `parseCount('1.2万')` / `formatDate(ts)` | その他のヘルパー |
| `Park.error(code, message, extra?)` | エラーコード付きのエラーを作る。「エラーコード」参照 |

### `http.request(opts)`

```js
await this.http.request({
  url, method: 'GET', headers: {}, params: { q: 'x' },   // params は URL に付く
  json: {...} | form: {...} | body: 'raw' | bodyBase64: '...',
  timeout: 15000,
  responseType: 'text' | 'base64',
});
// → { status, headers, body, url, ok, json() }
```

- `text()` / `json()` は 2xx 以外で例外を投げます（404 → `NOT_FOUND`）。Cookie は自動で保存され、リダイレクト先ごとに選び直されます。
- `bodyBase64` はバイナリの本文（最大 2 MiB）で、`body` やブラウザモードとは併用できません。テキストのリクエストと同じドメイン分離、TLS、リダイレクトの規則に従います。プラグインが自分でブラウザ通信、WebSocket、任意のファイルアクセスを開くことはできません。

## エラーコード

`throw Park.error(code, message, extra)` で投げると、アプリはコードに応じて案内します。

| code | アプリの対応 |
| --- | --- |
| `CLOUDFLARE` | 「認証する」：内蔵ブラウザを開く |
| `CONFIRM_REQUIRED` | 「確認する」：プラグインが宣言したアクセス確認をユーザーが終えるのを待つ（`extra.url` が確認ページ） |
| `LOGIN_REQUIRED` | 「ログインする」：サイト設定のアカウント欄を開く |
| `NOT_FOUND` | 「コンテンツがありません」を表示 |
| `BLOCKED` | 「アクセス制限」を表示（IP の遮断、上限到達など）。画像は再試行しない |
| `NETWORK` | 「ネットワークに接続できません」と理由、「再試行」を表示 |
| `HTTP` / `PARSE` / `UNSUPPORTED` / `CONFIG` | プラグインのメッセージと「再試行」を表示 |

### 構造化されたメッセージ

`message` は **中国語のテンプレート** で、そのまま翻訳キーになります。変わる部分は文字列に連結せず `extra.params` に入れます。

```js
throw Park.error('HTTP', '站点返回 HTTP {status}', { params: { status: res.status }, status: res.status });
throw Park.error('NOT_FOUND', '影片不存在');
```

アプリはまずプラグインの `i18n`、次にアプリ共通の語彙でテンプレートを翻訳し、`params` を差し込みます。連結した文字列は翻訳できず、中国語以外のユーザーには中国語のまま表示されます。`extra` の `status`、`url`、`diagnostics` はこれまでどおり使えます。

### ホームのキャッシュとエラーの意味

- `feed` のリアルタイムの結果はプラグインが返したフィールドをすべて保持します。ディスクのホームキャッシュは作品 ID、タイトル、表紙、タグ、投稿者、メディアの種類、分類、表示用の統計など許可リストのメタデータだけを保存し、`url`、認証情報、メディア一覧、投稿は書き込みません。ID、表紙のアドレス、カーソルに認証情報を入れないでください。動的なメディアや投稿の表示が必要な結果はキャッシュしません。
- 古いキャッシュは明確な `NETWORK` / `TIMEOUT` エラーのときだけオフラインの内容として表示し、キャッシュであることを示します。ログイン、確認、人による認証、解析、設定の失敗はそれぞれのエラーを投げる必要があり、フレームワークがネットワーク障害に見せかけることはありません。ユーザーが自分で更新して失敗した場合も実際のエラーを表示します。

## 多言語対応

アプリの UI は `zh-Hans`、`zh-Hant`、`ja`、`ko`、`en`、`es`、`ru`、`ar`（アラビア語は右から左）に対応します。プラグイン内の人が読む静的な文言（名前、説明、タブ名、オプション、検索のヒント、アカウントの説明、エラーメッセージ）はすべて **簡体字中国語の原文** で書き、原文が翻訳キーになります。

プラグインは manifest の `i18n` に自分の翻訳を持ちます。

```js
Park.register({
  i18n: {
    'zh-Hant': { '发行日期': '發行日期', '影片不存在': '影片不存在' },
    'en': { '发行日期': 'Release date', '影片不存在': 'Video not found', '站点返回 HTTP {status}': 'The site returned HTTP {status}' },
    // ja、ko、es、ru、ar も同様
  },
  key: 'mysite',
  // …
});
```

- 検索の順序：プラグインの `i18n` の現在の言語 → プラグインの `en`（簡体字中国語の UI を除く）→ アプリの共通語彙（`assets/i18n/`、例：「並べ替え」「最新」「人気」）→ 原文。
- アプリにない、そのプラグインだけの語句だけを `i18n` に書き、共通の語句はアプリの翻訳を使います。プレースホルダー `{name}` は原文と一致させます。
- リモートの内容（作品名、作者、タグ、紹介文）、ユーザーの入力、保存されるプロトコルのキーはそのままにし、UI の文言として翻訳しません。
- `i18n` の変更もプラグインの変更なので、バージョンを上げる必要があります。古いプラグインのユーザーは更新するまで以前の文言を見ます。

アプリ自体の UI 文言は `tr('已选 {count}', { 'count': count })` か `context.tr` で呼び、8 言語のリソースは `assets/i18n/` にあります。追加や変更のときはすべての言語を更新し、プレースホルダーを揃えてください。

## 公開

### リポジトリ

リポジトリは 1 つの `index.json` で、任意の静的ホスティングに置けます。ユーザーは「その他 → サイト → サイトを追加」にアドレスを入力して閲覧、インストール、更新できます。

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
      "sha256": "スクリプトの UTF-8 原文の 64 桁 16 進 SHA-256",
      "apiVersion": 1
    }
  ]
}
```

`url` はスクリプトの完全なアドレスで、`index.json` からの相対の `file` も使えます。サードパーティのリポジトリはユーザーの確認後に手動でインストールします。`sha256` は任意で、ある場合はダウンロード内容を検証します。

### バージョンと更新の規則

- バージョンはドット区切りで先頭ゼロのない 3 つの非負整数（例：`0.0.1`）で、各部分を数値で比較します。欠けた部分、余分な部分、プレリリースの接尾辞は受け付けません。
- 公式の更新ではスクリプトの UTF-8 原文の `sha256`（空白の除去や改行の変換をしない）が必要で、スクリプトが宣言した `key`、`version` はインデックスと一致する必要があります。`apiVersion` は現在のアプリのランタイムと完全に一致しなければ更新を拒否します。
- プラグインとアプリのバージョンは別々に管理します。プラグインのスクリプト（`i18n` を含む）を変更したら、スクリプトと `assets/sources/index.json` の両方でバージョンを上げます。公開ツールはダウングレードと、同じバージョンで内容が違うものを拒否します。

### アプリ内の公式更新

- 「その他 → サイト」と「その他 → このアプリについて → 更新」の「起動時にプラグインの更新を確認」は既定でオンです。起動ごとに公式インデックスだけを読み、新しいバージョンがあれば案内し、ユーザーの確認後にダウンロード、検証、インストールします。フォアグラウンドへの復帰時は 12 時間の間隔を保ち、失敗しても確認時刻を記録します。自動確認をオフにしても手動で確認できます。確認するのはインストール済みの内蔵と公式のプラグインだけで、新しいプラグインを自動でインストールしたり、同じ key のサードパーティプラグインを引き継いだりはしません。
- インストール時は識別、バージョン、取得元、API、ダイジェストを再検証し、初期化と状態の保存が成功して初めて完了します。失敗すると古いスクリプトとユーザーの状態を残し、インストール中に中断した場合は次回起動時に復元します。起動時にアプリ同梱のスクリプトで既存のプラグインを上書きすることはありません。スクリプトがない場合は登録情報とユーザーデータを残し、ユーザーが復元や更新を選ぶのを待ちます。「内蔵バージョンに戻す」は確認後、現在のアプリに同梱されたバージョンに戻します。
- アプリ自体の更新も既定で確認します。Android ではユーザーの確認後、端末に合う公式 APK をアプリ内でダウンロードし、サイズ、SHA-256、パッケージ名、バージョン、署名を検証してからシステムのインストーラーを開きます。進捗、取り消し、再試行に対応し、公式のリリースページを予備の入口とします。

### 公式プラグインの公開

公式プラグインはメインリポジトリ [drdon1234/Hentai-Park](https://github.com/drdon1234/Hentai-Park) から公開し、アプリは次を読みます。

```text
https://raw.githubusercontent.com/drdon1234/Hentai-Park/sources/index.json
https://raw.githubusercontent.com/drdon1234/Hentai-Park/rankings/index.json
```

- `assets/sources/index.json` が唯一の管理対象の一覧で、`file` は同じフォルダの `{key}.js` を指します（`[A-Za-z0-9_-]+.js`。サブフォルダ、シンボリックリンク、ファイル名の本体にドットは不可）。
- `tools/publish_sources.mjs` が公開インデックスを生成し、各項目に `key`、`name`、`version`、`category`、`description`、`url`、`sha256`、`apiVersion` を含めます。スクリプトの URL はソースの完全なコミット番号に固定されます：`https://raw.githubusercontent.com/drdon1234/Hentai-Park/<コミット SHA>/assets/sources/<file>`。`sources` ブランチには生成した `index.json` だけを置きます。
- 公開ツールは Node.js 22 以降の組み込みモジュールだけを使い、オフラインで動きます。一覧、ファイル、フォルダの境界を確認し、ネットワークと保存のない環境でランタイムとスクリプトを読み込み、インストール時のプレビューと同じ `Park.__pending` / `Park.manifest` の方法で `key`、`version`、API を確認します。`init`、ログイン、サイトのメソッドは呼ばないため、実際のリクエストでの確認の代わりにはなりません。

```powershell
node tools/publish_sources.mjs --commit '<40 桁のコミット SHA>' --output 'test/official-source-index.json'
```

ソースはメインブランチで管理し、通常プラグインは `sources`、専用ランキングは `rankings` で配信します。各ブランチは固定コミットURLとSHA-256を含む生成インデックスだけを保存します。ワークフローは各チャンネルを個別に検証・公開し、アプリは個別に読み込みます。不一致のチャンネルや重複keyを拒否し、更新確認の手順は共通です。

### ビルドで生成されるプラグイン

Telegram プラグインの唯一の実装は `assets/sources/telegram_entry.mjs` で、`assets/sources/telegram.js` はビルドで生成されるため手で編集してはいけません。

```powershell
npm ci --prefix 'tools/source-runner'
node tools/build_subscription_sources.mjs
```

[@mtproto/core 6.3.0](https://github.com/alik0211/mtproto-core)（GPL-3.0、[ライセンス](../../licenses/mtproto-core.txt)、依存関係の一覧は [サードパーティライセンス](../../licenses/telegram-dependencies.txt)）を使います。サイトの対応部分が転送、暗号、保存を置き換え、ライブラリ既定の WebSocket、ブラウザの localStorage、デバッグログは使いません。

## 付録：公式サイトのメモ

公式プラグインを保守するときに知っておくべきサイトの約束事です。サイトは変わるので、プラグインのコードが正です。

**ゲーム**

- 既定の順序は KUN Galgame → GalgameX → 次元茶館。GalgameX と KUN は NSFW を既定でオン（それぞれゲストの `content-filter` API と `include_nsfw` パラメータ）。
- GalgameX の既定は今週の人気。リソース更新一覧は現在のフロントエンドから動的に見つけた Next Server Action を使い、アクション ID を 15 分キャッシュし、無効になったら見つけ直します。リモートのスクリプトは実行しません。詳細は SSR Flight のデータから解析します。公開リソースはホストとパスのハッシュを安定したチャンネル ID とし、解決結果をホストとファイル名・共有 ID で照合し、不一致や重複は拒否します。一時リンクの順序には頼りません。
- KUN の既定は 7 日間の閲覧ランキングで、公開されたネイティブ API を使います。ダウンロード API はタップ時だけ呼び、先読みでサイトのダウンロード数を増やしません。リソースのページは API の総数で巡回し、同じページの繰り返しや早すぎる空ページはエラーにします。
- 次元茶館はブラウザモードと独自のログインを使い、既定は Galgame リソース板の人気です。一覧の表紙は最初の投稿の添付から補い、リクエスト間隔は 400ms です。リソース一覧は読み取り専用で、ユーザーが確認した後にだけ完全なフォームで「感谢分享，好人一生平安」を送信します。解除済みなら投稿せず、結果が不明な場合は状態を保持して元の投稿の確認を案内し、再起動後も再送しません。

**小説**

| サイト | 既定のタブ | 範囲と制限 |
| --- | --- | --- |
| Book18 | おすすめ | 中国語の長編・短編。目次はサイトの順序 |
| Cool18 | 精選 | 禁忌書屋のみ。各主投稿が独立した作品で、返信や同名の投稿は結合しない。一部はアカウントの権限が必要 |
| Canovel | 最新 | 記事内の本文ページ分割に対応 |
| Literotica | ランキング | 英語。検索は英語以外、オーディオ、ハウツー、レビュー、エッセイを除外 |
| Lush Stories | おすすめ | 英語。オーディオと詩を除外 |
| StoriesOnline | 作者のおすすめ | 英語。匿名で本文が切り詰められるとログインを案内し、プレビューを完全な章として保存しない |
| 69story | 最新 | 中国語。分類、検索、目次、章ごとの閲覧に対応 |

**購読**

| プラットフォーム | 内容 | ログイン |
| --- | --- | --- |
| X / Twitter | 匿名の公開メディア。ログイン後は認可された投稿とメディア | ウェブログイン、または `auth_token` と `ct0` |
| Telegram | 公開チャンネルのプレビュー。ログイン後はチャンネルの履歴と添付 | 既存の Telegram WebK のローカルストレージのセッションを取り込む |
| myfans.jp | クリエイター一覧、公開画像、公開動画、試聴プレビュー | 会員ログインは未検証 |
| pixivFANBOX | 公開の一覧と表紙のプレビュー | 会員ログインは未検証 |

- X の `ct0` は `X-CSRF-Token` と一致する必要があり、セッションは期限切れや取り消しが起こり得ます。ログイン後は現在のウェブページから操作 ID と feature flags を読み込んで UserTweets を読み、対象の作者のメディアだけを残します（リツイートと引用は除外）。匿名のサードパーティのプロキシに X の Cookie は送りません。
- Telegram のローカルストレージは Cookie ではありません。取り込みには `dc` と対応する `dcN_auth_key`（512 桁の 16 進）が必要で、JSON か `key=value` のテキストを使えます。プラグインは既存の WebK セッションを復元するだけで、認証コードでのログインや独自クライアントの登録はしません。ログアウトはこのアプリが保存したセッションを消すだけです。添付は 128 KiB 単位で読み、1 つ最大 512 MiB。メディアの参照が期限切れなら 1 回だけ更新します。通信は分離されたネイティブ HTTP ブリッジを通り、WebView の fetch や WebSocket は開きません。
- OnlyFans、Fantia、Patreon、Fansly はメディアの取得経路が完成しておらず、公式一覧に入っていません。トップページが開けることは購読できることを意味せず、有料の権限を回避することもありません。

動的 HLS CDN は native の `media.scope: 'session'` で利用できます。解析した再生 URL、プレイリストのリソース、最大8回のリダイレクトを現在の再生・ダウンロードセッションだけに許可し、Cookie 権限は変更しません。HTTPS 443 と認証情報を含まないリクエストを維持します。直接接続では公開 DNS アドレスを確認して接続先 IP を固定し、TLS ホスト名検証を維持します。明示的な HTTP プロキシを使用する場合は、その信頼されたプロキシが名前解決と公開ネットワーク制限を担当します。終了時に許可を破棄します。MP4 の直接再生と browser モードは静的ドメイン制限を維持します。

### `webVideo(id, episodeId)`

iXXX と TubeSafari はアプリ内ウェブ再生を使用します。再生ページでサイトの確認が必要な場合があります。操作は配信元のページが提供し、アプリのダウンロードと正確な続き再生には対応しません。Android では独立セッション対応の新しい Android System WebView が必要です。

```js
return { url: "https://player.example.com/watch/1", navigationDomains: ["player.example.com"], frameDomains: [] };
// Native HTTP only: this.http.get(url, { followRedirects: false })
```

## ランキングと独立配信

`rankings` は `key`、`label`、`category`、`metric`、`options` で定義します。専用プラグインは `rankingOnly: true` とし、`feeds` を宣言しません。`ranking(board, {page, offset, cursor, options})` は作品ページを返し、項目には `id`、元の `rank`、`title`、`cover`、任意の `keyword`、`subtitle`、HTTPS商品 `url` を含めます。同順位を保持します。既存ソースは `feed` を指定して選択肢を継承し、`feed()` を再利用できます。作品フィールドを保持し、`workId` と不足する順位を補って詳細を開きます。販売ランキングは指定カテゴリを検索します。

ソースはメインブランチで管理し、通常プラグインは `sources`、専用ランキングは `rankings` で配信します。各ブランチは固定コミットURLとSHA-256を含む生成インデックスだけを保存します。ワークフローは各チャンネルを個別に検証・公開し、アプリは個別に読み込みます。不一致のチャンネルや重複keyを拒否し、更新確認の手順は共通です。

```powershell
node tools/publish_sources.mjs --commit '<SHA>' --channel rankings --output 'test/official-ranking-index.json'
```
