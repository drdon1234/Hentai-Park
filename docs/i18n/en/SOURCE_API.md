[简体中文](../../SOURCE_API.md) · [繁體中文](../zh-Hant/SOURCE_API.md) · [日本語](../ja/SOURCE_API.md) · [한국어](../ko/SOURCE_API.md) · [English](SOURCE_API.md) · [Español](../es/SOURCE_API.md) · [Русский](../ru/SOURCE_API.md) · [العربية](../ar/SOURCE_API.md)

# Site plugin API

[Quick start](#quick-start) · [Manifest fields](#manifest-fields) · [Methods](#methods) · [Runtime API](#runtime-api) · [Error codes](#error-codes) · [Localization](#localization) · [Publishing](#publishing) · [Appendix: notes on official sites](#appendix-notes-on-official-sites)

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

Install the shared runner's dependencies at the repository root and create an ignored `test/source-smoke.mjs` like the one below. The example only loads the manifest; when you change a plugin, also verify with real requests the first page, the second page, search, details, cover decoding, and chapters or video media.

```js
import { loadSource } from '../tools/source-runner/host.mjs';
const { manifest } = await loadSource('nhentai.js');
console.log(manifest.key, manifest.version);
```

```powershell
npm ci --prefix 'tools/source-runner'
node 'test/source-smoke.mjs'
```

## Manifest fields

```js
Park.register({
  key: 'mysite',              // unique and permanent; only [A-Za-z0-9_-], 1–100 chars, not _app
  name: '我的站点',
  version: '0.0.1',           // three numbers; the app offers an update when the repository has a higher one
  type: 'comic',              // comic | video | novel | game: how works are read or played
  category: 'doujin',         // doujin | anime | aiDrama | jav | adult | shortvideo | gallery | novel | game | other
  color: '#E5355F',           // brand color: site avatar and site page
  description: '一句话介绍',
  homepage: 'https://example.com',
  domains: ['example.com'],                   // sites it belongs to, see "Isolation and security"; derived from homepage etc. if omitted
  linkPatterns: ['example\\.com/g/(\\d+)'],   // pasted links open the work directly; group 1 is the work ID
  idPattern: '^(\\d+)$',                      // typed IDs open the work directly
  imageHeaders: { Referer: 'https://example.com/' },  // default headers for covers and images
  network: { mode: 'native', vpnHint: true },  // see "Network"
  media: { mode: 'browser', origin: 'https://example.com', domains: ['media.example.com'] },  // optional HLS media permission
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
| `gallery` | Galleries: illustration, cosplay and photo sets. Image sites still declare `type: 'comic'`; one gallery is one work and its images come from `chapter()` in order, so reading, favorites and downloads work as usual. The category isn't about image count or explicitness |
| `anime` | Adult animation |
| `aiDrama` | AI short dramas. The old `drama` value isn't accepted; declare the site's own channel names as they are, the app category doesn't filter them |
| `jav` | Dedicated JAV sites |
| `adult` | General adult video (Pornhub, XVideos, 91porn…), `type: 'video'`. A category is a grouping; it doesn't replace site tags or user filters |
| `shortvideo` | Short videos: a full-screen vertical feed, see below |
| `novel` | Novels, `type: 'novel'` |
| `game` | Games, `type: 'game'` |
| `other` | Everything else (subscription sites, etc.) |

- **Short videos** (`type: 'video', category: 'shortvideo'`): works, search, favorites and history open straight into the feed. Each work is one short video and `videos(id, '_')` returns its current media; no detail page is needed. `hasNext` and `cursor` from `feed` drive automatic paging near the end; cursors must not contain credentials or media signatures. Refreshing starts from page one; the current item plays, the next one is preloaded paused, the rest are released. Don't declare `search` if the site has none.
- **Aggregators that can only play on the original site**: still declare `type: 'video', category: 'adult'`; without a verified media API, don't implement `videos`, and the runtime exports `capabilities.videos: false`. The detail page's main button then opens `detail.url` in the system browser, playback, downloads and episodes are hidden, no fake chapters are stored and no chapter updates are checked; favorites and history still work.
- **Novels** and **games** are covered under "Methods".

Choose `defaultFeed` in the order **recommended > rankings > popular**; use the latest page or another valid entry only if the site really has none of these, and never fake an unverified API. If it's missing or unknown, the app picks by key (first `promote` / `recommend` / `featured`, then `rank` / `toplist`, then `popular` / `hot` / `trending`), falling back to the first tab.

### Options

`feeds[].options`, `searchFilters` and `settings` share one format:

```js
{ key: 'sort', label: '排序', type: 'select', default: 'date',
  values: [{ value: 'date', label: '最新' }, { value: 'popular', label: '热门', color: '#f00' }] }
// type: select | multi | number | text | password | switch
// settings may use options instead of values
```

Each `feeds` entry is a tab on the site page: `{ key, label, options?: [...] }`.

### Network

- `network.mode: 'native'` (default): native HTTP with persistent cookies, using the user's proxy. A Cloudflare challenge raises `CLOUDFLARE`; the app guides the user through it in the built-in browser and syncs the clearance cookies back to native requests.
- `network.mode: 'browser'` + `network.origin`: requests are made with same-origin `fetch()` from a hidden browser page opened at `origin`, with a real browser fingerprint — for sites with strict Cloudflare protection. When a same-origin GET receives a Cloudflare challenge, the hidden browser navigates to it to pass automatically and retries once; if that fails, `CLOUDFLARE` is raised.
- `network.vpnHint: true`: declare it for sites that may need a VPN or proxy in mainland China; waits over 8 seconds and failures then mention "may need a VPN or proxy". Don't blame every error on the VPN.
- `network.confirmation: { selector, readySelector, requiredCookies, message }`: for sites that need explicit confirmation (an age gate, for example). `selector` matches the confirmation dialog, `readySelector` the accessible content, and `requiredCookies` are the cookies that must exist afterwards. When the plugin hits an unconfirmed page it throws `Park.error('CONFIRM_REQUIRED', message, { url })`; the app offers "Confirm" and returns once the dialog is gone, content is visible, cookies are written and navigation has settled. The app never clicks confirm for the user, and this declaration also keeps generic human checks from mistaking an age gate for success.
- Network errors carry safe `diagnostics` fields `host`, `transport` and `reason`, distinguishing TLS certificates, handshakes, DNS, connections and timeouts; automatic logs record only these allowed fields. `reason: 'TLS_HANDSHAKE_TERMINATED'` only means the native `HandshakeException.message` is exactly `Connection terminated during handshake` (the connection dropped before the handshake completed, not a certificate failure); only HTTPS GET/HEAD requests without a body retry once on it, and nothing else is retried.

### Images

- `imageNetwork: { mode: 'browser', origin, domains }`: declare it when an image CDN needs browser requests. `origin` and every image domain must be within `domains`; only HTTPS and allow-listed headers are used; image requests carry no account credentials, follow no redirects and are limited to 20 MiB each, and still go through decryption, format checks, decoding and per-site caching. Without it, the native image transport is used.
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

```js
domains: ['example.com'],
network: { mode: 'native' },
media: { mode: 'native', origin: 'https://example.com', domains: ['media.example.com'] },
```

- `media.mode` is `'native'` or `'browser'`. `media.origin` must belong to the plugin's sites, use HTTPS on the default port 443, and contain no credentials, query or fragment.
- `media.domains` is a separate allow-list for media (subdomains included) that grants no site cookie access. Playlists, segments and keys must be HTTPS on 443; URL credentials, fragments, IPs, localhost (and subdomains) and `.local` are rejected.
- `'native'` uses a separate native client without credentials: no site cookies, Authorization or proxy auth; every redirect hop is checked first. Only `Referer`, `Origin`, `Accept` and `Accept-Language` are allowed, and the first two must match `media.origin`.
- `'browser'` opens a media session in a hidden browser at `media.origin` with `credentials: 'omit'`, `mode: 'cors'` and `redirect: 'error'`.
- Responses are size-limited while streaming and their final address is re-checked: playlists up to 2 MiB, segments up to 32 MiB, AES-128 keys exactly 16 bytes. Oversized or empty responses and disallowed addresses are rejected.

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
  loginUrl?, cookieUrl?, requiredCookies?: ['ipb_member_id'],   // enables web sign-in; the app collects the cookies
  loginDomains?: ['accounts.google.com', 'appleid.apple.com'],  // third-party sign-in domains, used only for sign-in navigation
  async login(values) { return { name } },
  async logout() {},
  async status() { return { loggedIn, name, configured } },
  managedAccount: true,                 // optional: offers an automatically managed account
  async enableManaged() {},             // only called after the user agrees to registration
}
```

- Account status is refreshed only on first use, after sign-in, sign-out and web sign-in, and when the last check is older than 10 minutes — not after every call. `configured` means an account is set up, whether or not sign-in currently works.
- `loginDomains`: third-party sign-in domains the site actually uses (subdomains included). They're allowed only while the user has the web sign-in page open, HTTPS on 443 only; URL credentials, IPs, localhost and `.local` are refused. Verification pages, access confirmation, plugin requests and cookie import are still checked against `domains`; don't add sign-in domains to `domains` to widen access. The sign-in page supports same-window redirects and pop-ups that keep `window.opener`, with the same checks in pop-ups; a blank initial page grants no external navigation. Sign-in isn't considered complete while on a third-party page; cookies sync once back on the site. Third-party cookies aren't imported into the plugin's jar or cleared with the site's cookies; the system WebView manages them. Third parties may still restrict sign-in in embedded browsers.
- `type: 'session'` imports an existing authorized session: declare one secret field (such as `session`); the clipboard content is kept whole and validated by the plugin rather than split into username, password or cookies. Sign-in must really confirm authorization — never report success from the input's format alone.
- `managedAccount: true` declares an automatically managed account, controlled by a setting with the same name. The app must first explain automatic registration and get the user's agreement, then save the setting and call `account.enableManaged()`. Save candidate credentials and `await this.store.flush()` before registering, so a failure or restart recovers the same account. Keep manual and managed credentials separate; a managed account never overwrites a manual one. Turning the setting off keeps the managed account for reuse; an expired token only signs in again and never registers another account.
- Passwords, tokens and plugin state are the user's local data; never put real credentials in documents or logs.

## Methods

`this` inside methods is described in "Runtime API". All methods may be `async`.

```js
async feed(key, { page, cursor, options }) {}      // site page tabs
async search({ keyword, page, cursor, filters }) {}
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

**WorkItem**: `{ id, title, subtitle?, cover, coverAspect?, pages?, rating?, likes?, views?, language?, category?, badge?, badgeColor?, duration?, uploaded?, tags?, mediaKind? }`

- `coverAspect` (width / height) lets the grid lay out before images load.
- `badgeColor` colors the category badge.
- `mediaKind: 'comic' | 'video' | 'novel' | 'game'` is the work's own type. Plugins with a single type may omit it; mixed-type plugins must set it — never treat images as videos just because of the plugin's `type`. Novel and game works always set it, so offline works and history still open in the right reader after the plugin is uninstalled.
- Post-style results may include `presentation: 'post'`, `text`, `date`, `url` and a `media` array to show as post cards; `presentation: 'media'` shows a media grid that opens the media inside the work. Posts may have no media; media URLs remain subject to the plugin's declared domains and permissions.

### Details: `detail`

All WorkItem fields, plus:

```js
{
  url, authors: [], description, uploader?, size?, comments?,
  tags: [{ namespace: 'artist', label: '作者', tags: [{ name, keyword, filters?, count? }] }],
  chapters: [{ id, title }] | null,   // null means a single chapter
  singleChapterId?,                   // chapter ID needed by single-chapter works
  thumbnails?: [url | { url, width, height, offsetX, offsetY }],   // sprite sheets supported
  related?: [WorkItem], series?: [WorkItem],
}
```

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

Returns `[{ quality: 1080, label: '1080P', url, headers?, format?, preferred? }]`. Direct links usually expire, so the app fetches them again before every playback or download.

- Multi-episode videos return `[{ id, title }]` in play order from `detail(id).chapters`; each `id` must be stable, never a quality or temporary media URL. The app uses the same ID to pick episodes, store progress, download and resume, and calls `videos(id, episodeId)` for each episode. Single videos use `singleChapterId`, or `'_'` if absent.
- Without `format`, playback and download treat the link as direct MP4. HLS must return `format: 'hls'` and declare the `media` permission.
- An HLS master playlist (`#EXT-X-STREAM-INF`) is expanded by the app into per-variant playlists, with real quality taken from `RESOLUTION`. When you return a master playlist, `quality` is the desired quality: the highest real quality not above it is chosen, or the highest available. Each variant must be muxed audio/video MPEG-TS; separate `AUDIO`, `VIDEO`, `SUBTITLES` renditions and addresses outside `media.domains` are rejected. `#EXT-X-I-FRAME-STREAM-INF` tracks are ignored. If a single playlist has no known resolution, use `label: '原画'` rather than presenting the desired quality as real.
- Only complete, continuous MPEG-TS VOD playlists with `#EXT-X-ENDLIST` are supported; `METHOD=AES-128` with `KEYFORMAT=identity` (CBC/PKCS7) is decrypted, with exactly 16-byte keys and an explicit IV or one derived from the media sequence. Keys stay in session memory. Live streams, SAMPLE-AES, other KEYFORMATs, `EXT-X-MAP`, `EXT-X-BYTERANGE`, fMP4, discontinuities and gaps aren't supported; the non-standard `#EXT-X-TOKEN` is removed.
- Playback uses a random port bound to `127.0.0.1` and a random token, serving verified segments on demand from a limited URL registry; closing the session cancels requests. HLS offline downloads are Android-only for now: each segment is verified and its SHA-256 saved, downloads can resume and be cancelled, and Media3 finally muxes an MP4 — only complete files reach the offline library.

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
    return { items: [{ id, title, text, date, url, locked,
      media: [{ type: 'image', url, preview, previewOnly: false },
              { type: 'video', url, preview, format: 'mp4', headers: {} }] }],
      cursor: nextCursor, hasNext: true };
  },
  async mediaChunk(resource, offset) { return { base64, done }; }, // optional
}
```

- `normalize` must validate locally only, so targets can be saved signed out or offline; accept only usernames or controlled profile URLs of this site. `resolve` and `targets` are optional; with `targets`, the manifest outputs `subscription.joinedTargets: true`.
- `posts` cursors are opaque strings; the last page has `hasNext: false`, and pages without media may still continue. `locked` means insufficient permission; `previewOnly` marks public previews — never pass a thumbnail off as the full content.
- Authorized attachments without a direct link use `media[].resource` and implement `mediaChunk(resource, offset)`: at most 128 KiB per call, offsets aligned to 128 KiB; the resource must contain an integer `size` and a stable, non-secret string `cacheKey` that doesn't change with credentials or temporary references. The framework checks total size and each chunk and writes atomically to its own cache path; one attachment may be up to 512 MiB and the resource can't choose the local path. Signed links and resources aren't stored in subscription records.
- Saving a subscription never follows or joins anything. Unverified write actions must send the user to the original site; never follow, join or pay silently.

### Update subscriptions: `updateSubscriptions`

Regular plugins can support "follow for updates" with a separate `updateSubscriptions` object. The runtime exports `capabilities.subscriptionUpdates` only when `check` exists; it changes neither the category nor `capabilities.subscription`. Metadata includes `dimensions: [{ key, label, hint }]`; tag menus can pass the raw keyword and filter parameters.

- `normalize(dimension, input)` returns `{ id, label }`; `check({ dimension, target }, { cursor })` returns `{ items, hasNext, cursor }`. Items are `{ id, title, kind, workId, chapterId }` with `kind` limited to `work | post | chapter`, stable non-empty IDs and no media URLs, cookies or credentials. Chapter IDs include the work's identity so "Chapter 1" of different works don't collide.
- `Park.enableUpdateSubscriptions(Park.__pending, rules)` provides a generic adapter; declare dimensions explicitly at the end of the script, optionally with `searchFilters` and `seriesPattern`. `work` uses the real chapter list; `posts` uses the existing channel API; `search` and `filter` use search, `code` matches complete codes exactly, and `series` uses series paths validated against the site's domains. Search cursors store both page number and site cursor.
- Search and post checks return `windowed: true`, meaning the latest three pages are checked: the first check only records a baseline, later ones raise "newly found" events by stable ID without claiming a publish date. Other paged protocols check at most three pages per round, saving cursors and candidates and committing in one transaction once complete; chapter lists are never truncated, with a cap of 20,000 candidates (exceeding it is an error). Network, permission, verification, empty-list or partial-parse failures must raise explicit errors, never empty success.
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
| `Park.utils.rateLimiter(ms)` | returns `wait()` guaranteeing a minimum gap between requests |
| `Park.utils.mapLimit(items, n, fn)` / `lruMap(n)` / `parseCount('1.2万')` / `formatDate(ts)` | other helpers |
| `Park.error(code, message, extra?)` | creates an error with a code, see "Error codes" |

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

- Live `feed` results keep every field the plugin returns; the home cache on disk keeps only allow-listed display metadata (ID, title, cover, tags, uploader, media type, category, display stats); `url`, credentials, media lists and posts aren't written. Don't put credentials in IDs, cover URLs or cursors. Results that need dynamic media or posts aren't cached.
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
  "apiVersion": 1,
  "sources": [
    {
      "key": "mysite",
      "name": "我的站点",
      "version": "0.0.1",
      "description": "一句话介绍",
      "url": "https://example.com/sources/mysite.js",
      "sha256": "64-hex-digit SHA-256 of the script's UTF-8 text",
      "apiVersion": 1
    }
  ]
}
```

`url` is the full script address; `file` relative to `index.json` also works. Third-party repositories are installed manually after the user confirms; `sha256` is optional and checked when present.

### Versions and update rules

- Versions are three dot-separated non-negative integers without leading zeros (e.g. `0.0.1`), compared numerically per part; missing parts, extra parts and pre-release suffixes are rejected.
- Official updates must provide the `sha256` of the script's UTF-8 text (no trimming or newline conversion), and the script's `key` and `version` must match the index; `apiVersion` must equal the app runtime's exactly, otherwise the update is refused.
- Plugin and app versions are separate. When changing a plugin script (including `i18n`), bump the version in both the script and `assets/sources/index.json`; the publisher refuses downgrades and the same version with different content.

### Official updates in the app

- "Check plugin updates at startup", in More → Sites and More → About → Updates, is on by default: each launch reads only the official index, announces new versions, and downloads, verifies and installs only after the user confirms. Returning to the foreground keeps a 12-hour interval, and failures still record the check time. With automatic checks off, manual checks still work. Only installed built-in and official plugins are checked; new plugins aren't installed automatically and third-party plugins with the same key aren't taken over.
- Installation re-verifies identity, version, origin, API and digest, and completes only after initialization and state persistence succeed; failures keep the old script and user state, and an interrupted install is recovered on next launch. Launching never overwrites installed plugins with bundled scripts; a missing script keeps its record and data until the user restores or updates it. "Restore built-in version" rolls back to the version in the current app package after confirmation.
- App updates are also checked by default: on Android, after the user confirms, the app downloads the matching official APK, verifies size, SHA-256, package name, version and signature, then opens the system installer, with progress, cancel and retry; the official release page is the fallback.

### Publishing official plugins

Official plugins are published from the main repository [drdon1234/Hentai-Park](https://github.com/drdon1234/Hentai-Park); the app reads:

```text
https://raw.githubusercontent.com/drdon1234/Hentai-Park/sources/index.json
```

- `assets/sources/index.json` is the only maintained list; `file` points to a script in the same folder named `{key}.js` (`[A-Za-z0-9_-]+.js`; no subfolders, symlinks or dots in the base name).
- `tools/publish_sources.mjs` generates the published index with `key`, `name`, `version`, `category`, `description`, `url`, `sha256` and `apiVersion`; script URLs are pinned to the full source commit: `https://raw.githubusercontent.com/drdon1234/Hentai-Park/<commit SHA>/assets/sources/<file>`. The `sources` branch holds only the generated `index.json`.
- The publisher needs only Node.js 22+ built-ins and runs offline: it checks the list, files and folder boundaries, loads the runtime and scripts without network or storage, and verifies `key`, `version` and API with the same `Park.__pending` / `Park.manifest` probe as the install preview. It doesn't call `init`, sign-in or site methods, so it can't replace real requests.

```powershell
node tools/publish_sources.mjs --commit '<full 40-character commit SHA>' --output 'test/official-source-index.json'
```

Add `--previous 'path to old index'` to compare with an existing release; an invalid old index fails the check. `.github/workflows/publish-sources.yml` runs only for related pushes to `main` in the main repository or manual runs, one at a time, and updates the `sources` branch with a single ordinary push after every check passes; a failed check or a concurrent change to the branch never overwrites the live index.

### Generated plugins

The Telegram plugin's only implementation is `assets/sources/telegram_entry.mjs`; `assets/sources/telegram.js` is generated and must not be edited by hand:

```powershell
npm ci --prefix 'tools/source-runner'
node tools/build_subscription_sources.mjs
```

It uses [@mtproto/core 6.3.0](https://github.com/alik0211/mtproto-core) (GPL-3.0, [license](../../licenses/mtproto-core.txt); dependency summary in [third-party licenses](../../licenses/telegram-dependencies.txt)). The site adapter replaces transport, cryptography and storage, and doesn't enable the library's default WebSocket, browser localStorage or debug logging.

## Appendix: notes on official sites

Conventions you need when maintaining the official plugins. Sites change; the plugin code is authoritative.

**Games**

- Default order is GalgameX → KUN Galgame → Dimension Tea House. GalgameX and KUN enable NSFW by default (the guest `content-filter` API and the `include_nsfw` parameter respectively).
- GalgameX defaults to this week's popular list. The resource update list uses a Next Server Action discovered from the current front end; the action ID is cached for 15 minutes and rediscovered when it stops working, and no remote script is executed. Details are parsed from SSR Flight data. Public resources use host plus path hash as a stable channel ID; resolved results are matched by host and file name / share ID, rejecting mismatches and duplicates, without relying on the order of temporary links.
- KUN defaults to the 7-day views ranking using its public native API; the download API is called only on tap, so prefetching never inflates the site's download count. Resource pages are walked by the API's total; repeated pages or early empty pages are errors.
- Dimension Tea House uses browser mode with its own sign-in and defaults to the popular Galgame resource board; covers come from first-post attachments with 400 ms between requests. The resource list is read-only; the reply "感谢分享，好人一生平安" is sent with the full form only after the user confirms. Already unlocked threads are never replied to; when the result is unclear, state is kept and the user is pointed to the thread, and nothing is resent after a restart.

**Novels**

| Site | Default tab | Scope and limits |
| --- | --- | --- |
| Book18 | Recommended | Chinese long and short stories; chapters in site order |
| Cool18 | Featured | Only the forbidden-books board; each main post is its own work, replies and same-titled posts aren't merged; some content needs account permissions |
| Canovel | Latest | In-article pagination supported |
| Literotica | Rankings | English; search excludes non-English, audio, how-to, reviews and essays |
| Lush Stories | Recommended | English; audio and poetry excluded |
| StoriesOnline | Author picks | English; truncated anonymous text asks to sign in and is never saved as a full chapter |
| 69story | Latest | Chinese; categories, search, contents and per-chapter reading |

**Subscriptions**

| Platform | Content | Sign-in |
| --- | --- | --- |
| X / Twitter | Anonymous public media; authorized posts and media when signed in | Web sign-in, or `auth_token` and `ct0` |
| Telegram | Public channel previews; channel history and attachments when signed in | Import an existing Telegram WebK local-storage session |
| myfans.jp | Creator lists, public images, public videos and trial previews | Member sign-in not verified |
| pixivFANBOX | Public lists and cover previews | Member sign-in not verified |

- X's `ct0` must match `X-CSRF-Token`; sessions can expire or be revoked. After sign-in the plugin loads operation IDs and feature flags from the current web app, then reads UserTweets and keeps only the target author's media (no retweets or quotes). Anonymous third-party proxies never receive X cookies.
- Telegram local storage isn't a cookie: the import needs `dc` and the matching `dcN_auth_key` (512 hex digits), as JSON or `key=value` text. The plugin only restores an existing WebK session — no code-based sign-in or own client registration — and signing out only deletes the session saved by this app. Attachments are read in 128 KiB chunks, up to 512 MiB each; expired media references are refreshed once. Networking goes through the isolated native HTTP bridge; WebView fetch/WebSocket isn't enabled.
- OnlyFans, Fantia, Patreon and Fansly don't have a complete media path and aren't in the official list. A home page that opens doesn't mean media can be subscribed to, and paid access is never bypassed.

Dynamic HLS CDNs: declare `media.scope: 'session'` with native media. Only the current resolved URL, playlist resources and up to 8 redirect hops are authorized, without changing cookie permissions. HTTPS 443 and credential-free headers remain required. Direct connections reject non-public DNS addresses and connect to a checked IP with normal TLS hostname verification. An explicitly configured HTTP proxy resolves upstream hosts and is trusted to enforce public-network routing. Permissions disappear when the playback/download session closes; direct MP4 and browser media retain static domain restrictions.
