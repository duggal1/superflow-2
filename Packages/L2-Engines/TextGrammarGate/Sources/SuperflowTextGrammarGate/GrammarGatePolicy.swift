import Foundation

/// Data-driven policy for Harper. Categories ship disabled until they clear
/// 98 percent precision on the golden corpus (PLAN section 11).
public struct GrammarGatePolicy: Sendable, Equatable, Codable {
    public var enabled: Bool
    public var allowedKinds: [String]
    public var maxEditRatio: Double
    public var timeCapMs: Int
    public var minimumPrecision: Double

    public init(enabled: Bool = true,
                allowedKinds: [String] = GrammarGatePolicy.shippingKinds,
                maxEditRatio: Double = 0.03,
                timeCapMs: Int = 50,
                minimumPrecision: Double = 0.98) {
        self.enabled = enabled
        self.allowedKinds = allowedKinds
        self.maxEditRatio = max(0, maxEditRatio)
        self.timeCapMs = max(1, timeCapMs)
        self.minimumPrecision = min(1, max(0, minimumPrecision))
    }

    /// Only categories measured at 98 percent precision or better ship on.
    /// `aOrAn` is a rule-level classification: harper-core 2.13 reports its
    /// indefinite-article rule as `Miscellaneous`, which the adapter
    /// reclassifies before the gate sees it.
    public static let shippingKinds = ["Spelling", "Agreement", "Repetition", "aOrAn"]

    public static let `default` = GrammarGatePolicy()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GrammarGatePolicy()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        allowedKinds = try c.decodeIfPresent([String].self, forKey: .allowedKinds) ?? d.allowedKinds
        maxEditRatio = try c.decodeIfPresent(Double.self, forKey: .maxEditRatio) ?? d.maxEditRatio
        timeCapMs = try c.decodeIfPresent(Int.self, forKey: .timeCapMs) ?? d.timeCapMs
        minimumPrecision = try c.decodeIfPresent(Double.self, forKey: .minimumPrecision) ?? d.minimumPrecision
    }

    /// Loads the pinned resource; falls back to the in-code default if the resource is missing.
    public static func loadBundled() -> GrammarGatePolicy {
        guard let url = Bundle.module.url(forResource: "grammar-gate-policy", withExtension: "json",
                                          subdirectory: "Resources"),
              let data = try? Data(contentsOf: url),
              let policy = try? JSONDecoder().decode(GrammarGatePolicy.self, from: data)
        else { return .default }
        return policy
    }

    public func allows(kind: String) -> Bool {
        let key = Self.canonical(kind)
        guard !key.isEmpty else { return false }
        return allowedKinds.contains { Self.canonical($0) == key }
    }

    /// Applies a precision report: a category ships only when it has evidence
    /// and clears `minimumPrecision`. Categories absent from the report are
    /// disabled, so a new rule never ships on hope.
    public func qualified(by report: GrammarCategoryReport) -> GrammarGatePolicy {
        var copy = self
        copy.allowedKinds = allowedKinds.filter { kind in
            guard let category = report.category(kind) else { return false }
            return category.proposed > 0 && category.precision >= minimumPrecision
        }
        return copy
    }

    /// "Repeated Words", "repetition" and "repeatedWords" all compare equal.
    /// harper-core 2.13 uses `Repetition`; older notes used `RepeatedWords`.
    /// The article rule has shipped as "AnA", "a/an" and "aOrAn".
    public static func canonical(_ s: String) -> String {
        let key = s.lowercased().filter { $0.isLetter || $0.isNumber }
        switch key {
        case "aan", "ana", "aoran": return "aoran"
        case "repeatedword", "repeatedwords", "repetition": return "repetition"
        default: return key
        }
    }

    /// Display name used in diagnostics and reports.
    public static func displayName(_ kind: String) -> String {
        switch canonical(kind) {
        case "spelling": return "Spelling"
        case "agreement": return "Agreement"
        case "repetition": return "Repetition"
        case "aoran": return "aOrAn"
        default: return kind
        }
    }
}
