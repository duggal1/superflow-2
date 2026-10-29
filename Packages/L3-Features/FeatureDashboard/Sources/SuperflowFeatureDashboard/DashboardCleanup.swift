import SuperflowDesignSystem
import SuperflowIcons
import SuperflowUIComponents
import SwiftUI

public enum CleanupPhase: Sendable {
    case said, typed
}

/// One word on the line, in both versions. `raw == nil` means cleanup inserted it;
/// `clean == nil` means cleanup deleted it.
public struct CleanupToken: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable {
        case keep, restyle, replace, remove, insert
    }

    public let id: Int
    public let raw: String?
    public let clean: String?

    public init(id: Int, raw: String?, clean: String?) {
        self.id = id
        self.raw = raw
        self.clean = clean
    }

    public var kind: Kind {
        guard let raw else { return .insert }
        guard let clean else { return .remove }
        if raw == clean { return .keep }
        return WordDiff.norm(raw) == WordDiff.norm(clean) ? .restyle : .replace
    }

    public var isMarked: Bool { kind == .remove || kind == .replace }

    public func text(in phase: CleanupPhase) -> String? {
        phase == .said ? raw : clean
    }
}

public enum WordDiff {
    public static func norm(_ value: String) -> String {
        value.lowercased()
            .trimmingCharacters(in: .punctuationCharacters.union(.symbols))
    }

    /// Longest-common-subsequence on normalized words. Unmatched runs are paired in
    /// order: "twelve thousand dollars" against "$12,000," gives one replacement and
    /// two removals.
    public static func tokens(raw: String, clean: String) -> [CleanupToken] {
        let a = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        let b = clean.split(whereSeparator: \.isWhitespace).map(String.init)
        let na = a.map(norm)
        let nb = b.map(norm)

        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        if !a.isEmpty, !b.isEmpty {
            for i in stride(from: a.count - 1, through: 0, by: -1) {
                for j in stride(from: b.count - 1, through: 0, by: -1) {
                    table[i][j] = na[i] == nb[j]
                        ? table[i + 1][j + 1] + 1
                        : max(table[i + 1][j], table[i][j + 1])
                }
            }
        }

        var out: [CleanupToken] = []
        var id = 0
        var i = 0
        var j = 0
        var runA: [String] = []
        var runB: [String] = []

        func flush() {
            for k in 0..<max(runA.count, runB.count) {
                out.append(CleanupToken(id: id,
                                        raw: k < runA.count ? runA[k] : nil,
                                        clean: k < runB.count ? runB[k] : nil))
                id += 1
            }
            runA.removeAll()
            runB.removeAll()
        }

        while i < a.count || j < b.count {
            if i < a.count, j < b.count, na[i] == nb[j] {
                flush()
                out.append(CleanupToken(id: id, raw: a[i], clean: b[j]))
                id += 1
                i += 1
                j += 1
            } else if j >= b.count || (i < a.count && table[i + 1][j] >= table[i][j + 1]) {
                runA.append(a[i])
                i += 1
            } else {
                runB.append(b[j])
                j += 1
            }
        }
        flush()
        return out
    }
}

/// Words wrap like prose. Removing a token animates the others into place.
public struct FlowLayout: SwiftUI.Layout {
    public var spacing: CGFloat
    public var lineSpacing: CGFloat

    public init(spacing: CGFloat = 0, lineSpacing: CGFloat = 6) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: SwiftUI.Layout.Subviews,
                             cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + lineSpacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                              subviews: SwiftUI.Layout.Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + lineSpacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

public struct CleanupLine: View {
    private let tokens: [CleanupToken]
    private let phase: CleanupPhase

    public init(tokens: [CleanupToken], phase: CleanupPhase) {
        self.tokens = tokens
        self.phase = phase
    }

    public var body: some View {
        FlowLayout(spacing: -2, lineSpacing: 6) {
            ForEach(tokens) { token in
                if let shown = token.text(in: phase) {
                    let marked = phase == .said && token.isMarked
                    Text(shown)
                        .appType(.reading)
                        .foregroundStyle(phase == .typed || marked ? Tok.text : Tok.text2)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 2)
                        .background(marked ? Tok.accentSoft : .clear,
                                    in: .rect(cornerRadius: Radius.chip, style: .continuous))
                        .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: Space.proseMaxWidth, alignment: .leading)
    }
}

/// The component under the 12-month graph: the newest dictation as a picture you
/// can drag to hear, and as the sentence the model cleaned. It replaces the old
/// text-only card, so the audio component and the cleanup line live together.
///
/// The keycap is a control, not a drawing: clicking it plays the hold → release →
/// clean run, and it goes down for real while the physical fn key is held.
