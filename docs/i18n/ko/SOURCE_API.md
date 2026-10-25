[简体中文](../../SOURCE_API.md) · [繁體中文](../zh-Hant/SOURCE_API.md) · [日本語](../ja/SOURCE_API.md) · [한국어](SOURCE_API.md) · [English](../en/SOURCE_API.md) · [Español](../es/SOURCE_API.md) · [Русский](../ru/SOURCE_API.md) · [العربية](../ar/SOURCE_API.md)

# 사이트 플러그인 API

[빠른 시작](#빠른-시작) · [manifest 필드](#manifest-필드) · [메서드](#메서드) · [런타임 API](#런타임-api) · [오류 코드](#오류-코드) · [다국어](#다국어) · [배포](#배포)

HentaiPark의 각 사이트는 독립된 JavaScript 플러그인입니다. 앱은 실행 중에 플러그인을 불러오며, 저장소에서 설치·업데이트·켜기·끄기를 **앱을 다시 빌드하지 않고** 할 수 있습니다. 공식 플러그인은 [`assets/sources/`](../../../assets/sources/)에 있으며 예제로 바로 참고할 수 있습니다.

이 문서는 중국어 간체판이 기준입니다. 사이트 고유의 규칙은 플러그인에 두고, 통신·캐시·이미지 같은 공통 기능은 프레임워크가 제공합니다. 프레임워크는 사이트 이름으로 예외를 두지 않습니다.

## 빠른 시작

### 실행 환경

- 플러그인은 앱 안의 헤드리스 WebView에서 실행되며 최신 JS와 `DOMParser`를 쓸 수 있습니다. 네이티브 계층이 암호화, 쿠키, 네이티브 HTTP를 제공합니다. 네이티브 HTTP에는 CORS 제한이 없고, 브라우저 통신과 미디어는 아래의 별도 규칙을 따릅니다.
- 각 플러그인의 런타임은 사이트를 처음 쓸 때 시작되고, 약 5분간 쓰이지 않거나 동시에 6개를 넘으면 해제됩니다. manifest는 '스크립트 SHA-256 + 런타임 버전'으로 캐시되므로 앱을 켤 때 플러그인을 실행하지 않습니다. 앱이 시작되자마자 플러그인이 돌고 있다고 가정하지 마세요.
- 같은 런타임([`assets/runtime/park_runtime.js`](../../../assets/runtime/park_runtime.js))이 Node에서도 동작하므로 개발 중에 실제 사이트로 확인할 수 있습니다. Node 호스트는 개발용이며 신뢰할 수 없는 스크립트를 위한 샌드박스가 아닙니다.

### 가장 작은 플러그인

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

### Node에서 실행해 보기

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

## manifest 필드

```js
Park.register({
  key: 'mysite',              // 고유하며 바꿀 수 없음. [A-Za-z0-9_-]만, 1~100자, _app 불가
  name: '我的站点',
  version: '0.0.1',
  minAppVersion: '0.9.2',           // 숫자 세 개. 저장소 버전이 더 높으면 업데이트를 안내
  type: 'comic',              // comic | video | novel | game: 읽기·재생 방식을 결정
  category: 'doujin',         // doujin | anime | aiDrama | jav | adult | shortvideo | recording | live | gallery | illustration | novel | game | other
  color: '#E5355F',           // 브랜드 색: 사이트 아이콘과 사이트 페이지
  description: '一句话介绍',
  homepage: 'https://example.com',
  domains: ['example.com'],                   // 소속 사이트. '격리와 보안' 참고. 생략하면 homepage 등에서 추정
  linkPatterns: ['example\\.com/g/(\\d+)'],   // 붙여 넣은 링크로 작품 바로 열기. 첫 그룹이 작품 ID
  idPattern: '^(\\d+)$',                      // 입력한 번호로 작품 바로 열기
  imageHeaders: { Referer: 'https://example.com/' },  // 표지와 이미지의 기본 헤더
  network: { mode: 'auto', vpnHint: true },  // '네트워크' 참고
  media: { mode: 'browser', origin: 'https://example.com', domains: ['media.example.com'] },  // 동영상과 직접 파일의 미디어 권한
  imageNetwork: { mode: 'browser', origin: 'https://img.example.com', domains: ['img.example.com'] }, // 선택
  imageDecrypt: { /* 선택. '암호화된 이미지' 참고 */ },

  settings: [ /* 옵션. '옵션 정의' 참고 */ ],
  account: { /* 선택. '계정' 참고 */ },
  defaultFeed: 'ranking',     // 사이트 페이지에서 처음 여는 탭 (feeds의 key)
  feeds: [ /* 사이트 페이지 탭 */ ],
  searchFilters: [ /* 검색 필터 */ ],
  searchHint: '搜索技巧提示',
  i18n: { /* 플러그인 자체 UI 번역. '다국어' 참고 */ },

  subscription: { /* 선택: 채널·창작자 구독. '구독' 참고 */ },
  postShortVideos: true,
  updateSubscriptions: { /* 선택: 업데이트 구독. '업데이트 구독' 참고 */ },

  async init() {},              // 선택: 런타임 시작 시 한 번 호출 (도메인 목록 갱신 등)
  async onSettingsChanged() {}, // 선택: 사용자가 사이트 설정을 바꾼 뒤 호출
  // 그리고 '메서드'의 각 메서드
});
```

기능(`capabilities`)은 구현한 메서드를 보고 런타임이 자동으로 내보냅니다. 직접 쓰지 마세요.

### 유형과 분류

`type`은 작품의 읽기·재생·게임 자료 처리를, `category`는 탐색, 사이트 관리, 검색에서의 분류를 결정합니다. 알 수 없거나 선언하지 않은 분류는 '기타'로 들어갑니다. 새 사이트는 유형, 분류, 기능을 정확히 선언해야 합니다.

| 분류 | 의미 |
| --- | --- |
| `doujin` | 동인지와 만화 |
| `gallery` | 실사 갤러리: 코스프레, 사진 및 실사 이미지 모음. 이미지 사이트는 `type: 'comic'`을 사용하며 이미지 모음 하나가 작품 하나입니다. `chapter()`가 이미지를 순서대로 반환하고 읽기·즐겨찾기·다운로드를 공용으로 사용합니다. 장수나 수위로 분류하지 않습니다 |
| `illustration` | 일러스트 갤러리: 일러스트 및 애니메이션 이미지. 이미지 사이트는 `type: 'comic'`을 사용하며 이미지 모음 하나가 작품 하나입니다. `chapter()`가 이미지를 순서대로 반환하고 읽기·즐겨찾기·다운로드를 공용으로 사용합니다. 장수나 수위로 분류하지 않습니다 |
| `anime` | 성인 애니메이션 |
| `aiDrama` | AI 숏드라마. 예전 `drama` 값은 받지 않습니다. 사이트 자체의 채널 이름은 그대로 선언하며, 앱의 분류로 사이트 채널을 거르지 않습니다 |
| `jav` | JAV 전문 사이트 |
| `adult` | 종합 성인 동영상 (Pornhub, XVideos, 91porn 등), `type: 'video'`. 분류는 묶음일 뿐 사이트 태그나 사용자 필터를 대신하지 않습니다 |
| `shortvideo` | 짧은 동영상: 전체 화면 세로 피드 (아래 참고) |
| `recording` | 다시보기 영상(주문형 재생), `type: 'video'` |
| `live` | 라이브, `type: 'video'` |
| `novel` | 소설, `type: 'novel'` |
| `game` | 게임, `type: 'game'` |
| `other` | 크리에이터 커뮤니티 |

- **짧은 동영상** (`type: 'video', category: 'shortvideo'`): 작품, 검색, 즐겨찾기, 기록에서 바로 피드로 들어갑니다. 작품 하나가 동영상 하나이며 `videos(id, '_')`가 현재 미디어를 반환하고 상세 페이지는 필요 없습니다. `feed`의 `hasNext`와 `cursor`로 끝에 가까워지면 자동으로 다음 페이지를 불러옵니다. 커서에 인증 정보나 미디어 서명을 넣으면 안 됩니다. 새로고침하면 첫 페이지부터 시작하며, 보고 있는 항목은 재생하고 다음 항목은 일시 정지 상태로 미리 불러오며 나머지는 해제합니다. 검색이 없는 사이트는 `search`를 선언하지 않습니다.
- **게시물 동영상 모드** (`postShortVideos: true`): 사이트와 구독 대상 페이지에서 `media[]`의 동영상 첨부를 각각 재생합니다. 직접 `url` 또는 비어 있지 않은 `episodeId`가 필요하며, 지연 해석은 재생·미리 읽기 시 `videos(원본 게시물 ID, episodeId)`를 호출합니다. 웹 페이지를 미디어 URL로 쓰지 않습니다. 이미지는 재생하지 않고 첨부는 `preview`, `format`, `headers`를 지원합니다. 페이지 이동과 새로 고침은 현재 feed·필터 또는 대상의 `subscription.posts` 범위를 유지합니다. 재생은 첨부별로 구분하고 즐겨찾기·기록·원본 사이트 상호작용은 원본 게시물 ID를 씁니다. 분류는 바뀌지 않으며 별도 무작위 영상 API를 뜻하지 않습니다.
- **원본 사이트에서만 재생되는 모음 사이트**: `type: 'video', category: 'adult'`를 그대로 선언하고, 검증된 미디어 API가 없으면 `videos`를 구현하지 않으며 런타임은 `capabilities.videos: false`를 내보냅니다. 상세 페이지의 주 버튼은 `detail.url`을 시스템 브라우저로 열고, 재생·다운로드·회차를 숨기며, 가짜 챕터를 저장하거나 챕터 업데이트를 확인하지 않습니다. 즐겨찾기와 기록은 그대로 쓸 수 있습니다.
- **소설**과 **게임**은 '메서드'에서 설명합니다.

`defaultFeed`는 **추천 > 순위 > 인기** 순으로 고르고, 사이트에 이런 입구가 정말 없을 때만 최신 페이지 등 유효한 입구를 씁니다. 검증하지 않은 API를 만들어 내면 안 됩니다. 비어 있거나 key를 찾지 못하면 앱이 key로 자동 선택합니다 (`promote` / `recommend` / `featured`, 다음 `rank` / `toplist`, 다음 `popular` / `hot` / `trending`). 없으면 첫 탭입니다.

익명 접근은 가능하지만 추천에 로그인이 필요한 소스는 `anonymousDefaultFeed: 'ranking'`을 선언합니다. `feeds`에서 실제 익명 접근이 확인된 항목을 지정하고 순위를 우선합니다. 홈과 사이트 화면은 로그아웃 상태에서 이 항목을, 로그인 상태에서 `defaultFeed`를 사용하며 사용자가 직접 선택한 탭은 유지합니다. 빈 목록이나 네트워크 오류를 무조건 익명 상태로 판단하지 마세요.

### 옵션 정의

`feeds[].options`, `searchFilters`, `settings`는 같은 형식을 씁니다.

```js
{ key: 'sort', label: '排序', type: 'select', default: 'date',
  values: [{ value: 'date', label: '最新' }, { value: 'popular', label: '热门', color: '#f00' }] }
// type: select | multi | number | text | password | switch
// settings에서는 values 대신 options를 써도 됨
```

`feeds`의 각 항목은 사이트 페이지의 탭입니다: `{ key, label, options?: [...] }`.

### 공통 필터 및 정렬

플러그인은 Feed별로 `commonFilters`, 검색용으로 `searchCommonFilters`를 선언합니다. 앱은 선언된 기능만 표시하며 이미 불러온 작품 정보로 필터를 근사하지 않습니다. 조건은 실제 사이트 검색에 매핑하고 페이지를 넘겨도 유지해야 합니다. 차원은 `pages`, `likes`, `duration`이며, `range: true` 또는 배열로 지원하는 `min`/`max` 경계를 선언하고 `sort: true` 또는 배열로 지원하는 `asc`/`desc` 방향을 선언합니다. 페이지 수와 좋아요 수는 0 이상의 정수, 길이는 초 단위입니다. `feed`와 `search` 요청에는 별도의 `common` 맵을 전달하며, 빈 경계는 생략할 수 있고 한 번에 하나의 차원만 정렬할 수 있습니다. 선언하지 않은 차원은 거부해야 합니다.

### 동적 및 종속 필터

`feeds[].options`와 `searchFilters`의 단일 선택 항목은 `dynamic: true, values: []`를 선언할 수 있습니다. 동적 하위 항목은 `dependsOn: ['range']`로 같은 그룹의 상위 항목을 참조합니다. key는 고유해야 하며 의존 대상이 존재하고 순환하지 않아야 합니다. 동적 항목만 의존 관계를 선언합니다.

`filterOptions(request)`는 후보 배열을 반환합니다. 요청에는 `scope: 'feed' | 'search'`, `filter`, `values`가 있으며 목록 요청에는 `feed`, 검색에는 선택적으로 `keyword`가 있습니다. `values`에는 선언된 직접 상위 값만 포함하며 계정, 설정 또는 다른 필터는 전달하지 않습니다. 상위 값이 없거나 비어 있으면 하위를 불러오지 않습니다.

검색어에 따라 후보가 바뀌면 `keywordDependent: true`를 선언합니다. 검색어를 바꾸면 해당 항목과 하위 항목을 초기화하고 다른 필터는 유지합니다. `values`의 상위 값은 문자열, 숫자 또는 불리언이며 다중 선택 배열은 사용할 수 없습니다. 원본 이름은 고정 UI 문구가 아니며 콘텐츠 및 태그 번역 기능을 사용할 수 있습니다.

최대 500개의 `{value, label, color?}` 항목을 반환합니다. value는 고유 문자열 또는 유한 숫자입니다. label은 제어 문자가 없는 256자 이하의 비어 있지 않은 원본 이름이며 color는 6자리 16진수입니다. 큰 목록은 종속 그룹으로 나누며 조용히 잘라내지 않습니다. 원본 후보 이름은 자동 번역하지 않습니다.

선택은 `feed`의 `options`와 `search`의 `filters`로 전달됩니다. 플러그인은 실제 목록에 속하는지 검사하고 페이지 이동 시 조건을 유지해야 합니다. 목록 분석 실패는 오류를 반환합니다. 앱은 사이트, 목록/검색, 목록 키 또는 검색어, 상위 값별로 2분간 캐시합니다. 상위 변경 시 하위 선택과 오래된 응답을 지우며 실패한 로드는 재시도할 수 있습니다.

도메인별 플러그인은 해당 사이트 목록만 읽습니다. 같은 브랜드의 다른 도메인 플러그인을 호출하거나 Cookie를 공유하지 않습니다. 공통 파서는 빌드 시 템플릿으로 재사용하고 독립 스크립트를 생성합니다. 생성은 `node tools/build_catalog_sources.mjs`, 일치 확인은 `--check`를 사용합니다.

```js
{key: 'category', label: '分类', type: 'select', default: '',
 dynamic: true, dependsOn: ['range'], values: []}

async filterOptions({scope, feed, filter, keyword, values}) {
  return [{value: 'site-category-id', label: 'Site category'}];
}
```

### 네트워크

- `network.mode: 'auto'` (기본): 먼저 네이티브 HTTP를 사용합니다. 본문이 없는 동일 출처 HTTPS GET / HEAD가 Cloudflare 챌린지, HTTP 403·429 또는 복구 가능한 연결 오류를 받으면 브라우저로 한 번 재시도합니다. DNS, TLS, 시간 초과, 응답 스트림 및 일반 5xx 오류에서는 추가 지연을 피하기 위해 브라우저를 열지 않습니다. 대상은 소스가 선언한 도메인 안에 있어야 하며 동일 출처와 리디렉션 제한을 유지합니다.
- `network.mode: 'native'`: 영구 Cookie와 설정된 프록시로 네이티브 HTTP를 사용합니다. Cloudflare 감지 시 `CLOUDFLARE`를 반환하고 앱에서 재시도할 수 있습니다. 오류에 사이트 내 인증 URL이 있으면 확인 동작으로 페이지를 열 수 있습니다.
- `network.mode: 'browser'` + `network.origin`: `origin`의 숨겨진 페이지에서 동일 출처 `fetch()`를 보냅니다. 읽기 요청에 Cloudflare(HTTP 200 포함) 또는 필요한 Cookie/콘텐츠가 없는 연령 확인이 나타나면 최대 한 번 인증 페이지로 이동한 뒤 다시 읽으며 쓰기는 재전송하지 않습니다. 연령 확인은 `network.confirmation`을 따릅니다. Android와 Windows는 유일한 표준 Cloudflare 체크박스에 입력하며 다른 플랫폼은 자동 인증을 기다립니다. 실패하면 재시도하거나 사이트 내 인증 URL이 제공된 경우 확인 동작을 선택할 수 있습니다.

  문서는 선언된 도메인 내에서 동일한 스킴과 포트로 이동합니다. 미지정 요청 `origin`은 대상 사이트 URL에서 결정하며 응답은 최종 `url`을 유지합니다.

  자동 폴백은 `followRedirects: false`, `connectAddress`, 원인이 분류되지 않은 네트워크 오류에는 적용하지 않습니다. 본문 없는 브라우저 GET / HEAD는 일반 시도는 최대 세 번이며 인증 후 추가 재전송은 최대 한 번입니다. 연결 장애 또는 HTTP 408, 500, 502, 503, 504만 재시도합니다. 429와 시간 초과는 재전송하지 않습니다. 인증 페이지 이동은 모든 시도를 합쳐 논리 요청당 최대 한 번입니다. 시작, 요청, 문서 읽기, 해제에는 대기 제한이 있습니다. 사용자 지정 API 헤더가 있는 요청은 일반 탐색 결과로 대체하지 않고 실제 `fetch()`를 사용합니다. 재사용 HTML의 오류 상태를 유지하며 `responseType: 'base64'`는 원본 바이트의 base64를 반환합니다.

- `network.vpnHint: true`: 중국 본토에서 VPN이나 프록시가 필요할 수 있는 사이트에 선언합니다. 8초 넘게 기다리거나 실패하면 'VPN 또는 프록시가 필요할 수 있습니다'라고 안내합니다. 모든 오류를 VPN 탓으로 돌리지 마세요.
- `network.confirmation: { selector, readySelector, requiredCookies, auto: { clickSelector }, message }`: 사이트 연령 확인을 선언합니다. `selector`는 대화상자, `auto.clickSelector`는 그 안의 유일한 확인 버튼, `readySelector`는 접근 가능한 콘텐츠, `requiredCookies`는 확인 후 필요한 Cookie 이름입니다. 앱 입구에서 성인임을 확인한 뒤에만 숨겨진 브라우저가 클릭을 시뮬레이션하고 대화상자 소멸, 콘텐츠, Cookie 및 탐색 안정을 검사합니다. 규칙이 불완전하거나 일치하지 않거나 자동 확인에 실패하면 재시도할 수 있습니다. 오류에 사이트 내 인증 URL이 있으면 페이지에서 직접 처리한 뒤 완료를 누릅니다. 소스 도메인과 Cookie 분리 제한은 유지되며 작업 알림은 원래 작업을 자동 재전송하지 않습니다. 로그인, 결제 또는 게시에는 사용할 수 없습니다.
- 네트워크 오류에는 안전한 `diagnostics` 필드 `host`, `transport`, `reason`이 붙어 TLS 인증서, 핸드셰이크, DNS, 연결, 시간 초과를 구분합니다. 자동 로그에는 이 허용된 필드만 기록합니다. `reason: 'TLS_HANDSHAKE_TERMINATED'`는 네이티브 `HandshakeException.message`가 정확히 `Connection terminated during handshake`일 때만이며 (핸드셰이크 완료 전에 연결이 끊긴 것으로 인증서 실패가 아님), 본문이 없는 HTTPS GET / HEAD만 한 번 다시 시도하고 나머지는 다시 시도하지 않습니다.

### 이미지

- `imageNetwork: { mode: 'browser', origin, domains }`: 이미지 도메인과 하위 도메인은 사이트 Cookie 권한과 독립적입니다. `origin`은 사이트 또는 이미지 도메인에 속합니다. HTTPS 443과 허용 헤더를 사용하고 origin이 선언된 사이트 도메인에 속하면 동일 출처 이미지에 브라우저 사이트 세션을 사용하고, 교차 출처 이미지, 외부 이미지 출처 및 동영상은 인증 정보를 보내지 않으며 허용된 이미지 도메인 간 리디렉션을 지원합니다. 이미지당 20 MiB, 복호화, 형식 검사, 디코딩, 사이트별 캐시는 유지합니다. 미지정 시 네이티브 전송입니다. 브라우저 리디렉션의 플랫폼 제한은 미디어 권한을 참고하세요.
- **암호화된 이미지**: `imageDecrypt`를 선언하면 프레임워크가 형식 검사와 캐시 전에 복호화합니다. 복호화 설정은 캐시 식별에 포함되며 실패 결과는 캐시하지 않습니다. 엄격한 PKCS#7 패딩의 AES-CBC를 지원하며 `key`와 `iv`는 UTF-8입니다. 이미지 도메인을 반드시 한정하고 다른 도메인은 일반 경로를 씁니다.

```js
imageDecrypt: {
  type: 'aes-cbc',
  key: '0123456789abcdef', // UTF-8로 16, 24 또는 32바이트
  iv: '0123456789abcdef',  // UTF-8로 16바이트
  domains: ['images.example.com'],
},
```

표지가 HTTP 200을 반환해도 쓸 수 있다는 뜻은 아닙니다. 디코딩되는지 확인하세요.

### 미디어 권한 (HLS와 직접 파일)

`media` 권한은 `this.http`, `network`, 사이트 쿠키와 별개입니다.

MP4만 반환하더라도 `videos()`를 구현하는 플러그인은 유효한 `media`를 선언해야 합니다. `scope: 'session'`과 정적 `domains`를 함께 선언할 수 있습니다. HLS는 세션에서 승인된 개별 URL을 사용하며, 직접 재생하는 MP4는 정적 도메인 목록과 일치해야 합니다. 공식 게시 검사는 누락되거나 잘못된 미디어 선언을 거부합니다.

```js
domains: ['example.com'],
network: { mode: 'native' },
media: { mode: 'native', origin: 'https://example.com', domains: ['media.example.com'] },
```

- `media.mode`는 `'native'` 또는 `'browser'`입니다. `media.origin`은 플러그인의 소속 사이트에 속해야 하고, HTTPS 기본 포트 443을 쓰며, 인증 정보·쿼리·프래그먼트를 포함하지 않습니다.
- `media.domains`는 미디어 전용 허용 도메인 목록 (하위 도메인 포함)이며 사이트 쿠키 권한을 주지 않습니다. 재생목록, 세그먼트, 키는 HTTPS 443만 허용하고, URL 안의 인증 정보, 프래그먼트, IP, localhost (하위 도메인 포함), `.local`은 거부합니다.
- `'native'`: 사이트 Cookie, Authorization, 프록시 인증을 쓰지 않는 별도 클라이언트로 연결 전에 각 리디렉션을 검사합니다. `Referer`, `Origin`, `Accept`, `Accept-Language`만 허용합니다. 앞의 둘은 언어 하위 도메인을 포함한 선언된 사이트에 속하며 `Origin`에는 origin만 포함합니다.
- 선택 항목인 `media.referrerDomains`는 네이티브 동영상 미디어에서만 사용하며 유효한 공개 도메인을 최대 16개 지정합니다(하위 도메인 포함). 위 사이트 도메인 제한의 예외로 `Referer` 허용 출처만 추가합니다. `Origin`, 미디어 URL, 문서 탐색 또는 Cookie 권한은 확장하지 않으며 `imageNetwork`나 브라우저 미디어에는 사용할 수 없습니다.
- `'browser'`: `media.origin`에서 숨은 세션을 만들고 선언된 사이트 내 문서 이동을 허용합니다. `credentials: 'omit'`, `mode: 'cors'`를 사용하며 실제 문서와 브라우저가 Origin/Referer를 생성합니다. Windows는 WebView2로 각 연결 전에 도메인을 검사하여 허용 도메인 간 리디렉션을 지원하고 최종 URL도 확인합니다. 다른 엔진에는 단계별 차단 API가 없어 `redirect: 'error'`를 사용합니다. CORS와 사이트 CSP는 계속 적용되며 최종 URL 검사만으로 리디렉션을 허용하지 않습니다.
- 응답은 스트리밍 중에 크기를 제한하고 최종 주소를 다시 확인합니다. 재생목록 최대 2 MiB, 세그먼트 최대 32 MiB, AES-128 키는 정확히 16바이트입니다. 초과, 빈 응답, 허용되지 않은 주소는 모두 거부합니다.

- 동적 HLS CDN은 `mode: 'native'`에서 `media.scope: 'session'`을 선언할 수 있습니다. 권한은 현재 재생·다운로드 세션에서 해석한 URL, 재생 목록 리소스와 허용된 리디렉션에만 적용되며 종료 시 만료됩니다. Cookie나 영구 도메인 권한은 늘어나지 않습니다. HTTPS, 자격 증명 없는 요청, 목적지와 응답 크기 제한이 유지되며 직접 MP4와 브라우저 미디어에는 정적 도메인 허용 목록이 적용됩니다.

### 격리와 보안

- 각 플러그인은 **독립된** JS 환경 (각자의 헤드리스 WebView)에서 실행되어 서로의 전역 객체를 볼 수 없습니다. 네이티브 브리지는 호출한 환경을 알기 때문에 스크립트가 다른 플러그인을 사칭할 수 없습니다.
- 각 플러그인은 **독립된 쿠키 저장소**를 가지며, 요청은 자기 쿠키만 보내고 저장합니다.
- Secure 쿠키는 HTTP로 보내지 않습니다. 인증 페이지 열기와 브라우저 쿠키 가져오기는 설치된 플러그인의 `domains`로 확인하며, 가져올 수 있는 보안 속성과 만료 시간을 유지합니다. 사이트 쿠키를 지우거나 제거하면 해당 브라우저 세션도 닫고 그 사이트의 브라우저 쿠키를 지웁니다. 브라우저의 사이트 쿠키는 시스템이 공유하므로 같은 사이트를 선언한 플러그인도 영향을 받습니다.
- `domains`는 플러그인의 소속 사이트 (등록 가능한 도메인, 하위 도메인 포함)를 선언합니다. 이 사이트들의 쿠키만 내장 브라우저와 동기화되며 (Cloudflare 인증과 웹 로그인이 공유), 브라우저 모드의 `network.origin`도 여기에 속해야 합니다. 생략하면 `homepage`, `network.origin`, `account.cookieUrl/loginUrl`에서 추정합니다.
- 다른 출처로의 리디렉션은 원래 출처의 인증 헤더를 보내지 않고, 요청 본문을 유지하는 다른 출처 리디렉션은 거부합니다. TLS 인증서 검증은 항상 켜져 있습니다.
- 주소나 저장소에서 설치할 때 앱은 먼저 네트워크가 없는 샌드박스에서 스크립트 정보를 읽어 이름, 버전, SHA-256, 선언한 사이트, 위험 안내를 보여 주고, 사용자가 확인한 뒤에 설치합니다.

### 계정

```js
account: {
  type: 'password' | 'cookies' | 'session',
  title, hint, required: false,
  fields: [{ key: 'email', label: '邮箱' }, { key: 'password', label: '密码', secret: true }],
  loginUrl?, cookieUrl?, requiredCookies?: ['session_id'],   // 웹에서 로그인 가능, 앱이 쿠키를 가져옴
  loginDomains?: ['accounts.google.com', 'appleid.apple.com'],  // 외부 로그인 도메인 (로그인 이동에만 사용)
  localStorageKeys?: ['session_key'],  // cookieUrl과 같은 출처의 허용된 키만 읽어 login(values)에 전달; 값은 기록 금지
  async login(values) { return { name } },
  async logout() {},
  async status() { return { loggedIn, name, configured } },
  managedAccount: true,                 // 선택: 자동 관리 전용 계정 제공
  async enableManaged() {},             // 사용자가 가입에 동의한 뒤에만 호출
}
```

로그아웃 시 cookieUrl 사이트의 localStorageKeys에 선언된 키만 삭제하고 다른 로컬 저장소는 유지합니다. 빈 목록 진단은 고정 사유를 사용합니다: UPSTREAM_EMPTY(원본 목록 없음), NO_VIDEO(선택된 동영상 없음), EMPTY_RESULT(로드 후 콘텐츠 없음), CONTENT_FILTERED(표시 규칙으로 숨김), SEARCH_ONLY(데이터 절약 설정으로 추천 생략). 정상 페이지는 매번 기록하지 않고 빈 상태 변경과 복구만 기록합니다. 제목, 검색어, 콘텐츠 ID, 세션, 미디어 URL을 로그에 넣지 마세요.

- 계정 상태는 처음 사용할 때, 로그인·로그아웃·웹 로그인 후, 마지막 확인이 10분을 넘었을 때만 새로 고치며 호출할 때마다 확인하지 않습니다. `configured`는 계정이 설정되어 있음을 뜻하며 지금 로그인되어 있는지와는 별개입니다.
- `loginDomains`: 사이트가 실제로 쓰는 외부 로그인 도메인 (하위 도메인 포함). 사용자가 웹 로그인 페이지를 연 동안에만 HTTPS 443 이동을 허용하며, URL 인증 정보, IP, localhost, `.local`은 거부합니다. 인증 페이지, 접근 확인, 플러그인 요청, 쿠키 가져오기는 여전히 `domains`로 확인하므로 외부 로그인 도메인을 `domains`에 넣어 권한을 넓히면 안 됩니다. 로그인 페이지는 같은 창 이동과 `window.opener`를 유지하는 팝업을 지원하며 팝업에서도 같은 확인을 하고, 빈 초기 페이지는 외부 이동 권한을 주지 않습니다. 외부 페이지에 있는 동안은 로그인 완료로 보지 않고 사이트로 돌아온 뒤 쿠키를 동기화합니다. 외부 쿠키는 플러그인 저장소로 가져오지 않고 사이트 쿠키를 지워도 삭제되지 않으며 시스템 WebView가 관리합니다. 외부 서비스가 내장 브라우저 로그인을 제한할 수 있습니다.
- `type: 'session'`은 기존 인증 세션을 가져옵니다. 비밀 필드 하나 (예: `session`)를 선언하며, 클립보드 내용을 그대로 유지해 플러그인이 검증하고 아이디·비밀번호·쿠키로 나누지 않습니다. 로그인은 실제 인가를 확인해야 하며 입력 형식만 보고 성공했다고 하면 안 됩니다.
- `managedAccount: true`와 `account.enableManaged()`는 선택적 계정 관리 기능이며 설명을 제공하고 사용자가 확인한 후에만 활성화합니다. 수동 계정과 관리 계정을 별도로 저장하고 기존 인증 정보를 덮어쓰지 마세요. 계정 데이터는 기기에서만 사용하며 문서, 진단, 배포 파일에 포함하지 마세요.
- 비밀번호, 토큰, 플러그인 상태는 사용자 기기의 데이터입니다. 문서나 로그에 실제 인증 정보를 쓰지 마세요.

## 메서드

메서드 안의 `this`는 '런타임 API'를 참고하세요. 모든 메서드는 `async`로 쓸 수 있습니다.

```js
async feed(key, { page, cursor, options, common }) {} // 사이트 페이지 탭
async search({ keyword, page, cursor, filters, common }) {}
async random() {}                                  // 작품 ID 반환
async detail(id, preview) {}
async chapter(id, chapterId) {}                    // 만화, 갤러리
async resolveImage({ id, chapterId, index, token, retry }) {}  // 선택: 이미지 지연 해석
async thumbnails(id, page) {}                      // 선택: 미리보기 썸네일 페이지 불러오기
async videos(id, episodeId = '_') {}               // 동영상
async textChapter(id, chapterId) {}                // 소설
async gameResources(workId) {}                     // 게임
async resolveGameResource(workId, resourceId, channelId) {}
```

### 목록: `feed` / `search`

```js
{
  items: [WorkItem], page: 1, totalPages: 20, total: 500,
  hasNext: true,
  cursor: '12345',        // 선택: 커서 방식 사이트는 다음 커서를 반환하고 앱이 그대로 돌려줌
}
// 또는 구역을 반환하면 구역 레이아웃으로 표시:
{ sections: [{ title: '连载更新', items: [WorkItem] }], hasNext: false }
```

**WorkItem**: `{ id, title, subtitle?, cover, coverBlurred?, coverAspect?, pages?, rating?, likes?, views?, language?, category?, badge?, badgeColor?, duration?, uploaded?, tags?, mediaKind?, workCode?, editions?, commentsAvailable? }`

- `workCode`는 원본 사이트에서 확인한 작품 번호 또는 공통 검색 코드이며 같은 작품을 찾는 데만 사용합니다. `id`를 대체하거나 작품 식별, 즐겨찾기, 진행 상태, 다운로드를 병합하지 않습니다.
- `editions`는 원본 사이트가 명시한 고정 버전 라벨(중국어 자막, 무삭제 유출본 등)입니다. 라벨이 없다고 원본으로 추정하면 안 됩니다. 번역 표시는 원래 라벨을 변경하지 않습니다.

- `coverAspect` (너비 / 높이)가 있으면 이미지가 로드되기 전에 격자를 배치할 수 있습니다.
- `badgeColor`는 분류 배지의 색입니다.
- `mediaKind: 'comic' | 'video' | 'novel' | 'game'`은 작품 자체의 유형입니다. 유형이 하나인 플러그인은 생략할 수 있지만, 섞여 있는 플러그인은 반드시 지정하고 플러그인의 `type`만 보고 이미지를 동영상으로 다루면 안 됩니다. 소설과 게임 작품은 항상 지정하여 플러그인을 제거해도 오프라인 작품과 기록이 올바른 리더로 열리게 합니다.
- 게시물 형식의 결과는 `presentation: 'post'`, `text`, `date`, `url`, `media` 배열을 가질 수 있으며 게시물 카드로 표시됩니다. `presentation: 'media'`는 미디어 격자로 표시하고 누르면 작품 안의 미디어를 엽니다. 게시물에 미디어가 없어도 됩니다. 미디어 주소는 플러그인이 선언한 도메인과 권한을 따릅니다.

### 상세: `detail`

WorkItem의 모든 필드에 더해:

```js
{
  url, authors: [], description, uploader?, size?, comments?, commentsAvailable?,
  tags: [{ namespace: 'artist', label: '作者', tags: [{ name, keyword, filters?, count? }] }],
  chapters: [{ id, title }] | null,   // null은 단일 챕터
  singleChapterId?,                   // 단일 챕터 작품에 필요한 챕터 ID
  thumbnails?: [url | { url, width, height, offsetX, offsetY }],   // 스프라이트 지원
  related?: [WorkItem], series?: [WorkItem], variants?: [WorkItem],
}
```

- `variants`에는 원본 사이트가 제공한 같은 사이트의 동일 작품에 대한 실제 버전 링크만 포함하며 각 버전의 독립적인 `id`를 유지합니다. URL을 추측하지 마세요. 다른 사이트의 버전은 `workCode`로 검색하며 즐겨찾기, 진행 상태, 다운로드를 독립적으로 유지합니다.

- 태그를 누르면 이 사이트에서 `keyword`와 `filters`로 검색하므로, 태그를 사이트 고유 문법 (예: `artist:"xxx"`)이나 필터 매개변수에 대응시킬 수 있습니다.
- 두 번째 인자 `preview`는 선택이며, `preview.source`와 `preview.id`가 요청과 일치할 때만 이미 표시되었거나 저장된 공개 메타데이터가 전달됩니다. 플러그인은 여전히 ID를 확인하고 URL을 검증해야 합니다. 번호를 입력해 열면 preview가 없으므로 제목과 표지가 불완전할 수 있습니다.

### 챕터: `chapter` / `resolveImage` / `thumbnails`

```js
{ pages: [
  { url, headers?, fallbacks?: [url], width?, height?, transform? },  // 주소를 앎
  { token: '12' },                                                      // 지연 해석: 앱이 resolveImage 호출
]}
```

- `fallbacks`: 예비 미러. 주 주소가 실패하면 순서대로 시도합니다.
- `transform: { type: 'unscramble-strips', segments: N }`: 이미지가 N개 띠로 잘려 거꾸로 저장된 경우 GPU에서 복원합니다. 오프라인 파일은 원본 이미지를 저장하고 표시할 때 복원합니다.
- `resolveImage`는 `{ url, headers?, width?, height?, cacheKey? }`를 반환합니다. 실패하면 앱이 `retry`를 늘려 다시 호출하므로 플러그인은 서버를 바꿀 수 있습니다.
- `thumbnails(id, page)`는 `{ thumbnails: [...], hasNext }`를 반환합니다.

### 동영상: `videos`

`[{ quality: 1080, label: '1080P', url, headers?, format?, preferred?, hls? }]`를 반환합니다. 직접 링크는 보통 만료되므로 앱은 재생하거나 다운로드할 때마다 다시 가져옵니다.

- `format: 'hls'`에 `hls: {manifest, keys}`를 추가할 수 있습니다. `url`은 실제 HTTPS 변형 재생목록 기준 주소, `manifest`는 처리된 전체 VOD 미디어 목록(UTF-8 최대 2 MiB), `keys`는 참조된 절대 키 URL과 Base64 16바이트 키의 매핑(최대 32개)입니다. 네이티브 미디어만 지원하며 기존 주소 권한 및 콘텐츠 검증을 유지하고 참조되지 않은 키는 거부합니다. 이 필드가 있는 결과는 디스크에 캐시하지 않고 키는 세션 메모리에만 보관하며 store, 로그, 작품 또는 커서에 저장하면 안 됩니다.

- 여러 회차인 동영상은 `detail(id).chapters`에 재생 순서대로 `[{ id, title }]`를 반환합니다. 각 `id`는 안정적이어야 하며 화질이나 임시 미디어 URL로 대신하면 안 됩니다. 앱은 같은 ID로 회차 선택, 진행 저장, 다운로드, 이어 보기를 하고 `videos(id, episodeId)`로 그 회차의 자료를 가져옵니다. 단일 회차는 `singleChapterId`를, 없으면 `'_'`를 씁니다.
- `format`을 생략하면 MP4 직접 링크로 재생·다운로드합니다. HLS는 `format: 'hls'`를 반환하고 `media` 권한을 선언해야 합니다.
- HLS 마스터 재생목록 (`#EXT-X-STREAM-INF`)은 앱이 변형별 재생목록으로 펼치고 `RESOLUTION`에서 실제 화질을 얻습니다. 마스터를 반환하면 `quality`는 원하는 화질이며, 그 이하에서 가장 높은 실제 화질을 고르고 해당이 없으면 가장 높은 화질을 고릅니다. 각 변형은 오디오와 비디오가 다중화된 MPEG-TS 또는 VOD fMP4여야 하며, 독립된 `AUDIO`, `VIDEO`, `SUBTITLES`와 `media.domains` 밖의 주소는 거부합니다. `#EXT-X-I-FRAME-STREAM-INF`는 무시합니다. 단일 재생목록에서 해상도를 알 수 없으면 `label: '原画'`를 쓰고, 원하는 화질을 실제 해상도처럼 보이지 마세요. 마스터에 `RESOLUTION`이 없으면 유효한 `BANDWIDTH`가 필요합니다. 각 비트레이트를 kbps로 표시하고 최고 값을 기본으로 선택하며 해상도를 추측하지 않습니다.
- `type: 'video', category: 'live'`는 3차원 공개 라이브이며 홈과 카테고리에 이미지 카드만 표시합니다. `videos()`는 현재 공개 방송의 HLS만 반환하며 비공개·유료·오프라인 방송을 재생 가능한 것처럼 반환하지 않습니다. 갱신되는 재생 목록을 사용하며 VOD 위치 복원·저장이나 다운로드는 지원하지 않습니다. 녹화는 사용자 조작으로 시작하며 초기 창 이후의 새 세그먼트만 저장합니다. 중지나 앱 종료 시 끝나고 재실행 후 자동 재개하지 않습니다. 독립 미디어 세션과 백그라운드 작업이 세그먼트를 검증·복호화하여 완전한 로컬 목록을 저장합니다. 재연결 시 미디어를 다시 확인하며 인코딩 경계나 장시간 녹화는 분할됩니다. 실패해도 저장된 내용은 보존합니다. 다중화 MPEG-TS만 지원하며 MAP/fMP4, 저지연 PART, BYTERANGE, GAP은 지원하지 않습니다.
- VOD는 `#EXT-X-ENDLIST`가 있는 완전하고 연속적인 MPEG-TS 또는 fMP4 목록을 요구합니다. fMP4는 미디어 앞의 단일 `#EXT-X-MAP` 초기화 세그먼트만 지원하며 초기화 변경과 바이트 범위는 지원하지 않습니다. 초기화와 미디어를 모두 주소 승인, 내용 검증 및 로컬 재작성하고 오프라인 재생과 내보내기에도 초기화를 보존합니다. 라이브는 여전히 MPEG-TS만 지원하며 순환 목록과 discontinuity를 허용합니다. 양쪽 모두 `METHOD=AES-128`, `KEYFORMAT=identity` CBC/PKCS7과 16바이트 키를 지원합니다. 미디어 IV는 명시하거나 순번에서 유도하며 암호화된 초기화는 명시 IV가 필요합니다. 키는 세션 메모리에만 남습니다. SAMPLE-AES, 다른 KEYFORMAT, BYTERANGE, GAP은 지원하지 않으며 VOD는 discontinuity도 거부합니다. `#EXT-X-TOKEN`은 제거합니다.
- HLS 목록과 MPEG-TS 세그먼트는 PNG `roUd` 래퍼(원본 또는 zlib 압축)를 지원합니다. 래퍼 해제 후 분석·검증·복호화하며, 해제된 데이터에도 목록 2 MiB, 세그먼트 32 MiB 제한이 적용됩니다. 플러그인은 `format: 'hls'`를 반환하며 추가 권한이 필요하지 않습니다.
- 재생할 때는 `127.0.0.1`에만 바인딩된 무작위 포트와 무작위 토큰을 쓰며, 제한된 URL 등록부에서 검증된 세그먼트를 필요할 때 읽습니다. 세션을 닫으면 요청이 취소됩니다. HLS 오프라인 다운로드는 현재 Android만 지원하며, 세그먼트마다 검증하고 SHA-256을 저장하며 이어받기와 취소가 가능하고 마지막에 Media3로 MP4를 만듭니다. 완전한 파일만 오프라인 라이브러리에 들어갑니다. fMP4는 초기화와 미디어를 순서대로 저장하며 Media3 TS 변환을 사용하지 않습니다.

### 소설: `textChapter`

소설 플러그인은 `type: 'novel', category: 'novel'`을 선언하고, `textChapter`를 구현하면 `capabilities.textChapter: true`가 나옵니다. 목록과 상세에는 `mediaKind: 'novel'`과 `language: 'zh'` 또는 `'en'`을 지정합니다. 실제 표지가 없으면 `cover: ''`를 반환하며, 앱은 가짜 이미지를 요청하지 않고 글자 표지를 보여 줍니다.

```js
async textChapter(id, chapterId) {
  // 이 챕터의 전체 본문을 반환. paragraphs는 비어 있지 않은 문자열 배열이며 HTML을 포함하지 않음.
  return { title: '章节标题', paragraphs: ['第一段正文。', '第二段正文。'] };
}
```

- 여러 챕터 소설은 `detail.chapters`에 안정적인 ID와 사이트에서 확인한 읽기 순서를 반환하고, 단편은 `chapters: null`과 선택적인 `singleChapterId`를 씁니다.
- 챕터 안의 페이지 나눔은 플러그인이 순서대로 합치며, 다음 챕터, 게시판 댓글, 광고, 추천 작품을 본문에 넣으면 안 됩니다. `Park.html.paragraphs(node)`가 일반적인 텍스트 추출을 제공하지만 사이트의 경계와 페이지 나눔은 플러그인이 정합니다.
- 로그인, 결제, 권한 때문에 본문이 잘리면 `LOGIN_REQUIRED`를 던지며, 미리보기를 완전한 챕터로 꾸미면 안 됩니다.
- 앱은 챕터마다 `text.json`을 원자적으로 쓰며 완전히 쓰인 경우에만 다운로드 완료로 봅니다. 읽기 진행과 메모는 `paragraphs.join('\n\n')`의 UTF-16 위치를 쓰고, 글자 크기·글꼴·들여쓰기 같은 표시 설정은 본문이나 저장된 위치를 바꾸지 않습니다. 책갈피와 메모는 다운로드와 따로 저장되어 백업에 포함되며, 다운로드를 지워도 남습니다.

### 게임: `gameResources` / `resolveGameResource`

게임 플러그인은 `type: 'game', category: 'game'`을 선언하고, 작품은 `mediaKind: 'game'`을 지정하며 가짜 `chapters`를 두지 않습니다. 런타임은 메서드를 보고 `capabilities.gameResources`와 `capabilities.resolveGameResource`를 내보냅니다.

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
  // 클라우드 드라이브는 kind: 'external', urls: [모든 예비·분할 링크], url: urls[0]을 반환.
}
```

- `gameResources`는 안정적인 ID, 메타데이터, 채널만 반환하며 서명된 URL, 비밀번호, 가짜 다운로드 상태를 넣으면 안 됩니다. `testStatus`는 `tested | untested | unknown`이며 사이트 표시를 그대로 옮긴 것입니다. `status: 'expired'` 채널은 비활성화됩니다.
- `resolveGameResource`는 사용자가 누르거나 다시 시도할 때만 호출되며 반환한 URL은 저장하거나 로그에 남기지 않습니다. 비밀번호는 로컬 다운로드 작업과 함께 저장할 수 있지만 진단에는 쓰지 않습니다. 여러 클라우드 링크를 버리면 안 됩니다. 여러 개를 반환할 때는 `urls`와 길이가 같은 `extractionCodes` (빈 문자열은 추출 코드 없음)를, 공통 코드에는 `extractionCode`를 쓸 수 있습니다.
- 댓글이 필요한 채널은 `requiresReply: true, replyText: '실제 댓글 내용'`을 선언하며, 앱은 '댓글로 링크 해제'와 보낼 문구를 보여 주고 사용자가 확인한 뒤에만 호출합니다. 플러그인은 해석 전에 첫 게시물을 다시 확인해 이미 해제되었으면 읽기만 하고, 사용자가 누를 때 한 번만 보내며 보내기 전에 계정·게시물 상태를 확실히 저장합니다. 결과가 불분명하거나, 반복 시도이거나, 동적 인증이 필요하면 원글 URL과 함께 `CONFIRM_REQUIRED`를 반환하고 자동으로 다시 보내면 안 됩니다. 목록, 상세, 미리 불러오기, 백그라운드 업데이트에서는 댓글을 달지 않습니다.
- 직접 링크는 `media: { mode: 'native', origin, domains }`를 선언합니다. 파일은 쿠키 없는 별도 클라이언트로 스트리밍 저장하며, HTTPS, 단계별 도메인 확인, 길이 확인, 취소 시 정리, 완성 파일 보호는 프레임워크가 맡습니다. 이어받기는 없으며 다시 시도하면 주소를 다시 해석해 처음부터 받습니다. 클라우드 드라이브는 외부 앱으로 열며 HTTP(S), FTP(S), magnet, ed2k, thunder만 허용하고 사이트 쿠키는 쓰지 않습니다. 게임은 챕터, 읽기 진행, 챕터 업데이트를 만들지 않으며 앱이 파일을 자동으로 설치·압축 해제·실행하지 않습니다.

### 구독: `subscription`

채널이나 창작자를 구독하는 플러그인은 `subscription` 객체를 선언합니다. `normalize`와 `posts`가 모두 있으면 런타임이 `capabilities.subscription`을 내보내고 '탐색 → 구독'에 표시됩니다. `feeds`도 선언한 플러그인은 일반 분류에도 나타납니다.

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
  async mediaChunk(resource, offset) { return { base64, done }; }, // 선택
}
```

- `normalize`는 기기 안에서만 검증해야 하며, 로그인하지 않았거나 오프라인이어도 대상을 저장할 수 있어야 합니다. 이 사이트의 사용자 이름이나 관리되는 프로필 URL만 받습니다. `resolve`와 `targets`는 선택이며, `targets`가 있으면 manifest가 `subscription.joinedTargets: true`를 내보냅니다.
- 독립 커뮤니티 입구는 `communities: true`, `communityHint`, `communityExample`을 선언하며 런타임이 그대로 내보냅니다. 대상은 `{ id, label, kind: 'community' }`이고 ID는 작성자 대상과 구별해야 합니다. `targets({ kind: 'community' })`는 가입 커뮤니티, 인수 없는 `targets()`는 기본 대상을 반환합니다. 커뮤니티 API 오류가 작성자 목록을 망가뜨리지 않도록 별도로 처리합니다. `resolve`는 이름과 접근 권한을 읽기 전용으로 확인할 수 있지만 자동 가입하면 안 됩니다.
- `posts`의 커서는 불투명한 문자열이며 마지막 페이지는 `hasNext: false`, 미디어가 없는 페이지도 계속 넘길 수 있습니다. `locked`는 권한 부족, `previewOnly`는 공개 미리보기임을 뜻합니다. 썸네일을 전체 내용인 척하면 안 됩니다.

### 공개 앨범: `subscription.media`

앨범은 독립 기능이며 이미 읽은 게시물로 조립하거나 `subscription.posts`로 대체하지 않습니다. `subscription.media(scope, { page, cursor })`를 구현합니다. 공개 feed만 있고 구독 대상이 없는 소스도 `subscription` 아래 이 메서드만 선언할 수 있습니다. 런타임은 `capabilities.subscription`과 독립된 `capabilities.album`을 내보냅니다.

`scope`는 feed와 필터의 `{ feed, options }` 또는 사용자·커뮤니티·채널·그룹의 `{ target }` / `{ search: { keyword, filters } }`입니다. 대상 해석과 순회는 소스가 담당하며 UI에 사이트별 조건을 넣지 않습니다. `{ items, cursor, hasNext }`를 반환합니다. 일치하는 미디어가 없는 페이지도 계속할 수 있고 다음 커서는 반드시 진행해야 하며 중복은 오류입니다.

항목에는 안정적인 문자열 `id`, `presentation: 'post' | 'work'`, 날짜가 알려졌다면 해석 가능한 ISO 8601 날짜, 원본 순서의 완전한 `media` 배열이 필요합니다. 첨부마다 고유하고 안정적인 문자열 `id`, `type: 'image' | 'video'`, 실제 콘텐츠 `url` 또는 통제된 `resource`를 제공합니다. `preview`는 이미지 썸네일입니다. 대신 아래 첨부 형식의 `previewResource`를 쓸 수 있으며 별도 이미지이고 최대 2 MiB여야 합니다. 표지나 동영상 URL을 썸네일로 속이지 않습니다. 제한 콘텐츠는 원본 흐림을 유지한 공개 미리 보기만 `previewOnly: true`로 제공하고 게시물 전체가 잠기면 `locked: true`를 설정합니다.

소스는 페이지 사이의 첨부를 보완하고 원본 미디어 그룹을 합칩니다. 클라이언트는 첨부 `id`로 같은 작품을 병합하며, 한 작품의 모든 첨부에 유한 숫자 `order`가 있을 때만 이를 기준으로 정렬합니다. 날짜 필터는 현지 날짜 양 끝을 포함하고 범위 지정 시 날짜 미상을 제외합니다. 이미지·영상 필터와 게시물 접기는 식별 정보를 바꾸지 않습니다. 빈 필터 결과를 제한된 페이지까지 자동 로드한 뒤 수동으로 계속할 수 있습니다. `presentation: 'work'`는 작품 상세, `'post'`는 전체 게시물을 엽니다. 앨범 표지는 이미지나 명시적 썸네일만 읽고 동영상 재생 URL은 쓰지 않습니다.

- `coverBlurred: true`와 미디어의 `blurred: true`는 썸네일과 전체 사진 보기에서 원본 사이트의 흐림 효과를 유지합니다. 제한된 사진을 선명한 전체 콘텐츠로 표시하지 마세요. 미리보기와 전체 영상 모두 HLS 마스터를 해석한 후 선택한 VOD 화질을 재생합니다.
- 직접 링크를 줄 수 없는 인가된 첨부는 `media[].resource`를 쓰고 `mediaChunk(resource, offset)`를 구현합니다. 한 번에 최대 128 KiB, offset은 128 KiB 단위이며, resource에는 정수 `size`와 인증 정보나 임시 참조에 따라 바뀌지 않는 안정적이고 비밀이 아닌 문자열 `cacheKey`가 있어야 합니다. 프레임워크가 전체 크기와 각 조각을 확인하고 자체 캐시 경로에 원자적으로 씁니다. 첨부 하나는 최대 512 MiB이며 resource가 로컬 경로를 정할 수 없습니다. 서명된 링크와 resource는 구독 기록에 저장하지 않습니다.
- 원본 사이트에서 팔로우나 가입을 수행하는 구독은 저장 전에 동작을 명확히 알리고 사용자 확인을 받아야 합니다. 검증되지 않은 쓰기 작업은 원본 사이트로 안내하고 알리지 않은 팔로우, 가입 또는 결제를 수행하면 안 됩니다.

### 업데이트 구독: `updateSubscriptions`

일반 플러그인은 별도의 `updateSubscriptions` 객체로 '업데이트 따라가기'를 지원할 수 있습니다. 런타임은 `check`가 있을 때만 `capabilities.subscriptionUpdates`를 내보내며 작품 분류나 위의 `capabilities.subscription`에는 영향이 없습니다. 메타데이터에는 `dimensions: [{ key, label, hint }]`가 있으며, 태그 메뉴에서 원래 키워드와 필터를 넘길 수 있습니다.

- `normalize(dimension, input)`는 `{ id, label }`을, `check({ dimension, target }, { cursor })`는 `{ items, hasNext, cursor }`를 반환합니다. 각 항목은 `{ id, title, kind, workId, chapterId }`이며 `kind`는 `work | post | chapter`만, ID는 안정적이고 비어 있지 않으며 미디어 URL, 쿠키, 인증 정보를 담지 않습니다. 챕터 ID에는 작품 식별도 넣어 서로 다른 작품의 '1화'가 겹치지 않게 합니다.
- `Park.enableUpdateSubscriptions(Park.__pending, rules)`가 일반적인 대응을 제공합니다. 규칙은 스크립트 끝에서 차원을 명시적으로 선언하며 `searchFilters`, `seriesPattern`을 지정할 수 있습니다. `work`는 실제 챕터 목록, `posts`는 기존 채널 API, `search`와 `filter`는 검색을 쓰고, `code`는 완전한 품번에 정확히 일치하며, `series`는 사이트 도메인으로 검증한 시리즈 경로를 씁니다. 검색 커서는 페이지 번호와 사이트 커서를 함께 저장합니다.
- `windowed: true`는 처음에 최근 3페이지를 기준으로 저장합니다. 이후에는 한 번에 최대 3페이지씩 커서와 후보를 저장하며, 모두 알려진 항목인 페이지나 마지막 페이지에 도달한 뒤 새 이벤트를 확정합니다. 챕터 목록은 자르지 않으며 후보 20,000개 초과나 파싱 실패는 오류로 처리합니다.
- `query({ dimension, target })`는 구독 탐색과 확인이 공유하는 `{ keyword, filters }`를 반환합니다. 앨범도 `{ search: { keyword, filters } }`를 지원하며 페이지 이동 시 검색 조건을 유지합니다. 게시물 짧은 동영상은 `resource` 첨부를 지원하고 같은 검색 범위에서 계속 재생합니다.
- 포그라운드와 백그라운드는 플러그인 런타임, 쿠키 구역, 도메인 제약, 확인 로직을 공유합니다. 백그라운드는 관련 플러그인만 시작하며 로그인, 사이트에서의 구독, 미디어 다운로드, 권한 우회를 하지 않습니다. 계정이나 플러그인 설정이 바뀌면 기준을 다시 만듭니다 (토큰 갱신은 제외).

## 런타임 API

메서드 안에서 `this`로 다음을 쓸 수 있습니다.

| 멤버 | 설명 |
| --- | --- |
| `this.http` | `request(opts)`, `get(url, opts)`, `post(url, opts)`, `text(url, opts)`, `json(url, opts)` |
| `this.config` | 사용자가 사이트 설정에서 고른 값 (설정하지 않으면 `default`) |
| `this.store` | 영구 키-값 저장소: `get(key, fallback)` / `set(key, value)`. 토큰, 도메인 목록 등에 쓰며 `await flush()`로 기록을 확인 (실패하면 예외) |
| `this.cookies` | `get(url)` / `set(url, { name: value })` / `clear(url)` |
| `this.log({ code, host, transport, reason })` | 허용된 필드만 기록하며 자유 텍스트는 남기지 않아 인증 정보와 주소가 새지 않음 |

전역 도우미:

| 도우미 | 설명 |
| --- | --- |
| `Park.html.parse(text)` | 표준 `Document`를 반환하며 `querySelector`를 쓸 수 있음 |
| `Park.html.text(node)` / `unescape(s)` / `strip(html)` / `paragraphs(node)` | 텍스트 처리 |
| `Park.crypto.md5Hex(text \| text[])` | MD5. 배열로 한 번에 계산 가능 |
| `Park.crypto.sha256Hex` / `hmacSha256Hex(key, text)` / `aesEcbDecrypt(base64, key)` / `uuid()` | 네이티브 구현 |
| `Park.crypto.digestBytes('sha1' \| 'sha256', bytes)` | 최대 2 MiB, 0~255 정수 배열 |
| `Park.crypto.randomBytes(length)` | 안전한 무작위 바이트, length는 1~65536 |
| `Park.url.parse(value, base, domains)` / `site(source, value, base?)` / `response(source, response, requested)` | 허용 도메인과 하위 도메인의 HTTPS 443 URL을 해석하고 인증 정보를 거부하며 조각을 제거합니다. 실패 시 `null`. `site`는 소스 `domains`를 사용하고 `response`는 최종 주소를 검사하며 공유 소스 기준 주소를 변경하지 않고 `BLOCKED`를 발생시킵니다. 경로, 페이지, 작품, 검색 조건은 플러그인에서 확인하며 쿼리 키나 CDN 노드명 고정 목록은 피합니다. |
| `Park.utils.rateLimiter(ms)` | `wait()`를 반환해 요청 사이 최소 간격을 보장 |
| `Park.utils.mapLimit(items, n, fn)` / `lruMap(n)` / `parseCount('1.2万')` / `formatDate(ts)` | 기타 도우미 |
| `Park.error(code, message, extra?)` | 오류 코드가 있는 오류를 만듦. '오류 코드' 참고 |

`Park.crypto.aesGcmDecrypt(ciphertext, key, iv)`는 16진수 암호문(끝의 16바이트 인증 태그 포함, 최대 4096바이트), 16/24/32바이트 키와 12바이트 IV를 받아 평문 바이트 배열을 반환합니다. 인증 실패 시 인증되지 않은 평문 없이 오류를 발생시킵니다.

### `http.request(opts)`

```js
await this.http.request({
  url, method: 'GET', headers: {}, params: { q: 'x' },   // params는 URL에 붙음
  json: {...} | form: {...} | body: 'raw' | bodyBase64: '...',
  timeout: 15000,
  responseType: 'text' | 'base64',
});
// → { status, headers, body, url, ok, json() }
```

- `text()` / `json()`은 2xx가 아니면 예외를 던집니다 (404 → `NOT_FOUND`). 쿠키는 자동으로 저장되고 리디렉션 대상마다 다시 고릅니다.
- `bodyBase64`는 바이너리 본문 (최대 2 MiB)이며 `body`나 브라우저 모드와 함께 쓸 수 없습니다. 텍스트 요청과 같은 도메인 격리, TLS, 리디렉션 규칙을 따릅니다. 플러그인이 스스로 브라우저 통신, WebSocket, 임의 파일 접근을 열 수는 없습니다.

## 오류 코드

`throw Park.error(code, message, extra)`로 던지면 앱이 코드에 맞게 안내합니다.

| code | 앱의 처리 |
| --- | --- |
| `CLOUDFLARE` | '인증하기': 내장 브라우저 열기 |
| `CONFIRM_REQUIRED` | '확인하기': 플러그인이 선언한 접근 확인을 사용자가 마칠 때까지 대기 (`extra.url`이 확인 페이지) |
| `LOGIN_REQUIRED` | '로그인하기': 사이트 설정의 계정 영역 열기 |
| `NOT_FOUND` | '콘텐츠가 없습니다' 표시 |
| `BLOCKED` | '접근 제한' 표시 (IP 차단, 할당량 소진 등). 이미지는 다시 시도하지 않음 |
| `NETWORK` | '네트워크에 연결하지 못했습니다'와 원인, '다시 시도' 표시 |
| `HTTP` / `PARSE` / `UNSUPPORTED` / `CONFIG` | 플러그인의 메시지와 '다시 시도' 표시 |

### 구조화된 메시지

`message`는 **중국어 템플릿**이며 그대로 번역 키입니다. 바뀌는 부분은 문자열에 이어 붙이지 말고 `extra.params`에 넣으세요.

```js
throw Park.error('HTTP', '站点返回 HTTP {status}', { params: { status: res.status }, status: res.status });
throw Park.error('NOT_FOUND', '影片不存在');
```

앱은 먼저 플러그인의 `i18n`, 다음으로 앱의 공통 어휘로 템플릿을 번역하고 `params`를 자리 표시자에 채웁니다. 이어 붙인 문자열은 번역할 수 없어 중국어가 아닌 사용자에게 중국어가 그대로 보입니다. `extra`의 `status`, `url`, `diagnostics`는 그대로 씁니다.

### 홈 캐시와 오류의 의미

- `feed` 실시간 결과는 모든 필드를 유지합니다. 앱 전용의 재생성 가능한 디스크 캐시는 허용된 작품 정보, 게시물 본문, 첨부 접근 정보와 지원되는 상세 필드를 저장하여 새로 고침 전에도 내용을 열 수 있게 합니다. 만료되는 미디어 URL과 리소스 참조가 포함될 수 있으며 만료 시 새로 고쳐야 합니다. 다운로드나 백업을 대체하지 않습니다. 캐시 식별은 사이트·계정·설정·요청 범위를 분리합니다. 계정 인증 정보를 반환 내용·ID·커서에 넣지 말고 캐시 접근 정보를 진단이나 구독 기록에 복사하지 마세요.
- 오래된 캐시는 분명한 `NETWORK` / `TIMEOUT` 오류일 때만 오프라인 콘텐츠로 보여 주며 캐시임을 표시합니다. 로그인, 확인, 사람 인증, 해석, 설정 실패는 각자의 오류를 던져야 하며 프레임워크가 네트워크 장애로 꾸미지 않습니다. 사용자가 직접 새로고침했다 실패해도 실제 오류를 보여 줍니다.

## 다국어

앱 UI는 `zh-Hans`, `zh-Hant`, `ja`, `ko`, `en`, `es`, `ru`, `ar` (아랍어는 오른쪽에서 왼쪽)을 지원합니다. 플러그인의 사람이 읽는 정적 문구 (이름, 설명, 탭 이름, 옵션, 검색 힌트, 계정 안내, 오류 메시지)는 모두 **중국어 간체 원문**으로 쓰며, 원문이 번역 키입니다.

플러그인은 manifest의 `i18n`에 자체 번역을 담습니다.

```js
Park.register({
  i18n: {
    'zh-Hant': { '发行日期': '發行日期', '影片不存在': '影片不存在' },
    'en': { '发行日期': 'Release date', '影片不存在': 'Video not found', '站点返回 HTTP {status}': 'The site returned HTTP {status}' },
    // ja, ko, es, ru, ar도 같음
  },
  key: 'mysite',
  // …
});
```

- 찾는 순서: 플러그인 `i18n`의 현재 언어 → 플러그인의 `en` (중국어 간체 UI 제외) → 앱의 공통 어휘 (`assets/i18n/`, 예: '정렬', '최신', '인기') → 원문.
- 앱에 없는, 그 플러그인만의 낱말만 `i18n`에 쓰고 공통 낱말은 앱의 번역을 씁니다. 자리 표시자 `{name}`은 원문과 같아야 합니다.
- 원격 내용 (작품 제목, 작가, 태그, 소개), 사용자 입력, 저장되는 프로토콜 키는 그대로 두며 UI 문구로 번역하지 않습니다.
- `i18n`을 바꾸는 것도 플러그인 변경이므로 버전을 올려야 합니다. 이전 플러그인을 쓰는 사용자는 업데이트 전까지 예전 문구를 봅니다.

앱 자체의 UI 문구는 `tr('已选 {count}', { 'count': count })` 또는 `context.tr`로 호출하며, 8개 언어 리소스는 `assets/i18n/`에 있습니다. 추가하거나 바꿀 때는 모든 언어를 함께 고치고 자리 표시자를 맞추세요.

## 배포

### 저장소

저장소는 `index.json` 하나이며 어떤 정적 호스팅에도 둘 수 있습니다. 사용자는 '더 보기 → 사이트 → 사이트 추가'에 주소를 입력해 둘러보고 설치하고 업데이트합니다.

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
      "sha256": "스크립트 UTF-8 원문의 64자리 16진 SHA-256",
      "apiVersion": 2
    }
  ]
}
```

`url`은 스크립트의 전체 주소이며 `index.json` 기준 상대 경로인 `file`도 쓸 수 있습니다. 타사 저장소는 사용자가 확인한 뒤 직접 설치하며, `sha256`은 선택이고 있으면 내려받은 내용을 검증합니다.

### 버전과 업데이트 규칙

- 플러그인은 공식 목록과 일치하는 minAppVersion(예: 0.9.2)을 선언해야 합니다. 현재 apiVersion은 2이며 HentaiPark 0.9.2 이상이 필요합니다. 업데이트와 URL 설치는 교체 전에 호환성을 확인하며, 호환되지 않으면 기존 플러그인을 유지합니다. 자동 알림은 바로 업데이트할 수 있는 항목과 앱 업데이트가 필요한 항목을 구분합니다. 이 버전 알림 끄기는 표시된 앱 또는 플러그인 버전에만 적용되며 재시작 후에도 유지됩니다. 수동 확인에는 영향을 주지 않습니다.

- 버전은 점으로 구분하고 앞에 0이 없는 음이 아닌 정수 세 개 (예: `0.0.1`)이며 부분마다 숫자로 비교합니다. 빠진 부분, 남는 부분, 프리릴리스 접미사는 받지 않습니다.
- 공식 업데이트에는 스크립트 UTF-8 원문의 `sha256` (공백 정리나 줄바꿈 변환 없음)이 있어야 하고, 스크립트가 선언한 `key`, `version`은 인덱스와 같아야 합니다. `apiVersion`이 현재 앱 런타임과 정확히 같지 않으면 업데이트를 거부합니다.
- 플러그인과 앱의 버전은 따로 관리합니다. 플러그인 스크립트 (`i18n` 포함)를 바꾸면 스크립트와 `assets/sources/index.json`의 버전을 함께 올립니다. 배포 도구는 다운그레이드와 같은 버전에 다른 내용을 거부합니다.

### 앱 안의 공식 업데이트

- '더 보기 → 사이트'와 '더 보기 → 정보 → 업데이트'의 '시작 시 플러그인 업데이트 확인'은 기본으로 켜져 있습니다. 실행할 때마다 공식 인덱스만 읽어 새 버전이 있으면 알리고, 사용자가 확인한 뒤 다운로드·검증·설치합니다. 포그라운드로 돌아올 때는 12시간 간격을 유지하며 실패해도 확인 시각을 기록합니다. 자동 확인을 꺼도 직접 확인할 수 있습니다. 설치된 내장·공식 플러그인만 확인하며, 새 플러그인을 자동 설치하거나 같은 key의 타사 플러그인을 넘겨받지 않습니다.
- 설치할 때 식별, 버전, 출처, API, 다이제스트를 다시 검증하고 초기화와 상태 저장이 성공해야 완료됩니다. 실패하면 이전 스크립트와 사용자 상태를 유지하고, 설치 중 중단되면 다음 실행 때 복구합니다. 실행할 때 앱에 포함된 스크립트로 기존 플러그인을 덮어쓰지 않으며, 스크립트가 없으면 등록 정보와 사용자 데이터를 남기고 사용자가 복원하거나 업데이트할 때까지 기다립니다. '기본 제공 버전으로 되돌리기'는 확인 후 현재 앱에 포함된 버전으로 돌아갑니다.
- 앱 업데이트도 기본으로 확인합니다. Android에서는 사용자가 확인하면 기기에 맞는 공식 APK를 앱 안에서 내려받고 크기, SHA-256, 패키지 이름, 버전, 서명을 검증한 뒤 시스템 설치 화면을 엽니다. 진행 표시, 취소, 다시 시도를 지원하며 공식 릴리스 페이지가 예비 입구입니다.

### 공식 플러그인 배포

공식 플러그인은 `assets/sources/index.json`에서 관리합니다. `tools/publish_sources.mjs`는 목록과 런타임 선언을 오프라인으로 대조하고 변경되지 않는 스크립트 URL과 SHA-256을 포함한 배포 색인을 생성합니다. 로그인이나 사이트 메서드를 실행하지 않으므로 실제 요청 검증을 대신할 수 없습니다. 빌드와 배포 절차는 [개발 안내](../../DEVELOPMENT.md)를 참고하세요.

### 빌드로 생성되는 플러그인

Telegram 플러그인의 유일한 구현은 `assets/sources/telegram_entry.mjs`이며, `assets/sources/telegram.js`는 빌드로 생성되므로 직접 고치면 안 됩니다.

```powershell
npm ci --prefix 'tools/source-runner'
node tools/build_subscription_sources.mjs
```

[@mtproto/core 6.3.0](https://github.com/alik0211/mtproto-core) (GPL-3.0, [라이선스](../../licenses/mtproto-core.txt), 의존성 목록은 [타사 라이선스](../../licenses/telegram-dependencies.txt))을 씁니다. 사이트 대응 부분이 전송, 암호, 저장을 대체하며 라이브러리 기본 WebSocket, 브라우저 localStorage, 디버그 로그는 쓰지 않습니다.

### `webVideo(id, episodeId)`

웹 재생은 독립된 임시 세션에서 Cloudflare 인증을 처리합니다. 정확히 `challenges.cloudflare.com`인 인증 하위 프레임만 허용하며 해당 호스트로의 주 프레임 이동은 허용하지 않습니다. `network.confirmation`은 소스가 선언한 도메인에만 적용하고 외부 플레이어에는 적용하지 않습니다. 자동 처리가 끝나지 않으면 수동 조작을 위해 페이지를 유지하며 플레이어 Cookie는 가져오거나 내보내지 않습니다. `CONFIRM_REQUIRED`는 플러그인 안내를 유지하고 앱 내 확인 페이지에서 명시적으로 완료한 뒤 소스 세션을 동기화합니다. 원래 작업은 자동 재전송하지 않습니다.

iXXX와 TubeSafari의 지원되는 출처는 네이티브 재생을 우선하며 이어 보기와 오프라인 저장을 지원합니다. 지원되지 않는 출처는 앱 내 웹 재생을 사용합니다. 웹 재생은 사이트 확인이 필요할 수 있으며 앱 다운로드와 정확한 이어 보기를 지원하지 않습니다. Android 웹 재생에는 격리 세션을 지원하는 최신 Android System WebView가 필요합니다.

런타임은 `capabilities.webVideo`를 자동으로 내보냅니다. `webVideo`만 구현하면 앱 내 웹페이지를 엽니다. `videos`와 `webVideo`를 모두 구현하면 네이티브 재생을 우선하며 `videos`가 `UNSUPPORTED`를 반환할 때만 웹 재생으로 전환합니다. HTTP, 네트워크, Cloudflare, 로그인, 파싱, 삭제 및 취소 오류는 그대로 표시합니다. 다운로드는 성공적으로 해석한 네이티브 미디어만 지원하며 웹페이지로 전환하지 않습니다.

```js
return { url: "https://player.example.com/watch/1", navigationDomains: ["player.example.com"], frameDomains: [] };
// Native HTTP only: this.http.get(url, { followRedirects: false })
```

## 순위 및 별도 배포

`rankings`는 `key`, `label`, `category`, `metric`, `options`로 정의합니다. 순위 전용 플러그인은 `rankingOnly: true`이며 `feeds`를 선언하지 않습니다. `ranking(board, {page, offset, cursor, options})`는 작품 페이지를 반환하며 항목은 `id`, 원본 `rank`, `title`, `cover`, 선택적인 `keyword`, `subtitle`, HTTPS 상품 `url`을 포함합니다. 공동 순위를 유지합니다. 기존 소스는 `feed`를 지정하여 옵션을 상속하고 `feed()`를 재사용할 수 있습니다. 작품 필드를 유지하고 `workId`와 누락된 순위를 추가하여 상세 페이지를 엽니다. 판매 순위는 지정 분류를 검색합니다.

소스는 기본 브랜치에서 관리합니다. `sources`, `rankings`, `reverse-search` 브랜치는 각각 일반 사이트, 순위 전용, 이미지 역검색 전용 플러그인을 배포합니다. 각 브랜치에는 고정 커밋 URL과 SHA-256을 담은 색인만 저장합니다. 앱은 채널을 따로 읽고 채널 불일치와 중복 key를 거부하며 업데이트 전에 확인을 요청합니다. 태그 번역은 별도 `tag-translations` 브랜치로 배포합니다.

```powershell
node tools/publish_sources.mjs --commit '<SHA>' --channel rankings --output '<本地输出文件>'
```

## 댓글과 콘텐츠 링크

`comments`를 구현하면 런타임이 `capabilities.comments`를 자동으로 내보냅니다. `resolveContentLink`와 `searchLink`도 같은 이름의 기능을 내보냅니다. 검증된 읽기 작업만 선언하세요. 댓글·답글 작성, 추천, 신고 작업은 포함하지 않습니다.

공식 댓글 구현에는 Reddit, myfans, Fansly, GalgameX, XVideos, Pornhub Shorties, PicACG, SpankBang, X / Twitter, Telegram이 포함됩니다. 읽을 수 있는 범위는 원본 사이트 권한을 따릅니다. X / Twitter와 Telegram은 로그인이 필요하며 Telegram은 토론이 활성화된 게시물을 지원합니다. 직접 표시할 수 없는 첨부에는 정확한 원본 댓글 링크를 유지합니다.

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

- `WorkItem`, `WorkDetail`, `SubscriptionPost`의 선택적 최상위 필드 `commentsAvailable?: boolean`은 해당 작품의 댓글 활성화 여부를 나타냅니다. 엄격한 불리언 값 `false`이면 댓글 진입 버튼을 숨기며, `true`여도 소스의 `capabilities.comments`가 필요합니다. 생략하거나 불리언이 아니면 알 수 없는 상태로 보고 소스 기능에 따라 표시합니다. 댓글 수 0은 댓글이 비활성화되었다는 뜻이 아닙니다. 읽는 중 원본 게시물의 댓글이 비활성화된 것으로 확인되면 빈 목록으로 감추지 말고 `UNSUPPORTED`를 발생시킵니다.
- `workId`는 소스의 작품 식별자이며 `context`는 원본 페이지, 회차 또는 순위 정보를 담습니다. 작품과 회차별 댓글을 분리하세요.
- `id`는 소스 내에서 안정적인 비어 있지 않은 문자열입니다. `author.name`은 비워 둘 수 있지만 이름을 지어내면 안 됩니다. 본문에는 비어 있지 않은 텍스트나 유효한 이미지가 필요하며 이미지 전용 댓글도 보존합니다. `date`는 원본 표시 또는 ISO 시각, `likes`와 `replyCount`는 음수가 아닌 수, `rating`은 0–5, `spoiler`는 스포일러 표시입니다.
- `replies`는 같은 구조를 사용하고 `parentId`는 부모 댓글을 가리킵니다. 부모 본문에 자식 답글을 섞지 마세요. `replyCount`는 원본 답글 수입니다. `parentId`로 읽기를 검증한 경우에만 `repliesAvailable: true`를 설정합니다. 기본값은 false이며 수치만으로 추가 읽기를 허용하지 않습니다. 사이트가 개수를 제공하지 않으면 `replyCount: 0`과 `repliesAvailable: true`가 함께 있을 수 있습니다. 개수를 만들어 내거나 이미 읽은 수로 진입을 막지 않고 '답글 보기'를 제공합니다. 중첩 답글을 읽을 때 요청의 `parentId`에는 선택한 댓글의 `id`를 전달합니다.
- `hasNext`는 실제 응답에 근거합니다. 커서에 인증 정보를 넣지 말고 다음 요청에 그대로 전달합니다. ID 중복, 총수 도달 또는 명시적 종료 시 멈추며 검증하지 않은 페이지 이동은 false로 반환합니다. `sorts`에는 검증된 정렬만 넣고 `label`은 UI 번역 키를 사용합니다.
- 페이지 스냅샷이 바뀌면 `reset: true`, 다시 읽은 실제 `page`(보통 1), 새 커서를 반환하여 기존 목록을 교체합니다. 첫 페이지를 다음 페이지로 위장하지 마세요. 업무 오류, 로그인 요구, 파싱 오류는 해당 오류를 던지고 빈 목록으로 숨기지 않습니다.

`Park.comments.html(html, baseUrl)`은 텍스트, 줄바꿈, 링크, 이미지, 인용을 안전한 조각으로 변환하고 실행 가능한 내용을 제거합니다. `Park.comments.text(text)`는 일반 텍스트의 명시적인 HTTP(S) URL을 링크로 나눕니다. `Park.comments.url(value, baseUrl)`은 유효한 HTTP(S) URL 또는 null을 반환합니다. 아바타, 프로필, 본문 URL에 userinfo를 포함하면 안 됩니다. 프레임워크는 구조화된 데이터만 표시하며 원본 HTML을 실행하지 않습니다. 사이트 필드 파싱은 플러그인이 담당하고 요청은 `this.http`로 보냅니다.

`resolveContentLink`는 정확한 호스트, 검증된 경로와 매개변수만 식별하며 대상이 아니면 null을 반환합니다. 작품에는 `type: 'work'`, 원본 검색에는 `type: 'search'`, 다른 안전한 페이지에는 `type: 'external'`을 사용할 수 있습니다. 프로필, 댓글 앵커, 날짜, 댓글 번호, 재생 시각을 작품으로 오인하지 마세요. `searchLink`는 원본 URL 전체를 받아 검색어, 필터, 분류, 페이지 의미를 유지한 기존 WorkPage를 반환합니다. 검색어만 추출하여 다른 매개변수를 버리거나 쓰기 엔드포인트에 접근하면 안 됩니다. 인식되지 않은 링크는 원본 페이지를 열 수 있게 유지합니다.

## 읽기 전용 라이브 채팅

`capabilities.liveChat`은 `liveChat(id)`와 `liveChatEvent(state, event)`를 모두 구현한 경우에만 선언합니다. 공식 지원은 CAM4, XLoveCam, Stripchat, SOOP입니다. `chat.domains`는 호스트와 포트의 독립 허용 목록으로 페이지·이미지·미디어 권한을 상속하지 않습니다. `host`는 443만 허용합니다. 비표준 포트는 `host:port`로 명시해야 하며 범위는 1024–65535입니다. `*.host:port`는 해당 포트의 한 단계 하위 도메인만 허용하고 기본 호스트, 여러 단계 하위 도메인, 다른 포트는 허용하지 않습니다. HTTPS/SSE와 WSS만 허용하며 평문 통신, 사용자 정보, 프래그먼트는 금지합니다. 게스트 초기화의 임시 토큰은 다른 호스트나 포트로 리디렉션할 수 없습니다.

`liveChat`은 `transport: "sse" | "websocket"`, `url`, 선택적 `headers`, `state`를 반환합니다. 게스트 초기화 요청에는 `this.chatHttp.request({url, method, headers, body|json})`를 사용하며 현재 호출의 취소 신호를 공유합니다. Cookie는 소스별로 분리하고 토큰, 연결 URL, 상태, 메시지는 메모리에만 보관합니다.

- `protocols`: WebSocket 전용. 중복되지 않는 비어 있지 않은 RFC token 문자열을 최대 8개 지정하며 각각 128자 이하여야 합니다.
- `binary: true`: WebSocket 전용. UTF-8 이진 프레임으로 송수신하지만 플러그인의 `event.data`와 `send`는 계속 문자열입니다. 프레임당 최대 65536바이트이며 UTF-8을 엄격하게 검사합니다. 기본값은 텍스트 프레임입니다.
- `heartbeatIntervalMs`: 선택적 10000–60000 정수입니다. 연결 성공 후 해당 간격으로 `{type: "tick"}`을 같은 직렬 이벤트 큐에 넣습니다. 중지하거나 페이지를 떠나면 취소됩니다. tick은 연결 핸드셰이크나 SSE 수신 제한 시간을 연장하지 않습니다.

연결 설정과 프로토콜 핸드셰이크에는 합계 25초의 고정 제한 시간이 적용됩니다. `heartbeatIntervalMs`를 선언하지 않은 WebSocket은 30초 간격의 네이티브 ping/pong을 사용합니다. 이 필드를 선언하면 대신 플러그인 tick으로 연결을 유지하고 실제 전송 오류나 종료 이벤트로 연결 끊김을 판단합니다. 두 방식 모두 채팅 텍스트가 없다는 이유만으로 연결 끊김을 판단하지 않으며, 로컬 tick도 서버가 살아 있다는 증거가 아닙니다. SSE는 서버 데이터 수신에 계속 90초 제한 시간을 사용합니다.

`liveChatEvent`는 `{type: "open"}` 또는 `{type: "message", data, event?}` 또는 `{type: "tick"}`를 받으며 SSE 이벤트 이름을 보존합니다. 새 `state`와 선택적 `connected`, `error`, `messages`, `send`를 반환합니다. 메시지는 안정적인 `id`, 일반 텍스트 `text`, 선택적 `author`, `isHistory`를 사용합니다. 기록은 중복 제거에만 사용합니다. `send`는 검증된 인증·구독·하트비트 응답 전용이며 사용자 발언 API를 제공하지 않습니다.

호스트는 프레임, 큐, 캐시 및 재시도 횟수를 제한합니다. 재연결 시 새 게스트 토큰을 받고 실패 시 재시도를 표시합니다. 채팅 끄기, 화면 가림, 백그라운드, 앱 잠금, 플레이어 해제 시 즉시 취소하고 오래된 콜백을 무시합니다. 작품 댓글, 기록 페이지 또는 녹화 타임라인 댓글을 의미하지 않습니다.

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
