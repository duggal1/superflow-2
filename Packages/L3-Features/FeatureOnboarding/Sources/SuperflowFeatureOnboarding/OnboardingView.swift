import AppKit
import SuperflowDesignSystem
import SuperflowIcons
import SuperflowKernel
import SuperflowPorts
import SuperflowUIComponents
import SwiftUI

public struct OnboardingView: View {
    @ObservedObject private var model: OnboardingViewModel
    @State private var reveal: CGFloat = 0
    @State private var collapse: CGFloat = 0
    @State private var keyDown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: OnboardingViewModel) {
        self.model = model
    }

    public var body: some View {
        OnboardingShell(step: model.step.index,
                        count: model.step.count,
                        primaryTitle: model.primaryTitle,
                        primaryEnabled: model.primaryEnabled,
                        skipTitle: skipTitle,
                        reveal: reveal,
                        collapse: collapse,
                        backAction: model.step.previous == nil ? nil : { model.back() },
                        skipAction: skipTitle == nil ? nil : { Task { await model.skipCurrent() } }) {
            Task { await model.performPrimaryAction() }
        } content: {
            stepContent
        }
        .overlay { ToastHost(center: model.toast) }
        .task {
            await model.load()
            await revealField()
        }
        .task {
            // The Globe key and the permission rows are both outside the app, so they
            // are re-read whenever the user comes back to it.
            for await _ in NotificationCenter.default.notifications(
                named: NSApplication.didBecomeActiveNotification) {
                await model.refreshPermissions()
                await model.refreshGlobeAction()
            }
        }
        .onChange(of: model.step) { _, step in
            if step == .done {
                Task { await closeField() }
            }
        }
        .onAppear { pressKeyOnce() }
    }

    // MARK: steps

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .welcome: welcome
        case .permissions: permissions
        case .models: models
        case .done: done
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            heading
            HStack(spacing: Space.sm) {
                KeyCap("fn", down: keyDown)
                Text("Hold fn and speak")
                    .font(Typography.body)
                    .foregroundStyle(Tok.text2)
            }
            Text("Everything runs on this Mac. No account, no cloud, no telemetry.")
                .font(Typography.secondary)
                .foregroundStyle(Tok.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            heading
            VStack(spacing: Space.md) {
                ForEach(Array(OnboardingViewModel.requiredPermissions.enumerated()),
                        id: \.element) { index, permission in
                    OnboardingPresentation.PermissionRow(
                        model: model, permission: permission,
                        accent: index == firstPendingIndex)
                }
                OnboardingPresentation.GlobeRow(model: model)
            }
            .padding(Space.cardPaddingDense)
            .background(Tok.surface, in: .rect(cornerRadius: Radius.card, style: .continuous))
            .contrastStroke(radius: Radius.card)
            if model.permissionsSkipped {
                NoticeBanner("Superflow will ask again the first time you dictate.",
                             tone: .orange)
            }
        }
    }

    private var models: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            heading
            ProgressRow(title: model.speechName, detail: model.speechDetail,
                        progress: model.speechProgress) {
                NVIDIAIcon(size: 20, tint: Tok.text)
            } trailing: {
                state(speechReady: model.speechReady, error: model.speechError)
            }
            if model.cleanupAvailable {
                ProgressRow(title: "S1-mini cleanup", detail: model.cleanupDetail,
                            progress: model.cleanupProgress) {
                    Icon(.cleanup, size: 16, tint: Tok.text)
                } trailing: {
                    SettingToggle("Download cleanup", isOn: Binding(
                        get: { model.cleanupWanted },
                        set: { value in Task { await model.setCleanupWanted(value) } }))
                }
            }
            if let error = model.speechError {
                NoticeBanner("The speech model download failed: \(error)", tone: .rose,
                             actionTitle: "Try again") {
                    Task { await model.downloadSpeech() }
                }
            }
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(alignment: .lastTextBaseline, spacing: Space.xs) {
                    Text(model.step.title)
                        .displayStyle(size: TypeScale.displaySize)
                    PixelStop(cells: 7, cell: 2)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                if let subtitle = model.step.subtitle {
                    Text(subtitle)
                        .font(Typography.body)
                        .foregroundStyle(Tok.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if model.practiceReady {
                PracticeField("Hold fn and say something", text: $model.practiceText)
                HStack(spacing: Space.xs) {
                    if model.isListening {
                        AppButton("Cancel", kind: .quiet) { model.cancelPractice() }
                    } else {
                        AppButton("Record a test", kind: .quiet) {
                            Task { await model.startPractice() }
                        }
                    }
                    Spacer(minLength: Space.md)
                    if model.practiceState == .done {
                        Badge("Captured", variant: .green, size: .sm)
                    }
                }
                if case .failed(let message) = model.practiceState {
                    NoticeBanner("The test recording failed: \(message)", tone: .rose)
                }
            } else {
                Text("Grant the microphone and finish the download to try it here.")
                    .font(Typography.secondary)
                    .foregroundStyle(Tok.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(model.step.title)
                .displayStyle(size: TypeScale.displaySize)
                .accessibilityAddTraits(.isHeader)
            if let subtitle = model.step.subtitle {
                Text(subtitle)
                    .font(Typography.body)
                    .foregroundStyle(Tok.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func state(speechReady: Bool, error: String?) -> some View {
        if speechReady {
            Badge("Ready", variant: .green, size: .sm)
        } else if error != nil {
            Badge("Failed", variant: .rose, size: .sm)
        } else if model.isDownloadingSpeech {
            Text(model.speechDetail)
                .font(Typography.secondaryMedium)
                .monospacedDigit()
                .foregroundStyle(Tok.text)
        } else {
            Badge("Required", variant: .neutral, size: .sm)
        }
    }

    private var skipTitle: String? {
        model.step == .permissions && !model.permissionsGranted ? "Set up later" : nil
    }

    private var firstPendingIndex: Int? {
        OnboardingViewModel.requiredPermissions.firstIndex {
            model.status(for: $0) == .notDetermined
        }
    }

    // MARK: motion

    /// The reveal runs in whole steps, once, from the field's own progress value.
    private func revealField() async {
        guard !reduceMotion else {
            reveal = 1
            return
        }
        let steps = 14
        for value in 1...steps {
            try? await Task.sleep(for: .milliseconds(1300 / steps))
            reveal = CGFloat(value) / CGFloat(steps)
        }
    }

    /// The last step closes the ring: no second animation on top of it.
    private func closeField() async {
        guard !reduceMotion else {
            collapse = 1
            return
        }
        for value in 1...6 {
            try? await Task.sleep(for: .milliseconds(60))
            collapse = CGFloat(value) / 6
        }
    }

    private func pressKeyOnce() {
        guard !reduceMotion else {
            keyDown = false
            return
        }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            keyDown = true
            try? await Task.sleep(for: .milliseconds(260))
            keyDown = false
        }
    }
}
