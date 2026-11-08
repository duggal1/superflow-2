import Foundation
import SuperflowKernel

/// Versioned AI-era vocabulary (F12), kept as data so terms can be added
/// without a code change or app release. Loaded once per process; a missing
/// or invalid resource yields an empty lexicon. NEVER exposed to ASR or
/// the cleanup model prompt; the resolver applies it deterministically.
public enum AIEraLexicon {
    public struct Term: Sendable, Codable, Equatable {
        public let canonical: String
        public let category: String
        public let meaning: String
        public let casing: String
        public let boost: Int
        public let variants: [String]
        public init(canonical: String, category: String, meaning: String, casing: String, boost: Int, variants: [String]) {
            self.canonical = canonical
            self.category = category
            self.meaning = meaning
            self.casing = casing
            self.boost = boost
            self.variants = variants
        }
    }

    private struct File: Decodable {
        let version: Int
        let terms: [Term]
    }

    public static let version: Int = load().0
    public static let terms: [Term] = load().1

    /// Canonical -> term, plus variant -> canonical lookup for the resolver.
    /// Longest normalized variant wins during resolution.
    public static let resolutions: [(variant: String, canonical: String, casing: String)] = {
        var list: [(String, String, String)] = []
        for term in terms {
            list.append((term.canonical, term.canonical, term.casing))
            for variant in term.variants {
                list.append((variant, term.canonical, term.casing))
            }
        }
        return list
    }()

    private static func load() -> (Int, [Term]) {
        guard let url = Bundle.module.url(forResource: "ai-era-lexicon", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data),
              file.version == 1 else { return (0, []) }
        return (file.version, file.terms)
    }
}
