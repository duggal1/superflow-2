import AppKit
import SuperflowDesignSystem
import SuperflowKernel
import SuperflowUIComponents
import SwiftUI

struct GeneralTab: View {
    nonisolated static let titles = ["Name", "Appearance", "Launch at login"]

    @ObservedObject var model: SettingsViewModel
    let query: String

    var body: some View {
        SettingsCard(titles: Self.titles, query: query) {
            SettingRow(.person, "Name", filter: query) {
                AppTextField(text: $model.settings.displayName, prompt: "Your name")
                    .frame(width: 200)
            }
            SettingRow(.appearance, "Appearance", filter: query) {
                Segmented(selection: $model.settings.theme,
                          items: ThemeMode.allCases.map { .init($0.label, value: $0) })
            }
            SettingRow(.power, "Launch at login", filter: query) {
                AppToggle("Launch at login",
                          isOn: $model.settings.launchAtLogin,
                          enabled: model.launchAtLoginAvailable)
            }
        }
    }
}

struct DictationTab: View {
    @Environment(\.openModels) private var openModels
    nonisolated static let titles = ["Speech model", "Clean up with S1-mini",
                                     "Hold to talk", "Double-tap window", "Meeting hold"]

    @ObservedObject var model: SettingsViewModel
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            SettingsCard(titles: Array(Self.titles.prefix(2)), query: query) {
                SettingRow(.waveform, "Speech model", filter: query) {
                    HStack(spacing: 8) {
                        if !model.asrReady {
                            AppButton("Get model", kind: .quiet, height: 28) { openModels() }
                        }
                        Dropdown(selection: Binding(
                                    get: { model.settings.asrProfile },
                                    set: { model.setProfile($0) }),
                                 options: model.profileOptions.map {
                                     .init(model.profileName($0), value: $0)
                                 },
                                 label: "Speech model")
                    }
                }
                SettingRow(.cleanup, "Clean up with S1-mini", filter: query) {
                    HStack(spacing: 12) {
                        if !model.cleanupModelInstalled {
                            AppButton("Get model", kind: .quiet, height: 28) { openModels() }
                        }
                        AppToggle("Clean up with S1-mini", isOn: $model.settings.cleanupEnabled)
                            .disabled(!model.cleanupModelInstalled)
                    }
                }
            }
            SettingsCard(titles: Array(Self.titles.suffix(3)), query: query) {
                SettingRow(.handTap, "Hold to talk", filter: query) {
                    ms(\.holdMs, in: SettingsValidation.holdRange)
                }
                SettingRow(.timer, "Double-tap window", filter: query) {
                    ms(\.doubleTapMs, in: SettingsValidation.doubleTapRange)
                }
                SettingRow(.meetings, "Meeting hold", filter: query) {
                    ms(\.meetingHoldMs, in: SettingsValidation.meetingHoldRange)
                }
            }
        }
    }

    private func ms(_ key: WritableKeyPath<GestureConfig, Int>,
                    in range: ClosedRange<Int>) -> some View {
        AppSlider(value: Binding(
                    get: { Double(model.settings.gesture[keyPath: key]) },
                    set: { model.settings.gesture[keyPath: key] = Int($0.rounded()) }),
                  in: Double(range.lowerBound)...Double(range.upperBound),
                  step: 10, unit: "ms")
    }
}

struct MeetingsTab: View {
    nonisolated static let titles = ["Meetings in stats", "Speaker separation"]

    @ObservedObject var model: SettingsViewModel
    let query: String

    var body: some View {
        SettingsCard(titles: Self.titles, query: query) {
            SettingRow(.chart, "Meetings in stats", filter: query) {
                AppToggle("Meetings in stats", isOn: $model.settings.meetingsInStats)
            }
            SettingRow(.meetings, "Speaker separation", filter: query) {
                if model.diarizationReady {
                    Text("Installed")
                        .appType(.body)
                        .foregroundStyle(Tok.text2)
                } else {
                    AppButton("Get model", kind: .quiet, height: 28) {
                        Task { await model.downloadDiarizationModel() }
                    }
                }
            }
        }
    }
}

struct PrivacyTab: View {
    nonisolated static let titles = ["Don't store transcripts", "Keep audio",
                                     "Delete audio after", "Delete transcripts",
                                     "Diagnostics", "Licenses"]

    @ObservedObject var model: SettingsViewModel
    let query: String
    @Binding var showNotices: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            SettingsCard(titles: Array(Self.titles.prefix(3)), query: query) {
                SettingRow(.eyeSlash, "Don't store transcripts", filter: query) {
                    AppToggle("Don't store transcripts",
                              isOn: $model.settings.noTranscriptStorage)
                }
                SettingRow(.waveform, "Keep audio", filter: query) {
                    AppToggle("Keep audio", isOn: $model.settings.keepAudio)
                        .disabled(model.settings.noTranscriptStorage)
                }
                SettingRow(.clock, "Delete audio after", filter: query) {
                    Dropdown(selection: $model.settings.audioRetentionDays,
                             options: SettingsViewModel.audioRetentionOptions.map {
                                 .init(SettingsViewModel.audioRetentionLabel(for: $0), value: $0)
                             },
                             label: "Delete audio after")
                }
            }
            SettingsCard(titles: Array(Self.titles.suffix(3)), query: query) {
                SettingRow(.delete, "Delete transcripts", filter: query) {
                    Dropdown(selection: $model.settings.retentionDays,
                             options: SettingsViewModel.retentionOptions.map {
                                 .init(SettingsViewModel.retentionLabel(for: $0), value: $0)
                             },
                             label: "Delete transcripts")
                }
                SettingRow(.diagnostics, "Diagnostics", filter: query) {
                    AppButton("Export", kind: .quiet, height: 28,
                              enabled: model.diagnosticsAvailable, action: exportDiagnostics)
                }
                SettingRow(.licenses, "Licenses", filter: query) {
                    AppButton("View", kind: .quiet, height: 28) { showNotices = true }
                }
            }
        }
    }

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "superflow-diagnostics.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.exportDiagnostics(to: url) }
    }
}

struct AdvancedTab: View {
    nonisolated static let titles = ["Typing speed", "Interactive deadline",
                                     "Background deadline", "Cleanup workers"]

    @ObservedObject var model: SettingsViewModel
    let query: String

    var body: some View {
        SettingsCard(titles: Self.titles, query: query) {
            SettingRow(.keyboard, "Typing speed", filter: query) {
                AppStepper(value: $model.settings.typingWPM,
                           range: SettingsValidation.typingSpeedRange,
                           unit: "wpm", label: "Typing speed")
            }
            SettingRow(.timeSaved, "Interactive deadline", filter: query) {
                AppSlider(value: Binding(
                            get: { Double(model.settings.interactiveDeadlineMs) },
                            set: { model.settings.interactiveDeadlineMs = Int($0.rounded()) }),
                          in: 500...3_000, step: 100, unit: "ms")
            }
            SettingRow(.timeSaved, "Background deadline", filter: query) {
                AppSlider(value: Binding(
                            get: { Double(model.settings.backgroundDeadlineMs) / 1_000 },
                            set: { model.settings.backgroundDeadlineMs = Int(($0 * 1_000).rounded()) }),
                          in: 5...60, step: 1, unit: "s")
            }
            SettingRow(.models, "Cleanup workers", filter: query) {
                AppStepper(value: $model.settings.cleanupWorkers,
                           range: SettingsValidation.cleanupWorkersRange,
                           label: "Cleanup workers")
            }
        }
    }
}
