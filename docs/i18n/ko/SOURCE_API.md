[简体中文](../../SOURCE_API.md) · [繁體中文](../zh-Hant/SOURCE_API.md) · [日本語](../ja/SOURCE_API.md) · [한국어](SOURCE_API.md) · [English](../en/SOURCE_API.md) · [Español](../es/SOURCE_API.md) · [Русский](../ru/SOURCE_API.md) · [العربية](../ar/SOURCE_API.md)

# 소스 플러그인 개발 가이드

HentaiPark의 각 출처는 별도의 JavaScript 파일입니다. 앱은 런타임에 이를 로드합니다. 앱을 다시 컴파일하지 않고도 소스 저장소에서 설치, 업데이트, 활성화/비활성화할 수 있습니다.
내장 소스는 [`assets/sources/`](../../../assets/sources/)에 있으며 예제 참조로 직접 사용할 수 있습니다.

## 실행 환경

- 소스 스크립트는 앱의 헤드리스 WebView에서 실행됩니다(`DOMParser`를 포함한 최신 JS). 네이티브 계층이 암호화, Cookie 처리, 네이티브 HTTP 요청을 제공합니다. 네이티브 HTTP에는 CORS 제한이 없으며 브라우저 네트워크와 미디어 요청은 아래의 별도 규칙을 따릅니다.
- 동일한 런타임([`assets/runtime/park_runtime.js`](../../../assets/runtime/park_runtime.js))을 Node에서도 실행할 수 있으며, 개발 중에 실제 사이트에서 직접 스모크 테스트를 수행할 수 있습니다.

  ```bash
  cd tools/source-runner && npm install
  node ../../test/source-runner/smoke.mjs nhentai.js --keyword "tag:\"full color\""
  ```

  `smoke.mjs`는 `test/source-runner/`에 있는 로컬 테스트 파일이며 저장소에 포함되지 않습니다. 각 feed(2페이지 포함), 검색, 무작위 작품, 상세 정보, 표지, 챕터, 첫 페이지와 마지막 페이지 이미지 다운로드를 순서대로 확인합니다.

## 소스 등록

```js
Park.register({
  key: 'mysite',              // 고유 식별자, 설치 후에는 변경할 수 없습니다.
  name: 'Example Source',
  version: '0.0.1',           // 창고의 버전 번호가 더 높으면 앱에 업데이트 메시지가 표시됩니다.
  type: 'comic',              // comic | video
  color: '#E5355F',           // 브랜드 색상: 소스 입구 카드 및 소스 페이지 테마 색상에 사용됩니다.
  description: 'Example source description',
  homepage: 'https://example.com',
  domains: ['example.com'],                   // 그것이 속한 사이트에 대해서는 "격리 및 보안"을 참조하십시오. 생략시 홈페이지 등의 주소를 기준으로 추론됩니다.
  linkPatterns: ['example\\.com/g/(\\d+)'],   // 집계 검색에 링크를 붙여넣을 때 직접 액세스에 사용됩니다. 첫 번째 그룹은 작업 ID입니다.
  idPattern: '^(\\d+)$',                      // 번호를 직접 입력할 때 바로 접속을 위해 사용됩니다.
  imageHeaders: { Referer: 'https://example.com/' },  // 표지와 사진을 로드할 때 기본적으로 수행됨
  network: { mode: 'native' },                // "네트워크" 섹션을 참조하세요.
  media: { mode: 'browser', origin: 'https://example.com', domains: ['media.example.com'] },  // 선택적 HLS 미디어 권한, 아래 참고

  settings: [ /* option definitions */ ],
  account: { /* optional account */ },
  defaultFeed: 'ranking',                     // 원본 페이지를 열 때 기본적으로 입력되는 라벨(피드 키)
  feeds: [ /* browse tabs */ ],
  searchFilters: [ /* search filters */ ],
  searchHint: 'Search by title or tag',

  async init() {},                            // 선택사항: 로드 시 한 번 호출됩니다(예: 도메인 이름 목록 새로 고침).
  async onSettingsChanged() {},               // 선택사항: 사용자가 소스 설정을 수정한 후 호출됩니다.

  async feed(key, { page, cursor, options }) {},
  async search({ keyword, page, cursor, filters }) {},
  async random() {},                          // 작업 ID를 반환합니다.
  async detail(id) {},
  async chapter(id, chapterId) {},            // 만화
  async resolveImage({ id, chapterId, index, token, retry }) {},  // 선택 사항: 이미지 구문 분석 지연
  async thumbnails(id, page) {},              // 선택 사항: 페이지에 미리보기 축소판 로드
  async videos(id, episodeId = '_') {},                        // 동영상
});
```

이 방법에서는 `this`를 사용하여 다음에 액세스할 수 있습니다.

| 회원 | 설명 |
|------|------|
| `this.http` | `request(opts)`, `get(url, opts)`, `post(url, opts)`, `text(url, opts)`, `json(url, opts)` |
| `this.config` | 소스 설정에서 사용자가 선택한 값(설정되지 않은 경우 `default`) |
| `this.store` | 영구 키-값 저장: `get(key, fallback)` / `set(key, value)`, 토큰, 도메인 이름 목록 등을 저장하는 데 사용됩니다. `await flush()`는 디스크 쓰기가 성공했는지 확인하고 실패하면 오류를 발생시킵니다. |
| `this.cookies` | `get(url)` / `set(url, {name: value})` / `clear(url)` |
| `this.log(...)` | 앱의 "실행 로그"에 쓰기 |

전역 도구:

| 도구 | 지침 |
|------|------|
| `Park.html.parse(text)` | 표준 `Document`를 반환하고 `querySelector` |
| `Park.html.text(node)` / `unescape(s)` / `strip(html)` | 텍스트 처리 |
| `Park.crypto.md5Hex(text \| text[])` | MD5, 일괄 계산을 위해 배열을 전달할 수 있습니다 |
| `Park.crypto.sha256Hex` / `hmacSha256Hex(key, text)` / `aesEcbDecrypt(base64, key)` / `uuid()` | 빠른 기본 구현 |
| `Park.utils.rateLimiter(ms)` | `wait()`를 반환하여 두 요청 간의 최소 간격을 보장합니다. |
| `Park.utils.mapLimit(items, n, fn)` / `lruMap(n)` / `parseCount('1.2万')` / `formatDate(ts)` | 기타 일반적으로 사용되는 도구 |
| `Park.error(code, message)` | 오류 코드와 함께 오류가 발생합니다. 아래를 참조하세요 |

### `http.request(opts)`

```js
await this.http.request({
  url, method: 'GET', headers: {}, params: { q: 'x' },   // 매개변수는 URL에 연결됩니다.
  json: {...} | form: {...} | body: 'raw',
  timeout: 15000,
  responseType: 'text' | 'base64',
});
// → { status, headers, body, url, ok, json() }
```

`text()` / `json()`은 2xx가 아닌 응답에서 자동으로 오류를 던집니다(404 → `NOT_FOUND`). Cookie는 자동 저장되며 리디렉션 대상 주소마다 다시 선택됩니다. 다른 출처로 리디렉션할 때 원래 인증 헤더를 전달하지 않으며, 요청 본문을 유지하는 다른 출처 리디렉션은 거부됩니다.

## 데이터 구조

**목록 페이지** (반환 값 `feed` / `search`)

```js
{
  items: [WorkItem], page: 1, totalPages: 20, total: 500,
  hasNext: true,
  cursor: '12345',        // 선택 사항: 커서가 페이지를 넘기는 사이트(예: E-Hentai)는 다음 페이지 커서를 반환하고 앱은 다음에 요청할 때 이를 그대로 반환합니다.
}
// 또는 섹션 레이아웃(피드 레이아웃이 '섹션'인 경우):
{ sections: [{ title: 'Latest chapters', items: [WorkItem] }], hasNext: false }
```

**작업 항목**: `{ id, title, subtitle?, cover, coverAspect?, pages?, rating?, likes?, views?, language?, category?, badge?, badgeColor?, duration?, uploaded?, tags? }`

- `coverAspect`(너비/높이)는 점프를 방지하기 위해 이미지가 로드되기 전에 그리드 레이아웃을 만듭니다.
- `badgeColor` 카테고리 라벨에 사용되는 색상입니다(예: E-Hentai 각 카테고리의 전통적인 색 구성표).

**세부정보** (`detail`): 다음을 추가로 포함하는 WorkItem의 모든 필드

```js
{
  url, authors: [], description, uploader?, size?, comments?,
  tags: [{ namespace: 'artist', label: 'Author', tags: [{ name, keyword, filters?, count? }] }],
  chapters: [{ id, title }] | null,   // null은 단일 장을 나타냅니다.
  singleChapterId?,                   // 단일 챕터 작업에 필요한 챕터 ID(예: Bika의 경우 "1")
  thumbnails?: [url | {url, width, height, offsetX, offsetY}],   // 스프라이트 이미지 지원
  related?: [WorkItem], series?: [WorkItem],
}
```

태그를 클릭하면 앱이 소스에서 `keyword` 및 `filters`를 검색하므로 태그를 사이트의 기본 구문(예: `artist:"xxx"`) 또는 필터 매개변수(예: Hanime1/`tags[]`).

**챕터** (`chapter`)

```js
{ pages: [
  { url, headers?, fallbacks?: [url], width?, height?, transform? },  // 주소가 알려져 있습니다
  { token: '12' },                                                      // 지연된 해결: 앱이 ResolveImage를 호출합니다.
]}
```

- `fallbacks`: 백업 미러, 기본 주소가 실패하면 순차적으로 시도합니다.
- `transform: { type: 'unscramble-strips', segments: N }`: 이미지를 가로로 N 스트립으로 자르고 역순으로 저장하면(JMComic) 앱이 GPU에서 기본적으로 복원됩니다. 다운로드한 오프라인 파일은 원본 이미지를 저장하고 표시 시 복원합니다.
- `resolveImage`는 `{ url, headers?, width?, height?, cacheKey? }`를 반환합니다. 실패하면 앱은 `retry`를 증가시키고 다시 호출하며 소스는 이를 사용하여 서버를 변경할 수 있습니다(`nl` 매개변수) E-Hentai).

**동영상**(`videos`): `[{ quality: 1080, label: '1080P', url, headers?, format?, preferred? }]`. 동영상 직접 링크에는 일반적으로 시간 제한이 있으며 앱은 재생/다운로드하기 전에 매번 이를 다시 얻습니다.

- 영상 소스는 `detail(id).chapters`에 재생 순서의 `[{id, title}]`을 반환합니다. 각 `id`는 안정적인 식별자여야 하며 화질명이나 임시 미디어 URL을 사용하면 안 됩니다. 앱은 같은 ID로 회차 선택, 개별 진행 상황, 다운로드와 이어보기를 관리하고 `videos(id, episodeId = '_')`로 해당 회차를 가져옵니다. 단일 영상은 `singleChapterId`를 사용하며 생략하면 `'_'`입니다.
- `format`을 생략하면 기존의 직접 MP4 재생 및 다운로드 경로를 사용합니다. HLS 항목은 `format: 'hls'`를 명시하고 manifest에 아래의 `media` 권한을 선언해야 합니다.
- HLS 마스터 재생목록(`#EXT-X-STREAM-INF`)은 먼저 호스트가 각 화질의 독립적인 세그먼트 재생목록으로 펼치고 `RESOLUTION`에서 실제 화질을 얻은 뒤 플레이어나 다운로더에 전달합니다. 마스터를 반환할 때 `quality`는 원하는 화질을 뜻하며, 기본적으로 해당 값 이하에서 가능한 가장 높은 화질을 선택합니다. 해당 항목이 없으면 최고 화질을 선택합니다. 각 변형은 오디오와 비디오가 함께 다중화된 MPEG-TS여야 합니다. 별도 `AUDIO`, `VIDEO`, `SUBTITLES` renditions와 `media.domains` 밖의 주소는 거부합니다.
- 확장된 HLS는 `#EXT-X-ENDLIST`가 있는 완전하고 연속적인 MPEG-TS VOD만 지원합니다. `METHOD=AES-128`, `KEYFORMAT=identity`(생략 시에도 identity)의 CBC/PKCS7 복호화를 지원합니다. 키는 정확히 16바이트이고 IV는 명시적인 128비트 값 또는 세그먼트 미디어 시퀀스에서 생성합니다. 키는 세션 메모리에만 보관하며 복호화한 TS는 재생과 다운로드의 공통 처리 과정에서 검증합니다. 라이브, SAMPLE-AES, 다른 KEYFORMAT, `EXT-X-MAP`, `EXT-X-BYTERANGE`, fMP4, discontinuity와 gap은 지원하지 않습니다. MissAV의 비표준 `#EXT-X-TOKEN`은 제거합니다.
- 재생 시 `127.0.0.1`에만 바인딩한 무작위 포트와 토큰을 사용하며, 유한한 URL 등록 목록에서 검증된 세그먼트를 필요할 때 가져옵니다. 세션을 닫으면 요청을 취소합니다. HLS 오프라인 다운로드는 현재 Android에서만 지원합니다. 각 세그먼트를 검증하고 SHA-256을 저장하며 재개 시 다시 검증합니다. 취소를 지원하며, 마지막에 기기의 Media3로 MP4를 리먹싱한 후 완성된 파일만 오프라인 라이브러리에 등록합니다. iOS/macOS의 HLS 재생은 이번에 검증하지 않았으므로 검증된 기능으로 표기할 수 없습니다.

## 옵션 정의

`feeds[].options`, `searchFilters`, `settings`는 동일한 형식을 사용합니다.

```js
{ key: 'sort', label: 'Sort', type: 'select', default: 'date',
  values: [{ value: 'date', label: 'Latest' }, { value: 'popular', label: 'Popular', color: '#f00' }] }
// type: select (단일 선택) | multi (다중 선택) | number | text | password | switch
// settings에서는 values 대신 options를 사용할 수도 있습니다.
```

`feeds`의 각 항목은 소스 페이지 `{ key, label, layout?: 'grid' | 'sections', options?: [...] }`의 탭입니다.

`defaultFeed`는 소스 페이지를 열 때 처음 표시할 탭을 지정합니다. 값을 생략하거나 해당 key를 찾을 수 없으면, App은 key에 `promote` / `recommend` / `featured`가 포함된 추천 탭, `rank` / `toplist`가 포함된 순위 탭, `popular` / `hot` / `trending`이 포함된 인기 탭 순으로 선택합니다. 일치하는 탭이 없으면 첫 번째 탭을 엽니다.

## 네트워크

- `network.mode: 'native'`(기본값): 영구 쿠키를 사용하는 기본 HTTP 요청은 사용자가 설정한 프록시를 통과할 수 있습니다. Cloudflare 쿼리가 감지되면 `CLOUDFLARE`가 발생합니다. 앱은 사용자에게 내장된 브라우저에서 확인을 완료하고 공통 쿠키를 기본 요청과 다시 동기화하도록 안내합니다.
- `network.mode: 'browser'` + `network.origin`: 실제 브라우저 지문을 사용하여 `origin`에서 열린 숨겨진 브라우저 페이지에서 원본 `fetch()`로 요청이 이루어졌습니다. 더욱 강력하게 보호되는 Cloudflare 사이트에 적용됩니다(예: Hanime1). 동일 출처 GET 요청에서 Cloudflare 인증 응답을 받으면 숨겨진 브라우저가 해당 문서로 이동하여 자동 인증한 뒤 원래 요청을 한 번 재시도합니다. 인증에 실패하면 `CLOUDFLARE`를 반환하고 기존 인증 절차를 사용합니다.

## 미디어 권한 (HLS)

`media` 권한은 `this.http`, `network`, 사이트 Cookie 동기화와 별개이며 두 전송 방식은 같은 도메인 규칙을 적용합니다.

```js
domains: ['example.com'],
network: { mode: 'native' },
media: { mode: 'native', origin: 'https://example.com', domains: ['media.example.com'] },
```

- `media.mode`는 `'native'`와 `'browser'`를 지원합니다. 둘 다 `media.origin`이 소스가 선언한 사이트에 속하고 HTTPS 기본 포트 443을 사용해야 하며 URL 인증 정보, 쿼리나 프래그먼트를 포함할 수 없습니다.
- `media.domains`는 하위 도메인을 포함하는 독립적인 미디어 허용 목록이며 사이트 Cookie 접근 권한을 부여하지 않습니다. 재생목록, 세그먼트와 키는 HTTPS 443만 허용합니다. URL 인증 정보, 프래그먼트, IP 주소, localhost(하위 도메인 포함)와 `.local`은 거부합니다.
- `media.mode: 'native'`는 인증 정보 없는 별도 네이티브 클라이언트를 사용하며 사이트 Cookie, Authorization과 프록시 인증을 전송하지 않습니다. 리디렉션은 각 대상 주소를 허용 목록으로 검증한 뒤 따라갑니다. `Referer`, `Origin`, `Accept`, `Accept-Language` 헤더만 허용하며 앞의 두 헤더는 `media.origin`과 일치해야 합니다.
- `media.mode: 'browser'`는 `media.origin`의 숨겨진 브라우저에서 세션을 만들고 `credentials: 'omit'`, `mode: 'cors'`, `redirect: 'error'`를 사용합니다. CDN의 CORS 규칙을 따르며 리디렉션하지 않습니다.
- 스트리밍 중 응답 크기를 제한하고 응답 URL을 다시 검증합니다. 재생목록은 최대 2 MiB, 세그먼트는 최대 32 MiB이며 AES-128 키는 정확히 16바이트여야 합니다. 초과, 빈 응답과 허용되지 않은 URL은 거부합니다. 소스 `domains`와 Cookie를 사용하는 `network` 규칙은 별개로 유지됩니다.

## 격리 및 보안

- 각 소스는 **독립적인** JS 환경(각각 인터페이스가 없는 WebView가 있음)에서 실행되며 소스는 서로의 전역 개체를 볼 수 없습니다. 네이티브 브리지는 호출이 어떤 환경에서 왔는지만 인식하며 스크립트는 다른 소스를 가장할 수 없습니다.
- 각 소스에는 독립적인 쿠키 항아리가 있습니다. 소스에서 발행한 요청은 자체 쿠키만 가져와 저장하며 다른 소스의 로그인 상태는 읽지 않습니다.
- `domains`는 소스가 속한 사이트를 선언합니다. (도메인명은 등록 가능, 서브도메인명은 자동으로 포함됩니다.) 이러한 사이트의 쿠키만 내장 브라우저(Cloudflare 인증, 웹 로그인에 의해 공유됨)와 동기화되며 브라우저 모드의 `network.origin`도 해당 쿠키에 속해야 합니다. 생략할 경우 `homepage`, `network.origin`, `account.cookieUrl/loginUrl`에서 추론합니다.
- 웹사이트나 웨어하우스에서 소스를 설치하는 경우 앱은 인터넷 연결이 불가능한 샌드박스의 스크립트 정보를 먼저 읽어서 사용자에게 이름, 버전, SHA-256, 선언된 사이트 및 위험 경고를 표시한 후 확인 후 설치합니다. 소스웨어하우스의 `index.json` 항목에는 `sha256` 필드가 포함될 수 있으며, 다운로드 내용이 일치하지 않을 경우 설치가 거부됩니다.

## 계정

```js
account: {
  type: 'password' | 'cookies',
  title, hint, required: false,
  fields: [{ key: 'email', label: 'Email' }, { key: 'password', label: 'Password', secret: true }],
  loginUrl?, cookieUrl?, requiredCookies?: ['ipb_member_id'],   // 쿠키를 제공한 후 웹페이지에 로그인하면 앱이 자동으로 쿠키를 얻습니다.
  async login(values) { return { name } },
  async logout() {},
  async status() { return { loggedIn, name, configured } },
  managedAccount: true,                 // 선택 사항: 전용 자동 유지 관리 계정 제공
  async enableManaged() {},             // 사용자가 등록을 확인한 후에만 호출됩니다.
}
```

`configured`는 현재 로그인 성공 여부와 관계없이 계정이 구성되었음을 나타냅니다. `managedAccount: true`는 소스가 전용 자동 유지 관리 계정을 지원한다고 선언합니다. 소스 설정은 동일한 이름의 `managedAccount` 스위치를 사용합니다. 호스트는 활성화 설정을 저장하고 `account.enableManaged()`를 호출하기 전에 먼저 자동 등록 지침을 표시하고 사용자 확인을 얻어야 합니다. 실패 또는 애플리케이션 재시작 후 동일한 계정이 복원될 수 있도록 등록 전에 후보 자격 증명을 저장하고 `await this.store.flush()`를 사용해야 합니다.

PicACG 예시에서는 수동 자격 증명과 전용 계정을 별도로 저장하며, 기존 수동 계정을 전용 계정으로 덮어쓰면 안 됩니다. 전용 계정을 유지하려면 스위치를 끄고 재사용하려면 다시 켜십시오. 토큰이 만료되면 다시 로그인만 가능하고 다시 등록할 수 없습니다. 등록이 실패하거나 응답이 손실되면 중복 계정 생성을 방지하기 위해 원래 후보 계정을 다시 시도하십시오. 계정 비밀번호, 토큰, 소스 상태는 모두 사용자 로컬 데이터입니다. 문서 및 로그에 실제 자격 증명을 출력하지 마십시오.

## 국제화

애플리케이션 인터페이스 지원 `zh-Hans`, `zh-Hant`, `ja`, `ko`, `en`, `es`, `ru`, `ar`. 머티리얼, Cupertino 및 시스템 컨트롤은 해당 언어를 사용합니다. 아랍어 인터페이스는 오른쪽에서 왼쪽으로 이동합니다. 인터페이스 언어 설정은 즉시 적용되며 지속적으로 저장됩니다. 기본적으로 시스템을 따릅니다. 중국어 스크립트 및 지역에 따라 중국어 간체 또는 번체를 사용할지 여부가 결정됩니다.

Flutter 인터페이스는 `tr('已选 {count}', {'count': count})` 또는 `context.tr`를 균일하게 호출합니다. 메시지의 원본 중국어 텍스트는 리소스 키로 사용되며 매개변수는 `{name}`이며 8개 언어 리소스는 다음 위치에 있습니다. `assets/i18n/`. 표시되는 복사본을 추가하거나 수정할 때 모든 리소스는 동시에 업데이트되어야 하며 자리 표시자는 일관되어야 합니다. 플러그인의 정적 이름, 설명, 검색 레이블, 옵션 및 오류 프롬프트는 애플리케이션이 표시될 때 리소스 매핑됩니다. 원격 작업의 제목, 작성자, 태그, 사용자 입력 및 지속성 프로토콜 키는 원본 텍스트로 유지됩니다.

## 오류 코드

`throw Park.error(code, message)`를 사용하여 오류를 발생시키면 앱은 오류 코드에 따라 해당 지침을 제공합니다.

| 코드 | 앱 처리 |
|------|------------|
| `CLOUDFLARE` | "확인으로 이동" 버튼: 내장 브라우저 열기 |
| `LOGIN_REQUIRED` | "로그인으로 이동" 버튼: 소스 설정의 계정 영역 열기 |
| `NOT_FOUND` | "콘텐츠가 존재하지 않습니다" 표시 |
| `BLOCKED` | "액세스 제한됨"(예: IP 차단, 할당량 소진)이 표시되고 사진이 다시 시도되지 않습니다. |
| `NETWORK` / `HTTP` / `PARSE` | "재시도" 버튼으로 오류 메시지 표시 |

## 소스 창고

저장소는 정적 호스팅(예: GitHub 원시)에 배치할 수 있는 `index.json`입니다. 사용자는 "소스 사이트 관리 → 소스 추가"에 창고 주소를 입력하여 탐색, 설치 및 업데이트할 수 있습니다.

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

`url`는 스크립트의 전체 주소입니다. `index.json`와 관련하여 `file`를 사용할 수도 있습니다. 타사 창고는 사용자 확인 후 수동으로 설치됩니다. `sha256`는 선택사항입니다. 다운로드한 콘텐츠는 제공 시 검증됩니다.

공식 자동 업데이트는 엄격한 규칙을 채택합니다. 버전은 점으로 구분되고 앞에 0이 없는 3개의 세그먼트로 구성된 음수가 아닌 정수여야 합니다(예: `0.0.1`, `0.1.0`). 이는 세그먼트별로 번호별로 비교됩니다. 누락된 세그먼트, 여러 세그먼트 또는 시험판 접미사는 허용되지 않습니다. 스크립트 `sha256`의 원래 UTF-8 텍스트는 공백을 자르거나 줄 바꿈을 변환하지 않고 제공되어야 합니다. 스크립트에서 선언된 `key` 및 `version`는 인덱스와 일치해야 합니다. `apiVersion`는 현재 앱 런타임과 완전히 일치해야 합니다. 일치하지 않을 경우 자동 업데이트가 거부됩니다. 먼저 이 API를 지원하는 앱을 사용해야 합니다. 호환되는 분기가 제공되지 않습니다.

### 앱 공식 업데이트

"Origin Site Management"는 기본적으로 "공식 소스 자동 업데이트"를 켜고 시작하거나 포그라운드로 돌아갈 때 12시간마다 확인합니다. 실패하면 잦은 재시도를 피하기 위해 확인 시간도 기록됩니다. 자동 업데이트를 끈 후에도 지금 업데이트 확인을 계속 사용할 수 있습니다. 설치된 내장 소스와 공식 온라인 소스만 업그레이드합니다. 새로운 소스를 자동으로 설치하지 않으며, 사용자가 설치한 동일한 이름의 타사 소스를 인수하지도 않습니다.

설치 중에 ID, 버전, API 및 다이제스트를 확인하고 업데이트를 완료하기 전에 초기화 및 상태 지속성이 성공할 때까지 기다립니다. 이전 스크립트 및 사용자 상태를 유지하지 못했습니다. 설치 중에 애플리케이션이 중단되면 다음에 시작할 때 복원됩니다. 새로운 온라인 버전은 내장 스크립트의 이전 버전이나 동일한 버전보다 우선하며, 새 설치 패키지는 더 높은 버전이 있을 때 정상적으로 업그레이드될 수 있습니다. "내장 소스 복원"은 현재 설치 패키지 버전으로 적극적으로 롤백할 수 있습니다. 나중에 자동 업데이트를 켜면 계속해서 공식 새 버전을 받을 수 있습니다.

### 공식 소스 공개

공식 소스는 공용 주 창고 [drdon1234/Hentai-Park](https://github.com/drdon1234/Hentai-Park)를 따르며 클라이언트의 고정 입구는 다음과 같습니다.

```text
https://raw.githubusercontent.com/drdon1234/Hentai-Park/sources/index.json
```

`assets/sources/index.json`는 유지되는 유일한 소스 목록이고, `file`는 동일한 디렉터리에 있는 유일한 스크립트 소스 코드를 가리킵니다. 파일 이름은 `[A-Za-z0-9_-]+.js`를 준수해야 합니다. 파일 이름 본문의 하위 디렉터리, 기호 링크 또는 점은 허용되지 않으며 클라이언트의 공식 소스 주소 확인과 일치해야 합니다. `tools/publish_sources.mjs` 게시 인덱스 생성: 각 레코드에는 `key`, `name`, `version`, `description`, `url`, `sha256` 및 `apiVersion`. 스크립트 URL은 이 소스 코드의 전체 40자리 커밋 번호로 고정되어 있습니다.

```text
https://raw.githubusercontent.com/drdon1234/Hentai-Park/<源码提交 SHA>/assets/sources/<file>
```

`sources` 분기는 스크립트를 복사하거나 두 번째 소스 목록을 수동으로 유지 관리하지 않고 생성된 루트 디렉터리 `index.json`만 저장합니다. 스크립트를 업데이트할 때 스크립트의 버전과 매니페스트를 동시에 업그레이드해야 합니다. 게시자는 버전 다운그레이드를 거부하고 동일한 버전이 다른 스크립트 콘텐츠에 해당하는 것을 거부합니다. 동일한 버전은 내용이 변경되지 않은 상태로 반복적으로 게시될 수 있으며 일반 업그레이드는 이전 인덱스 버전의 영향을 받지 않습니다.

게시자는 Node.js 기본 제공 모듈에만 의존하며 Node.js 22 이상에서는 오프라인으로 실행할 수 있습니다. 매니페스트, 파일 존재 및 디렉터리 경계를 확인하고, 네트워크 또는 스토리지 인터페이스를 제공하지 않는 별도의 컨텍스트에서 공유 런타임 및 스크립트를 로드하고, 앱 설치 미리 보기 `key`와 동일한 `Park.__pending` / `Park.manifest` 프로브를 사용하여 확인합니다. `version` 및 API. 탐지는 `setup`, `init`, 로그인 또는 사이트 비즈니스 메서드를 호출하지 않으며 원본 사이트 네트워크 사용성 테스트를 대체할 수 없습니다.

로컬 미리보기 예(출력은 `test/`에 있으며 무시되어 게시되지 않습니다. 커밋 번호는 해당 소스 코드의 실제 SHA를 사용해야 합니다):

```powershell
node tools/publish_sources.mjs --commit '<完整 40 位源码提交 SHA>' --output 'test/official-source-index.json'
```

기존 릴리스를 확인해야 하는 경우 `--previous '旧索引本地路径'`를 전달합니다. 이전 인덱스가 유효하지 않아 확인에 실패하면 버전 보호가 자동으로 건너뛰지 않습니다. 작업공간에 커밋되지 않은 수정 사항이 있는 경우 로컬 결과는 미리 보기에만 사용됩니다. 공식 릴리스는 워크플로에서 체크아웃한 소스 코드를 제출하여 생성됩니다.

`.github/workflows/publish-sources.yml` 기본 저장소 기본값 `main` 분기 관련 파일이 푸시되거나 `main`에서 수동으로 트리거되는 경우에만 실행됩니다. 워크플로는 순차적으로 실행되며 최신 `main`는 다음에서 체크아웃됩니다. 각 작업의 시작과 스크립트 주소 및 릴리스 기록은 실제 체크아웃된 커밋 번호로 고정됩니다. 작업이 실행되는 동안 후속 문서 제출은 게시를 방해하지 않습니다. 후속 소스 파일 제출은 다음 직렬 작업을 트리거합니다. 워크플로는 먼저 기존의 안정적인 인덱스를 다운로드하고 모든 오프라인 확인을 완료한 다음 일반 Git을 사용하여 원자 업데이트를 `sources` 분기에 푸시합니다. `sources` 분기에서 확인이 실패하거나 동시 변경이 발생하면 온라인 인덱스를 덮어쓰지 않습니다. 안정적인 색인 없이 처음으로 출판물을 만들 수 있습니다. 릴리스에서는 스크립트와 인덱스가 위의 검증을 통과했음을 나타냅니다. 사이트 액세스, 계정 로그인, 이미지 또는 비디오 로딩은 여전히 ​​별도로 확인해야 합니다.
