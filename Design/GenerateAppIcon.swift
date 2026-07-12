import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

func deg(_ d: Double) -> CGFloat { CGFloat(d) * .pi / 180 }

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255, alpha: a)
}

// A continuous-corner (squircle-ish) rounded rect, close to Apple's macOS grid.
func squirclePath(rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func annularSector(center: CGPoint, inner: CGFloat, outer: CGFloat,
                   startDeg: Double, sweepDeg: Double) -> CGPath {
    let path = CGMutablePath()
    let a0 = deg(startDeg)
    let a1 = deg(startDeg - sweepDeg) // clockwise
    path.addArc(center: center, radius: outer, startAngle: a0, endAngle: a1, clockwise: true)
    path.addArc(center: center, radius: inner, startAngle: a1, endAngle: a0, clockwise: false)
    path.closeSubpath()
    return path
}

func drawIcon(size S: CGFloat) -> CGImage {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)

    // Body squircle (macOS grid: ~80% of canvas, leaving room for the shadow).
    let margin = S * 0.096
    let bodyRect = CGRect(x: margin, y: margin, width: S - 2 * margin, height: S - 2 * margin)
    let corner = bodyRect.width * 0.2237
    let body = squirclePath(rect: bodyRect, radius: corner)

    // Soft drop shadow beneath the body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.012), blur: S * 0.045,
                  color: rgb(0, 0, 0, 0.40))
    ctx.addPath(body)
    ctx.setFillColor(rgb(20, 22, 26))
    ctx.fillPath()
    ctx.restoreGState()

    // Graphite vertical gradient inside the body.
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    let bg = CGGradient(colorsSpace: cs,
                        colors: [rgb(64, 67, 74), rgb(30, 32, 37), rgb(21, 23, 27)] as CFArray,
                        locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: bodyRect.maxY),
                           end: CGPoint(x: 0, y: bodyRect.minY), options: [])

    // Subtle specular highlight along the top edge.
    let hi = CGGradient(colorsSpace: cs,
                        colors: [rgb(255, 255, 255, 0.14), rgb(255, 255, 255, 0)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(hi, start: CGPoint(x: 0, y: bodyRect.maxY),
                           end: CGPoint(x: 0, y: bodyRect.maxY - bodyRect.height * 0.32),
                           options: [])
    ctx.restoreGState()

    // Donut ring — mirrors the app's CPU chart, in the same system colors.
    let center = CGPoint(x: S / 2, y: S / 2)
    let outerR = S * 0.300
    let innerR = S * 0.188
    let gap = 3.0

    // (color, fraction of the circle)
    let segments: [(CGColor, Double)] = [
        (rgb(10, 132, 255), 0.34),   // blue
        (rgb(255, 159, 10), 0.20),   // orange
        (rgb(191, 90, 242), 0.12),   // purple
        (rgb(48, 209, 88), 0.10),    // green
        (rgb(255, 55, 95), 0.08),    // pink
        (rgb(255, 255, 255, 0.14), 0.16), // idle track
    ]
    let usable = 360.0 - gap * Double(segments.count)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.006), blur: S * 0.02,
                  color: rgb(0, 0, 0, 0.45))
    var cursor = 90.0 // start at top
    for (color, fraction) in segments {
        let sweep = usable * fraction
        ctx.addPath(annularSector(center: center, inner: innerR, outer: outerR,
                                   startDeg: cursor, sweepDeg: sweep))
        ctx.setFillColor(color)
        ctx.fillPath()
        cursor -= sweep + gap
    }
    ctx.restoreGState()

    // Faint glow in the hole for depth.
    ctx.saveGState()
    let glow = CGGradient(colorsSpace: cs,
                          colors: [rgb(255, 255, 255, 0.10), rgb(255, 255, 255, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: innerR, options: [])
    ctx.restoreGState()

    // Crisp rim on the body edge.
    ctx.saveGState()
    ctx.addPath(body)
    ctx.setStrokeColor(rgb(255, 255, 255, 0.09))
    ctx.setLineWidth(max(1, S * 0.0035))
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let outDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// (filename, pixel size)
let targets: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
var cache: [Int: CGImage] = [:]
for (name, size) in targets {
    let img = cache[Int(size)] ?? drawIcon(size: size)
    cache[Int(size)] = img
    writePNG(img, to: outDir + "/" + name)
}
// A standalone preview at 1024 for eyeballing.
writePNG(cache[1024]!, to: outDir + "/preview_1024.png")
print("wrote \(targets.count) icon PNGs to \(outDir)")
