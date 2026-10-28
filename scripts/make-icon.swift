import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let source = root.appendingPathComponent("assets/LocalMind.png")
let iconset = root.appendingPathComponent("assets/LocalMind.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
guard let image = NSImage(contentsOf: source) else {
    fatalError("Cannot open icon source at \(source.path)")
}

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png")
]

for (size, name) in sizes {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { fatalError("Cannot allocate \(size)px icon") }
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current = context
    context?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Cannot encode \(name)")
    }
    try data.write(to: iconset.appendingPathComponent(name), options: .atomic)
}

let output = root.appendingPathComponent("assets/LocalMind.icns")
let icnsImages: [(String, String)] = [
    ("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]
var chunks = Data()
for (type, name) in icnsImages {
    let png = try Data(contentsOf: iconset.appendingPathComponent(name))
    chunks.append(contentsOf: type.utf8)
    let chunkLength = UInt32(png.count + 8)
    chunks.append(contentsOf: [UInt8(chunkLength >> 24), UInt8((chunkLength >> 16) & 0xff), UInt8((chunkLength >> 8) & 0xff), UInt8(chunkLength & 0xff)])
    chunks.append(png)
}
var container = Data("icns".utf8)
let totalLength = UInt32(chunks.count + 8)
container.append(contentsOf: [UInt8(totalLength >> 24), UInt8((totalLength >> 16) & 0xff), UInt8((totalLength >> 8) & 0xff), UInt8(totalLength & 0xff)])
container.append(chunks)
try container.write(to: output, options: .atomic)
print("Created \(output.path)")
