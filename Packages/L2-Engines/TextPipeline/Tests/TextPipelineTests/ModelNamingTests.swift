import XCTest
import SuperflowKernel
import SuperflowTextLexicon
import SuperflowTechDictionary
@testable import SuperflowTextPipeline

final class ModelNamingTests: XCTestCase {
    func testRequestedModelNames() async {
        let gate = TechDictionaryGate(userEntries: [], project: nil)
        let stage = LexiconStage(entries: TechDictionary.lexiconEntries(), id: "techDictionary",
            includeCanonical: false, filter: { trigger, canonical, line, context in
                gate.accepts(trigger: trigger, canonical: canonical, line: line, context: context)
            })
        let cases = [
            ("use opus five point nine", "use Claude Opus 5.9"),
            ("use opus five point five", "use Claude Opus 5.5"),
            ("use gpt six astra", "use GPT-6 Astra"),
            ("use chatgpt six sol", "use GPT-6 Sol"),
            ("use gpt luna", "use GPT Luna"),
            ("use gpt terra", "use GPT Terra"),
            ("use hugging phase", "use Hugging Face"),
            ("use s one mini", "use S1-mini"),
            ("five point nine dollars", "five point nine dollars"),
            ("the opera starts at six", "the opera starts at six"),
        ]
        for (input, expected) in cases {
            let result = await stage.apply(TranscriptDraft(text: input), context: TextContext())
            XCTAssertEqual(result.text, expected, input)
        }
    }
}
