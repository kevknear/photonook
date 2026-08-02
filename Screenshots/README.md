# Capturas del App Store

Las que se suben a App Store Connect, en el orden en que aparecen en la ficha.

| Archivo | Pantalla | Qué cuenta |
|---|---|---|
| `00-gallery.png` | Cuadrícula de la galería | El diferenciador: empieza por donde quieras y el progreso se guarda por foto |
| `01-deck.png` | Mazo a media decisión | Cómo se usa: swipe para decidir |
| `02-tray.png` | Bandeja «Por borrar» | Borrado por lotes con una sola confirmación |
| `03-explore.png` | Explorador | El alcance: secciones por tipo, app y fecha |
| `04-summary.png` | Resumen de sesión | La recompensa: espacio recuperado |
| `05-settings-dark.png` | Ajustes en oscuro | Acabado y modo oscuro |

Las dos primeras son las que se ven en los resultados de búsqueda del App Store, así que
entre ambas tienen que comunicar la propuesta completa.

## Especificaciones

- **1320 × 2868 px**, que es el iPhone de 6,9 pulgadas. Apple escala sola para el resto
  de tamaños, así que con este juego basta.
- PNG, capturadas del simulador con `xcrun simctl io booted screenshot`.
- **No** uses `⇧⌘4` de macOS: captura a la resolución de tu pantalla y App Store Connect
  las rechaza.

## Cómo rehacerlas

Están en inglés porque es el idioma principal de la ficha. Antes de capturar:

```bash
# barra de estado limpia
xcrun simctl status_bar booted override --time "9:41" --batteryState charged \
  --batteryLevel 100 --cellularBars 4 --wifiBars 3

# biblioteca grande, para que los recuentos sean creíbles
./Scripts/stress-library.sh 12000
```

En Xcode: Edit Scheme → Run → Options → App Language → English.
En la app: apariencia Light y modo de borrado «Al final de la sesión».

Revisa unas 30 fotos antes de capturar, para que la cuadrícula tenga distintivos y la
bandeja contenido.

Al terminar: `xcrun simctl status_bar booted clear`.

## Cuándo hay que rehacerlas

Siempre que cambie la interfaz de alguna de esas seis pantallas. Ha pasado ya varias
veces —al añadir la cuadrícula, al cambiar la tipografía— y es fácil olvidarlo y publicar
capturas que ya no se parecen a la app.
