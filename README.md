# PhotoNook

> *Your gallery, clean and cozy.*

App de iOS para limpiar la galería del iPhone con gestos tipo Tinder: swipe izquierda = borrar,
swipe derecha = conservar.

Bundle ID `com.kevinknear.photonook` · iOS 17+ · SwiftUI · inglés y español.

## Qué incluye

- **Mazo de cartas** con la foto actual y un vistazo de la siguiente, rotación y sellos
  "DELETE" / "KEEP" durante el arrastre.
- **Contadores**: progreso "X de Y", conservadas, descartadas y espacio recuperado en MB/GB.
- **Deshacer** el último swipe.
- **Cuatro pestañas navegables**: `Explorar` (inicio), `Revisar` (el mazo), `Por borrar`
  (con badge del pendiente) y `Ajustes`.
- **Explorar**: catálogo de la galería en tarjetas con portada y recuento, agrupadas en:
  - *Por tipo* — capturas, vídeos, selfies, ráfagas, Live Photos, panorámicas, retratos,
    cámara lenta, time-lapse, GIFs, favoritas. Salen de los álbumes inteligentes de iOS.
  - *Por app* — WhatsApp, Instagram, Telegram… detectadas por el nombre del álbum que crean.
  - *Mis álbumes* — los que creaste tú.
  - *Reciente / Por año / Por mes* — hoy, esta semana, este mes, cada año y los últimos 12 meses.
- **Bandeja "Por borrar"** (staging): todo lo descartado con swipe izquierda espera en una rejilla.
  Borras el lote entero de golpe con **una única alerta de iOS**. Sobre cada foto tienes tres salidas:
  - **Tocar** para desmarcarla → se queda como conservada (decisión tomada).
  - **Mantener pulsada → Devolver al mazo** → vuelve al final del carrusel, sin decisión. Útil
    cuando no estás seguro y quieres verla otra vez al final.
  - Dejarla marcada → se borra con el lote.

  El botón `Devolver al mazo` de la barra inferior hace lo mismo en bloque con todas las desmarcadas.
- **Tres modos de borrado** (elegibles en Filtros):
  - `Al final de la sesión` (por defecto) — nada se borra hasta que revises la bandeja.
  - `Por lotes` — dispara el borrado automáticamente cada N descartes (ajustable, 5-100).
  - `En cada swipe` — borra al instante, con una alerta del sistema por foto.

> Nada se borra de forma permanente: todo va a **Eliminados recientemente** en la app Fotos, donde permanece 30 días.

### Sobre la alerta de confirmación de iOS

Cada llamada a `PHAssetChangeRequest.deleteAssets` provoca una alerta del sistema
("Allow PhotoNook to delete this photo?"). **No se puede suprimir**: no hay parámetro, entitlement
ni nivel de permiso que la desactive, y no depende de haber concedido acceso completo a la galería.
Es una protección deliberada de iOS para que ninguna app pueda vaciar la galería sin intervención
del usuario. La única palanca disponible es reducir el número de llamadas agrupando las fotos en
un solo `deleteAssets`, que es exactamente lo que hacen los modos por lotes.

## Estructura

```
Sources/
  PhotoNookApp.swift          punto de entrada
  Models/FilterOptions.swift   fuentes, rangos de fecha, orden
  Services/PhotoLibraryService.swift   único punto de contacto con el framework Photos
  ViewModels/SwipeViewModel.swift      estado, undo, contadores, borrado
  Views/
    RootView.swift             enrutado por fase + permisos + resumen
    SwipeDeckView.swift        mazo, gesto de arrastre, barra de botones, háptica
    PhotoCardView.swift        una carta (imagen + metadata)
    StatsBar.swift             progreso y espacio
    FilterView.swift           hoja de filtros y modo de borrado
```

## Abrir y ejecutar

El proyecto ya está montado: `PhotoNook.xcodeproj`. Solo tienes que abrirlo.

```bash
open ~/Documents/SwiftApps/PhotoNook/PhotoNook.xcodeproj
```

Ya viene configurado con deployment target iOS 17.0, el permiso `NSPhotoLibraryUsageDescription`
en `Sources/Info.plist`, bundle ID `com.kev.photoswipe` y un scheme llamado `PhotoNook`.

### En el simulador (rápido, para ver la interfaz)

1. En la barra superior de Xcode, junto al nombre del scheme `PhotoNook`, abre el selector de
   destino y elige cualquier **iPhone 16 / 17** de la lista de simuladores.
2. Pulsa ▶︎ (o `⌘R`).
3. El simulador arranca con la galería casi vacía. **Arrastra imágenes desde el Finder
   directamente a la ventana del simulador** para que se guarden en Fotos y tengas material que
   swipear. Con 15-20 imágenes ya se prueba bien.
4. Acepta el diálogo de permiso de fotos cuando aparezca.

El borrado funciona en el simulador (con su alerta de confirmación incluida), así que puedes
validar el flujo completo antes de tocar tu galería real.

### Recuperar / regenerar fotos de prueba

Si te quedaste sin fotos en el simulador, tienes tres caminos:

**1. Recuperar las que borraste** (lo más rápido — siguen ahí 30 días)
   App Fotos del simulador → Álbumes → Eliminados recientemente → Seleccionar → Recuperar todo.

**2. Generar fotos sintéticas** (lo mejor para probar en serio)

```bash
cd ~/Documents/SwiftApps/PhotoNook
chmod +x Scripts/reset-demo.sh
./Scripts/reset-demo.sh 60
```

Crea 60 imágenes numeradas con formatos variados (vertical tipo captura, horizontal, cuadrada) y
las carga en Fotos con `simctl addmedia`. Al ir numeradas sabes exactamente cuál borraste.
Añade `--erase` para resetear el simulador entero antes.

**3. Arrastrar imágenes** desde el Finder a la ventana del simulador.

> `simctl addmedia` no marca las imágenes con el subtipo `photoScreenshot`, así que el filtro
> «Capturas de pantalla» no las detectará. Para probar ese filtro, haz capturas reales dentro del
> simulador con `⌘S`.

### En tu iPhone (la prueba de verdad)

1. **Firma**: selecciona el proyecto en el navegador → target `PhotoNook` →
   **Signing & Capabilities** → marca *Automatically manage signing* y en *Team* elige tu Apple ID.
   Si no aparece ninguno: Xcode → Settings → Accounts → `+` → añade tu Apple ID (la cuenta gratuita sirve).
2. **Modo desarrollador en el iPhone**: conecta el cable, y en el teléfono ve a
   Ajustes → Privacidad y seguridad → **Modo desarrollador** → activar y reiniciar.
3. Selecciona tu iPhone como destino en Xcode y pulsa ▶︎.
4. La primera vez el iPhone rechazará la app. Ve a
   Ajustes → General → VPN y gestión de dispositivos → tu certificado → **Confiar**.

Con cuenta gratuita la app caduca a los 7 días; basta con volver a ejecutarla desde Xcode.

### Si Xcode se queja

- *"Signing for PhotoNook requires a development team"* → solo aparece al compilar para
  dispositivo físico. Para simulador puedes ignorarlo; para iPhone, haz el paso 1 de arriba.
- *"Cannot find 'X' in scope"* → algún archivo no está en el target. Selecciónalo en el navegador
  y comprueba en el inspector de la derecha que `PhotoNook` está marcado en *Target Membership*.
- Errores de concurrencia (`Sendable`) → ve a build settings del target y confirma que
  **Swift Language Version** es **5**, no 6.

## Firma (identidad de desarrollador)

El `DEVELOPMENT_TEAM` no está en el `.xcodeproj`: vive en `Config/Local.xcconfig`, que está
en `.gitignore` y por tanto nunca se sube al repositorio.

Si clonas el proyecto en otro Mac, crea ese archivo con tu propio Team ID:

```
DEVELOPMENT_TEAM = XXXXXXXXXX
```

Lo encuentras en Xcode → Settings → Accounts → tu Apple ID (entre paréntesis), o en
developer.apple.com → Membership.

Sin ese archivo el proyecto compila igualmente para el **simulador**; solo hace falta para
firmar en un dispositivo físico o para archivar. `Config/Shared.xcconfig` lo incluye con
`#include?`, una inclusión opcional que no falla si el archivo no existe.

> **Importante:** si cambias el equipo desde Xcode → Signing & Capabilities, Xcode volverá a
> escribir `DEVELOPMENT_TEAM` dentro del `.xcodeproj`. Si pasa, bórralo de ahí y ponlo en
> `Local.xcconfig`, o acabará en el repositorio.

## Idiomas

Inglés (base) y español, con String Catalogs. iOS elige según el ajuste del teléfono.

- `Sources/Localizable.xcstrings` — la interfaz. El idioma fuente es el inglés: las claves son
  el propio texto en inglés, y el español va como traducción.
- `Sources/InfoPlist.xcstrings` — el nombre visible y el texto del permiso de Fotos.

Para añadir un idioma, abre el catálogo en Xcode y pulsa `+` junto a la lista de idiomas; Xcode
extrae las claves del código automáticamente en cada compilación.

Dos reglas al tocar el código:

- `Text("literal")` se localiza solo. `Text(variable)` **no**: usa `String(localized: "…")` al
  construir esa variable.
- En un ternario dentro de `Text`/`Button`, envuelve cada rama en `String(localized:)`. Con dos
  literales sueltos, Swift puede elegir la sobrecarga que no localiza.

## Publicar en el App Store

Requiere el Apple Developer Program ($99/año). Lo que ya está preparado en el repo:

- **Icono** — `Scripts/make-icon.sh` genera `Sources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`
  (1024×1024, sin transparencia). Ejecútalo una vez:

  ```bash
  chmod +x Scripts/make-icon.sh
  ./Scripts/make-icon.sh
  ```

  La paleta está en las llamadas a `color(0x…)` dentro del script; retoca y vuelve a ejecutar.

- **Privacy manifest** — `Sources/PrivacyInfo.xcprivacy`, ya incluido en la fase de recursos.
  Declara `NSPrivacyAccessedAPICategoryUserDefaults` con motivo `CA92.1`, obligatorio porque
  `@AppStorage` usa `UserDefaults`, que está en la lista de *Required Reason APIs* de Apple.

- **Política de privacidad** — borrador en `PRIVACY.md`. Hay que publicarlo en una URL pública
  (GitHub Pages, Notion o similar) y poner esa dirección en App Store Connect.

Falta por hacer fuera del repo: registrar el Bundle ID, crear la ficha en App Store Connect
(nombre, descripción, palabras clave, categoría Utilidades, clasificación por edad), subir
entre 2 y 8 capturas por tamaño de dispositivo tomadas de pantallas reales, rellenar las
App Privacy Labels como *Data Not Collected*, y hacer Archive → Distribute App desde Xcode.

Desde el 28 de abril de 2026 hay que compilar con el SDK de iOS 26 o superior, es decir
Xcode 26 o superior.

## Notas técnicas

- Swift 6 / concurrencia estricta: `PHAsset` no es `Sendable`, así que el fetch se hace en el `MainActor` y los cálculos de tamaño (que sí son lentos) cruzan a background pasando solo `localIdentifier` como `String`.
- El tamaño en disco se obtiene con `PHAssetResource.value(forKey: "fileSize")`. Es la vía habitual y aceptada en la App Store, pero es lenta: se calcula en segundo plano y los MB aparecen progresivamente.
- `PHCachingImageManager` precarga las 6 fotos siguientes para que el mazo no parpadee.
- Cada llamada a `PHAssetChangeRequest.deleteAssets` genera una alerta del sistema. No hay forma de suprimirla: es por diseño de iOS. De ahí el modo por lotes.

## Ideas para v2

- Modo "carpetas": mover a un álbum en vez de borrar (swipe arriba).
- Detección de duplicados / fotos casi idénticas con `PHAsset` + hashing perceptual.
- Sesiones reanudables guardando los `localIdentifier` ya revisados.
