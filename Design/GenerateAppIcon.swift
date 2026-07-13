import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

func d2r(_ d: Double) -> CGFloat { CGFloat(d) * .pi / 180 }
func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: a)
}

// green -> yellow -> orange -> red, by fraction 0...1
func gaugeColor(_ t: Double) -> CGColor {
    let stops: [(Double, (Int,Int,Int))] = [
        (0.0, (48,209,88)), (0.5, (255,214,10)), (0.75, (255,159,10)), (1.0, (255,55,95))]
    for i in 0..<stops.count-1 {
        let (t0, c0) = stops[i], (t1, c1) = stops[i+1]
        if t <= t1 {
            let f = (t - t0) / max(0.0001, t1 - t0)
            return rgb(Int(Double(c0.0)+(Double(c1.0-c0.0))*f),
                       Int(Double(c0.1)+(Double(c1.1-c0.1))*f),
                       Int(Double(c0.2)+(Double(c1.2-c0.2))*f))
        }
    }
    return rgb(stops.last!.1.0, stops.last!.1.1, stops.last!.1.2)
}

func drawIcon(size S: CGFloat) -> CGImage {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high

    // Body squircle
    let margin = S * 0.096
    let bodyRect = CGRect(x: margin, y: margin, width: S - 2*margin, height: S - 2*margin)
    let body = CGPath(roundedRect: bodyRect, cornerWidth: bodyRect.width*0.2237,
                      cornerHeight: bodyRect.width*0.2237, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -S*0.012), blur: S*0.045, color: rgb(0,0,0,0.40))
    ctx.addPath(body); ctx.setFillColor(rgb(20,22,26)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(body); ctx.clip()
    let bg = CGGradient(colorsSpace: cs, colors: [rgb(64,67,74), rgb(30,32,37), rgb(21,23,27)] as CFArray,
                        locations: [0,0.55,1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x:0,y:bodyRect.maxY), end: CGPoint(x:0,y:bodyRect.minY), options: [])
    let hi = CGGradient(colorsSpace: cs, colors: [rgb(255,255,255,0.13), rgb(255,255,255,0)] as CFArray, locations: [0,1])!
    ctx.drawLinearGradient(hi, start: CGPoint(x:0,y:bodyRect.maxY),
                           end: CGPoint(x:0,y:bodyRect.maxY - bodyRect.height*0.32), options: [])
    ctx.restoreGState()

    // Gauge geometry — a 240° speedometer arc opening at the bottom.
    let center = CGPoint(x: S/2, y: S*0.545)
    let R = S*0.285
    let thick = S*0.085
    let startDeg = 210.0, sweep = 240.0
    let value = 0.68

    // Track (dark)
    ctx.saveGState()
    ctx.setLineWidth(thick)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(rgb(255,255,255,0.10))
    let trackPath = CGMutablePath()
    trackPath.addArc(center: center, radius: R, startAngle: d2r(startDeg),
                     endAngle: d2r(startDeg - sweep), clockwise: true)
    ctx.addPath(trackPath); ctx.strokePath()
    ctx.restoreGState()

    // Value arc — angular gradient (green->red), drawn as small stroked steps.
    ctx.saveGState()
    ctx.setLineWidth(thick)
    ctx.setLineCap(.round)
    let steps = 160
    let valueSteps = Int(Double(steps) * value)
    for i in 0..<valueSteps {
        let f0 = Double(i)/Double(steps)
        let f1 = Double(i+1)/Double(steps)
        let a0 = startDeg - f0*sweep
        let a1 = startDeg - f1*sweep
        let seg = CGMutablePath()
        seg.addArc(center: center, radius: R, startAngle: d2r(a0), endAngle: d2r(a1), clockwise: true)
        ctx.addPath(seg)
        ctx.setStrokeColor(gaugeColor(f0 / max(0.0001, value)))
        ctx.strokePath()
    }
    ctx.restoreGState()

    // Tick dots just outside the arc.
    ctx.saveGState()
    let ticks = 9
    for i in 0...ticks {
        let f = Double(i)/Double(ticks)
        let a = d2r(startDeg - f*sweep)
        let rr = R + thick*0.95
        let p = CGPoint(x: center.x + cos(a)*rr, y: center.y + sin(a)*rr)
        ctx.addEllipse(in: CGRect(x: p.x - S*0.012, y: p.y - S*0.012, width: S*0.024, height: S*0.024))
        ctx.setFillColor(rgb(255,255,255, i % 3 == 0 ? 0.55 : 0.28))
        ctx.fillPath()
    }
    ctx.restoreGState()

    // Needle pointing to the value, with a hub.
    let na = d2r(startDeg - value*sweep)
    let tip = CGPoint(x: center.x + cos(na)*(R + thick*0.15), y: center.y + sin(na)*(R + thick*0.15))
    let perp = na + .pi/2
    let baseW = S*0.028
    let b1 = CGPoint(x: center.x + cos(perp)*baseW, y: center.y + sin(perp)*baseW)
    let b2 = CGPoint(x: center.x - cos(perp)*baseW, y: center.y - sin(perp)*baseW)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -S*0.004), blur: S*0.02, color: rgb(0,0,0,0.5))
    let needle = CGMutablePath()
    needle.move(to: b1); needle.addLine(to: tip); needle.addLine(to: b2); needle.closeSubpath()
    ctx.addPath(needle); ctx.setFillColor(rgb(245,246,248)); ctx.fillPath()
    ctx.restoreGState()
    // Hub
    ctx.addEllipse(in: CGRect(x: center.x - S*0.05, y: center.y - S*0.05, width: S*0.10, height: S*0.10))
    ctx.setFillColor(rgb(28,30,34)); ctx.fillPath()
    ctx.addEllipse(in: CGRect(x: center.x - S*0.05, y: center.y - S*0.05, width: S*0.10, height: S*0.10))
    ctx.setStrokeColor(rgb(255,255,255,0.5)); ctx.setLineWidth(S*0.006); ctx.strokePath()

    // Body rim
    ctx.saveGState(); ctx.addPath(body)
    ctx.setStrokeColor(rgb(255,255,255,0.09)); ctx.setLineWidth(max(1, S*0.0035)); ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil); CGImageDestinationFinalize(dest)
}

let outDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let targets: [(String, CGFloat)] = [
    ("icon_16x16.png",16),("icon_16x16@2x.png",32),("icon_32x32.png",32),("icon_32x32@2x.png",64),
    ("icon_128x128.png",128),("icon_128x128@2x.png",256),("icon_256x256.png",256),
    ("icon_256x256@2x.png",512),("icon_512x512.png",512),("icon_512x512@2x.png",1024)]
var cache: [Int: CGImage] = [:]
for (name,size) in targets { let img = cache[Int(size)] ?? drawIcon(size:size); cache[Int(size)]=img; writePNG(img, to: outDir+"/"+name) }
writePNG(cache[1024]!, to: outDir+"/preview_1024.png")
print("wrote gauge icons")
