import SuperflowDesignSystem
import SuperflowKernel
import SuperflowTextLexicon
import SuperflowUIComponents
import SwiftUI

/// Add and Edit are the same dialog, for both a term and a correction. The
/// "You say / You get" composer card is gone.
public struct TermDialog: View {
    enum Kind: Hashable { case term, correction }

    private let existing: LexiconEntry?
    private let onSave: (LexiconDraft) -> Void
    @State private var kind: Kind
    @State private var say: String
    @State private var result: String
    @State private var wire = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(existing: LexiconEntry? = nil, onSave: @escaping (LexiconDraft) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _kind = State(initialValue: existing?.kind == .correction ? .correction : .term)
        _say = State(initialValue: existing?.triggers.first ?? "")
        _result = State(initialValue: existing?.canonical ?? "")
    }

    private var canConfirm: Bool {
        let value = say.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        if kind == .term { return true }
        return !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var risky: Bool {
        let trimmed = say.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && CommonWords.isRisky(trigger: trimmed)
    }

    public var body: some View {
        DialogFrame(title: existing == nil
                        ? (kind == .term ? "Add a term" : "Add a correction")
                        : (kind == .term ? "Edit term" : "Edit correction"),
                    subtitle: kind == .term ? "A word Superflow should always spell your way."
                        : "When the transcript has this, type that instead.",
                    confirmTitle: existing == nil ? "Add" : "Save",
                    canConfirm: canConfirm,
                    onConfirm: {
                        let trimmedSay = say.trimmingCharacters(in: .whitespacesAndNewlines)
                        var draft = LexiconDraft(id: existing?.id,
                                                 kind: kind == .term ? .term : .correction,
                                                 triggers: [trimmedSay],
                                                 canonical: result.trimmingCharacters(in: .whitespacesAndNewlines),
                                                 enabled: existing?.enabled ?? true,
                                                 source: .user)
                        if kind == .term { draft.canonical = trimmedSay }
                        onSave(draft)
                    }) {
            VStack(alignment: .leading, spacing: 16) {
                if existing == nil {
                    Segmented(selection: $kind, items: [
                        .init("Term", value: .term),
                        .init("Correction", value: .correction),
                    ], level: .dialog)
                }
                if kind == .correction {
                    HStack(alignment: .bottom, spacing: 12) {
                        DialogField("You say") { AppTextField(text: $say, prompt: "next js", autofocus: true) }
                        PixelWire(progress: wire, horizontal: true).frame(height: 32)
                        DialogField("You get") { AppTextField(text: $result, prompt: "Next.js") }
                    }
                    if canConfirm {
                        HStack(spacing: 10) {
                            Text(say).foregroundStyle(Tok.text2).strikethrough()
                            PixelMark(rows: ["....#..", ".....#.", "#######", ".....#.", "....#.."], cell: 2, color: Ramp.blue[4])
                            Text(result).foregroundStyle(Tok.text)
                        }
                        .appType(.body).frame(height: 24)
                    }
                } else {
                    DialogField("Term") { AppTextField(text: $say, prompt: "Next.js", autofocus: true) }
                    if canConfirm { PixelChip(say, mono: false) }
                }
                if risky {
                    PixelBadge("Common phrase", kind: .caution)
                }
            }
            .animation(reduceMotion ? nil : Motion.fade, value: kind)
        }
        .onAppear { wire = canConfirm ? 1 : 0 }
        .onChange(of: canConfirm) { _, valid in
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { wire = valid ? 1 : 0 }
        }
    }
}
