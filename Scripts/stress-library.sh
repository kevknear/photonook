#!/bin/bash
#
# stress-library.sh — llena el simulador con MUCHAS fotos para probar rendimiento.
#
#   ./Scripts/stress-library.sh            3000 fotos (recomendado para empezar)
#   ./Scripts/stress-library.sh 12000      12000 fotos
#   ./Scripts/stress-library.sh 12000 --erase   borra la galería antes
#
# A diferencia de make-landscapes.sh, aquí las imágenes son pequeñas (720 px de
# lado mayor, JPEG al 55%) porque lo que se prueba es el volumen, no la calidad:
# 12.000 a resolución completa serían ~20 GB y horas de trabajo.
#
# Rinde unos 25-40 KB por imagen, así que 12.000 ≈ 400 MB.

set -euo pipefail

COUNT="${1:-3000}"
ERASE=false
for arg in "$@"; do [[ "$arg" == "--erase" ]] && ERASE=true; done

OUT_DIR="${TMPDIR:-/tmp}photonook-stress"
SRC="$OUT_DIR/StressLibrary.swift"

if ! xcrun simctl list devices booted | grep -q "Booted"; then
	echo "❌ No hay ningún simulador arrancado."
	exit 1
fi

if [[ "$ERASE" == true ]]; then
	echo "🧹 Borrando el simulador…"
	xcrun simctl shutdown booted
	xcrun simctl erase booted
	xcrun simctl boot booted
	open -a Simulator
	echo "   Esperando a que arranque…"
	sleep 12
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

cat > "$SRC" <<'SWIFT_EOF'
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let count = Int(CommandLine.arguments.dropFirst().first ?? "3000") ?? 3000
let outDir = CommandLine.arguments.dropFirst(2).first ?? "/tmp/photonook-stress"
let space = CGColorSpaceCreateDeviceRGB()

func color(_ hex: UInt32) -> CGColor {
    CGColor(colorSpace: space, components: [
        CGFloat((hex >> 16) & 0xFF) / 255,
        CGFloat((hex >> 8) & 0xFF) / 255,
        CGFloat(hex & 0xFF) / 255, 1,
    ])!
}

// Paletas variadas para que la cuadrícula no se vea monótona al desplazarse.
let skies: [(UInt32, UInt32, UInt32, UInt32)] = [
    (0x2E4A6B, 0xF2B888, 0xFFD9A0, 0x2B3A4A),   // amanecer
    (0x4A90D9, 0xBFE3F5, 0xFFF6D8, 0x3E5C4B),   // mediodía
    (0x4B2D5E, 0xE8825A, 0xFFC46B, 0x2A1E33),   // atardecer
    (0xBBD3C6, 0xE9F0E4, 0xFFFFFF, 0x2F4438),   // bruma
    (0x0E1A33, 0x35507A, 0xE8EEF7, 0x0B1220),   // noche
    (0x7B4B2A, 0xE0A46B, 0xFFE0A8, 0x3A2418),   // desierto
]

// Tamaños pequeños: el objetivo es el volumen, no el detalle.
let sizes: [(Int, Int)] = [(720, 540), (540, 720), (600, 600), (720, 405)]

let exif: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy:MM:dd HH:mm:ss"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

/// Reparto sesgado hacia lo reciente, con un mínimo de 45 días para no pisar
/// las secciones «Hoy», «Esta semana» y «Este mes».
func captureDate() -> Date {
    let days = pow(Double.random(in: 0...1), 1.8) * 2900 + 45
    return Date().addingTimeInterval(-(days * 86_400 + Double.random(in: 0...86_400)))
}

var written = 0
let reportEvery = max(1, count / 20)

for index in 0..<count {
    let (w, h) = sizes[index % sizes.count]
    let (skyTop, skyBottom, sun, ridge) = skies[index % skies.count]
    let W = CGFloat(w), H = CGFloat(h)

    guard let ctx = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { continue }

    // Cielo
    if let g = CGGradient(colorsSpace: space,
                          colors: [color(skyBottom), color(skyTop)] as CFArray,
                          locations: [0, 1]) {
        ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: H), options: [])
    }

    // Sol o luna, en posición variable
    let r = min(W, H) * CGFloat.random(in: 0.06...0.12)
    let sx = W * CGFloat.random(in: 0.15...0.85)
    let sy = H * CGFloat.random(in: 0.55...0.85)
    ctx.setFillColor(color(sun))
    ctx.fillEllipse(in: CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2))

    // Dos crestas: suficiente variedad sin coste. Sin grano ni capas extra,
    // que es lo que dispara el tiempo cuando son miles de imágenes.
    for layer in 0..<2 {
        let base = H * CGFloat.random(in: 0.22...0.42) - CGFloat(layer) * H * 0.06
        let amp = H * CGFloat.random(in: 0.05...0.14)
        let freq = CGFloat.random(in: 1.5...4.0)
        let phase = CGFloat.random(in: 0...6.28)

        ctx.beginPath()
        ctx.move(to: .zero)
        var x: CGFloat = 0
        while x <= W {
            ctx.addLine(to: CGPoint(x: x, y: base + sin(x / W * freq * .pi + phase) * amp))
            x += 10
        }
        ctx.addLine(to: CGPoint(x: W, y: 0))
        ctx.closePath()
        ctx.setFillColor(color(layer == 0 ? skyTop : ridge))
        ctx.fillPath()
    }

    guard let image = ctx.makeImage() else { continue }

    let url = URL(fileURLWithPath: outDir)
        .appendingPathComponent(String(format: "stress-%05d.jpg", index + 1))
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
    ) else { continue }

    let stamp = exif.string(from: captureDate())
    CGImageDestinationAddImage(dest, image, [
        kCGImageDestinationLossyCompressionQuality: 0.55,
        kCGImagePropertyExifDictionary: [
            kCGImagePropertyExifDateTimeOriginal: stamp,
            kCGImagePropertyExifDateTimeDigitized: stamp,
        ],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFDateTime: stamp],
    ] as CFDictionary)

    if CGImageDestinationFinalize(dest) { written += 1 }

    if (index + 1) % reportEvery == 0 {
        FileHandle.standardError.write(Data("   generadas \(index + 1)/\(count)\n".utf8))
    }
}

print(written)
SWIFT_EOF

echo "🖼  Generando $COUNT imágenes pequeñas…"
GENERATED="$(swift "$SRC" "$COUNT" "$OUT_DIR")"
TOTAL_SIZE="$(du -sh "$OUT_DIR" | cut -f1)"
echo "   $GENERATED archivos · $TOTAL_SIZE en disco"

echo ""
echo "📥 Importando a Fotos. Esta es la parte lenta —cuenta con varios minutos"
echo "   si son miles— porque Photos indexa cada archivo."

TOTAL=0
find "$OUT_DIR" -name "stress-*.jpg" -print0 | xargs -0 -n 100 sh -c '
	xcrun simctl addmedia booted "$@" 2>/dev/null
	echo -n "."
' _
echo ""

echo ""
echo "✅ Listo. Abre PhotoNook y entra en una sección grande."
echo ""
echo "   Qué mirar:"
echo "   · que la cuadrícula se desplace fluida y sin huecos en blanco"
echo "   · que Explorar tarde poco en calcular las secciones"
echo "   · que tocar una foto del final entre al mazo sin retraso"
echo "   · el consumo de memoria en el Debug Navigator de Xcode"
