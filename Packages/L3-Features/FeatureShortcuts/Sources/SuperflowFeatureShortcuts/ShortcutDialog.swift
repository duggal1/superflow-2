import SuperflowDesignSystem
import SuperflowKernel
import SuperflowTextLexicon
import SuperflowUIComponents
import SwiftUI

/// Add and Edit are the same dialog. The composer card that used to sit at the
/// top of the page is gone.
public struct ShortcutDialog: View {
    private let existing: ShortcutEntry?
    private let onSave: (ShortcutDraft) -> Void
    @State private var trigger: String
    @State private var content: String
    @State private var wire = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(existing: ShortcutEntry? = nil, onSave: @escaping (ShortcutDraft) -> Void) {
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

    public var body: some View {
        DialogFrame(title: existing == nil ? "Add a shortcut" : "Edit shortcut",
                    subtitle: "Say a short phrase. Superflow types the full text.",
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
            VStack(alignment: .leading, spacing: 0) {
                DialogField("You say") {
                    AppTextField(text: $trigger, prompt: "sign off", autofocus: true)
                }
                HStack(spacing: 12) {
                    PixelWire(progress: wire).padding(.leading, 14)
                    if risky {
                        PixelBadge("Common phrase", kind: .caution)
                        Text("It expands whenever you say it.").appType(.caption).foregroundStyle(Tok.text2)
                    } else {
                        Text(canConfirm ? "Superflow types" : "Then Superflow types")
                            .appType(.caption).foregroundStyle(Tok.text2)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 38)
                DialogField("It types") {
                    AppEditor(text: $content, prompt: "Best, Harshit")
                }
                if canConfirm {
                    HStack(spacing: 10) {
                        PixelChip(trigger.trimmingCharacters(in: .whitespacesAndNewlines))
                        PixelMark(rows: ["....#..", ".....#.", "#######", ".....#.", "....#.."], cell: 2, color: Ramp.blue[4])
                        Text(content.components(separatedBy: .newlines).first ?? "")
                            .font(.system(size: 12, design: .monospaced)).foregroundStyle(Tok.text2).lineLimit(1)
                    }
                    .padding(.top, 16).frame(height: 44)
                }
            }
        }
        .onAppear { wire = canConfirm ? 1 : 0 }
        .onChange(of: canConfirm) { _, valid in
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { wire = valid ? 1 : 0 }
        }
    }
}
