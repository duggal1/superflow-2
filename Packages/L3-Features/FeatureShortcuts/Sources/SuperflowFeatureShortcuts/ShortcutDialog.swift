import SuperflowDesignSystem
import SuperflowKernel
import SuperflowTextLexicon
import SuperflowUIComponents
import SwiftUI

/// Add and Edit are the same dialog. The composer card that used to sit at the
/// top of the page is gone.
struct ShortcutDialog: View {
    private let existing: ShortcutEntry?
    private let onSave: (ShortcutDraft) -> Void
    @State private var trigger: String
    @State private var content: String

    init(existing: ShortcutEntry? = nil, onSave: @escaping (ShortcutDraft) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _trigger = State(initialValue: existing?.trigger ?? "")
        _content = State(initialValue: existing?.content ?? "")
    }

    private var canConfirm: Bool {
        !trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var risky: Bool {
        let trimmed = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && CommonWords.isRisky(trigger: trimmed)
    }

    var body: some View {
        DialogFrame(title: existing == nil ? "Add a shortcut" : "Edit shortcut",
                    confirmTitle: existing == nil ? "Add shortcut" : "Save",
                    canConfirm: canConfirm,
                    onConfirm: {
                        var draft = ShortcutDraft(id: existing?.id, trigger: trigger,
                                                  content: content,
                                                  match: existing?.match ?? .wholeUtterance,
                                                  enabled: existing?.enabled ?? true)
                        draft.trigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(draft)
                    }) {
            VStack(alignment: .leading, spacing: 16) {
                DialogField("You say") {
                    AppTextField(text: $trigger, prompt: "sign off", autofocus: true)
                }
                if risky {
                    Badge("Common phrase", variant: .orange)
                }
                DialogField("It types") {
                    AppEditor(text: $content, prompt: "Best, Harshit")
                }
            }
        }
    }
}
