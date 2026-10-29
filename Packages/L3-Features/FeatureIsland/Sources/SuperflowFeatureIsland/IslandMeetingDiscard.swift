import SuperflowDesignSystem
import SuperflowUIComponents
import SwiftUI

struct MeetingDiscardCard: View {
    let model: IslandModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Discard meeting?").appType(.label).foregroundStyle(Tok.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, IslandLayout.cardPad)
            .frame(height: model.geometry.band)
            HStack(spacing: 12) {
                Text("Recording continues.").appType(.caption).foregroundStyle(Tok.text2)
                Spacer(minLength: 0)
                AppButton("Keep recording", kind: .secondary, height: IslandLayout.actionHeight) { model.keepMeeting() }
                AppButton("Discard", kind: .sapphire, height: IslandLayout.actionHeight) { model.confirmDiscard() }
            }
            .padding(.horizontal, IslandLayout.cardPad)
            .frame(height: 60)
            Spacer(minLength: 0)
        }
    }
}
