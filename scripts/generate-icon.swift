// Editable vector artwork, rendered at every standard macOS application icon size.
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "assets", isDirectory: true)
let iconset = output.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func rounded(_ rect: NSRect, _ radius: CGFloat, _ fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func gradient(_ rect: NSRect, radius: CGFloat, colors: [NSColor], angle: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
    NSGradient(colors: colors)!.draw(in: rect, angle: angle)
    NSGraphicsContext.restoreGraphicsState()
}

func drawIcon(pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(pixels) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()

    // A quiet blue/teal tile, two overlapping windows, and one active Dock item.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x082B54, alpha: 0.22)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    rounded(NSRect(x: 84, y: 84, width: 856, height: 856), 190, color(0x1671DC))
    NSGraphicsContext.restoreGraphicsState()
    gradient(NSRect(x: 84, y: 84, width: 856, height: 856), radius: 190,
             colors: [color(0x155CC6), color(0x198DDC), color(0x50DDCB)], angle: 48)

    let back = NSRect(x: 302, y: 424, width: 508, height: 328)
    rounded(back, 42, color(0xFFFFFF, alpha: 0.34))
    let backBorder = NSBezierPath(roundedRect: back.insetBy(dx: 2, dy: 2), xRadius: 40, yRadius: 40)
    color(0xFFFFFF, alpha: 0.54).setStroke()
    backBorder.lineWidth = 4
    backBorder.stroke()

    NSGraphicsContext.saveGraphicsState()
    shadow.shadowColor = color(0x063D82, alpha: 0.26)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.set()
    rounded(NSRect(x: 192, y: 306, width: 548, height: 360), 44, .white)
    NSGraphicsContext.restoreGraphicsState()
    gradient(NSRect(x: 204, y: 318, width: 524, height: 276), radius: 32,
             colors: [color(0xD1F1FC), color(0xF3FCFF)], angle: 60)
    for x in [230, 258, 286] {
        color(0x8EB5C8).setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: 620, width: 12, height: 12)).fill()
    }
    // A single focus marker keeps the symbol readable at 16 and 32 pixels.
    rounded(NSRect(x: 418, y: 420, width: 96, height: 78), 18, color(0x218BCB, alpha: 0.16))
    rounded(NSRect(x: 438, y: 440, width: 56, height: 38), 9, color(0x208DCE, alpha: 0.5))

    rounded(NSRect(x: 264, y: 174, width: 496, height: 82), 36, color(0x073A86, alpha: 0.28))
    rounded(NSRect(x: 334, y: 193, width: 44, height: 44), 12, color(0xFFFFFF, alpha: 0.32))
    rounded(NSRect(x: 490, y: 190, width: 50, height: 50), 14, .white)
    rounded(NSRect(x: 652, y: 193, width: 44, height: 44), 12, color(0xFFFFFF, alpha: 0.32))
    color(0x91FFF0).setFill()
    NSBezierPath(ovalIn: NSRect(x: 509, y: 157, width: 12, height: 7)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try drawIcon(pixels: points * scale).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
try drawIcon(pixels: 1024).write(to: output.appendingPathComponent("AppIcon.png"))

// Modern ICNS entries contain PNG data; include both standard and Retina sizes.
func bigEndian(_ value: Int) -> Data {
    var value = UInt32(value).bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}
var entries = Data()
for (type, size) in [("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128),
                     ("ic08", 256), ("ic09", 512), ("ic10", 1024),
                     ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512)] {
    let png = drawIcon(pixels: size)
    entries.append(Data(type.utf8))
    entries.append(bigEndian(png.count + 8))
    entries.append(png)
}
var icns = Data("icns".utf8)
icns.append(bigEndian(entries.count + 8))
icns.append(entries)
try icns.write(to: output.appendingPathComponent("AppIcon.icns"))
