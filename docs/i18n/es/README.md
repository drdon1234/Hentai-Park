[简体中文](../../../README.md) · [繁體中文](../zh-Hant/README.md) · [日本語](../ja/README.md) · [한국어](../ko/README.md) · [English](../en/README.md) · [Español](README.md) · [Русский](../ru/README.md) · [العربية](../ar/README.md)

<p align="center"><img src="../../images/banner.svg" alt="HentaiPark · 18+" width="100%"></p>

<p align="center"><strong>Tu cliente de contenido para adultos. Descubre, lee, mira y guarda en un solo lugar.</strong></p>

<p align="center">Explora doujinshi, anime para adultos, JAV, galerías, vídeos, novelas y juegos, y retoma lo que estabas viendo.</p>

<p align="center">
  <a href="https://github.com/drdon1234/Hentai-Park/releases/latest"><img src="https://img.shields.io/github/v/release/drdon1234/Hentai-Park?label=Download&amp;color=C96442" alt="Download"></a>
  <img src="https://img.shields.io/badge/18%2B-Adult_content-C96442" alt="18+">
  <img src="https://img.shields.io/badge/Android_7.0%2B-333333" alt="Android 7.0+">
</p>

<p align="center"><a href="https://github.com/drdon1234/Hentai-Park/releases/latest">Descargar</a> · <a href="#screenshots">Demostración</a> · <a href="#features">Funciones</a> · <a href="#faq">Preguntas</a> · <a href="https://github.com/drdon1234/Hentai-Park/issues">Comentarios</a></p>

> **18+** Solo para adultos y donde lo permita la ley local. El contenido procede de sitios externos; HentaiPark no lo aloja.

## Descarga y plataformas

**[Descargar](https://github.com/drdon1234/Hentai-Park/releases/latest)**

**Android 7.0+**

[Plataformas e instalación](../../PLATFORMS.md)

[Despliegue Web](../../WEB_DEPLOYMENT.md) · `drdon1234/hentai-park`

<a id="screenshots"></a>

## Demostración

https://github.com/user-attachments/assets/d648927a-e4d6-48e8-b8c0-b77349ffd607

## Primeros pasos

1. En Explorar, elige una categoría y un sitio, o busca por obra, etiqueta, enlace o código.
2. Abre una obra para leerla o verla. Guárdala en Favoritos o descárgala para usarla sin conexión.
3. Retoma desde Inicio → Continuar → Todo y consulta capítulos nuevos en Favoritos → Actualizaciones.

Configura el acceso en Más → Sitios y el proxy en Más → Red cuando sea necesario.

### Web autohospedada (Docker Compose)

Accede desde navegadores de escritorio o móviles a una instancia de un solo usuario. El destino Docker es linux/amd64. La primera imagen estará disponible después de subir el código y completar correctamente el flujo Release platforms; antes de publicarla, utiliza la compilación local documentada.

```sh
git clone https://github.com/drdon1234/Hentai-Park.git
cd Hentai-Park
cp clients/web/.env.example clients/web/.env
```

Tras copiar la plantilla, edita `clients/web/.env`: configura `WEB_IMAGE=drdon1234/hentai-park:latest`, un `AUTH_TOKEN` aleatorio (al menos 16 caracteres) y el `WEB_ALLOWED_ORIGIN` HTTPS real.

```sh
docker compose -f clients/web/compose.yaml pull
docker compose -f clients/web/compose.yaml up -d --no-build
```

Por defecto solo se escucha en `127.0.0.1:8787`. Accede mediante un proxy inverso HTTPS y desbloquea con `AUTH_TOKEN`; no se necesita un nombre de usuario predeterminado. El volumen `park-data` conserva `/data`, con las descargas en `/data/downloads`. Actualiza con `pull` y `up -d --no-build`; detén con `stop`, nunca con `down -v` para una parada normal.

[Despliegue, compilación local antes de publicar y permisos de directorios](../../WEB_DEPLOYMENT.md)

<a id="features"></a>

## Funciones

| Función | Qué ofrece |
| --- | --- |
| Descubrir y buscar | Filtra por 2D, 3D y tipo de contenido; busca en varios sitios o abre una obra con un enlace o código. |
| Leer y ver | Artículos de cotilleos y vídeos; cómics con desplazamiento, páginas y doble página; episodios, velocidad y reanudación de vídeo; marcadores, notas y lectura de novelas en voz alta. |
| Favoritos y novedades | Organiza grupos, guarda el progreso y consulta capítulos nuevos. Sigue autores, canales o palabras clave. |
| Juegos en línea | Juega en el navegador sin instalar paquetes, con pantalla completa y controles virtuales opcionales. |
| Sin conexión y exportación | Descarga cómics, vídeos, audio, novelas, publicaciones, adjuntos de artículos y recursos de juegos. Importa y exporta CBZ y exporta capítulos completos de galerías a PDF. |
| Listas y búsqueda por imagen | Explora clasificaciones de doujinshi, anime y JAV o busca posibles obras con una imagen. |
| Información de obras | Explora, busca y filtra información de obras, abre los detalles del sitio original de los rankings y elige los sitios de detalles y búsqueda. |
| Comentarios y chat | Lee comentarios, respuestas e imágenes de los sitios compatibles y muestra el chat en directos compatibles. |
| Traducción y filtros | Traduce títulos, nombres de capítulos, descripciones, etiquetas, comentarios, textos, subtítulos de texto y chat en directo; se prioriza el diccionario del idioma actual. Oculta contenido por etiquetas. |
| Privacidad y copias | Bloqueo de la app, modo incógnito, portadas borrosas y bloqueo de capturas donde sea compatible. Copias de favoritos, progreso, suscripciones y ajustes. |

## Sitios y servicios compatibles

[Ver todos los sitios, rankings y servicios de búsqueda inversa de imágenes](SITES.md)

<a id="faq"></a>

## Limitaciones y preguntas

La taberna requiere tu propio servicio de IA compatible con OpenAI. Los mensajes, ajustes del personaje, personaje del usuario y contenido coincidente de los libros se envían al servicio y pueden generar cargos. Consulta [Sitios y servicios](SITES.md) para las reglas e importación y exportación. Los recursos y conversaciones guardados se incluyen en copias sin cifrar; los ajustes de IA y las claves quedan excluidos.

La lectura, reproducción, comentarios, suscripciones y descargas dependen de cada sitio. Consulta las opciones disponibles en la app. Las actualizaciones de sitios pueden exigir actualizar la app.

La búsqueda por imagen envía imágenes al servicio elegido; el historial local no está cifrado. Las contraseñas y cookies son visibles al iniciar sesión manualmente; ten cuidado al compartir pantalla.

**¿No puedes abrir un sitio o contenido?**

Comprueba la conexión y sigue las indicaciones para iniciar sesión, confirmar tu edad o superar la verificación del sitio. En algunas regiones puede ser necesario un VPN o proxy; el sitio original controla el contenido y los permisos. Las comprobaciones de cumpleaños compatibles usan la fecha fija 1999-12-31 solo tras confirmar la mayoría de edad en el dispositivo; no leen tu fecha real.

**¿Puedo enviar comentarios o chat?**

Los comentarios, respuestas y chat son de solo lectura. Si un recurso de juego requiere una respuesta para desbloquearse, se muestra el texto y solo se envía tras tu confirmación.

**¿Cómo guardo favoritos y progreso?**

Exporta o restaura .parkbak en Más → Copia de seguridad. La restauración combina los datos y excluye las descargas. Puedes incluir opcionalmente el estado de acceso y confirmación de los sitios, incluidas las cookies, para usarlo en otro dispositivo. Las sesiones caducadas o vinculadas al dispositivo pueden requerir una nueva verificación. Las copias no están cifradas; guárdalas de forma segura. Las partidas en línea no se incluyen en .parkbak. La importación y exportación del juego solo abarca localStorage, no IndexedDB; los archivos exportados no están cifrados.

**¿Cómo informo de un problema?**

Usa Issues e indica versión, sitio y pasos. Oculta cuentas, cookies, tokens, copias y URL firmadas completas.

[Guía de registros](DIAGNOSTICS.md)

---

[AGPL-3.0 · Licencia](../../../LICENSE) · [Avisos de terceros](../../licenses/README.md) · [Plataformas](../../PLATFORMS.md)
