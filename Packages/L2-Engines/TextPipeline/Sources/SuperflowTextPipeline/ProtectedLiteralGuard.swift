import SuperflowKernel

public enum ProtectedLiteralGuard {
    public static func missingCount(in cleaned: String, protectedFrom source: TextDraft) -> Int {
        var available: [String: Int] = [:]
        for w in Word.tokenize(cleaned) { available[w.literal, default: 0] += 1 }
        var missing = 0
        for w in source.words where w.isProtected && !w.core.isEmpty {
            if let c = available[w.literal], c > 0 { available[w.literal] = c - 1 } else { missing += 1 }
        }
        return missing
    }
}
