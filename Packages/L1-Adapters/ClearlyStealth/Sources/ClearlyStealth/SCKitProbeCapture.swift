import AppKit
import ClearlyStealthCore
import CoreGraphics
import ScreenCaptureKit
import Foundation

public enum StealthCaptureError: LocalizedError {
    case noPermission
    case unsupportedOS
    case noDisplay

    public var errorDescription: String? {
        switch self {
        case .noPermission: "Screen Recording permission is required to verify hiding."
        case .unsupportedOS: "Verification requires macOS 14 or newer."
        case .noDisplay: "No display is available for verification."
        }
    }
}

/// The one OS-dependent probe: two pure-magenta rectangles captured the way a
/// meeting app captures the display, with NO window exclusions. Probe A lives
/// in a `.none` window (the Island's policy); the control lives in a `.readOnly`
/// window. If the control is captured and the `.none` probe is not, hiding
/// worked for this capture path on this macOS build.
///
/// This runs only on an explicit user "Verify" action, never during a meeting,
/// and briefly shows the two probe rectangles. It is not exercised by tests.
public struct SCKitProbeCapture: ProbeCapturing {
    private static let magenta = (r: UInt8(255), g: UInt8(0), b: UInt8(255))
    private static let probeSide: CGFloat = 32

    /// Verification-only switch. When true, the Island probe window is created
    /// as `.readOnly` instead of `.none` so a driver can prove the verifier is
    /// capable of returning `Failed` (acceptance gate 5b). Never set by the app.
    private let forceIslandCapturable: Bool

    public init(forceIslandCapturable: Bool = false) {
        self.forceIslandCapturable = forceIslandCapturable
    }

    @MainActor
    public func capture() async throws -> ProbeMeasurement {
        guard #available(macOS 14.0, *) else { throw StealthCaptureError.unsupportedOS }
        guard CGPreflightScreenCaptureAccess() else { throw StealthCaptureError.noPermission }

        let screens = NSScreen.screens
        guard let screen = NSScreen.main ?? screens.first else { throw StealthCaptureError.noDisplay }
        let screenFrame = screen.frame
        let globalHeight = screens.map(\.frame.maxY).max() ?? screenFrame.maxY
        let displayTopLeftY = globalHeight - screenFrame.maxY

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: {
            $0.displayID == screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        }) ?? content.displays.first else { throw StealthCaptureError.noDisplay }

        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.showsCursor = false

        // Probe placement in global top-left points.
        let islandX = screenFrame.minX + 120
        let islandY = displayTopLeftY + 120
        let controlX = islandX + 80
        let side = Self.probeSide

        let islandSharing: StealthSharingMode = forceIslandCapturable ? .readOnly : .none
        let islandWindow = Self.makeProbe(x: islandX, topLeftY: islandY, side: side, sharing: islandSharing)
        let controlWindow = Self.makeProbe(x: controlX, topLeftY: islandY, side: side, sharing: .readOnly)
        defer { islandWindow.close(); controlWindow.close() }
        islandWindow.orderFrontRegardless()
        controlWindow.orderFrontRegardless()

        // Let the windows land in a real frame before capture.
        try await Task.sleep(nanoseconds: 100_000_000)

        // NO exclusions: we want to see whether the .none window leaked.
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        let pixelsPerPointX = CGFloat(config.width) / screenFrame.width
        let pixelsPerPointY = CGFloat(config.height) / screenFrame.height
        let islandRect = CGRect(
            x: (islandX - screenFrame.minX) * pixelsPerPointX,
            y: (islandY - displayTopLeftY) * pixelsPerPointY,
            width: side * pixelsPerPointX,
            height: side * pixelsPerPointY
        )
        let controlRect = CGRect(
            x: (controlX - screenFrame.minX) * pixelsPerPointX,
            y: (islandY - displayTopLeftY) * pixelsPerPointY,
            width: side * pixelsPerPointX,
            height: side * pixelsPerPointY
        )

        return ProbeMeasurement(
            controlMatchedRatio: Self.magentaRatio(in: controlRect, of: image),
            islandMatchedRatio: Self.magentaRatio(in: islandRect, of: image)
        )
    }

    @MainActor
    private static func makeProbe(x: CGFloat, topLeftY: CGFloat, side: CGFloat,
                                  sharing: StealthSharingMode) -> NSWindow {
        let globalHeight = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        let frame = NSRect(x: x, y: globalHeight - (topLeftY + side),
                           width: side, height: side)
        let window = NSWindow(contentRect: frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isOpaque = true
        window.backgroundColor = NSColor(red: 1, green: 0, blue: 1, alpha: 1)
        window.hasShadow = false
        window.level = .statusBar
        window.sharingType = sharing.nsSharingType
        window.isReleasedWhenClosed = false
        return window
    }

    /// Fraction of pixels inside `rect` that are the probe magenta. Reads the
    /// CGImage into a known RGBA layout so bitmap-info differences don't matter.
    private static func magentaRatio(in rect: CGRect, of image: CGImage) -> Double {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return 0 }
        let bytesPerRow = width * 4
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.assumingMemoryBound(to: UInt8.self)

        let x0 = max(0, Int(rect.minX.rounded(.down)))
        let y0 = max(0, Int(rect.minY.rounded(.down)))
        let x1 = min(width, Int(rect.maxX.rounded(.up)))
        let y1 = min(height, Int(rect.maxY.rounded(.up)))
        guard x1 > x0, y1 > y0 else { return 0 }

        var matched = 0
        for y in y0..<y1 {
            for x in x0..<x1 {
                let i = y * bytesPerRow + x * 4
                let r = pixels[i], g = pixels[i + 1], b = pixels[i + 2]
                if r > 200, g < 60, b > 200 { matched += 1 }
            }
        }
        return Double(matched) / Double((x1 - x0) * (y1 - y0))
    }
}
