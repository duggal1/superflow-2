// Renders the Superflow app-icon set into App/Resources/Assets.xcassets.
//
// The mark is deterministic and drawn entirely with Core Graphics so the icons are reproducible
// from source rather than checked-in binaries that nobody can regenerate. Run with:
//   swift tools/gen-appicon/main.swift
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let catalog = root.appendingPathComponent("App/Resources/Assets.xcassets", isDirectory: true)
let iconSet = catalog.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
let brandMarkURL = root.appendingPathComponent(
    "Packages/L4-UI/Icons/Sources/SuperflowIcons/Resources/brand-mark.svg"
)
guard let brandMark = NSImage(contentsOf: brandMarkURL) else {
    throw NSError(domain: "gen-appicon", code: 3,
                  userInfo: [NSLocalizedDescriptionKey: "cannot load \(brandMarkURL.path)"])
}

// point size -> the pixel sizes to render for that slot (1x and 2x).
let slots: [(point: Int, scales: [(suffix: String, pixels: Int)])] = [
    (16, [("", 16), ("@2x", 32)]),
    (32, [("", 32), ("@2x", 64)]),
    (128, [("", 128), ("@2x", 256)]),
    (256, [("", 256), ("@2x", 512)]),
    (512, [("", 512), ("@2x", 1024)]),
]

func makeDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
}

/// Draws the supplied brand mark on a blue-600 macOS icon tile.
func drawIcon(pixels: Int) -> CGImage? {
    let size = CGFloat(pixels)
    guard let context = CGContext(data: nil, width: pixels, height: pixels,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return nil
    }
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    // Rounded-square tile with macOS-style corner radius.
    let inset = size * 0.06
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.225
    let tile = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius,
                      transform: nil)
    context.saveGState()
    context.addPath(tile)
    context.clip()
    context.setFillColor(CGColor(srgbRed: 37.0 / 255, green: 99.0 / 255,
                                 blue: 235.0 / 255, alpha: 1))
    context.fill(rect)
    context.restoreGState()

    let logoSize = size * 0.68
    let logoRect = CGRect(x: (size - logoSize) / 2, y: (size - logoSize) / 2,
                          width: logoSize, height: logoSize * 110 / 108.92)
    let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    brandMark.draw(in: logoRect)
    NSGraphicsContext.restoreGraphicsState()

    return context.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "gen-appicon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "cannot write \(url.path)"])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "gen-appicon", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "finalize failed for \(url.path)"])
    }
}

try makeDirectory(catalog)
try makeDirectory(iconSet)

var entries: [String] = []
for slot in slots {
    for scale in slot.scales {
        let name = "icon_\(slot.point)x\(slot.point)\(scale.suffix).png"
        guard let image = drawIcon(pixels: scale.pixels) else {
            FileHandle.standardError.write(Data("failed to render \(name)\n".utf8))
            exit(1)
        }
        try writePNG(image, to: iconSet.appendingPathComponent(name))
        entries.append("""
            {
              "filename" : "\(name)",
              "idiom" : "mac",
              "scale" : "\(scale.suffix == "@2x" ? "2x" : "1x")",
              "size" : "\(slot.point)x\(slot.point)"
            }
        """)
    }
}

let appIconContents = """
{
  "images" : [
\(entries.joined(separator: ",\n"))
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try appIconContents.write(to: iconSet.appendingPathComponent("Contents.json"), atomically: true,
                          encoding: .utf8)

let accentSet = catalog.appendingPathComponent("AccentColor.colorset", isDirectory: true)
try makeDirectory(accentSet)
let accentContents = """
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.831",
          "green" : "0.318",
          "red" : "0.149"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try accentContents.write(to: accentSet.appendingPathComponent("Contents.json"), atomically: true,
                         encoding: .utf8)

let catalogRoot = """
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try catalogRoot.write(to: catalog.appendingPathComponent("Contents.json"), atomically: true,
                      encoding: .utf8)

print("Wrote \(slots.reduce(0) { $0 + $1.scales.count }) icon files into \(iconSet.path)")
