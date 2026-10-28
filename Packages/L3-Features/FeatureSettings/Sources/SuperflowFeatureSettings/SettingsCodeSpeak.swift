import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

/// Code Speak is preview-first: when it is on, the card grows to show a live
/// example instead of explaining itself. Commands open a dialog, not an
/// in-card expander.
struct CodeSpeakCard: View {
    nonisolated static let titles = ["Code Speak", "Try Code Speak"]

    @ObservedObject var model: SettingsViewModel
    let query: String

    @State private var sample = "camel case user profile id"
    @Environment(DialogHost.self) private var dialogs
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var enabled: Bool { model.settings.codeSpeakEnabled }

    var body: some View {
        VStack(spacing: 0) {
            SettingRow(.code, "Code Speak", filter: query) {
                AppToggle("Code Speak", isOn: $model.settings.codeSpeakEnabled)
            }
            .padding(.horizontal, Space.sm)

            if enabled {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("You say")
                            .appType(.caption)
                            .foregroundStyle(Tok.text2)
                        Spacer()
                        AppButton("Commands", kind: .quiet, height: 24) {
                            dialogs.present {
                                CodeSpeakCommandsDialog(commands: SettingsViewModel.codeSpeakCommands)
                            }
                        }
                    }
                    AppTextField(text: $sample, prompt: "camel case user profile id", mono: true)
                    Text("It types")
                        .appType(.caption)
                        .foregroundStyle(Tok.text2)
                    result
                }
                .padding(.horizontal, Space.sm)
                .padding(.top, 4)
                .padding(.bottom, Space.sm)
                .transition(.opacity)
            }
        }
        .padding(.vertical, Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tok.surface, in: .rect(cornerRadius: Radius.card, style: .continuous))
        .modifier(ContrastStroke(radius: Radius.card))
        .animation(reduceMotion ? nil : .smooth(duration: 0.30), value: enabled)
        .animation(.easeOut(duration: 0.15), value: sample)
    }

    private var result: some View {
        let typed = model.codeSpeakPreview(sample)
        return Text(typed.isEmpty ? " " : typed)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(Tok.text)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .id(typed)
            .transition(.opacity)
    }
}

struct CodeSpeakCommandsDialog: View {
    let commands: [(say: String, types: String)]

    var body: some View {
        DialogFrame(title: "Code Speak commands", confirmTitle: "Done",
                    canConfirm: true, showsCancel: false, onConfirm: {}) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(commands.enumerated()), id: \.offset) { _, command in
                        HStack(spacing: 16) {
                            Text(command.say)
                                .foregroundStyle(Tok.text2)
                                .frame(width: 180, alignment: .leading)
                            Icon(.arrow, size: 12, tint: Tok.text2)
                            Text(command.types)
                                .foregroundStyle(Tok.text)
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 13, design: .monospaced))
                        .frame(height: 32)
                    }
                }
            }
            .frame(height: 256)
        }
    }
}
