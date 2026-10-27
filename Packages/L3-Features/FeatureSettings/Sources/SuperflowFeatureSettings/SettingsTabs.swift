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
    nonisolated static let titles = ["Speech model", "Clean up with S1-mini",
                         "Hold to talk", "Double-tap window", "Meeting hold", "Typing speed"]

    @ObservedObject var model: SettingsViewModel
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SettingsCard(titles: Array(Self.titles.prefix(2)), query: query) {
                SettingRow("Speech model", filter: query) { speechModel }
                SettingRow("Clean up with S1-mini", filter: query) {
                    HStack(spacing: Space.xs) {
                        if !model.cleanupReady {
                            AppButton("Download", kind: .quiet, height: ControlHeight.small,
                                      enabled: !model.isDownloadingCleanup) {
                                Task { await model.downloadCleanupModel() }
                            }
                        }
                        AppToggle("Clean up with S1-mini", isOn: $model.settings.cleanupEnabled)
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
                               in: SettingsValidation.typingSpeedRange, unit: "wpm")
                }
            }
        }
    }

    @ViewBuilder
    private var speechModel: some View {
        HStack(spacing: Space.xs) {
            if model.asrReady {
                Badge("Verified", variant: .green, size: .sm)
            } else if model.isDownloadingASR {
                Text(progressLabel)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Tok.text2)
            } else {
                AppButton("Download", kind: .quiet, height: ControlHeight.small,
                          enabled: model.profile.supportsLiveDictation) {
                    Task { await model.downloadASRModel() }
                }
            }
            Dropdown(selection: Binding(get: { model.settings.asrProfile },
                                        set: { model.setProfile($0) }),
                     options: model.profileOptions.map {
                         Dropdown.Option(model.profileName($0), value: $0)
                     },
                     label: "Speech model")
        }
    }

    private var progressLabel: String {
        guard let progress = model.asrProgress else { return "Downloading…" }
        return "\(Int(progress * 100))%"
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
