[简体中文](../../SOURCE_API.md) · [繁體中文](../zh-Hant/SOURCE_API.md) · [日本語](../ja/SOURCE_API.md) · [한국어](../ko/SOURCE_API.md) · [English](../en/SOURCE_API.md) · [Español](SOURCE_API.md) · [Русский](../ru/SOURCE_API.md) · [العربية](../ar/SOURCE_API.md)

# Guía de desarrollo del complemento fuente

Cada origen de HentaiPark es un archivo JavaScript independiente. Las aplicaciones las cargan en tiempo de ejecución: se pueden instalar, actualizar, habilitar/desactivar desde el repositorio de origen sin volver a compilar la aplicación.
La fuente incorporada se encuentra en [`assets/sources/`](../../../assets/sources/) y se puede utilizar directamente como referencia de ejemplo.

## Entorno de ejecución

- El script fuente se ejecuta en un WebView sin cabeza dentro de la aplicación (JS moderno completo con `DOMParser`). La capa nativa proporciona la red, el cifrado y las cookies, por lo que no hay restricciones de CORS.
- El mismo tiempo de ejecución ([`assets/runtime/park_runtime.js`](../../../assets/runtime/park_runtime.js)) también se puede ejecutar en Node, y puedes realizar pruebas de humo directamente en el sitio real durante el desarrollo:

  ```bash
  cd tools/source-runner && npm install
  node ../../test/source-runner/smoke.mjs nhentai.js --keyword "tag:\"full color\""
  ```

  `smoke.mjs` es un archivo de pruebas local ubicado en `test/source-runner/` y no se distribuye con el repositorio. Comprueba cada feed (incluida la segunda página), búsqueda, obras aleatorias, detalles, portadas, capítulos y la descarga de las imágenes de la primera y última página.

## Registrar una fuente

```js
Park.register({
  key: 'mysite',              // Identificador único, no se puede cambiar después de la instalación
  name: 'Example Source',
  version: '0.0.1',           // Cuando el número de versión en el almacén sea mayor, la aplicación solicitará una actualización.
  type: 'comic',              // comic | video
  color: '#E5355F',           // Color de marca: utilizado para tarjetas de entrada de origen y colores de tema de página de origen
  description: 'Example source description',
  homepage: 'https://example.com',
  domains: ['example.com'],                   // Para conocer el sitio al que pertenece, consulte "Aislamiento y seguridad"; si se omite, se deducirá de la dirección, como la página de inicio.
  linkPatterns: ['example\\.com/g/(\\d+)'],   // Se utiliza para acceso directo al pegar enlaces en búsquedas agregadas; el primer grupo es el ID del trabajo
  idPattern: '^(\\d+)$',                      // Se utiliza para acceso directo al ingresar el número directamente
  imageHeaders: { Referer: 'https://example.com/' },  // Se lleva por defecto al cargar portadas e imágenes.
  network: { mode: 'native' },                // Ver la sección "Red"

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
  async detail(id) {},
  async chapter(id, chapterId) {},            // historietas
  async resolveImage({ id, chapterId, index, token, retry }) {},  // Opcional: análisis retrasado de imágenes
  async thumbnails(id, page) {},              // Opcional: cargar miniaturas de vista previa en páginas
  async videos(id) {},                        // video
});
```

En el método, puedes utilizar `this` para acceder:

| Miembros | Descripción |
|------|------|
| `this.http` | `request(opts)`, `get(url, opts)`, `post(url, opts)`, `text(url, opts)`, `json(url, opts)` |
| `this.config` | El valor seleccionado por el usuario en la configuración de origen (`default` si no está configurado) |
| `this.store` | Almacenamiento persistente de valores-clave: `get(key, fallback)` / `set(key, value)`, utilizado para guardar tokens, listas de nombres de dominio, etc.; `await flush()` confirma que la escritura en el disco fue exitosa y arroja un error si falla |
| `this.cookies` | `get(url)` / `set(url, {name: value})` / `clear(url)` |
| `this.log(...)` | Escriba en el "Registro de ejecución" de la aplicación |

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

`text()`/`json()` generará automáticamente un error (404 → `NOT_FOUND`) cuando encuentre una respuesta que no sea 2xx. La cookie se guarda automáticamente y persiste cuando se siguen las redirecciones.

## Estructura de datos

**Página de lista** (valor de retorno de `feed` / `search`)

```js
{
  items: [WorkItem], page: 1, totalPages: 20, total: 500,
  hasNext: true,
  cursor: '12345',        // Opcional: los sitios donde el cursor pasa de página (como E-Hentai) devuelven el cursor de la página siguiente y la aplicación lo devolverá tal como está la próxima vez que realice una solicitud.
}
// O diseño de sección (cuando el diseño del feed es 'secciones'):
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

**Video** (`videos`): `[{ quality: 1080, label: '1080P', url, headers?, preferred? }]`. Los enlaces directos de video generalmente tienen un límite de tiempo y la aplicación los volverá a obtener cada vez antes de reproducirlos o descargarlos.

## Definición de opción

`feeds[].options`, `searchFilters`, `settings` utilizan el mismo formato:

```js
{ key: 'sort', label: 'Sort', type: 'select', default: 'date',
  values: [{ value: 'date', label: 'Latest' }, { value: 'popular', label: 'Popular', color: '#f00' }] }
// type: select (selección única) | multi (selección múltiple) | number | text | password | switch
// En settings también se puede usar options en lugar de values.
```

Cada elemento de `feeds` es una pestaña en la página de origen: `{ key, label, layout?: 'grid' | 'sections', options?: [...] }`.

`defaultFeed` Especifica qué pestaña ingresar de forma predeterminada al abrir la página de origen. Cuando la clave correspondiente no está completa o no se puede encontrar, la aplicación seleccionará automáticamente de acuerdo con la clave en el orden de Recomendación > Clasificación > Popular (la clave incluye `promote` / `recommend` / `featured`, y luego `rank` / `toplist`, luego `popular` / `hot` / `trending`), si no, ingresa el primero etiqueta.

## red

- `network.mode: 'native'` (predeterminado): la solicitud HTTP nativa, que utiliza cookies persistentes, puede pasar por el proxy configurado por el usuario. Si se detecta la consulta Cloudflare, se generará `CLOUDFLARE`. La aplicación guiará al usuario para completar la verificación en el navegador integrado y sincronizar la cookie común con la solicitud nativa.
- `network.mode: 'browser'` + `network.origin`: La solicitud se realizó con origen `fetch()` en una página oculta del navegador abierta en `origin`, con una huella digital real del navegador. Se aplica a Cloudflare sitios que están más protegidos (por ejemplo, Hanime1).

## Aislamiento y seguridad

- Cada fuente se ejecuta en un entorno JS **independiente** (cada una tiene un WebView sin interfaz) y las fuentes no pueden ver los objetos globales de cada una; el puente nativo solo reconoce de qué entorno proviene la llamada y los scripts no pueden hacerse pasar por otras fuentes.
- Cada fuente tiene un contenedor de cookies independiente: la solicitud emitida por la fuente solo traerá y guardará su propia cookie, y no leerá el estado de inicio de sesión de otras fuentes.
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

Un almacén es `index.json`, que se puede colocar en cualquier hosting estático (como GitHub raw):

```json
{ "name": "Example source repository", "sources": [
  { "key": "mysite", "name": "Example Source", "version": "0.0.1", "type": "comic", "file": "mysite.js", "description": "…" }
] }
```

`file` es la ruta relativa a `index.json` (también puedes escribir el `url` completo). Los usuarios pueden navegar, instalar y actualizar ingresando la dirección del almacén en "Administración del sitio de origen → Agregar origen".

Cuando la cuenta de mantenimiento automático encuentra una falla, la cantidad de fallas y el siguiente tiempo de reintento deben guardarse y volverse a intentar en el intervalo de retroceso; No se permite el registro o inicio de sesión repetidos durante el período límite actual. Los usuarios que reintenten activamente seguirán reutilizando la cuenta original y no podrán saltarse el límite actual del lado del servidor.
