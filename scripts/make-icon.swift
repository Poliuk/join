// Draws Join!'s app icon and writes Resources/AppIcon.icns (plus docs/AppIcon.png for the README).
//   make icon        # or: swift scripts/make-icon.swift
// The icon is an amber tile with a countdown ring, three quarters left, around a camera. Geometry is
// in a 1024-point canvas with the origin at the top left, the macOS app icon grid: an 824-point tile
// inset 100 points, leaving room for the shadow. Each size is drawn from the vectors, not scaled down.
import CoreGraphics
import Foundation
import ImageIO

let canvas: CGFloat = 1024
let center = CGPoint(x: 512, y: 512)
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: srgb,
        components: [
            CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha,
        ])!
}

func verticalGradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: srgb, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
}

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tileRadius: CGFloat = 186

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// The camera: a rounded body and a lens wedge with softened corners.
func camera() -> CGPath {
    let path = CGMutablePath()
    path.addPath(roundedRect(CGRect(x: 397, y: 452, width: 150, height: 120), 30))
    path.move(to: CGPoint(x: 547, y: 494))
    path.addLine(to: CGPoint(x: 617, y: 459))
    path.addQuadCurve(to: CGPoint(x: 627, y: 465), control: CGPoint(x: 627, y: 454))
    path.addLine(to: CGPoint(x: 627, y: 559))
    path.addQuadCurve(to: CGPoint(x: 617, y: 565), control: CGPoint(x: 627, y: 570))
    path.addLine(to: CGPoint(x: 547, y: 530))
    path.closeSubpath()
    return path
}

func render(pixels: Int) -> CGImage {
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(pixels) / canvas
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: scale, y: -scale)

    // Shadows ignore the transform: offsets are in device pixels with y up, and the blur is about
    // twice the Gaussian's standard deviation.
    func shadow(dy: CGFloat, deviation: CGFloat, _ shadowColor: CGColor, around draw: () -> Void) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -dy * scale), blur: 2 * deviation * scale, color: shadowColor)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        draw()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    func fillTile(with gradient: CGGradient, to bottom: CGFloat) {
        ctx.saveGState()
        ctx.addPath(roundedRect(tile, tileRadius))
        ctx.clip()
        ctx.drawLinearGradient(
            gradient, start: CGPoint(x: 0, y: tile.minY), end: CGPoint(x: 0, y: bottom), options: [.drawsAfterEndLocation])
        ctx.restoreGState()
    }

    // The amber tile, lifted off the desktop.
    shadow(dy: 14, deviation: 16, color(0x000000, 0.28)) {
        fillTile(with: verticalGradient([(0, color(0xFFC857)), (1, color(0xEC8706))]), to: tile.maxY)
    }
    // Light from above over the top half, and a thin bright rim.
    fillTile(with: verticalGradient([(0, color(0xFFFFFF, 0.28)), (1, color(0xFFFFFF, 0))]), to: tile.midY)
    ctx.addPath(roundedRect(tile.insetBy(dx: 1, dy: 1), tileRadius - 1))
    ctx.setStrokeColor(color(0xFFFFFF, 0.22))
    ctx.setLineWidth(2)
    ctx.strokePath()

    // The ring's track.
    ctx.addEllipse(in: CGRect(x: center.x - 250, y: center.y - 250, width: 500, height: 500))
    ctx.setStrokeColor(color(0xFFFFFF, 0.30))
    ctx.setLineWidth(66)
    ctx.strokePath()

    // Three quarters of the time left, from twelve o'clock clockwise (angles grow clockwise here,
    // since y points down), and the camera, both raised by a warm shadow.
    shadow(dy: 10, deviation: 12, color(0x8A4300, 0.30)) {
        ctx.addArc(center: center, radius: 250, startAngle: -.pi / 2, endAngle: .pi, clockwise: false)
        ctx.setStrokeColor(color(0xFFFFFF))
        ctx.setLineWidth(66)
        ctx.setLineCap(.round)
        ctx.strokePath()
        ctx.addPath(camera())
        ctx.setFillColor(color(0x1C1C1E))
        ctx.fillPath()
    }
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL, dpi: Int = 72) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(
        destination, image,
        [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { fatalError("Couldn't write \(url.path)") }
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(getpid()).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

// No 1x files for 16 and 32 points: iconutil stores those two as legacy ARGB entries, and macOS 26
// and later shrink a legacy entry onto a grey plate instead of masking it. Without them, 32 points
// at 1x uses the 32-pixel picture of icon_16x16@2x, and 16 points at 1x scales that down.
for points in [16, 32, 128, 256, 512] {
    if points >= 128 {
        writePNG(render(pixels: points), to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    }
    writePNG(
        render(pixels: points * 2), to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"), dpi: 144)
}

let icns = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "-o", icns.path, iconset.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }

writePNG(render(pixels: 256), to: root.appendingPathComponent("docs/AppIcon.png"))
print("Wrote \(icns.path) and docs/AppIcon.png")
