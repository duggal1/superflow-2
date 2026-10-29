import SuperflowDesignSystem
import SuperflowKernel
import SuperflowTextLexicon
import SuperflowUIComponents
import SwiftUI

/// Add and Edit are the same dialog, for both a term and a correction. The
/// "You say / You get" composer card is gone.
struct TermDialog: View {
    enum Kind: Hashable { case term, correction }

    private let existing: LexiconEntry?
    private let onSave: (LexiconDraft) -> Void
    @State private var kind: Kind
    @State private var say: String
    @State private var result: String

    init(existing: LexiconEntry? = nil, onSave: @escaping (LexiconDraft) -> Void) {
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

    var body: some View {
        DialogFrame(title: existing == nil
                        ? (kind == .term ? "Add a term" : "Add a correction")
                        : (kind == .term ? "Edit term" : "Edit correction"),
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
                Segmented(selection: $kind, items: [
                    .init("Term", value: .term),
                    .init("Correction", value: .correction),
                ], level: .dialog)
                DialogField(kind == .term ? "Term" : "You say") {
                    AppTextField(text: $say, prompt: kind == .term ? "Next.js" : "next js",
                                 autofocus: true)
                }
                if kind == .correction {
                    DialogField("You get") {
                        AppTextField(text: $result, prompt: "Next.js")
                    }
                    .transition(.opacity)
                }
                if risky {
                    Badge("Common phrase", variant: .orange)
                }
            }
            .animation(Motion.fade, value: kind)
        }
    }
}
