import AppKit
import Foundation

struct Args {
    let input: URL
    let output: URL
    let threshold: UInt8
}

func parseArgs() -> Args? {
    let args = CommandLine.arguments
    guard args.count >= 3 else { return nil }
    let threshold: UInt8
    if args.count >= 4, let value = UInt8(args[3]) {
        threshold = value
    } else {
        threshold = 6
    }
    return Args(
        input: URL(fileURLWithPath: args[1]),
        output: URL(fileURLWithPath: args[2]),
        threshold: threshold
    )
}

func makeTransparent(input: URL, output: URL, threshold: UInt8) throws {
    guard
        let image = NSImage(contentsOf: input),
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData)
    else {
        throw NSError(domain: "export_confirmed_logo", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Failed to decode input image."
        ])
    }

    guard let converted = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: bitmap.pixelsWide,
        pixelsHigh: bitmap.pixelsHigh,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "export_confirmed_logo", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Failed to allocate output bitmap."
        ])
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: converted)
    image.draw(in: NSRect(x: 0, y: 0, width: converted.size.width, height: converted.size.height))
    NSGraphicsContext.restoreGraphicsState()

    let width = converted.pixelsWide
    let height = converted.pixelsHigh

    for y in 0..<height {
        for x in 0..<width {
            guard let color = converted.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                continue
            }

            let r = UInt8(max(0, min(255, Int(round(color.redComponent * 255)))))
            let g = UInt8(max(0, min(255, Int(round(color.greenComponent * 255)))))
            let b = UInt8(max(0, min(255, Int(round(color.blueComponent * 255)))))

            if r <= threshold && g <= threshold && b <= threshold {
                converted.setColor(NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0), atX: x, y: y)
            }
        }
    }

    guard let pngData = converted.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "export_confirmed_logo", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "Failed to encode PNG output."
        ])
    }

    try pngData.write(to: output)
}

guard let args = parseArgs() else {
    fputs("usage: swift export_confirmed_logo.swift <input.png> <output.png> [threshold]\n", stderr)
    exit(2)
}

do {
    try makeTransparent(input: args.input, output: args.output, threshold: args.threshold)
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
