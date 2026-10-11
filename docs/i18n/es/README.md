[简体中文](../../../README.md) · [繁體中文](../zh-Hant/README.md) · [日本語](../ja/README.md) · [한국어](../ko/README.md) · [English](../en/README.md) · [Español](README.md) · [Русский](../ru/README.md) · [العربية](../ar/README.md)

<p align="center">
  <img src="../../images/banner.svg" alt="HentaiPark" width="100%">
</p>

<div align="center">

[![Release](https://img.shields.io/github/v/release/drdon1234/Hentai-Park?label=Descargar)](https://github.com/drdon1234/Hentai-Park/releases/latest)
![Android](https://img.shields.io/badge/Android-7.0%2B-3DDC84?logo=android&logoColor=white)
![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)

</div>

> [!WARNING]
> Esta aplicación incluye contenido para adultos y solo puede ser utilizada por adultos dentro del alcance permitido por las leyes locales. Todo el contenido proviene de sitios de terceros y la aplicación en sí no almacena ni ofrece ningún contenido.

## Captura de pantalla

<p align="center">
  <img src="../../screenshots/home.jpg" width="24%">
  <img src="../../screenshots/multi_language_search.jpg" width="24%">
  <img src="../../screenshots/continue_reading.jpg" width="24%">
  <img src="../../screenshots/blocklist_presets.jpg" width="24%">
</p>

## Sitios de origen compatibles

| Sitio de origen | Tipo | Descripción |
|------|------|------|
| E-Hentai / ExHentai | Cómics | Puede cambiar de sitio después de iniciar sesión en la página web |
| nhentai | Cómics | |
| JMComic | Cómics | Abrir por ID de obra y cambiar automáticamente de servidor API |
| WNACG (绅士漫画) | Cómics | Lectura sin cuenta, capítulos de colecciones y cambio automático de servidor |
| PicACG | Cómics | Configure su propia cuenta o registre automáticamente una cuenta dedicada después de la confirmación |
| Hanime1 | Vídeo | El uso por primera vez puede requerir verificación Cloudflare |
| MissAV | Vídeo | Reproducción con distintas calidades y descarga sin conexión en Android |

El sitio de origen se carga como un complemento y se pueden agregar fuentes de terceros en la configuración. Las fuentes oficiales admiten actualizaciones automáticas; también puedes buscar actualizaciones manualmente en «Administrar fuentes».

## Función

- **Búsqueda de agregación**: busca en todos los sitios de origen a la vez; pegue el enlace o ingrese el ID de obra (como `JM350234`) para abrir directamente el trabajo
- **Búsqueda en varios idiomas**: traduce automáticamente palabras clave al chino/japonés/coreano/inglés y otros idiomas para búsqueda simultánea
- **Estantería y actualizaciones**: colección de múltiples categorías, busca automáticamente actualizaciones en serie y envía notificaciones automáticas, y puede descargar automáticamente nuevos capítulos.
- **Lector**: desplazamiento vertical, lectura de izquierda a derecha o de derecha a izquierda, doble página, recorte de márgenes blancos, filtro de descanso visual y cambio de página con las teclas de volumen
- **Reproducción de vídeo**: selección de calidad y velocidad, y posición de reproducción guardada. Deslice verticalmente a la izquierda para ajustar el brillo y a la derecha para el volumen; arrastre en horizontal para cambiar la posición. Admite pantalla completa vertical y horizontal, también con el dispositivo invertido.
- **Descargar**: descarga cómics por capítulo, descarga vídeos por calidad; admite importación y exportación CBZ
- **Migración de cambio de fuente**: migre colecciones a otra fuente y conserve el progreso de lectura
- **Etiquetas de bloqueo**: personalice el bloqueo y proporcione agrupaciones preestablecidas que se pueden habilitar a pedido
- **Protección de privacidad**: bloqueo de aplicaciones, modo incógnito, desenfoque de portada, anti-captura de pantalla
- **Copia de seguridad y recuperación**: copia de seguridad con un solo clic de la biblioteca, el progreso y la configuración, admite copias de seguridad automáticas programadas
- **Interfaz en ocho idiomas**: chino simplificado, chino tradicional, japonés, coreano, inglés, español, ruso, árabe; admite seguir el sistema y cambiar instantáneamente, el árabe adopta un diseño de derecha a izquierda

## Descargar

Vaya a [Releases](https://github.com/drdon1234/Hentai-Park/releases/latest) para descargar la última versión. Cuando no esté seguro de cuál elegir, elija la versión `arm64-v8a` para la mayoría de los teléfonos.

## Empezar

1. Seleccione el sitio de origen en "Explorar" o use la barra de búsqueda para buscar el trabajo, pegue el enlace al trabajo e ingrese el ID de obra. La búsqueda multilingüe conserva las palabras clave originales y los idiomas de origen detectados, al tiempo que muestra las palabras clave traducidas.
2. Seleccione el idioma en "Más → Idioma → Idioma de la aplicación". Siga el sistema por defecto; las modificaciones entrarán en vigor inmediatamente y se guardarán localmente, sin afectar el título original, las etiquetas o los datos de usuario guardados de la obra.
3. Habilite, ordene y configure los sitios de origen en "Más → Administrar fuentes". PicACG Cuando la cuenta no esté configurada, "Explorar" mostrará un mensaje y podrá configurar su propia cuenta o habilitar una cuenta de mantenimiento automático dedicada.
4. Al activar PicACG "Usar cuenta de mantenimiento automático dedicada", aparecerá una confirmación de registro. Después de la confirmación, cree una cuenta dedicada e inicie sesión inmediatamente. La aplicación mantendrá el estado de inicio de sesión posterior. Al apagar el interruptor se conservará la cuenta dedicada; volver a encenderlo se puede reutilizar y las cuentas manuales existentes no se sobrescribirán. Si el registro falla, puedes volver a intentarlo con la misma cuenta.
5. En la página de detalles del cómic, puedes recopilar, seleccionar categorías y descargar capítulos; "Libro" organiza colecciones, "Actualizar" comprueba nuevos capítulos y "Historial" y continúa leyendo restaura el progreso. "Más → Copia de seguridad y recuperación" puede exportar datos y fusionarlos con los datos actuales durante la restauración.

Desliza hacia arriba y hacia abajo en el lado izquierdo de la página del video para ajustar el brillo, deslízate hacia arriba y hacia abajo en el lado derecho para ajustar el volumen, deslízate horizontalmente para obtener una vista previa del progreso y salta después de soltarlo. El control de reproducción proporciona expansión horizontal y vertical de la pantalla, y el área de operación se ajusta con la dirección de la pantalla cuando se gira la pantalla. El lector admite desplazamiento hacia arriba y hacia abajo, pasar páginas de izquierda a derecha o de derecha a izquierda, y la dirección de lectura está determinada por la configuración del lector.

## Preguntas frecuentes

**¿PicACG/ExHentai no se puede utilizar?**
PicACG necesita configurar la cuenta por sí mismo o confirmar el registro de una cuenta de mantenimiento automático dedicada; ExHentai requiere inicio de sesión web y la cuenta en sí debe tener permisos de sitio.

**¿Las imágenes se cargan lentamente o fallan?**
Puede configurar el proxy HTTP en la configuración; JMComic/PicACG puede intentar cambiar el servidor de imágenes.

**Hanime1 ¿Sigues dando vueltas en círculos?**
Siga las instrucciones para completar la verificación Cloudflare en el navegador integrado.

## Desarrollo

```bash
flutter pub get
flutter build apk --release --split-per-abi
```

Para escribir un complemento fuente para un sitio nuevo, consulte [Guía de desarrollo de complementos de fuentes](SOURCE_API.md). La versión del complemento fuente incorporado comienza en `0.0.1`; la versión de la aplicación y la versión del complemento se administran por separado.
