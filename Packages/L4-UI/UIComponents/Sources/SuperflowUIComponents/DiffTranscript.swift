import SuperflowDesignSystem
import SwiftUI

public struct DiffTranscript: View {
    private enum Variant: Hashable { case cleaned, raw }
    private struct DiffKey: Hashable { let raw: String; let cleaned: String }
    private struct SweepKey: Hashable { let raw: Bool; let ready: Bool }

    private let raw: String
    private let cleaned: String
    private let externalRaw: Binding<Bool>?
    private let onCard: Bool
    @State private var mode: Variant = .cleaned
    @State private var diff: TranscriptDiff.Result?
    @State private var reveal = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(raw: String, cleaned: String, showRaw: Binding<Bool>? = nil, onCard: Bool = true) {
        self.raw = raw
        self.cleaned = cleaned
        self.externalRaw = showRaw
        self.onCard = onCard
    }

    public var body: some View {
        let showRaw = (externalRaw?.wrappedValue ?? (mode == .raw)) && !raw.isEmpty
        VStack(alignment: .leading, spacing: 20) {
            if !raw.isEmpty {
                HStack(spacing: 20) {
                    Segmented(selection: Binding<Variant>(get: { showRaw ? .raw : .cleaned }, set: { next in
                        if let externalRaw { externalRaw.wrappedValue = next == .raw }
                        else { mode = next }
                    }), items: [.init("Cleaned", value: .cleaned), .init("Raw", value: .raw)], onCard: onCard)
                    if let diff {
                        swatch(Tok.diffStrong, count: showRaw ? diff.removed : diff.rewritten,
                               label: showRaw ? "removed" : "rewritten")
                        swatch(Tok.diffSoft, count: diff.polished, label: "polished")
                        Text("\(Int((diff.ratio * 100).rounded()))% edited")
                            .appType(.caption).monospacedDigit().foregroundStyle(Tok.text2)
                    }
                }
            }
            Text(shown(showRaw)).appType(.reading).lineSpacing(6).foregroundStyle(Tok.text)
                .textSelection(.enabled).frame(maxWidth: 720, alignment: .leading)
            if let diff, !diff.hunks.isEmpty { changes(diff.hunks) }
        }
        .task(id: DiffKey(raw: raw, cleaned: cleaned)) {
            diff = nil
            guard !raw.isEmpty else { return }
            let result = await Task.detached(priority: .userInitiated) {
                TranscriptDiff.compute(raw: raw, cleaned: cleaned)
            }.value
            guard !Task.isCancelled else { return }
            diff = result
        }
        .task(id: SweepKey(raw: showRaw, ready: diff != nil)) { await sweep(showRaw) }
    }

    private func shown(_ showRaw: Bool) -> AttributedString {
        guard let diff else { return AttributedString(showRaw ? raw : cleaned) }
        let tokens = showRaw ? diff.raw : diff.cleaned
        var result = AttributedString()
        for (index, token) in tokens.enumerated() {
            var word = AttributedString(token.text)
            if index < reveal && token.level > 0 {
                word.backgroundColor = token.level == 2 ? Tok.diffStrong : Tok.diffSoft
                word.foregroundColor = token.level == 2 ? Tok.diffInk : Tok.text
            }
            result += word
            result += AttributedString(token.gap)
        }
        return result
    }

    private func sweep(_ showRaw: Bool) async {
        guard let diff else { reveal = 0; return }
        let count = showRaw ? diff.raw.count : diff.cleaned.count
        guard !reduceMotion else { reveal = count; return }
        reveal = 0
        for step in 1...14 {
            do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
            reveal = count * step / 14
        }
    }

    private func swatch(_ color: Color, count: Int, label: String) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(color).frame(width: 8, height: 8)
            Text("\(count)").monospacedDigit().foregroundStyle(Tok.text)
            Text(label).foregroundStyle(Tok.text2)
        }
        .appType(.caption)
        .accessibilityElement(children: .combine)
    }

    private func changes(_ hunks: [TranscriptDiff.Hunk]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What changed").appType(.caption).foregroundStyle(Tok.text2)
            ForEach(Array(hunks.prefix(4).enumerated()), id: \.offset) { _, hunk in
                HStack(spacing: 10) {
                    Text(hunk.from.isEmpty ? "added" : hunk.from).strikethrough(!hunk.from.isEmpty)
                        .foregroundStyle(Tok.text2).lineLimit(1)
                    PixelMark(rows: ["....#..", ".....#.", "#######", ".....#.", "....#.."], cell: 1, color: Ramp.blue[4])
                    Text(hunk.to.isEmpty ? "removed" : hunk.to).foregroundStyle(Tok.text).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .appType(.body).frame(height: 24)
            }
            if hunks.count > 4 { Text("+\(hunks.count - 4) more").appType(.caption).foregroundStyle(Tok.text2) }
        }
    }
}
