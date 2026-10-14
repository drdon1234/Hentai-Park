[简体中文](../../SOURCE_API.md) · [繁體中文](../zh-Hant/SOURCE_API.md) · [日本語](../ja/SOURCE_API.md) · [한국어](../ko/SOURCE_API.md) · [English](../en/SOURCE_API.md) · [Español](SOURCE_API.md) · [Русский](../ru/SOURCE_API.md) · [العربية](../ar/SOURCE_API.md)

# Guía de desarrollo del complemento fuente

Cada origen de HentaiPark es un archivo JavaScript independiente. Las aplicaciones las cargan en tiempo de ejecución: se pueden instalar, actualizar, habilitar/desactivar desde el repositorio de origen sin volver a compilar la aplicación.
La fuente incorporada se encuentra en [`assets/sources/`](../../../assets/sources/) y se puede utilizar directamente como referencia de ejemplo.

## Entorno de ejecución

- Los scripts fuente se ejecutan en un WebView sin interfaz dentro de la aplicación (JS moderno completo con `DOMParser`). La capa nativa proporciona criptografía, Cookie y solicitudes HTTP nativas. HTTP nativo no tiene restricciones CORS; las solicitudes de red y medios del navegador siguen las reglas independientes descritas abajo.
- El mismo tiempo de ejecución ([`assets/runtime/park_runtime.js`](../../../assets/runtime/park_runtime.js)) también se puede ejecutar en Node, y puedes realizar pruebas de humo directamente en el sitio real durante el desarrollo:

Instalar dependencias del runner desde la raíz y crear `test/source-smoke.mjs` ignorado con este ejemplo. Solo carga el manifest; añadir comprobaciones reales de inicio, página2, búsqueda, detalle, decodificación de portada, capítulos y medios de la fuente modificada. El anfitrión Node es una ayuda de desarrollo, no una barrera de seguridad para scripts no fiables.

```js
import { loadSource } from '../tools/source-runner/host.mjs';
const { manifest } = await loadSource('nhentai.js');
console.log(manifest.key, manifest.version);
```

```powershell
npm ci --prefix 'tools/source-runner'
node 'test/source-smoke.mjs'
```

## Registrar una fuente

```js
Park.register({
  key: 'mysite',              // Identificador único, no se puede cambiar después de la instalación
  name: 'Example Source',
  version: '0.0.1',           // Cuando el número de versión en el almacén sea mayor, la aplicación solicitará una actualización.
  type: 'comic',              // comic | video | novel | game
  category: 'doujin',         // doujin | anime | aiDrama | jav | adult | shortvideo | gallery | novel | game | other
  color: '#E5355F',           // Color de marca: utilizado para tarjetas de entrada de origen y colores de tema de página de origen
  description: 'Example source description',
  homepage: 'https://example.com',
  domains: ['example.com'],                   // Para conocer el sitio al que pertenece, consulte "Aislamiento y seguridad"; si se omite, se deducirá de la dirección, como la página de inicio.
  linkPatterns: ['example\\.com/g/(\\d+)'],   // Se utiliza para acceso directo al pegar enlaces en búsquedas agregadas; el primer grupo es el ID del trabajo
  idPattern: '^(\\d+)$',                      // Se utiliza para acceso directo al ingresar el número directamente
  imageHeaders: { Referer: 'https://example.com/' },  // Se lleva por defecto al cargar portadas e imágenes.
  network: { mode: 'native', vpnHint: true },                // Ver la sección "Red"
  media: { mode: 'browser', origin: 'https://example.com', domains: ['media.example.com'] },  // Permiso HLS opcional; ver abajo

  settings: [ /* option definitions */ ],
  account: { /* optional account */ },
  defaultFeed: 'ranking',                     // La etiqueta ingresada por defecto al abrir la página de origen (ingrese los feeds)
  feeds: [ /* browse tabs */ ],
  searchFilters: [ /* search filters */ ],
  searchHint: 'Search by title or tag',

  async init() {},                            // Opcional: se llama una vez durante la carga (por ejemplo, al actualizar la lista de nombres de dominio)
  async onSettingsChanged() {},               // Opcional: se llama después de que el usuario modifica la configuración de origen.

  async feed(key, { page, cursor, options }) {},
  async search({ keyword, page, cursor, filters }) {},
  async random() {},                          // Devuelve el ID del trabajo
  async detail(id, preview) {},
  async chapter(id, chapterId) {},            // historietas
  async resolveImage({ id, chapterId, index, token, retry }) {},  // Opcional: análisis retrasado de imágenes
  async thumbnails(id, page) {},              // Opcional: cargar miniaturas de vista previa en páginas
  async videos(id, episodeId = '_') {},                        // video
});
```

`type` decide entre lectura y reproducción; `category` agrupa las fuentes en inicio, gestión y búsqueda. Las categorías desconocidas o ausentes van a Otros. El inicio debe priorizar recomendaciones, clasificación y populares, en ese orden; usar novedades solo si ninguno existe.

Los dramas cortos de IA usan `category: 'aiDrama'`; no se acepta el identificador anterior `drama`. Los nombres de los canales del sitio son independientes de la categoría de la aplicación y conservan sus nombres originales. La categoría no filtra automáticamente los canales del sitio.

`adult` agrupa sitios generales como Pornhub, XVideos y 91porn con `type: 'video'`. Los sitios especializados en JAV usan `jav`. Las categorías no sustituyen las etiquetas del sitio ni los filtros del usuario.

Las fuentes agregadas declaran `type: 'video', category: 'adult'`. Si no hay API multimedia verificada, omiten `videos` y exportan `capabilities.videos: false`. La acción principal abre `detail.url` en el navegador del sistema, oculta reproducción/descarga/episodios y evita sincronizar capítulos ficticios o buscar sus actualizaciones; conserva favoritos e historial. El parámetro opcional de `detail(id, preview)` contiene metadatos públicos sólo si coinciden fuente e ID; la fuente vuelve a validar ID y URL. iXXX usa la URL externa sin parámetros de seguimiento conocidos como ID estable; TubeSafari conserva la clave externa. No solicitan obras externas con cookies de la fuente. Las referencias directas sin vista previa se pueden abrir, aunque falten título o portada. Thumbzilla analiza estáticamente metadatos MP4 y restringe los dominios multimedia.

`gallery` agrupa ilustraciones, cosplay y conjuntos de fotos. Las fuentes de imágenes mantienen `type: 'comic'`: cada galería es una obra y `chapter()` devuelve las imágenes en orden, reutilizando lectura, biblioteca y descargas. La categoría no depende del número de imágenes ni de su contenido explícito.

Declare las imágenes cifradas con `imageDecrypt`. Se descifran antes de validar el formato y guardar en caché; la estrategia forma parte de la identidad de caché y los fallos no se guardan. Se admite AES-CBC con relleno PKCS#7 estricto. `key` e `iv` se codifican en UTF-8; limite los dominios de imágenes. Las imágenes de otros dominios no se modifican.

```js
imageDecrypt: {
  type: 'aes-cbc',
  key: '0123456789abcdef', // UTF-8: 16, 24 or 32 bytes
  iv: '0123456789abcdef',  // UTF-8: 16 bytes
  domains: ['images.example.com'],
},
```

Los errores de red incluyen los campos seguros de `diagnostics`: `host`, `transport` y `reason`, para distinguir certificados, negociación TLS, DNS, conexión y tiempos de espera. Los registros automáticos solo incluyen campos permitidos, nunca mensajes originales, credenciales, cuerpos de petición ni URL firmadas.

`reason: 'TLS_HANDSHAKE_TERMINATED'` solo indica que el `HandshakeException.message` nativo coincide exactamente con `Connection terminated during handshake`: la conexión terminó antes de completar TLS, no un fallo de certificado. Solo HTTPS GET / HEAD sin cuerpo reintenta una vez ante ese error exacto. Cancelaciones, certificados, otros errores TLS, HTTP y lectura de respuesta no se reintentan. Si vuelve a fallar, se muestra el host y se recomienda revisar VPN o proxy; solo se registran diagnósticos seguros.

En el método, puedes utilizar `this` para acceder:

| Miembros | Descripción |
|------|------|
| `this.http` | `request(opts)`, `get(url, opts)`, `post(url, opts)`, `text(url, opts)`, `json(url, opts)` |
| `this.config` | El valor seleccionado por el usuario en la configuración de origen (`default` si no está configurado) |
| `this.store` | Almacenamiento persistente de valores-clave: `get(key, fallback)` / `set(key, value)`, utilizado para guardar tokens, listas de nombres de dominio, etc.; `await flush()` confirma que la escritura en el disco fue exitosa y arroja un error si falla |
| `this.cookies` | `get(url)` / `set(url, {name: value})` / `clear(url)` |
| `this.log({code, host, transport, reason})` | Solo se conservan campos estructurados permitidos; se descarta texto libre. |

Herramientas globales:

| Herramientas | Instrucciones |
|------|------|
| `Park.html.parse(text)` | Estándar de devolución `Document`, puede usar `querySelector` |
| `Park.html.text(node)` / `unescape(s)` / `strip(html)` | Procesamiento de textos |
| `Park.crypto.md5Hex(text \| text[])` | MD5, puede pasar matrices para cálculo por lotes |
| `Park.crypto.sha256Hex` / `hmacSha256Hex(key, text)` / `aesEcbDecrypt(base64, key)` / `uuid()` | Implementación nativa, rápida |
| `Park.utils.rateLimiter(ms)` | Devuelve `wait()`, asegurando el intervalo mínimo entre dos solicitudes |
| `Park.utils.mapLimit(items, n, fn)` / `lruMap(n)` / `parseCount('1.2万')` / `formatDate(ts)` | Otras herramientas de uso común |
| `Park.error(code, message)` | Genera un error con un código de error, ver más abajo |

### `http.request(opts)`

```js
await this.http.request({
  url, method: 'GET', headers: {}, params: { q: 'x' },   // los parámetros se concatenarán en la URL
  json: {...} | form: {...} | body: 'raw',
  timeout: 15000,
  responseType: 'text' | 'base64',
});
// → { status, headers, body, url, ok, json() }
```

`text()` / `json()` lanzan un error automáticamente ante respuestas que no sean 2xx (404 → `NOT_FOUND`). Las cookies se guardan automáticamente y se seleccionan de nuevo para cada destino de redirección. Las redirecciones entre orígenes no envían las cabeceras de autenticación originales; se rechazan si mantienen el cuerpo de la solicitud.

## Estructura de datos

**Página de lista** (valor de retorno de `feed` / `search`)

```js
{
  items: [WorkItem], page: 1, totalPages: 20, total: 500,
  hasNext: true,
  cursor: '12345',        // Opcional: los sitios donde el cursor pasa de página (como E-Hentai) devuelven el cursor de la página siguiente y la aplicación lo devolverá tal como está la próxima vez que realice una solicitud.
}
// Si se devuelven sections, la aplicación muestra el diseño por secciones:
{ sections: [{ title: 'Latest chapters', items: [WorkItem] }], hasNext: false }
```

**Artículo de trabajo**: `{ id, title, subtitle?, cover, coverAspect?, pages?, rating?, likes?, views?, language?, category?, badge?, badgeColor?, duration?, uploaded?, tags? }`

- `coverAspect` (ancho/alto) realiza el diseño de la cuadrícula antes de cargar la imagen para evitar saltos.
- `badgeColor` El color utilizado para las etiquetas de categorías (por ejemplo, E-Hentai el esquema de color tradicional para cada categoría).

**Detalles** (`detail`): Todos los campos del WorkItem, incluyendo además:

```js
{
  url, authors: [], description, uploader?, size?, comments?,
  tags: [{ namespace: 'artist', label: 'Author', tags: [{ name, keyword, filters?, count? }] }],
  chapters: [{ id, title }] | null,   // null representa un solo capítulo
  singleChapterId?,                   // El ID de capítulo requerido para un trabajo de un solo capítulo (como "1" para Bika)
  thumbnails?: [url | {url, width, height, offsetX, offsetY}],   // Imagen de sprite de soporte
  related?: [WorkItem], series?: [WorkItem],
}
```

Cuando se hace clic en una etiqueta, la aplicación busca `keyword` y `filters` en la fuente, por lo que la etiqueta se puede asignar a la sintaxis nativa del sitio (por ejemplo, `artist:"xxx"`) o a los parámetros de filtro (por ejemplo, Hanime1 de `tags[]`).

**Capítulo** (`chapter`)

```js
{ pages: [
  { url, headers?, fallbacks?: [url], width?, height?, transform? },  // Se conoce la dirección
  { token: '12' },                                                      // Resolución retrasada: la aplicación llamará a resolveImage
]}
```

- `fallbacks`: espejo de respaldo, intente en secuencia cuando falle la dirección principal.
- `transform: { type: 'unscramble-strips', segments: N }`: cuando la imagen se corta en N tiras horizontalmente y se almacena en orden inverso (JMComic), la aplicación se restaurará de forma nativa en la GPU. El archivo descargado sin conexión guarda la imagen original y la restaura cuando se muestra.
- `resolveImage` devuelve `{ url, headers?, width?, height?, cacheKey? }`. Cuando falla, la aplicación incrementará `retry` y volverá a llamar, y la fuente puede usar esto para cambiar un servidor (parámetro `nl` de E-Hentai).

**Video** (`videos`): `[{ quality: 1080, label: '1080P', url, headers?, format?, preferred? }]`. Los enlaces directos de video generalmente tienen un límite de tiempo y la aplicación los volverá a obtener cada vez antes de reproducirlos o descargarlos.

- Las fuentes de vídeo devuelven `[{id, title}]` en orden de reproducción mediante `detail(id).chapters`. Cada `id` debe ser estable; no uses una etiqueta de calidad ni una URL temporal. La aplicación usa el mismo ID para seleccionar, guardar el progreso independiente, descargar y reanudar, y llama a `videos(id, episodeId = '_')` para obtener ese episodio. Un vídeo único usa `singleChapterId`, o `'_'` si se omite.
- Si se omite `format`, se conserva la ruta de reproducción y descarga directa de MP4. Las entradas HLS deben devolver explícitamente `format: 'hls'` y declarar en el manifest el permiso `media` descrito a continuación.
- La aplicación primero expande la lista maestra HLS (`#EXT-X-STREAM-INF`) en listas de segmentos independientes por variante, obtiene las resoluciones reales de `RESOLUTION` y entrega esas variantes al reproductor o al gestor de descargas. En una lista maestra, `quality` indica la resolución deseada: se prefiere la mayor resolución disponible que no supere ese valor, o la máxima si ninguna cumple. Cada variante debe contener audio y video multiplexados en MPEG-TS. Se rechazan las rendiciones separadas `AUDIO`, `VIDEO` o `SUBTITLES` y las URL fuera de `media.domains`. Las pistas opcionales de vista previa `#EXT-X-I-FRAME-STREAM-INF` se ignoran; sus direcciones no se registran ni solicitan. Si se desconoce la resolución de una lista multimedia única, proporcione `label: '原画'`; la etiqueta se traduce al idioma de la interfaz y la calidad solicitada no se muestra como resolución real.
- Las variantes HLS solo admiten listas MPEG-TS VOD completas y continuas con `#EXT-X-ENDLIST`. Se admite descifrado CBC/PKCS7 de `METHOD=AES-128` con `KEYFORMAT=identity` (también el valor predeterminado), claves de exactamente 16 bytes e IV explícito de 128 bits o derivado de la secuencia del segmento. Las claves permanecen en la memoria de la sesión; el TS descifrado se valida en el mismo proceso de reproducción y descarga. No se admiten directo, SAMPLE-AES, otros KEYFORMAT, `EXT-X-MAP`, `EXT-X-BYTERANGE`, fMP4, discontinuidades ni huecos. Se elimina el `#EXT-X-TOKEN` no estándar de MissAV.
- La reproducción usa un puerto aleatorio vinculado solo a `127.0.0.1` y un token aleatorio, con un registro finito de URL que obtiene segmentos validados bajo demanda. Al cerrar la sesión, se cancelan sus solicitudes. Las descargas HLS sin conexión solo se admiten en Android: se valida cada segmento, se guarda su SHA-256 y se comprueba al reanudar, con posibilidad de cancelar. Media3 convierte el contenido a MP4 en el dispositivo y solo el archivo completo se publica en la biblioteca sin conexión. La reproducción HLS en iOS/macOS no se ha verificado en esta ronda y no debe presentarse como verificada.

## Definición de opción

`feeds[].options`, `searchFilters`, `settings` utilizan el mismo formato:

```js
{ key: 'sort', label: 'Sort', type: 'select', default: 'date',
  values: [{ value: 'date', label: 'Latest' }, { value: 'popular', label: 'Popular', color: '#f00' }] }
// type: select (selección única) | multi (selección múltiple) | number | text | password | switch
// En settings también se puede usar options en lugar de values.
```

Cada elemento de `feeds` es una pestaña en la página de origen: `{ key, label, options?: [...] }`.

`defaultFeed` Especifica qué pestaña ingresar de forma predeterminada al abrir la página de origen. Cuando la clave correspondiente no está completa o no se puede encontrar, la aplicación seleccionará automáticamente de acuerdo con la clave en el orden de Recomendación > Clasificación > Popular (la clave incluye `promote` / `recommend` / `featured`, y luego `rank` / `toplist`, luego `popular` / `hot` / `trending`), si no, ingresa el primero etiqueta.

## red

- `network.mode: 'native'` (predeterminado): la solicitud HTTP nativa, que utiliza cookies persistentes, puede pasar por el proxy configurado por el usuario. Si se detecta la consulta Cloudflare, se generará `CLOUDFLARE`. La aplicación guiará al usuario para completar la verificación en el navegador integrado y sincronizar la cookie común con la solicitud nativa.
- `network.mode: 'browser'` + `network.origin`: La solicitud se realizó con origen `fetch()` en una página oculta del navegador abierta en `origin`, con una huella digital real del navegador. Se aplica a Cloudflare sitios que están más protegidos (por ejemplo, Hanime1). Si una solicitud GET del mismo origen recibe un desafío Cloudflare, el navegador oculto abre ese documento para completar la verificación automática y reintenta la solicitud original una sola vez. Si falla, se genera `CLOUDFLARE` y se utiliza el flujo de verificación existente.

## Permisos de medios (HLS)

El permiso `media` es independiente de `this.http`, `network` y la sincronización de Cookie del sitio. Ambos transportes aplican las mismas reglas de dominio:

```js
domains: ['example.com'],
network: { mode: 'native' },
media: { mode: 'native', origin: 'https://example.com', domains: ['media.example.com'] },
```

- `media.mode` admite `'native'` y `'browser'`. Ambos requieren que `media.origin` pertenezca a un sitio declarado por la fuente y use HTTPS en el puerto 443, sin credenciales, consulta ni fragmento en la URL.
- `media.domains` es una lista independiente de dominios permitidos, incluidos los subdominios; no concede acceso a las Cookie del sitio. Listas, segmentos y claves requieren HTTPS 443. Se rechazan credenciales, fragmentos, direcciones IP, localhost (incluidos sus subdominios) y `.local`.
- `media.mode: 'native'` usa un cliente nativo independiente sin credenciales, Cookie del sitio, Authorization ni autenticación de proxy. Se valida cada destino de redirección antes de seguirlo. Solo se permiten las cabeceras `Referer`, `Origin`, `Accept` y `Accept-Language`; las dos primeras deben coincidir con `media.origin`.
- `media.mode: 'browser'` crea una sesión en un navegador oculto en `media.origin` con `credentials: 'omit'`, `mode: 'cors'` y `redirect: 'error'`. Respeta el CORS del CDN y no sigue redirecciones.
- Se limita el tamaño al recibir la respuesta y se vuelve a validar su URL. Las listas tienen un máximo de 2 MiB, los segmentos de 32 MiB y las claves AES-128 deben tener 16 bytes exactos. Se rechazan respuestas vacías, demasiado grandes o URL no permitidas. Las reglas de `domains` y de `network` con Cookie siguen siendo independientes.

## Aislamiento y seguridad

- Cada fuente se ejecuta en un entorno JS **independiente** (cada una tiene un WebView sin interfaz) y las fuentes no pueden ver los objetos globales de cada una; el puente nativo solo reconoce de qué entorno proviene la llamada y los scripts no pueden hacerse pasar por otras fuentes.
- Cada fuente tiene un contenedor de cookies independiente: la solicitud emitida por la fuente solo traerá y guardará su propia cookie, y no leerá el estado de inicio de sesión de otras fuentes.
- Las Cookie Secure nunca se envían por HTTP. El acceso a la página de verificación y la importación de Cookie del navegador se validan con `domains` de la fuente instalada; se conservan los atributos de seguridad y la caducidad disponibles. Borrar las Cookie de una fuente o desinstalarla también cierra sus sesiones de navegador y borra las Cookie del sitio. El sistema comparte las Cookie de sitios del navegador, por lo que otras fuentes que declaren el mismo sitio también se ven afectadas.
- `domains` declara el sitio al que pertenece la fuente (el nombre de dominio se puede registrar, el nombre del subdominio se incluye automáticamente). Solo las cookies de estos sitios se sincronizarán con el navegador integrado (compartidas mediante autenticación Cloudflare, inicio de sesión web), y `network.origin` en modo navegador también deben pertenecer a ellas. Cuando se omite, infiere de `homepage`, `network.origin`, `account.cookieUrl/loginUrl`.
- Al instalar la fuente desde un sitio web o almacén, la aplicación primero leerá la información del script en un entorno limitado que no se puede conectar a Internet, mostrará el nombre, la versión, SHA-256, el sitio declarado y la advertencia de riesgo para el usuario, y luego la instalará después de la confirmación. La entrada `index.json` en el almacén de origen puede tener el campo `sha256` y la instalación se rechazará si el contenido de la descarga no coincide.

## Cuenta

```js
account: {
  type: 'password' | 'cookies',
  title, hint, required: false,
  fields: [{ key: 'email', label: 'Email' }, { key: 'password', label: 'Password', secret: true }],
  loginUrl?, cookieUrl?, requiredCookies?: ['ipb_member_id'],   // Tras facilitarla podrás iniciar sesión en la página web y la App obtendrá automáticamente la cookie.
  async login(values) { return { name } },
  async logout() {},
  async status() { return { loggedIn, name, configured } },
  managedAccount: true,                 // Opcional: proporcione una cuenta de mantenimiento automático dedicada
  async enableManaged() {},             // Solo se llama después de que el usuario confirma el registro.
}
```

`configured` indica que la cuenta se ha configurado, independientemente de si el inicio de sesión actual se realizó correctamente. `managedAccount: true` declara que la fuente admite una cuenta de mantenimiento automático dedicada; La configuración de fuente utiliza el interruptor `managedAccount` con el mismo nombre. El anfitrión primero debe mostrar las instrucciones de registro automático y obtener la confirmación del usuario antes de guardar la configuración de habilitación y llamar al `account.enableManaged()`. Las credenciales del candidato deben guardarse y usarse `await this.store.flush()` antes del registro para garantizar que se pueda restaurar la misma cuenta después de una falla o reinicio de la aplicación.

El ejemplo PicACG guarda las credenciales manuales y las cuentas dedicadas por separado, y las cuentas manuales existentes no deben sobrescribirse con cuentas dedicadas. Apague el interruptor para conservar la cuenta dedicada y vuelva a encenderlo para reutilizarla; si el Token caduca, solo podrá iniciar sesión nuevamente y no registrarse nuevamente. Después de que el registro falle o se pierda la respuesta, vuelva a intentar la cuenta del candidato original para evitar la creación de cuentas redundantes. La contraseña de la cuenta, el token y el estado de la fuente son datos locales del usuario. No muestre credenciales reales en documentos y registros.

## Internacionalización

Soporte de interfaz de aplicación `zh-Hans`, `zh-Hant`, `ja`, `ko`, `en`, `es`, `ru`, `ar`. Los controles de material, Cupertino y del sistema utilizan los idiomas correspondientes; la interfaz árabe va de derecha a izquierda. La configuración del idioma de la interfaz entra en vigor inmediatamente y se guarda de forma persistente. Sigue el sistema por defecto; Las escrituras y regiones chinas determinan si se utiliza chino simplificado o tradicional.

La interfaz Flutter llama uniformemente a `tr('已选 {count}', {'count': count})`, o `context.tr`. El texto chino original del mensaje se utiliza como clave de recurso, el parámetro es `{name}` y el recurso de ocho idiomas se encuentra en `assets/i18n/`. Al agregar o modificar una copia visible, todos los recursos deben actualizarse simultáneamente y los marcadores de posición deben ser consistentes. El nombre estático, la descripción, la etiqueta de navegación, las opciones y los mensajes de error del complemento se asignan a los recursos cuando se muestra la aplicación; el título, autor, etiqueta, entrada del usuario y clave del protocolo de persistencia del trabajo remoto siguen siendo el texto original.

## Código de error

Utilice `throw Park.error(code, message)` para generar un error y la aplicación proporcionará la guía correspondiente según el código de error:

| código | Procesamiento de aplicaciones |
|------|-----------|
| `CLOUDFLARE` | Botón "Ir a verificación": abre el navegador integrado |
| `LOGIN_REQUIRED` | Botón "Ir a iniciar sesión": abre el área de cuenta de la configuración de origen |
| `NOT_FOUND` | Mostrar "El contenido no existe" |
| `BLOCKED` | Muestra "Acceso restringido" (como IP bloqueada, cuota agotada), no se volverá a intentar la imagen |
| `NETWORK` / `HTTP` / `PARSE` | Mostrar mensaje de error con el botón "Reintentar" |

## Almacén de origen

Un repositorio es un `index.json` que se puede colocar en un alojamiento estático (por ejemplo, GitHub sin formato). Los usuarios pueden explorar, instalar y actualizar ingresando la dirección del almacén en "Administración del sitio de origen → Agregar origen":

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

`url` es la dirección completa del script; también puede utilizar `file` en relación con `index.json`. El almacén de terceros se instala manualmente después de la confirmación del usuario. `sha256` es opcional. El contenido descargado se verificará cuando se proporcione.

Las actualizaciones oficiales adoptan reglas estrictas: la versión debe ser un entero no negativo de tres segmentos separados por puntos y sin ceros a la izquierda (por ejemplo, `0.0.1`, `0.1.0`), que se compara segmento por segmento por número; No se aceptan segmentos faltantes, segmentos múltiples o sufijos previos al lanzamiento. El texto UTF-8 original del script `sha256` debe proporcionarse sin recortar espacios en blanco ni convertir nuevas líneas; los `key` y `version` declarados por el script deben ser coherentes con el índice. `apiVersion` debe coincidir completamente con el tiempo de ejecución actual de la aplicación. Si no coincide, se rechazará la actualización. Primero debe utilizar una aplicación que admita esta API; no se proporciona ninguna rama compatible.

### Actualizaciones oficiales en la aplicación

Al iniciar solo se consulta el índice oficial. Si hay una versión nueva, se solicita confirmación antes de descargar e instalar. Al volver al primer plano se mantiene un intervalo de 12 horas, incluso para intentos fallidos. Ambas comprobaciones automáticas están activadas por defecto y se pueden desactivar por separado; la comprobación manual sigue disponible. Solo se comprueban fuentes integradas y oficiales instaladas, sin modificar fuentes de terceros.

Tras confirmar, se validan de nuevo la identidad, versión, origen, API y SHA-256, y se espera a que la inicialización y el guardado del estado terminen. Si falla, se recuperan el script anterior y los datos privados; una instalación interrumpida se recupera en el siguiente inicio. El inicio no sustituye complementos instalados por scripts incluidos, ni siquiera cuando falta el script. Se conservan el registro y los datos; solo los complementos nuevos reciben el script incluido inicial. Restaurar una fuente integrada también requiere confirmación. En Android, tras confirmar se descarga el APK oficial compatible dentro de la aplicación. Se verifican tamaño, SHA-256, paquete, versión y firmas antes de abrir el instalador del sistema, que requiere confirmación. Si falta permiso, concédelo, vuelve y pulsa Continuar instalación. Hay progreso, cancelación y reintento; la página oficial sirve como alternativa si falla. Otras plataformas usan la descarga manual desde la página oficial.

### Publicación de fuentes oficiales

La fuente oficial sigue al almacén principal público [drdon1234/Hentai-Park](https://github.com/drdon1234/Hentai-Park), y la entrada fija al cliente es:

```text
https://raw.githubusercontent.com/drdon1234/Hentai-Park/sources/index.json
```

El `key` de la fuente solo admite `[A-Za-z0-9_-]`, mide entre 1–100 caracteres y no puede usar el valor reservado `_app`; el archivo debe llamarse `{key}.js`.

`assets/sources/index.json` es la única lista de fuentes mantenida y `file` apunta al único código fuente del script en el mismo directorio. El nombre del archivo debe cumplir con `[A-Za-z0-9_-]+.js`. No se aceptan subdirectorios, enlaces simbólicos o puntos en el cuerpo del nombre del archivo y deben ser coherentes con la verificación de la dirección de origen oficial del cliente. `tools/publish_sources.mjs` Generar índice de publicación: cada registro contiene `key`, `name`, `version`, `category`, `description`, `url`, `sha256` y `apiVersion`. La URL del script se fija en el número de confirmación completo de 40 dígitos de este código fuente:

```text
https://raw.githubusercontent.com/drdon1234/Hentai-Park/<源码提交 SHA>/assets/sources/<file>
```

La rama `sources` solo guarda el directorio raíz generado `index.json`, sin copiar el script ni mantener manualmente una segunda lista de fuentes. Al actualizar un script, la versión del script y el manifiesto deben actualizarse al mismo tiempo; el editor se niega a degradar la versión y también rechaza que la misma versión corresponda a un contenido de guión diferente. La misma versión se puede publicar repetidamente sin cambios y las actualizaciones normales no se verán afectadas por la versión anterior del índice.

El editor depende únicamente del módulo integrado Node.js y puede ejecutarse sin conexión en Node.js 22 o posterior. Comprueba los manifiestos, la existencia de archivos y los límites de los directorios, carga el tiempo de ejecución compartido y los scripts en un contexto separado que no proporciona interfaces de red o almacenamiento, y realiza las comprobaciones utilizando las mismas sondas `Park.__pending`/`Park.manifest` que la vista previa de instalación de la aplicación `key`. `version` y API. La detección no llama a `setup`, `init`, a los métodos de inicio de sesión o de negocio del sitio, y no puede reemplazar la prueba de usabilidad de la red del sitio de origen.

Ejemplo de vista previa local (el resultado está en `test/`, que se ha ignorado y no se publicará; el número de confirmación debe usar el SHA real del código fuente correspondiente):

```powershell
node tools/publish_sources.mjs --commit '<完整 40 位源码提交 SHA>' --output 'test/official-source-index.json'
```

Cuando necesite verificar las versiones existentes, ingrese `--previous '旧索引本地路径'`. Si la verificación falla cuando el índice anterior no es válido, la protección de versiones no se omitirá silenciosamente. Cuando hay modificaciones no confirmadas en el espacio de trabajo, los resultados locales solo se utilizan para la vista previa; el lanzamiento oficial se genera enviando el código fuente extraído por el flujo de trabajo.

`.github/workflows/publish-sources.yml` Solo se ejecuta cuando los archivos relacionados con la rama predeterminada `main` del repositorio principal se envían o se activan manualmente desde `main`. El flujo de trabajo se ejecuta en serie y se comprueba el último `main`. al comienzo de cada tarea, y la dirección del script y el registro de liberación se fijan con el número de confirmación desprotegido real. Los envíos posteriores de documentos mientras se ejecuta la tarea no impedirán la publicación; Los envíos posteriores de archivos fuente activarán la siguiente tarea en serie. El flujo de trabajo primero descarga el índice estable existente y completa toda la verificación fuera de línea, y luego usa Git normal para enviar la actualización atómica a la rama `sources`; el índice en línea no se sobrescribirá cuando falle la verificación o se produzcan cambios simultáneos en la rama `sources`. Se puede crear una publicación por primera vez sin un índice estable. El comunicado solo indica que el script y el índice han pasado la verificación anterior. El acceso al sitio, el inicio de sesión de la cuenta y la carga de imágenes o videos aún deben verificarse por separado.


`type: 'video', category: 'shortvideo'` activa el flujo vertical a pantalla completa. Cada obra es un vídeo corto y `videos(id, '_')` devuelve medios actuales. `feed` usa `hasNext` y `cursor` para paginar automáticamente; los cursores no deben contener credenciales ni URLs multimedia firmadas. Solo se reproduce el vídeo actual; el siguiente se precarga en pausa y los demás reproductores se cancelan y liberan. No declares `search` sin una interfaz verificada.


La declaración opcional `imageNetwork` usa `mode: browser`, un `origin` HTTPS y `domains` dentro de los dominios de la fuente. Solo permite cabeceras autorizadas, sin credenciales ni redirecciones, con un límite de 20 MiB por imagen. Mantiene descifrado, validación, decodificación y caché particionada. Las páginas y API de Tik.porn usan sesiones de su propio origen; los medios son MP4.


## Lectura de novelas

`type: 'novel', category: 'novel'` · `capabilities.textChapter: true`

Implementar `textChapter(id, chapterId)` con `{title?, paragraphs: [String]}` de texto plano no vacío. Listas y detalles conservan `mediaKind: 'novel'`, `language: 'zh'` o `'en'`; sin portada se devuelve una cadena vacía. Unir solo páginas del mismo capítulo, sin respuestas, otros capítulos ni anuncios. El texto truncado requiere `LOGIN_REQUIRED`. Los capítulos tienen IDs estables y orden del sitio; un relato usa `chapters: null`. `Park.html.paragraphs(node)` extrae texto; cada capítulo se escribe atómicamente en `text.json`. Progreso y anotaciones usan posiciones UTF-16 originales. Los marcadores se guardan aparte y se incluyen en las copias de la biblioteca.

`paragraphs.join('\n\n')` → UTF-16


## Protocolo de suscripción

Declarar `subscription.normalize` y `subscription.posts` genera `capabilities.subscription` para la entrada independiente de suscripciones. La lógica del sitio permanece en el plugin. `normalize` valida nombres o perfiles controlados localmente, sin acceso ni red. `resolve` es opcional para resolver en línea; `targets` lista destinos unidos y genera `subscription.joinedTargets: true`. Los cursores son cadenas opacas, `hasNext: false` finaliza y una página vacía puede continuar. `locked` indica falta de permisos; `previewOnly` identifica vistas previas.

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

Adjuntos autorizados sin URL directa usan `media[].resource` con `size` entero y `cacheKey` estable y no secreto, independiente de credenciales o referencias caducables. `subscription.mediaChunk(resource, offset)` devuelve `{base64, done}`: máximo128 KiB por bloque, desplazamientos alineados, bloques intermedios completos y máximo512 MiB por adjunto. El anfitrión valida el total y escribe atómicamente en su caché, con archivos activos protegidos. El recurso no elige rutas; los destinos de copia no guardan URL firmadas ni resource.

Importar sesiones existentes mediante `account.type: 'session'` y un campo secreto, validado sin dividirlo en contraseñas/Cookies. Confirmar autorización real; guardar nunca sigue ni se une. `bodyBase64` nativo admite hasta2 MiB y excluye body/modo navegador; respuestas base64 disponibles. `digestBytes('sha1'|'sha256', bytes)` acepta hasta2 MiB de bytes enteros y `randomBytes(length)` acepta1–65536. Mantener TLS, aislamiento de dominios y restricciones de redirección; no abrir redes arbitrarias del navegador, WebSockets ni archivos.

[Suscripciones](../../SUBSCRIPTIONS.md)

Las fuentes con subscription y feeds aparecen también en categorías normales. Los elementos feed/search pueden incluir presentation:'post', text, date, url y media para tarjetas; presentation:'media' usa una cuadrícula. mediaKind y coverAspect describen los medios y las imágenes admiten paginación. network.confirmation:{selector,readySelector,requiredCookies,message} declara la confirmación, el marcador de contenido y las Cookie necesarias. Tras CONFIRM_REQUIRED, el navegador vuelve cuando desaparece la confirmación, aparece el contenido, se guardan las Cookie y la navegación se estabiliza. Nunca confirma por el usuario.


## Juegos

Las fuentes declaran `type:game`, `category:game` y `mediaKind:game`. `gameResources(workId)` devuelve datos estables y canales `{id,kind:direct|external,label,size}` sin URL resuelta. `resolveGameResource(workId,resourceId,channelId)` devuelve `{kind,url,urls?,filename?,extractionCode,archivePassword}` al pulsar o reintentar. La descarga directa requiere dominios HTTPS native `media` autorizados; se valida cada redirección sin enviar cookies. Conservar todos los enlaces y partes del archivo. No crear capítulos ni actualizaciones de lectura. No guardar ni registrar URL temporales.

GalgameX → KUN Galgame. [game-domain.md](../../game-domain.md)


## Recursos del salón de té

El salón de té aparece después de GalgameX y KUN y usa los posts populares del foro Galgame. Inicia sesión dentro de la app. Al pulsar para desbloquear se envía “感谢分享，好人一生平安”. Las listas y detalles son de solo lectura. No se responde de nuevo a posts ya desbloqueados. Un resultado incierto se guarda por cuenta y post; no se reenvía automáticamente, ni tras reiniciar. Comprueba el post original. La verificación dinámica se completa en el sitio. Se conservan enlaces originales, códigos por enlace y contraseñas de archivos. La sesión del navegador de escritorio es independiente de la app.

`GameChannel`: `requiresReply: true`, `replyText`. `resolveGameResource`: `extractionCodes` aligned with `urls` (empty string: no code), or shared `extractionCode`. `CONFIRM_REQUIRED` → original post URL.

Para CDN HLS dinámicas, declare `media.scope: 'session'` en modo native. Se autorizan la URL resuelta, los recursos de la lista y hasta 8 redirecciones solo durante la reproducción o descarga, sin ampliar permisos de Cookie. Se exige HTTPS 443 y solicitudes sin credenciales. La conexión directa valida DNS público y fija una IP comprobada conservando TLS. Un proxy HTTP explícito y de confianza resuelve los destinos y controla el acceso a redes públicas. Al cerrar se revocan los permisos. MP4 directo y browser mantienen la lista estática de dominios.
