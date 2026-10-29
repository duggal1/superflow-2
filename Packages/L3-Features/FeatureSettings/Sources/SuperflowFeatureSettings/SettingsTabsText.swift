import SuperflowDesignSystem
import SuperflowKernel
import SuperflowUIComponents
import SwiftUI

struct TextTab: View {
    nonisolated static let titles = [
        "Spell out 0 to 9", "Capitalize sentences", "End with a period", "Trailing space",
        "Paragraph break", "Block length",
    ] + CodeSpeakCard.titles

    @ObservedObject var model: SettingsViewModel
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            SettingsCard(titles: Array(Self.titles.prefix(4)), query: query) {
                SettingRow(.number, "Spell out 0 to 9", filter: query) {
                    AppToggle("Spell out 0 to 9", isOn: $model.settings.spellOutSmallNumbers)
                }
                SettingRow(.textSize, "Capitalize sentences", filter: query) {
                    AppToggle("Capitalize sentences", isOn: $model.settings.lineFormat.capitalize)
                }
                SettingRow(.textAppend, "End with a period", filter: query) {
                    AppToggle("End with a period", isOn: $model.settings.lineFormat.finalPeriod)
                }
                SettingRow(.space, "Trailing space", filter: query) {
                    AppToggle("Trailing space", isOn: $model.settings.lineFormat.trailingSpace)
                }
            }
            SettingsCard(titles: ["Paragraph break", "Block length"], query: query) {
                SettingRow(.paragraph, "Paragraph break", filter: query) {
                    Segmented(selection: $model.settings.lineFormat.breakStyle,
                              items: BreakStyle.allCases.map { .init($0.label, value: $0) },
                              onCard: true)
                }
                SettingRow(.blocks, "Block length", filter: query) {
                    Dropdown(selection: $model.blockLength,
                             options: BlockLength.allCases.map { .init(value: $0, title: $0.title) },
                             label: "Block length")
                }
            }
            if query.isEmpty || CodeSpeakCard.titles.contains(where: {
                $0.localizedCaseInsensitiveContains(query)
            }) {
                CodeSpeakCard(model: model, query: query)
            }
        }
    }
}
