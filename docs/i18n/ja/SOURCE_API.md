[简体中文](../../SOURCE_API.md) · [繁體中文](../zh-Hant/SOURCE_API.md) · [日本語](SOURCE_API.md) · [한국어](../ko/SOURCE_API.md) · [English](../en/SOURCE_API.md) · [Español](../es/SOURCE_API.md) · [Русский](../ru/SOURCE_API.md) · [العربية](../ar/SOURCE_API.md)

# ソースプラグイン開発ガイド

HentaiPark の各オリジンは、別個の JavaScript ファイルです。アプリは実行時にそれらを読み込みます。アプリを再コンパイルすることなく、ソース リポジトリからインストール、更新、有効化/非アクティブ化できます。
組み込みソースは [`assets/sources/`](../../../assets/sources/) にあり、サンプル参照として直接使用できます。

## 実行環境

- ソーススクリプトはアプリ内のヘッドレス WebView で実行されます（`DOMParser` を含む最新の JS）。暗号処理、Cookie、ネイティブ HTTP リクエストはネイティブ層が提供します。ネイティブ HTTP に CORS 制限はありませんが、ブラウザのネットワーク・メディアリクエストは下記の個別規則に従います。
- 同じランタイム ([`assets/runtime/park_runtime.js`](../../../assets/runtime/park_runtime.js)) を Node で実行することもでき、開発中に実際のサイトでスモーク テストを直接実行できます。

  ```bash
  cd tools/source-runner && npm install
  node ../../test/source-runner/smoke.mjs nhentai.js --keyword "tag:\"full color\""
  ```

  `smoke.mjs` は `test/source-runner/` に置くローカルのテストファイルで、リポジトリには含まれません。各 feed（2ページ目を含む）、検索、ランダム作品、詳細、表紙、章、最初と最後のページ画像のダウンロードを順に確認します。

## ソースを登録する

```js
Park.register({
  key: 'mysite',              // 一意の識別子。インストール後は変更できません
  name: 'Example Source',
  version: '0.0.1',           // ウェアハウス内のバージョン番号が高い場合、アプリは更新を求めるプロンプトを表示します。
  type: 'comic',              // comic | video
  color: '#E5355F',           // ブランドカラー: ソース入口カードとソースページのテーマカラーに使用されます。
  description: 'Example source description',
  homepage: 'https://example.com',
  domains: ['example.com'],                   // 所属するサイトについては、「分離とセキュリティ」を参照してください。省略した場合はホームページなどのアドレスから推測されます。
  linkPatterns: ['example\\.com/g/(\\d+)'],   // 集約検索にリンクを貼り付けるときに直接アクセスするために使用されます。最初のグループは作品IDです
  idPattern: '^(\\d+)$',                      // 番号を直接入力してダイレクトアクセスする場合に使用します。
  imageHeaders: { Referer: 'https://example.com/' },  // 表紙や写真を読み込むときにデフォルトで適用されます
  network: { mode: 'native' },                // 「ネットワーク」セクションを参照してください。
  media: { mode: 'browser', origin: 'https://example.com', domains: ['media.example.com'] },  // 任意の HLS メディア権限。下記参照

  settings: [ /* option definitions */ ],
  account: { /* optional account */ },
  defaultFeed: 'ranking',                     // 元のページを開いたときにデフォルトで入力されるラベル (フィードにキー入力)
  feeds: [ /* browse tabs */ ],
  searchFilters: [ /* search filters */ ],
  searchHint: 'Search by title or tag',

  async init() {},                            // オプション: ロード時に 1 回呼び出されます (ドメイン名リストの更新など)。
  async onSettingsChanged() {},               // オプション: ユーザーがソース設定を変更した後に呼び出されます。

  async feed(key, { page, cursor, options }) {},
  async search({ keyword, page, cursor, filters }) {},
  async random() {},                          // 作品IDを返します
  async detail(id) {},
  async chapter(id, chapterId) {},            // 漫画
  async resolveImage({ id, chapterId, index, token, retry }) {},  // オプション: 画像の遅延解析
  async thumbnails(id, page) {},              // オプション: プレビューのサムネイルをページにロードします
  async videos(id) {},                        // ビデオ
});
```

このメソッドでは、`this` を使用して以下にアクセスできます。

|メンバー |説明 |
|------|------|
| `this.http` | `request(opts)`、`get(url, opts)`、`post(url, opts)`、`text(url, opts)`、`json(url, opts)` |
| `this.config` |ソース設定でユーザーが選択した値 (設定されていない場合は `default`) |
| `this.store` |永続的なキーと値のストレージ: `get(key, fallback)` / `set(key, value)`、トークン、ドメイン名リストなどの保存に使用されます。 `await flush()` は、ディスクの書き込みが成功したことを確認し、失敗した場合はエラーをスローします。
| `this.cookies` | `get(url)` / `set(url, {name: value})` / `clear(url)` |
| `this.log(...)` |アプリの「実行ログ」に書き込む |

グローバルツール:

|ツール |説明書 |
|------|------|
| `Park.html.parse(text)` |標準の `Document` を返します。`querySelector` | を使用できます。
| `Park.html.text(node)` / `unescape(s)` / `strip(html)` |テキスト処理 |
| `Park.crypto.md5Hex(text \| text[])` | MD5、バッチ計算のために配列を渡すことができます |
| `Park.crypto.sha256Hex` / `hmacSha256Hex(key, text)` / `aesEcbDecrypt(base64, key)` / `uuid()` |ネイティブ実装、高速 |
| `Park.utils.rateLimiter(ms)` | `wait()` を返し、2 つのリクエスト間の最小間隔を保証します。
| `Park.utils.mapLimit(items, n, fn)` / `lruMap(n)` / `parseCount('1.2万')` / `formatDate(ts)` |その他の一般的に使用されるツール |
| `Park.error(code, message)` |エラー コード付きのエラーがスローされます。以下を参照してください。

### `http.request(opts)`

```js
await this.http.request({
  url, method: 'GET', headers: {}, params: { q: 'x' },   // params は URL に連結されます
  json: {...} | form: {...} | body: 'raw',
  timeout: 15000,
  responseType: 'text' | 'base64',
});
// → { status, headers, body, url, ok, json() }
```

`text()` / `json()` は非 2xx レスポンスで自動的にエラーを投げます（404 → `NOT_FOUND`）。Cookie は自動保存され、リダイレクト先のアドレスごとに選び直されます。異なるオリジンへのリダイレクトでは元の認証ヘッダーを送信しません。リクエスト本文を保持したまま異なるオリジンへ転送するリダイレクトは拒否します。

## データ構造

**リストページ** (戻り値 `feed` / `search`)

```js
{
  items: [WorkItem], page: 1, totalPages: 20, total: 500,
  hasNext: true,
  cursor: '12345',        // オプション: カーソルでページをめくるサイト (E-Hentai など) は次のページ カーソルを返し、アプリは次回リクエストを行うときにそれをそのまま返します。
}
// またはセクション レイアウト (フィードのレイアウトが「セクション」の場合):
{ sections: [{ title: 'Latest chapters', items: [WorkItem] }], hasNext: false }
```

**作業項目**: `{ id, title, subtitle?, cover, coverAspect?, pages?, rating?, likes?, views?, language?, category?, badge?, badgeColor?, duration?, uploaded?, tags? }`

- `coverAspect` (幅 / 高さ) は、ジャンプを避けるために画像が読み込まれる前にグリッド レイアウトを作成します。
- `badgeColor` カテゴリ ラベルに使用される色 (例: E-Hentai 各カテゴリの従来の配色)。

**詳細** (`detail`): WorkItem のすべてのフィールド。さらに次のものが含まれます。

```js
{
  url, authors: [], description, uploader?, size?, comments?,
  tags: [{ namespace: 'artist', label: 'Author', tags: [{ name, keyword, filters?, count? }] }],
  chapters: [{ id, title }] | null,   // null は単一の章を表します
  singleChapterId?,                   // 単一章作品に必要な章ID (例: Bika の場合は「1」)
  thumbnails?: [url | {url, width, height, offsetX, offsetY}],   // スプライト画像をサポート
  related?: [WorkItem], series?: [WorkItem],
}
```

タグをクリックすると、アプリはソース内で `keyword` と `filters` を検索するため、タグをサイトのネイティブ構文 (例: `artist:"xxx"`) またはフィルター パラメーター (例: Hanime1/`tags[]`)。

**章** (`chapter`)

```js
{ pages: [
  { url, headers?, fallbacks?: [url], width?, height?, transform? },  // 住所がわかっている
  { token: '12' },                                                      // 遅延解決: アプリはresolveImageを呼び出します
]}
```

- `fallbacks`: バックアップ ミラー。プライマリ アドレスに障害が発生したときに順番に試行します。
- `transform: { type: 'unscramble-strips', segments: N }`: 画像が水平方向に N 個のストリップにカットされ、逆の順序で保存されると (JMComic)、アプリは GPU 上でネイティブに復元されます。ダウンロードしたオフライン ファイルは元の画像を保存し、表示時に復元します。
- `resolveImage` は `{ url, headers?, width?, height?, cacheKey? }` を返します。失敗すると、アプリは `retry` を増分して再度呼び出します。ソースはこれを使用してサーバー (`nl` パラメーター) を変更できます。 E-Hentai）。

**ビデオ** (`videos`): `[{ quality: 1080, label: '1080P', url, headers?, format?, preferred? }]`。通常、ビデオの直接リンクには時間制限があり、アプリは再生/ダウンロードする前に毎回リンクを再取得します。

- `format` を省略すると、直接 MP4 を再生・ダウンロードする経路を使います。HLS は `format: 'hls'` を明示し、manifest に下記の `media` 権限を宣言する必要があります。
- HLS マスター再生リスト（`#EXT-X-STREAM-INF`）は、まずホストが各画質の独立したセグメント再生リストに展開し、`RESOLUTION` から実際の画質を取得してプレーヤーやダウンローダーに渡します。マスターを返す場合、`quality` は希望画質を示し、それ以下で利用できる最高画質を既定で選びます。該当しなければ最も高い画質を選びます。各バリアントは音声と映像を多重化した MPEG-TS である必要があります。別ストリームの `AUDIO`、`VIDEO`、`SUBTITLES` renditions と `media.domains` 外の URL は拒否します。
- 展開後の HLS は `#EXT-X-ENDLIST` を含む完全で連続した MPEG-TS オンデマンド再生リストのみ対応しています。ライブ、暗号化、バイト範囲、fMP4、discontinuity、gap には対応していません。MissAV の非標準タグ `#EXT-X-TOKEN` は削除され、プレーヤーには渡されません。
- 再生には `127.0.0.1` のみにバインドしたランダムなポートとトークンを使い、有限の URL 登録表から検証済みセグメントを必要に応じて取得します。セッション終了時にリクエストをキャンセルします。HLS のオフラインダウンロードは現在 Android のみ対応し、各セグメントを検証して SHA-256 を保存し、再開時に再検証します。キャンセルにも対応し、最後に端末上の Media3 で MP4 に再多重化して、完成したファイルのみをオフラインライブラリに公開します。iOS/macOS の HLS 再生は今回検証していないため、検証済みとは表記できません。

## オプションの定義

`feeds[].options`、`searchFilters`、`settings` は同じ形式を使用します。

```js
{ key: 'sort', label: 'Sort', type: 'select', default: 'date',
  values: [{ value: 'date', label: 'Latest' }, { value: 'popular', label: 'Popular', color: '#f00' }] }
// type: select（単一選択）| multi（複数選択）| number | text | password | switch
// settings では values の代わりに options を使うこともできます。
```

`feeds` の各項目は、ソース ページ `{ key, label, layout?: 'grid' | 'sections', options?: [...] }` のタブです。

`defaultFeed` 元のページを開いたときにデフォルトで入るタブを指定します。該当するキーが未入力または見つからない場合は、アプリがおすすめ > ランキング > 人気の順でキーに応じて自動的に選択します (キーには `promote` / `recommend` / `featured` が含まれます)。 `rank` / `toplist`、次に `popular` / `hot` / `trending`)、そうでない場合は最初の文字列を入力しますラベル。

## ネットワーク

- `network.mode: 'native'` (デフォルト): 永続的な Cookie を使用するネイティブ HTTP リクエストは、ユーザーが設定したプロキシを通過できます。 Cloudflare クエリが検出された場合、`CLOUDFLARE` がスローされます。このアプリは、ユーザーが組み込みブラウザで検証を完了し、共通 Cookie をネイティブ リクエストに同期するようにガイドします。
- `network.mode: 'browser'` + `network.origin`: リクエストは、`origin` で開かれた非表示のブラウザ ページで、発信元 `fetch()` を使用して、実際のブラウザのフィンガープリントを使用して行われました。より厳重に保護されている Cloudflare サイトに適用されます (例: Hanime1)。 同一オリジンの GET が Cloudflare 認証ページを返した場合、非表示ブラウザでその文書を開いて自動認証を行い、元のリクエストを一度だけ再試行します。認証に失敗すると `CLOUDFLARE` を返し、既存の手動認証フローに進みます。

## ブラウザメディア（HLS）

ブラウザメディア権限は `this.http`、`network`、サイトの Cookie 同期とは独立しています。MissAV の例：

```js
domains: ['missav.ai'],
network: { mode: 'browser', origin: 'https://missav.ai' },
media: { mode: 'browser', origin: 'https://missav.ai', domains: ['surrit.com'] },
```

- `media.origin` はソースが宣言したサイトに属し、HTTPS の既定ポート 443 を使用する必要があります。URL に認証情報を含めてはいけません。非表示ブラウザがその同一オリジンのページでメディアセッションを開始します。
- `media.domains` はサブドメインを含む独立したメディア許可リストで、ソースサイトの Cookie 権限は付与しません。再生リストとセグメントは HTTPS 443 のみ許可し、URL の認証情報、フラグメント、IP アドレス、localhost（サブドメインを含む）、`.local` を拒否します。リクエストは `credentials: 'omit'`、`mode: 'cors'`、`redirect: 'error'` を使い、CDN の CORS 規則に従い、リダイレクトしません。
- 応答はストリーミング中にサイズを制限し、応答 URL を再検証します。再生リストは最大 2 MiB、各セグメントは最大 32 MiB です。上限超過、空の応答、URL の変更を拒否します。所属サイトを指定する `domains` と、同一オリジンで Cookie を送る `network` の規則は変わりません。メディアドメインとサイトのログイン状態は共有できません。

## 分離とセキュリティ

- 各ソースは **独立した** JS 環境で実行され (それぞれにインターフェイスのない WebView があります)、ソースは互いのグローバル オブジェクトを認識できません。ネイティブ ブリッジは、呼び出しがどの環境から来たのかを認識するだけであり、スクリプトは他のソースになりすますことはできません。
- 各ソースには独立した Cookie jar があります。ソースによって発行されたリクエストは、独自の Cookie を取得および保存するだけであり、他のソースのログイン ステータスは読み取りません。
- `domains` はソースが属するサイトを宣言します (ドメイン名を登録可能、サブドメイン名は自動的に含まれます)。これらのサイトからの Cookie のみが組み込みブラウザ (Cloudflare 認証、Web ログインで共有) に同期され、ブラウザ モードの `network.origin` もこれらのサイトに属している必要があります。省略した場合は、`homepage`、`network.origin`、`account.cookieUrl/loginUrl`から推測します。
- ウェブサイトや倉庫からソースをインストールする場合、アプリはまずインターネットに接続できないサンドボックス内のスクリプト情報を読み取り、名前、バージョン、SHA-256、宣言されたサイト、およびリスク警告をユーザーに表示し、確認後にインストールします。ソース ウェアハウスの `index.json` エントリには `sha256` フィールドを含めることができ、ダウンロード コンテンツが一致しない場合、インストールは拒否されます。

## アカウント

```js
account: {
  type: 'password' | 'cookies',
  title, hint, required: false,
  fields: [{ key: 'email', label: 'Email' }, { key: 'password', label: 'Password', secret: true }],
  loginUrl?, cookieUrl?, requiredCookies?: ['ipb_member_id'],   // 提供後、Web ページにログインすると、アプリが自動的に Cookie を取得します。
  async login(values) { return { name } },
  async logout() {},
  async status() { return { loggedIn, name, configured } },
  managedAccount: true,                 // オプション: 専用の自動メンテナンス アカウントを提供します
  async enableManaged() {},             // ユーザーが登録を確認した後にのみ呼び出されます
}
```

`configured` は、現在のログインが成功したかどうかに関係なく、アカウントが構成されていることを示します。 `managedAccount: true` は、ソースが専用の自動メンテナンス アカウントをサポートしていることを宣言します。ソース設定では、同じ名前の `managedAccount` スイッチが使用されます。ホストは、有効化設定を保存して `account.enableManaged()` を呼び出す前に、最初に自動登録手順を表示し、ユーザーの確認を取得する必要があります。失敗またはアプリケーションの再起動後に同じアカウントを確実に復元できるように、候補資格情報を保存し、登録前に `await this.store.flush()` を使用する必要があります。

PicACG の例では、手動資格情報と専用アカウントを個別に保存します。既存の手動アカウントを専用アカウントで上書きしてはなりません。専用アカウントを保持するにはスイッチをオフにし、再利用するにはオンに戻します。トークンの有効期限が切れた場合は、再度ログインすることのみが可能であり、再登録はできません。登録が失敗するか、応答が失われた後は、冗長なアカウントの作成を避けるために、元の候補アカウントを再試行してください。アカウントのパスワード、トークン、およびソースのステータスはすべてユーザーのローカル データです。実際の認証情報をドキュメントやログに出力しないでください。

## 国際化

アプリケーション インターフェイスのサポート `zh-Hans`、`zh-Hant`、`ja`、`ko`、 `en`、`es`、`ru`、`ar`。マテリアル、クパチーノ、およびシステム コントロールは対応する言語を使用します。アラビア語のインターフェイスは右から左に進みます。インターフェイス言語設定はすぐに有効になり、永続的に保存されます。デフォルトではシステムに従います。中国語の文字と地域によって、簡体字中国語と繁体字中国語のどちらを使用するかが決まります。

Flutter インターフェイスは一律に `tr('已选 {count}', {'count': count})` または `context.tr` を呼び出します。メッセージの元の中国語テキストがリソース キーとして使用され、パラメータは `{name}` で、8 か国語のリソースは次の場所にあります。 `assets/i18n/`。表示されているコピーを追加または変更する場合、すべてのリソースを同時に更新し、プレースホルダーが一貫している必要があります。プラグインの静的名、説明、参照ラベル、オプション、およびエラー プロンプトは、アプリケーションの表示時にリソース マップされます。リモート作業のタイトル、作成者、タグ、ユーザー入力、および永続化プロトコル キーは元のテキストのままです。

## エラーコード

`throw Park.error(code, message)` を使用してエラーをスローすると、アプリはエラー コードに基づいて対応するガイダンスを提供します。

|コード |アプリの処理 |
|------|-----------|
| `CLOUDFLARE` | 「検証に進む」ボタン: 内蔵ブラウザを開きます |
| `LOGIN_REQUIRED` | 「ログインに進む」ボタン: ソース設定のアカウント領域を開きます |
| `NOT_FOUND` | 「コンテンツが存在しません」と表示 |
| `BLOCKED` | 「アクセスが制限されています」と表示されます (IP がブロックされている、クォータが使い果たされているなど)。画像は再試行されません。
| `NETWORK` / `HTTP` / `PARSE` | 「再試行」ボタンでエラーメッセージを表示 |

## ソース倉庫

リポジトリは、静的ホスティングに配置できる `index.json` です (例: GitHub raw)。ユーザーは、[ソース サイト管理] → [ソースの追加] に倉庫のアドレスを入力することで、参照、インストール、更新できます。

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

`url` はスクリプトの完全なアドレスです。 `index.json` に対して `file` を使用することもできます。サードパーティ ウェアハウスは、ユーザーの確認後に手動でインストールされます。 `sha256` はオプションです。ダウンロードしたコンテンツは提供時に検証されます。

公式の自動更新では、厳密なルールが採用されています。バージョンは、ドットで区切られ、先頭のゼロのない 3 つのセグメントからなる非負の整数である必要があります (たとえば、`0.0.1`、`0.1.0`)。数値によってセグメントごとに比較されます。欠落しているセグメント、複数のセグメント、またはプレリリースのサフィックスは受け入れられません。スクリプト `sha256` の元の UTF-8 テキストは、空白のトリミングや改行の変換を行わずに提供する必要があります。スクリプトによって宣言された `key` および `version` は、インデックスと一致している必要があります。 `apiVersion` は、現在のアプリのランタイムと完全に一致する必要があります。一致しない場合は自動アップデートが拒否されます。まず、この API をサポートするアプリを使用する必要があります。互換性のあるブランチは提供されていません。

### アプリの公式アップデート

「Origin Site Management」はデフォルトで「公式ソースを自動的に更新する」をオンにし、起動時またはフォアグラウンドに戻るときに 12 時間ごとにチェックします。失敗した場合は、頻繁な再試行を避けるためにチェック時間も記録されます。 「今すぐアップデートを確認」は、自動アップデートをオフにした後も利用できます。インストールされている組み込みソースと公式オンライン ソースのみをアップグレードします。新しいソースを自動的にインストールしたり、ユーザーがインストールした同じ名前のサードパーティのソースを引き継いだりすることはありません。

インストール中に ID、バージョン、API、ダイジェストを確認し、初期化と状態の永続化が成功するまで待ってから更新を完了します。古いスクリプトとユーザーのステータスを保持できない。インストール中にアプリケーションが中断された場合、次回起動時に復元されます。新しいオンライン バージョンは、組み込みスクリプトの古いバージョンまたは同一のバージョンよりも優先され、新しいインストール パッケージがより高いバージョンを搭載している場合は、通常どおりアップグレードできます。 「組み込みソースの復元」では、現在のインストール パッケージ バージョンにアクティブにロールバックできます。後で自動更新を有効にしても、引き続き正式な新しいバージョンを入手できます。

### 公式ソースの公開

公式ソースは公開メイン ウェアハウス [drdon1234/Hentai-Park](https://github.com/drdon1234/Hentai-Park) に従い、クライアントへの固定入り口は次のとおりです。

```text
https://raw.githubusercontent.com/drdon1234/Hentai-Park/sources/index.json
```

`assets/sources/index.json` は維持される唯一のソース リストであり、`file` は同じディレクトリ内の唯一のスクリプト ソース コードを指します。ファイル名は `[A-Za-z0-9_-]+.js` に準拠する必要があります。ファイル名の本文内のサブディレクトリ、シンボリック リンク、またはドットは受け入れられず、クライアントの公式ソース アドレス検証と一致している必要があります。 `tools/publish_sources.mjs` 公開インデックスを生成します。各レコードには、`key`、`name`、`version`、`description`、が含まれます。 `url`、`sha256`、および `apiVersion`。スクリプト URL は、このソース コードの完全な 40 桁のコミット番号に固定されています。

```text
https://raw.githubusercontent.com/drdon1234/Hentai-Park/<源码提交 SHA>/assets/sources/<file>
```

`sources` ブランチは、スクリプトをコピーしたり、2 番目のソース リストを手動で管理したりせず、生成されたルート ディレクトリ `index.json` のみを保存します。スクリプトを更新するときは、スクリプト内のバージョンとマニフェストを同時にアップグレードする必要があります。発行者はバージョンのダウングレードを拒否し、異なるスクリプト コンテンツに対応する同じバージョンも拒否します。同じバージョンを内容を変更せずに繰り返し公開することができ、通常のアップグレードは古いインデックス バージョンの影響を受けません。

パブリッシャーは Node.js 組み込みモジュールのみに依存しており、Node.js 22 以降ではオフラインで実行できます。マニフェスト、ファイルの存在、ディレクトリ境界をチェックし、ネットワークまたはストレージ インターフェイスを提供しない別のコンテキストで共有ランタイムとスクリプトを読み込み、アプリ インストール プレビュー `key` と同じ `Park.__pending` / `Park.manifest` プローブを使用してチェックします。 `version` および API。この検出では、`setup`、`init`、ログインまたはサイト ビジネス メソッドは呼び出されず、元のサイトのネットワーク ユーザビリティ テストを置き換えることはできません。

ローカル プレビューの例 (出力は `test/` にありますが、これは無視され、公開されません。コミット番号は、対応するソース コードの実際の SHA を使用する必要があります):

```powershell
node tools/publish_sources.mjs --commit '<完整 40 位源码提交 SHA>' --output 'test/official-source-index.json'
```

既存のリリースを確認する必要がある場合は、`--previous '旧索引本地路径'` を渡します。古いインデックスが無効で検証が失敗した場合でも、バージョン保護は暗黙的にスキップされません。ワークスペースにコミットされていない変更がある場合、ローカルの結果はプレビューにのみ使用されます。正式リリースは、ワークフローによってチェックアウトされたソース コードを送信することによって生成されます。

`.github/workflows/publish-sources.yml` メイン リポジトリのデフォルト `main` ブランチ関連ファイルがプッシュされた場合、または `main` から手動でトリガーされた場合にのみ実行されます。ワークフローはシリアルに実行され、最新の `main` は各タスクの開始時にチェックアウトされ、スクリプト アドレスとリリース レコードは実際にチェックアウトされたコミット番号で固定されます。タスクの実行中にその後ドキュメントを送信しても、公開が妨げられることはありません。後続のソース ファイルの送信により、次のシリアル タスクがトリガーされます。ワークフローは、最初に既存の安定したインデックスをダウンロードしてすべてのオフライン検証を完了し、次に通常の Git を使用してアトミック更新を `sources` ブランチにプッシュします。検証が失敗した場合、または `sources` ブランチで同時に変更が発生した場合、オンライン インデックスは上書きされません。パブリケーションは、安定したインデックスなしで初めて作成される可能性があります。このリリースでは、スクリプトとインデックスが上記の検証に合格したことのみが示されます。サイトへのアクセス、アカウントへのログイン、画像またはビデオの読み込みは個別に検証する必要があります。
