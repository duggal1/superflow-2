import SuperflowDesignSystem
import SuperflowKernel
import SuperflowTextShortcuts
import SuperflowUIComponents
import SwiftUI

struct ShortcutRowEditor: View {
    @ObservedObject var model: ShortcutsViewModel
    let entry: ShortcutEntry
    let onDone: () -> Void
    @State private var draft: ShortcutDraft

    init(model: ShortcutsViewModel, entry: ShortcutEntry, onDone: @escaping () -> Void) {
        self.model = model
        self.entry = entry
        self.onDone = onDone
        _draft = State(initialValue: ShortcutDraft(entry: entry))
    }

    private var issues: [ShortcutIssue] { model.issues(for: draft) }
    private var valid: Bool { ShortcutValidation.isValid(draft, existing: model.entries) }

    var body: some View {
        Card(padding: Space.cardPaddingDense) {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(spacing: Space.sm) {
                    Text("Say")
                        .appType(.body)
                        .foregroundStyle(Tok.text2)
                    AppField("Trigger", prompt: "sign off", text: $draft.trigger)
                        .frame(maxWidth: 260)
                    Segmented(selection: $draft.match, items: [
                        Segmented.Item("Whole utterance", value: ShortcutMatch.wholeUtterance),
                        Segmented.Item("Inline", value: ShortcutMatch.inline),
                    ], onCard: true)
                    Spacer(minLength: Space.md)
                    Text("On").appType(.body).foregroundStyle(Tok.text)
                    SettingToggle("Shortcut enabled", isOn: $draft.enabled)
                }
                AppTextEditor("Shortcut text", text: $draft.content, minHeight: 96)
                HStack(spacing: Space.sm) {
                    if let counter = byteCounter {
                        Text(counter)
                            .appType(.body)
                            .foregroundStyle(Tok.text2)
                    }
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

    private var byteCounter: String? {
        let limit = ShortcutsStage.maxContentBytes
        let bytes = draft.contentBytes
        guard bytes > Int(Double(limit) * 0.8) else { return nil }
        return "\(bytes / 1024) KB of \(limit / 1024) KB"
    }
}
