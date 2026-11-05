import XCTest
import SuperflowKernel
@testable import SuperflowTextPipeline

final class ModelNameGrammarTests: XCTestCase {
    func testModelFamiliesAndNumericalVersions() {
        let cases: [(String, String)] = [
            ("use claude opus five point five five", "use Claude Opus 5.55"),
            ("use opus five point nine", "use Claude Opus 5.9"),
            ("claude sonnet four point five", "Claude Sonnet 4.5"),
            ("haiku five", "Claude Haiku 5"),
            ("chat gbd six", "ChatGPT 6"),
            ("gpt six", "GPT-6"),
            ("gpt 5.55", "GPT-5.55"),
            ("gemini three point five", "Gemini 3.5"),
            ("gemma three", "Gemma 3"),
            ("grok four point one", "Grok 4.1"),
            ("qwen three", "Qwen 3"),
            ("deep seek three point two", "DeepSeek 3.2"),
            ("llama four", "Llama 4"),
            ("mistral seven", "Mistral 7"),
            ("mixtral eight", "Mixtral 8"),
            ("phi four", "Phi 4"),
            ("nemotron three", "Nemotron 3"),
            ("kimi two", "Kimi 2"),
            ("g l m four", "GLM 4"),
            ("mini max two point five", "MiniMax 2.5"),
            ("command r seven", "Command R 7"),
            ("granite four", "Granite 4"),
            ("jamba two", "Jamba 2"),
            ("falcon three", "Falcon 3"),
            ("ernie five", "ERNIE 5"),
            ("nova two", "Nova 2"),
            ("perplexity sonar two", "Sonar 2"),
            ("olmo three", "OLMo 3"),
            ("d b r x two", "DBRX 2"),
            ("aya four", "Aya 4"),
            ("reka two", "Reka 2"),
            ("hunyuan three", "Hunyuan 3"),
            ("intern l m four", "InternLM 4"),
            ("entropic claude", "Anthropic claude"),
            ("enthropic claude", "Anthropic claude"),
            ("gpt six astra", "GPT-6 Astra"),
            ("gpt six sol", "GPT-6 Sol"),
            ("gpt six luna", "GPT-6 Luna"),
            ("gpt six terra", "GPT-6 Terra"),
            ("open air models", "OpenAI models"),
        ]
        XCTAssertGreaterThanOrEqual(cases.count, 30)
        for (input, expected) in cases {
            XCTAssertEqual(ModelNameNormalizer.normalize(input).text, expected, input)
        }
    }

    func testOrdinaryLanguageNeverBecomesAnAIModel() {
        for input in [
            "we got an open air concert",
            "the granite counter is gray",
            "the nova was visible at night",
            "I wrote a sonnet yesterday",
            "there was a falcon in the park",
            "the llama ate grass",
            "five point nine dollars",
            "the opera starts at six",
            "please read https://example.org/gpt",
        ] {
            XCTAssertEqual(ModelNameNormalizer.normalize(input).text, input, input)
        }
    }

    func testProtectedSegmentsAndIdempotence() {
        let original = "use opus five point five and model GPT-6"
        let first = ModelNameNormalizer.normalize(original)
        XCTAssertEqual(first.text, "use Claude Opus 5.5 and model GPT-6")
        XCTAssertEqual(ModelNameNormalizer.normalize(first.text).text, first.text)

        let protected = Protected(literals: ["opus five point five"])
        XCTAssertEqual(ModelNameNormalizer.normalize(original, protected: protected).text,
                       "use opus five point five and model GPT-6")
    }

    func testNaturalModelNamesAndProviderContext() {
        let input = "i use claude opus five point five enthropic model and gpt six astra from open air"
        let result = ModelNameNormalizer.normalize(input)
        XCTAssertEqual(result.text,
                       "i use Claude Opus 5.5 Anthropic model and GPT-6 Astra from OpenAI")
        XCTAssertTrue(result.literals.contains("GPT-6 Astra"))
        XCTAssertTrue(result.literals.contains("Claude Opus 5.5"))
    }

    func testPipelineRunsGrammarBeforeTechDictionary() {
        let pipeline = TextPipelineBuilder.make(settings: .default)
        XCTAssertEqual(Array(pipeline.stageIDs.suffix(2)), ["modelNames", "techDictionary"])
    }
}
