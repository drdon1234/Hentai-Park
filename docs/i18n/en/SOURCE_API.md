[简体中文](../../SOURCE_API.md) · [繁體中文](../zh-Hant/SOURCE_API.md) · [日本語](../ja/SOURCE_API.md) · [한국어](../ko/SOURCE_API.md) · [English](SOURCE_API.md) · [Español](../es/SOURCE_API.md) · [Русский](../ru/SOURCE_API.md) · [العربية](../ar/SOURCE_API.md)

# Source plug-in development guide

Each origin of HentaiPark is a separate JavaScript file. Apps load them at runtime: they can be installed, updated, enabled/deactivated from the source repository without recompiling the app.
The built-in source is located at [`assets/sources/`](../../../assets/sources/) and can be used directly as an example reference.

## Running environment

- Source scripts run in a headless WebView within the App (full modern JS with `DOMParser`). The native layer provides cryptography, Cookie handling, and native HTTP requests. Native HTTP has no CORS restrictions; browser network and media requests follow the separate rules below.
- The same runtime ([`assets/runtime/park_runtime.js`](../../../assets/runtime/park_runtime.js)) can also be run in Node, and you can directly do smoke testing on the real site during development:

Install runner dependencies from the repository root, then create your own ignored `test/source-smoke.mjs` using the shared host below. It only loads a manifest; add actual feed/page 2/search/detail/cover decoding/chapter/media checks for the changed source. The Node host is a development aid, not a security sandbox for untrusted scripts.

```js
import { loadSource } from '../tools/source-runner/host.mjs';
const { manifest } = await loadSource('nhentai.js');
console.log(manifest.key, manifest.version);
```

```powershell
npm ci --prefix 'tools/source-runner'
node 'test/source-smoke.mjs'
```

## Register a source

```js
Park.register({
  key: 'mysite',              // Unique identifier, cannot be changed after installation
  name: 'Example Source',
  version: '0.0.1',           // When the version number in the warehouse is higher, the App will prompt for an update.
  type: 'comic',              // comic | video | novel | game
  category: 'doujin',         // doujin | anime | aiDrama | jav | adult | shortvideo | gallery | novel | game | other
  color: '#E5355F',           // Brand color: used for source entrance cards and source page theme colors
  description: 'Example source description',
  homepage: 'https://example.com',
  domains: ['example.com'],                   // For the site it belongs to, see "Isolation and Security"; if omitted, it will be deduced from the address such as homepage.
  linkPatterns: ['example\\.com/g/(\\d+)'],   // Used for direct access when pasting links in aggregate searches; the first group is the work ID
  idPattern: '^(\\d+)$',                      // Used for direct access when entering the number directly
  imageHeaders: { Referer: 'https://example.com/' },  // Carried by default when loading covers and pictures
  network: { mode: 'native', vpnHint: true },                // See the "Network" section
  media: { mode: 'browser', origin: 'https://example.com', domains: ['media.example.com'] },  // Optional HLS media permission; see below

  settings: [ /* option definitions */ ],
  account: { /* optional account */ },
  defaultFeed: 'ranking',                     // The label entered by default when opening the origin page (key in feeds)
  feeds: [ /* browse tabs */ ],
  searchFilters: [ /* search filters */ ],
  searchHint: 'Search by title or tag',

  async init() {},                            // Optional: Called once when loading (for example, refreshing the domain name list)
  async onSettingsChanged() {},               // Optional: Called after the user modifies the source settings

  async feed(key, { page, cursor, options }) {},
  async search({ keyword, page, cursor, filters }) {},
  async random() {},                          // Returns the work ID
  async detail(id, preview) {},
  async chapter(id, chapterId) {},            // comics
  async resolveImage({ id, chapterId, index, token, retry }) {},  // Optional: Delayed parsing of images
  async thumbnails(id, page) {},              // Optional: Load preview thumbnails in pages
  async videos(id, episodeId = '_') {},                        // video
});
```

`type` controls reading or playback; `category` groups sources on the home page, in source management and in search. Unknown or missing categories go under Other. Prefer recommendations, then rankings, then popular works for the default feed; use latest only if none are available.

AI short dramas use `category: 'aiDrama'`; the old `drama` identifier is not accepted. Site channel names are independent of the app category and keep their original names. The app category does not automatically filter site channels.

`adult` groups general adult video sites such as Pornhub, XVideos and 91porn, with `type: 'video'`. Dedicated JAV sites use `jav`. Categories group content and do not replace site tags or user filters.

Aggregate video sources still declare `type: 'video', category: 'adult'`. Omit `videos` when no media API is verified; the runtime exports `capabilities.videos: false`. The main detail action opens `detail.url` in the system browser, hides playback/download/episodes and skips synthetic chapter sync and updates while preserving favorites/history. Optional `detail(id, preview)` receives public displayed or stored metadata only when source and ID match; the source must revalidate the ID and URL. iXXX uses the upstream URL without known tracking parameters as its stable ID; TubeSafari keeps the upstream key. Neither requests external works with source cookies. Direct references without preview remain openable but may lack a title or cover. Thumbzilla statically parses MP4 metadata and restricts media domains.

`gallery` groups illustrations, cosplay and photo sets. Image sources keep `type: 'comic'`: one gallery maps to one work and `chapter()` returns its images in order, reusing reading, library and downloads. Classification does not depend on image count or explicitness.

Declare encrypted images with `imageDecrypt`. The framework decrypts before format validation and caching; the strategy is part of the cache identity, and failures are not cached. AES-CBC with strict PKCS#7 padding is supported. Encode `key` and `iv` as UTF-8 and limit the image domains; images on other domains remain unchanged.

```js
imageDecrypt: {
  type: 'aes-cbc',
  key: '0123456789abcdef', // UTF-8: 16, 24 or 32 bytes
  iv: '0123456789abcdef',  // UTF-8: 16 bytes
  domains: ['images.example.com'],
},
```

Network errors include safe `diagnostics` fields `host`, `transport` and `reason` to distinguish certificate, handshake, DNS, connection and timeout failures. Automatic logs record only allowlisted fields, never raw messages, credentials, request bodies or signed URLs.

`reason: 'TLS_HANDSHAKE_TERMINATED'` means only that the native `HandshakeException.message` exactly equals `Connection terminated during handshake`: the connection ended before the TLS handshake completed, not that certificate validation failed. Only HTTPS GET / HEAD requests without a body retry once for this exact error. Cancellation, certificate failures, other TLS errors, HTTP errors and response-stream errors do not retry. A repeated failure shows the host and suggests checking the VPN or proxy route; logs retain only safe diagnostic fields.

In the method, you can use `this` to access:

| Members | Description |
|------|------|
| `this.http` | `request(opts)`, `get(url, opts)`, `post(url, opts)`, `text(url, opts)`, `json(url, opts)` |
| `this.config` | The value selected by the user in the source settings (`default` if not set) |
| `this.store` | Persistent key-value storage: `get(key, fallback)` / `set(key, value)`, used to save Token, domain name list, etc.; `await flush()` confirms the disk writing is successful, and throws an error if it fails |
| `this.cookies` | `get(url)` / `set(url, {name: value})` / `clear(url)` |
| `this.log({code, host, transport, reason})` | Only allowlisted structured fields are retained; free text is discarded. |

Global tools:

| Tools | Instructions |
|------|------|
| `Park.html.parse(text)` | Return standard `Document`, you can use `querySelector` |
| `Park.html.text(node)` / `unescape(s)` / `strip(html)` | Text processing |
| `Park.crypto.md5Hex(text \| text[])` | MD5, you can pass arrays for batch calculation |
| `Park.crypto.sha256Hex` / `hmacSha256Hex(key, text)` / `aesEcbDecrypt(base64, key)` / `uuid()` | Native implementation, fast |
| `Park.utils.rateLimiter(ms)` | Returns `wait()`, ensuring the minimum interval between two requests |
| `Park.utils.mapLimit(items, n, fn)` / `lruMap(n)` / `parseCount('1.2万')` / `formatDate(ts)` | Other commonly used tools |
| `Park.error(code, message)` | Throws an error with error code, see below |

### `http.request(opts)`

```js
await this.http.request({
  url, method: 'GET', headers: {}, params: { q: 'x' },   // params will be concatenated into the URL
  json: {...} | form: {...} | body: 'raw',
  timeout: 15000,
  responseType: 'text' | 'base64',
});
// → { status, headers, body, url, ok, json() }
```

`text()` / `json()` automatically throw on non-2xx responses (404 → `NOT_FOUND`). Cookies are saved automatically and selected again for each redirect target. Cross-origin redirects do not carry the original authentication headers; cross-origin redirects that retain a request body are rejected.

## Data structure

**List page** (return value of `feed` / `search`)

```js
{
  items: [WorkItem], page: 1, totalPages: 20, total: 500,
  hasNext: true,
  cursor: '12345',        // Optional: Sites where the cursor turns pages (such as E-Hentai) return the next page cursor, and the App will return it as it is the next time it makes a request.
}
// Or return sections; the app selects the section layout from the response:
{ sections: [{ title: 'Latest chapters', items: [WorkItem] }], hasNext: false }
```

**WorkItem**: `{ id, title, subtitle?, cover, coverAspect?, pages?, rating?, likes?, views?, language?, category?, badge?, badgeColor?, duration?, uploaded?, tags? }`

- `coverAspect` (width / height) makes the grid layout before the image is loaded to avoid jumping.
- `badgeColor` The color used for category labels (e.g. E-Hentai the traditional color scheme for each category).

**Details** (`detail`): All fields of the WorkItem, additionally including:

```js
{
  url, authors: [], description, uploader?, size?, comments?,
  tags: [{ namespace: 'artist', label: 'Author', tags: [{ name, keyword, filters?, count? }] }],
  chapters: [{ id, title }] | null,   // null represents a single chapter
  singleChapterId?,                   // The chapter ID required for a single chapter work (such as "1" for Bika)
  thumbnails?: [url | {url, width, height, offsetX, offsetY}],   // Support sprite image
  related?: [WorkItem], series?: [WorkItem],
}
```

When a tag is clicked, the app searches for `keyword` and `filters` in the source, so the tag can be mapped to the site's native syntax (e.g. `artist:"xxx"`) or filter parameters (e.g. Hanime1 of `tags[]`).

**Chapter** (`chapter`)

```js
{ pages: [
  { url, headers?, fallbacks?: [url], width?, height?, transform? },  // Address is known
  { token: '12' },                                                      // Delayed resolution: App will call resolveImage
]}
```

- `fallbacks`: backup mirror, try in sequence when the primary address fails.
- `transform: { type: 'unscramble-strips', segments: N }`: When the image is cut into N strips horizontally and stored in reverse order (JMComic), the App will be restored natively on the GPU. The downloaded offline file saves the original image and restores it when displayed.
- `resolveImage` returns `{ url, headers?, width?, height?, cacheKey? }`. When it fails, the App will increment `retry` and call again, and the source can use this to change a server (`nl` parameter of E-Hentai).

**Video** (`videos`): `[{ quality: 1080, label: '1080P', url, headers?, format?, preferred? }]`. Video direct links usually have a time limit, and the App will re-obtain it every time before playing/downloading.

- Video sources return `[{id, title}]` in playback order through `detail(id).chapters`. Each `id` must be stable, never a quality label or temporary media URL. The host uses the same ID for selection, independent progress, downloads and resume, and calls `videos(id, episodeId = '_')` for that episode. Single videos use `singleChapterId`, or `'_'` when omitted.
- Omitting `format` keeps the direct MP4 playback and download path. HLS entries must explicitly return `format: 'hls'` and declare the `media` permission described below in the manifest.
- The host first expands an HLS master playlist (`#EXT-X-STREAM-INF`) into its separate variant playlists, obtains actual resolutions from `RESOLUTION`, and passes those variants to the player or downloader. For a master playlist, `quality` is the desired resolution: the highest available resolution not exceeding it is preferred, or the highest available resolution if none qualifies. Each variant must contain muxed audio and video in MPEG-TS. Separate `AUDIO`, `VIDEO`, or `SUBTITLES` renditions and URLs outside `media.domains` are rejected. Optional `#EXT-X-I-FRAME-STREAM-INF` trick-play tracks are ignored; their addresses are never registered or requested. When a single media playlist has no known resolution, provide `label: '原画'`; the label is translated by the UI language, and a requested quality must not be presented as the actual resolution.
- Expanded HLS variants support only complete, continuous MPEG-TS VOD playlists containing `#EXT-X-ENDLIST`. CBC/PKCS7 decryption supports `METHOD=AES-128` with `KEYFORMAT=identity` (also the default when omitted), exactly 16-byte keys, and either an explicit 128-bit IV or an IV derived from the segment media sequence. Keys stay in session memory; decrypted TS is validated through the same playback/download pipeline. Live streams, SAMPLE-AES, other KEYFORMAT values, `EXT-X-MAP`, `EXT-X-BYTERANGE`, fMP4, discontinuities and gaps remain unsupported. MissAV's nonstandard `#EXT-X-TOKEN` is removed.
- Playback uses a random port bound only to `127.0.0.1` and a random token, with a finite URL registry fetching validated segments on demand; closing the session cancels its requests. HLS offline downloads currently support Android only: each segment is validated, saved with a SHA-256 hash, and rechecked on resume, with cancellation support. Local Media3 remuxing produces MP4, and only a complete file is published to the offline library. HLS playback on iOS/macOS has not been verified in this round and must not be described as verified.

## Option definition

`feeds[].options`, `searchFilters`, `settings` use the same format:

```js
{ key: 'sort', label: 'Sort', type: 'select', default: 'date',
  values: [{ value: 'date', label: 'Latest' }, { value: 'popular', label: 'Popular', color: '#f00' }] }
// type: select (single choice) | multi (multiple choices) | number | text | password | switch
// In settings, options can be used instead of values.
```

Each item in `feeds` is a tab in the source page: `{ key, label, options?: [...] }`.

`defaultFeed` Specifies which tab to enter by default when opening the origin page. When the corresponding key is not filled in or cannot be found, the App will automatically select according to the key in the order of Recommendation > Ranking > Popular (key includes `promote` / `recommend` / `featured`, and then `rank` / `toplist`, then `popular` / `hot` / `trending`), if not, enter the first label.

## network

- `network.mode: 'native'` (default): Native HTTP request, using persistent cookies, can go through the proxy set by the user. If the Cloudflare query is detected, `CLOUDFLARE` will be thrown. The App will guide the user to complete the verification in the built-in browser and synchronize the common cookie back to the native request.
- `network.mode: 'browser'` + `network.origin`: The request was made with origin `fetch()` in a hidden browser page opened at `origin`, with a real browser fingerprint. Applies to Cloudflare sites that are more heavily protected (e.g. Hanime1). When a same-origin GET receives a Cloudflare challenge response, the hidden browser navigates to that document to perform automatic verification and retries the original request once. Failure still raises `CLOUDFLARE` and uses the existing verification flow.

## Media permissions (HLS)

`media` permission is separate from `this.http`, `network` and site Cookie synchronization. Both transports apply the same domain rules:

```js
domains: ['example.com'],
network: { mode: 'native' },
media: { mode: 'native', origin: 'https://example.com', domains: ['media.example.com'] },
```

- `media.mode` supports `'native'` and `'browser'`. Both require `media.origin` to belong to a source-declared site, use HTTPS on the default port 443, and contain no URL credentials, query or fragment.
- `media.domains` is an independent media allowlist including subdomains; it grants no source-site Cookie access. Playlists, segments and keys require HTTPS 443. URL credentials, fragments, IP addresses, localhost (including subdomains) and `.local` are rejected.
- `media.mode: 'native'` uses a separate credential-free native client, without site Cookies, Authorization or proxy authentication. Every redirect target is checked against the allowlist before following that hop. Only `Referer`, `Origin`, `Accept` and `Accept-Language` headers are allowed; the first two must match `media.origin`.
- `media.mode: 'browser'` opens a media session in a hidden browser at `media.origin` using `credentials: 'omit'`, `mode: 'cors'` and `redirect: 'error'`. It follows the CDN's CORS rules and does not follow redirects.
- Response sizes are limited during streaming and response URLs are checked again. Playlists are limited to 2 MiB, segments to 32 MiB, and AES-128 keys must be exactly 16 bytes. Oversized or empty responses and disallowed URLs are rejected. Source `domains` and Cookie-bearing `network` rules remain separate.

## Isolation and security

- Each source runs in an **independent** JS environment (each has an interfaceless WebView), and the sources cannot see each other's global objects; the native bridge only recognizes which environment the call comes from, and scripts cannot impersonate other sources.
- Each source has an independent cookie jar: the request issued by the source will only bring and save its own cookie, and will not read the login status of other sources.
- Secure Cookies are never sent over HTTP. Verification-page access and browser Cookie imports are checked against the installed source’s `domains`; available security attributes and expiry are preserved. Clearing a source’s Cookies or uninstalling it also closes the associated browser sessions and clears that site’s browser Cookies. The system shares browser site Cookies, so sources declaring the same site are affected by clearing that site.
- `domains` declares the site to which the source belongs (domain name can be registered, subdomain name is automatically included). Only cookies from these sites will be synchronized to the built-in browser (shared by Cloudflare authentication, web login), and `network.origin` in browser mode must also belong to them. When omitted, infer from `homepage`, `network.origin`, `account.cookieUrl/loginUrl`.
- When installing the source from a website or warehouse, the App will first read the script information in a sandbox that cannot be connected to the Internet, display the name, version, SHA-256, declared site and risk warning to the user, and then install it after confirmation. The `index.json` entry in the source warehouse can have the `sha256` field, and the installation will be refused if the download content does not match.

## Account

```js
account: {
  type: 'password' | 'cookies',
  title, hint, required: false,
  fields: [{ key: 'email', label: 'Email' }, { key: 'password', label: 'Password', secret: true }],
  loginUrl?, cookieUrl?, requiredCookies?: ['ipb_member_id'],   // After providing it, you can log in to the web page and the App will automatically obtain the cookie.
  async login(values) { return { name } },
  async logout() {},
  async status() { return { loggedIn, name, configured } },
  managedAccount: true,                 // Optional: Provide dedicated automatic maintenance account
  async enableManaged() {},             // Only called after the user confirms registration
}
```

`configured` indicates that the account has been configured, independent of whether the current login is successful. `managedAccount: true` declares that the source supports a dedicated automatic maintenance account; source settings use the `managedAccount` switch with the same name. The host must first display the auto-registration instructions and obtain user confirmation before saving the enablement settings and calling `account.enableManaged()`. Candidate credentials should be saved and `await this.store.flush()` used before registration to ensure that the same account can be restored after a failure or application restart.

PicACG example saves manual credentials and dedicated accounts separately, and existing manual accounts must not be overwritten by dedicated accounts. Turn off the switch to retain the dedicated account and turn it back on for reuse; if the Token expires, you can only log in again and do not register again. After registration fails or the response is lost, retry the original candidate account to avoid creating redundant accounts. Account password, token, and source status are all user local data. Do not output real credentials in documents and logs.

## Internationalization

Application interface support `zh-Hans`, `zh-Hant`, `ja`, `ko`, `en`, `es`, `ru`, `ar`. Material, Cupertino, and system controls use corresponding languages; the Arabic interface goes from right to left. The interface language setting takes effect immediately and is saved persistently. It follows the system by default; Chinese scripts and regions determine whether to use simplified or traditional Chinese.

The Flutter interface uniformly calls `tr('已选 {count}', {'count': count})`, or `context.tr`. The original Chinese text of the message is used as the resource key, the parameter is `{name}`, and the eight-language resource is located at `assets/i18n/`. When adding or modifying visible copy, all resources must be updated simultaneously and the placeholders must be consistent. The static name, description, browsing label, options and error prompts of the plug-in are resource mapped when the application is displayed; the title, author, tag, user input and persistence protocol key of the remote work remain the original text.

## Error code

Use `throw Park.error(code, message)` to throw an error, and the App will provide corresponding guidance based on the error code:

| code | App processing |
|------|-----------|
| `CLOUDFLARE` | "Go to verification" button: Open the built-in browser |
| `LOGIN_REQUIRED` | "Go to login" button: Open the account area of the source settings |
| `NOT_FOUND` | Display "Content does not exist" |
| `BLOCKED` | Displays "Access Restricted" (such as IP blocked, quota exhausted), the picture will not be retried |
| `NETWORK` / `HTTP` / `PARSE` | Display error message with "Retry" button |

## Source warehouse

A repository is a `index.json` that can be placed on static hosting (e.g. GitHub raw). Users can browse, install and update by entering the warehouse address in "Source Site Management → Add Source":

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

`url` is the full address of the script; you can also use `file` relative to `index.json`. The third-party warehouse is manually installed after user confirmation. `sha256` is optional. The downloaded content will be verified when provided.

Official updates adopt strict rules: the version must be a three-segment non-negative integer separated by dots and without leading zeros (for example, `0.0.1`, `0.1.0`), which is compared segment by segment by number; missing segments, multiple segments, or pre-release suffixes are not accepted. The original UTF-8 text of the script `sha256` must be provided without trimming whitespace or converting newlines; the `key` and `version` declared by the script must be consistent with the index. `apiVersion` must completely match the current App runtime. If it does not match, the update will be refused. You need to use an App that supports this API first; no compatible branch is provided.

### Official updates in the App

Official update checks read only the index at each launch. Checks on returning to the foreground retain a 12-hour interval, including failed attempts. Both automatic checks are enabled by default and can be disabled separately in settings; manual checks remain available. Only installed built-in and official sources are checked; third-party sources remain independent. Downloads and installation require explicit confirmation.

After confirmation, installation rechecks source identity, version, origin, API and SHA-256, and waits for initialization and state persistence. Failure restores the previous script and private data; interrupted installation is recovered at the next launch. Startup never replaces an installed plugin with a bundled script, even if its script is missing. Only new plugins receive their initial bundled script. Explicitly restoring a built-in source requires confirmation. On Android, confirmation downloads the matching official APK in the app. Size, SHA-256, package name, version and signing certificates are verified before opening the system installer, which still requires confirmation. If permission is needed, grant it and return to tap Continue installation. Progress, cancellation and retry are supported; the official release page is a fallback on failure. Other platforms use the official page for manual downloads.

### Release of official sources

The official source follows the public main warehouse [drdon1234/Hentai-Park](https://github.com/drdon1234/Hentai-Park), and the fixed entrance to the client is:

```text
https://raw.githubusercontent.com/drdon1234/Hentai-Park/sources/index.json
```

The source `key` allows only `[A-Za-z0-9_-]`, has a length of 1–100, and cannot use the reserved `_app`; the script filename must be `{key}.js`.

`assets/sources/index.json` is the only source list maintained, and `file` points to the only script source code in the same directory. The file name must conform to `[A-Za-z0-9_-]+.js`. Subdirectories, symbolic links, or dots in the body of the file name are not accepted and must be consistent with the client's official source address verification. `tools/publish_sources.mjs` Generate publishing index: each record contains `key`, `name`, `version`, `category` ,`description`, `url`, `sha256` and `apiVersion`. The script URL is fixed to the complete 40-digit commit number of this source code:

```text
https://raw.githubusercontent.com/drdon1234/Hentai-Park/<源码提交 SHA>/assets/sources/<file>
```

The `sources` branch only saves the generated root directory `index.json`, without copying the script or manually maintaining a second source list. When updating a script, the version in the script and the manifest must be upgraded at the same time; the publisher refuses to downgrade the version, and also refuses the same version to correspond to different script content. The same version can be published repeatedly with unchanged content, and normal upgrades will not be affected by the old index version.

The publisher relies only on the Node.js built-in module and can run offline in Node.js 22 or newer. It checks manifests, file existences, and directory boundaries, loads the shared runtime and scripts in a separate context that provides no network or storage interfaces, and checks using the same `Park.__pending` / `Park.manifest` probes as the App Install Preview `key`, `version` and API. The detection does not call `setup`, `init`, login or site business methods, and cannot replace the origin site network usability test.

Local preview example (the output is at `test/` which has been ignored and will not be published; the commit number should use the real SHA of the corresponding source code):

```powershell
node tools/publish_sources.mjs --commit '<完整 40 位源码提交 SHA>' --output 'test/official-source-index.json'
```

When you need to check for existing releases, pass in `--previous '旧索引本地路径'`. If the verification fails when the old index is invalid, version protection will not be silently skipped. When there are uncommitted modifications in the workspace, the local results are only used for preview; the official release is generated by submitting the source code checked out by the workflow.

`.github/workflows/publish-sources.yml` Only runs when the main repository default `main` branch related files are pushed, or triggered manually from `main`. The workflow is executed serially, and the latest `main` is checked out at the beginning of each task, and the script address and release record are fixed with the actual checked-out commit number. Subsequent document submissions while the task is running will not prevent publishing; subsequent source file submissions will trigger the next serial task. The workflow first downloads the existing stable index and completes all offline verification, and then uses ordinary Git to push the atomic update to the `sources` branch; the online index will not be overwritten when the verification fails or concurrent changes occur in the `sources` branch. A publication can be created for the first time without a stable index. The release only indicates that the script and index have passed the above verification. Site access, account login and image or video loading still need to be verified separately.


`type: 'video', category: 'shortvideo'` enables the full-screen vertical feed. Each work represents one short video; `videos(id, '_')` returns fresh media URLs. `feed` uses `hasNext` and `cursor` for automatic pagination; cursors must not contain credentials or signed media URLs. Only the current video plays, the next is preloaded while paused, and other players are cancelled and released. Omit `search` when no verified search interface exists.


Optional `imageNetwork: {mode: 'browser', origin: 'https://image.example.com', domains: ['image.example.com']}` declares a browser image CDN. The origin and every image domain must belong to source domains. Requests allow only HTTPS and approved headers, omit credentials, refuse redirects and limit each image to 20 MiB. Decryption, format checks, decoding and partitioned caching still apply. Tik.porn pages and API each use their own same-origin browser session; playback uses MP4, not fMP4 HLS or DASH.


## Novel reading

`type: 'novel', category: 'novel'` · `capabilities.textChapter: true`

Implement `textChapter(id, chapterId)` returning `{title?, paragraphs: [String]}` with nonempty plain text. Lists and details retain `mediaKind: 'novel'`, `language: 'zh'` or `'en'`; missing covers are empty strings. Merge internal pages of the same chapter, never replies, unrelated chapters or ads. Throw `LOGIN_REQUIRED` for truncated access previews. Chapters use stable IDs and site order, or `chapters: null` for a single story. `Park.html.paragraphs(node)` extracts text; downloads atomically write each chapter to `text.json`. Progress and annotations use original UTF-16 offsets. Bookmarks are separate from downloads and included in library backups.

`paragraphs.join('\n\n')` → UTF-16


## Subscription protocol

Declare both `subscription.normalize` and `subscription.posts` to expose `capabilities.subscription` in the independent Discovery subscription entry. Site logic stays in the plugin. `normalize` validates locally without login/network and accepts only the site’s usernames or controlled profile URLs. Optional `resolve` performs network resolution; optional `targets` lists joined targets and exports `subscription.joinedTargets: true`. Cursors are opaque strings; `hasNext: false` ends pagination and an empty page may still continue. `locked` means insufficient permissions; `previewOnly` must identify previews.

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

For authorized attachments without a direct URL, supply `media[].resource` with an integer `size` and a stable non-secret `cacheKey`, independent of expiring file references or credentials. Implement `subscription.mediaChunk(resource, offset)` returning `{base64, done}`: at most 128 KiB per chunk, aligned offsets, full intermediate chunks; maximum attachment 512 MiB. The host validates totals and writes atomically to its own cache; resources cannot choose paths. Cache usage counts toward the media limit and active files are protected. Targets in backups contain no signed URLs/resources.

Existing session imports use `account.type: 'session'` with a secret session field, validated by the plugin without splitting it into passwords/Cookies. Login success requires actual authorization. Saving subscriptions never follows/joins a service. Native binary requests use `bodyBase64` (at most 2 MiB), mutually exclusive with `body` and browser mode; responses can use `responseType: 'base64'`. `Park.crypto.digestBytes('sha1'|'sha256', bytes)` accepts at most 2 MiB of integer bytes; `randomBytes(length)` accepts 1–65536. TLS, domain isolation and redirect restrictions remain in force; plugins cannot open arbitrary browser network, WebSockets or files.

[Subscriptions](../../SUBSCRIPTIONS.md)

Sources declaring both subscription and feeds also appear in ordinary categories. Feed/search items may include presentation:'post', text, date, url and a media array for post cards; presentation:'media' uses a grid. mediaKind and coverAspect describe item media, and image collections support paging. network.confirmation:{selector,readySelector,requiredCookies,message} declares the gate, content marker and required cookies. After CONFIRM_REQUIRED, the browser returns only after the gate disappears, content is ready, cookies are stored and navigation is stable. The framework never confirms on the user's behalf.


## Games

Game sources declare `type:game`, `category:game` and `mediaKind:game`. `gameResources(workId)` returns stable resource metadata and channels `{id,kind:direct|external,label,size}` without resolved URLs. `resolveGameResource(workId,resourceId,channelId)` returns ephemeral `{kind,url,urls?,filename?,extractionCode,archivePassword}` on a user click or retry. Direct downloads require a native HTTPS `media` domain allowlist; redirects are checked at each hop and no source cookies are sent. Keep every external mirror or archive part. Game resources never become reader chapters or chapter updates. Temporary URLs must not be persisted or logged.

GalgameX → KUN Galgame. [game-domain.md](../../game-domain.md)


## Tea House game resources

Tea House follows GalgameX and KUN and uses the popular Galgame forum feed. Sign in inside the app. Clicking “Reply to unlock links” sends “感谢分享，好人一生平安”. Lists and details are read-only. Already unlocked posts are not replied to again. An uncertain submission is persisted by account and post and requires checking the original page; it is not automatically resent, including after restart. Dynamic verification requires the site page. Original cloud links, per-link extraction codes and archive passwords are preserved. Desktop browser sessions are separate from app sessions.

`GameChannel`: `requiresReply: true`, `replyText`. `resolveGameResource`: `extractionCodes` aligned with `urls` (empty string: no code), or shared `extractionCode`. `CONFIRM_REQUIRED` → original post URL.
