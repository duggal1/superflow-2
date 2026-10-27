import SuperflowDesignSystem
import SuperflowKernel
import SuperflowPorts
import SuperflowTextLexicon
import SuperflowUIComponents
import SwiftUI

/// Runs the real deterministic dictionary stage on every keystroke, so the
/// preview is the app's own behaviour and not a mock.
struct DictionaryPlayground: View {
    let entries: [LexiconEntry]
    @State private var input = ""
    @State private var output = AttributedString()

    private struct Key: Hashable {
        let input: String
        let count: Int
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.sm) {
                SectionHeader("Try it")
                AppField("Try it", prompt: "Say a sentence that uses one of your terms",
                         text: $input)
                if !input.isEmpty {
                    Text(output)
                        .font(Typography.large)
                        .foregroundStyle(Tok.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task(id: Key(input: input, count: entries.count)) {
            await run()
        }
    }

    private func run() async {
        let text = input
        guard !text.isEmpty else {
            output = AttributedString()
            return
        }
        let stage = LexiconStage(entries: entries)
        let result = await stage.apply(TranscriptDraft(text: text), context: TextContext())
        var attributed = AttributedString()
        for segment in TextDiff.segments(reference: text, candidate: result.text) {
            var piece = AttributedString(segment.text)
            if segment.changed { piece.backgroundColor = Tok.accentSoft }
            attributed += piece
        }
        output = attributed
    }
}
