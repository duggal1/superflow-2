import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTextPipeline

// Standalone Agent 1 runner: exercises the REAL Tier-0 pipeline on the 20
// representative corpus samples. Compiled against the already-built TextPipeline
// objects; no package build, no mock, no S1-mini (machine-throttle safe).

struct DimAssert: Decodable { let requiredAny: [[String]]; let forbidden: [String] }
struct DimsDec: Decodable { let facts, grammar, terms, format, novel: DimAssert }
struct SampleDec: Decodable {
    let id: String, tier: String, domain: String, raw: String
    let wordCount: Int
    let requiredAll: [String]
    let requiredAny: [[String]]
    let forbidden: [String]
    let dimensions: DimsDec
}
struct CorpusDec: Decodable { let samples: [SampleDec] }

func containsCI(_ haystack: String, _ needle: String) -> Bool {
    let h = haystack.lowercased(), n = needle.lowercased()
    // Word-boundary match for word/space tokens so "um" cannot match "numbers".
    let wordish = n.unicodeScalars.allSatisfy { c in
        (c.value >= 97 && c.value <= 122) || (c.value >= 48 && c.value <= 57) || c.value == 32
    }
    let numeric = n.filter { $0 != " " }.allSatisfy { $0.isNumber }
    let suffix = numeric ? "" : "(?!\\w)"
    if wordish, let rx = try? NSRegularExpression(pattern: "(?<!\\w)" + NSRegularExpression.escapedPattern(for: n) + suffix) {
        return rx.firstMatch(in: h, range: NSRange(h.startIndex..., in: h)) != nil
    }
    return h.contains(n)
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: runner <corpus.json> <out.json>\n".utf8))
    exit(2)
}
let corpusURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])
let data = try Data(contentsOf: corpusURL)
let corpus = try JSONDecoder().decode(CorpusDec.self, from: data)

// 10 short + 10 long, spread across indices (same set as the Swift test file)
let short = corpus.samples.filter { $0.tier == "short" }
let long = corpus.samples.filter { $0.tier == "long" }
let execIDs = Set(short[0..<10].enumerated().map { _ in 0 }.indices.map { short[$0 * 10].id }
                  + long[0..<10].enumerated().map { _ in 0 }.indices.map { long[$0 * 10].id })

var settings = AppSettings.default
settings.cleanupEnabled = false  // documented deterministic Tier-0 fallback
let pipeline = TextPipelineBuilder.make(settings: settings)
let context = TextContext(settings: settings)

var records: [[String: Any]] = []
for s in corpus.samples where execIDs.contains(s.id) {
    let result = await pipeline.run(s.raw, context: context)
    let out = result.text
    var dims: [String: Bool] = [:]
    let all: [(String, DimAssert)] = [
        ("facts", s.dimensions.facts), ("grammar", s.dimensions.grammar),
        ("terms", s.dimensions.terms), ("format", s.dimensions.format),
        ("novel", s.dimensions.novel)]
    for (name, a) in all {
        let req = a.requiredAny.allSatisfy { group in group.contains { containsCI(out, $0) } }
        let forb = a.forbidden.allSatisfy { !containsCI(out, $0) }
        dims[name] = req && forb
    }
    records.append([
        "id": s.id, "tier": s.tier, "domain": s.domain, "executed": true,
        "wordCount": s.wordCount, "raw": s.raw, "output": out,
        "dimensions": dims
    ])
}

let payload: [String: Any] = ["path": "Tier0-deterministic", "count": records.count, "records": records]
let json = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outURL)
FileHandle.standardOutput.write(Data("AGENT1_RUNNER_OK records=\(records.count) -> \(outURL.path)\n".utf8))
