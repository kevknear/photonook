#!/bin/bash
#
# reset-demo.sh — repuebla la galería del simulador con fotos de prueba.
#
#   ./reset-demo.sh              genera 40 imágenes y las mete en Fotos
#   ./reset-demo.sh 120          genera 120
#   ./reset-demo.sh 40 --erase   borra el simulador de cero primero (tarda más)
#
# Requiere: Xcode instalado y un simulador arrancado.

set -euo pipefail

COUNT="${1:-40}"
ERASE=false
for arg in "$@"; do
	[[ "$arg" == "--erase" ]] && ERASE=true
done

OUT_DIR="${TMPDIR:-/tmp}photoswipe-demo"
SWIFT_SRC="$OUT_DIR/GenerateTestPhotos.swift"

# ---------------------------------------------------------------- simulador

if ! xcrun simctl list devices booted | grep -q "Booted"; then
	echo "❌ No hay ningún simulador arrancado."
	echo "   Abre Xcode, elige un iPhone como destino y pulsa ▶︎ (o abre Simulator.app)."
	exit 1
fi

DEVICE_NAME="$(xcrun simctl list devices booted | grep "Booted" | head -1 | sed 's/^ *//;s/ (.*//')"
echo "📱 Simulador: $DEVICE_NAME"

if [[ "$ERASE" == true ]]; then
	echo "🧹 Borrando el simulador por completo…"
	xcrun simctl shutdown booted
	xcrun simctl erase booted 2>/dev/null || xcrun simctl erase all
	xcrun simctl boot booted 2>/dev/null || true
	open -a Simulator
	echo "   Esperando a que arranque…"
	sleep 12
fi

# ---------------------------------------------------------------- generación

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

cat > "$SWIFT_SRC" <<'SWIFT_EOF'
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let count = Int(args.count > 1 ? args[1] : "40") ?? 40
let outDir = args.count > 2 ? args[2] : "/tmp/photoswipe-demo"

// Mezcla de formatos: vertical tipo captura, foto horizontal, foto vertical, cuadrada.
let sizes: [(w: Int, h: Int, label: String)] = [
    (1290, 2796, "captura"),
    (4032, 3024, "foto H"),
    (3024, 4032, "foto V"),
    (1440, 1440, "cuadrada"),
    (2048, 1536, "foto H"),
    (828, 1792, "captura"),
]

/// HSB → RGB sin dependencias.
func rgb(hue: Double, sat: Double, bri: Double) -> (Double, Double, Double) {
    let h = (hue - hue.rounded(.down)) * 6
    let i = Int(h)
    let f = h - Double(i)
    let p = bri * (1 - sat)
    let q = bri * (1 - sat * f)
    let t = bri * (1 - sat * (1 - f))
    switch i % 6 {
    case 0: return (bri, t, p)
    case 1: return (q, bri, p)
    case 2: return (p, bri, t)
    case 3: return (p, q, bri)
    case 4: return (t, p, bri)
    default: return (bri, p, q)
    }
}

/// `.font` y `.foregroundColor` los define AppKit/UIKit, que no están disponibles
/// al ejecutar con `swift` en modo intérprete. Usamos las claves de CoreText.
func makeLine(_ text: String, font: CTFont, color: CGColor) -> CTLine {
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ]
    return CTLineCreateWithAttributedString(
        NSAttributedString(string: text, attributes: attributes)
    )
}

var written = 0

for index in 1...count {
    let spec = sizes[index % sizes.count]
    let w = spec.w, h = spec.h
    let space = CGColorSpaceCreateDeviceRGB()

    guard let ctx = CGContext(
        data: nil, width: w, height: h,
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { continue }

    // Degradado diagonal con un tono distinto por imagen.
    let hue = Double(index) * 0.137
    let (r1, g1, b1) = rgb(hue: hue, sat: 0.65, bri: 0.95)
    let (r2, g2, b2) = rgb(hue: hue + 0.12, sat: 0.85, bri: 0.45)

    let colors = [
        CGColor(colorSpace: space, components: [r1, g1, b1, 1])!,
        CGColor(colorSpace: space, components: [r2, g2, b2, 1])!,
    ] as CFArray

    if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
        ctx.drawLinearGradient(
            gradient,
            start: .zero,
            end: CGPoint(x: w, y: h),
            options: []
        )
    }

    // Número grande centrado, para reconocer cada foto de un vistazo.
    let fontSize = CGFloat(min(w, h)) * 0.42
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
    let line = makeLine(
        "\(index)",
        font: font,
        color: CGColor(colorSpace: space, components: [1, 1, 1, 0.92])!
    )
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    ctx.textPosition = CGPoint(
        x: (CGFloat(w) - bounds.width) / 2 - bounds.minX,
        y: (CGFloat(h) - bounds.height) / 2 - bounds.minY
    )
    CTLineDraw(line, ctx)

    // Etiqueta con el formato, abajo.
    let smallFont = CTFontCreateWithName("Helvetica" as CFString, CGFloat(min(w, h)) * 0.055, nil)
    let subLine = makeLine(
        "\(spec.label) · \(w)×\(h)",
        font: smallFont,
        color: CGColor(colorSpace: space, components: [1, 1, 1, 0.75])!
    )
    let subBounds = CTLineGetBoundsWithOptions(subLine, .useOpticalBounds)
    ctx.textPosition = CGPoint(
        x: (CGFloat(w) - subBounds.width) / 2 - subBounds.minX,
        y: CGFloat(h) * 0.12
    )
    CTLineDraw(subLine, ctx)

    guard let image = ctx.makeImage() else { continue }

    let url = URL(fileURLWithPath: outDir)
        .appendingPathComponent(String(format: "demo-%03d.png", index))
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { continue }

    CGImageDestinationAddImage(dest, image, nil)
    if CGImageDestinationFinalize(dest) { written += 1 }
}

print("\(written)")
SWIFT_EOF

echo "🎨 Generando $COUNT imágenes de prueba…"
GENERATED="$(swift "$SWIFT_SRC" "$COUNT" "$OUT_DIR")"
echo "   $GENERATED archivos en $OUT_DIR"

# ---------------------------------------------------------------- carga

echo "📥 Añadiendo a la app Fotos del simulador…"
# En lotes, por si son muchas.
find "$OUT_DIR" -name "demo-*.png" -print0 \
	| xargs -0 -n 25 xcrun simctl addmedia booted

echo ""
echo "✅ Listo. Abre PhotoNook en el simulador y vuelve a probar."
echo ""
echo "   Nota: simctl no marca las imágenes como capturas de pantalla reales,"
echo "   así que el filtro «Capturas de pantalla» no las verá. Para probar ese"
echo "   filtro, haz capturas de verdad en el simulador con ⌘S."
