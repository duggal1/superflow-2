import Testing
import SuperflowKernel
@testable import SuperflowAudioCpp

@Test func dictationFlushesBoundedSpeechAndPrefersSentenceEnds() {
    let short = Int64(sampleRate * 5)
    let normal = Int64(sampleRate * 6)
    let limit = Int64(sampleRate * 8)
    #expect(!DictationBoundary.shouldCommit("The test finished.", samples: short))
    #expect(DictationBoundary.shouldCommit("The test finished.", samples: normal))
    #expect(!DictationBoundary.shouldCommit("Call Dr.", samples: normal))
    #expect(!DictationBoundary.shouldCommit("The test is still running", samples: limit - 1))
    #expect(DictationBoundary.shouldCommit("The test is still running", samples: limit))
    #expect(!DictationBoundary.shouldCommit("", samples: limit))
}
