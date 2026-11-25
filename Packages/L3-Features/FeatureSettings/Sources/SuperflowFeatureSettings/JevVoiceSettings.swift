import SuperflowDesignSystem
import SuperflowIcons
import SuperflowMeetingIntelligence
import SuperflowUIComponents
import SwiftUI

struct JevVoiceSettings: View {
    let query: String
    @AppStorage("jev.enabled") private var enabled = false
    @State private var key = ""
    @State private var saved = false
    @State private var status = ""
    private let credentials = ReflectionCredentials(service: "Superflow.Jev")

    var body: some View {
        SettingsCard(titles: ["Jev voice commands", "Jev API key"], query: query) {
            SettingRow(.keyboard, "Jev voice commands", filter: query) {
                AppToggle("Left Control", isOn: $enabled, enabled: saved)
            }
            SettingRow(.keyboard, "Jev API key", filter: query) {
                AppSecureField(saved ? "Replace saved key" : "TypeSafe API key", text: $key)
                AppButton("Save", kind: .secondary, height: ControlHeight.regular, enabled: !key.isEmpty) {
                    do { try credentials.save(key); key = ""; saved = true; status = "Key saved." }
                    catch { status = "Could not save key." }
                }
                if saved {
                    AppButton("Remove", kind: .quiet, height: ControlHeight.regular) {
                        do { try credentials.remove(); saved = false; enabled = false; status = "Key removed." }
                        catch { status = "Could not remove key." }
                    }
                }
            }
            Text("Tap left Control to record, then tap again to run. Only command text is sent to TypeSafe. Normal dictation stays local.")
                .appType(.caption).foregroundStyle(Tok.text2)
                .padding(.vertical, Space.xs)
            if !status.isEmpty { Text(status).appType(.caption).foregroundStyle(Tok.text2) }
        }
        .task { saved = await Task.detached { [credentials] in credentials.exists() }.value }
        .onDisappear { key = "" }
    }
}
