import AppKit

func render(size: Int, menu: Bool) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 200, y: CGFloat(size) / 200)
    context.cgContext.translateBy(x: 0, y: 200)
    context.cgContext.scaleBy(x: 1, y: -1)
    if !menu {
        NSColor(srgbRed: 40/255, green: 91/255, blue: 206/255, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 8, y: 8, width: 184, height: 184), xRadius: 40, yRadius: 40).fill()
    } else {
        context.cgContext.translateBy(x: -33, y: -33)
        context.cgContext.scaleBy(x: 1.33, y: 1.33)
    }
    (menu ? NSColor.black : NSColor.white).setStroke()
    let wheel = NSBezierPath(roundedRect: NSRect(x: 77, y: 44, width: 46, height: 112), xRadius: 23, yRadius: 23)
    wheel.lineWidth = 12
    wheel.stroke()
    (menu ? NSColor.black : NSColor.white).withAlphaComponent(0.4).setStroke()
    let trails = NSBezierPath()
    trails.lineWidth = 10
    trails.lineCapStyle = .round
    trails.move(to: NSPoint(x: 51, y: 63)); trails.line(to: NSPoint(x: 51, y: 116))
    trails.move(to: NSPoint(x: 149, y: 84)); trails.line(to: NSPoint(x: 149, y: 137))
    trails.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = output.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(size: size, menu: false).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size: size * 2, menu: false).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try render(size: 18, menu: true).write(to: output.appendingPathComponent("MenuIcon.png"))
try render(size: 36, menu: true).write(to: output.appendingPathComponent("MenuIcon@2x.png"))
