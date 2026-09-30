import AppKit
let folder = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let factor = CGFloat(pixels) / 1024
        let transform = NSAffineTransform(); transform.scale(by: factor); transform.concat()
        NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.93, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 210, yRadius: 210).fill()
        NSColor(calibratedRed: 0.12, green: 0.44, blue: 0.38, alpha: 1).setStroke()
        let back = NSBezierPath(roundedRect: NSRect(x: 232, y: 190, width: 454, height: 596), xRadius: 68, yRadius: 68)
        back.lineWidth = 36; back.stroke()
        NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.93, alpha: 1).setFill()
        let front = NSBezierPath(roundedRect: NSRect(x: 334, y: 258, width: 454, height: 596), xRadius: 68, yRadius: 68)
        front.fill(); front.lineWidth = 36; front.stroke()
        NSColor(calibratedRed: 0.12, green: 0.44, blue: 0.38, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 451, y: 792, width: 220, height: 94), xRadius: 30, yRadius: 30).fill()
        for y in [650, 530, 410] {
            let line = NSBezierPath(); line.move(to: NSPoint(x: 425, y: y)); line.line(to: NSPoint(x: y == 410 ? 600 : 696, y: y))
            line.lineWidth = 30; line.lineCapStyle = .round; line.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: folder + "/icon_\(size)x\(size)\(suffix).png"))
    }
}
