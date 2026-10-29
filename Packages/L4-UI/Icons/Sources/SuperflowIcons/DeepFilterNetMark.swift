import AppKit
import SwiftUI

/// The genuine Hugging Face source mark. DeepFilterNet does not publish a dedicated vendor logo.
@MainActor
public struct DeepFilterNetMark: View {
    public static var resourceURL: URL? {
        Bundle.module.url(forResource: "logo-huggingface", withExtension: "svg")
    }
    private static let image = resourceURL.flatMap { NSImage(contentsOf: $0) }
    public init() {}
    public var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image).resizable().scaledToFit()
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityLabel("Hugging Face, source of the DeepFilterNet 3 model")
    }
}
