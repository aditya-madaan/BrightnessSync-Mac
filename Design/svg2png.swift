// Usage: swift svg2png.swift <input.svg> <output.png> <size>
// Renders SVG to PNG preserving alpha (qlmanage adds a white background that
// breaks template menu bar icons; this script doesn't).

import AppKit

guard CommandLine.arguments.count == 4,
      let size = Int(CommandLine.arguments[3]) else {
    fputs("usage: svg2png <input.svg> <output.png> <size>\n", stderr)
    exit(1)
}

let input  = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])

guard let img = NSImage(contentsOf: input) else {
    fputs("failed to load \(input.path)\n", stderr)
    exit(1)
}

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
) else {
    fputs("failed to allocate bitmap\n", stderr); exit(1)
}
rep.size = NSSize(width: size, height: size)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
img.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
         from: .zero, operation: .copy, fraction: 1.0)
NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    fputs("failed to encode png\n", stderr); exit(1)
}
try data.write(to: output)
