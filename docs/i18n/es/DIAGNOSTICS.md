# Registros e informes de errores

Los registros normales incluyen fallos, reintentos automáticos, resultados de llamadas a sitios y cambios del ciclo de vida. Actualice o exporte los registros en Ajustes y adjunte los pasos de reproducción a un Issue.

Para problemas difíciles, active debug solo en esta sesión para reproducirlos ahora, o solo en el próximo inicio para registrar el arranque completo. Se mostrará un aviso cuando se active la opción programada. Debug termina al salir y la programación se consume una sola vez.

Los registros persistentes están desactivados por defecto: cada inicio reemplaza los registros recientes. Al activarlos, se añaden registros entre inicios y solo se eliminan los más antiguos al alcanzar 100 MiB. Desactivarlos reemplaza inmediatamente el historial de ejecución. El historial de cierres inesperados independiente no cambia.

Debug añade tiempos de solicitudes, reintentos, caché y estado de reproducción, sin cuentas, cookies, tokens, contenido, rutas locales ni enlaces firmados completos. La página muestra registros recientes; la exportación incluye todos los conservados. El modo anonimizado también oculta hosts y versiones detalladas del sistema. Revise los archivos antes de compartirlos.
