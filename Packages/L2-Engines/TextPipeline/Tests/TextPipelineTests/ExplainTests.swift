import XCTest
import SuperflowKernel
import SuperflowPorts
import SuperflowTextLexicon
import SuperflowTextPipeline

private struct ReplaceStage: SuperflowPorts.TextStage {
    let id = "replace"
    let from: String
    let to: String

    func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        var out = draft
        out.text = draft.text.replacingOccurrences(of: from, with: to)
        return out
    }
}

private struct ShortcutStage: SuperflowPorts.TextStage {
    let id = "shortcut"

    func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        var out = draft
        out.text = "expanded"
        out.shortCircuit = true
        return out
    }
}

private struct EraserStage: SuperflowPorts.TextStage {
    let id = "eraser"

    func apply(_ draft: TranscriptDraft, context: TextContext) async -> TranscriptDraft {
        var out = draft
        out.text = ""
        return out
    }
}

final class ExplainTests: XCTestCase {
    private func slice(_ text: String, _ span: TextSpan) -> String {
        (text as NSString).substring(with: span.nsRange)
    }

    func testExplainReportsAReplacement() async {
        let pipeline = TextPipeline(stages: [ReplaceStage(from: "foo", to: "bar")])
        let explanation = await pipeline.explain("a foo b", context: TextContext())

        XCTAssertEqual(explanation.result.text, "a bar b")
        XCTAssertEqual(explanation.stages.count, 1)
        let edit = try? XCTUnwrap(explanation.edits.first)
        XCTAssertEqual(edit?.stageID, "replace")
        XCTAssertEqual(edit?.ruleID, "replace")
        XCTAssertEqual(edit?.kind, .replace)
        if let edit {
            XCTAssertEqual(slice("a foo b", edit.input), "foo")
            XCTAssertEqual(slice("a bar b", edit.output), "bar")
        }
    }

    func testExplainReportsAnInsertion() async {
        let pipeline = TextPipeline(stages: [ReplaceStage(from: "alpha beta", to: "alpha inserted beta")])
        let explanation = await pipeline.explain("alpha beta", context: TextContext())

        let edit = try? XCTUnwrap(explanation.edits.first)
        XCTAssertEqual(edit?.kind, .insert)
        XCTAssertEqual(edit?.input.length, 0)
        if let edit {
            XCTAssertEqual(slice("alpha inserted beta", edit.output), " inserted")
        }
    }

    func testExplainReportsADeletion() async {
        let pipeline = TextPipeline(stages: [ReplaceStage(from: "alpha inserted beta", to: "alpha beta")])
        let explanation = await pipeline.explain("alpha inserted beta", context: TextContext())

        let edit = try? XCTUnwrap(explanation.edits.first)
        XCTAssertEqual(edit?.kind, .delete)
        XCTAssertEqual(edit?.output.length, 0)
        if let edit {
            XCTAssertEqual(slice("alpha inserted beta", edit.input), " inserted")
        }
    }

    func testExplainNamesTheLexiconEntry() async {
        let entry = LexiconEntry(id: "lex-nextjs", kind: .term, triggers: ["next js"], canonical: "Next.js")
        let pipeline = TextPipeline(stages: [LexiconStage(entries: [entry])])
        let input = "i use next js daily"
        let explanation = await pipeline.explain(input, context: TextContext())

        XCTAssertEqual(explanation.result.text, "i use Next.js daily")
        let edit = try? XCTUnwrap(explanation.edits.first)
        XCTAssertEqual(edit?.stageID, "lexicon")
        XCTAssertEqual(edit?.ruleID, "lex-nextjs")
        if let edit {
            XCTAssertEqual(slice(input, edit.input), "next js")
            XCTAssertEqual(slice(explanation.result.text, edit.output), "Next.js")
        }
    }

    func testExplainStopsAtAShortCircuit() async {
        let pipeline = TextPipeline(stages: [
            ReplaceStage(from: "a", to: "b"),
            ShortcutStage(),
            ReplaceStage(from: "expanded", to: "never"),
        ])
        let explanation = await pipeline.explain("a", context: TextContext())

        XCTAssertEqual(explanation.result.shortCircuitedBy, "shortcut")
        XCTAssertEqual(explanation.result.text, "expanded")
        XCTAssertEqual(explanation.stages.map(\.stageID), ["replace", "shortcut"])
    }

    func testExplainRevertsAnErasedDraft() async {
        let pipeline = TextPipeline(stages: [EraserStage()])
        let explanation = await pipeline.explain("keep me", context: TextContext())

        XCTAssertEqual(explanation.result.text, "keep me")
        XCTAssertTrue(explanation.edits.isEmpty)
        XCTAssertTrue(explanation.result.draft.diagnostics.contains { $0.stage == "eraser" })
    }

    func testExplainIsDeterministic() async {
        let entry = LexiconEntry(id: "lex-superflow", kind: .correction,
                                 triggers: ["super flow"], canonical: "Superflow")
        let pipeline = TextPipeline(stages: [LexiconStage(entries: [entry])])
        let input = "super flow ships super flow twice"

        let first = await pipeline.explain(input, context: TextContext())
        let second = await pipeline.explain(input, context: TextContext())

        XCTAssertEqual(first.result.text, second.result.text)
        XCTAssertEqual(first.edits, second.edits)
        XCTAssertEqual(first.edits.count, 2)
        XCTAssertEqual(Set(first.edits.map(\.ruleID)), ["lex-superflow"])
    }

    func testExplainMatchesRunText() async {
        let pipeline = TextPipeline(stages: [
            ReplaceStage(from: "next js", to: "Next.js"),
            ReplaceStage(from: "two hundred", to: "200"),
        ])
        let input = "next js costs two hundred"
        let run = await pipeline.run(input, context: TextContext())
        let explained = await pipeline.explain(input, context: TextContext())

        XCTAssertEqual(run.text, explained.result.text)
        XCTAssertEqual(explained.result.timings.map(\.id), run.timings.map(\.id))
    }
}
