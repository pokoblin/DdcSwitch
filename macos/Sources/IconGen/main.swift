// Draws the macOS app icon: the monitor with a ⇄ double arrow from the Windows icon
// (src/icon_art.rs), placed on the rounded-square plate of the macOS icon grid.
//
// usage: IconGen <output.iconset>

import AppKit

let dark = CGColor(srgbRed: 38 / 255, green: 50 / 255, blue: 56 / 255, alpha: 1)
let mid = CGColor(srgbRed: 84 / 255, green: 110 / 255, blue: 122 / 255, alpha: 1)
let screenTop = CGColor(srgbRed: 41 / 255, green: 182 / 255, blue: 246 / 255, alpha: 1)
let screenBottom = CGColor(srgbRed: 30 / 255, green: 110 / 255, blue: 229 / 255, alpha: 1)

func render(_ px: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(px) / 1024
    // Work top-down in 1024-point icon grid coordinates.
    ctx.translateBy(x: 0, y: CGFloat(px))
    ctx.scaleBy(x: s, y: -s)
    ctx.interpolationQuality = .high

    // Plate: 824 × 824 at (100, 100) with a soft shadow, like Apple's icon template.
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let platePath = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 24 * s, color: CGColor(gray: 0, alpha: 0.30))
    ctx.addPath(platePath)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(platePath)
    ctx.clip()
    let plateGradient = CGGradient(colorsSpace: nil, colors: [
        CGColor(srgbRed: 0.98, green: 0.985, blue: 0.99, alpha: 1),
        CGColor(srgbRed: 0.86, green: 0.89, blue: 0.92, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(plateGradient, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])
    ctx.restoreGState()

    // Monitor art, in the unit square of icon_art.rs (u right, v down), mapped onto 660 points.
    let art = CGRect(x: 182, y: 196, width: 660, height: 660)
    func p(_ u: CGFloat, _ v: CGFloat) -> CGPoint { CGPoint(x: art.minX + u * art.width, y: art.minY + v * art.height) }
    func rrect(_ cx: CGFloat, _ cy: CGFloat, _ hw: CGFloat, _ hh: CGFloat, _ r: CGFloat) -> CGPath {
        let rect = CGRect(origin: p(cx - hw, cy - hh), size: CGSize(width: 2 * hw * art.width, height: 2 * hh * art.height))
        return CGPath(roundedRect: rect, cornerWidth: r * art.width, cornerHeight: r * art.width, transform: nil)
    }

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8 * s), blur: 18 * s, color: CGColor(gray: 0, alpha: 0.22))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setFillColor(dark)
    ctx.addPath(rrect(0.5, 0.885, 0.24, 0.05, 0.035))
    ctx.fillPath()
    ctx.setFillColor(mid)
    ctx.fill(CGRect(origin: p(0.43, 0.70), size: CGSize(width: 0.14 * art.width, height: 0.16 * art.height)))
    ctx.setFillColor(dark)
    ctx.addPath(rrect(0.5, 0.42, 0.48, 0.33, 0.08))
    ctx.fillPath()
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(rrect(0.5, 0.41, 0.40, 0.25, 0.04))
    ctx.clip()
    let screen = CGGradient(colorsSpace: nil, colors: [screenTop, screenBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(screen, start: p(0, 0.16), end: p(0, 0.66), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    // ⇄ arrows
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    func arrow(tail: CGFloat, tip: CGFloat, y: CGFloat) {
        let dir: CGFloat = tip > tail ? 1 : -1
        let headLen: CGFloat = 0.17, headHalf: CGFloat = 0.12, stroke: CGFloat = 0.08
        let shaftEnd = tip - dir * headLen * 0.8
        let x0 = min(tail, shaftEnd), x1 = max(tail, shaftEnd)
        ctx.fill(CGRect(origin: p(x0, y - stroke / 2), size: CGSize(width: (x1 - x0) * art.width, height: stroke * art.height)))
        ctx.move(to: p(tip, y))
        ctx.addLine(to: p(tip - dir * headLen, y - headHalf))
        ctx.addLine(to: p(tip - dir * headLen, y + headHalf))
        ctx.closePath()
        ctx.fillPath()
    }
    arrow(tail: 0.25, tip: 0.75, y: 0.32)
    arrow(tail: 0.75, tip: 0.25, y: 0.51)

    return ctx.makeImage()!
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: IconGen <output.iconset>\n".utf8))
    exit(2)
}
let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        let rep = NSBitmapImageRep(cgImage: render(size * scale))
        try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    }
}
