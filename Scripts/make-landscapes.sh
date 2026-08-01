#!/bin/bash
#
# make-landscapes.sh — genera paisajes sintéticos y los mete en el simulador.
#
#   ./Scripts/make-landscapes.sh          30 imágenes
#   ./Scripts/make-landscapes.sh 60       60 imágenes
#
# Son ilustraciones, no fotos: sirven para probar la app con material variado y
# agradable a la vista. Para las capturas del App Store usa fotos reales.
#
# Requiere Xcode y un simulador arrancado. No instala nada.

set -euo pipefail

COUNT="${1:-30}"
OUT_DIR="${TMPDIR:-/tmp}photonook-landscapes"
SRC="$OUT_DIR/MakeLandscapes.swift"

if ! xcrun simctl list devices booted | grep -q "Booted"; then
	echo "❌ No hay ningún simulador arrancado."
	exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

cat > "$SRC" <<'SWIFT_EOF'
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let count = Int(CommandLine.arguments.dropFirst().first ?? "30") ?? 30
let outDir = CommandLine.arguments.dropFirst(2).first ?? "/tmp/photonook-landscapes"
let space = CGColorSpaceCreateDeviceRGB()

// --- Fechas ---------------------------------------------------------------
// Photos lee la fecha EXIF al importar, así que repartiendo las imágenes por
// los últimos años conseguimos que el explorador tenga secciones de verdad:
// «Hoy», «Esta semana», «Este mes» y un desglose por año y por mes.
let exifFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy:MM:dd HH:mm:ss"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

/// Antigüedad mínima de las imágenes generadas, en días.
///
/// Deliberadamente por encima de un mes: así «Hoy», «Esta semana» y «Este mes»
/// —y la portada de «All Photos», que es siempre la foto más reciente— se
/// quedan para las fotos reales que hayas importado, que son las bonitas.
/// Las sintéticas solo rellenan el desglose por año y por mes.
let minDaysAgo: Double = 45

/// Reparto sesgado hacia lo reciente dentro del tramo antiguo, como una
/// galería de verdad: bastantes del último año y una cola hacia los siete.
func captureDate(for index: Int) -> Date {
    // pow(x, 1.8) concentra los valores cerca de cero.
    let daysAgo = pow(Double.random(in: 0...1), 1.8) * 2510 + minDaysAgo
    let seconds = daysAgo * 86_400 + Double.random(in: 0...86_400)
    return Date().addingTimeInterval(-seconds)
}

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [
        CGFloat((hex >> 16) & 0xFF) / 255,
        CGFloat((hex >> 8) & 0xFF) / 255,
        CGFloat(hex & 0xFF) / 255,
        alpha,
    ])!
}

/// Cada paleta: cielo (arriba, abajo), disco solar, y tono base de las crestas.
struct Palette {
    let skyTop: UInt32, skyBottom: UInt32
    let sun: UInt32
    let ridgeFar: UInt32, ridgeNear: UInt32
    let water: UInt32
}

let palettes: [Palette] = [
    // Amanecer
    .init(skyTop: 0x2E4A6B, skyBottom: 0xF2B888, sun: 0xFFD9A0,
          ridgeFar: 0x8FA3B8, ridgeNear: 0x2B3A4A, water: 0xC98F63),
    // Mediodía
    .init(skyTop: 0x4A90D9, skyBottom: 0xBFE3F5, sun: 0xFFF6D8,
          ridgeFar: 0xA9C4D4, ridgeNear: 0x3E5C4B, water: 0x6FA8C9),
    // Atardecer
    .init(skyTop: 0x4B2D5E, skyBottom: 0xE8825A, sun: 0xFFC46B,
          ridgeFar: 0x8A6A82, ridgeNear: 0x2A1E33, water: 0xB05F4A),
    // Bosque brumoso
    .init(skyTop: 0xBBD3C6, skyBottom: 0xE9F0E4, sun: 0xFFFFFF,
          ridgeFar: 0x9BB5A6, ridgeNear: 0x2F4438, water: 0x86A894),
    // Noche
    .init(skyTop: 0x0E1A33, skyBottom: 0x35507A, sun: 0xE8EEF7,
          ridgeFar: 0x445E85, ridgeNear: 0x0B1220, water: 0x1B2E4F),
]

let sizes: [(Int, Int)] = [
    (4032, 3024), (3024, 4032), (2400, 2400), (4032, 3024), (1290, 2796),
]

/// Mezcla dos colores. Se usa para la perspectiva atmosférica: las crestas
/// lejanas tiran hacia el color del cielo, las cercanas hacia el tono oscuro.
func blend(_ a: UInt32, _ b: UInt32, _ t: CGFloat) -> CGColor {
    func ch(_ v: UInt32, _ s: UInt32) -> CGFloat {
        let x = CGFloat((v >> s) & 0xFF), y = CGFloat((b >> s) & 0xFF)
        return (x + (y - x) * t) / 255
    }
    return CGColor(colorSpace: space, components: [ch(a,16), ch(a,8), ch(a,0), 1])!
}

var written = 0

for index in 0..<count {
    var rng = SystemRandomNumberGenerator()
    let (w, h) = sizes[index % sizes.count]
    let palette = palettes[index % palettes.count]
    let W = CGFloat(w), H = CGFloat(h)

    guard let ctx = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { continue }

    // --- Cielo
    if let g = CGGradient(colorsSpace: space,
                          colors: [rgb(palette.skyBottom), rgb(palette.skyTop)] as CFArray,
                          locations: [0, 1]) {
        ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: H), options: [])
    }

    // --- Sol o luna
    let horizon = H * CGFloat.random(in: 0.34...0.46, using: &rng)
    let sunR = min(W, H) * CGFloat.random(in: 0.055...0.10, using: &rng)
    let sunX = W * CGFloat.random(in: 0.2...0.8, using: &rng)
    let sunY = horizon + H * CGFloat.random(in: 0.06...0.24, using: &rng)
    ctx.setFillColor(rgb(palette.sun, 0.25))
    ctx.fillEllipse(in: CGRect(x: sunX - sunR * 2, y: sunY - sunR * 2,
                               width: sunR * 4, height: sunR * 4))
    ctx.setFillColor(rgb(palette.sun))
    ctx.fillEllipse(in: CGRect(x: sunX - sunR, y: sunY - sunR,
                               width: sunR * 2, height: sunR * 2))

    // --- Agua: banda inferior con el reflejo del sol
    let hasWater = Bool.random(using: &rng)
    let waterTop = hasWater ? horizon * CGFloat.random(in: 0.45...0.7, using: &rng) : 0
    if hasWater {
        if let g = CGGradient(colorsSpace: space,
                              colors: [blend(palette.water, palette.skyTop, 0.45),
                                       rgb(palette.water)] as CFArray,
                              locations: [0, 1]) {
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: 0, width: W, height: waterTop))
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: waterTop), options: [])
            ctx.restoreGState()
        }
        ctx.setFillColor(rgb(palette.sun, 0.22))
        ctx.fill(CGRect(x: sunX - sunR * 0.7, y: 0, width: sunR * 1.4, height: waterTop))
    }

    // --- Crestas: varias capas, de lejana y clara a cercana y oscura
    let layers = Int.random(in: 3...5, using: &rng)
    for layer in 0..<layers {
        let t = CGFloat(layer) / CGFloat(max(1, layers - 1))
        let base = horizon - (horizon - waterTop) * t * CGFloat.random(in: 0.55...0.95, using: &rng)
        let amplitude = H * (0.10 - 0.014 * CGFloat(layer)) * CGFloat.random(in: 0.7...1.3, using: &rng)

        // Suma de senos con fases aleatorias: colinas suaves y nunca iguales.
        let f1 = CGFloat.random(in: 1.2...2.6, using: &rng)
        let f2 = CGFloat.random(in: 3.0...6.0, using: &rng)
        let p1 = CGFloat.random(in: 0...6.28, using: &rng)
        let p2 = CGFloat.random(in: 0...6.28, using: &rng)

        ctx.beginPath()
        ctx.move(to: CGPoint(x: 0, y: 0))
        var x: CGFloat = 0
        while x <= W {
            let u = x / W
            let y = base
                + sin(u * f1 * .pi + p1) * amplitude
                + sin(u * f2 * .pi + p2) * amplitude * 0.35
            ctx.addLine(to: CGPoint(x: x, y: y))
            x += 6
        }
        ctx.addLine(to: CGPoint(x: W, y: 0))
        ctx.closePath()
        ctx.setFillColor(blend(palette.ridgeFar, palette.ridgeNear, t))
        ctx.fillPath()
    }

    // --- Grano suave, para que no se vea plano como un vector
    for _ in 0..<Int(W * H / 9000) {
        ctx.setFillColor(rgb(0xFFFFFF, CGFloat.random(in: 0.01...0.05, using: &rng)))
        let s = CGFloat.random(in: 1...3, using: &rng)
        ctx.fill(CGRect(x: CGFloat.random(in: 0...W, using: &rng),
                        y: CGFloat.random(in: 0...H, using: &rng),
                        width: s, height: s))
    }

    guard let image = ctx.makeImage() else { continue }

    // JPEG en vez de PNG: el PNG no lleva EXIF, y sin EXIF Photos le pone
    // la fecha de importación a todo y el explorador se queda sin secciones.
    let url = URL(fileURLWithPath: outDir)
        .appendingPathComponent(String(format: "landscape-%03d.jpg", index + 1))
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
    ) else { continue }

    let stamp = exifFormatter.string(from: captureDate(for: index))
    let properties: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: 0.86,
        kCGImagePropertyExifDictionary: [
            kCGImagePropertyExifDateTimeOriginal: stamp,
            kCGImagePropertyExifDateTimeDigitized: stamp,
        ],
        kCGImagePropertyTIFFDictionary: [
            kCGImagePropertyTIFFDateTime: stamp,
        ],
    ]

    CGImageDestinationAddImage(dest, image, properties as CFDictionary)
    if CGImageDestinationFinalize(dest) { written += 1 }
}

print(written)
SWIFT_EOF

echo "🏔  Generando $COUNT paisajes…"
GENERATED="$(swift "$SRC" "$COUNT" "$OUT_DIR")"
echo "   $GENERATED imágenes"

echo "📥 Añadiendo a Fotos del simulador…"
find "$OUT_DIR" -name "landscape-*.jpg" -print0 | xargs -0 -n 20 xcrun simctl addmedia booted

echo ""
echo "✅ Listo. Las fechas van repartidas entre hace 45 días y hace unos 7 años,"
echo "   así que el explorador tendrá secciones por año y por mes con contenido."
echo ""
echo "   Nada generado cae en «Hoy», «Esta semana» ni «Este mes»: esas secciones"
echo "   y la portada de «All Photos» quedan para tus fotos reales importadas."
