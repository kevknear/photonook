#!/bin/bash
#
# make-icon.sh — genera el icono de la app (1024×1024, sin transparencia).
#
#   ./Scripts/make-icon.sh
#
# Escribe directamente en Sources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
# Requiere Xcode (usa `swift` en modo intérprete). No instala nada.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/Sources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
SRC="${TMPDIR:-/tmp}MakeIcon.swift"

mkdir -p "$(dirname "$OUT")"

cat > "$SRC" <<'SWIFT_EOF'
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let side = 1024
let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "icon-1024.png"

let space = CGColorSpaceCreateDeviceRGB()

// `noneSkipLast` => sin canal alfa. El icono del App Store no admite transparencia.
guard let ctx = CGContext(
    data: nil, width: side, height: side,
    bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    FileHandle.standardError.write(Data("No se pudo crear el contexto gráfico.\n".utf8))
    exit(1)
}

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: space,
        components: [
            CGFloat((hex >> 16) & 0xFF) / 255,
            CGFloat((hex >> 8) & 0xFF) / 255,
            CGFloat(hex & 0xFF) / 255,
            alpha,
        ]
    )!
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

let full = CGFloat(side)
let center = CGPoint(x: full / 2, y: full / 2)

// ---------------------------------------------------------------- fondo

if let gradient = CGGradient(
    colorsSpace: space,
    colors: [color(0xEDA871), color(0xBE6236)] as CFArray,
    locations: [0, 1]
) {
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: full),
        end: CGPoint(x: full, y: 0),
        options: []
    )
}

// ------------------------------------------------------- tarjetas apiladas

/// Dibuja una tarjeta de papel rotada sobre el centro del lienzo.
func drawCard(
    rect: CGRect,
    radius: CGFloat,
    rotation: CGFloat,
    fill: CGColor,
    scene: ((CGRect) -> Void)? = nil
) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: rotation)
    ctx.translateBy(x: -center.x, y: -center.y)

    ctx.setShadow(
        offset: CGSize(width: 0, height: -16),
        blur: 40,
        color: color(0x5A3418, alpha: 0.32)
    )
    ctx.addPath(rounded(rect, radius))
    ctx.setFillColor(fill)
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    if let scene {
        ctx.saveGState()
        ctx.addPath(rounded(rect, radius))
        ctx.clip()
        scene(rect)
        ctx.restoreGState()
    }

    ctx.restoreGState()
}

// Tarjeta de atrás: solo asoma, da sensación de mazo.
drawCard(
    rect: CGRect(x: 292, y: 300, width: 440, height: 440),
    radius: 78,
    rotation: 0.155,
    fill: color(0xF0DFC2)
)

// Tarjeta de delante: lleva la escena.
drawCard(
    rect: CGRect(x: 272, y: 262, width: 480, height: 480),
    radius: 86,
    rotation: -0.085,
    fill: color(0xFFFAF1)
) { rect in
    // Sol
    ctx.setFillColor(color(0xE9B45F))
    ctx.fillEllipse(in: CGRect(
        x: rect.maxX - 178, y: rect.maxY - 178,
        width: 108, height: 108
    ))

    // Montaña de atrás (salvia)
    ctx.setFillColor(color(0x8DA37C))
    ctx.move(to: CGPoint(x: rect.minX - 40, y: rect.minY))
    ctx.addLine(to: CGPoint(x: rect.minX + 168, y: rect.minY + 286))
    ctx.addLine(to: CGPoint(x: rect.minX + 352, y: rect.minY))
    ctx.closePath()
    ctx.fillPath()

    // Montaña de delante (terracota)
    ctx.setFillColor(color(0xC4703F))
    ctx.move(to: CGPoint(x: rect.minX + 176, y: rect.minY))
    ctx.addLine(to: CGPoint(x: rect.minX + 330, y: rect.minY + 214))
    ctx.addLine(to: CGPoint(x: rect.maxX + 40, y: rect.minY))
    ctx.closePath()
    ctx.fillPath()

    // Suelo: una banda que asienta la composición.
    ctx.setFillColor(color(0x6F8563))
    ctx.fill(CGRect(x: rect.minX - 40, y: rect.minY - 40, width: rect.width + 80, height: 84))
}

// ---------------------------------------------------------------- guardar

guard let image = ctx.makeImage() else {
    FileHandle.standardError.write(Data("No se pudo renderizar la imagen.\n".utf8))
    exit(1)
}

let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(
    url as CFURL, UTType.png.identifier as CFString, 1, nil
) else {
    FileHandle.standardError.write(Data("No se pudo crear el archivo de destino.\n".utf8))
    exit(1)
}

CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write(Data("No se pudo escribir el PNG.\n".utf8))
    exit(1)
}

print("OK")
SWIFT_EOF

echo "🎨 Generando el icono…"
swift "$SRC" "$OUT" > /dev/null
echo "✅ Icono escrito en:"
echo "   $OUT"
echo ""
echo "   Ábrelo para verlo. Si quieres retocar colores o formas, edita este script"
echo "   (la paleta está en las llamadas a color(0x…)) y vuelve a ejecutarlo."
