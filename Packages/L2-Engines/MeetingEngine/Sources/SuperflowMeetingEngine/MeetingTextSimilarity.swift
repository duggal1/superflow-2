import SuperflowKernel

enum MeetingTextSimilarity {
    static func ratio(_ first: String, _ second: String) -> Double {
        let firstWords = Set(Tokenizer.words(in: first.lowercased())
            .map { $0.trimmingCharacters(in: .punctuationCharacters) })
        let secondWords = Set(Tokenizer.words(in: second.lowercased())
            .map { $0.trimmingCharacters(in: .punctuationCharacters) })
        let union = firstWords.union(secondWords).filter { !$0.isEmpty }
        guard !union.isEmpty else { return 0 }
        let intersection = firstWords.intersection(secondWords).filter { !$0.isEmpty }
        return Double(intersection.count) / Double(union.count)
    }
}
