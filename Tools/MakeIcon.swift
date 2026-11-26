import AppKit

// Repo-native vector drawing: reproducible app icon without external assets/tools.
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        // An explicit pixel buffer avoids NSImage.lockFocus inheriting the
        // current display's Retina scale and doubling the requested dimensions.
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        let inset = CGFloat(pixels) * 0.08
        let rect = NSRect(x: inset, y: inset, width: CGFloat(pixels) - 2 * inset, height: CGFloat(pixels) - 2 * inset)
        NSColor(calibratedRed: 0.88, green: 0.19, blue: 0.23, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: CGFloat(pixels) * 0.20, yRadius: CGFloat(pixels) * 0.20).fill()
        NSColor.white.setStroke()
        let cross = NSBezierPath()
        cross.lineWidth = CGFloat(pixels) * 0.085
        cross.lineCapStyle = .round
        let low = CGFloat(pixels) * 0.34
        let high = CGFloat(pixels) * 0.66
        cross.move(to: NSPoint(x: low, y: low))
        cross.line(to: NSPoint(x: high, y: high))
        cross.move(to: NSPoint(x: low, y: high))
        cross.line(to: NSPoint(x: high, y: low))
        cross.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
