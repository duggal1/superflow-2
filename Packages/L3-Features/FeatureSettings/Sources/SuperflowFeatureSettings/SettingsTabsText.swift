import AppKit
import SuperflowDesignSystem
import SuperflowKernel
import SuperflowUIComponents
import SwiftUI
import UniformTypeIdentifiers

struct TextTab: View {
    nonisolated static let titles = ["Harper grammar pass", "Spoken commands", "Large numbers",
                         "Zero through nine as words", "Minimum block", "Preferred maximum",
                         "Hard maximum", "Separate blocks with", "Capitalize sentence starts",
                         "Add a final period", "Leave a trailing space"]

    @ObservedObject var model: SettingsViewModel
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SettingsCard(titles: Array(Self.titles.prefix(3)), query: query) {
                SettingRow("Harper grammar pass", filter: query) {
                    AppToggle("Harper grammar pass", isOn: $model.settings.harperEnabled)
                }
                SettingRow("Spoken commands", filter: query) {
                    AppToggle("Spoken commands", isOn: $model.settings.commandsEnabled)
                }
                SettingRow("Large numbers", filter: query) {
                    Segmented(selection: $model.settings.numberStyle,
                              items: LargeNumberStyle.allCases.map { .init($0.label, value: $0) })
                }
            }
            SettingsCard(titles: Array(Self.titles[3...6]), query: query) {
                SettingRow("Zero through nine as words", filter: query) {
                    AppToggle("Zero through nine as words",
                              isOn: $model.settings.spellOutSmallNumbers)
                }
                SettingRow("Minimum block", filter: query) {
                    AppStepper(value: $model.settings.lineFormat.minWords,
                               in: SettingsValidation.lineWordRange, unit: "words")
                }
                SettingRow("Preferred maximum", filter: query) {
                    AppStepper(value: $model.settings.lineFormat.preferredMax,
                               in: SettingsValidation.lineWordRange, unit: "words")
                }
                SettingRow("Hard maximum", filter: query) {
                    AppStepper(value: $model.settings.lineFormat.hardMax,
                               in: SettingsValidation.lineWordRange, unit: "words")
                }
            }
            SettingsCard(titles: Array(Self.titles.suffix(4)), query: query) {
                SettingRow("Separate blocks with", filter: query) {
                    Segmented(selection: $model.settings.lineFormat.breakStyle,
                              items: BreakStyle.allCases.map { .init($0.label, value: $0) })
                }
                SettingRow("Capitalize sentence starts", filter: query) {
                    AppToggle("Capitalize sentence starts",
                              isOn: $model.settings.lineFormat.capitalize)
                }
                SettingRow("Add a final period", filter: query) {
                    AppToggle("Add a final period", isOn: $model.settings.lineFormat.finalPeriod)
                }
                SettingRow("Leave a trailing space", filter: query) {
                    AppToggle("Leave a trailing space",
                              isOn: $model.settings.lineFormat.trailingSpace)
                }
            }
        }
    }
}

struct MeetingsTab: View {
    nonisolated static let titles = ["Meetings in stats", "Speaker separation"]

    @ObservedObject var model: SettingsViewModel
    let query: String

    var body: some View {
        SettingsCard(titles: Self.titles, query: query) {
            SettingRow("Meetings in stats", filter: query) {
                AppToggle("Meetings in stats", isOn: $model.settings.meetingsInStats)
            }
            SettingRow("Speaker separation", filter: query) {
                if model.diarizationReady {
                    Badge("Installed", variant: .green, size: .sm)
                } else {
                    HStack(spacing: Space.xs) {
                        if model.isDownloadingDiarization {
                            Text(progressLabel)
                                .font(.system(size: 12))
                                .monospacedDigit()
                                .foregroundStyle(Tok.text2)
                        }
                        AppButton("Download", kind: .quiet, height: ControlHeight.small,
                                  enabled: !model.isDownloadingDiarization) {
                            Task { await model.downloadDiarizationModel() }
                        }
                    }
                }
            }
        }
    }

    private var progressLabel: String {
        guard let progress = model.diarizationProgress else { return "Downloading…" }
        return "\(Int(progress * 100))%"
    }
}

struct PrivacyTab: View {
    nonisolated static let titles = ["Don't store transcripts", "Keep audio journals",
                         "Delete transcripts", "Diagnostics", "Licenses"]

    @ObservedObject var model: SettingsViewModel
    let query: String
    @Binding var showNotices: Bool

    var body: some View {
        SettingsCard(titles: Self.titles, query: query) {
            SettingRow("Don't store transcripts", filter: query) {
                AppToggle("Don't store transcripts",
                          isOn: $model.settings.noTranscriptStorage)
            }
            SettingRow("Keep audio journals", filter: query) {
                AppToggle("Keep audio journals", isOn: $model.settings.keepJournals)
            }
            SettingRow("Delete transcripts", filter: query) {
                Dropdown(selection: $model.settings.retentionDays,
                         options: SettingsViewModel.retentionOptions.map {
                             Dropdown.Option(SettingsViewModel.retentionLabel(for: $0), value: $0)
                         },
                         label: "Delete transcripts")
            }
            SettingRow("Diagnostics", filter: query) {
                AppButton("Export", kind: .quiet, height: ControlHeight.small,
                          enabled: model.diagnosticsAvailable, action: exportDiagnostics)
            }
            SettingRow("Licenses", filter: query) {
                AppButton("View", kind: .quiet, height: ControlHeight.small) {
                    showNotices = true
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
    nonisolated static let titles = ["Interactive deadline", "Background deadline", "Cleanup workers"]

    @ObservedObject var model: SettingsViewModel
    let query: String

    var body: some View {
        SettingsCard(titles: Self.titles, query: query) {
            SettingRow("Interactive deadline", filter: query) {
                TimingSlider(value: Binding(
                                get: { Double(model.settings.interactiveDeadlineMs) },
                                set: { model.settings.interactiveDeadlineMs = Int($0.rounded()) }),
                             in: 500...3_000, step: 100, unit: "ms")
            }
            SettingRow("Background deadline", filter: query) {
                TimingSlider(value: Binding(
                                get: { Double(model.settings.backgroundDeadlineMs) / 1_000 },
                                set: { model.settings.backgroundDeadlineMs = Int(($0 * 1_000).rounded()) }),
                             in: 5...60, step: 1, unit: "s")
            }
            SettingRow("Cleanup workers", filter: query) {
                AppStepper(value: $model.settings.cleanupWorkers,
                           in: SettingsValidation.cleanupWorkersRange)
            }
        }
    }
}
