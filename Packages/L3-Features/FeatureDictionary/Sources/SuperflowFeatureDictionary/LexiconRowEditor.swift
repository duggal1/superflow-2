import SuperflowDesignSystem
import SuperflowKernel
import SuperflowUIComponents
import SwiftUI

/// Editing happens in place under the row it belongs to; there is no add sheet.
struct LexiconRowEditor: View {
    @ObservedObject var model: DictionaryViewModel
    let entry: LexiconEntry
    let onDone: () -> Void
    @State private var draft: LexiconDraft

    init(model: DictionaryViewModel, entry: LexiconEntry, onDone: @escaping () -> Void) {
        self.model = model
        self.entry = entry
        self.onDone = onDone
        _draft = State(initialValue: LexiconDraft(entry: entry))
    }

    private var triggers: Binding<String> {
        Binding(
            get: { draft.triggers.joined(separator: ", ") },
            set: { draft.triggers = $0.split(separator: ",").map(String.init) }
        )
    }

    private var issues: [LexiconIssue] { model.issues(for: draft) }
    private var valid: Bool { LexiconValidation.isValid(draft, existing: model.entries) }

    var body: some View {
        Card(padding: Space.cardPaddingDense) {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(spacing: Space.sm) {
                    Text("You say")
                        .appType(.body)
                        .foregroundStyle(Tok.text2)
                    AppField("Trigger", prompt: "next js, next.js", text: triggers)
                        .frame(maxWidth: 260)
                    Text("You get")
                        .appType(.body)
                        .foregroundStyle(Tok.text2)
                    AppField("Replacement", prompt: "Next.js", text: $draft.canonical)
                        .frame(maxWidth: 260)
                    Spacer(minLength: 0)
                }
                HStack(spacing: Space.sm) {
                    Text("On").appType(.body).foregroundStyle(Tok.text)
                    SettingToggle("Entry enabled", isOn: $draft.enabled)
                    Spacer(minLength: Space.md)
                    AppButton("Cancel", kind: .quiet, height: ControlHeight.small, action: onDone)
                    AppButton("Save", kind: .primary, height: ControlHeight.small,
                              enabled: valid) {
                        let value = draft
                        Task {
                            if await model.save(value) { onDone() }
                        }
                    }
                }
                if !issues.isEmpty {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        ForEach(issues, id: \.self) { issue in
                            Badge(issue.message,
                                  variant: issue.isBlocking ? .rose : .orange,
                                  size: .sm)
                        }
                    }
                }
            }
        }
    }
}
