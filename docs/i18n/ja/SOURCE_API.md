[简体中文](../../SOURCE_API.md) · [繁體中文](../zh-Hant/SOURCE_API.md) · [日本語](SOURCE_API.md) · [한국어](../ko/SOURCE_API.md) · [English](../en/SOURCE_API.md) · [Español](../es/SOURCE_API.md) · [Русский](../ru/SOURCE_API.md) · [العربية](../ar/SOURCE_API.md)

# サイトプラグイン API

[クイックスタート](#クイックスタート) · [manifest のフィールド](#manifest-のフィールド) · [メソッド](#メソッド) · [ランタイム API](#ランタイム-api) · [エラーコード](#エラーコード) · [多言語対応](#多言語対応) · [公開](#公開)

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
  version: '0.0.1',
  minAppVersion: '0.9.2',           // 3 つの数字。リポジトリの方が新しいと更新を案内
  type: 'comic',              // comic | video | novel | game：読み方・再生方法を決める
  category: 'doujin',         // doujin | anime | aiDrama | jav | adult | shortvideo | recording | live | gallery | illustration | novel | game | other
  color: '#E5355F',           // ブランドカラー：サイトのアイコンとサイトページ
  description: '一句话介绍',
  homepage: 'https://example.com',
  domains: ['example.com'],                   // 所属サイト。「分離とセキュリティ」参照。省略時は homepage などから推定
  linkPatterns: ['example\\.com/g/(\\d+)'],   // 貼り付けたリンクで作品を直接開く。1 番目のグループが作品 ID
  idPattern: '^(\\d+)$',                      // 入力した ID で作品を直接開く
  imageHeaders: { Referer: 'https://example.com/' },  // 表紙と画像の既定ヘッダー
  network: { mode: 'auto', vpnHint: true },  // 「ネットワーク」参照
  media: { mode: 'browser', origin: 'https://example.com', domains: ['media.example.com'] },  // 動画と直接ファイル用のメディア権限
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
  postShortVideos: true,
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
| `gallery` | 三次元美図：コスプレ、写真、実写の画像集. 画像サイトは `type: 'comic'` を宣言し、1 つの画像集が 1 作品です。`chapter()` が順に画像を返し、閲覧・お気に入り・ダウンロードを共用します。枚数や過激さでは分類しません |
| `illustration` | 二次元美図：イラスト、アニメの画像集. 画像サイトは `type: 'comic'` を宣言し、1 つの画像集が 1 作品です。`chapter()` が順に画像を返し、閲覧・お気に入り・ダウンロードを共用します。枚数や過激さでは分類しません |
| `anime` | 成人向けアニメ |
| `aiDrama` | AI ショートドラマ。旧 `drama` は受け付けません。サイト自身のチャンネル名はそのまま宣言し、アプリの分類で絞り込むことはしません |
| `jav` | JAV 専門サイト |
| `adult` | 総合成人向け動画（Pornhub、XVideos、91porn など）、`type: 'video'`。分類はグループ分けで、サイトのタグやユーザーの絞り込みの代わりにはなりません |
| `shortvideo` | ショート動画：全画面の縦スクロールフィード（後述） |
| `recording` | 録画アーカイブ（オンデマンド）、`type: 'video'` |
| `live` | ライブ配信, `type: 'video'` |
| `novel` | 小説、`type: 'novel'` |
| `game` | ゲーム、`type: 'game'` |
| `other` | クリエイターコミュニティ |

- **ショート動画**（`type: 'video', category: 'shortvideo'`）：作品、検索、お気に入り、履歴からフィードに直接入ります。1 作品が 1 本の動画で、`videos(id, '_')` が現在のメディアを返し、詳細ページは不要です。`feed` の `hasNext` と `cursor` で終わり付近を自動ページングします。カーソルに認証情報やメディア署名を入れてはいけません。更新すると 1 ページ目から始まり、表示中の 1 本を再生、次の 1 本を一時停止で先読みし、ほかは解放します。検索がないサイトは `search` を宣言しません。
- **投稿動画モード**（`postShortVideos: true`）：サイトと購読対象のページで `media[]` の動画添付を個別に再生します。動画には直接の `url` または空でない `episodeId` が必要です。遅延解決は再生・先読み時に `videos(元の投稿 ID, episodeId)` を呼び、Web ページをメディア URL として扱いません。画像は再生対象外で、添付は `preview`、`format`、`headers` に対応します。ページ送りと更新は現在の feed、絞り込み、対象の `subscription.posts` の範囲を維持します。再生は添付ごとに識別し、お気に入り・履歴・原サイトでの操作は元の投稿 ID を使います。分類は変わらず、独立したランダム動画 API を意味しません。
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

### 動的・連動フィルター

`feeds[].options` と `searchFilters` の単一選択項目は `dynamic: true, values: []` を宣言できます。動的な子項目は `dependsOn: ['range']` で同じグループの親を参照します。key は一意、依存先は存在し循環しないことが必要です。依存関係を宣言できるのは動的項目のみです。

`filterOptions(request)` は候補配列を返します。要求には `scope: 'feed' | 'search'`、`filter`、`values` を含め、一覧には `feed`、検索には任意で `keyword` を渡します。`values` は宣言した直接の親のみで、アカウント情報、設定、他の条件は含めません。親が未選択または空なら子を読み込みません。

検索語に依存する候補は `keywordDependent: true` を宣言します。検索語の変更でその項目と子孫をリセットし、他の条件は保持します。`values` の親の値は文字列・数値・真偽値のみで、複数選択の配列は渡せません。取得した名称は固定UI文言ではなく、コンテンツやタグの翻訳機能を利用できます。

候補は最大500件の `{value, label, color?}` です。value は一意の文字列または有限数、label は空でなく制御文字を含まない256文字以内の原サイト名、color は6桁の16進数です。大きな目録は分割して連動させ、黙って切り捨てません。取得した候補名は自動翻訳しません。

選択値は `feed` の `options`、`search` の `filters` で渡します。プラグインは目録への所属を検証し、ページ送りでも条件を保持します。解析失敗は例外にします。アプリはサイト、一覧/検索、一覧キーまたは検索語、親の値ごとに2分間キャッシュします。親の変更で子の選択と古い応答を破棄し、失敗時は再試行できます。

各ドメインのプラグインは自サイトの目録のみを読み取ります。同ブランドの別ドメイン間でプラグインを呼び出したりCookieを共有しません。共通解析はビルド時のテンプレートで再利用し、独立スクリプトを生成します。生成は `node tools/build_catalog_sources.mjs`、整合性確認は `--check` を使います。

```js
{key: 'category', label: '分类', type: 'select', default: '',
 dynamic: true, dependsOn: ['range'], values: []}

async filterOptions({scope, feed, filter, keyword, values}) {
  return [{value: 'site-category-id', label: 'Site category'}];
}
```

### ネットワーク

- `network.mode: 'auto'`（既定）：まずネイティブ HTTP を使います。本文のない同一オリジン HTTPS GET / HEAD が Cloudflare チャレンジ、HTTP 403・429、または回復可能な接続エラーを受けた場合は、ブラウザで 1 回再試行します。DNS、TLS、タイムアウト、レスポンスストリーム、通常の 5xx は追加の遅延を避けるためブラウザを起動しません。対象はサイトの宣言済みドメイン内に限られ、同一オリジンとリダイレクトの制限は維持されます。
- `network.mode: 'native'`: 永続 Cookie と設定済みプロキシでネイティブ HTTP を使用します。Cloudflare を検出した場合は `CLOUDFLARE` を返し、アプリ内で再試行できます。エラーにサイト内の認証 URL がある場合は、確認操作からページを開けます。
- `network.mode: 'browser'` + `network.origin`: `origin` の非表示ページから同一オリジンの `fetch()` を送信します。読み取りで Cloudflare（HTTP 200 を含む）や必要な Cookie・コンテンツのない年齢確認を受けた場合は、最大1回認証ページへ移動して再読込します。書き込みは再送しません。年齢確認は `network.confirmation` に従います。Android と Windows は一意の標準 Cloudflare チェックボックスに入力し、他の環境では自動認証を待ちます。失敗時は再試行するか、サイト内の認証 URL が提供されていれば確認操作を選べます。

  文書は宣言済みドメイン内で同じスキームとポートを使って移動できます。未指定のリクエスト `origin` は対象サイト URL から決まります。応答には最終 `url` が残ります。

  自動フォールバックは `followRedirects: false`、`connectAddress`、原因未分類のネットワークエラーには使いません。本文のないブラウザ GET / HEAD は通常の試行は最大 3 回で、検証後の再送は別途最大 1 回です。接続障害または HTTP 408、500、502、503、504 だけを再試行します。429 とタイムアウトは再送しません。検証ページへの移動はリクエスト全体で最大 1 回です。起動、要求、文書読み取り、破棄には待機上限があります。独自 API ヘッダー付き要求は通常のページ移動で代替せず `fetch()` を実行します。再利用する HTML のエラーステータスを保持し、`responseType: 'base64'` は元のバイト列の base64 を返します。

- `network.vpnHint: true`：中国本土で VPN やプロキシが必要かもしれないサイトに宣言します。8 秒を超える待機や失敗時に「VPN またはプロキシが必要な場合があります」と表示します。すべてのエラーを VPN のせいにしないでください。
- `network.confirmation: { selector, readySelector, requiredCookies, auto: { clickSelector }, message }`: サイトの年齢確認を宣言します。`selector` はダイアログ、`auto.clickSelector` はその中の一意の確認ボタン、`readySelector` は表示可能なコンテンツ、`requiredCookies` は確認後に必要な Cookie 名です。アプリの入口で成年を確認した後に限り、非表示ブラウザがクリックを模擬し、ダイアログ消失、コンテンツ表示、Cookie、画面遷移の安定を確認します。規則が不完全、不一致、または自動処理失敗の場合は再試行できます。エラーにサイト内の認証 URL があれば、ページで手動処理した後に完了を押せます。ソースのドメイン制限と Cookie 分離は維持され、操作通知から元の操作を自動再送しません。ログイン、支払い、投稿には使用できません。
- ネットワークエラーには安全な `diagnostics` フィールド `host`、`transport`、`reason` が付き、TLS 証明書、ハンドシェイク、DNS、接続、タイムアウトを区別します。自動ログにはこれらの許可されたフィールドだけを記録します。`reason: 'TLS_HANDSHAKE_TERMINATED'` はネイティブの `HandshakeException.message` が `Connection terminated during handshake` と完全一致した場合だけで（ハンドシェイク完了前の切断であり、証明書の失敗ではありません）、本文のない HTTPS の GET / HEAD だけが 1 回再試行され、ほかは再試行しません。

### 画像

- `imageNetwork: { mode: 'browser', origin, domains }`：画像ドメインとサブドメインはサイトの Cookie 権限から独立しています。`origin` はサイトまたは画像ドメインに属します。HTTPS 443 と許可ヘッダーを使い、origin がサイトの宣言ドメインに属する場合、同一オリジンの画像でブラウザーのサイトセッションを使用し、別オリジンの画像、外部画像オリジン、動画では認証情報を送らず、許可された画像ドメイン間のリダイレクトに対応します。上限 20 MiB、復号、形式検査、デコード、サイト別キャッシュを維持します。未指定ならネイティブ転送です。 ブラウザーのリダイレクト対応のプラットフォーム制限はメディア権限を参照してください。
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

MP4 のみを返す場合も、`videos()` を実装するプラグインは有効な `media` 宣言が必要です。`scope: 'session'` と静的な `domains` は併用できます。HLS はセッションで許可された個別 URL を使い、直接再生する MP4 は静的ドメインリストに一致する必要があります。公式の公開チェックは欠落または無効な宣言を拒否します。

```js
domains: ['example.com'],
network: { mode: 'native' },
media: { mode: 'native', origin: 'https://example.com', domains: ['media.example.com'] },
```

- `media.mode` は `'native'` か `'browser'`。`media.origin` はプラグインの所属サイトに含まれ、HTTPS の既定ポート 443 を使い、認証情報・クエリ・フラグメントを含めません。
- `media.domains` はメディア専用の許可ドメイン一覧（サブドメインを含む）で、サイトの Cookie 権限は与えません。プレイリスト、セグメント、鍵は HTTPS 443 のみで、URL 内の認証情報、フラグメント、IP、localhost（サブドメインを含む）、`.local` は拒否します。
- `'native'`：サイト Cookie、Authorization、プロキシ認証を使わない独立クライアントで、接続前に各リダイレクトを検査します。許可ヘッダーは `Referer`、`Origin`、`Accept`、`Accept-Language`。最初の二つは言語サブドメインを含む宣言済みサイトに属し、`Origin` は origin のみです。
- 任意の `media.referrerDomains` はネイティブ動画メディア専用で、有効な公開ドメインを最大 16 個指定できます（サブドメインを含む）。上記のサイトドメイン制限の例外として `Referer` の許可先だけを追加します。`Origin`、メディア URL、文書の遷移、Cookie の権限は拡張しません。`imageNetwork` とブラウザメディアでは使用できません。
- `'browser'`：`media.origin` の非表示セッションを使い、宣言済みサイト内で文書を移動できます。`credentials: 'omit'` と `mode: 'cors'` を使い、Origin/Referer は実際の文書とブラウザーが生成します。Windows は WebView2 で接続前に各リソースドメインを検査し、許可ドメイン間のリダイレクトと最終 URL を確認します。他のエンジンには各転送先の事前検査 API がないため `redirect: 'error'` を使います。CORS とサイト CSP は有効で、最終 URL の検査だけでは転送を許可しません。
- 応答はストリーミング中にサイズを制限し、最終アドレスを再確認します。プレイリスト最大 2 MiB、セグメント最大 32 MiB、AES-128 の鍵はちょうど 16 バイト。超過、空の応答、許可されないアドレスはすべて拒否します。

- 動的 HLS CDN は `mode: 'native'` で `media.scope: 'session'` を宣言できます。許可は現在の再生・ダウンロードセッションで解決した URL、プレイリスト資源、許可された転送先に限られ、終了時に失効します。Cookie 権限や永続的なドメイン許可は拡大しません。HTTPS、認証情報を含めないリクエスト、接続先と応答サイズの制限は維持され、直接 MP4 とブラウザのメディアには静的ドメイン一覧が適用されます。

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
  loginUrl?, cookieUrl?, requiredCookies?: ['session_id'],   // ウェブでログインでき、アプリが Cookie を取得
  loginDomains?: ['accounts.google.com', 'appleid.apple.com'],  // 外部ログインのドメイン（ログイン時の遷移のみ）
  localStorageKeys?: ['session_key'],  // cookieUrl と同じオリジンから許可されたキーだけを読み取り login(values) に渡す。値のログ出力は禁止
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
- `managedAccount: true` と `account.enableManaged()` は任意のアカウント管理機能です。内容を説明し、ユーザーの確認後にのみ有効にします。手動アカウントと管理対象アカウントを別々に保存し、既存の認証情報を上書きしません。アカウント情報は端末内で扱い、文書、診断、配布物に含めないでください。
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

**WorkItem**：`{ id, title, subtitle?, cover, coverBlurred?, coverAspect?, pages?, rating?, likes?, views?, language?, category?, badge?, badgeColor?, duration?, uploaded?, tags?, mediaKind?, workCode?, editions? }`

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

`[{ quality: 1080, label: '1080P', url, headers?, format?, preferred?, hls? }]` を返します。直接リンクは通常期限があるため、アプリは再生やダウンロードのたびに取得し直します。

- `format: 'hls'` は `hls: {manifest, keys}` を指定できます。`url` はバリアントの実際の HTTPS ベース URL、`manifest` は処理済みの完全な VOD メディアリスト（UTF-8 最大 2 MiB）、`keys` は参照された絶対鍵 URL と Base64 の 16 バイト鍵の対応（最大 32 件）です。ネイティブメディア専用で、既存のアドレス認可と内容検証は維持され、未参照の鍵は拒否します。このフィールドを含む結果はディスクにキャッシュせず、鍵はセッションメモリのみで使用し、store、ログ、作品、カーソルには保存しません。

- 複数話の動画は `detail(id).chapters` で再生順の `[{ id, title }]` を返します。各 `id` は安定している必要があり、画質や一時的なメディア URL で代用してはいけません。アプリは同じ ID でエピソード選択、進捗の保存、ダウンロード、続きからの再生を行い、`videos(id, episodeId)` でその話のリソースを取得します。単話は `singleChapterId`、なければ `'_'` です。
- `format` を省略すると MP4 の直接リンクとして再生・ダウンロードします。HLS は `format: 'hls'` を返し、`media` 権限を宣言する必要があります。
- HLS のマスタープレイリスト（`#EXT-X-STREAM-INF`）はアプリがバリアントごとのプレイリストに展開し、`RESOLUTION` から実際の画質を得ます。マスターを返す場合、`quality` は希望画質で、それ以下で最高の実画質を選び、該当がなければ最高画質を選びます。各バリアントは音声と映像を多重化した MPEG-TS または VOD fMP4 である必要があり、独立した `AUDIO`、`VIDEO`、`SUBTITLES` や `media.domains` 外のアドレスは拒否します。`#EXT-X-I-FRAME-STREAM-INF` は無視します。単一のプレイリストで解像度が分からない場合は `label: '原画'` とし、希望画質を実際の解像度として示さないでください。 マスターに `RESOLUTION` がない場合は有効な `BANDWIDTH` が必要です。各ビットレートを kbps で表示し、最高値を既定にします。解像度は推測しません。
- `type: 'video', category: 'live'` は三次元の公開ライブ配信です。ホームとカテゴリは画像カードのみ。`videos()` は現在の公開ルームの HLS を返し、非公開・有料・オフラインのルームを再生可能として返さないでください。ローリング再生に対応し、再生位置の復元・保存とダウンロードは行いません。録画は明示的な操作で開始し、初期ウィンドウより新しいセグメントのみを保存します。停止・アプリ終了で終了し、再起動後に再開しません。独立したメディアセッションとバックグラウンドタスクで各セグメントを検証・復号して完全なローカルリストを保存します。再接続時にメディアを再解決し、符号化の境界や長時間録画は分割されます。失敗時も保存済み内容は保持します。多重化 MPEG-TS のみ対応し、MAP/fMP4、低遅延 PART、BYTERANGE、GAP は非対応です。
- VOD は `#EXT-X-ENDLIST` のある完全で連続した MPEG-TS または fMP4 が必要です。fMP4 はメディアの前にある単一の `#EXT-X-MAP` 初期化セグメントのみ対応し、切り替えやバイト範囲には非対応です。初期化とメディアを認可・検証してローカルに書き換え、オフライン再生とエクスポートにも初期化セグメントを含めます。ライブは引き続き MPEG-TS のみで、ローリングリストと discontinuity に対応します。両者は `METHOD=AES-128`、`KEYFORMAT=identity` の CBC/PKCS7 を16バイトの鍵で復号します。メディア IV は明示値またはシーケンスから導出し、暗号化された初期化セグメントは明示 IV が必要です。鍵はセッション内のメモリのみです。SAMPLE-AES、他の KEYFORMAT、BYTERANGE、GAP は非対応で、VOD は discontinuity も拒否します。`#EXT-X-TOKEN` は除去します。
- HLS プレイリストと MPEG-TS セグメントは PNG `roUd` ラッパー（非圧縮または zlib 圧縮）に対応します。展開後に解析・検証・復号し、展開後もプレイリスト 2 MiB、セグメント 32 MiB の制限を適用します。プラグインは引き続き `format: 'hls'` を返し、追加権限は不要です。
- 再生時は `127.0.0.1` だけにバインドしたランダムなポートとランダムなトークンを使い、限定された URL 登録から検証済みのセグメントを必要に応じて読み出します。セッションを閉じるとリクエストは取り消されます。HLS のオフラインダウンロードは現在 Android のみで、セグメントごとに検証して SHA-256 を保存し、再開と取り消しができ、最後に Media3 で MP4 にまとめます。完全なファイルだけがオフラインライブラリに入ります。 fMP4 は初期化とメディアを順に保存し、Media3 の TS 変換を使用しません。

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
- コミュニティの独立した入口には `communities: true`、`communityHint`、`communityExample` を宣言し、ランタイムはそのまま公開します。対象は `{ id, label, kind: 'community' }` で、作者と異なる ID が必要です。`targets({ kind: 'community' })` は参加済みコミュニティ、引数なしの `targets()` は既定の対象を返します。コミュニティ API の失敗が作者一覧を壊さないよう別々に処理します。`resolve` は名前とアクセス権の読み取り確認のみで、自動参加は禁止です。
- `posts` のカーソルは不透明な文字列で、最終ページは `hasNext: false`、メディアのないページでもページングを続けられます。`locked` は権限不足、`previewOnly` は公開プレビューであることを示します。サムネイルを全文と偽ってはいけません。

### 公開アルバム：`subscription.media`

アルバムは独立した機能です。読み込み済みの投稿から組み立てず、`subscription.posts` にフォールバックしません。`subscription.media(scope, { page, cursor })` を実装します。公開 feed があり購読対象がないソースでも、`subscription` にこのメソッドだけを宣言できます。ランタイムは `capabilities.subscription` と独立して `capabilities.album` を公開します。

`scope` は feed と絞り込みの `{ feed, options }`、またはユーザー・コミュニティ・チャンネル・グループの `{ target }` です。対象の解決と走査はソースが担当し、UI にサイト固有条件を置きません。`{ items, cursor, hasNext }` を返し、該当メディアのないページでも続行できます。継続カーソルは必ず進め、重複はエラーです。

各項目には安定した文字列 `id`、`presentation: 'post' | 'work'`、既知なら解析可能な ISO 8601 日付、原サイト順の完全な `media` 配列が必要です。各添付には一意で安定した文字列 `id`、`type: 'image' | 'video'`、実際のコンテンツの `url` または管理対象の `resource` を指定します。`preview` は画像サムネイルです。代わりに下記の管理対象添付形式の `previewResource` を使えますが、別の画像で最大 2 MiB です。表紙や動画 URL をサムネイルに偽装しません。制限付き内容は原サイトのぼかしを維持した公開プレビューのみを `previewOnly: true` で返し、投稿全体がロックされていれば `locked: true` を付けます。

ソースはページをまたぐ添付の補完とメディアグループの統合を行います。クライアントは添付 `id` で同じ作品を統合し、全添付に有限数値の `order` がある場合のみ並べ替えます。日付はローカル日付の両端を含む範囲で絞り込み、範囲指定時は日付不明を除外します。画像・動画の絞り込みや投稿の折りたたみは識別情報を変えません。空の絞り込み結果を有限ページ自動取得した後は手動で続行できます。`presentation: 'work'` は作品詳細、`'post'` は投稿全文を開きます。表紙は画像または明示的なサムネイルのみで、動画再生 URL を使いません。

- `coverBlurred: true` とメディアの `blurred: true` は、サムネイルと全画面の両方で元サイトのぼかしを保持します。制限付き写真をぼかしなしの完全版として表示しないでください。動画プレビューも完全版も HLS マスターを展開し、選択した画質の VOD を再生します。
- 直接リンクを出せない認可済みの添付ファイルは `media[].resource` を使い、`mediaChunk(resource, offset)` を実装します。1 回最大 128 KiB、offset は 128 KiB 単位で、resource には整数の `size` と、認証情報や一時的な参照で変わらない安定した非秘密の文字列 `cacheKey` が必要です。フレームワークは全体サイズと各チャンクを確認し、自分のキャッシュパスにアトミックに書き込みます。1 つの添付は最大 512 MiB で、resource がローカルパスを決めることはできません。署名付きリンクと resource は購読記録に保存しません。
- 元サイトでのフォローや参加を伴う購読は、保存前に操作を明示して利用者の確認を得る必要があります。未検証の書き込み操作は元サイトへ案内し、通知せずにフォロー・参加・支払いを行ってはいけません。

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
| `Park.url.parse(value, base, domains)` / `site(source, value, base?)` / `response(source, response, requested)` | 許可ドメインとサブドメインの HTTPS 443 URL を解析し、認証情報を拒否、フラグメントを除去、失敗時は `null`。`site` は源の `domains` を使用。`response` は最終 URL を確認し、共有された源の基底 URL を変更せず、不正なら `BLOCKED`。パス、ページ、作品、検索条件はプラグインで確認し、クエリキーや CDN ノード名の固定リストを避けます。 |
| `Park.utils.rateLimiter(ms)` | `wait()` を返し、リクエスト間の最小間隔を保証 |
| `Park.utils.mapLimit(items, n, fn)` / `lruMap(n)` / `parseCount('1.2万')` / `formatDate(ts)` | その他のヘルパー |
| `Park.error(code, message, extra?)` | エラーコード付きのエラーを作る。「エラーコード」参照 |

`Park.crypto.aesGcmDecrypt(ciphertext, key, iv)` は 16 進数の暗号文（末尾の 16 バイト認証タグ込み、最大 4096 バイト）、16/24/32 バイト鍵、12 バイト IV を受け取り、平文バイト配列を返します。認証失敗時は未認証の平文を返さず例外になります。

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

- `feed` のリアルタイム結果は全フィールドを保持します。アプリ専用の再構築可能なディスクキャッシュは、許可リストの作品データ、投稿本文、添付へのアクセス情報、対応する詳細フィールドを保存し、更新前にも内容を開けます。有効期限付きメディア URL やリソース参照を含むことがあり、期限切れは更新が必要です。ダウンロードやバックアップの代わりではありません。キャッシュ識別はサイト、アカウント、設定、要求範囲を分離します。認証情報を返却内容・ID・カーソルに入れず、キャッシュのアクセス情報を診断や購読記録へ転記しません。
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
  "apiVersion": 2,
  "sources": [
    {
      "key": "mysite",
      "name": "我的站点",
      "version": "0.0.1",
      "minAppVersion": "0.9.2",
      "description": "一句话介绍",
      "url": "https://example.com/sources/mysite.js",
      "sha256": "スクリプトの UTF-8 原文の 64 桁 16 進 SHA-256",
      "apiVersion": 2
    }
  ]
}
```

`url` はスクリプトの完全なアドレスで、`index.json` からの相対の `file` も使えます。サードパーティのリポジトリはユーザーの確認後に手動でインストールします。`sha256` は任意で、ある場合はダウンロード内容を検証します。

### バージョンと更新の規則

- プラグインは minAppVersion（例：0.9.2）を宣言し、公式インデックスと一致させる必要があります。現在の apiVersion は 2 で、HentaiPark 0.9.2 以降が必要です。更新と URL インストールは置き換え前に互換性を確認し、非対応の場合は既存プラグインを保持します。自動通知では更新可能なものとアプリ更新が必要なものを分けます。「このバージョンを通知しない」は表示中のアプリ・プラグインのバージョンだけに適用され、再起動後も保持されます。手動確認には影響しません。

- バージョンはドット区切りで先頭ゼロのない 3 つの非負整数（例：`0.0.1`）で、各部分を数値で比較します。欠けた部分、余分な部分、プレリリースの接尾辞は受け付けません。
- 公式の更新ではスクリプトの UTF-8 原文の `sha256`（空白の除去や改行の変換をしない）が必要で、スクリプトが宣言した `key`、`version` はインデックスと一致する必要があります。`apiVersion` は現在のアプリのランタイムと完全に一致しなければ更新を拒否します。
- プラグインとアプリのバージョンは別々に管理します。プラグインのスクリプト（`i18n` を含む）を変更したら、スクリプトと `assets/sources/index.json` の両方でバージョンを上げます。公開ツールはダウングレードと、同じバージョンで内容が違うものを拒否します。

### アプリ内の公式更新

- 「その他 → サイト」と「その他 → このアプリについて → 更新」の「起動時にプラグインの更新を確認」は既定でオンです。起動ごとに公式インデックスだけを読み、新しいバージョンがあれば案内し、ユーザーの確認後にダウンロード、検証、インストールします。フォアグラウンドへの復帰時は 12 時間の間隔を保ち、失敗しても確認時刻を記録します。自動確認をオフにしても手動で確認できます。確認するのはインストール済みの内蔵と公式のプラグインだけで、新しいプラグインを自動でインストールしたり、同じ key のサードパーティプラグインを引き継いだりはしません。
- インストール時は識別、バージョン、取得元、API、ダイジェストを再検証し、初期化と状態の保存が成功して初めて完了します。失敗すると古いスクリプトとユーザーの状態を残し、インストール中に中断した場合は次回起動時に復元します。起動時にアプリ同梱のスクリプトで既存のプラグインを上書きすることはありません。スクリプトがない場合は登録情報とユーザーデータを残し、ユーザーが復元や更新を選ぶのを待ちます。「内蔵バージョンに戻す」は確認後、現在のアプリに同梱されたバージョンに戻します。
- アプリ自体の更新も既定で確認します。Android ではユーザーの確認後、端末に合う公式 APK をアプリ内でダウンロードし、サイズ、SHA-256、パッケージ名、バージョン、署名を検証してからシステムのインストーラーを開きます。進捗、取り消し、再試行に対応し、公式のリリースページを予備の入口とします。

### 公式プラグインの公開

公式プラグインは `assets/sources/index.json` で管理します。`tools/publish_sources.mjs` が一覧とランタイム宣言をオフラインで照合し、不変のスクリプト URL と SHA-256 を含む公開インデックスを生成します。ログインやサイトのメソッドは実行しないため、実際のリクエストによる検証は別途必要です。ビルドと公開の手順は[開発ガイド](../../DEVELOPMENT.md)を参照してください。

### ビルドで生成されるプラグイン

Telegram プラグインの唯一の実装は `assets/sources/telegram_entry.mjs` で、`assets/sources/telegram.js` はビルドで生成されるため手で編集してはいけません。

```powershell
npm ci --prefix 'tools/source-runner'
node tools/build_subscription_sources.mjs
```

[@mtproto/core 6.3.0](https://github.com/alik0211/mtproto-core)（GPL-3.0、[ライセンス](../../licenses/mtproto-core.txt)、依存関係の一覧は [サードパーティライセンス](../../licenses/telegram-dependencies.txt)）を使います。サイトの対応部分が転送、暗号、保存を置き換え、ライブラリ既定の WebSocket、ブラウザの localStorage、デバッグログは使いません。

### `webVideo(id, episodeId)`

Web 再生の Cloudflare 認証は独立した一時セッションで処理します。認証フレームは正確な `challenges.cloudflare.com` のみ許可し、そのホストへのメインフレーム移動は許可しません。年齢確認の `network.confirmation` はソースが宣言したドメインだけに適用し、外部プレーヤーには適用しません。自動処理できない場合は手動操作用にページを残し、プレーヤーの Cookie は入出力しません。`CONFIRM_REQUIRED` はプラグインの説明を保持し、アプリ内の確認ページで明示的に完了した後にソースのセッションを同期します。元の操作は再送しません。

iXXX と TubeSafari の対応済み配信元はネイティブ再生を優先し、続き再生とオフライン保存に対応します。未対応の配信元はアプリ内ウェブ再生を使用します。ウェブ再生ではサイトの確認が必要な場合があり、アプリのダウンロードと正確な続き再生には対応しません。Android のウェブ再生には独立セッション対応の新しい Android System WebView が必要です。

ランタイムは `capabilities.webVideo` を自動で公開します。`webVideo` のみを実装する場合はアプリ内ウェブページを開きます。`videos` と `webVideo` の両方を実装する場合はネイティブ再生を優先し、`videos` が `UNSUPPORTED` を返した場合だけウェブ再生に切り替えます。HTTP、ネットワーク、Cloudflare、ログイン、解析、削除、キャンセルのエラーはそのまま表示します。ダウンロードには解析できたネイティブメディアが必要で、ウェブページには切り替えません。

```js
return { url: "https://player.example.com/watch/1", navigationDomains: ["player.example.com"], frameDomains: [] };
// Native HTTP only: this.http.get(url, { followRedirects: false })
```

## ランキングと独立配信

`rankings` は `key`、`label`、`category`、`metric`、`options` で定義します。専用プラグインは `rankingOnly: true` とし、`feeds` を宣言しません。`ranking(board, {page, offset, cursor, options})` は作品ページを返し、項目には `id`、元の `rank`、`title`、`cover`、任意の `keyword`、`subtitle`、HTTPS商品 `url` を含めます。同順位を保持します。既存ソースは `feed` を指定して選択肢を継承し、`feed()` を再利用できます。作品フィールドを保持し、`workId` と不足する順位を補って詳細を開きます。販売ランキングは指定カテゴリを検索します。

ソースはメインブランチで管理します。`sources`、`rankings`、`reverse-search` はそれぞれ通常サイト、ランキング専用、画像検索専用プラグインを配信します。各ブランチには固定コミットの URL と SHA-256 を持つ索引のみを保存します。アプリは各チャネルを個別に読み込み、チャネル不一致と key の重複を拒否し、更新前に確認を求めます。タグ翻訳は `tag-translations` で別途配信します。

```powershell
node tools/publish_sources.mjs --commit '<SHA>' --channel rankings --output 'test/official-ranking-index.json'
```
