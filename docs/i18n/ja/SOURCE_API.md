[简体中文](../../SOURCE_API.md) · [繁體中文](../zh-Hant/SOURCE_API.md) · [日本語](SOURCE_API.md) · [한국어](../ko/SOURCE_API.md) · [English](../en/SOURCE_API.md) · [Español](../es/SOURCE_API.md) · [Русский](../ru/SOURCE_API.md) · [العربية](../ar/SOURCE_API.md)

# ソースプラグイン開発ガイド

HentaiPark の各オリジンは、別個の JavaScript ファイルです。アプリは実行時にそれらを読み込みます。アプリを再コンパイルすることなく、ソース リポジトリからインストール、更新、有効化/非アクティブ化できます。
組み込みソースは [`assets/sources/`](../../../assets/sources/) にあり、サンプル参照として直接使用できます。

## 実行環境

- ソース スクリプトは、アプリ内のヘッドレス WebView で実行されます (`DOMParser` を含む完全な最新の JS)。ネットワーク、暗号化、Cookie はすべてネイティブ層によって提供されるため、CORS の制限はありません。
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

`text()` / `json()` は、2xx 以外の応答が発生すると自動的にエラー (404 → `NOT_FOUND`) をスローします。 Cookie は自動的に保存され、リダイレクトが行われた後も保持されます。

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

**ビデオ** (`videos`): `[{ quality: 1080, label: '1080P', url, headers?, preferred? }]`。通常、ビデオの直接リンクには時間制限があり、アプリは再生/ダウンロードする前に毎回リンクを再取得します。

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
- `network.mode: 'browser'` + `network.origin`: リクエストは、`origin` で開かれた非表示のブラウザ ページで、発信元 `fetch()` を使用して、実際のブラウザのフィンガープリントを使用して行われました。より厳重に保護されている Cloudflare サイトに適用されます (例: Hanime1)。

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

ウェアハウスは `index.json` で、任意の静的ホスティング (GitHub raw など) に配置できます。

```json
{ "name": "Example source repository", "sources": [
  { "key": "mysite", "name": "Example Source", "version": "0.0.1", "type": "comic", "file": "mysite.js", "description": "…" }
] }
```

`file` は、`index.json` に対する相対パスです (完全な `url` を記述することもできます)。ユーザーは、「ソースサイト管理→ソースの追加」で倉庫のアドレスを入力することで、参照、インストール、更新を行うことができます。

自動メンテナンス アカウントで障害が発生した場合は、障害の数と次の再試行時間を保存し、バックオフ間隔で再試行する必要があります。現在の制限期間中は、繰り返しの登録またはログインはできません。積極的に再試行するユーザーは元のアカウントを再利用するため、サーバー側の現在の制限をスキップすることはできません。
