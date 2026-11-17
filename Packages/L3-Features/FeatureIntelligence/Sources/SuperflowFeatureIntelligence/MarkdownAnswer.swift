import AppKit
import SuperflowDesignSystem
import SuperflowUIComponents
import SwiftUI

/// Renders the answer as selectable prose plus fenced code blocks, each with its
/// own Copy action. Plain text without fences renders as prose, byte for byte.
struct MarkdownAnswer: View {
    let text: String

    private enum Block: Equatable {
        case prose(String)
        case code(String)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var prose = ""
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                let fence = lines[index].trimmingCharacters(in: .whitespaces)
                if !prose.isEmpty { result.append(.prose(prose)); prose = "" }
                index += 1
                var code: [String] = []
                while index < lines.count,
                      !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[index]); index += 1
                }
                if index < lines.count { index += 1 }
                result.append(.code(code.joined(separator: "\n")))
            } else {
                if !prose.isEmpty { prose += "\n" }
                prose += lines[index]
                index += 1
            }
        }
        if !prose.isEmpty { result.append(.prose(prose)) }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .prose(let prose):
                    Text(prose)
                        .appType(.reading)
                        .foregroundStyle(Tok.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                case .code(let code):
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(code)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Tok.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        HStack {
                            Spacer(minLength: 0)
                            AppButton("Copy code", glyph: .copy, kind: .quiet, height: 24) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(code, forType: .string)
                            }
                        }
                    }
                    .padding(Space.sm)
                    .background(Tok.control, in: .rect(cornerRadius: Radius.field, style: .continuous))
                }
            }
        }
    }
}
