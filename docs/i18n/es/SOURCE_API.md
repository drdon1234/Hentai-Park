[简体中文](../../SOURCE_API.md) · [繁體中文](../zh-Hant/SOURCE_API.md) · [日本語](../ja/SOURCE_API.md) · [한국어](../ko/SOURCE_API.md) · [English](../en/SOURCE_API.md) · [Español](SOURCE_API.md) · [Русский](../ru/SOURCE_API.md) · [العربية](../ar/SOURCE_API.md)

# API de plugins de sitios

[Inicio rápido](#inicio-rápido) · [Campos del manifest](#campos-del-manifest) · [Métodos](#métodos) · [API del entorno](#api-del-entorno) · [Códigos de error](#códigos-de-error) · [Localización](#localización) · [Publicación](#publicación)

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

### Probarlo en Node

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

## Campos del manifest

```js
Park.register({
  key: 'mysite',              // único y permanente; solo [A-Za-z0-9_-], 1–100 caracteres, no _app
  name: '我的站点',
  version: '0.0.1',
  minAppVersion: '0.9.2',           // tres números; la app ofrece actualizar si el repositorio tiene uno mayor
  type: 'comic',              // comic | video | novel | game: cómo se leen o reproducen las obras
  category: 'doujin',         // doujin | anime | aiDrama | jav | adult | shortvideo | recording | live | gallery | illustration | novel | game | other
  color: '#E5355F',           // color de marca: icono y página del sitio
  description: '一句话介绍',
  homepage: 'https://example.com',
  domains: ['example.com'],                   // sitios a los que pertenece, ver «Aislamiento y seguridad»; si falta, se deduce de homepage, etc.
  linkPatterns: ['example\\.com/g/(\\d+)'],   // los enlaces pegados abren la obra; el grupo 1 es el ID
  idPattern: '^(\\d+)$',                      // los ID escritos abren la obra
  imageHeaders: { Referer: 'https://example.com/' },  // cabeceras por defecto de portadas e imágenes
  network: { mode: 'auto', vpnHint: true },  // ver «Red»
  media: { mode: 'browser', origin: 'https://example.com', domains: ['media.example.com'] },  // permiso multimedia para vídeo y archivos directos
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
  postShortVideos: true,
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
| `gallery` | Galerías de fotos: cosplay, fotografía e imágenes de personas reales. Los sitios de imágenes usan `type: 'comic'`; cada conjunto es una obra y `chapter()` devuelve sus imágenes ordenadas, con lectura, favoritos y descargas compartidos. La cantidad de imágenes y su contenido no determinan la categoría |
| `illustration` | Galerías de ilustraciones: dibujos e imágenes de anime. Los sitios de imágenes usan `type: 'comic'`; cada conjunto es una obra y `chapter()` devuelve sus imágenes ordenadas, con lectura, favoritos y descargas compartidos. La cantidad de imágenes y su contenido no determinan la categoría |
| `anime` | Anime adulto |
| `aiDrama` | Dramas cortos de IA. No se acepta el antiguo `drama`; declara los nombres de canal del sitio tal cual, la categoría de la app no los filtra |
| `jav` | Sitios dedicados a JAV |
| `adult` | Vídeo adulto general (Pornhub, XVideos, 91porn…), `type: 'video'`. Una categoría es una agrupación; no sustituye las etiquetas del sitio ni los filtros del usuario |
| `shortvideo` | Vídeos cortos: flujo vertical a pantalla completa, ver abajo |
| `recording` | Grabaciones y vídeo bajo demanda, `type: 'video'` |
| `live` | Directos, `type: 'video'` |
| `novel` | Novelas, `type: 'novel'` |
| `game` | Juegos, `type: 'game'` |
| `other` | Comunidades de creadores |

- **Vídeos cortos** (`type: 'video', category: 'shortvideo'`): obras, búsqueda, favoritos e historial abren directamente el flujo. Cada obra es un vídeo y `videos(id, '_')` devuelve su medio actual; no hace falta página de detalles. `hasNext` y `cursor` de `feed` cargan la página siguiente cerca del final; los cursores no deben contener credenciales ni firmas de medios. Al refrescar se empieza por la primera página; el elemento actual se reproduce, el siguiente se precarga en pausa y el resto se libera. No declares `search` si el sitio no tiene búsqueda.
- **Vídeos de publicaciones** (`postShortVideos: true`): las páginas del sitio y de los objetivos de suscripción reproducen por separado los vídeos de `media[]`. Cada uno necesita una `url` directa o un `episodeId` no vacío; la resolución diferida llama a `videos(idOriginalDePublicación, episodeId)` al reproducir o precargar, sin usar páginas web como URL de medios. Las imágenes quedan fuera; se admiten `preview`, `format` y `headers`. La paginación y la actualización conservan el feed, los filtros o el ámbito de `subscription.posts` del objetivo. La reproducción distingue adjuntos; favoritos, historial e interacciones usan el ID original. No cambia la categoría ni implica una API aleatoria independiente.
- **Agregadores que solo reproducen en el sitio original**: siguen declarando `type: 'video', category: 'adult'`; sin una API de medios verificada no implementan `videos` y el entorno exporta `capabilities.videos: false`. El botón principal abre `detail.url` en el navegador del sistema, se ocultan reproducción, descargas y episodios, no se guardan capítulos falsos ni se comprueban actualizaciones; favoritos e historial siguen funcionando.
- **Novelas** y **juegos** se explican en «Métodos».

Elige `defaultFeed` en el orden **recomendados > clasificaciones > populares**; usa la página de novedades u otra entrada válida solo si el sitio no tiene ninguna de ellas, y nunca inventes una API no verificada. Si falta o no existe, la app elige por la key (primero `promote` / `recommend` / `featured`, luego `rank` / `toplist`, luego `popular` / `hot` / `trending`) y, si nada encaja, la primera pestaña.

Las fuentes que permiten acceso anónimo pero requieren iniciar sesión para las recomendaciones declaran `anonymousDefaultFeed: 'ranking'`. Debe apuntar a una entrada de `feeds` cuyo acceso anónimo se haya verificado, preferiblemente una clasificación. El inicio y la página de la fuente usan esta entrada sin sesión y `defaultFeed` con sesión; se conserva la pestaña elegida explícitamente. No interpretes toda lista vacía o error de red como una sesión anónima.

### Opciones

`feeds[].options`, `searchFilters` y `settings` comparten formato:

```js
{ key: 'sort', label: '排序', type: 'select', default: 'date',
  values: [{ value: 'date', label: '最新' }, { value: 'popular', label: '热门', color: '#f00' }] }
// type: select | multi | number | text | password | switch
// en settings se puede usar options en lugar de values
```

Cada entrada de `feeds` es una pestaña de la página del sitio: `{ key, label, options?: [...] }`.

### Filtros dinámicos y en cascada

Las opciones de selección de `feeds[].options` y `searchFilters` pueden declarar `dynamic: true, values: []`. Los hijos dinámicos referencian padres del mismo grupo con `dependsOn: ['range']`. Las claves deben ser únicas y las dependencias existentes y sin ciclos. Solo las opciones dinámicas declaran dependencias.

`filterOptions(request)` devuelve un array de opciones. La solicitud contiene `scope: 'feed' | 'search'`, `filter` y `values`; los listados incluyen `feed` y las búsquedas pueden incluir `keyword`. `values` solo contiene padres directos declarados, nunca cuentas, ajustes ni filtros ajenos. Los hijos no se cargan si un padre está vacío o sin seleccionar.

Declara `keywordDependent: true` si las opciones dependen de la palabra clave. Cambiarla restablece esa opción y sus descendientes y conserva los demás filtros. Los padres de `values` deben ser cadenas, números o booleanos, nunca arrays de selección múltiple. Las etiquetas remotas no son texto fijo de interfaz; se permite la traducción de contenido y etiquetas.

Devuelve como máximo 500 entradas `{value, label, color?}`. Los valores son cadenas únicas o números finitos. Las etiquetas son nombres originales no vacíos, sin caracteres de control y de hasta 256 caracteres; los colores tienen seis dígitos hexadecimales. Divide catálogos grandes en grupos en cascada sin truncarlos silenciosamente. Las etiquetas remotas no se traducen automáticamente.

Las selecciones llegan a `feed` mediante `options` y a `search` mediante `filters`. El plugin valida la pertenencia real al catálogo y conserva los filtros al paginar; los fallos de análisis generan errores. La app guarda las opciones dos minutos por sitio, ámbito, listado o palabra clave y valores superiores. Cambiar un padre borra los hijos y descarta respuestas antiguas; los fallos permiten reintentar.

Cada plugin de dominio lee solo su propio catálogo. Los dominios relacionados no llaman a otros plugins ni comparten cookies. Reutiliza plantillas de análisis al compilar y genera scripts independientes. Ejecuta `node tools/build_catalog_sources.mjs` para generar catálogos y `--check` para comprobar su coherencia.

```js
{key: 'category', label: '分类', type: 'select', default: '',
 dynamic: true, dependsOn: ['range'], values: []}

async filterOptions({scope, feed, filter, keyword, values}) {
  return [{value: 'site-category-id', label: 'Site category'}];
}
```

### Red

- `network.mode: 'auto'` (por defecto): primero usa HTTP nativo. En solicitudes GET/HEAD HTTPS del mismo origen sin cuerpo, los desafíos de Cloudflare, HTTP 403, 429 o errores de conexión recuperables activan un único reintento en el navegador. DNS, TLS, tiempos de espera, errores de flujo de respuesta y respuestas 5xx normales no activan el navegador para evitar latencia adicional. El destino debe estar dentro de los dominios declarados por la fuente y se mantienen las restricciones de mismo origen y redirección.
- `network.mode: 'native'`: Fuerza HTTP nativo con cookies persistentes y el proxy configurado. Una comprobación de Cloudflare devuelve `CLOUDFLARE` para reintentar en la app; si el error incluye una URL de verificación del sitio, el usuario puede abrir su página de confirmación.
- `network.mode: 'browser'` + `network.origin`: Envía `fetch()` del mismo origen desde una página oculta en `origin`. Las lecturas con Cloudflare (incluido HTTP 200) o una confirmación de edad sin las cookies/contenido necesarios navegan para verificar como máximo una vez antes de volver a leer; las escrituras no se repiten. La edad sigue `network.confirmation`. Android y Windows envían entrada al único checkbox estándar de Cloudflare; otras plataformas esperan la comprobación automática. Los fallos permiten reintentar o abrir la confirmación si se proporciona una URL de verificación del sitio.

  Los documentos navegan entre dominios declarados con el mismo protocolo y puerto. Si no se indica, el `origin` de la petición se obtiene de la URL del sitio de destino. La respuesta conserva la `url` final.

  El cambio automático excluye `followRedirects: false`, `connectAddress` y errores de red sin clasificar. Las solicitudes GET/HEAD del navegador sin cuerpo tienen como máximo tres intentos ordinarios y una repetición adicional tras la verificación, solo ante fallos de conexión o HTTP 408, 500, 502, 503 y 504; no se repiten 429 ni tiempos de espera. Cada solicitud lógica admite una sola navegación de verificación entre todos sus intentos. El inicio, las solicitudes, la lectura del documento y el cierre tienen esperas limitadas. Las cabeceras API personalizadas se envían mediante `fetch()`, sin sustituir la solicitud por una navegación. El HTML reutilizado conserva su estado de error; `responseType: 'base64'` devuelve los bytes originales en base64.

- `network.vpnHint: true`: decláralo en sitios que puedan necesitar VPN o proxy en China continental; las esperas de más de 8 segundos y los fallos mencionarán «puede necesitar VPN o proxy». No atribuyas todos los errores a la VPN.
- `network.confirmation: { selector, readySelector, requiredCookies, auto: { clickSelector }, message }`: Declara la confirmación de edad. `selector` identifica el diálogo, `auto.clickSelector` su único botón de confirmación, `readySelector` el contenido accesible y `requiredCookies` los nombres de cookies necesarios tras confirmar. Solo después de confirmar la mayoría de edad al entrar en la app, el navegador oculto simula un clic y comprueba que desaparezca el diálogo, aparezca el contenido, existan las cookies y termine la navegación. Las reglas incompletas, no coincidentes o fallidas permiten reintentar. Si el error incluye una URL de verificación del sitio, se puede abrir, resolver manualmente y pulsar Hecho. Se mantienen los límites de dominio y la separación de cookies; las notificaciones de operaciones no repiten automáticamente la acción original. No sirve para iniciar sesión, pagar o publicar.
- Los errores de red llevan los campos seguros `diagnostics` `host`, `transport` y `reason`, que distinguen certificados TLS, negociación, DNS, conexión y tiempos de espera; los registros automáticos solo guardan esos campos. `reason: 'TLS_HANDSHAKE_TERMINATED'` solo significa que `HandshakeException.message` nativo es exactamente `Connection terminated during handshake` (la conexión se cortó antes de completar la negociación, no un fallo de certificado); solo los GET/HEAD HTTPS sin cuerpo se reintentan una vez, y nada más se reintenta.

### Imágenes

- `imageNetwork: { mode: 'browser', origin, domains }`: Los dominios y subdominios de imágenes son independientes de las cookies del sitio. `origin` puede pertenecer al sitio o a imágenes. Usa HTTPS 443 y cabeceras permitidas, con la sesión del navegador para imágenes del mismo origen si origin pertenece al sitio; las imágenes de otro origen, los orígenes externos y los vídeos no envían credenciales, y admite redirecciones entre dominios autorizados. Se mantienen el límite de 20 MiB, descifrado, formato, decodificación y caché por sitio. Sin declaración se usa transporte nativo. Consulte los permisos de medios para las limitaciones de redirección del navegador por plataforma.
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

Todo complemento que implemente `videos()` debe declarar permisos `media` válidos, aunque solo devuelva MP4. `scope: 'session'` puede coexistir con `domains` estáticos: HLS usa las URL exactas autorizadas para la sesión; el MP4 directo debe coincidir con la lista de dominios estáticos. La publicación oficial rechaza declaraciones ausentes o no válidas.

```js
domains: ['example.com'],
network: { mode: 'native' },
media: { mode: 'native', origin: 'https://example.com', domains: ['media.example.com'] },
```

- `media.mode` es `'native'` o `'browser'`. `media.origin` debe pertenecer a los sitios del plugin, usar HTTPS en el puerto 443 y no llevar credenciales, consulta ni fragmento.
- `media.domains` es una lista aparte de dominios de medios (con subdominios) que no da acceso a cookies del sitio. Listas, segmentos y claves deben ser HTTPS en 443; se rechazan credenciales en la URL, fragmentos, IP, localhost (y subdominios) y `.local`.
- `'native'`: Usa un cliente independiente sin cookies, Authorization ni autenticación de proxy; comprueba cada redirección antes de conectar. Permite `Referer`, `Origin`, `Accept`, `Accept-Language`; las dos primeras pertenecen a dominios declarados del sitio, incluidos subdominios de idioma. `Origin` contiene solo el origen.
- `media.referrerDomains` es opcional, solo para medios de vídeo nativos y con un máximo de 16 dominios públicos válidos (incluidos subdominios). Amplía únicamente los orígenes permitidos de `Referer`, como excepción explícita a los dominios del sitio anteriores. No concede permisos adicionales de `Origin`, URL multimedia, navegación de documentos ni cookies, y no es válido para `imageNetwork` o medios de navegador.
- `'browser'`: Abre una sesión oculta en `media.origin`, con navegación dentro de los dominios del sitio. Usa `credentials: 'omit'`, `mode: 'cors'`; el documento real y el navegador generan Origin/Referer. En Windows, WebView2 comprueba cada dominio antes de conectar y permite redirecciones autorizadas, comprobando también la URL final. Otros motores no permiten interceptar cada salto y usan `redirect: 'error'`. CORS y la CSP siguen vigentes; comprobar solo la URL final no autoriza redirecciones.
- Las respuestas se limitan en tamaño mientras llegan y se vuelve a comprobar su dirección final: listas de hasta 2 MiB, segmentos de hasta 32 MiB y claves AES-128 de exactamente 16 bytes. Se rechazan respuestas demasiado grandes o vacías y direcciones no permitidas.

- Los CDN HLS dinámicos pueden declarar `media.scope: 'session'` con `mode: 'native'`. La autorización solo cubre las URL, recursos de listas y redirecciones permitidas de la sesión actual de reproducción o descarga, y caduca al cerrarla. No amplía permisos de cookies ni dominios persistentes. Se mantienen HTTPS, las peticiones sin credenciales y los límites de destino y tamaño; MP4 directo y medios del navegador conservan sus listas estáticas.

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
  loginUrl?, cookieUrl?, requiredCookies?: ['session_id'],   // permite iniciar sesión en la web; la app recoge las cookies
  loginDomains?: ['accounts.google.com', 'appleid.apple.com'],  // dominios de inicio de sesión de terceros, solo para navegar al iniciar sesión
  localStorageKeys?: ['session_key'],  // solo claves localStorage permitidas del origen cookieUrl, pasadas a login(values); no registrar valores
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
- `managedAccount: true` y `account.enableManaged()` ofrecen gestión opcional de cuentas, que solo se activa tras la confirmación informada del usuario. Guarda por separado las cuentas manuales y gestionadas sin sobrescribir credenciales existentes. Los datos de cuenta permanecen en el dispositivo y no deben aparecer en documentación, diagnósticos ni archivos de publicación.
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

**WorkItem**: `{ id, title, subtitle?, cover, coverBlurred?, coverAspect?, pages?, rating?, likes?, views?, language?, category?, badge?, badgeColor?, duration?, uploaded?, tags?, mediaKind?, workCode?, editions? }`

- `workCode` es un código de obra confirmado por la fuente y se usa solo para buscar la misma obra. No sustituye a `id` ni fusiona identidades, favoritos, progreso o descargas.
- `editions` contiene etiquetas fijas de edición indicadas explícitamente por la fuente, como subtítulos en chino o una filtración sin censura. La ausencia de etiquetas no implica una edición original. La traducción visible no modifica las etiquetas originales.

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
  related?: [WorkItem], series?: [WorkItem], variants?: [WorkItem],
}
```

- `variants` incluye únicamente enlaces reales proporcionados por la fuente a ediciones de la misma obra en esa fuente, cada una con su propio `id`; no se deben adivinar URL. Las ediciones de otras fuentes se buscan mediante `workCode`; favoritos, progreso y descargas permanecen independientes.

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

Devuelve `[{ quality: 1080, label: '1080P', url, headers?, format?, preferred?, hls? }]`. Los enlaces directos suelen caducar, así que la app los vuelve a pedir antes de cada reproducción o descarga.

- `format: 'hls'` admite `hls: {manifest, keys}`: `url` es la base HTTPS real de la variante; `manifest` es una lista multimedia VOD completa ya procesada (máximo 2 MiB UTF-8); `keys` asigna las URL absolutas de claves referenciadas a claves de 16 bytes en Base64, hasta 32 entradas. Solo para medios nativos. Se mantienen la autorización de direcciones y la validación del contenido; se rechazan claves no referenciadas. Estos resultados no se guardan en la caché de disco; las claves solo permanecen en la memoria de sesión, nunca en store, registros, obras o cursores.

- Los vídeos con varios episodios devuelven `[{ id, title }]` en orden de reproducción en `detail(id).chapters`; cada `id` debe ser estable, nunca una calidad ni una URL temporal. La app usa el mismo ID para elegir episodios, guardar el progreso, descargar y reanudar, y llama a `videos(id, episodeId)` para cada episodio. Los vídeos sueltos usan `singleChapterId`, o `'_'` si no existe.
- Sin `format`, reproducción y descarga tratan el enlace como MP4 directo. HLS debe devolver `format: 'hls'` y declarar el permiso `media`.
- La app expande una lista maestra HLS (`#EXT-X-STREAM-INF`) en listas por variante y toma la calidad real de `RESOLUTION`. Si devuelves una maestra, `quality` es la calidad deseada: se elige la mayor calidad real que no la supere o, si no hay, la más alta. Cada variante debe ser MPEG-TS o fMP4 de VOD con audio y vídeo multiplexados; se rechazan las versiones `AUDIO`, `VIDEO`, `SUBTITLES` separadas y las direcciones fuera de `media.domains`. Las pistas `#EXT-X-I-FRAME-STREAM-INF` se ignoran. Si una lista simple no tiene resolución conocida, usa `label: '原画'` en vez de presentar la calidad deseada como real. Sin `RESOLUTION` se exige `BANDWIDTH` válido: se conservan las variantes en kbps y se prefiere la de mayor tasa, sin inventar resoluciones.
- `type: 'video', category: 'live'` identifica directos públicos en 3D con tarjetas solo de imagen. `videos()` devuelve el HLS de la sala pública actual; no inventes resultados reproducibles para salas privadas, de pago o desconectadas. Se usan listas móviles sin progreso VOD ni descargas. La grabación requiere una acción explícita y solo guarda segmentos posteriores a la ventana inicial. Termina al detenerla o salir de la aplicación, sin reanudarse al reiniciar. Una sesión independiente y una tarea en segundo plano validan y descifran cada segmento y guardan una lista local completa. Al reconectar se resuelve de nuevo el medio; los cambios de codificación y las grabaciones largas pueden crear nuevas partes. Se conservan los datos guardados si falla. Solo se admite MPEG-TS multiplexado; MAP/fMP4, PART de baja latencia, BYTERANGE y GAP no se admiten.
- VOD requiere listas MPEG-TS o fMP4 completas y continuas con `#EXT-X-ENDLIST`. fMP4 admite un solo segmento de inicialización `#EXT-X-MAP` antes de los medios, sin cambios ni rangos de bytes. Se autorizan, validan y reescriben localmente ambos tipos de segmento; la reproducción sin conexión y la exportación conservan la inicialización. Los directos siguen usando MPEG-TS con listas móviles y discontinuidades. Ambos descifran `METHOD=AES-128`, `KEYFORMAT=identity` con CBC/PKCS7 y claves de 16 bytes. El IV de los medios es explícito o derivado de la secuencia; la inicialización cifrada exige un IV explícito. Las claves permanecen en la memoria de la sesión. No se admiten SAMPLE-AES, otros KEYFORMAT, BYTERANGE ni GAP; VOD tampoco admite discontinuidades. Se elimina `#EXT-X-TOKEN`.
- Las listas HLS y los segmentos MPEG-TS admiten envolturas PNG `roUd` (sin compresión o con zlib). Se extraen antes de analizar, validar o descifrar, con límites de 2 MiB por lista y 32 MiB por segmento extraído. Los plugins siguen devolviendo `format: 'hls'` sin permisos adicionales.
- La reproducción usa un puerto aleatorio ligado a `127.0.0.1` y un token aleatorio, y sirve bajo demanda segmentos verificados desde un registro limitado de URL; cerrar la sesión cancela las solicitudes. Las descargas HLS sin conexión solo funcionan en Android por ahora: cada segmento se verifica y se guarda su SHA-256, se pueden reanudar y cancelar, y Media3 crea al final un MP4; solo los archivos completos llegan a la biblioteca sin conexión. fMP4 conserva la inicialización y los medios en orden, sin conversión TS mediante Media3.

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
- Para una entrada independiente de comunidades, declara `communities: true`, `communityHint` y `communityExample`; el runtime exporta esos metadatos sin cambios. Los objetivos devuelven `{ id, label, kind: 'community' }` con ID distintos de los creadores. `targets({ kind: 'community' })` lista comunidades a las que se pertenece y `targets()` los objetivos predeterminados. Trátalos por separado para que un fallo comunitario no rompa la lista de creadores. `resolve` solo comprueba nombres y acceso en lectura; nunca se une automáticamente.
- Los cursores de `posts` son cadenas opacas; la última página tiene `hasNext: false` y las páginas sin medios pueden seguir. `locked` indica falta de permisos; `previewOnly` marca vistas previas públicas: nunca hagas pasar una miniatura por el contenido completo.

### Álbumes públicos: `subscription.media`

Los álbumes son una capacidad independiente: no se construyen con publicaciones ya cargadas ni recurren a `subscription.posts`. Implementa `subscription.media(scope, { page, cursor })`; una fuente con feeds públicos y sin objetivos suscribibles puede declarar solo este método en `subscription`. El runtime exporta `capabilities.album` por separado de `capabilities.subscription`.

`scope` es `{ feed, options }` o `{ target }`: feed con filtros o usuario, comunidad, canal o grupo. La fuente resuelve y recorre objetivos sin condiciones por sitio en la interfaz. Devuelve `{ items, cursor, hasNext }`; una página sin medios coincidentes puede continuar y cada cursor debe avanzar. Los cursores repetidos son errores.

Cada elemento lleva un `id` de cadena estable, `presentation: 'post' | 'work'`, fecha ISO 8601 interpretable si se conoce y el array `media` completo en orden del sitio. Cada adjunto tiene `id` de cadena único y estable, `type: 'image' | 'video'` y `url` de contenido real o `resource` controlado. `preview` es una miniatura de imagen; `previewResource` usa el formato controlado descrito abajo, con máximo de 2 MiB y una imagen independiente. No uses portadas ni URL de vídeo como miniaturas falsas. El contenido restringido solo muestra vistas públicas con `previewOnly: true`, conserva el desenfoque original y usa `locked: true` si toda la publicación está bloqueada.

La fuente completa adjuntos entre páginas y une grupos del sitio. El cliente fusiona obras repetidas por `id` de adjunto; el `order` numérico finito opcional solo ordena si está presente en todos los adjuntos de la obra. Las fechas locales se filtran con extremos incluidos y se excluyen fechas desconocidas al fijar un rango. Los filtros de imagen/vídeo y plegar publicaciones no cambian identidades. Tras un número limitado de páginas vacías filtradas se puede continuar manualmente. `presentation: 'work'` abre detalles y `'post'` la publicación completa. Las portadas solo cargan imágenes o miniaturas explícitas, nunca URL de reproducción.

- `coverBlurred: true` y `blurred: true` en medios conservan el desenfoque del sitio en miniaturas e imágenes completas. No muestres fotos restringidas como contenido completo sin desenfocar. Las vistas previas y los vídeos completos resuelven el maestro HLS antes de reproducir la variante VOD elegida.
- Los adjuntos autorizados sin enlace directo usan `media[].resource` e implementan `mediaChunk(resource, offset)`: como mucho 128 KiB por llamada, con offsets alineados a 128 KiB; el resource debe tener un `size` entero y una cadena `cacheKey` estable y no secreta que no cambie con credenciales ni referencias temporales. El framework comprueba el tamaño total y cada fragmento y escribe de forma atómica en su propia caché; un adjunto puede ocupar hasta 512 MiB y el resource no elige la ruta local. Ni los enlaces firmados ni los resources se guardan en los registros de suscripción.
- Las suscripciones que sigan o se unan en el sitio original deben explicar la acción y pedir confirmación antes de guardar. Las escrituras no verificadas deben dirigir al usuario al sitio original; nunca seguir, unirse ni pagar de forma silenciosa.

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
| `Park.url.parse(value, base, domains)` / `site(source, value, base?)` / `response(source, response, requested)` | Analiza URL HTTPS 443 autorizadas con subdominios, rechaza credenciales, elimina fragmentos y devuelve `null` si falla. `site` usa los `domains` de la fuente; `response` valida la URL final y no modifica la base compartida de la fuente, o lanza `BLOCKED`. El plugin comprueba ruta, página, obra y búsqueda; evite listas cerradas de claves y nombres de nodos CDN. |
| `Park.utils.rateLimiter(ms)` | devuelve `wait()` y garantiza un intervalo mínimo entre solicitudes |
| `Park.utils.mapLimit(items, n, fn)` / `lruMap(n)` / `parseCount('1.2万')` / `formatDate(ts)` | otras utilidades |
| `Park.error(code, message, extra?)` | crea un error con código, ver «Códigos de error» |

`Park.crypto.aesGcmDecrypt(ciphertext, key, iv)` recibe texto cifrado hexadecimal (incluida la etiqueta final de autenticación de 16 bytes, máximo 4096 bytes), una clave de 16/24/32 bytes y un IV de 12 bytes; devuelve bytes en claro. Si falla la autenticación, lanza un error sin devolver texto sin autenticar.

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

- Los resultados en vivo de `feed` conservan todos los campos. La caché privada y reconstruible en disco guarda metadatos permitidos, texto de publicaciones, datos de acceso a adjuntos y campos de detalle admitidos para abrir entradas antes de actualizar. Puede contener URL de medios temporales y referencias de recursos; los enlaces vencidos requieren actualizar. No sustituye descargas ni copias de seguridad. La identidad de caché separa sitio, cuenta, configuración y ámbito de solicitud. No incluyas credenciales en contenido devuelto, ID ni cursores, ni copies datos de acceso a diagnósticos o registros de suscripción.
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
  "apiVersion": 2,
  "sources": [
    {
      "key": "mysite",
      "name": "我的站点",
      "version": "0.0.1",
      "minAppVersion": "0.9.2",
      "description": "一句话介绍",
      "url": "https://example.com/sources/mysite.js",
      "sha256": "SHA-256 en 64 dígitos hexadecimales del texto UTF-8 del script",
      "apiVersion": 2
    }
  ]
}
```

`url` es la dirección completa del script; también vale `file` relativo a `index.json`. Los repositorios de terceros se instalan a mano tras confirmar el usuario; `sha256` es opcional y se comprueba si existe.

### Versiones y reglas de actualización

- Los plugins deben declarar minAppVersion (por ejemplo, 0.9.2), coincidente con el índice oficial. El apiVersion actual es 2 y requiere HentaiPark 0.9.2 o posterior. Las actualizaciones y las instalaciones por URL comprueban la compatibilidad antes de sustituir el plugin; si no es compatible, se conserva el instalado. Los avisos automáticos separan las actualizaciones compatibles de las que requieren una app más reciente. Ignorar esta versión solo silencia las versiones de la app o de los plugins indicadas, persiste tras reiniciar y no afecta a las comprobaciones manuales.

- Las versiones son tres enteros no negativos separados por puntos y sin ceros a la izquierda (p. ej. `0.0.1`), comparados numéricamente por partes; se rechazan partes de menos o de más y sufijos de prelanzamiento.
- Las actualizaciones oficiales deben aportar el `sha256` del texto UTF-8 del script (sin recortar espacios ni convertir saltos de línea), y la `key` y la `version` del script deben coincidir con el índice; `apiVersion` debe ser exactamente la del entorno de la app o se rechaza la actualización.
- Las versiones de plugins y de la app son independientes. Al cambiar un script (también su `i18n`), sube la versión en el script y en `assets/sources/index.json`; el publicador rechaza bajadas de versión y una misma versión con contenido distinto.

### Actualizaciones oficiales en la app

- «Buscar actualizaciones de plugins al iniciar», en Más → Sitios y Más → Acerca de → Actualizaciones, está activado por defecto: cada arranque solo lee el índice oficial, avisa de versiones nuevas y descarga, verifica e instala solo tras confirmar el usuario. Al volver al primer plano se respeta un intervalo de 12 horas y los fallos también registran la hora. Con las comprobaciones automáticas apagadas siguen funcionando las manuales. Solo se comprueban los plugins integrados y oficiales instalados; no se instalan plugins nuevos automáticamente ni se sustituyen plugins de terceros con la misma key.
- La instalación vuelve a verificar identidad, versión, origen, API y resumen, y solo termina cuando la inicialización y el guardado del estado salen bien; si falla, se conservan el script antiguo y el estado del usuario, y una instalación interrumpida se recupera en el siguiente arranque. Arrancar nunca sobrescribe plugins instalados con los scripts incluidos; si falta un script, se conservan su registro y sus datos hasta que el usuario lo restaure o actualice. «Restaurar la versión integrada» vuelve, tras confirmar, a la versión incluida en el paquete actual.
- Las actualizaciones de la app también se comprueban por defecto: en Android, tras confirmar, la app descarga el APK oficial adecuado, verifica tamaño, SHA-256, nombre de paquete, versión y firma y abre el instalador del sistema, con progreso, cancelación y reintento; la página oficial de versiones es la alternativa.

### Publicar los plugins oficiales

Los plugins oficiales se mantienen en `assets/sources/index.json`. `tools/publish_sources.mjs` comprueba el índice y las declaraciones del entorno sin conexión y genera un índice de publicación con URL inmutables y SHA-256. No inicia sesión ni llama a métodos del sitio y no sustituye la verificación real. Los pasos de compilación y publicación están en la [guía de desarrollo](../../DEVELOPMENT.md).

### Plugins generados

La única implementación del plugin de Telegram es `assets/sources/telegram_entry.mjs`; `assets/sources/telegram.js` se genera y no debe editarse a mano:

```powershell
npm ci --prefix 'tools/source-runner'
node tools/build_subscription_sources.mjs
```

Usa [@mtproto/core 6.3.0](https://github.com/alik0211/mtproto-core) (GPL-3.0, [licencia](../../licenses/mtproto-core.txt); resumen de dependencias en [licencias de terceros](../../licenses/telegram-dependencies.txt)). El adaptador del sitio sustituye transporte, criptografía y almacenamiento, y no activa el WebSocket predeterminado de la biblioteca, el localStorage del navegador ni los registros de depuración.

### `webVideo(id, episodeId)`

La reproducción web resuelve Cloudflare en una sesión temporal aislada. Solo permite el marco de verificación exacto `challenges.cloudflare.com`, nunca la navegación principal a ese host. `network.confirmation` solo se aplica a los dominios declarados por la fuente, no a reproductores externos. Si la verificación automática no termina, la página permanece disponible para el usuario; no se importan ni exportan cookies del reproductor. `CONFIRM_REQUIRED` conserva el mensaje del plugin y permite completar la verificación en la app y sincronizar la sesión de la fuente, sin repetir la operación original.

Los proveedores compatibles de iXXX y TubeSafari priorizan la reproducción nativa, con reanudación y guardado sin conexión. Los demás usan reproducción web integrada, que puede requerir confirmación del sitio y no permite descargas de la app ni reanudación precisa. En Android, la reproducción web requiere un Android System WebView reciente con sesiones aisladas.

El entorno exporta `capabilities.webVideo` automáticamente. Si solo se implementa `webVideo`, abre una página web integrada. Si se implementan `videos` y `webVideo`, prioriza la reproducción nativa y solo pasa a la web cuando `videos` devuelve `UNSUPPORTED`. Los errores de HTTP, red, Cloudflare, inicio de sesión, análisis, contenido eliminado y cancelación se muestran sin cambios. Las descargas requieren medios nativos resueltos correctamente y nunca pasan a una página web.

```js
return { url: "https://player.example.com/watch/1", navigationDomains: ["player.example.com"], frameDomains: [] };
// Native HTTP only: this.http.get(url, { followRedirects: false })
```

## Clasificaciones y distribución independiente

`rankings` declara listas mediante `key`, `label`, `category`, `metric` y `options`. Un complemento dedicado usa `rankingOnly: true` y no declara `feeds`. `ranking(board, {page, offset, cursor, options})` devuelve una página de obras con `id`, `rank` original, `title`, `cover` y campos opcionales `keyword`, `subtitle` y `url` HTTPS del producto. Se conservan los empates. Una fuente existente puede declarar `feed`: hereda sus opciones si se omiten y reutiliza `feed()`, conserva los campos y añade `workId` y el puesto si falta, para abrir los detalles. Las entradas comerciales buscan en la categoría declarada.

Los scripts se mantienen en la rama principal. Las ramas `sources`, `rankings` y `reverse-search` distribuyen complementos generales, solo de clasificaciones y solo de búsqueda inversa, respectivamente. Cada una contiene un índice con URL de commits inmutables y SHA-256. La app consulta los tres canales por separado, rechaza canales incorrectos y claves duplicadas, y pide confirmación antes de actualizar. Las traducciones de etiquetas se distribuyen por `tag-translations`.

```powershell
node tools/publish_sources.mjs --commit '<SHA>' --channel rankings --output '<本地输出文件>'
```
