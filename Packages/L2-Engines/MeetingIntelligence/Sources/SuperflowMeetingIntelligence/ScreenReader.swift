import AppKit
import ScreenCaptureKit
import Vision

public enum ScreenReaderError: LocalizedError {
    case noPermission, noDisplay

    public var errorDescription: String? {
        switch self {
        case .noPermission: "Screen recording permission is required for screen awareness."
        case .noDisplay: "No display is available for screen awareness."
        }
    }
}

public struct ScreenReader: Sendable {
    public init() {}

    @MainActor
    public func readText(maxChars: Int = 6_000) async throws -> String {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw ScreenReaderError.noPermission
        }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let displayID = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw ScreenReaderError.noDisplay
        }
        let ownBundle = Bundle.main.bundleIdentifier
        let ownWindows = content.windows.filter { window in
            guard let ownBundle else { return window.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }
            return window.owningApplication?.bundleIdentifier == ownBundle ||
                window.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
        }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
        let config = SCStreamConfiguration()
        let scale = screen?.backingScaleFactor ?? 1
        config.width = Int((CGFloat(display.width) * scale).rounded())
        config.height = Int((CGFloat(display.height) * scale).rounded())
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: image).perform([request])
            let lines = (request.results ?? [])
                .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                .compactMap { $0.topCandidates(1).first?.string }
            return String(lines.joined(separator: "\n").prefix(max(0, min(maxChars, 6_000))))
        }.value
    }
}
