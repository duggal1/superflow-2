import SuperflowDesignSystem
import SwiftUI

public struct NotchedRect: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let n = min(2, rect.width / 3, rect.height / 3)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + n, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - n, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - n, y: rect.minY + n))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + n))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - n))
        path.addLine(to: CGPoint(x: rect.maxX - n, y: rect.maxY - n))
        path.addLine(to: CGPoint(x: rect.maxX - n, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + n, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + n, y: rect.maxY - n))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - n))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + n))
        path.addLine(to: CGPoint(x: rect.minX + n, y: rect.minY + n))
        path.closeSubpath()
        return path
    }
}

public struct PixelBadge: View {
    public enum Kind { case active, installed, failed, required, caution }
    private let title: String
    private let kind: Kind

    public init(_ title: String, kind: Kind) {
        self.title = title
        self.kind = kind
    }

    private var rows: [String] {
        switch kind {
        case .active: ["..##..", ".####.", "######", "######", ".####.", "..##.."]
        case .installed: ["....#", "...#.", "#.#..", ".#..."]
        case .failed: ["#...#", ".#.#.", "..#..", ".#.#.", "#...#"]
        case .required, .caution: [".#.", ".#.", ".#.", "...", ".#."]
        }
    }

    private var ink: Color {
        switch kind {
        case .active: Tok.accentText
        case .failed: Tok.statusBad
        case .installed, .required, .caution: Tok.text2
        }
    }

    public var body: some View {
        HStack(spacing: 6) {
            PixelMark(rows: rows, cell: 1, color: ink)
            Text(title).appType(.caption).foregroundStyle(ink).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 8).frame(height: 20)
        .background(NotchedRect().fill(kind == .active ? Tok.accentSoft : Tok.control,
                                       style: FillStyle(antialiased: false)))
        .accessibilityElement(children: .combine)
    }
}

public struct PixelMark: View {
    private let rows: [String]
    private let cell: CGFloat
    private let color: Color

    public init(rows: [String], cell: CGFloat, color: Color) {
        self.rows = rows
        self.cell = cell
        self.color = color
    }

    public var body: some View {
        Canvas { context, _ in
            for (y, row) in rows.enumerated() {
                for (x, value) in row.enumerated() where value == "#" {
                    context.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell,
                                             width: cell, height: cell)),
                                 with: .color(color), style: FillStyle(antialiased: false))
                }
            }
        }
        .frame(width: CGFloat(rows.map(\.count).max() ?? 0) * cell, height: CGFloat(rows.count) * cell)
        .accessibilityHidden(true)
    }
}
