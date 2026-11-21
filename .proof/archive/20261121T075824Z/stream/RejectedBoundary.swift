import SuperflowKernel

enum DictationBoundary {
    static func shouldCommit(_ text: String, samples: Int64) -> Bool {
        guard samples >= Int64(sampleRate * 6), !text.isEmpty else { return false }
        return samples >= Int64(sampleRate * 8) || SentenceSplitter.endsSentence(text)
    }
}
