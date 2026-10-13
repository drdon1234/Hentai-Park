[简体中文](../../SOURCE_API.md) · [繁體中文](../zh-Hant/SOURCE_API.md) · [日本語](SOURCE_API.md) · [한국어](../ko/SOURCE_API.md) · [English](../en/SOURCE_API.md) · [Español](../es/SOURCE_API.md) · [Русский](../ru/SOURCE_API.md) · [العربية](../ar/SOURCE_API.md)

# ソースプラグイン開発ガイド

HentaiPark の各オリジンは、別個の JavaScript ファイルです。アプリは実行時にそれらを読み込みます。アプリを再コンパイルすることなく、ソース リポジトリからインストール、更新、有効化/非アクティブ化できます。
組み込みソースは [`assets/sources/`](../../../assets/sources/) にあり、サンプル参照として直接使用できます。

## 実行環境

- ソーススクリプトはアプリ内のヘッドレス WebView で実行されます（`DOMParser` を含む最新の JS）。暗号処理、Cookie、ネイティブ HTTP リクエストはネイティブ層が提供します。ネイティブ HTTP に CORS 制限はありませんが、ブラウザのネットワーク・メディアリクエストは下記の個別規則に従います。
- 同じランタイム ([`assets/runtime/park_runtime.js`](../../../assets/runtime/park_runtime.js)) を Node で実行することもでき、開発中に実際のサイトでスモーク テストを直接実行できます。

ルートで共有 runner の依存関係をインストールし、無視される `test/source-smoke.mjs` を以下の例で作成します。例は manifest の読込のみです。変更したソースのホーム、2ページ目、検索、詳細、表紙のデコード、章とメディアを実測してください。Node ホストは開発用で、未信頼スクリプトの安全な隔離ではありません。

```js
import { loadSource } from '../tools/source-runner/host.mjs';
const { manifest } = await loadSource('nhentai.js');
console.log(manifest.key, manifest.version);
```

```powershell
npm ci --prefix 'tools/source-runner'
node 'test/source-smoke.mjs'
```

## ソースを登録する

```js
Park.register({
  key: 'mysite',              // 一意の識別子。インストール後は変更できません
  name: 'Example Source',
  version: '0.0.1',           // ウェアハウス内のバージョン番号が高い場合、アプリは更新を求めるプロンプトを表示します。
  type: 'comic',              // comic | video | novel | game
  category: 'doujin',         // doujin | anime | aiDrama | jav | adult | shortvideo | gallery | novel | game | other
  color: '#E5355F',           // ブランドカラー: ソース入口カードとソースページのテーマカラーに使用されます。
  description: 'Example source description',
  homepage: 'https://example.com',
  domains: ['example.com'],                   // 所属するサイトについては、「分離とセキュリティ」を参照してください。省略した場合はホームページなどのアドレスから推測されます。
  linkPatterns: ['example\\.com/g/(\\d+)'],   // 集約検索にリンクを貼り付けるときに直接アクセスするために使用されます。最初のグループは作品IDです
  idPattern: '^(\\d+)$',                      // 番号を直接入力してダイレクトアクセスする場合に使用します。
  imageHeaders: { Referer: 'https://example.com/' },  // 表紙や写真を読み込むときにデフォルトで適用されます
  network: { mode: 'native', vpnHint: true },                // 「ネットワーク」セクションを参照してください。
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
  async detail(id, preview) {},
  async chapter(id, chapterId) {},            // 漫画
  async resolveImage({ id, chapterId, index, token, retry }) {},  // オプション: 画像の遅延解析
  async thumbnails(id, page) {},              // オプション: プレビューのサムネイルをページにロードします
  async videos(id, episodeId = '_') {},                        // ビデオ
});
```

`type` は閲覧または再生を決め、`category` はホーム、ソース管理、検索の分類を決めます。不明または未指定の分類は「その他」です。既定のフィードはおすすめ、ランキング、人気の順に選び、いずれもない場合のみ最新を使用します。

AIショートドラマには `category: 'aiDrama'` を使用し、旧識別子 `drama` は受け付けません。サイトのチャンネル名はアプリの分類とは独立しており、元の名前を保持します。アプリの分類でサイトのチャンネルを自動的に除外することはありません。

`adult` は Pornhub、XVideos、91porn などの総合成人動画サイトの分類で、`type: 'video'` を指定します。JAV 専門サイトには `jav` を使用します。分類はサイトのタグやユーザーの絞り込みを置き換えません。

集約動画ソースも `type: 'video', category: 'adult'` を指定します。確認済みメディア API がなければ `videos` を実装せず、`capabilities.videos: false` になります。詳細の主操作は `detail.url` をシステムブラウザーで開き、再生・ダウンロード・話一覧を非表示にし、架空の章同期や更新確認を行いません。お気に入りと履歴は保持します。任意の `detail(id, preview)` はソースと ID が一致する公開メタデータだけを受け取り、ソース側でも ID と URL を検証します。iXXX は既知の追跡パラメーターを除いた上流 URL、TubeSafari は上流 key を安定 ID に使い、ソース Cookie で外部作品を要求しません。プレビューなしの直接参照も開けますが、題名や表紙が不足する場合があります。Thumbzilla は MP4 メタデータを静的に解析し、配信ドメインを制限します。

`gallery` はイラスト、コスプレ、写真集の分類です。画像ソースは `type: 'comic'` を使用し、1 ギャラリーを1作品として扱い、`chapter()` で画像を順番に返します。閲覧・ライブラリ・ダウンロードは既存機能を利用します。画像数や内容の露出度で分類を分けません。

暗号化画像は `imageDecrypt` で宣言します。形式検査とキャッシュ前に復号し、復号設定もキャッシュ識別に含めます。失敗はキャッシュしません。AES-CBC と厳密な PKCS#7 パディングに対応し、`key` と `iv` は UTF-8 で符号化します。画像ドメインを限定し、それ以外の画像は変更しません。

```js
imageDecrypt: {
  type: 'aes-cbc',
  key: '0123456789abcdef', // UTF-8: 16, 24 or 32 bytes
  iv: '0123456789abcdef',  // UTF-8: 16 bytes
  domains: ['images.example.com'],
},
```

ネットワークエラーには安全な `diagnostics` の `host`、`transport`、`reason` を付与し、証明書、ハンドシェイク、DNS、接続、タイムアウトを区別します。自動ログは許可された項目のみを記録し、元のメッセージ、認証情報、本文、署名 URL は記録しません。

`reason: 'TLS_HANDSHAKE_TERMINATED'` はネイティブの `HandshakeException.message` が `Connection terminated during handshake` と完全に一致した場合のみです。証明書検証の失敗ではなく、TLS ハンドシェイク完了前の切断を示します。本文のない HTTPS GET / HEAD のみ、このエラーで一度再試行します。キャンセル、証明書、その他の TLS、HTTP、応答読み取りエラーは再試行しません。再失敗時はホストと VPN・プロキシ経路の確認案内を表示し、安全な診断項目のみを記録します。

このメソッドでは、`this` を使用して以下にアクセスできます。

|メンバー |説明 |
|------|------|
| `this.http` | `request(opts)`、`get(url, opts)`、`post(url, opts)`、`text(url, opts)`、`json(url, opts)` |
| `this.config` |ソース設定でユーザーが選択した値 (設定されていない場合は `default`) |
| `this.store` |永続的なキーと値のストレージ: `get(key, fallback)` / `set(key, value)`、トークン、ドメイン名リストなどの保存に使用されます。 `await flush()` は、ディスクの書き込みが成功したことを確認し、失敗した場合はエラーをスローします。
| `this.cookies` | `get(url)` / `set(url, {name: value})` / `clear(url)` |
| `this.log({code, host, transport, reason})` | 許可された構造化フィールドのみ保存し、自由文は保存しません。 |

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
// sections を返すと、応答に基づいてアプリがセクション表示を選択します。
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

- ビデオソースは `detail(id).chapters` に再生順の `[{id, title}]` を返します。各 `id` は安定した識別子とし、画質名や一時的なメディア URL を使わないでください。ホストは同じ ID で選択、個別進捗、ダウンロード、再開を管理し、`videos(id, episodeId = '_')` でそのエピソードのリソースを取得します。単一ビデオには `singleChapterId` を使い、省略時は `'_'` とします。
- `format` を省略すると、直接 MP4 を再生・ダウンロードする経路を使います。HLS は `format: 'hls'` を明示し、manifest に下記の `media` 権限を宣言する必要があります。
- HLS マスター再生リスト（`#EXT-X-STREAM-INF`）は、まずホストが各画質の独立したセグメント再生リストに展開し、`RESOLUTION` から実際の画質を取得してプレーヤーやダウンローダーに渡します。マスターを返す場合、`quality` は希望画質を示し、それ以下で利用できる最高画質を既定で選びます。該当しなければ最も高い画質を選びます。各バリアントは音声と映像を多重化した MPEG-TS である必要があります。別ストリームの `AUDIO`、`VIDEO`、`SUBTITLES` renditions と `media.domains` 外の URL は拒否します。 任意の `#EXT-X-I-FRAME-STREAM-INF` 早送りプレビュートラックは無視され、アドレスは登録も取得もされません。単一メディアプレイリストの解像度が不明な場合は `label: '原画'` を指定します。ラベルは画面の言語に翻訳され、希望画質を実際の解像度として表示しません。
- 展開後の HLS は `#EXT-X-ENDLIST` を含む完全で連続した MPEG-TS VOD のみ対応します。`METHOD=AES-128` と `KEYFORMAT=identity`（省略時も identity）の CBC/PKCS7 復号に対応し、鍵は正確に 16 バイト、IV は明示的な 128 ビット値またはセグメントのメディアシーケンスから導出します。鍵はセッションのメモリだけに保持し、復号した TS を再生・ダウンロード共通の処理で検証します。ライブ、SAMPLE-AES、他の KEYFORMAT、`EXT-X-MAP`、`EXT-X-BYTERANGE`、fMP4、discontinuity、gap は未対応です。MissAV の非標準 `#EXT-X-TOKEN` は削除します。
- 再生には `127.0.0.1` のみにバインドしたランダムなポートとトークンを使い、有限の URL 登録表から検証済みセグメントを必要に応じて取得します。セッション終了時にリクエストをキャンセルします。HLS のオフラインダウンロードは現在 Android のみ対応し、各セグメントを検証して SHA-256 を保存し、再開時に再検証します。キャンセルにも対応し、最後に端末上の Media3 で MP4 に再多重化して、完成したファイルのみをオフラインライブラリに公開します。iOS/macOS の HLS 再生は今回検証していないため、検証済みとは表記できません。

## オプションの定義

`feeds[].options`、`searchFilters`、`settings` は同じ形式を使用します。

```js
{ key: 'sort', label: 'Sort', type: 'select', default: 'date',
  values: [{ value: 'date', label: 'Latest' }, { value: 'popular', label: 'Popular', color: '#f00' }] }
// type: select（単一選択）| multi（複数選択）| number | text | password | switch
// settings では values の代わりに options を使うこともできます。
```

`feeds` の各項目は、ソース ページ `{ key, label, options?: [...] }` のタブです。

`defaultFeed` 元のページを開いたときにデフォルトで入るタブを指定します。該当するキーが未入力または見つからない場合は、アプリがおすすめ > ランキング > 人気の順でキーに応じて自動的に選択します (キーには `promote` / `recommend` / `featured` が含まれます)。 `rank` / `toplist`、次に `popular` / `hot` / `trending`)、そうでない場合は最初の文字列を入力しますラベル。

## ネットワーク

- `network.mode: 'native'` (デフォルト): 永続的な Cookie を使用するネイティブ HTTP リクエストは、ユーザーが設定したプロキシを通過できます。 Cloudflare クエリが検出された場合、`CLOUDFLARE` がスローされます。このアプリは、ユーザーが組み込みブラウザで検証を完了し、共通 Cookie をネイティブ リクエストに同期するようにガイドします。
- `network.mode: 'browser'` + `network.origin`: リクエストは、`origin` で開かれた非表示のブラウザ ページで、発信元 `fetch()` を使用して、実際のブラウザのフィンガープリントを使用して行われました。より厳重に保護されている Cloudflare サイトに適用されます (例: Hanime1)。 同一オリジンの GET が Cloudflare 認証ページを返した場合、非表示ブラウザでその文書を開いて自動認証を行い、元のリクエストを一度だけ再試行します。認証に失敗すると `CLOUDFLARE` を返し、既存の手動認証フローに進みます。

## メディア権限（HLS）

`media` 権限は `this.http`、`network`、サイトの Cookie 同期と独立し、どちらの転送方式も同じドメイン規則を使います。

```js
domains: ['example.com'],
network: { mode: 'native' },
media: { mode: 'native', origin: 'https://example.com', domains: ['media.example.com'] },
```

- `media.mode` は `'native'` と `'browser'` に対応します。両方とも `media.origin` はソースが宣言したサイトに属し、HTTPS の既定ポート 443 を使い、URL の認証情報、クエリ、フラグメントを含めてはいけません。
- `media.domains` はサブドメインを含む独立したメディア許可リストで、サイト Cookie の権限を与えません。再生リスト、セグメント、鍵は HTTPS 443 のみ許可し、URL 認証情報、フラグメント、IP アドレス、localhost（サブドメイン含む）、`.local` を拒否します。
- `media.mode: 'native'` は独立した認証情報なしのネイティブクライアントを使い、サイト Cookie、Authorization、プロキシ認証を送信しません。リダイレクトは各転送先を許可リストで検証してから追跡します。許可するヘッダーは `Referer`、`Origin`、`Accept`、`Accept-Language` のみで、前の二つは `media.origin` に一致する必要があります。
- `media.mode: 'browser'` は `media.origin` の非表示ブラウザでセッションを開き、`credentials: 'omit'`、`mode: 'cors'`、`redirect: 'error'` を使います。CDN の CORS 規則に従い、リダイレクトしません。
- ストリーミング中に応答サイズを制限し、応答 URL を再検証します。再生リストは 2 MiB、セグメントは 32 MiB が上限で、AES-128 鍵は正確に 16 バイトです。超過、空の応答、許可外 URL を拒否し、ソース `domains` と Cookie 付き `network` の規則は独立したままです。

## 分離とセキュリティ

- 各ソースは **独立した** JS 環境で実行され (それぞれにインターフェイスのない WebView があります)、ソースは互いのグローバル オブジェクトを認識できません。ネイティブ ブリッジは、呼び出しがどの環境から来たのかを認識するだけであり、スクリプトは他のソースになりすますことはできません。
- 各ソースには独立した Cookie jar があります。ソースによって発行されたリクエストは、独自の Cookie を取得および保存するだけであり、他のソースのログイン ステータスは読み取りません。
- Secure Cookie は HTTP では送信しません。検証ページの表示とブラウザ Cookie の取り込みは、インストール済みソースの `domains` に照らして検証し、取得できる安全属性と有効期限を保持します。Cookie の消去やソースの削除では、該当ブラウザセッションを閉じ、そのサイトのブラウザ Cookie も消去します。ブラウザのサイト Cookie はシステムで共有されるため、同じサイトを宣言するソースも消去の影響を受けます。
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

公式更新では、厳密なルールが採用されています。バージョンは、ドットで区切られ、先頭のゼロのない 3 つのセグメントからなる非負の整数である必要があります (たとえば、`0.0.1`、`0.1.0`)。数値によってセグメントごとに比較されます。欠落しているセグメント、複数のセグメント、またはプレリリースのサフィックスは受け入れられません。スクリプト `sha256` の元の UTF-8 テキストは、空白のトリミングや改行の変換を行わずに提供する必要があります。スクリプトによって宣言された `key` および `version` は、インデックスと一致している必要があります。 `apiVersion` は、現在のアプリのランタイムと完全に一致する必要があります。一致しない場合はアップデートが拒否されます。まず、この API をサポートするアプリを使用する必要があります。互換性のあるブランチは提供されていません。

### アプリの公式アップデート

起動時の自動確認では公式インデックスのみを読み込み、更新がある場合に確認を求めます。ダウンロードとインストールはユーザーの確認後に行います。前面に戻った際の確認には、失敗時を含め12時間の間隔を設けます。両方の自動確認は初期設定で有効で、個別に無効化しても手動確認は可能です。インストール済みの内蔵・公式ソースのみが対象で、第三者のソースは変更しません。

確認後、ソースの同一性、バージョン、提供元、API、SHA-256を再検証し、初期化と状態の保存が成功してから完了します。失敗時には元のスクリプトと個人データを復元し、中断したインストールは次回起動時に復旧します。起動時に既存プラグインを内蔵スクリプトで置き換えません。スクリプトがなくても登録情報とデータを保持し、新規プラグインにのみ内蔵スクリプトを導入します。内蔵ソースへの復元も確認が必要です。Android では確認後に対応する公式 APK をアプリ内でダウンロードします。サイズ、SHA-256、パッケージ名、バージョン、署名を検証し、システムでインストールを確認します。権限を許可して戻った後は「インストールを続行」を押してください。進捗、キャンセル、再試行に対応し、失敗時は公式ページを利用できます。他の環境では公式ページから手動でダウンロードします。

### 公式ソースの公開

公式ソースは公開メイン ウェアハウス [drdon1234/Hentai-Park](https://github.com/drdon1234/Hentai-Park) に従い、クライアントへの固定入り口は次のとおりです。

```text
https://raw.githubusercontent.com/drdon1234/Hentai-Park/sources/index.json
```

ソースの `key` は `[A-Za-z0-9_-]` のみ、長さは 1–100 とし、予約済みの `_app` は使用できません。スクリプト名は `{key}.js` です。

`assets/sources/index.json` は維持される唯一のソース リストであり、`file` は同じディレクトリ内の唯一のスクリプト ソース コードを指します。ファイル名は `[A-Za-z0-9_-]+.js` に準拠する必要があります。ファイル名の本文内のサブディレクトリ、シンボリック リンク、またはドットは受け入れられず、クライアントの公式ソース アドレス検証と一致している必要があります。 `tools/publish_sources.mjs` 公開インデックスを生成します。各レコードには、`key`、`name`、`version`, `category`、`description`、が含まれます。 `url`、`sha256`、および `apiVersion`。スクリプト URL は、このソース コードの完全な 40 桁のコミット番号に固定されています。

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


`type: 'video', category: 'shortvideo'` は全画面縦型フィードを有効にします。作品ごとに1本の動画を扱い、`videos(id, '_')` が最新のメディアURLを返します。`feed` の `hasNext` と `cursor` で自動ページングします。カーソルに認証情報や署名付きメディアURLを含めないでください。現在の動画のみ再生、次は停止して先読みし、他のプレーヤーは中止・解放します。未検証の検索APIは `search` を宣言しません。


任意の `imageNetwork` に `mode: browser`、HTTPS の `origin` と `domains` を指定できます。すべて源のドメイン内に限定し、許可されたヘッダーのみ使用、認証情報を送信せず、リダイレクトを拒否し、画像を20 MiBに制限します。復号、形式確認、デコード、分離キャッシュを維持します。Tik.porn のページとAPIは各自の同一オリジンで取得し、再生はMP4を使います。


## 小説の閲覧

`type: 'novel', category: 'novel'` · `capabilities.textChapter: true`

`textChapter(id, chapterId)` は空ではないプレーンテキスト `{title?, paragraphs: [String]}` を返します。一覧・詳細には `mediaKind: 'novel'`、`language: 'zh'` または `'en'` を保持します。表紙がなければ空文字列です。同じ章の本文ページのみを結合し、返信や別の章、広告は含めません。権限で切り詰められた本文は `LOGIN_REQUIRED` を返します。章は安定した ID とサイト順を使用し、単編は `chapters: null` です。`Park.html.paragraphs(node)` が文字を抽出し、ダウンロードは章ごとに `text.json` を原子的に書き込みます。進捗と注釈は原文の UTF-16 位置を使います。しおりは独立して保存し、書庫バックアップに含めます。

`paragraphs.join('\n\n')` → UTF-16


## 購読プロトコル

`subscription.normalize` と `subscription.posts` の両方を宣言すると `capabilities.subscription` が生成され、独立した購読画面に表示されます。サイト固有処理はプラグイン内に置きます。`normalize` はログインや通信なしにサイトのユーザー名または管理されたプロフィール URL を検証します。任意の `resolve` はオンライン解決、`targets` は参加済み対象を返して `subscription.joinedTargets: true` を生成します。カーソルは不透明文字列、`hasNext: false` で終了し、空ページでも続行できます。権限不足は `locked`、プレビューは `previewOnly` で明示します。

```js
subscription: {
  normalize(input) { return { id: validatedTarget, label: displayName }; },
  async resolve(input) { return { id: validatedTarget, label: displayName }; },
  async targets() { return [{ id: joinedTarget, label: displayName }]; },
  async posts(target, { cursor }) {
    return {
      items: [{ id, title, text, date, url, locked, media: [
        { type: 'image', url, preview, previewOnly: false },
        { type: 'video', url, preview, format: 'mp4', headers: {} },
        { type: 'image', resource: { cacheKey, size } },
      ] }],
      cursor: nextCursor, hasNext: true,
    };
  },
  async mediaChunk(resource, offset) { return { base64, done }; },
}
```

直接 URL のない認証メディアは `media[].resource` に整数の `size` と安定した秘密情報を含まない `cacheKey` を指定します。期限付き参照や認証情報でキーを変えません。`subscription.mediaChunk(resource, offset)` は `{base64, done}` を返し、128 KiB 以下、整列オフセット、中間ブロックは完全長、添付は最大512 MiBです。ホストが総量とキャッシュパスを管理して原子的に保存し、使用中のファイルを保護します。バックアップ対象に署名 URL や resource は保存しません。

既存セッションは `account.type: 'session'` と秘密フィールドで受け取り、分割せずプラグインが検証します。ログインは実際の認証を確認し、保存で自動フォロー・参加しません。ネイティブ `bodyBase64` は最大2 MiB、body・ブラウザモードと併用不可、応答は base64 にできます。`digestBytes('sha1'|'sha256', bytes)` は最大2 MiBの整数バイト、`randomBytes(length)` は1–65536です。TLS、ドメイン分離、リダイレクト制限を維持し、任意のブラウザ通信・WebSocket・ファイルは許可しません。

[購読](../../SUBSCRIPTIONS.md)

subscription と feeds の両方を宣言するソースは通常カテゴリにも表示されます。feed/search の項目は presentation:'post'、text、date、url、media 配列で投稿カードを表示し、presentation:'media' はグリッドを使用します。mediaKind と coverAspect は各項目のメディアを表し、画像は順に閲覧できます。network.confirmation:{selector,readySelector,requiredCookies,message} は確認画面、本文の目印、必要 Cookie を宣言します。CONFIRM_REQUIRED 後は確認画面が消え、本文と Cookie が揃い、遷移が安定してから戻ります。利用者の代わりに確認しません。


## ゲーム

ゲームソースは `type:game`、`category:game`、`mediaKind:game` を宣言します。`gameResources(workId)` は安定 ID と `{id,kind:direct|external,label,size}` を返し、解決済み URL を含めません。`resolveGameResource(workId,resourceId,channelId)` はクリックや再試行時に `{kind,url,urls?,filename?,extractionCode,archivePassword}` を返します。直接転送は HTTPS の native `media` 許可ドメインが必要で、各リダイレクトを検査し Cookie を送りません。全ミラーと分割ファイルを保持します。ゲームには読書章や章更新を作成しません。一時 URL を保存・ログ記録しないでください。

GalgameX → KUN Galgame. [game-domain.md](../../game-domain.md)


## 次元茶館のゲームリソース

次元茶館は GalgameX、KUN の後に表示され、Galgame フォーラムの人気投稿を使います。アプリ内でログインし、解除ボタンを押すと「感谢分享，好人一生平安」を送信します。一覧と詳細は読み取り専用です。解除済みの投稿には再返信しません。送信結果が不明な場合はアカウントと投稿ごとに状態を保存し、再起動後も自動再送信せず、元の投稿で確認します。動的な認証はサイトで行います。元のクラウドリンク、リンクごとのコード、解凍パスワードを保持します。デスクトップのログインはアプリと別です。

`GameChannel`: `requiresReply: true`, `replyText`. `resolveGameResource`: `extractionCodes` aligned with `urls` (empty string: no code), or shared `extractionCode`. `CONFIRM_REQUIRED` → original post URL.
