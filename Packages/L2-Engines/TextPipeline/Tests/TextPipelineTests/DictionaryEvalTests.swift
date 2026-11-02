import XCTest
import SuperflowKernel
import SuperflowTextLexicon
import SuperflowTechDictionary
@testable import SuperflowTextPipeline

final class DictionaryEvalTests: XCTestCase {
    private func stage() -> LexiconStage {
        let gate = TechDictionaryGate(userEntries: [], project: nil)
        return LexiconStage(entries: TechDictionary.lexiconEntries(),
                            id: "techDictionary",
                            includeCanonical: false,
                            filter: { trigger, canonical, line, context in
                                gate.accepts(trigger: trigger, canonical: canonical,
                                             line: line, context: context)
                            })
    }

    private func lines(_ name: String) throws -> [String] {
        guard let url = Bundle.module.url(forResource: name, withExtension: "txt",
                                          subdirectory: "Resources") else {
            throw XCTSkip("missing \(name).txt")
        }
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    func testEverydaySentencesAreUntouched() async throws {
        let stage = stage()
        var failures: [String] = []
        for line in try lines("negatives") {
            let output = await stage.apply(TranscriptDraft(text: line),
                                           context: TextContext()).text
            if output != line { failures.append("\(line)  ->  \(output)") }
        }
        XCTAssertTrue(failures.isEmpty,
                      "false positives:\n" + failures.prefix(20).joined(separator: "\n"))
    }

    func testDeveloperSentencesReplaceAsExpected() async throws {
        let stage = stage()
        var failures: [String] = []
        for row in try lines("positives") {
            let parts = row.components(separatedBy: "\t")
            guard parts.count == 2 else { continue }
            let output = await stage.apply(TranscriptDraft(text: parts[0]),
                                           context: TextContext()).text
            if output != parts[1] {
                failures.append("\(parts[0])  ->  \(output)  (expected \(parts[1]))")
            }
        }
        XCTAssertTrue(failures.isEmpty,
                      "missed replacements:\n" + failures.prefix(20).joined(separator: "\n"))
    }
}
