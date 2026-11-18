import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

/// The value the Island hands to an Intelligence host for the compose and answer
/// states. Agent 4's `SuperflowFeatureIntelligence` module exposes the same shape
/// (`IslandIntelligenceContent` + a view model); this local value is the seam until
/// that module lands, so FeatureIsland never imports or reimplements the backend.
public struct IslandIntelligenceContent: Equatable, Sendable {
    public var prompt: String
    public var answer: String
    public var isStreaming: Bool
    public var suggestions: [String]
    public var errorMessage: String?

    public init(prompt: String = "", answer: String = "", isStreaming: Bool = false,
                suggestions: [String] = [], errorMessage: String? = nil) {
        self.prompt = prompt
        self.answer = answer
        self.isStreaming = isStreaming
        self.suggestions = suggestions
        self.errorMessage = errorMessage
    }

    public static let empty = IslandIntelligenceContent()
}

/// Name used by the App-side hosting seam. Kept as an alias of the Island's own
/// value so FeatureIsland never imports a second L3 module and the App can keep
/// calling `SuperflowFeatureIsland.IntelligenceContent` unqualified in its files.
public typealias IntelligenceContent = IslandIntelligenceContent

/// Hosts the Intelligence presentation for compose and answer. The Island owns
/// no backend logic: it gives the host content and callbacks and renders whatever
/// view the host returns. An adapter for `SuperflowFeatureIntelligence` can
/// conform to this protocol without changing a view in this package.
@MainActor
public protocol IslandIntelligenceSeam: AnyObject {
    func composeView(content: IslandIntelligenceContent, onSend: @escaping (String) -> Void) -> AnyView
    func answerView(content: IslandIntelligenceContent, onCopy: @escaping () -> Void) -> AnyView
}

/// A minimal, honest local host used until the Intelligence module is available.
/// It renders the content directly with Island tokens and does no network work.
@MainActor
public final class LocalIntelligenceSeam: IslandIntelligenceSeam {
    public init() {}

    public func composeView(content: IslandIntelligenceContent,
                            onSend: @escaping (String) -> Void) -> AnyView {
        AnyView(LocalComposeView(prompt: content.prompt, onSend: onSend))
    }

    public func answerView(content: IslandIntelligenceContent,
                           onCopy: @escaping () -> Void) -> AnyView {
        AnyView(LocalAnswerView(content: content, onCopy: onCopy))
    }
}

private struct LocalComposeView: View {
    @State private var draft: String
    let onSend: (String) -> Void

    init(prompt: String, onSend: @escaping (String) -> Void) {
        _draft = State(initialValue: prompt)
        self.onSend = onSend
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onSend(text)
    }

    var body: some View {
        HStack(spacing: IslandTokens.Space.sm) {
            PixelBitmap(rows: PixelGlyphs.compose, cell: PixelInstrument.cell,
                        gap: PixelInstrument.gap, tone: canSend ? IslandRamp.step(4) : IslandRamp.step(2))
            AppField("Question", prompt: "Ask about your meeting", text: $draft,
                     height: IslandTokens.Size.control, onCard: true, onSubmit: send)
            PixelSendMark(enabled: canSend, action: send)
        }
    }
}

private struct LocalAnswerView: View {
    let content: IslandIntelligenceContent
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: IslandTokens.Space.sm) {
            if let message = content.errorMessage, !message.isEmpty {
                Text(message)
                    .appType(IslandTokens.TypeRole.caption)
                    .foregroundStyle(IslandTokens.Color.danger)
                    .textSelection(.enabled)
            }
            Text(content.answer)
                .appType(IslandTokens.TypeRole.body)
                .foregroundStyle(IslandTokens.Color.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if content.isStreaming {
                HStack(spacing: IslandTokens.Space.sm) {
                    PixelBand(active: true, cells: 16)
                    Text("Streaming").appType(IslandTokens.TypeRole.caption)
                        .foregroundStyle(IslandTokens.Color.ink2)
                }
            }
            HStack(spacing: IslandTokens.Space.sm) {
                PixelBitmap(rows: PixelBitmap.check, cell: PixelInstrument.cell,
                            gap: PixelInstrument.gap, tone: IslandRamp.step(4))
                AppButton("Copy", glyph: nil, kind: .quiet,
                          height: IslandTokens.Size.control, action: onCopy)
                    .frame(width: IslandTokens.Size.copyWidth, alignment: .leading)
            }
        }
    }
}
