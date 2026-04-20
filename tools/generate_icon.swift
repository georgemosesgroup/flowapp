import AppKit
import Foundation

// ────────────────────────────────────────────────────────────────────
// Flow app-icon generator.
//
// Renders the macOS AppIcon set at 1024×1024 using the brand colours
// from `lib/theme/tokens.dart`, then `sips`-downscales into all the
// required sizes (16, 32, 64, 128, 256, 512, 1024). The resulting
// PNGs land directly in Runner/Assets.xcassets/AppIcon.appiconset/
// — no Contents.json edits needed; the existing manifest already
// points at these filenames.
//
// Design:
//   • macOS "squircle" — cornerRadius = 22.37% of the canvas.
//   • Diagonal gradient: accentHover (top-left) → accent (bottom-right).
//   • Five vertical white bars (graphic-eq style), matching the
//     sidebar brand logo (Icons.graphic_eq_rounded, white on accent).
//   • Subtle inner shadow for depth — common on macOS 14+ icons.
//
// Run via `tools/generate_icon.sh`.
// ────────────────────────────────────────────────────────────────────

// Flow palette (must stay in sync with lib/theme/tokens.dart).
let accentHover = NSColor(srgbRed: 1.00, green: 0.373, blue: 0.447, alpha: 1.0)  // #FF5F72
let accent      = NSColor(srgbRed: 0.910, green: 0.298, blue: 0.372, alpha: 1.0) // #E84C5F

let canvasSize: CGFloat = 1024

// Render into a fixed-pixel-size bitmap rep, NOT `NSImage.lockFocus`.
// lockFocus() uses the current display's backing scale (2× on any
// Retina Mac), which would silently produce a 2048×2048 PNG — bad for
// an asset catalog that explicitly expects 1024×1024.
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize),
    pixelsHigh: Int(canvasSize),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .calibratedRGB,
    bytesPerRow: 0,
    bitsPerPixel: 32
)!
rep.size = NSSize(width: canvasSize, height: canvasSize)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
guard let ctx = NSGraphicsContext.current?.cgContext else {
    fatalError("Could not acquire drawing context")
}

// 1. macOS squircle background + diagonal accent gradient.
let cornerRadius = canvasSize * 0.2237
let bgRect = NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
let bgPath = NSBezierPath(roundedRect: bgRect,
                          xRadius: cornerRadius,
                          yRadius: cornerRadius)
ctx.saveGState()
bgPath.addClip()

let gradient = NSGradient(starting: accentHover, ending: accent)!
// -45° = top-left (0,1024) → bottom-right (1024,0) in AppKit's flipped Y.
gradient.draw(in: bgPath, angle: -45)

// 2. Five vertical bars, matching Icons.graphic_eq_rounded proportions.
//    Heights vary so the logo reads as "sound / voice" rather than a
//    static grid. Ordered: short, tall, tallest, medium, short — the
//    same silhouette the Flutter brand tile uses.
let barHeights: [CGFloat] = [0.42, 0.72, 0.94, 0.58, 0.34]
let iconAreaSize = canvasSize * 0.56
let barCount = CGFloat(barHeights.count)
let barGap = iconAreaSize * 0.06
let barWidth = (iconAreaSize - barGap * (barCount - 1)) / barCount
let cornerBar = barWidth / 2
let centerX = canvasSize / 2
let centerY = canvasSize / 2
let leftEdge = centerX - iconAreaSize / 2

// Soft shadow under the bars so they lift off the red gradient — same
// trick the brand tile uses (BoxShadow alpha .35 blur 8).
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
shadow.shadowOffset = NSSize(width: 0, height: -canvasSize * 0.01)
shadow.shadowBlurRadius = canvasSize * 0.015
shadow.set()

NSColor.white.setFill()
for (i, hFactor) in barHeights.enumerated() {
    let height = hFactor * iconAreaSize
    let x = leftEdge + (barWidth + barGap) * CGFloat(i)
    let y = centerY - height / 2
    let bar = NSBezierPath(
        roundedRect: NSRect(x: x, y: y, width: barWidth, height: height),
        xRadius: cornerBar,
        yRadius: cornerBar
    )
    bar.fill()
}

ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()

// 3. Write out 1024×1024 PNG — the downscale script takes it from here.
guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode PNG")
}

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "icon_1024.png"

do {
    try png.write(to: URL(fileURLWithPath: outputPath))
    print("Wrote \(outputPath) (\(png.count) bytes)")
} catch {
    fatalError("Failed to write \(outputPath): \(error)")
}
