[简体中文](../../SOURCE_API.md) · [繁體中文](../zh-Hant/SOURCE_API.md) · [日本語](../ja/SOURCE_API.md) · [한국어](SOURCE_API.md) · [English](../en/SOURCE_API.md) · [Español](../es/SOURCE_API.md) · [Русский](../ru/SOURCE_API.md) · [العربية](../ar/SOURCE_API.md)

# 소스 플러그인 개발 가이드

HentaiPark의 각 출처는 별도의 JavaScript 파일입니다. 앱은 런타임에 이를 로드합니다. 앱을 다시 컴파일하지 않고도 소스 저장소에서 설치, 업데이트, 활성화/비활성화할 수 있습니다.
내장 소스는 [`assets/sources/`](../../../assets/sources/)에 있으며 예제 참조로 직접 사용할 수 있습니다.

## 실행 환경

- 소스 스크립트는 앱 내의 헤드리스 WebView에서 실행됩니다(`DOMParser`가 포함된 완전한 최신 JS). 네트워킹, 암호화 및 쿠키는 모두 기본 레이어에서 제공되므로 CORS 제한이 없습니다.
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
  async videos(id) {},                        // 동영상
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

`text()` / `json()`는 2xx가 아닌 응답이 발생하면 자동으로 오류(404 → `NOT_FOUND`)를 발생시킵니다. 쿠키는 자동으로 저장되며 리디렉션을 따를 때 지속됩니다.

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

**동영상**(`videos`): `[{ quality: 1080, label: '1080P', url, headers?, preferred? }]`. 동영상 직접 링크에는 일반적으로 시간 제한이 있으며 앱은 재생/다운로드하기 전에 매번 이를 다시 얻습니다.

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
- `network.mode: 'browser'` + `network.origin`: 실제 브라우저 지문을 사용하여 `origin`에서 열린 숨겨진 브라우저 페이지에서 원본 `fetch()`로 요청이 이루어졌습니다. 더욱 강력하게 보호되는 Cloudflare 사이트에 적용됩니다(예: Hanime1).

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

웨어하우스는 `index.json`이며, 모든 정적 호스팅(예: GitHub raw)에 배치할 수 있습니다.

```json
{ "name": "Example source repository", "sources": [
  { "key": "mysite", "name": "Example Source", "version": "0.0.1", "type": "comic", "file": "mysite.js", "description": "…" }
] }
```

`file`는 `index.json`에 대한 상대 경로입니다(전체 `url`를 작성할 수도 있음). 사용자는 "소스 사이트 관리 → 소스 추가"에서 창고 주소를 입력하여 찾아보고 설치하고 업데이트할 수 있습니다.

자동 유지 관리 계정에 오류가 발생하면 오류 횟수와 다음 재시도 시간을 저장하고 백오프 간격으로 재시도해야 합니다. 현재 제한 기간 동안에는 중복 등록이나 로그인이 허용되지 않습니다. 적극적으로 재시도하는 사용자는 원래 계정을 계속 재사용하며 서버측 현재 제한을 건너뛸 수 없습니다.
