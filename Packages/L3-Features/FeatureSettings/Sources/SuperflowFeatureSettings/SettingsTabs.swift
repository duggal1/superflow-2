import SuperflowDesignSystem
import SuperflowKernel
import SuperflowUIComponents
import SwiftUI

struct GeneralTab: View {
    nonisolated static let titles = ["Name", "Appearance", "Launch at login", "Idle pill"]

    @ObservedObject var model: SettingsViewModel
    let query: String

    var body: some View {
        SettingsCard(titles: Self.titles, query: query) {
            SettingRow("Name", filter: query) {
                AppTextField(text: $model.settings.displayName, label: "Name")
                    .frame(width: 200)
            }
            SettingRow("Appearance", filter: query) {
                Segmented(selection: $model.settings.theme,
                          items: ThemeMode.allCases.map { .init($0.label, value: $0) })
            }
            SettingRow("Launch at login", filter: query) {
                AppToggle("Launch at login",
                          isOn: $model.settings.launchAtLogin,
                          enabled: model.launchAtLoginAvailable)
            }
            SettingRow("Idle pill", filter: query) {
                AppToggle("Idle pill", isOn: $model.settings.showIdlePill)
            }
        }
    }
}

struct DictationTab: View {
    @Environment(\.openModels) private var openModels
    nonisolated static let titles = ["Clean up with S1-mini",
                         "Hold to talk", "Double-tap window", "Meeting hold", "Typing speed"]

    @ObservedObject var model: SettingsViewModel
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SettingsCard(titles: Array(Self.titles.prefix(1)), query: query) {
                SettingRow("Clean up with S1-mini", filter: query) {
                    HStack(spacing: 12) {
                        if !model.cleanupModelInstalled {
                            AppButton("Get model", kind: .link, height: ControlHeight.small) { openModels() } 
                        }
                        AppToggle("Clean up with S1-mini", isOn: $model.settings.cleanupEnabled)
                            .disabled(!model.cleanupModelInstalled)
                    }
                }
            }
            SettingsCard(titles: Array(Self.titles.suffix(4)), query: query) {
                SettingRow("Hold to talk", filter: query) {
                    ms(\.holdMs, in: SettingsValidation.holdRange)
                }
                SettingRow("Double-tap window", filter: query) {
                    ms(\.doubleTapMs, in: SettingsValidation.doubleTapRange)
                }
                SettingRow("Meeting hold", filter: query) {
                    ms(\.meetingHoldMs, in: SettingsValidation.meetingHoldRange)
                }
                SettingRow("Typing speed", filter: query) {
                    AppStepper(value: $model.settings.typingWPM,
                               range: SettingsValidation.typingSpeedRange, unit: "wpm", label: "Typing speed")
                }
            }
        }
    }

    private func ms(_ key: WritableKeyPath<GestureConfig, Int>,
                    in range: ClosedRange<Int>) -> some View {
        TimingSlider(value: Binding(
                        get: { Double(model.settings.gesture[keyPath: key]) },
                        set: { model.settings.gesture[keyPath: key] = Int($0.rounded()) }),
                     in: Double(range.lowerBound)...Double(range.upperBound),
                     step: 10, unit: "ms")
    }
}
