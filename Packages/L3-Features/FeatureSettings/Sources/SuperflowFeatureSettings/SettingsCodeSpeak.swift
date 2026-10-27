import SuperflowDesignSystem
import SuperflowIcons
import SuperflowKernel
import SuperflowTextCodeSpeak
import SuperflowUIComponents
import SwiftUI

/// Code Speak is preview-first: the switch, the sentence it acts on and the
/// written form sit in one card, so the setting never asks for trust.
struct CodeSpeakCard: View {
    nonisolated static let titles = ["Code Speak", "Try Code Speak", "Code Speak commands"]

    /// The preview is a debug surface, not the pipeline. Bounded so a pasted
    /// document cannot rebuild an attributed string on every keystroke.
    private static let previewLimit = 4_000

    @ObservedObject var model: SettingsViewModel
    let query: String

    @State private var input = ""
    @State private var showingCommands = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var enabled: Bool { model.settings.codeSpeakEnabled }

    var body: some View {
        SettingsCard(titles: Self.titles, query: query) {
            SettingRow("Code Speak", filter: query) {
                AppToggle("Code Speak", isOn: $model.settings.codeSpeakEnabled)
            }
            Text("Reads identifiers, paths and flags as written. Runs after numbers, "
                 + "before your dictionary.")
                .font(Typography.secondary)
                .foregroundStyle(Tok.text2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, Space.sm)
            preview
            commands
                .padding(.bottom, Space.sm)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            AppField("Try Code Speak", prompt: "camel case user profile id", text: $input)
                .disabled(!enabled)
                .help(enabled ? "Type a sentence to see the written form."
                              : "Turn on Code Speak to preview.")
            result
            if !input.isEmpty {
                HStack(spacing: Space.sm) {
                    Spacer(minLength: 0)
                    AppButton("Clear", kind: .quiet, height: ControlHeight.small,
                              enabled: enabled) {
                        input = ""
                    }
                }
            }
        }
        .padding(.vertical, Space.sm)
    }

    @ViewBuilder
    private var result: some View {
        if !enabled {
            note("Turn on Code Speak to preview.")
        } else if input.isEmpty {
            note("Type a sentence to see the written form.")
        } else if input.count > Self.previewLimit {
            note("Preview stops at \(Self.previewLimit) characters. Cleanup still runs on the "
                 + "full text.")
        } else {
            let output = CodeSpeakRewriter.rewrite(input, protected: Protected())
            if output.text == input {
                note("Nothing to rewrite. This already reads as speech.")
            } else {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(written(output.text, against: input))
                        .font(Typography.large)
                        .foregroundStyle(Tok.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(summary(of: output))
                        .font(Typography.secondary)
                        .monospacedDigit()
                        .foregroundStyle(Tok.text2)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Written form. \(output.text)")
            }
        }
    }

    private var commands: some View {
        VStack(spacing: 0) {
            RowButton("Code Speak commands", height: ControlHeight.regular) {
                showingCommands.toggle()
            } content: {
                HStack(spacing: Space.xs) {
                    Text("Commands")
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Tok.text)
                    Spacer(minLength: 0)
                    Text(showingCommands ? "Hide" : "Show")
                        .font(Typography.secondary)
                        .foregroundStyle(Tok.text2)
                    Icon(.chevronDown, size: 9, weight: .medium, tint: Tok.text2)
                        .rotationEffect(.degrees(showingCommands ? 180 : 0))
                }
                .padding(.horizontal, Space.xs)
            }
            .animation(reduceMotion ? nil : Motion.hoverIn, value: showingCommands)

            if showingCommands {
                VStack(spacing: 0) {
                    ForEach(Self.commandRows) { row in
                        commandRow(row)
                    }
                }
                .padding(.top, Space.xxs)
            }
        }
    }

    private func commandRow(_ row: CommandRow) -> some View {
        HStack(spacing: Space.sm) {
            Text(row.spoken)
                .font(Typography.mono)
                .foregroundStyle(Tok.text2)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Icon(.arrow, size: 12, tint: Tok.text2)
            Text(row.written)
                .font(Typography.mono)
                .foregroundStyle(Tok.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: ControlHeight.regular)
        .padding(.horizontal, Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.spoken), becomes \(row.written)")
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Typography.secondary)
            .foregroundStyle(Tok.text2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Changed words carry the accent; everything else is plain ink. No red and
    /// green: status colour stays inside badges and dots.
    private func written(_ text: String, against input: String) -> AttributedString {
        var attributed = AttributedString()
        for piece in TextDiff.segments(reference: input, candidate: text) {
            var run = AttributedString(piece.text)
            run.font = Typography.large
            run.foregroundColor = Tok.text
            if piece.changed {
                run.foregroundColor = Tok.accent
                run.backgroundColor = Tok.accentSoft
            }
            attributed += run
        }
        return attributed
    }

    private func summary(of output: CodeSpeakOutput) -> String {
        var labels: [String] = []
        for edit in output.edits {
            let label = Self.label(for: edit.ruleID)
            if !labels.contains(label) { labels.append(label) }
        }
        let count = output.edits.count
        let noun = count == 1 ? "change" : "changes"
        return "\(count) \(noun) · \(labels.joined(separator: ", "))"
    }

    private static func label(for ruleID: String) -> String {
        if ruleID.hasPrefix("identifier.") {
            return ruleID.replacingOccurrences(of: "identifier.", with: "") + " case"
        }
        if ruleID.hasPrefix("symbol.") { return "symbol" }
        if ruleID.hasPrefix("flag.") { return "flag" }
        switch ruleID {
        case "path": return "path"
        case "backtick": return "literal"
        default: return ruleID
        }
    }

    private struct CommandRow: Identifiable {
        let spoken: String
        let written: String
        var id: String { spoken }
    }

    private static let commandRows: [CommandRow] = [
        CommandRow(spoken: "camel case user profile", written: "userProfile"),
        CommandRow(spoken: "snake case user profile", written: "user_profile"),
        CommandRow(spoken: "pascal case user profile", written: "UserProfile"),
        CommandRow(spoken: "src slash main dot ts", written: "src/main.ts"),
        CommandRow(spoken: "dash dash dry run", written: "--dry-run"),
        CommandRow(spoken: "open bracket x close bracket", written: "[x]"),
        CommandRow(spoken: "fat arrow", written: "=>"),
    ]
}
