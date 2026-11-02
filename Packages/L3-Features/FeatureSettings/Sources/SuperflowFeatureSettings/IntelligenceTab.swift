import SuperflowDesignSystem
import SuperflowIcons
import SuperflowMeetingIntelligence
import SuperflowUIComponents
import SwiftUI

struct IntelligenceTab: View {
    nonisolated static let titles = ["Reflection API key", "Connection", "Default effort", "Mode", "Trigger key", "Screen awareness", "Custom instructions"]
    let query: String
    @AppStorage("intelligence.effort") private var effort = ReasoningEffort.low.rawValue
    @AppStorage("intelligence.mode") private var mode = MeetingMode.normal.rawValue
    @AppStorage("intelligence.trigger") private var trigger = 59
    @AppStorage("intelligence.screenAware") private var screenAware = false
    @AppStorage("intelligence.customInstructions") private var custom = ""
    @State private var key = ""
    @State private var hasKey = false
    @State private var status = ""
    @State private var testing = false
    @State private var request: Task<Void, Never>?
    private let credentials = ReflectionCredentials()

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            SettingsCard(titles: Array(Self.titles.prefix(2)), query: query) {
                SettingRow(.keyboard, "Reflection API key", filter: query) {
                    AppSecureField(hasKey ? "Replace saved key" : "API key", text: $key)
                    AppButton("Save", kind: .secondary, height: ControlHeight.regular, enabled: !key.isEmpty) { saveKey() }
                }
                SettingRow(.settingMeeting, "Connection", filter: query) {
                    AppButton(testing ? "Testing" : "Test connection", kind: .quiet,
                              height: ControlHeight.regular, enabled: hasKey && !testing) { testConnection() }
                    AppButton("Remove key", kind: .quiet, height: ControlHeight.regular, enabled: hasKey && !testing) {
                        do { try credentials.remove(); hasKey = false; status = "Key removed." }
                        catch { status = "Couldn't remove the key from Keychain." }
                    }
                }
            }
            if !status.isEmpty {
                Text(status).appType(.body).foregroundStyle(Tok.text2).accessibilityLabel(status)
            }
            SettingsCard(titles: Array(Self.titles[2...5]), query: query) {
                SettingRow(.settingCompute, "Default effort", filter: query) {
                    Segmented(selection: $effort, items: ReasoningEffort.allCases.map { .init($0.rawValue.capitalized, value: $0.rawValue) })
                }
                SettingRow(.settingMeeting, "Mode", filter: query) {
                    Dropdown(selection: $mode, options: [
                        .init(value: "normal", title: "Meeting"), .init(value: "codingInterview", title: "Coding interview"),
                        .init(value: "sales", title: "Sales"), .init(value: "custom", title: "Custom")
                    ], label: "Mode")
                }
                SettingRow(.keyboard, "Trigger key", filter: query) {
                    Dropdown(selection: $trigger, options: [.init(value: 59, title: "Left Control"), .init(value: 62, title: "Right Control")], label: "Trigger key")
                }
                SettingRow(.eyeSlash, "Screen awareness", filter: query) {
                    AppToggle("Screen awareness", isOn: $screenAware)
                }
            }
            SettingsCard(titles: [Self.titles[6]], query: query) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Custom instructions").appType(.label).foregroundStyle(Tok.text)
                    AppTextEditor("Custom instructions", text: $custom)
                }.padding(.vertical, Space.sm)
            }
            Text("Reflection receives transcript text and optional screen text. Defaults are saved on this Mac; Island capture integration is pending. Screen OCR is currently unverified.")
                .appType(.body).foregroundStyle(Tok.text2)
        }
        .task {
            do { hasKey = try credentials.load() != nil }
            catch { status = "Couldn't access Keychain." }
        }
        .onDisappear { request?.cancel(); request = nil; testing = false; key = "" }
    }

    private func saveKey() {
        do { try credentials.save(key); key = ""; hasKey = true; status = "Key saved in Keychain." }
        catch { status = "Couldn't save the key in Keychain." }
    }

    private func testConnection() {
        testing = true
        status = "Connecting to Reflection…"
        request = Task { @MainActor in
            defer { testing = false }
            do {
                guard let saved = try credentials.load(),
                      let url = URL(string: "https://api.reflection.ai/openai/v1") else {
                    status = "Save an API key first."; return
                }
                let client = ReflectionClient(apiKey: saved, baseURL: url)
                var received = false
                for try await event in client.stream(system: "Reply briefly.", user: "Confirm this connection test.", effort: ReasoningEffort(rawValue: effort) ?? .low) {
                    try Task.checkCancellation()
                    switch event {
                    case .text(let text): received = received || !text.isEmpty
                    case .finished(let reason, _): status = reason == "stop" && received ? "Connected to Reflection." : "The test did not return a complete answer. Try again."
                    case .thinking: break
                    }
                }
            } catch is CancellationError { }
            catch { if !Task.isCancelled { status = "Connection failed. Check the saved key and network, then try again." } }
        }
    }
}
