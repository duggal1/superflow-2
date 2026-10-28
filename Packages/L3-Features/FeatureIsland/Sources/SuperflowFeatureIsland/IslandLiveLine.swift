import SuperflowDesignSystem
import SuperflowUIComponents
import SwiftUI

/// Newest words on the right, the oldest dissolve out of the left edge.
/// Partials are `text2`; a finalised phrase turns `text`. The caret is the one
/// blue pixel column where the next word lands.
struct LiveLine: View {
    let live: LiveText

    var body: some View {
        HStack(spacing: 8) {
            if let speaker = live.speaker {
                Text(speaker)
                    .appType(.caption)
                    .foregroundStyle(Ramp.blue[4])
                    .lineLimit(1)
                    .fixedSize()
            }
            HStack(spacing: 2) {
                if live.text.isEmpty {
                    Text("Listening")
                        .appType(.reading)
                        .foregroundStyle(Tok.text2)
                } else {
                    Text(String(live.text.suffix(160)).replacingOccurrences(of: "\n", with: " "))
                        .appType(.reading)
                        .foregroundStyle(live.isFinal ? Tok.text : Tok.text2)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Rectangle()
                    .fill(Ramp.blue[4])
                    .frame(width: 2, height: 14)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .clipped()
            .modifier(EdgeFadeLeading(length: 32))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // VoiceOver reads the final transcript, not the churn.
        .accessibilityHidden(true)
    }
}
