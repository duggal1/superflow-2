import SuperflowDesignSystem
import SuperflowKernel
import SuperflowUIComponents
import SwiftUI

/// The last input choice before the sandbox: which physical modifier starts a
/// dictation. Only modifiers are offered, because a letter key cannot be held
/// without typing it, and right ⌘ already starts meetings.
struct DictationKeyPicker: View {
    @Binding var selection: DictationKey

    var body: some View {
        HStack(spacing: Space.sm) {
            ForEach(DictationKey.allCases) { key in
                DictationKeyOption(key: key,
                                   selected: key == selection,
                                   action: {
                                       Sounds.play(.clickSoft)
                                       selection = key
                                   })
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

/// One cap in the picker. The selected key is the one that looks pressed, and the
/// blue dot underneath is the only accent on the row.
private struct DictationKeyOption: View {
    let key: DictationKey
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.xs) {
                Text(key.cap)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Tok.keycapText)
                    .frame(width: 84, height: 56)
                    .background(fill, in: .rect(cornerRadius: Radius.field, style: .continuous))
                    .background(alignment: .bottom) {
                        // The lip is a second surface, never a shadow.
                        RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                            .fill(Tok.well)
                            .frame(height: 56)
                            .offset(y: 3)
                    }
                    .padding(.bottom, 3)
                Text(key.caption)
                    .appType(.caption)
                    .foregroundStyle(selected ? Tok.text : Tok.text2)
                    .lineLimit(1)
                Circle()
                    .fill(selected ? Tok.accent : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .clickable()
        .focusStep(.rect(cornerRadius: Radius.field))
        .onHover { hover = $0 }
        .animation(Motion.hoverIn, value: hover)
        .accessibilityLabel("\(key.caption) key")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var fill: Color {
        if selected { return Tok.controlPressed }
        return hover ? Tok.controlHover : Tok.control
    }
}
