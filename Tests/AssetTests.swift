import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
for (name, pixels) in [("icon_16x16.png", 16), ("icon_32x32@2x.png", 64), ("icon_512x512@2x.png", 1024)] {
    let data = try Data(contentsOf: directory.appendingPathComponent(name))
    let bitmap = NSBitmapImageRep(data: data)!
    precondition(bitmap.pixelsWide == pixels && bitmap.pixelsHigh == pixels, "Wrong pixel dimensions for \(name)")
    precondition(bitmap.hasAlpha && bitmap.colorAt(x: 0, y: 0)?.alphaComponent == 0, "Icon background must be transparent")
}
print("PASS: 6 icon pixel-dimension/transparency checks")
