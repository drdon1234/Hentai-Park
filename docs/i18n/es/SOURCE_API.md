[简体中文](../../SOURCE_API.md) · [繁體中文](../zh-Hant/SOURCE_API.md) · [日本語](../ja/SOURCE_API.md) · [한국어](../ko/SOURCE_API.md) · [English](../en/SOURCE_API.md) · [Español](SOURCE_API.md) · [Русский](../ru/SOURCE_API.md) · [العربية](../ar/SOURCE_API.md)

# API de plugins de sitios

[Inicio rápido](#inicio-rápido) · [Campos del manifest](#campos-del-manifest) · [Métodos](#métodos) · [API del entorno](#api-del-entorno) · [Códigos de error](#códigos-de-error) · [Localización](#localización) · [Publicación](#publicación) · [Apéndice: notas sobre los sitios oficiales](#apéndice-notas-sobre-los-sitios-oficiales)

Cada sitio de HentaiPark es un plugin JavaScript independiente. La app carga los plugins en tiempo de ejecución; se pueden instalar desde un repositorio, actualizar, activar o desactivar **sin recompilar la app**. Los plugins oficiales están en [`assets/sources/`](../../../assets/sources/) y sirven de ejemplo.

La versión en chino simplificado de este documento es la de referencia. Las reglas de cada sitio viven en su plugin; la red, la caché y las imágenes las aporta el framework, que nunca trata un sitio de forma especial por su nombre.

## Inicio rápido

### Entorno

- Los plugins se ejecutan en un WebView sin interfaz dentro de la app, con JS moderno y `DOMParser`. La capa nativa aporta criptografía, cookies y HTTP nativo; el HTTP nativo no tiene restricciones CORS, mientras que la red del navegador y los medios siguen sus propias reglas, descritas más abajo.
- El entorno de un plugin arranca la primera vez que se usa el sitio y se libera tras unos 5 minutos de inactividad o cuando hay más de 6 en marcha. Los manifests se guardan en caché por «SHA-256 del script + versión del entorno», así que abrir la app no ejecuta plugins. No supongas que un plugin está en marcha nada más arrancar la app.
- El mismo entorno ([`assets/runtime/park_runtime.js`](../../../assets/runtime/park_runtime.js)) funciona en Node, de modo que puedes probar contra sitios reales mientras desarrollas. El host de Node es una herramienta de desarrollo, no un entorno aislado para scripts no fiables.

### Un plugin mínimo

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

### Probarlo en Node

Instala las dependencias del runner compartido en la raíz del repositorio y crea un `test/source-smoke.mjs` ignorado como este. El ejemplo solo carga el manifest; cuando cambies un plugin, verifica también con solicitudes reales la primera y la segunda página, la búsqueda, los detalles, la decodificación de portadas y los capítulos o los medios de vídeo.

```js
import { loadSource } from '../tools/source-runner/host.mjs';
const { manifest } = await loadSource('nhentai.js');
console.log(manifest.key, manifest.version);
```

```powershell
npm ci --prefix 'tools/source-runner'
node 'test/source-smoke.mjs'
```

## Campos del manifest

```js
Park.register({
  key: 'mysite',              // único y permanente; solo [A-Za-z0-9_-], 1–100 caracteres, no _app
  name: '我的站点',
  version: '0.0.1',           // tres números; la app ofrece actualizar si el repositorio tiene uno mayor
  type: 'comic',              // comic | video | novel | game: cómo se leen o reproducen las obras
  category: 'doujin',         // doujin | anime | aiDrama | jav | adult | shortvideo | gallery | novel | game | other
  color: '#E5355F',           // color de marca: icono y página del sitio
  description: '一句话介绍',
  homepage: 'https://example.com',
  domains: ['example.com'],                   // sitios a los que pertenece, ver «Aislamiento y seguridad»; si falta, se deduce de homepage, etc.
  linkPatterns: ['example\\.com/g/(\\d+)'],   // los enlaces pegados abren la obra; el grupo 1 es el ID
  idPattern: '^(\\d+)$',                      // los ID escritos abren la obra
  imageHeaders: { Referer: 'https://example.com/' },  // cabeceras por defecto de portadas e imágenes
  network: { mode: 'native', vpnHint: true },  // ver «Red»
  media: { mode: 'browser', origin: 'https://example.com', domains: ['media.example.com'] },  // permiso opcional de medios HLS
  imageNetwork: { mode: 'browser', origin: 'https://img.example.com', domains: ['img.example.com'] }, // opcional
  imageDecrypt: { /* opcional, ver «Imágenes cifradas» */ },

  settings: [ /* opciones, ver «Opciones» */ ],
  account: { /* opcional, ver «Cuentas» */ },
  defaultFeed: 'ranking',     // pestaña que se abre por defecto en la página del sitio (una key de feeds)
  feeds: [ /* pestañas de la página del sitio */ ],
  searchFilters: [ /* filtros de búsqueda */ ],
  searchHint: '搜索技巧提示',
  i18n: { /* traducciones propias de la interfaz, ver «Localización» */ },

  subscription: { /* opcional: seguir canales/creadores, ver «Suscripciones» */ },
  updateSubscriptions: { /* opcional: suscripciones de actualizaciones */ },

  async init() {},              // opcional: se llama una vez al arrancar el entorno (p. ej. refrescar dominios)
  async onSettingsChanged() {}, // opcional: se llama tras cambiar los ajustes del sitio
  // más los métodos de «Métodos»
});
```

Las capacidades (`capabilities`) las exporta el entorno a partir de los métodos implementados; no las escribas a mano.

### Tipo y categoría

`type` decide cómo se leen, reproducen o tratan como recursos de juego las obras; `category` decide dónde aparece el sitio en Explorar, en la gestión de sitios y en la búsqueda. Las categorías desconocidas o ausentes van a «Otros». Los sitios nuevos deben declarar con precisión su tipo, categoría y capacidades.

| Categoría | Significado |
| --- | --- |
| `doujin` | Doujinshi y cómics |
| `gallery` | Galerías: ilustración, cosplay y sesiones de fotos. Los sitios de imágenes siguen declarando `type: 'comic'`; una galería es una obra y sus imágenes salen en orden de `chapter()`, así que lectura, favoritos y descargas funcionan igual. La categoría no depende del número de imágenes ni del contenido |
| `anime` | Anime adulto |
| `aiDrama` | Dramas cortos de IA. No se acepta el antiguo `drama`; declara los nombres de canal del sitio tal cual, la categoría de la app no los filtra |
| `jav` | Sitios dedicados a JAV |
| `adult` | Vídeo adulto general (Pornhub, XVideos, 91porn…), `type: 'video'`. Una categoría es una agrupación; no sustituye las etiquetas del sitio ni los filtros del usuario |
| `shortvideo` | Vídeos cortos: flujo vertical a pantalla completa, ver abajo |
| `novel` | Novelas, `type: 'novel'` |
| `game` | Juegos, `type: 'game'` |
| `other` | Todo lo demás (sitios de suscripción, etc.) |

- **Vídeos cortos** (`type: 'video', category: 'shortvideo'`): obras, búsqueda, favoritos e historial abren directamente el flujo. Cada obra es un vídeo y `videos(id, '_')` devuelve su medio actual; no hace falta página de detalles. `hasNext` y `cursor` de `feed` cargan la página siguiente cerca del final; los cursores no deben contener credenciales ni firmas de medios. Al refrescar se empieza por la primera página; el elemento actual se reproduce, el siguiente se precarga en pausa y el resto se libera. No declares `search` si el sitio no tiene búsqueda.
- **Agregadores que solo reproducen en el sitio original**: siguen declarando `type: 'video', category: 'adult'`; sin una API de medios verificada no implementan `videos` y el entorno exporta `capabilities.videos: false`. El botón principal abre `detail.url` en el navegador del sistema, se ocultan reproducción, descargas y episodios, no se guardan capítulos falsos ni se comprueban actualizaciones; favoritos e historial siguen funcionando.
- **Novelas** y **juegos** se explican en «Métodos».

Elige `defaultFeed` en el orden **recomendados > clasificaciones > populares**; usa la página de novedades u otra entrada válida solo si el sitio no tiene ninguna de ellas, y nunca inventes una API no verificada. Si falta o no existe, la app elige por la key (primero `promote` / `recommend` / `featured`, luego `rank` / `toplist`, luego `popular` / `hot` / `trending`) y, si nada encaja, la primera pestaña.

### Opciones

`feeds[].options`, `searchFilters` y `settings` comparten formato:

```js
{ key: 'sort', label: '排序', type: 'select', default: 'date',
  values: [{ value: 'date', label: '最新' }, { value: 'popular', label: '热门', color: '#f00' }] }
// type: select | multi | number | text | password | switch
// en settings se puede usar options en lugar de values
```

Cada entrada de `feeds` es una pestaña de la página del sitio: `{ key, label, options?: [...] }`.

### Red

- `network.mode: 'native'` (por defecto): HTTP nativo con cookies persistentes, usando el proxy del usuario. Un desafío de Cloudflare lanza `CLOUDFLARE`; la app guía al usuario por la verificación en el navegador integrado y sincroniza las cookies de paso con las solicitudes nativas.
- `network.mode: 'browser'` + `network.origin`: las solicitudes se hacen con `fetch()` del mismo origen desde una página oculta abierta en `origin`, con la huella de un navegador real — para sitios con protección estricta de Cloudflare. Si un GET del mismo origen recibe un desafío, el navegador oculto navega a él para superarlo y reintenta una vez; si falla, lanza `CLOUDFLARE`.
- `network.vpnHint: true`: decláralo en sitios que puedan necesitar VPN o proxy en China continental; las esperas de más de 8 segundos y los fallos mencionarán «puede necesitar VPN o proxy». No atribuyas todos los errores a la VPN.
- `network.confirmation: { selector, readySelector, requiredCookies, message }`: para sitios que exigen una confirmación explícita (como una verificación de edad). `selector` encuentra el diálogo, `readySelector` el contenido accesible y `requiredCookies` las cookies que deben existir después. Ante una página sin confirmar, el plugin lanza `Park.error('CONFIRM_REQUIRED', message, { url })`; la app muestra «Confirmar» y vuelve cuando el diálogo desaparece, el contenido es visible, las cookies se han escrito y la navegación se ha estabilizado. La app nunca confirma por el usuario, y esta declaración también evita que una verificación genérica tome la de edad por superada.
- Los errores de red llevan los campos seguros `diagnostics` `host`, `transport` y `reason`, que distinguen certificados TLS, negociación, DNS, conexión y tiempos de espera; los registros automáticos solo guardan esos campos. `reason: 'TLS_HANDSHAKE_TERMINATED'` solo significa que `HandshakeException.message` nativo es exactamente `Connection terminated during handshake` (la conexión se cortó antes de completar la negociación, no un fallo de certificado); solo los GET/HEAD HTTPS sin cuerpo se reintentan una vez, y nada más se reintenta.

### Imágenes

- `imageNetwork: { mode: 'browser', origin, domains }`: decláralo cuando una CDN de imágenes necesite solicitudes desde el navegador. `origin` y todos los dominios de imágenes deben estar en `domains`; solo HTTPS y cabeceras permitidas; las solicitudes no llevan credenciales, no siguen redirecciones y se limitan a 20 MiB por imagen, y siguen pasando por descifrado, comprobación de formato, decodificación y caché por sitio. Sin él se usa el transporte nativo.
- **Imágenes cifradas**: declara `imageDecrypt` y el framework descifra antes de comprobar el formato y guardar en caché; los ajustes de descifrado forman parte de la identidad en caché y los fallos no se guardan. Se admite AES-CBC con relleno PKCS#7 estricto, con `key` e `iv` en UTF-8; hay que limitar los dominios de imágenes, el resto usa la ruta normal.

```js
imageDecrypt: {
  type: 'aes-cbc',
  key: '0123456789abcdef', // 16, 24 o 32 bytes UTF-8
  iv: '0123456789abcdef',  // 16 bytes UTF-8
  domains: ['images.example.com'],
},
```

Que una portada devuelva HTTP 200 no basta: comprueba que se decodifica.

### Permiso de medios (HLS y archivos directos)

El permiso `media` es independiente de `this.http`, `network` y las cookies del sitio:

```js
domains: ['example.com'],
network: { mode: 'native' },
media: { mode: 'native', origin: 'https://example.com', domains: ['media.example.com'] },
```

- `media.mode` es `'native'` o `'browser'`. `media.origin` debe pertenecer a los sitios del plugin, usar HTTPS en el puerto 443 y no llevar credenciales, consulta ni fragmento.
- `media.domains` es una lista aparte de dominios de medios (con subdominios) que no da acceso a cookies del sitio. Listas, segmentos y claves deben ser HTTPS en 443; se rechazan credenciales en la URL, fragmentos, IP, localhost (y subdominios) y `.local`.
- `'native'` usa un cliente nativo aparte y sin credenciales: sin cookies del sitio, Authorization ni autenticación de proxy; cada salto de redirección se comprueba antes. Solo se permiten `Referer`, `Origin`, `Accept` y `Accept-Language`, y las dos primeras deben coincidir con `media.origin`.
- `'browser'` abre una sesión de medios en un navegador oculto en `media.origin` con `credentials: 'omit'`, `mode: 'cors'` y `redirect: 'error'`.
- Las respuestas se limitan en tamaño mientras llegan y se vuelve a comprobar su dirección final: listas de hasta 2 MiB, segmentos de hasta 32 MiB y claves AES-128 de exactamente 16 bytes. Se rechazan respuestas demasiado grandes o vacías y direcciones no permitidas.

### Aislamiento y seguridad

- Cada plugin se ejecuta en su **propio** entorno JS (su propio WebView sin interfaz), así que no ve las variables globales de los demás; el puente nativo sabe qué entorno lo llama, por lo que un script no puede hacerse pasar por otro plugin.
- Cada plugin tiene su **propio almacén de cookies**: sus solicitudes solo llevan y guardan sus cookies.
- Las cookies Secure nunca se envían por HTTP. Abrir páginas de verificación e importar cookies del navegador se comprueba contra los `domains` del plugin instalado, conservando los atributos de seguridad y la caducidad disponibles. Borrar las cookies de un sitio o desinstalarlo también cierra su sesión del navegador y borra sus cookies del navegador; esas cookies las comparte el sistema, así que los plugins que declaren el mismo sitio se ven afectados por esa limpieza.
- `domains` declara a qué sitios pertenece un plugin (dominios registrables, con subdominios). Solo las cookies de esos sitios se sincronizan con el navegador integrado (compartido por la verificación de Cloudflare y el inicio de sesión web), y `network.origin` en modo navegador debe pertenecer a ellos. Si falta, se deduce de `homepage`, `network.origin` y `account.cookieUrl/loginUrl`.
- Las redirecciones entre orígenes descartan las cabeceras de autenticación del origen inicial; las que conservarían un cuerpo de solicitud se rechazan. La validación de certificados TLS siempre está activa.
- Al instalar desde una URL o un repositorio, la app lee primero el script en un entorno sin red y muestra nombre, versión, SHA-256, sitios declarados y riesgos; no instala nada hasta que el usuario confirma.

### Cuentas

```js
account: {
  type: 'password' | 'cookies' | 'session',
  title, hint, required: false,
  fields: [{ key: 'email', label: '邮箱' }, { key: 'password', label: '密码', secret: true }],
  loginUrl?, cookieUrl?, requiredCookies?: ['ipb_member_id'],   // permite iniciar sesión en la web; la app recoge las cookies
  loginDomains?: ['accounts.google.com', 'appleid.apple.com'],  // dominios de inicio de sesión de terceros, solo para navegar al iniciar sesión
  async login(values) { return { name } },
  async logout() {},
  async status() { return { loggedIn, name, configured } },
  managedAccount: true,                 // opcional: ofrece una cuenta gestionada automáticamente
  async enableManaged() {},             // solo se llama tras aceptar el usuario el registro
}
```

- El estado de la cuenta se refresca solo en el primer uso, tras iniciar o cerrar sesión o tras el inicio de sesión web, y cuando la última comprobación tiene más de 10 minutos; no después de cada llamada. `configured` indica que hay una cuenta configurada, funcione o no el inicio de sesión en ese momento.
- `loginDomains`: dominios de terceros que el sitio usa de verdad para iniciar sesión (con subdominios). Solo se permiten mientras el usuario tiene abierta la página de inicio de sesión web, y solo HTTPS en 443; se rechazan credenciales en la URL, IP, localhost y `.local`. Las páginas de verificación, la confirmación de acceso, las solicitudes del plugin y la importación de cookies se siguen comprobando contra `domains`; no añadas dominios de inicio de sesión a `domains` para ampliar el acceso. La página admite redirecciones en la misma ventana y ventanas emergentes que conservan `window.opener`, con las mismas comprobaciones; una página inicial en blanco no da navegación externa. No se considera iniciada la sesión mientras se está en una página de terceros; las cookies se sincronizan al volver al sitio. Las cookies de terceros no se importan al almacén del plugin ni se borran con las del sitio; las gestiona el WebView del sistema. Los terceros pueden seguir limitando el inicio de sesión en navegadores integrados.
- `type: 'session'` importa una sesión ya autorizada: declara un campo secreto (como `session`); el contenido del portapapeles se conserva íntegro y lo valida el plugin, sin dividirlo en usuario, contraseña o cookies. El inicio de sesión debe confirmar la autorización de verdad; nunca informes de éxito solo por el formato de la entrada.
- `managedAccount: true` declara una cuenta gestionada automáticamente, controlada por un ajuste con el mismo nombre. La app debe explicar primero el registro automático y obtener el consentimiento, luego guardar el ajuste y llamar a `account.enableManaged()`. Guarda las credenciales candidatas y haz `await this.store.flush()` antes de registrar, para recuperar la misma cuenta tras un fallo o reinicio. Guarda por separado las credenciales manuales y la cuenta gestionada; esta nunca sustituye a una manual. Desactivar el ajuste conserva la cuenta gestionada para reutilizarla; un token caducado solo vuelve a iniciar sesión y nunca registra otra cuenta.
- Contraseñas, tokens y estado del plugin son datos locales del usuario; nunca pongas credenciales reales en documentos ni registros.

## Métodos

`this` dentro de los métodos se describe en «API del entorno». Todos los métodos pueden ser `async`.

```js
async feed(key, { page, cursor, options }) {}      // pestañas de la página del sitio
async search({ keyword, page, cursor, filters }) {}
async random() {}                                  // devuelve un ID de obra
async detail(id, preview) {}
async chapter(id, chapterId) {}                    // cómics, galerías
async resolveImage({ id, chapterId, index, token, retry }) {}  // opcional: resolución diferida de imágenes
async thumbnails(id, page) {}                      // opcional: miniaturas de vista previa por páginas
async videos(id, episodeId = '_') {}               // vídeo
async textChapter(id, chapterId) {}                // novelas
async gameResources(workId) {}                     // juegos
async resolveGameResource(workId, resourceId, channelId) {}
```

### Listas: `feed` / `search`

```js
{
  items: [WorkItem], page: 1, totalPages: 20, total: 500,
  hasNext: true,
  cursor: '12345',        // opcional: los sitios con cursor devuelven el siguiente y la app lo reenvía tal cual
}
// o secciones, mostradas por bloques:
{ sections: [{ title: '连载更新', items: [WorkItem] }], hasNext: false }
```

**WorkItem**: `{ id, title, subtitle?, cover, coverAspect?, pages?, rating?, likes?, views?, language?, category?, badge?, badgeColor?, duration?, uploaded?, tags?, mediaKind? }`

- `coverAspect` (ancho / alto) permite colocar la cuadrícula antes de que carguen las imágenes.
- `badgeColor` colorea la insignia de categoría.
- `mediaKind: 'comic' | 'video' | 'novel' | 'game'` es el tipo de la propia obra. Los plugins de un solo tipo pueden omitirlo; los de tipos mixtos deben indicarlo: nunca trates imágenes como vídeos solo por el `type` del plugin. Las obras de novela y juego siempre lo indican, para que las obras sin conexión y el historial sigan abriéndose en el lector correcto tras desinstalar el plugin.
- Los resultados tipo publicación pueden incluir `presentation: 'post'`, `text`, `date`, `url` y un array `media` para mostrarse como tarjetas; `presentation: 'media'` muestra una cuadrícula que abre los medios dentro de la obra. Una publicación puede no tener medios; sus direcciones siguen sujetas a los dominios y permisos declarados.

### Detalles: `detail`

Todos los campos de WorkItem, más:

```js
{
  url, authors: [], description, uploader?, size?, comments?,
  tags: [{ namespace: 'artist', label: '作者', tags: [{ name, keyword, filters?, count? }] }],
  chapters: [{ id, title }] | null,   // null significa un solo capítulo
  singleChapterId?,                   // ID de capítulo que necesitan las obras de un solo capítulo
  thumbnails?: [url | { url, width, height, offsetX, offsetY }],   // admite sprites
  related?: [WorkItem], series?: [WorkItem],
}
```

- Al tocar una etiqueta se busca en este sitio con `keyword` y `filters`, así que las etiquetas pueden corresponder a la sintaxis propia del sitio (como `artist:"xxx"`) o a parámetros de filtro.
- El segundo argumento opcional `preview` lleva los metadatos públicos ya mostrados o guardados, y solo se pasa si `preview.source` y `preview.id` coinciden con la solicitud. El plugin debe seguir comprobando el ID y validando las URL. Las obras abiertas por ID escrito no tienen vista previa, así que título y portada pueden estar incompletos.

### Capítulos: `chapter` / `resolveImage` / `thumbnails`

```js
{ pages: [
  { url, headers?, fallbacks?: [url], width?, height?, transform? },  // dirección conocida
  { token: '12' },                                                      // diferida: la app llama a resolveImage
]}
```

- `fallbacks`: espejos que se prueban en orden si falla la dirección principal.
- `transform: { type: 'unscramble-strips', segments: N }`: para imágenes cortadas en N tiras guardadas al revés, que se restauran en la GPU. Los archivos sin conexión guardan la imagen original y se restauran al mostrarse.
- `resolveImage` devuelve `{ url, headers?, width?, height?, cacheKey? }`. Si falla, la app vuelve a llamar con un `retry` mayor, lo que permite cambiar de servidor.
- `thumbnails(id, page)` devuelve `{ thumbnails: [...], hasNext }`.

### Vídeo: `videos`

Devuelve `[{ quality: 1080, label: '1080P', url, headers?, format?, preferred? }]`. Los enlaces directos suelen caducar, así que la app los vuelve a pedir antes de cada reproducción o descarga.

- Los vídeos con varios episodios devuelven `[{ id, title }]` en orden de reproducción en `detail(id).chapters`; cada `id` debe ser estable, nunca una calidad ni una URL temporal. La app usa el mismo ID para elegir episodios, guardar el progreso, descargar y reanudar, y llama a `videos(id, episodeId)` para cada episodio. Los vídeos sueltos usan `singleChapterId`, o `'_'` si no existe.
- Sin `format`, reproducción y descarga tratan el enlace como MP4 directo. HLS debe devolver `format: 'hls'` y declarar el permiso `media`.
- La app expande una lista maestra HLS (`#EXT-X-STREAM-INF`) en listas por variante y toma la calidad real de `RESOLUTION`. Si devuelves una maestra, `quality` es la calidad deseada: se elige la mayor calidad real que no la supere o, si no hay, la más alta. Cada variante debe ser MPEG-TS con audio y vídeo multiplexados; se rechazan las versiones `AUDIO`, `VIDEO`, `SUBTITLES` separadas y las direcciones fuera de `media.domains`. Las pistas `#EXT-X-I-FRAME-STREAM-INF` se ignoran. Si una lista simple no tiene resolución conocida, usa `label: '原画'` en vez de presentar la calidad deseada como real.
- Solo se admiten listas VOD MPEG-TS completas y continuas con `#EXT-X-ENDLIST`; se descifra `METHOD=AES-128` con `KEYFORMAT=identity` (CBC/PKCS7), con claves de exactamente 16 bytes y un IV explícito o derivado de la secuencia. Las claves solo están en la memoria de la sesión. No se admiten directos, SAMPLE-AES, otros KEYFORMAT, `EXT-X-MAP`, `EXT-X-BYTERANGE`, fMP4, discontinuidades ni huecos; se elimina el `#EXT-X-TOKEN` no estándar.
- La reproducción usa un puerto aleatorio ligado a `127.0.0.1` y un token aleatorio, y sirve bajo demanda segmentos verificados desde un registro limitado de URL; cerrar la sesión cancela las solicitudes. Las descargas HLS sin conexión solo funcionan en Android por ahora: cada segmento se verifica y se guarda su SHA-256, se pueden reanudar y cancelar, y Media3 crea al final un MP4; solo los archivos completos llegan a la biblioteca sin conexión.

### Novelas: `textChapter`

Los plugins de novelas declaran `type: 'novel', category: 'novel'`; implementar `textChapter` exporta `capabilities.textChapter: true`. Listas y detalles indican `mediaKind: 'novel'` y `language: 'zh'` o `'en'`. Sin portada real, devuelve `cover: ''` y la app mostrará una portada de texto en lugar de pedir una imagen inventada.

```js
async textChapter(id, chapterId) {
  // El texto completo del capítulo; paragraphs debe ser un array de cadenas no vacías sin HTML.
  return { title: '章节标题', paragraphs: ['第一段正文。', '第二段正文。'] };
}
```

- Las novelas de varios capítulos devuelven ID estables en el orden de lectura confirmado del sitio en `detail.chapters`; los relatos sueltos usan `chapters: null` y, opcionalmente, `singleChapterId`.
- El plugin une en orden la paginación interna del capítulo; nunca añadas al texto el capítulo siguiente, respuestas de foro, anuncios ni recomendaciones. `Park.html.paragraphs(node)` extrae texto plano de forma genérica; los límites y la paginación del sitio siguen siendo cosa del plugin.
- Si el texto se corta por inicio de sesión, pago o permisos, lanza `LOGIN_REQUIRED`; nunca presentes una vista previa como capítulo completo.
- La app escribe `text.json` de forma atómica por capítulo; una descarga solo cuenta como completa si se escribió entera. El progreso y las notas usan posiciones UTF-16 en `paragraphs.join('\n\n')`; tamaño de letra, tipografía, sangría y otros ajustes solo afectan a la visualización. Marcadores y notas se guardan aparte de las descargas, entran en las copias de seguridad y sobreviven a borrar una descarga.

### Juegos: `gameResources` / `resolveGameResource`

Los plugins de juegos declaran `type: 'game', category: 'game'`; sus obras indican `mediaKind: 'game'` y no tienen `chapters` inventados. El entorno exporta `capabilities.gameResources` y `capabilities.resolveGameResource` a partir de los métodos.

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
  // Las nubes devuelven kind: 'external', urls: [todos los espejos/partes], url: urls[0].
}
```

- `gameResources` solo devuelve ID estables, metadatos y canales: nada de URL firmadas, contraseñas ni estados de descarga inventados. `testStatus` es `tested | untested | unknown`, copiado del sitio; los canales con `status: 'expired'` se desactivan.
- `resolveGameResource` solo se llama cuando el usuario toca o reintenta; su URL nunca se guarda ni se registra. Las contraseñas pueden guardarse con la tarea de descarga local, nunca en diagnósticos. No descartes enlaces de nube; si devuelves varios, `extractionCodes` puede ir uno a uno con `urls` (cadena vacía = sin código) y `extractionCode` sirve para un código común.
- Los canales que exigen responder declaran `requiresReply: true, replyText: 'la respuesta real'`; la app muestra «Responder y desbloquear enlaces» y el texto exacto, y solo llama tras la confirmación del usuario. Antes de resolver, el plugin debe volver a comprobar el primer mensaje: si ya está desbloqueado, solo lee; envía una sola vez y solo al tocar el usuario, guardando antes de forma fiable el estado de cuenta e hilo. Si el resultado no está claro, hay intentos repetidos o hace falta verificación dinámica, devuelve `CONFIRM_REQUIRED` con la URL del hilo y nunca reenvíes automáticamente; nunca respondas desde listas, detalles, precargas ni actualizaciones en segundo plano.
- Los enlaces directos declaran `media: { mode: 'native', origin, domains }`. Los archivos se descargan en streaming con un cliente aparte sin cookies; el framework se ocupa de HTTPS, la comprobación de dominio en cada salto, la de longitud, la limpieza al cancelar y la protección de los archivos terminados. No hay reanudación; reintentar vuelve a resolver la dirección y empieza de cero. Las nubes se abren en apps externas, limitadas a HTTP(S), FTP(S), magnet, ed2k y thunder, sin cookies del sitio. Los juegos no crean capítulos, progreso ni actualizaciones de capítulos, y la app nunca instala, descomprime ni ejecuta archivos.

### Suscripciones: `subscription`

Los plugins de suscripción (seguir canales o creadores) declaran un objeto `subscription`; el entorno exporta `capabilities.subscription` cuando existen `normalize` y `posts`, y el sitio aparece en Explorar → Suscripciones. Los que además declaran `feeds` aparecen también en las categorías normales.

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
  async mediaChunk(resource, offset) { return { base64, done }; }, // opcional
}
```

- `normalize` solo valida en local, para poder guardar objetivos sin sesión o sin conexión; acepta solo nombres de usuario o URL de perfil controladas del propio sitio. `resolve` y `targets` son opcionales; con `targets`, el manifest incluye `subscription.joinedTargets: true`.
- Los cursores de `posts` son cadenas opacas; la última página tiene `hasNext: false` y las páginas sin medios pueden seguir. `locked` indica falta de permisos; `previewOnly` marca vistas previas públicas: nunca hagas pasar una miniatura por el contenido completo.
- Los adjuntos autorizados sin enlace directo usan `media[].resource` e implementan `mediaChunk(resource, offset)`: como mucho 128 KiB por llamada, con offsets alineados a 128 KiB; el resource debe tener un `size` entero y una cadena `cacheKey` estable y no secreta que no cambie con credenciales ni referencias temporales. El framework comprueba el tamaño total y cada fragmento y escribe de forma atómica en su propia caché; un adjunto puede ocupar hasta 512 MiB y el resource no elige la ruta local. Ni los enlaces firmados ni los resources se guardan en los registros de suscripción.
- Guardar una suscripción nunca sigue ni se une a nada. Las acciones de escritura no verificadas deben llevar al usuario al sitio original; nunca sigas, te unas ni pagues en silencio.

### Suscripciones de actualizaciones: `updateSubscriptions`

Los plugins normales pueden ofrecer «seguir actualizaciones» con un objeto `updateSubscriptions` aparte. El entorno exporta `capabilities.subscriptionUpdates` solo si existe `check`; no cambia la categoría ni `capabilities.subscription`. Los metadatos incluyen `dimensions: [{ key, label, hint }]`; los menús de etiquetas pueden pasar la palabra clave original y los filtros.

- `normalize(dimension, input)` devuelve `{ id, label }`; `check({ dimension, target }, { cursor })` devuelve `{ items, hasNext, cursor }`. Los elementos son `{ id, title, kind, workId, chapterId }`, con `kind` limitado a `work | post | chapter`, ID estables y no vacíos y sin URL de medios, cookies ni credenciales. Los ID de capítulo incluyen la identidad de la obra para que el «Capítulo 1» de obras distintas no choque.
- `Park.enableUpdateSubscriptions(Park.__pending, rules)` ofrece un adaptador genérico; declara las dimensiones de forma explícita al final del script, con `searchFilters` y `seriesPattern` opcionales. `work` usa la lista real de capítulos; `posts`, la API de canal existente; `search` y `filter` usan la búsqueda, `code` coincide exactamente con códigos completos y `series` usa rutas de serie validadas contra los dominios del sitio. Los cursores de búsqueda guardan el número de página y el cursor del sitio.
- Las comprobaciones de búsqueda y publicaciones devuelven `windowed: true`, es decir, revisan las tres últimas páginas: la primera solo registra una referencia y las siguientes generan eventos de «nuevo contenido encontrado» por ID estable, sin presumir fecha de publicación. Los demás protocolos paginados revisan como mucho tres páginas por ronda, guardan cursores y candidatos y confirman en una transacción al terminar; las listas de capítulos nunca se truncan, con un máximo de 20.000 candidatos (superarlo es un error). Los fallos de red, permisos, verificación, listas vacías o análisis parcial deben lanzar errores explícitos, nunca un éxito vacío.
- Primer y segundo plano comparten el entorno del plugin, las particiones de cookies, las restricciones de dominio y el verificador. En segundo plano solo se inician los plugins necesarios y nunca se inicia sesión, se suscribe en el sitio, se descargan medios ni se saltan permisos. Un cambio de cuenta o de configuración del plugin rehace la referencia (renovar el token no).

## API del entorno

Dentro de los métodos, `this` ofrece:

| Miembro | Descripción |
| --- | --- |
| `this.http` | `request(opts)`, `get(url, opts)`, `post(url, opts)`, `text(url, opts)`, `json(url, opts)` |
| `this.config` | valores elegidos por el usuario en los ajustes del sitio (`default` si no hay) |
| `this.store` | almacén persistente clave-valor: `get(key, fallback)` / `set(key, value)` para tokens, listas de dominios, etc.; `await flush()` confirma la escritura y lanza un error si falla |
| `this.cookies` | `get(url)` / `set(url, { name: value })` / `clear(url)` |
| `this.log({ code, host, transport, reason })` | solo escribe estos campos permitidos; el texto libre se descarta para no filtrar credenciales ni URL |

Utilidades globales:

| Utilidad | Descripción |
| --- | --- |
| `Park.html.parse(text)` | devuelve un `Document` estándar para `querySelector` |
| `Park.html.text(node)` / `unescape(s)` / `strip(html)` / `paragraphs(node)` | texto |
| `Park.crypto.md5Hex(text \| text[])` | MD5, admite arrays |
| `Park.crypto.sha256Hex` / `hmacSha256Hex(key, text)` / `aesEcbDecrypt(base64, key)` / `uuid()` | implementaciones nativas |
| `Park.crypto.digestBytes('sha1' \| 'sha256', bytes)` | arrays de enteros 0–255, hasta 2 MiB |
| `Park.crypto.randomBytes(length)` | bytes aleatorios seguros, length de 1 a 65536 |
| `Park.utils.rateLimiter(ms)` | devuelve `wait()` y garantiza un intervalo mínimo entre solicitudes |
| `Park.utils.mapLimit(items, n, fn)` / `lruMap(n)` / `parseCount('1.2万')` / `formatDate(ts)` | otras utilidades |
| `Park.error(code, message, extra?)` | crea un error con código, ver «Códigos de error» |

### `http.request(opts)`

```js
await this.http.request({
  url, method: 'GET', headers: {}, params: { q: 'x' },   // params se añaden a la URL
  json: {...} | form: {...} | body: 'raw' | bodyBase64: '...',
  timeout: 15000,
  responseType: 'text' | 'base64',
});
// → { status, headers, body, url, ok, json() }
```

- `text()` / `json()` lanzan un error con respuestas no 2xx (404 → `NOT_FOUND`). Las cookies se guardan solas y se eligen de nuevo para cada destino de redirección.
- `bodyBase64` es un cuerpo binario (hasta 2 MiB) que no se combina con `body` ni con el modo navegador; sigue las mismas reglas de aislamiento de dominios, TLS y redirecciones que las solicitudes de texto. Los plugins no pueden abrir por su cuenta red del navegador, WebSockets ni acceso arbitrario a archivos.

## Códigos de error

Lanza con `throw Park.error(code, message, extra)`; la app reacciona según el código:

| code | Qué hace la app |
| --- | --- |
| `CLOUDFLARE` | «Verificar»: abre el navegador integrado |
| `CONFIRM_REQUIRED` | «Confirmar»: espera a que el usuario complete la confirmación de acceso declarada (`extra.url` apunta a ella) |
| `LOGIN_REQUIRED` | «Iniciar sesión»: abre la sección de cuenta de los ajustes del sitio |
| `NOT_FOUND` | muestra «Contenido no encontrado» |
| `BLOCKED` | muestra «Acceso restringido» (IP bloqueada, cuota agotada…); las imágenes no se reintentan |
| `NETWORK` | muestra «No se pudo conectar» con el motivo y «Reintentar» |
| `HTTP` / `PARSE` / `UNSUPPORTED` / `CONFIG` | muestra el mensaje del plugin y «Reintentar» |

### Mensajes estructurados

`message` es una **plantilla en chino** que sirve además de clave de traducción; pon las partes variables en `extra.params` en lugar de concatenarlas:

```js
throw Park.error('HTTP', '站点返回 HTTP {status}', { params: { status: res.status }, status: res.status });
throw Park.error('NOT_FOUND', '影片不存在');
```

La app traduce la plantilla primero con el `i18n` del plugin, después con el vocabulario común de la app, y rellena los marcadores con `params`. Una cadena concatenada no se puede traducir y los usuarios que no lean chino la verían en chino. `status`, `url` y `diagnostics` en `extra` funcionan como siempre.

### Caché de inicio y semántica de errores

- Los resultados en vivo de `feed` conservan todos los campos del plugin; la caché de inicio en disco solo guarda metadatos de visualización permitidos (ID, título, portada, etiquetas, autor de la subida, tipo de medio, categoría, estadísticas); no se escriben `url`, credenciales, listas de medios ni publicaciones. No pongas credenciales en ID, URL de portada ni cursores. Los resultados que necesitan medios dinámicos o publicaciones no se guardan en caché.
- Una caché antigua solo se muestra como contenido sin conexión ante errores explícitos `NETWORK` / `TIMEOUT`, y se marca como tal. Los fallos de inicio de sesión, confirmación, verificación humana, análisis y configuración deben lanzar sus propios errores; el framework nunca los disfraza de fallos de red, y un refresco iniciado por el usuario también muestra el error real.

## Localización

La interfaz admite `zh-Hans`, `zh-Hant`, `ja`, `ko`, `en`, `es`, `ru` y `ar` (el árabe va de derecha a izquierda). Escribe todo texto estático visible de un plugin (nombre, descripción, pestañas, opciones, ayuda de búsqueda, notas de cuenta, mensajes de error) en **chino simplificado**; el texto original es la clave de traducción.

Un plugin incluye sus propias traducciones en el `i18n` del manifest:

```js
Park.register({
  i18n: {
    'zh-Hant': { '发行日期': '發行日期', '影片不存在': '影片不存在' },
    'en': { '发行日期': 'Release date', '影片不存在': 'Video not found', '站点返回 HTTP {status}': 'The site returned HTTP {status}' },
    // igual para ja, ko, es, ru, ar
  },
  key: 'mysite',
  // …
});
```

- Orden de búsqueda: el `i18n` del plugin en el idioma actual → el `en` del plugin (salvo en chino simplificado) → el vocabulario común de la app (`assets/i18n/`, p. ej. «Ordenar», «Recientes», «Populares») → el texto original.
- Solo hace falta poner en `i18n` lo que la app no tiene ya; las palabras comunes reutilizan sus traducciones. Los marcadores `{name}` deben coincidir con el original.
- El contenido remoto (títulos, autores, etiquetas, descripciones), lo que escribe el usuario y las claves de protocolo guardadas no se traducen como texto de interfaz.
- Cambiar `i18n` es cambiar el plugin y exige subir la versión. Quien tenga una versión anterior verá el texto antiguo hasta actualizar.

El texto de la interfaz de la propia app usa `tr('已选 {count}', { 'count': count })` o `context.tr`; los ocho archivos de idioma están en `assets/i18n/`, y cada añadido o cambio debe actualizarlos todos con los mismos marcadores.

## Publicación

### Repositorios

Un repositorio es un solo `index.json` en cualquier alojamiento estático. Los usuarios escriben su dirección en Más → Sitios → Añadir sitio para explorar, instalar y actualizar:

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
      "sha256": "SHA-256 en 64 dígitos hexadecimales del texto UTF-8 del script",
      "apiVersion": 1
    }
  ]
}
```

`url` es la dirección completa del script; también vale `file` relativo a `index.json`. Los repositorios de terceros se instalan a mano tras confirmar el usuario; `sha256` es opcional y se comprueba si existe.

### Versiones y reglas de actualización

- Las versiones son tres enteros no negativos separados por puntos y sin ceros a la izquierda (p. ej. `0.0.1`), comparados numéricamente por partes; se rechazan partes de menos o de más y sufijos de prelanzamiento.
- Las actualizaciones oficiales deben aportar el `sha256` del texto UTF-8 del script (sin recortar espacios ni convertir saltos de línea), y la `key` y la `version` del script deben coincidir con el índice; `apiVersion` debe ser exactamente la del entorno de la app o se rechaza la actualización.
- Las versiones de plugins y de la app son independientes. Al cambiar un script (también su `i18n`), sube la versión en el script y en `assets/sources/index.json`; el publicador rechaza bajadas de versión y una misma versión con contenido distinto.

### Actualizaciones oficiales en la app

- «Buscar actualizaciones de plugins al iniciar», en Más → Sitios y Más → Acerca de → Actualizaciones, está activado por defecto: cada arranque solo lee el índice oficial, avisa de versiones nuevas y descarga, verifica e instala solo tras confirmar el usuario. Al volver al primer plano se respeta un intervalo de 12 horas y los fallos también registran la hora. Con las comprobaciones automáticas apagadas siguen funcionando las manuales. Solo se comprueban los plugins integrados y oficiales instalados; no se instalan plugins nuevos automáticamente ni se sustituyen plugins de terceros con la misma key.
- La instalación vuelve a verificar identidad, versión, origen, API y resumen, y solo termina cuando la inicialización y el guardado del estado salen bien; si falla, se conservan el script antiguo y el estado del usuario, y una instalación interrumpida se recupera en el siguiente arranque. Arrancar nunca sobrescribe plugins instalados con los scripts incluidos; si falta un script, se conservan su registro y sus datos hasta que el usuario lo restaure o actualice. «Restaurar la versión integrada» vuelve, tras confirmar, a la versión incluida en el paquete actual.
- Las actualizaciones de la app también se comprueban por defecto: en Android, tras confirmar, la app descarga el APK oficial adecuado, verifica tamaño, SHA-256, nombre de paquete, versión y firma y abre el instalador del sistema, con progreso, cancelación y reintento; la página oficial de versiones es la alternativa.

### Publicar los plugins oficiales

Los plugins oficiales se publican desde el repositorio principal [drdon1234/Hentai-Park](https://github.com/drdon1234/Hentai-Park); la app lee:

```text
https://raw.githubusercontent.com/drdon1234/Hentai-Park/sources/index.json
https://raw.githubusercontent.com/drdon1234/Hentai-Park/rankings/index.json
```

- `assets/sources/index.json` es la única lista mantenida; `file` apunta a un script de la misma carpeta llamado `{key}.js` (`[A-Za-z0-9_-]+.js`; sin subcarpetas, enlaces simbólicos ni puntos en el nombre base).
- `tools/publish_sources.mjs` genera el índice publicado con `key`, `name`, `version`, `category`, `description`, `url`, `sha256` y `apiVersion`; las URL de los scripts se fijan al commit completo del código: `https://raw.githubusercontent.com/drdon1234/Hentai-Park/<SHA del commit>/assets/sources/<file>`. La rama `sources` solo contiene el `index.json` generado.
- El publicador solo necesita los módulos integrados de Node.js 22+ y funciona sin conexión: comprueba la lista, los archivos y los límites de carpeta, carga el entorno y los scripts sin red ni almacenamiento y verifica `key`, `version` y API con la misma sonda `Park.__pending` / `Park.manifest` que la vista previa de instalación. No llama a `init`, al inicio de sesión ni a métodos del sitio, así que no sustituye a las solicitudes reales.

```powershell
node tools/publish_sources.mjs --commit '<SHA completo de 40 caracteres>' --output 'test/official-source-index.json'
```

El código permanece en la rama principal. `sources` distribuye complementos normales y `rankings` los dedicados a clasificaciones. Ambas ramas contienen solo un índice generado con URL de un commit fijo y SHA-256. El flujo valida y publica cada canal por separado; la aplicación lee ambos de forma independiente, rechaza canales incorrectos y claves duplicadas y conserva la confirmación de actualización.

### Plugins generados

La única implementación del plugin de Telegram es `assets/sources/telegram_entry.mjs`; `assets/sources/telegram.js` se genera y no debe editarse a mano:

```powershell
npm ci --prefix 'tools/source-runner'
node tools/build_subscription_sources.mjs
```

Usa [@mtproto/core 6.3.0](https://github.com/alik0211/mtproto-core) (GPL-3.0, [licencia](../../licenses/mtproto-core.txt); resumen de dependencias en [licencias de terceros](../../licenses/telegram-dependencies.txt)). El adaptador del sitio sustituye transporte, criptografía y almacenamiento, y no activa el WebSocket predeterminado de la biblioteca, el localStorage del navegador ni los registros de depuración.

## Apéndice: notas sobre los sitios oficiales

Convenciones necesarias para mantener los plugins oficiales. Los sitios cambian; el código del plugin es la referencia.

**Juegos**

- Orden por defecto: GalgameX → KUN Galgame → Salón de té dimensional. GalgameX y KUN activan NSFW por defecto (la API de invitado `content-filter` y el parámetro `include_nsfw`, respectivamente).
- GalgameX abre por defecto los populares de la semana. La lista de recursos actualizados usa una Next Server Action descubierta en el front-end actual; su ID se guarda 15 minutos y se vuelve a descubrir cuando deja de funcionar, sin ejecutar scripts remotos. Los detalles se analizan desde los datos SSR Flight. Los recursos públicos usan host más hash de ruta como ID de canal estable; los resultados resueltos se emparejan por host y nombre de archivo / ID de compartición, rechazando discrepancias y duplicados, sin depender del orden de los enlaces temporales.
- KUN abre por defecto la clasificación de vistas de 7 días con su API nativa pública; la API de descarga solo se llama al tocar, para que la precarga no infle el contador de descargas del sitio. Las páginas de recursos se recorren según el total de la API; las páginas repetidas o vacías antes de tiempo son errores.
- El Salón de té dimensional usa modo navegador con su propio inicio de sesión y abre por defecto los populares del tablón de recursos Galgame; las portadas salen de los adjuntos del primer mensaje con 400 ms entre solicitudes. La lista de recursos es de solo lectura; la respuesta «感谢分享，好人一生平安» se envía con el formulario completo solo tras confirmar el usuario. No se responde en hilos ya desbloqueados; si el resultado no está claro, se conserva el estado y se dirige al usuario al hilo, y nada se reenvía tras reiniciar.

**Novelas**

| Sitio | Pestaña por defecto | Alcance y límites |
| --- | --- | --- |
| Book18 | Recomendados | Relatos largos y cortos en chino; capítulos en el orden del sitio |
| Cool18 | Destacados | Solo el tablón de libros prohibidos; cada mensaje principal es una obra, sin unir respuestas ni mensajes con el mismo título; parte del contenido requiere permisos de cuenta |
| Canovel | Recientes | Admite paginación dentro del artículo |
| Literotica | Clasificación | Inglés; la búsqueda excluye no inglés, audio, guías, reseñas y ensayos |
| Lush Stories | Recomendados | Inglés; excluye audio y poesía |
| StoriesOnline | Selección de autores | Inglés; el texto anónimo recortado pide iniciar sesión y nunca se guarda como capítulo completo |
| 69story | Recientes | Chino; categorías, búsqueda, índice y lectura por capítulos |

**Suscripciones**

| Plataforma | Contenido | Inicio de sesión |
| --- | --- | --- |
| X / Twitter | Medios públicos anónimos; publicaciones y medios autorizados con sesión | Inicio de sesión web, o `auth_token` y `ct0` |
| Telegram | Vistas previas de canales públicos; historial y adjuntos con sesión | Importar una sesión existente del almacenamiento local de Telegram WebK |
| myfans.jp | Listas de creadores, imágenes y vídeos públicos y vistas previas de prueba | Inicio de sesión de miembro no verificado |
| pixivFANBOX | Listas públicas y vistas previas de portadas | Inicio de sesión de miembro no verificado |

- El `ct0` de X debe coincidir con `X-CSRF-Token`; las sesiones pueden caducar o revocarse. Tras iniciar sesión, el plugin carga los ID de operación y las feature flags de la web actual, lee UserTweets y conserva solo los medios del autor elegido (sin retuits ni citas). Los proxies anónimos de terceros nunca reciben cookies de X.
- El almacenamiento local de Telegram no es una cookie: la importación necesita `dc` y el `dcN_auth_key` correspondiente (512 dígitos hexadecimales), en JSON o como texto `key=value`. El plugin solo restaura una sesión WebK existente —sin inicio de sesión por código ni registro de cliente propio— y cerrar sesión solo borra la sesión guardada por esta app. Los adjuntos se leen en fragmentos de 128 KiB, hasta 512 MiB cada uno; las referencias de medios caducadas se refrescan una vez. La red pasa por el puente HTTP nativo aislado; no se habilitan fetch ni WebSocket del WebView.
- OnlyFans, Fantia, Patreon y Fansly no tienen una ruta de medios completa y no están en la lista oficial. Que la página principal abra no significa que se puedan suscribir sus medios, y nunca se elude el acceso de pago.

Para CDN HLS dinámicas, declare `media.scope: 'session'` en modo native. Se autorizan la URL resuelta, los recursos de la lista y hasta 8 redirecciones solo durante la reproducción o descarga, sin ampliar permisos de Cookie. Se exige HTTPS 443 y solicitudes sin credenciales. La conexión directa valida DNS público y fija una IP comprobada conservando TLS. Un proxy HTTP explícito y de confianza resuelve los destinos y controla el acceso a redes públicas. Al cerrar se revocan los permisos. MP4 directo y browser mantienen la lista estática de dominios.

### `webVideo(id, episodeId)`

iXXX y TubeSafari usan reproducción web en la app. La página puede requerir confirmación del sitio; los controles los proporciona la página de origen. No se admiten las descargas de la app ni reanudar en un punto exacto. Android requiere una versión reciente de Android System WebView con sesiones aisladas.

```js
return { url: "https://player.example.com/watch/1", navigationDomains: ["player.example.com"], frameDomains: [] };
// Native HTTP only: this.http.get(url, { followRedirects: false })
```

## Clasificaciones y distribución independiente

`rankings` declara listas mediante `key`, `label`, `category`, `metric` y `options`. Un complemento dedicado usa `rankingOnly: true` y no declara `feeds`. `ranking(board, {page, offset, cursor, options})` devuelve una página de obras con `id`, `rank` original, `title`, `cover` y campos opcionales `keyword`, `subtitle` y `url` HTTPS del producto. Se conservan los empates. Una fuente existente puede declarar `feed`: hereda sus opciones si se omiten y reutiliza `feed()`, conserva los campos y añade `workId` y el puesto si falta, para abrir los detalles. Las entradas comerciales buscan en la categoría declarada.

El código permanece en la rama principal. `sources` distribuye complementos normales y `rankings` los dedicados a clasificaciones. Ambas ramas contienen solo un índice generado con URL de un commit fijo y SHA-256. El flujo valida y publica cada canal por separado; la aplicación lee ambos de forma independiente, rechaza canales incorrectos y claves duplicadas y conserva la confirmación de actualización.

```powershell
node tools/publish_sources.mjs --commit '<SHA>' --channel rankings --output 'test/official-ranking-index.json'
```
