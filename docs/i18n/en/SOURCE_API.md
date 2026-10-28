[简体中文](../../SOURCE_API.md) · [繁體中文](../zh-Hant/SOURCE_API.md) · [日本語](../ja/SOURCE_API.md) · [한국어](../ko/SOURCE_API.md) · [English](SOURCE_API.md) · [Español](../es/SOURCE_API.md) · [Русский](../ru/SOURCE_API.md) · [العربية](../ar/SOURCE_API.md)

# Site plugin API

[Quick start](#quick-start) · [Manifest fields](#manifest-fields) · [Methods](#methods) · [Runtime API](#runtime-api) · [Error codes](#error-codes) · [Localization](#localization) · [Publishing](#publishing)

Every site in HentaiPark is a standalone JavaScript plugin. The app loads plugins at runtime; they can be installed from a repository, updated, enabled or disabled **without rebuilding the app**. The official plugins live in [`assets/sources/`](../../../assets/sources/) and make good examples.

The Simplified Chinese version of this document is authoritative. Site rules stay in the plugin; networking, caching and images are provided by the framework, which never special-cases a site by name.

## Quick start

### Runtime environment

- Plugins run in a headless WebView inside the app, with modern JS and `DOMParser`. The native layer provides crypto, cookies and native HTTP; native HTTP has no CORS restrictions, while browser networking and media follow their own rules below.
- A plugin's runtime starts the first time the site is used and is released after about 5 idle minutes, or when more than 6 are running. Manifests are cached by "script SHA-256 + runtime version", so launching the app doesn't run plugins. Don't assume a plugin is running as soon as the app starts.
- The same runtime ([`assets/runtime/park_runtime.js`](../../../assets/runtime/park_runtime.js)) also runs in Node, so you can smoke-test against real sites while developing. The Node host is a development tool, not a security sandbox for untrusted scripts.

### A minimal plugin

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

### Trying it in Node

Use a temporary ignored local validation script; verify the relevant source flows with real requests.

```js
import { loadSource } from '../tools/source-runner/host.mjs';
const { manifest } = await loadSource('nhentai.js');
console.log(manifest.key, manifest.version);
```

```powershell
npm ci --prefix 'tools/source-runner'
node <local-validation-script>
```

## Manifest fields

```js
Park.register({
  key: 'mysite',              // unique and permanent; only [A-Za-z0-9_-], 1–100 chars, not _app
  name: '我的站点',
  version: '0.0.1',
  minAppVersion: '0.9.2',           // three numbers; the app offers an update when the repository has a higher one
  type: 'comic',              // comic | video | novel | game: how works are read or played
  category: 'doujin',         // doujin | anime | aiDrama | jav | adult | shortvideo | recording | live | gallery | illustration | novel | game | other
  color: '#E5355F',           // brand color: site avatar and site page
  description: '一句话介绍',
  homepage: 'https://example.com',
  domains: ['example.com'],                   // sites it belongs to, see "Isolation and security"; derived from homepage etc. if omitted
  linkPatterns: ['example\\.com/g/(\\d+)'],   // pasted links open the work directly; group 1 is the work ID
  idPattern: '^(\\d+)$',                      // typed IDs open the work directly
  imageHeaders: { Referer: 'https://example.com/' },  // default headers for covers and images
  network: { mode: 'auto', vpnHint: true },  // see "Network"
  media: { mode: 'browser', origin: 'https://example.com', domains: ['media.example.com'] },  // media permission for video and direct files
  imageNetwork: { mode: 'browser', origin: 'https://img.example.com', domains: ['img.example.com'] }, // optional
  imageDecrypt: { /* optional, see "Encrypted images" */ },

  settings: [ /* options, see "Options" */ ],
  account: { /* optional, see "Accounts" */ },
  defaultFeed: 'ranking',     // tab opened by default on the site page (a key in feeds)
  feeds: [ /* site page tabs */ ],
  searchFilters: [ /* search filters */ ],
  searchHint: '搜索技巧提示',
  i18n: { /* the plugin's own UI translations, see "Localization" */ },

  subscription: { /* optional: follow channels/creators, see "Subscriptions" */ },
  postShortVideos: true,
  updateSubscriptions: { /* optional: update subscriptions, see "Update subscriptions" */ },

  async init() {},              // optional: called once when the runtime starts (e.g. refresh a domain list)
  async onSettingsChanged() {}, // optional: called after the user changes site settings
  // plus the methods in "Methods"
});
```

Capabilities are exported by the runtime from the methods a plugin implements; don't write them by hand.

### Type and category

`type` decides how works are read, played or treated as game resources; `category` decides where the site appears on Discover, in site management and in search. Unknown or missing categories go to "Other". New sites must declare their type, category and capabilities accurately.

| Category | Meaning |
| --- | --- |
| `doujin` | Doujinshi and comics |
| `gallery` | Photo galleries: cosplay, photography and real-person image sets. Image sites use `type: 'comic'`; one image set is one work, with ordered images from `chapter()` and shared reading, favorites and downloads. Image count and explicitness do not determine the category |
| `illustration` | Illustration galleries: drawn and anime images. Image sites use `type: 'comic'`; one image set is one work, with ordered images from `chapter()` and shared reading, favorites and downloads. Image count and explicitness do not determine the category |
| `anime` | Adult animation |
| `aiDrama` | AI short dramas. The old `drama` value isn't accepted; declare the site's own channel names as they are, the app category doesn't filter them |
| `jav` | Dedicated JAV sites |
| `adult` | General adult video (Pornhub, XVideos, 91porn…), `type: 'video'`. A category is a grouping; it doesn't replace site tags or user filters |
| `shortvideo` | Short videos: a full-screen vertical feed, see below |
| `recording` | Recorded video archives (video on demand), `type: 'video'` |
| `live` | Live streams, `type: 'video'` |
| `novel` | Novels, `type: 'novel'` |
| `game` | Games, `type: 'game'` |
| `other` | Creator communities |

- **Short videos** (`type: 'video', category: 'shortvideo'`): works, search, favorites and history open straight into the feed. Each work is one short video and `videos(id, '_')` returns its current media; no detail page is needed. `hasNext` and `cursor` from `feed` drive automatic paging near the end; cursors must not contain credentials or media signatures. Refreshing starts from page one; the current item plays, the next one is preloaded paused, the rest are released. Don't declare `search` if the site has none.
- **Post video mode** (`postShortVideos: true`): site and subscription-target pages can play each video attachment in `media[]` separately. A video needs a direct `url` or a non-empty `episodeId`; lazy resolution calls `videos(originalPostId, episodeId)` on playback or preloading, never a web page as a media URL. Images stay out of the player. Attachments support `preview`, `format` and `headers`. Paging and refresh preserve the current feed/options or the target’s `subscription.posts` scope. Playback identifies each attachment separately; favorites, history and site interactions use the original post ID. This capability changes neither the category nor the site’s API.
- **Aggregators that can only play on the original site**: still declare `type: 'video', category: 'adult'`; without a verified media API, don't implement `videos`, and the runtime exports `capabilities.videos: false`. The detail page's main button then opens `detail.url` in the system browser, playback, downloads and episodes are hidden, no fake chapters are stored and no chapter updates are checked; favorites and history still work.
- **Novels** and **games** are covered under "Methods".

Choose `defaultFeed` in the order **recommended > rankings > popular**; use the latest page or another valid entry only if the site really has none of these, and never fake an unverified API. If it's missing or unknown, the app picks by key (first `promote` / `recommend` / `featured`, then `rank` / `toplist`, then `popular` / `hot` / `trending`), falling back to the first tab.

Sources that allow anonymous access but require login for recommendations declare `anonymousDefaultFeed: 'ranking'`. It must reference a verified anonymously accessible entry in `feeds`, preferably rankings. The home and source pages use it when logged out and `defaultFeed` when logged in; an explicitly selected tab is preserved. Do not treat every empty list or network failure as an anonymous session.

### Options

`feeds[].options`, `searchFilters` and `settings` share one format:

```js
{ key: 'sort', label: '排序', type: 'select', default: 'date',
  values: [{ value: 'date', label: '最新' }, { value: 'popular', label: '热门', color: '#f00' }] }
// type: select | multi | number | text | password | switch
// settings may use options instead of values
```

Each `feeds` entry is a tab on the site page: `{ key, label, options?: [...] }`.

### Common filters and sorting

Plugins declare `commonFilters` per feed and `searchCommonFilters` for search. The app only shows declared operations and never approximates filtering from already loaded work fields. Plugins must map these values to real site queries and preserve them across pages.

```js
feeds: [{ key: 'latest', label: 'Latest', commonFilters: {
  pages: { range: ['min'], sort: ['asc', 'desc'] },
  likes: { range: true, sort: ['desc'] },
  duration: { range: ['min', 'max'] },
} }],
searchCommonFilters: { pages: { range: ['min', 'max'] } },
```

Dimensions are `pages`, `likes` and `duration`. `range: true` enables both `min` and `max`; an array can declare only supported bounds. `sort: true` enables `asc` and `desc`; an array lists the directions the site supports. Pages and likes use non-negative integers; duration is in seconds. The `feed` or `search` request object receives a separate `common` map, for example `{ pages: { min: 10, order: 'desc' } }`. Empty bounds and ordering are omitted, either range bound may be left blank, and at most one dimension may be sorted at a time. Declare capabilities only where the site supports them; undeclared dimensions must be rejected.

### Dynamic and cascading filters

Select options in `feeds[].options` and `searchFilters` may declare `dynamic: true, values: []`. A dynamic child references parents in the same group with `dependsOn: ['range']`. Keys must be unique; dependencies must exist and be acyclic. Only dynamic options may declare dependencies.

`filterOptions(request)` returns a choice array. Requests contain `scope: 'feed' | 'search'`, `filter` and `values`; feed requests also include `feed`, and search requests may include `keyword`. `values` contains only declared direct parents, never account data, settings or unrelated filters. Children do not load while a parent is unselected or empty.

Declare `keywordDependent: true` when search choices depend on the keyword. Changing the keyword resets that option and its descendants while preserving other filters. Parent values in `values` must be strings, numbers or booleans, not multi-select arrays. Remote labels are not fixed UI copy; content and tag translation remain available.

Return at most 500 entries shaped as `{value, label, color?}`. Values are unique strings or finite numbers. Labels are nonempty original-site names without control characters and at most 256 characters; colors use six hexadecimal digits. Group large catalogs into cascading choices instead of silently truncating them. Remote choice labels are not automatically translated.

Selections reach `feed` through `options` and `search` through `filters`. Plugins must validate actual catalog membership and preserve filters across pagination; catalog parsing failures must throw errors. The app caches choices for two minutes by source, feed/search scope, feed or keyword, and parent values. Parent changes clear descendants and discard stale responses; failed loads can be retried.

Each domain plugin reads only its own catalog. Related domains must not call each other’s plugins or share cookies. Reuse parsing templates at build time and generate self-contained scripts. Run `node tools/build_catalog_sources.mjs` to generate navigation catalogs and `--check` to verify consistency.

```js
{key: 'category', label: '分类', type: 'select', default: '',
 dynamic: true, dependsOn: ['range'], values: []}

async filterOptions({scope, feed, filter, keyword, values}) {
  return [{value: 'site-category-id', label: 'Site category'}];
}
```

### Network

- `network.mode: 'auto'` (default): try native HTTP first. For same-origin HTTPS GET/HEAD requests without a body, Cloudflare challenges, HTTP 403, 429, or recoverable connection errors trigger one browser retry. DNS, TLS, timeout, response-stream, and ordinary 5xx failures do not open the browser, avoiding extra latency. The target must be within the source's declared domains, and browser fallback keeps the same-origin and redirect restrictions.
- `network.mode: 'native'`: Force native HTTP with persistent cookies and the configured proxy. A detected Cloudflare challenge returns `CLOUDFLARE` for in-app retry; when the error includes a site verification URL, the user can choose to open its confirmation page.
- `network.mode: 'browser'` + `network.origin`: Send same-origin `fetch()` from a hidden page at `origin`. Read-only requests encountering Cloudflare (including HTTP 200 challenge pages), or an age gate without required cookies/content, navigate for verification at most once before reading again; writes are never replayed. Age gates follow `network.confirmation`. Android and Windows send browser input to one standard Cloudflare checkbox; other platforms wait for automatic site checks. Failures offer in-app retry or a confirmation action when a site verification URL is provided.

  Documents may navigate within declared domains with the same scheme and port. Unless explicitly supplied, request `origin` comes from the target site URL. Responses preserve the final `url`.

  Automatic fallback excludes `followRedirects: false`, `connectAddress`, and unclassified network errors. Browser GET/HEAD requests without a body make at most three ordinary attempts, plus at most one extra read after verification, recovering only connection failures or HTTP 408, 500, 502, 503, and 504; 429 and timeouts are not replayed. Each logical request allows at most one verification navigation across all attempts. Startup, requests, document reads, and disposal have bounded waits. Reads with custom API headers use actual `fetch()` rather than a navigation result. Reused HTML preserves its error status; `responseType: 'base64'` returns base64 of the original bytes.

- `network.vpnHint: true`: declare it for sites that may need a VPN or proxy in mainland China; waits over 8 seconds and failures then mention "may need a VPN or proxy". Don't blame every error on the VPN.
- `network.confirmation: { selector, readySelector, requiredCookies, auto: { clickSelector }, message }`: Declares a site age gate. `selector` matches the dialog, `auto.clickSelector` its unique confirmation button, `readySelector` accessible content, and `requiredCookies` the cookie names required after confirmation. Only after the user confirms adulthood at the app entrance does the hidden browser simulate a click, then check that the gate disappears, content appears, cookies exist and navigation settles. Incomplete or unmatched rules and failed automatic confirmation allow retry. When the error provides a site verification URL, users can open it, handle the page manually and explicitly tap Done. Source-domain and cookie-partition restrictions still apply; operation notifications never replay the original action automatically. This declaration is only for age gates, not login, payment or posting.
- Network errors carry safe `diagnostics` fields `host`, `transport` and `reason`, distinguishing TLS certificates, handshakes, DNS, connections and timeouts; automatic logs record only these allowed fields. `reason: 'TLS_HANDSHAKE_TERMINATED'` only means the native `HandshakeException.message` is exactly `Connection terminated during handshake` (the connection dropped before the handshake completed, not a certificate failure); only HTTPS GET/HEAD requests without a body retry once on it, and nothing else is retried.

### Images

- `imageNetwork: { mode: 'browser', origin, domains }`: Image domains and subdomains are independent of site cookie permissions. `origin` may belong to a site or image domain. Requests use HTTPS 443 and allowed headers, reuse the browser site session for same-origin images when origin belongs to a declared site domain; cross-origin images, external image origins and video requests omit credentials, and allow redirects between authorized image domains. The 20 MiB limit, decryption, format checks, decoding and per-site cache remain. Without this declaration, native image transport is used. Browser redirect support depends on the platform; see media permissions.
- **Encrypted images**: declare `imageDecrypt` and the framework decrypts before the format check and caching; the decryption settings are part of the cache identity and failures aren't cached. AES-CBC with strict PKCS#7 padding is supported, with `key` and `iv` encoded as UTF-8; image domains must be listed, other domains use the normal path.

```js
imageDecrypt: {
  type: 'aes-cbc',
  key: '0123456789abcdef', // 16, 24 or 32 UTF-8 bytes
  iv: '0123456789abcdef',  // 16 UTF-8 bytes
  domains: ['images.example.com'],
},
```

A cover returning HTTP 200 isn't enough — verify that it decodes.

### Media permission (HLS and direct files)

The `media` permission is independent of `this.http`, `network` and site cookies:

Every plugin implementing `videos()` must declare valid `media` permissions, including MP4-only plugins. `scope: 'session'` may coexist with static `domains`: HLS uses exact URLs authorized for the session, while direct MP4 must match the static domain list. Official publishing rejects missing or invalid media declarations.

```js
domains: ['example.com'],
network: { mode: 'native' },
media: { mode: 'native', origin: 'https://example.com', domains: ['media.example.com'] },
```

- `media.mode` is `'native'` or `'browser'`. `media.origin` must belong to the plugin's sites, use HTTPS on the default port 443, and contain no credentials, query or fragment.
- `media.domains` is a separate allow-list for media (subdomains included) that grants no site cookie access. Playlists, segments and keys must be HTTPS on 443; URL credentials, fragments, IPs, localhost (and subdomains) and `.local` are rejected.
- `'native'`: Uses a separate client without site cookies, Authorization or proxy credentials, checking each redirect before connecting. Allowed headers are `Referer`, `Origin`, `Accept`, `Accept-Language`; the first two must belong to declared site domains, including language subdomains. `Origin` contains only an origin.
- Optional `media.referrerDomains` is limited to native video media and at most 16 valid public domains (including subdomains). It explicitly extends only the allowed `Referer` origins beyond the site domains above. It grants no extra `Origin`, media URL, document navigation or cookie permissions, and is invalid for `imageNetwork` or browser media.
- `'browser'`: Opens a hidden session at `media.origin` with document navigation inside declared site domains. Uses `credentials: 'omit'` and `mode: 'cors'`; the real document and browser generate Origin/Referer. On Windows, WebView2 checks the resource domain before each connection, permits redirects between authorized domains and validates the final URL. Other engines lack per-hop interception and use `redirect: 'error'`. CORS and the site CSP still apply; final-URL checks alone do not authorize redirects.
- Responses are size-limited while streaming and their final address is re-checked: playlists up to 2 MiB, segments up to 32 MiB, AES-128 keys exactly 16 bytes. Oversized or empty responses and disallowed addresses are rejected.

- Dynamic HLS CDNs may declare `media.scope: 'session'` with `mode: 'native'`. Authorization covers only URLs, playlist resources and allowed redirects resolved for the current playback or download session, and expires when it closes. It grants no extra cookie access or persistent domain permissions. HTTPS, credential-free requests, destination and response-size restrictions still apply; direct MP4 and browser media keep static domain allow-lists.

### Isolation and security

- Each plugin runs in its **own** JS environment (its own headless WebView), so plugins can't see each other's globals; the native bridge knows which environment called it, so a script can't impersonate another plugin.
- Each plugin has its **own cookie jar**: its requests carry and store only its own cookies.
- Secure cookies are never sent over HTTP. Opening verification pages and importing browser cookies are checked against the installed plugin's `domains`, keeping available security attributes and expiry. Clearing a site's cookies or uninstalling also closes its browser session and clears that site's browser cookies; browser cookies are shared by the system, so plugins declaring the same site are affected by that clean-up.
- `domains` declares which sites a plugin belongs to (registrable domains, subdomains included). Only these sites' cookies sync with the built-in browser (shared by Cloudflare verification and web sign-in), and `network.origin` in browser mode must belong to them. If omitted, they're derived from `homepage`, `network.origin` and `account.cookieUrl/loginUrl`.
- Cross-origin redirects drop the original origin's auth headers; cross-origin redirects that keep a request body are refused. TLS certificate validation is always on.
- When installing from a URL or repository, the app first reads the script in an offline sandbox and shows the name, version, SHA-256, declared sites and risks; nothing is installed until the user confirms.

### Accounts

```js
account: {
  type: 'password' | 'cookies' | 'session',
  title, hint, required: false,
  fields: [{ key: 'email', label: '邮箱' }, { key: 'password', label: '密码', secret: true }],
  loginUrl?, cookieUrl?, requiredCookies?: ['session_id'],   // enables web sign-in; the app collects the cookies
  loginDomains?: ['accounts.google.com', 'appleid.apple.com'],  // third-party sign-in domains, used only for sign-in navigation
  localStorageKeys?: ['session_key'],  // explicitly allowlisted localStorage keys, read only from the cookieUrl origin and passed to login(values); never log their values
  async login(values) { return { name } },
  async logout() {},
  async status() { return { loggedIn, name, configured } },
  managedAccount: true,                 // optional: offers an automatically managed account
  async enableManaged() {},             // only called after the user agrees to registration
}
```

On sign-out, the app removes only the localStorage keys declared by the site from the cookieUrl origin; other local storage is preserved. Empty-list diagnostics use fixed reasons: UPSTREAM_EMPTY (empty upstream list), NO_VIDEO (no video selected), EMPTY_RESULT (no loaded content), CONTENT_FILTERED (hidden by display rules), and SEARCH_ONLY (recommendations skipped in data-saving mode). Successful pages are not logged individually; only empty-state changes and recovery are logged. Never include titles, search terms, content IDs, sessions or media URLs in logs.

- Account status is refreshed only on first use, after sign-in, sign-out and web sign-in, and when the last check is older than 10 minutes — not after every call. `configured` means an account is set up, whether or not sign-in currently works.
- `loginDomains`: third-party sign-in domains the site actually uses (subdomains included). They're allowed only while the user has the web sign-in page open, HTTPS on 443 only; URL credentials, IPs, localhost and `.local` are refused. Verification pages, access confirmation, plugin requests and cookie import are still checked against `domains`; don't add sign-in domains to `domains` to widen access. The sign-in page supports same-window redirects and pop-ups that keep `window.opener`, with the same checks in pop-ups; a blank initial page grants no external navigation. Sign-in isn't considered complete while on a third-party page; cookies sync once back on the site. Third-party cookies aren't imported into the plugin's jar or cleared with the site's cookies; the system WebView manages them. Third parties may still restrict sign-in in embedded browsers.
- `type: 'session'` imports an existing authorized session: declare one secret field (such as `session`); the clipboard content is kept whole and validated by the plugin rather than split into username, password or cookies. Sign-in must really confirm authorization — never report success from the input's format alone.
- `managedAccount: true` and `account.enableManaged()` provide optional account management, enabled only after informed user confirmation. Store manual and managed accounts separately without overwriting existing credentials. Account data stays on the device and must not appear in documentation, diagnostics or release artifacts.
- Passwords, tokens and plugin state are the user's local data; never put real credentials in documents or logs.

## Methods

`this` inside methods is described in "Runtime API". All methods may be `async`.

```js
async feed(key, { page, cursor, options, common }) {} // site page tabs
async search({ keyword, page, cursor, filters, common }) {}
async random() {}                                  // returns a work ID
async detail(id, preview) {}
async chapter(id, chapterId) {}                    // comics, galleries
async resolveImage({ id, chapterId, index, token, retry }) {}  // optional: lazy image resolution
async thumbnails(id, page) {}                      // optional: paged preview thumbnails
async videos(id, episodeId = '_') {}               // video
async textChapter(id, chapterId) {}                // novels
async gameResources(workId) {}                     // games
async resolveGameResource(workId, resourceId, channelId) {}
```

### Lists: `feed` / `search`

```js
{
  items: [WorkItem], page: 1, totalPages: 20, total: 500,
  hasNext: true,
  cursor: '12345',        // optional: cursor-paged sites return the next cursor, passed back as is
}
// or sections, shown as a sectioned layout:
{ sections: [{ title: '连载更新', items: [WorkItem] }], hasNext: false }
```

**WorkItem**: `{ id, title, subtitle?, cover, coverBlurred?, coverAspect?, pages?, rating?, likes?, views?, language?, category?, badge?, badgeColor?, duration?, uploaded?, tags?, mediaKind?, workCode?, editions?, commentsAvailable? }`

- `workCode` is a work code confirmed by the source, used only to find the same work. It never replaces `id` or merges identities, favorites, progress, or downloads.
- `editions` contains explicit, fixed edition labels from the source, such as Chinese subtitles or an uncensored leak. Missing labels must not imply an original edition. Translated display text does not change stored labels.

- `coverAspect` (width / height) lets the grid lay out before images load.
- `badgeColor` colors the category badge.
- `mediaKind: 'comic' | 'video' | 'novel' | 'game'` is the work's own type. Plugins with a single type may omit it; mixed-type plugins must set it — never treat images as videos just because of the plugin's `type`. Novel and game works always set it, so offline works and history still open in the right reader after the plugin is uninstalled.
- Post-style results may include `presentation: 'post'`, `text`, `date`, `url` and a `media` array to show as post cards; `presentation: 'media'` shows a media grid that opens the media inside the work. Posts may have no media; media URLs remain subject to the plugin's declared domains and permissions.

### Details: `detail`

All WorkItem fields, plus:

```js
{
  url, authors: [], description, uploader?, size?, comments?, commentsAvailable?,
  tags: [{ namespace: 'artist', label: '作者', tags: [{ name, keyword, filters?, count? }] }],
  chapters: [{ id, title }] | null,   // null means a single chapter
  singleChapterId?,                   // chapter ID needed by single-chapter works
  thumbnails?: [url | { url, width, height, offsetX, offsetY }],   // sprite sheets supported
  related?: [WorkItem], series?: [WorkItem], variants?: [WorkItem],
}
```

- `variants` contains only actual links supplied by the source to editions of the same work on that source, each with its own `id`; never guess URLs. Find editions on other sources with `workCode`; favorites, progress, and downloads stay independent.

- Tapping a tag searches this site with `keyword` and `filters`, so tags can map to the site's own syntax (such as `artist:"xxx"`) or filter parameters.
- The optional second argument `preview` carries public metadata already shown or stored, passed only when `preview.source` and `preview.id` match the request. The plugin must still check the ID and validate URLs. Works opened by typed ID have no preview, so title and cover may be incomplete.

### Chapters: `chapter` / `resolveImage` / `thumbnails`

```js
{ pages: [
  { url, headers?, fallbacks?: [url], width?, height?, transform? },  // known URL
  { token: '12' },                                                      // lazy: the app calls resolveImage
]}
```

- `fallbacks`: mirrors tried in order when the main URL fails.
- `transform: { type: 'unscramble-strips', segments: N }`: for images cut into N strips stored in reverse, restored on the GPU. Offline files keep the original image and are restored on display.
- `resolveImage` returns `{ url, headers?, width?, height?, cacheKey? }`. On failure the app calls it again with a higher `retry`, letting the plugin switch servers.
- `thumbnails(id, page)` returns `{ thumbnails: [...], hasNext }`.

### Video: `videos`

Returns `[{ quality: 1080, label: '1080P', url, headers?, format?, preferred?, hls? }]`. Direct links usually expire, so the app fetches them again before every playback or download.

- `format: 'hls'` may include `hls: {manifest, keys}`: `url` is the real HTTPS base of the variant playlist; `manifest` is a prepared complete VOD media playlist (at most 2 MiB UTF-8); `keys` maps referenced absolute key URLs to Base64-encoded 16-byte keys, up to 32 entries. Native media only. Existing address authorization and content validation still apply; unreferenced keys are rejected. Results containing this field are never cached to disk; keys stay in session memory and must not enter store, logs, works or cursors.

- Multi-episode videos return `[{ id, title }]` in play order from `detail(id).chapters`; each `id` must be stable, never a quality or temporary media URL. The app uses the same ID to pick episodes, store progress, download and resume, and calls `videos(id, episodeId)` for each episode. Single videos use `singleChapterId`, or `'_'` if absent.
- Without `format`, playback and download treat the link as direct MP4. HLS must return `format: 'hls'` and declare the `media` permission.
- An HLS master playlist (`#EXT-X-STREAM-INF`) is expanded by the app into per-variant playlists, with real quality taken from `RESOLUTION`. When you return a master playlist, `quality` is the desired quality: the highest real quality not above it is chosen, or the highest available. Each variant must be muxed audio/video MPEG-TS or VOD fMP4; separate `AUDIO`, `VIDEO`, `SUBTITLES` renditions and addresses outside `media.domains` are rejected. `#EXT-X-I-FRAME-STREAM-INF` tracks are ignored. If a single playlist has no known resolution, use `label: '原画'` rather than presenting the desired quality as real. Without `RESOLUTION`, a master variant needs valid `BANDWIDTH`; variants are labeled in kbps, with the highest bitrate preferred, without inventing a resolution.
- `type: 'video', category: 'live'` identifies public live streams in 3D, with image-only home and domain cards. `videos()` returns the current public room's HLS; never fabricate playable results for private, paid or offline rooms. Playback uses rolling playlists without VOD resume positions or downloads. Recording requires an explicit user action and saves only segments newer than the initial live window. It ends on stop or app exit and never resumes after restart. An independent media session and background task validate and decrypt each segment and commit a complete local playlist. Reconnection resolves fresh media; encoding boundaries and long recordings may start new parts. Previously committed content survives failure. Only muxed MPEG-TS is supported; MAP/fMP4, low-latency PART, BYTERANGE and GAP are unsupported.
- VOD requires a complete, continuous MPEG-TS or fMP4 playlist with `#EXT-X-ENDLIST`. fMP4 accepts one `#EXT-X-MAP` initialization segment before media segments; changing initialization segments and byte ranges are unsupported. Initialization and media segments are authorized, validated and rewritten locally; offline playback and export retain the initialization segment. Live streams still require MPEG-TS and accept rolling playlists and discontinuities. Both decrypt `METHOD=AES-128`, `KEYFORMAT=identity` with CBC/PKCS7 and exactly 16-byte keys. Media IVs are explicit or sequence-derived; encrypted initialization segments require an explicit IV. Keys stay in session memory. SAMPLE-AES, other KEYFORMATs, BYTERANGE and GAP are unsupported; VOD also rejects discontinuities. Non-standard `#EXT-X-TOKEN` tags are removed.
- HLS playlists and MPEG-TS segments support PNG `roUd` wrapping (raw or zlib-compressed). Unwrapping precedes parsing, validation or decryption, with decoded limits of 2 MiB per playlist and 32 MiB per segment. Plugins still return `format: 'hls'`; no extra permissions are required.
- Playback uses a random port bound to `127.0.0.1` and a random token, serving verified segments on demand from a limited URL registry; closing the session cancels requests. HLS offline downloads are Android-only for now: each segment is verified and its SHA-256 saved, downloads can resume and be cancelled, and MPEG-TS is finally muxed with Media3 while fMP4 retains its initialization and media segments in order — only complete files reach the offline library.

### Novels: `textChapter`

Novel plugins declare `type: 'novel', category: 'novel'`; implementing `textChapter` exports `capabilities.textChapter: true`. Lists and details set `mediaKind: 'novel'` and `language: 'zh'` or `'en'`. Without a real cover, return `cover: ''` and the app shows a text cover instead of requesting a fake image.

```js
async textChapter(id, chapterId) {
  // The full text of the chapter; paragraphs must be non-empty strings without HTML.
  return { title: '章节标题', paragraphs: ['第一段正文。', '第二段正文。'] };
}
```

- Multi-chapter novels return stable IDs in the site's confirmed reading order in `detail.chapters`; single stories use `chapters: null` and optionally `singleChapterId`.
- In-chapter pagination is merged in order by the plugin; never merge the next chapter, forum replies, ads or recommendations into the text. `Park.html.paragraphs(node)` extracts plain text generically; site boundaries and pagination are still the plugin's job.
- Text cut short by sign-in, payment or permissions throws `LOGIN_REQUIRED`; never present a preview as a complete chapter.
- The app writes `text.json` atomically per chapter; a download counts as complete only when fully written. Reading progress and notes use UTF-16 offsets into `paragraphs.join('\n\n')`; font size, typeface, indentation and other layout settings only affect display. Bookmarks and notes live apart from downloads, are included in backups, and survive deleting a download.

### Games: `gameResources` / `resolveGameResource`

Game plugins declare `type: 'game', category: 'game'`; works set `mediaKind: 'game'` and have no fake `chapters`. The runtime exports `capabilities.gameResources` and `capabilities.resolveGameResource` from the methods.

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
  // Cloud drives return kind: 'external', urls: [all mirrors/parts], url: urls[0].
}
```

- `gameResources` returns only stable IDs, metadata and channels — no signed URLs, passwords or fake download states. `testStatus` is `tested | untested | unknown`, copied from the site; channels with `status: 'expired'` are disabled.
- `resolveGameResource` is called only when the user taps or retries; its URL is never persisted or logged. Passwords may be saved with the local download task but never in diagnostics. Don't drop cloud-drive links; when returning several, `extractionCodes` can match `urls` one to one (empty string means none), and `extractionCode` is for a shared code.
- Channels that require a reply declare `requiresReply: true, replyText: 'the actual reply'`; the app shows "Reply to unlock links" and the exact text, and calls only after the user confirms. Before resolving, the plugin must re-check the first post: if already unlocked it only reads; it submits once and only on the user's tap, saving account/thread state reliably before sending. When the result is unclear, on repeated attempts or when dynamic verification is needed, return `CONFIRM_REQUIRED` with the thread URL and never resend automatically; never reply from lists, details, prefetching or background updates.
- Direct links must declare `media: { mode: 'native', origin, domains }`. Files are streamed by a separate cookie-less client; the framework handles HTTPS, per-hop domain checks, length checks, cleanup on cancel and protection of finished files. There's no resume; retrying resolves the address again and restarts. Cloud drives open in external apps, limited to HTTP(S), FTP(S), magnet, ed2k and thunder, without site cookies. Games create no chapters, reading progress or chapter updates, and the app never installs, extracts or runs files.

### Subscriptions: `subscription`

Subscription plugins (following channels or creators) declare a `subscription` object; the runtime exports `capabilities.subscription` when both `normalize` and `posts` exist, and the site appears under Discover → Subscriptions. Plugins that also declare `feeds` appear in the normal categories too.

```js
subscription: {
  hint: '无需登录即可保存订阅；媒体访问取决于原站权限。',
  normalize(input) { return { id: validatedTarget, label: displayName }; },
  async resolve(input) { return { id: validatedTarget, label: displayName }; },
  async targets() { return [{ id: joinedChannelId, label: channelName }]; },
  async posts(target, { cursor }) {
    return { items: [{ id, title, text, date, url, locked, commentsAvailable,
      media: [{ type: 'image', url, preview, previewOnly: false },
              { type: 'video', url, preview, format: 'mp4', headers: {} }] }],
      cursor: nextCursor, hasNext: true };
  },
  async mediaChunk(resource, offset) { return { base64, done }; }, // optional
}
```

- `normalize` must validate locally only, so targets can be saved signed out or offline; accept only usernames or controlled profile URLs of this site. `resolve` and `targets` are optional; with `targets`, the manifest outputs `subscription.joinedTargets: true`.
- For a separate community entry, declare `communities: true`, `communityHint` and `communityExample`; the runtime exports this metadata unchanged. Targets return `{ id, label, kind: 'community' }` with IDs distinct from creator targets. `targets({ kind: 'community' })` lists joined communities; `targets()` lists default targets. Handle them independently so a community API failure does not break creator lists. `resolve` may check names and access read-only; it must not automatically join.
- `posts` cursors are opaque strings; the last page has `hasNext: false`, and pages without media may still continue. `locked` means insufficient permission; `previewOnly` marks public previews — never pass a thumbnail off as the full content.

### Public albums: `subscription.media`

Albums are an independent capability, never assembled from already loaded posts and never falling back to `subscription.posts`. Implement `subscription.media(scope, { page, cursor })`; a source with public feeds but no subscribable targets may expose only this method under `subscription`. The runtime exports `capabilities.album` independently of `capabilities.subscription`.

`scope` is either `{ feed, options }` or `{ target }` / `{ search: { keyword, filters } }`, for a feed with its filters or a user, community, channel or group. The source resolves and traverses targets without site-specific conditions in the UI. Return `{ items, cursor, hasNext }`; a page without matching media may still continue, and every continuation cursor must advance. Repeated cursors are errors.

Each item has a stable string `id`, `presentation: 'post' | 'work'`, a parseable ISO 8601 date when known, and the complete `media` array in site order. Every attachment has a unique stable string `id`, `type: 'image' | 'video'` and an actual content `url` or controlled `resource`. `preview` is an image thumbnail; alternatively `previewResource` uses the controlled attachment format below, limited to 2 MiB and pointing to a separate image. Covers and video URLs must not impersonate thumbnails. Restricted content exposes only public previews marked `previewOnly: true`, retaining the site's blur and `locked: true` when the whole post is locked.

The source completes media across pages and merges site media groups. The client merges repeated works by attachment `id`; optional finite numeric `order` restores ordering only when supplied for every attachment of a work. Filtering uses inclusive local dates and image/video types; unknown dates are excluded when a date range is set. Collapsing a post changes display only. After a bounded number of empty filtered pages the user can load more manually. `presentation: 'work'` opens work details; `'post'` opens the complete post. Album covers load images or explicit thumbnail resources only, never video playback URLs.

- `coverBlurred: true` and media `blurred: true` retain the site’s blurred covers and photos in thumbnails and full-image views. Do not present restricted photos as unblurred full content. Both previews and full videos expand HLS masters before playing the selected VOD variant.
- Authorized attachments without a direct link use `media[].resource` and implement `mediaChunk(resource, offset)`: at most 128 KiB per call, offsets aligned to 128 KiB; the resource must contain an integer `size` and a stable, non-secret string `cacheKey` that doesn't change with credentials or temporary references. The framework checks total size and each chunk and writes atomically to its own cache path; one attachment may be up to 512 MiB and the resource can't choose the local path. Signed links and resources aren't stored in subscription records.
- Subscriptions that follow or join on the original site must clearly explain the action and require user confirmation before saving. Unverified write actions must direct users to the original site; never follow, join or pay silently.

### Update subscriptions: `updateSubscriptions`

Regular plugins can support "follow for updates" with a separate `updateSubscriptions` object. The runtime exports `capabilities.subscriptionUpdates` only when `check` exists; it changes neither the category nor `capabilities.subscription`. Metadata includes `dimensions: [{ key, label, hint }]`; tag menus can pass the raw keyword and filter parameters.

- `normalize(dimension, input)` returns `{ id, label }`; `check({ dimension, target }, { cursor })` returns `{ items, hasNext, cursor }`. Items are `{ id, title, kind, workId, chapterId }` with `kind` limited to `work | post | chapter`, stable non-empty IDs and no media URLs, cookies or credentials. Chapter IDs include the work's identity so "Chapter 1" of different works don't collide.
- `Park.enableUpdateSubscriptions(Park.__pending, rules)` provides a generic adapter; declare dimensions explicitly at the end of the script, optionally with `searchFilters` and `seriesPattern`. `work` uses the real chapter list; `posts` uses the existing channel API; `search` and `filter` use search, `code` matches complete codes exactly, and `series` uses series paths validated against the site's domains. Search cursors store both page number and site cursor.
- `windowed: true` establishes a three-page baseline on the first check. Later checks process up to three pages per batch, saving cursors and candidates until a fully known page or the end is reached, then commit newly found events. Chapter lists are not truncated; exceeding 20,000 candidates or parsing failures must raise errors.
- `query({ dimension, target })` returns `{ keyword, filters }` shared by subscription browsing and checks. Albums also accept `{ search: { keyword, filters } }` and preserve the query while paging. Post video mode supports `resource` attachments and continues within the same search.
- Foreground and background share the plugin runtime, cookie partitions, domain constraints and checker. Background checks only start the relevant plugins and never sign in, subscribe on the site, download media or bypass permissions. A change of account or plugin configuration rebuilds the baseline (token renewal doesn't).

## Runtime API

Inside methods, `this` provides:

| Member | Description |
| --- | --- |
| `this.http` | `request(opts)`, `get(url, opts)`, `post(url, opts)`, `text(url, opts)`, `json(url, opts)` |
| `this.config` | values the user chose in site settings (`default` when unset) |
| `this.store` | persistent key-value store: `get(key, fallback)` / `set(key, value)` for tokens, domain lists, etc.; `await flush()` confirms the write and throws on failure |
| `this.cookies` | `get(url)` / `set(url, { name: value })` / `clear(url)` |
| `this.log({ code, host, transport, reason })` | writes only these allowed fields; free text is dropped so credentials and URLs never leak |

Global helpers:

| Helper | Description |
| --- | --- |
| `Park.html.parse(text)` | returns a standard `Document` for `querySelector` |
| `Park.html.text(node)` / `unescape(s)` / `strip(html)` / `paragraphs(node)` | text helpers |
| `Park.crypto.md5Hex(text \| text[])` | MD5, arrays allowed for batches |
| `Park.crypto.sha256Hex` / `hmacSha256Hex(key, text)` / `aesEcbDecrypt(base64, key)` / `uuid()` | native implementations |
| `Park.crypto.digestBytes('sha1' \| 'sha256', bytes)` | arrays of 0–255 integers, up to 2 MiB |
| `Park.crypto.randomBytes(length)` | secure random bytes, length 1–65536 |
| `Park.url.parse(value, base, domains)` / `site(source, value, base?)` / `response(source, response, requested)` | Parses HTTPS 443 URLs in authorized domains and subdomains, rejects user credentials, removes fragments and returns `null` on failure. `site` uses source `domains`; `response` validates the final URL without modifying the shared source base, or raises `BLOCKED`. Plugins retain path, page, work and search identity checks; avoid closed query-key lists and CDN node-name restrictions. |
| `Park.utils.rateLimiter(ms)` | returns `wait()` guaranteeing a minimum gap between requests |
| `Park.utils.mapLimit(items, n, fn)` / `lruMap(n)` / `parseCount('1.2万')` / `formatDate(ts)` | other helpers |
| `Park.error(code, message, extra?)` | creates an error with a code, see "Error codes" |

`Park.crypto.aesGcmDecrypt(ciphertext, key, iv)` takes hexadecimal ciphertext (including its final 16-byte authentication tag, at most 4096 bytes), a 16/24/32-byte key and a 12-byte IV, and returns plaintext bytes. Failed authentication throws without returning unauthenticated plaintext.

### `http.request(opts)`

```js
await this.http.request({
  url, method: 'GET', headers: {}, params: { q: 'x' },   // params are appended to the URL
  json: {...} | form: {...} | body: 'raw' | bodyBase64: '...',
  timeout: 15000,
  responseType: 'text' | 'base64',
});
// → { status, headers, body, url, ok, json() }
```

- `text()` / `json()` throw on non-2xx responses (404 → `NOT_FOUND`). Cookies are saved automatically and chosen again for every redirect target.
- `bodyBase64` is a raw binary body (up to 2 MiB) and can't be combined with `body` or browser mode; it follows the same domain isolation, TLS and redirect rules as text requests. Plugins can't open browser networking, WebSockets or arbitrary file access themselves.

## Error codes

Throw with `throw Park.error(code, message, extra)`; the app reacts to the code:

| code | What the app does |
| --- | --- |
| `CLOUDFLARE` | "Verify": opens the built-in browser |
| `CONFIRM_REQUIRED` | "Confirm": waits for the user to complete the declared access confirmation (`extra.url` points to it) |
| `LOGIN_REQUIRED` | "Sign in": opens the account section of the site settings |
| `NOT_FOUND` | shows "Content not found" |
| `BLOCKED` | shows "Access restricted" (IP ban, quota exhausted…); images aren't retried |
| `NETWORK` | shows "Couldn't connect" with the reason and "Retry" |
| `HTTP` / `PARSE` / `UNSUPPORTED` / `CONFIG` | shows the plugin's message and "Retry" |

### Structured messages

`message` is a **Chinese template** that doubles as the translation key; put the variable parts in `extra.params` instead of concatenating them:

```js
throw Park.error('HTTP', '站点返回 HTTP {status}', { params: { status: res.status }, status: res.status });
throw Park.error('NOT_FOUND', '影片不存在');
```

The app translates the template with the plugin's own `i18n` first, then the app's shared vocabulary, and fills `params` into the placeholders. A concatenated string can't be translated, so non-Chinese users would see Chinese. `status`, `url` and `diagnostics` in `extra` work as before.

### Home cache and error semantics

- Live `feed` results retain all returned fields. The private, rebuildable disk cache stores allow-listed work metadata, post text, attachment access data and supported detail fields so cached entries can open before refresh. It may contain expiring media URLs and resource references; it is not a download or backup, and expired links need refreshing. Cache identity separates site, account, configuration and request scope. Keep account credentials out of returned content, IDs and cursors, and never copy cached access data to diagnostics or subscription records.
- A stale cache is shown as offline content only for explicit `NETWORK` / `TIMEOUT` errors, and is marked as cached. Sign-in, confirmation, human verification, parsing and configuration failures must throw their own errors; the framework never disguises them as network failures, and a user-triggered refresh also shows the real error.

## Localization

The app UI supports `zh-Hans`, `zh-Hant`, `ja`, `ko`, `en`, `es`, `ru` and `ar` (Arabic is right-to-left). Write every static, user-facing text in a plugin (name, description, tab names, options, search hint, account notes, error messages) in **Simplified Chinese**; the original text is the translation key.

A plugin ships its own translations in the manifest's `i18n`:

```js
Park.register({
  i18n: {
    'zh-Hant': { '发行日期': '發行日期', '影片不存在': '影片不存在' },
    'en': { '发行日期': 'Release date', '影片不存在': 'Video not found', '站点返回 HTTP {status}': 'The site returned HTTP {status}' },
    // likewise ja, ko, es, ru, ar
  },
  key: 'mysite',
  // …
});
```

- Lookup order: the plugin's `i18n` for the current language → the plugin's `en` (except for Simplified Chinese) → the app's shared vocabulary (`assets/i18n/`, e.g. "Sort", "Latest", "Popular") → the original text.
- Only words the app doesn't already have need to go in `i18n`; common words reuse the app's translations. Placeholders `{name}` must match the original.
- Remote content (titles, authors, tags, descriptions), user input and persisted protocol keys stay as they are and aren't translated as UI text.
- Changing `i18n` is a plugin change and needs a version bump. Users with an older plugin see the old wording until they update.

The app's own UI text uses `tr('已选 {count}', { 'count': count })` or `context.tr`; the eight language files live in `assets/i18n/`, and every addition or change must update all of them with matching placeholders.

## Publishing

### Repositories

A repository is a single `index.json` on any static host. Users enter its address in More → Sites → Add site to browse, install and update:

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
      "sha256": "64-hex-digit SHA-256 of the script's UTF-8 text",
      "apiVersion": 2
    }
  ]
}
```

`url` is the full script address; `file` relative to `index.json` also works. Third-party repositories are installed manually after the user confirms; `sha256` is optional and checked when present.

### Versions and update rules

- Plugins must declare minAppVersion (for example 0.9.2), matching the official index. The current apiVersion is 2 and requires HentaiPark 0.9.2 or later. Updates and URL installations validate compatibility before replacing an installed plugin; incompatible updates leave the installed plugin unchanged. Automatic notifications separate compatible updates from those requiring a newer app. Ignore this version only suppresses the listed app or plugin versions, persists after restart, and does not affect manual checks.

- Versions are three dot-separated non-negative integers without leading zeros (e.g. `0.0.1`), compared numerically per part; missing parts, extra parts and pre-release suffixes are rejected.
- Official updates must provide the `sha256` of the script's UTF-8 text (no trimming or newline conversion), and the script's `key` and `version` must match the index; `apiVersion` must equal the app runtime's exactly, otherwise the update is refused.
- Plugin and app versions are separate. When changing a plugin script (including `i18n`), bump the version in both the script and `assets/sources/index.json`; the publisher refuses downgrades and the same version with different content.

### Official updates in the app

- "Check plugin updates at startup", in More → Sites and More → About → Updates, is on by default: each launch reads only the official index, announces new versions, and downloads, verifies and installs only after the user confirms. Returning to the foreground keeps a 12-hour interval, and failures still record the check time. With automatic checks off, manual checks still work. Only installed built-in and official plugins are checked; new plugins aren't installed automatically and third-party plugins with the same key aren't taken over.
- Installation re-verifies identity, version, origin, API and digest, and completes only after initialization and state persistence succeed; failures keep the old script and user state, and an interrupted install is recovered on next launch. Launching never overwrites installed plugins with bundled scripts; a missing script keeps its record and data until the user restores or updates it. "Restore built-in version" rolls back to the version in the current app package after confirmation.
- App updates are also checked by default: on Android, after the user confirms, the app downloads the matching official APK, verifies size, SHA-256, package name, version and signature, then opens the system installer, with progress, cancel and retry; the official release page is the fallback.

### Publishing official plugins

Official plugins are maintained in `assets/sources/index.json`. `tools/publish_sources.mjs` checks the index against runtime declarations offline and generates a release index with immutable script URLs and SHA-256. It does not sign in or call site methods, and cannot replace live verification. See the [development guide](../../DEVELOPMENT.md) for build and publishing steps.

### Generated plugins

The Telegram plugin's only implementation is `assets/sources/telegram_entry.mjs`; `assets/sources/telegram.js` is generated and must not be edited by hand:

```powershell
npm ci --prefix 'tools/source-runner'
node tools/build_subscription_sources.mjs
```

It uses [@mtproto/core 6.3.0](https://github.com/alik0211/mtproto-core) (GPL-3.0, [license](../../licenses/mtproto-core.txt); dependency summary in [third-party licenses](../../licenses/telegram-dependencies.txt)). The site adapter replaces transport, cryptography and storage, and doesn't enable the library's default WebSocket, browser localStorage or debug logging.

### `webVideo(id, episodeId)`

Android uses an isolated temporary WebView Profile and requires `MULTI_PROFILE`; update Android System WebView if it is unavailable. Closing playback clears its cookies and site storage and destroys the WebView; loaded profiles that cannot yet be deleted are cleaned up when playback starts in the next app process. Windows uses a separate temporary user directory and a private session; playback is refused if private sessions are unavailable, and the directory is cleaned up on exit. Playback pauses when the app enters the background or is locked.

Web playback handles Cloudflare in an isolated temporary session. Only the exact `challenges.cloudflare.com` verification frame is allowed, never main-frame navigation to that host. Age confirmation uses `network.confirmation` only on source-declared domains, not external players. If automatic checks cannot finish, the page remains available for manual handling; player cookies are never imported or exported. `CONFIRM_REQUIRED` preserves the plugin message and opens an in-app confirmation page to synchronize the source session after explicit completion, without replaying the original operation.

Supported providers in iXXX and TubeSafari prefer native playback, with resume and offline saving. Other providers use in-app web playback, which may require site confirmation and does not support app downloads or precise resume. Android web playback requires a recent Android System WebView with isolated-session support.

The runtime exports `capabilities.webVideo` automatically. A plugin implementing only `webVideo` opens an in-app web page. When both `videos` and `webVideo` are implemented, native playback is preferred and falls back to the web page only when `videos` returns `UNSUPPORTED`. HTTP, network, Cloudflare, login, parse, removed-content and cancellation errors remain visible. Downloads require successfully resolved native media and never fall back to a web page.

```js
return { url: "https://player.example.com/watch/1", navigationDomains: ["player.example.com"], frameDomains: [] };
// Native HTTP only: this.http.get(url, { followRedirects: false })
```

## Rankings and separate distribution

`rankings` declares boards with `key`, `label`, `category`, `metric` and `options`. A ranking-only plugin sets `rankingOnly: true` and declares no `feeds`. `ranking(board, {page, offset, cursor, options})` returns a work page; each item includes `id`, original `rank`, `title`, `cover`, optional `keyword`, `subtitle` and an HTTPS product `url`. Preserve tied ranks. An existing source may declare `feed` on its board: options are inherited when omitted, and the runtime reuses `feed()` while retaining work fields and adding `workId` and any missing rank. Those entries open work details; commercial entries search the declared category.

Source scripts stay on the main branch. The `sources`, `rankings` and `reverse-search` branches distribute regular, ranking-only and reverse-search-only plugins respectively. Each contains an index with immutable source URLs and SHA-256. The app reads all three independently, rejects mismatched channel markers and duplicate keys, and asks for confirmation before updates. Tag translations use a separate `tag-translations` branch.

```powershell
node tools/publish_sources.mjs --commit '<SHA>' --channel rankings --output '<本地输出文件>'
```

## Comments and content links

Implementing `comments` automatically exports `capabilities.comments`; `resolveContentLink` and `searchLink` export their matching capabilities. Declare only verified read operations. The comment interface does not post comments or replies, vote, or report content.

Official comment adapters include Reddit, myfans, Fansly, GalgameX, XVideos, Pornhub Shorties, PicACG, SpankBang, X / Twitter and Telegram; readable content remains subject to the original site's permissions. X / Twitter and Telegram require sign-in, and Telegram supports posts with discussions enabled. Preserve the exact original comment link for attachments that cannot be displayed directly.

```js
// WorkItem / WorkDetail / SubscriptionPost: { ..., commentsAvailable?: boolean }
comments(workId, {page = 1, cursor = null, parentId = null, sort = 'default', context = {}})
// context: {url?, episodeId?, board?}
// result: {items, hasNext, page?, cursor?, total?, reset?, sorts?: [{value, label}]}
// item: {id, author: {name, avatar?, url?, badges?: []}, body,
//        date?, likes?, rating?, spoiler?, parentId?, replyCount?,
//        repliesAvailable?, replies?: [item]}
// body: [{type: 'text' | 'link' | 'image' | 'quote', text?, url?}]
resolveContentLink(url) // null | {type: 'work', id} | {type: 'search', url} | {type: 'external', url}
searchLink(url, request) // WorkPage
```

- The optional top-level `commentsAvailable?: boolean` field on `WorkItem`, `WorkDetail` and `SubscriptionPost` indicates whether comments are enabled for that work. Strict boolean `false` hides the comment entry; `true` still requires the source's `capabilities.comments`. An omitted or non-boolean value means unknown, so source capabilities determine visibility. A count of 0 does not mean comments are disabled. If a read discovers that the original post has disabled comments, throw `UNSUPPORTED` instead of hiding that state behind an empty list.
- `workId` identifies the source work; `context` carries the original page, episode or ranking board. Keep episode comments separate by work and episode.
- `id` is a stable, nonempty source-local string. `author.name` may be empty; never invent names. Preserve comments containing only images; each body needs nonempty text or a valid image. `date` retains the original display text or ISO time. `likes` and `replyCount` are nonnegative, `rating` is 0–5, and `spoiler` flags spoilers.
- `replies` has the same item structure; `parentId` identifies its parent. A parent's body must exclude child reply bodies. `replyCount` is the site's reply count. Set `repliesAvailable: true` only after verifying reads using `parentId`; the default is false, and a count alone does not enable loading. When the site provides no count, `replyCount: 0` may coexist with `repliesAvailable: true`. The UI still offers View replies without inventing a count or blocking access based on the number already loaded. When reading nested replies, the request `parentId` is the selected comment's `id`.
- Derive `hasNext` from the site response. Cursors must contain no credentials and must be passed back unchanged. Stop on repeated IDs, exhausted totals or an explicit end; use false for unverified pagination. `sorts` lists only verified orders, with UI translation keys in `label`.
- When the site's pagination snapshot changes, return `reset: true`, the actual reloaded `page` (usually 1) and a new cursor to replace the old list. Never pass the first page off as a later page. Throw appropriate business, login or parsing errors instead of concealing them with an empty list.

`Park.comments.html(html, baseUrl)` produces safe body parts, retaining text, line breaks, links, images and quotes while removing executable content. `Park.comments.text(text)` splits explicit HTTP(S) URLs from plain text. `Park.comments.url(value, baseUrl)` returns a valid HTTP(S) URL or null. Avatar, profile and body URLs must not contain userinfo. The framework renders structured data and never executes site HTML. Plugins still parse site fields and send requests through `this.http`.

`resolveContentLink` recognizes exact hosts and verified paths and parameters; return null for unrelated targets. Use `type: 'work'` for works, `type: 'search'` for original-site searches and optionally `type: 'external'` for other safe pages. Profiles, comment anchors, dates, floor numbers and playback timestamps are not work IDs. `searchLink` receives the complete original URL and returns the existing WorkPage format while preserving keywords, filters, categories and pagination. Do not discard parameters by extracting only keywords, or access write endpoints. Unrecognized links retain an option to open the original page.

## Read-only live chat

Declare `capabilities.liveChat` only when both `liveChat(id)` and `liveChatEvent(state, event)` exist. Official support covers CAM4, XLoveCam, Stripchat and SOOP. `chat.domains` is an independent host-and-port allowlist; page, image and media permissions do not apply. `host` permits only port 443. Nonstandard ports must be explicitly declared as `host:port` and fall within 1024–65535. `*.host:port` matches exactly one subdomain level on that port, excluding the base host, deeper subdomains and other ports. Only HTTPS/SSE and WSS are allowed, without plaintext transport, user information or fragments. Guest bootstrap tickets must never follow a redirect to another host or port.

`liveChat` returns `transport: "sse" | "websocket"`, `url`, optional `headers`, and `state`. Use `this.chatHttp.request({url, method, headers, body|json})` for guest bootstrap requests within the chat allowlist; cancellation belongs to the current invocation. Cookies are partitioned by source. Tickets, connection URLs, protocol state and messages remain in memory.

- `protocols`: WebSocket only; at most 8 unique, nonempty RFC token strings, each no longer than 128 characters.
- `binary: true`: WebSocket only; sends and receives UTF-8 binary frames while plugin `event.data` and `send` remain strings. Each frame is limited to 65536 bytes and UTF-8 is validated strictly. The default uses text frames.
- `heartbeatIntervalMs`: optional integer from 10000 to 60000. After a successful connection, `{type: "tick"}` events enter the same serial event queue at this interval. Stopping or leaving the page cancels them. Ticks do not extend the connection handshake or SSE receive timeout.

A fixed 25-second deadline covers connection setup and the protocol handshake. WebSockets without `heartbeatIntervalMs` use native ping/pong at 30-second intervals. When that field is declared, plugin ticks provide keepalive instead, and actual transport errors or close events determine disconnection. Neither mode treats a quiet room without chat text as disconnected, and local ticks are not proof that the server is alive. SSE retains a 90-second timeout for receiving server data.

`liveChatEvent` receives `{type: "open"}` or `{type: "message", data, event?}` or `{type: "tick"}`. SSE retains its event name in `event`. Return the new `state` and optional `connected`, `error`, `messages`, and `send`. Each message has a stable `id`, plain `text`, optional `author`, and `isHistory`; history is used for deduplication and is not replayed as new chat. `send` is limited to verified authentication, subscription and heartbeat frames. No user message API is provided.

The host bounds frame size, decode queues, message storage and retries. Reconnection obtains fresh guest tickets and failures expose retry. Turning chat off, covering the route, moving to the background, locking the app or disposing the player immediately cancels the connection and calls; stale callbacks cannot update a new session. This capability does not imply work comments, history pagination or timed comments for recordings.

```js
chat: {domains: ["chat.example.com"]},
async liveChat(id) {
  return {transport: "websocket", url: "wss://chat.example.com/room", state: {}};
},
liveChatEvent(state, event) {
  return {state, connected: true, messages: [
    {id: "message-id", text: "message", author: "author", isHistory: false}
  ], send: []};
}
```
