import Foundation
import SuperflowKernel
import SuperflowPorts

struct VoiceInsertionDirective {
    var text: String
    var opening: VoiceOpeningShortcut?
    var submit = false
}

extension SessionEngine {
    func prepareInsertion(_ assembled: String, session: SessionRecord) async -> VoiceInsertionDirective {
        guard !commandCapture else { return VoiceInsertionDirective(text: assembled) }
        let formatted = await pipeline.formatForInsertion(assembled, context: TextContext(
            settings: settings, project: project, activeAppBundleID: session.frontmostBundleID))
        var directive = VoiceInsertionDirective(text: formatted)
        guard settings.commandsEnabled, nextIndex > 0,
              let last = try? await repository.segmentForProcessing(session: session.id, index: nextIndex - 1)
        else { return directive }
        if nextIndex == 1, let opening = VoiceOpeningShortcut.parse(last.rawText),
           VoiceOpeningShortcut.parse(formatted) == opening {
            directive.opening = opening
        } else if VoiceSendSuffix.endsWithCommandWords(last.rawText),
                  VoiceSendSuffix.isExplicit(last.rawText),
                  VoiceSendSuffix.isExplicit(formatted),
                  let body = VoiceSendSuffix.removing(formatted) {
            directive.text = body
            directive.submit = true
        }
        return directive
    }

    func insertDirective(_ directive: VoiceInsertionDirective, expectedBundleID: String?) async throws -> InsertionOutcome {
        let text = directive.text
        if directive.submit {
            let result = try await withDeadline(insertionDeadline, label: "verified message insertion") { [inserter] in
                try await inserter.insertAndSubmit(text, expectedBundleID: expectedBundleID)
            }
            if !result.submitted { emit(.notice("Message not submitted automatically. Review and send it manually.")) }
            return result.insertion
        }
        return try await withDeadline(insertionDeadline, label: "insertion") { [inserter] in
            try await inserter.insert(text, strategy: .auto)
        }
    }
}
