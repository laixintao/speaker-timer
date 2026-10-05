import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/SpeakerTimer.iconset")
let output = root.appendingPathComponent("SpeakerTimer/Resources/SpeakerTimer.icns")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

        let tile = NSBezierPath(roundedRect: NSRect(x: 76, y: 76, width: 872, height: 872), xRadius: 205, yRadius: 205)
        NSGradient(
            colors: [
                NSColor(srgbRed: 0.08, green: 0.60, blue: 0.98, alpha: 1),
                NSColor(srgbRed: 0.17, green: 0.24, blue: 0.84, alpha: 1),
                NSColor(srgbRed: 0.31, green: 0.13, blue: 0.62, alpha: 1),
            ],
            atLocations: [0, 0.58, 1],
            colorSpace: .deviceRGB
        )!.draw(in: tile, angle: -55)

        let faceRect = NSRect(x: 247, y: 302, width: 530, height: 530)
        let face = NSBezierPath(ovalIn: faceRect)
        NSColor.white.withAlphaComponent(0.20).setFill()
        face.fill()
        NSColor.white.withAlphaComponent(0.94).setStroke()
        face.lineWidth = 45
        face.stroke()

        let center = NSPoint(x: 512, y: 567)
        let hand = NSBezierPath()
        hand.move(to: center)
        hand.line(to: NSPoint(x: 512, y: 704))
        hand.move(to: center)
        hand.line(to: NSPoint(x: 632, y: 507))
        hand.lineCapStyle = .round
        hand.lineJoinStyle = .round
        hand.lineWidth = 42
        NSColor.white.setStroke()
        hand.stroke()
        NSBezierPath(ovalIn: NSRect(x: 482, y: 537, width: 60, height: 60)).fill()

        let widths: [CGFloat] = [150, 220, 116, 170]
        let colors: [NSColor] = [
            .white,
            NSColor.white.withAlphaComponent(0.92),
            NSColor.white.withAlphaComponent(0.72),
            NSColor.white.withAlphaComponent(0.45),
        ]
        var x: CGFloat = 160
        for (index, width) in widths.enumerated() {
            let bar = NSBezierPath(roundedRect: NSRect(x: x, y: 184, width: width, height: 54), xRadius: 27, yRadius: 27)
            colors[index].setFill()
            bar.fill()
            x += width + 18
        }

        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let filename = "icon_\(points)x\(points)\(suffix).png"
        try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(filename))
    }
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
