import SuperflowDesignSystem
import SuperflowIcons
import SuperflowKernel
import SuperflowTextPipeline
import SuperflowUIComponents
import SwiftUI

/// One rule: fixed trigger column, flexible result with an edge fade, status
/// badge in its own frame. No text length can move or clip the badge.
struct KnowledgeRowSpec: Identifiable {
    let id: String
    let trigger: String
    let result: String
    let badge: String?
    let variant: BadgeVariant
    let dimmed: Bool
    let open: () -> Void
    let delete: () -> Void
}

struct KnowledgeRow: View {
    let spec: KnowledgeRowSpec

    var body: some View {
        RowButton("\(spec.trigger), becomes \(spec.result)", height: 44) {
            spec.open()
        } content: {
            HStack(spacing: Space.sm) {
                Text(spec.trigger)
                    .appType(.label).foregroundStyle(spec.dimmed ? Tok.text2 : Tok.text)
                    .lineLimit(1).frame(width: 168, alignment: .leading)
                    .modifier(TextFade(length: 12))
                IconView(.arrow, size: 12, tint: Tok.text2).frame(width: 12)
                Text(spec.result)
                    .appType(.body).foregroundStyle(spec.dimmed ? Tok.text2 : Tok.text)
                    .lineLimit(1).frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .modifier(TextFade(length: 24)).textSelection(.enabled)
                if let badge = spec.badge {
                    Badge(badge, variant: spec.variant, size: .sm).fixedSize()
                }
            }
            .padding(.horizontal, Space.sm)
        }
        .contextMenu { Button("Delete", role: .destructive, action: spec.delete) }
    }
}

/// Candidate text flexes; the control cluster is fixed and gets layout priority.
struct LearningRow: View {
    let candidate: LearningCandidate
    let onConfirm: () -> Void
    let onReject: () -> Void
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: Space.sm) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("\(candidate.heard) → \(candidate.canonical)")
                    .appType(.body).foregroundStyle(Tok.text).lineLimit(1)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .modifier(TextFade(length: 24)).textSelection(.enabled)
                Text(candidate.appScope ?? "All apps")
                    .appType(.caption).foregroundStyle(Tok.text2).lineLimit(1)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Space.xs) {
                if candidate.state == .suggested {
                    AppButton("Confirm", kind: .secondary, height: ControlHeight.regular, action: onConfirm)
                    AppButton("Reject", kind: .quiet, height: ControlHeight.regular, action: onReject)
                } else {
                    Badge("Added", variant: .green, size: .sm)
                    AppButton("Undo", kind: .quiet, height: ControlHeight.regular, action: onUndo)
                }
            }
            .fixedSize(horizontal: true, vertical: false).layoutPriority(1)
        }
        .padding(.horizontal, Space.sm).frame(height: 56)
        .accessibilityElement(children: .contain)
    }
}
