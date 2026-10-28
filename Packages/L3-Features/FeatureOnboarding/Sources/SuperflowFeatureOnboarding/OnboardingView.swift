import AppKit
import SuperflowDesignSystem
import SuperflowIcons
import SuperflowKernel
import SuperflowPorts
import SuperflowUIComponents
import SwiftUI

public struct OnboardingView: View {
    @ObservedObject private var model: OnboardingViewModel
    /// Field progress, in whole steps, run once at launch.
    @State private var fieldReveal: CGFloat = 0
    @State private var bloom = BloomModel()
    /// The last step closes the ring, grows the disc, then flies it to the slot.
    @State private var collapse: CGFloat = 0
    @State private var discGrow: Double = 0
    @State private var discTravel: Double = 0
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
                        reveal: fieldReveal,
                        backAction: model.step.previous == nil ? nil : { model.back() },
                        skipTitle: skipTitle,
                        skipAction: skipTitle == nil ? nil : { Task { await model.skipCurrent() } }) {
            Task { await model.performPrimaryAction() }
        } content: {
            stepContent
        }
        .overlay { ToastHost(center: model.toast) }
        .environment(bloom)
        .focusEffectDisabled()
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
            switch step {
            case .done:
                Task { await closeField() }
            case .welcome:
                resetField()
                pressKeyOnce()
            default:
                resetField()
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

    /// 1 — one line of body, one key that presses once, the privacy line stated once.
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Speak. It types.").displayStyle(size: TypeScale.displaySize).clearsPixels()
            FnDemo()
            Text("Everything runs on this Mac. No account, no cloud, no telemetry.")
                .appType(.body).foregroundStyle(Tok.text2).clearsPixels()
        }
    }

    /// 2 — four rows in one card. Only the first row that still needs action carries
    /// the accent, so the footer's Continue stays the accent control.
    private var permissions: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            heading
                .clearsPixels()
                .reveal(0)
            VStack(spacing: Space.md) {
                ForEach(OnboardingViewModel.requiredPermissions, id: \.self) { permission in
                    OnboardingPresentation.PermissionRow(model: model, permission: permission)
                }
                OnboardingPresentation.GlobeRow(model: model)
            }
            .padding(Space.cardPaddingDense)
            .background(Tok.surface, in: .rect(cornerRadius: Radius.card, style: .continuous))
            .contrastStroke(radius: Radius.card)
            .reveal(1)
            if model.permissionsSkipped {
                StatusNote(text: "Superflow asks again the first time you dictate.")
                    .reveal(2)
            }
        }
    }

    /// 3 — two rows, one button. Progress is the row fill and the detail line, never
    /// a bar, and the detail line is never printed twice.
    private var models: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            heading
                .clearsPixels()
                .reveal(0)
            VStack(spacing: Space.md) {
                DownloadCard(title: model.speechName,
                             detail: model.speechDetail,
                             state: model.speechReady ? .installed : (model.isDownloadingSpeech ? .downloading(model.speechProgress) : (model.speechError.map { .failed($0) } ?? .idle)),
                             totalBytes: model.speechTotalBytes) {
                    NVIDIAIcon(size: 24)
                } trailing: {
                    speechStatus
                }
                if model.cleanupAvailable {
                    DownloadCard(title: "S1-mini cleanup",
                                 detail: model.cleanupDetail,
                                 state: cleanupIsDownloading ? .downloading(model.cleanupProgress) : (model.cleanupWanted ? .idle : .idle),
                                 totalBytes: model.cleanupTotalBytes) {
                        S1MiniMark(size: 24)
                    } trailing: {
                        SettingToggle("Download S1-mini", isOn: Binding(
                            get: { model.cleanupWanted },
                            set: { value in Task { await model.setCleanupWanted(value) } }))
                    }
                }
            }
            .reveal(1)
            if let error = model.speechError {
                NoticeBanner("The speech model download failed: \(error)", tone: .rose,
                             actionTitle: "Try again") {
                    Task { await model.downloadSpeech() }
                }
                .reveal(2)
            }
            if let error = model.cleanupError {
                NoticeBanner("The cleanup download failed: \(error)", tone: .rose,
                             actionTitle: "Try again") {
                    Task { await model.downloadCleanupModel() }
                }
                .reveal(3)
            }
        }
    }

    private var cleanupIsDownloading: Bool {
        model.cleanupWanted && (model.cleanupProgress ?? 1) < 1
    }

    /// 4 — the title ends in the pixel disc, the ring has closed, and the sandbox
    /// field appears only when it can actually work.
    private var done: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            heading(stop: true)
                .clearsPixels()
                .reveal(0)
            VStack(alignment: .leading, spacing: Space.md) {
                if model.practiceReady {
                    PracticeField("Hold fn and say something", text: $model.practiceText)
                    // One mic test for the whole app: the same component Settings uses.
                    MicTestView()
                } else {
                    Text("Grant the microphone and finish the download to try it here.")
                        .appType(.body)
                        .foregroundStyle(Tok.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .reveal(1)
            if case .failed(let message) = model.practiceState {
                NoticeBanner("The test recording failed: \(message)", tone: .rose)
                    .reveal(2)
            }
        }
    }

    private var heading: some View {
        heading(stop: false)
    }

    private func heading(stop: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .lastTextBaseline, spacing: Space.xs) {
                Text(model.step.title)
                    .displayStyle(size: TypeScale.displaySize)
                if stop {
                    // The dot is the disc that flew here, drawn by the field over this
                    // measured slot. One dot exists, not two.
                    Color.clear
                        .frame(width: PixelDiscFlight.slotSide,
                               height: PixelDiscFlight.slotSide)
                        .pixelSlot()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if let subtitle = model.step.subtitle {
                Text(subtitle)
                    .appType(.reading)
                    .foregroundStyle(Tok.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The row fill and the detail line already carry progress, so the trailing
    /// slot only ever adds information.
    @ViewBuilder
    private var speechStatus: some View {
        if model.speechReady {
            Badge("Ready", variant: .green, size: .sm)
        } else if model.speechError != nil {
            Badge("Failed", variant: .rose, size: .sm)
        } else if !model.isDownloadingSpeech {
            Badge("Required", variant: .neutral, size: .sm)
        }
    }

    private var skipTitle: String? {
        model.step == .permissions && !model.permissionsGranted ? "Set up later" : nil
    }

    // MARK: motion

    /// The reveal runs in whole steps, once, from the field's own progress value.
    private func revealField() async {
        guard !reduceMotion else {
            fieldReveal = 1
            return
        }
        let steps = 14
        for value in 1...steps {
            try? await Task.sleep(for: .milliseconds(1300 / steps))
            fieldReveal = CGFloat(value) / CGFloat(steps)
        }
    }

    /// One chain, one progress value at a time: ring closes, disc grows in at the
    /// centre, disc travels to the slot. No second animation runs on top (§8.6, §8.7).
    private func closeField() async {
        guard !reduceMotion else {
            collapse = 1
            discGrow = 1
            discTravel = 1
            return
        }
        for value in 1...6 {
            try? await Task.sleep(for: .milliseconds(60))
            collapse = CGFloat(value) / 6
        }
        for value in 1...5 {
            try? await Task.sleep(for: .milliseconds(45))
            discGrow = Double(value) / 5
        }
        for value in 1...14 {
            try? await Task.sleep(for: .milliseconds(26))
            discTravel = Double(value) / 14
        }
    }

    /// Going back reopens the field and puts the disc away with it.
    private func resetField() {
        collapse = 0
        discGrow = 0
        discTravel = 0
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
